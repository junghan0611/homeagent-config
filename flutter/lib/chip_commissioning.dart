/// Matter BLE 커미셔닝 화면 — CHIP SDK AAR 경로
///
/// CHIP SDK Android AAR이 Android BLE HAL을 직접 사용해 커미셔닝.
/// BLE relay(matterjs WS) 불필요 — CHIP SDK가 전부 처리.
///
/// Multi-admin 흐름:
/// 1. CHIP SDK로 BLE 커미셔닝 (디바이스를 CHIP fabric에 추가)
/// 2. openCommissioningWindow → setupPinCode 획득
/// 3. Go 서버에 handoff 요청 → python-matter-server commission_on_network(pin)
/// 4. python-matter-server fabric에 추가 완료 (SSE로 확인)
/// 5. CHIP fabric에서 제거
library;

import 'dart:async';
import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'chip_controller.dart';

/// BLE 커미셔닝 화면
class ChipCommissioningScreen extends StatefulWidget {
  final String serverUrl;
  const ChipCommissioningScreen({super.key, required this.serverUrl});

  @override
  State<ChipCommissioningScreen> createState() => _ChipCommissioningScreenState();
}

class _ChipCommissioningScreenState extends State<ChipCommissioningScreen> {
  String _status = '초기화 중...';
  bool _commissioning = false;
  bool _chipReady = false;
  final ChipController _chip = ChipController();
  int? _lastCommissionedNodeId;

  @override
  void initState() {
    super.initState();
    _initChip();
  }

  /// CHIP SDK 초기화
  Future<void> _initChip() async {
    setState(() => _status = 'CHIP SDK 초기화 중...');

    if (!await _checkBlePermissions()) return;

    try {
      await _chip.init();
      await _loadThreadDataset();
      setState(() {
        _status = '✅ 준비 완료 — 디바이스를 추가할 수 있습니다';
        _chipReady = true;
      });
    } catch (e) {
      setState(() => _status = '❌ CHIP SDK 초기화 실패\n$e');
    }
  }

  /// BLE 권한 확인 (Android 12+)
  Future<bool> _checkBlePermissions() async {
    if (!Platform.isAndroid) return true;
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      setState(() => _status = '⚠️ 블루투스가 꺼져있습니다');
      try {
        await FlutterBluePlus.turnOn();
        await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 5));
        return true;
      } catch (_) {
        setState(() => _status = '❌ 블루투스를 켜야 커미셔닝이 가능합니다.\n설정에서 블루투스를 활성화하세요.');
        return false;
      }
    }
    return true;
  }

  /// Go 서버에서 Thread dataset 가져와서 CHIP SDK에 설정
  Future<void> _loadThreadDataset() async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(
        Uri.parse('${widget.serverUrl}/api/thread-dataset'),
      );
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(const SystemEncoding().decoder).join();
        final data = jsonDecode(body);
        final dataset = data['dataset'] as String?;
        if (dataset != null && dataset.isNotEmpty) {
          await _chip.setThreadDataset(dataset);
        }
      }
    } catch (e) {
      debugPrint('[CHIP] Thread dataset load failed (non-fatal): $e');
    }
  }

  /// 커미셔닝 시작
  Future<void> _startCommissioning() async {
    if (!_chipReady) {
      await _initChip();
      if (!_chipReady) return;
    }

    final info = await _showCommissionDialog();
    if (info == null) return;

    setState(() {
      _commissioning = true;
      _status = '🔄 커미셔닝 준비 중...';
    });

    try {
      // 1. WiFi credentials 설정 (Thread일 때는 스킵)
      if (!info.isThread) {
        setState(() => _status = '🔄 WiFi 정보 설정 중...');
        await _chip.setWifiCredentials(info.ssid, info.password);
        await _setServerWifiCredentials(info.ssid, info.password);
      }

      // 2. CHIP SDK BLE 커미셔닝
      setState(() => _status = '⏳ BLE 커미셔닝 진행 중...\n'
          'BLE 스캔 → BTP → PASE → ${info.isThread ? "Thread" : "WiFi"} 설정\n'
          '(60~120초 소요)');

      final nodeId = DateTime.now().millisecondsSinceEpoch % 100000 + 1;
      final commResult = await _chip.pairDevice(nodeId, info.pairingCode);

      if (!commResult.success) {
        throw Exception('BLE 커미셔닝 실패');
      }
      _lastCommissionedNodeId = commResult.nodeId;

      // 3. Multi-admin: openCommissioningWindow
      setState(() => _status = '🔄 서버 핸드오프 준비 중...');
      final window = await _chip.openCommissioningWindow(commResult.nodeId);

      // 4. Go 서버에 핸드오프 요청 (비동기 — 202 즉시 반환, SSE로 추적)
      await _requestHandoff(window.setupPinCode);

      setState(() => _status = '⏳ 서버에서 디바이스 등록 중...\n(60~120초 소요)');

      // 5. SSE로 결과 추적
      final networkType = info.isThread ? 'Thread' : 'WiFi (${info.ssid})';
      _listenHandoffResult(networkType);
    } catch (e) {
      setState(() {
        _commissioning = false;
        _status = '❌ 커미셔닝 실패: $e';
      });
    }
  }

  /// SSE로 handoff 결과 추적
  void _listenHandoffResult(String networkType) {
    final client = HttpClient();
    final sseUri = Uri.parse('${widget.serverUrl}/api/events');

    client.getUrl(sseUri).then((request) {
      return request.close();
    }).then((response) {
      response
          .transform(const SystemEncoding().decoder)
          .listen((chunk) {
        for (final line in chunk.split('\n')) {
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6);
          if (data.contains('device_added') || data.contains('node_added')) {
            if (mounted) {
              setState(() {
                _status = '✅ 커미셔닝 완료!';
                _commissioning = false;
              });
              _showResultDialog('✅ 커미셔닝 완료',
                  '디바이스가 $networkType 네트워크에 추가되었습니다.\n\n'
                  '뒤로 돌아가면 대시보드에서 확인할 수 있습니다.');
              // CHIP fabric에서 제거 (python-matter-server가 관리)
              _cleanupChipFabric();
            }
          } else if (data.contains('commission_error')) {
            if (mounted) {
              setState(() {
                _status = '❌ 서버 핸드오프 실패 — 재시도하세요';
                _commissioning = false;
              });
            }
          }
        }
      });
    }).catchError((e) {
      debugPrint('[COMM] SSE connection failed: $e');
    });
  }

  /// CHIP fabric에서 디바이스 제거 (python-matter-server가 이제 관리)
  Future<void> _cleanupChipFabric() async {
    final nodeId = _lastCommissionedNodeId;
    if (nodeId == null) return;
    try {
      await _chip.unpairDevice(nodeId);
    } catch (_) {
      // 제거 실패해도 큰 문제 아님
    }
    _lastCommissionedNodeId = null;
  }

  /// Go 서버에 multi-admin 핸드오프 요청 (비동기 — 202 반환)
  Future<void> _requestHandoff(int setupPinCode) async {
    final client = HttpClient();
    final request = await client.postUrl(
      Uri.parse('${widget.serverUrl}/api/commission-on-network'),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'setup_pin_code': setupPinCode}));
    final response = await request.close();
    await response.drain();

    if (response.statusCode != 200 && response.statusCode != 202) {
      throw Exception('핸드오프 요청 실패: HTTP ${response.statusCode}');
    }
  }

  /// Go 서버에 WiFi credentials 설정 (python-matter-server용)
  Future<void> _setServerWifiCredentials(String ssid, String password) async {
    final client = HttpClient();
    final request = await client.postUrl(
      Uri.parse('${widget.serverUrl}/api/wifi-credentials'),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'ssid': ssid, 'password': password}));
    final response = await request.close();
    await response.drain();
  }

  void _showResultDialog(String title, String content) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  /// WiFi/Thread + Pairing Code 입력 다이얼로그
  Future<({String pairingCode, String ssid, String password, bool isThread})?>
      _showCommissionDialog() async {
    final codeController = TextEditingController();
    final ssidController = TextEditingController();
    final pwController = TextEditingController();
    bool isThread = false;
    bool ssidLoaded = false;
    bool wifiAutoDetected = false;

    return showDialog<({String pairingCode, String ssid, String password, bool isThread})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
        if (!ssidLoaded) {
          ssidLoaded = true;
          () async {
            try {
              final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
              final request = await client.getUrl(Uri.parse('${widget.serverUrl}/api/wifi-info'));
              final response = await request.close();
              final body = await response.transform(const SystemEncoding().decoder).join();
              final data = jsonDecode(body);
              setDialogState(() {
                if (data['ssid'] != null && (data['ssid'] as String).isNotEmpty) {
                  ssidController.text = data['ssid'];
                }
                if (data['password'] != null && (data['password'] as String).isNotEmpty) {
                  pwController.text = data['password'];
                }
                wifiAutoDetected = data['auto'] == true;
              });
            } catch (_) {}
          }();
        }
        return AlertDialog(
        title: const Text('Matter 디바이스 페어링'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.wifi),
                      label: const Text('WiFi'),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: !isThread ? Theme.of(ctx).colorScheme.primaryContainer : null,
                      ),
                      onPressed: () => setDialogState(() => isThread = false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.cable),
                      label: const Text('Thread'),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: isThread ? Theme.of(ctx).colorScheme.primaryContainer : null,
                      ),
                      onPressed: () => setDialogState(() => isThread = true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!isThread) ...[
                if (wifiAutoDetected) ...[
                  const SizedBox(height: 8),
                  Chip(
                    avatar: const Icon(Icons.check_circle, color: Colors.green, size: 16),
                    label: Text('WiFi 자동 감지됨: ${ssidController.text}'),
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: ssidController,
                  decoration: InputDecoration(
                    labelText: 'WiFi SSID',
                    suffixIcon: ssidController.text.isNotEmpty
                        ? const Icon(Icons.wifi, color: Colors.green, size: 20)
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: pwController,
                  decoration: const InputDecoration(labelText: 'WiFi 비밀번호'),
                  obscureText: true,
                ),
              ] else ...[
                const SizedBox(height: 12),
                Text(
                  'Thread 디바이스는 WiFi 정보가 필요 없습니다.\nOTBR에서 자동으로 Thread Dataset이 주입됩니다.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: codeController,
                decoration: const InputDecoration(
                  labelText: '페어링 코드',
                  hintText: '숫자만 입력 (예: 05641540754)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              final code = codeController.text.replaceAll(' ', '').replaceAll('-', '');
              final needsWifi = !isThread;
              if (code.isNotEmpty && (!needsWifi || ssidController.text.isNotEmpty)) {
                Navigator.pop(ctx, (
                  pairingCode: code,
                  ssid: ssidController.text,
                  password: pwController.text,
                  isThread: isThread,
                ));
              }
            },
            child: const Text('커미셔닝 시작'),
          ),
        ],
      );
    }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Matter 디바이스 페어링')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: _commissioning
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                if (_commissioning) ...[
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 12),
                ],
                Expanded(child: Text(_status, style: const TextStyle(fontSize: 14))),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _chipReady ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                    size: 64,
                    color: _chipReady
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Matter 디바이스를 페어링 모드로 설정한 후\n'
                      '아래 버튼을 눌러 커미셔닝을 시작하세요.\n\n'
                      'CHIP SDK가 BLE로 직접 커미셔닝한 뒤\n'
                      '서버에 자동으로 핸드오프합니다.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (!_chipReady && !_commissioning) ...[
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _initChip,
                      icon: const Icon(Icons.refresh),
                      label: const Text('재초기화'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _commissioning ? null : _startCommissioning,
        icon: Icon(_commissioning ? Icons.hourglass_top : Icons.add_link),
        label: Text(_commissioning ? '진행 중...' : '디바이스 추가'),
      ),
    );
  }
}
