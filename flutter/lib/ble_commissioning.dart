/// Matter BLE 커미셔닝 화면 — Plan B
///
/// BLE 스캔 UI + BLE relay를 통한 matterjs 커미셔닝.
/// 프로토콜(BTP/PASE/WiFi/CASE)은 matterjs-server가 전부 처리.
/// Flutter는 BLE 바이트를 WS로 중계만 한다.
///
/// 흐름:
/// 1. BLE relay 시작 (matterjs-server :5581 연결)
/// 2. 사용자가 WiFi credentials 입력
/// 3. Go 서버에 commission 요청 (network_only=false)
/// 4. matterjs가 BLE scan/connect/BTP/PASE/WiFi/CASE 전부 수행
/// 5. Flutter는 BLE 바이트 relay만 담당
library;

import 'dart:async';
import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_relay.dart';

/// BLE 커미셔닝 화면
class BleCommissioningScreen extends StatefulWidget {
  final String serverUrl;
  const BleCommissioningScreen({super.key, required this.serverUrl});

  @override
  State<BleCommissioningScreen> createState() => _BleCommissioningScreenState();
}

class _BleCommissioningScreenState extends State<BleCommissioningScreen> {
  String _status = '초기화 중...';
  bool _commissioning = false;
  bool _relayConnected = false;
  BleRelay? _relay;

  @override
  void initState() {
    super.initState();
    _startRelay();
  }

  @override
  void dispose() {
    _relay?.disconnect();
    super.dispose();
  }

  /// BLE 권한 확인 (Android 12+)
  Future<bool> _checkBlePermissions() async {
    if (!Platform.isAndroid) return true;
    // FlutterBluePlus가 내부적으로 권한 체크/요청 수행
    // turnOn()이 BLE가 꺼져있을 때 시스템 다이얼로그를 띄움
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      setState(() => _status = '⚠️ 블루투스가 꺼져있습니다');
      try {
        await FlutterBluePlus.turnOn();
        // 켜질 때까지 최대 5초 대기
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

  /// BLE relay 시작 — matterjs-server의 BLE WS에 연결
  Future<void> _startRelay() async {
    setState(() {
      _status = 'BLE 권한 확인 중...';
      _relayConnected = false;
    });

    // 1. BLE 권한 확인
    if (!await _checkBlePermissions()) return;

    // serverUrl에서 호스트 추출 → BLE WS 포트로 연결
    final serverUri = Uri.parse(widget.serverUrl);
    final bleWsUrl = 'ws://${serverUri.host}:5581';

    // 2. 이전 relay 정리 (2회 연속 커미셔닝 대응)
    await _relay?.disconnect();

    _relay = BleRelay(
      wsUrl: bleWsUrl,
      onStatus: (status) {
        if (mounted) setState(() => _status = status);
      },
    );

    try {
      await _relay!.connect();
      setState(() {
        _status = '✅ BLE relay 연결됨 — 커미셔닝 준비 완료';
        _relayConnected = true;
      });
    } catch (e) {
      setState(() {
        _status = '❌ BLE relay 연결 실패\n$e';
        _relayConnected = false;
      });
    }
  }

  /// 커미셔닝 시작 — WiFi + pairing code 입력 → Go 서버 요청
  Future<void> _startCommissioning() async {
    // BLE relay가 연결되어 있지 않으면 재연결 시도
    if (!_relayConnected) {
      await _startRelay();
      if (!_relayConnected) return;
    }

    // 1. WiFi + Pairing code 입력
    final info = await _showCommissionDialog();
    if (info == null) return;

    setState(() {
      _commissioning = true;
      _status = info.isThread ? '🔄 Thread 커미셔닝 준비 중...' : '🔄 WiFi 정보 설정 중...';
    });

    try {
      // 2. WiFi credentials — Thread일 때는 스킵
      if (!info.isThread) {
        await _setWifiCredentials(info.ssid, info.password);
      }
      setState(() => _status = '🔄 커미셔닝 요청 중...');

      // 3. Commission 요청 (network_only=false → matterjs가 BLE 커미셔닝)
      await _requestCommission(info.pairingCode);

      final networkType = info.isThread ? 'Thread' : 'WiFi';
      setState(() => _status = '⏳ 커미셔닝 진행 중...\n'
          'BLE 스캔 → BTP 핸드셰이크 → PASE 인증 → $networkType 설정\n'
          '(60~120초 소요, 디바이스가 페어링 모드인지 확인)');

      // SSE로 커미셔닝 결과 추적
      _listenCommissionResult(info.pairingCode, info.isThread ? 'Thread' : info.ssid);
    } catch (e) {
      setState(() {
        _commissioning = false;
        _status = '❌ 커미셔닝 실패: $e';
      });
    }
  }

  /// SSE로 커미셔닝 결과 추적
  void _listenCommissionResult(String code, String ssid) {
    final client = HttpClient();
    final sseUri = Uri.parse('${widget.serverUrl}/api/events');

    client.getUrl(sseUri).then((request) {
      return request.close();
    }).then((response) {
      response
          .transform(const SystemEncoding().decoder)
          .listen((chunk) {
        // SSE 파싱: "data: {...}\n\n"
        for (final line in chunk.split('\n')) {
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6);
          if (data.contains('device_added') || data.contains('commission_result')) {
            if (mounted) {
              setState(() {
                _status = '✅ 커미셔닝 성공! 디바이스가 추가되었습니다.';
                _commissioning = false;
              });
              _showResultDialog('✅ 커미셔닝 완료', '디바이스가 네트워크에 추가되었습니다.\nWiFi: $ssid\n\n뒤로 돌아가면 대시보드에서 확인할 수 있습니다.');
            }
          } else if (data.contains('commission_error')) {
            if (mounted) {
              setState(() {
                _status = '❌ 커미셔닝 실패 — 재시도하려면 아래 버튼을 누르세요';
                _commissioning = false;
              });
              _showResultDialog('❌ 커미셔닝 실패',
                  '확인 사항:\n'
                  '• 디바이스가 페어링 모드인지\n'
                  '• Pairing Code가 맞는지\n'
                  '• WiFi SSID/비밀번호가 맞는지\n'
                  '• 디바이스가 BLE 범위 내에 있는지\n\n'
                  'Code: $code');
            }
          }
        }
      });
    }).catchError((e) {
      print('[COMM] SSE connection failed: $e');
    });
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
        // WiFi SSID+PW 자동 로드 (1회만)
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
              // Thread/WiFi 선택
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
              // WiFi 모드일 때만 SSID/PW 입력
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
                  decoration: const InputDecoration(
                    labelText: 'WiFi 비밀번호',
                  ),
                  obscureText: true,
                ),
              ] else ...[
                const SizedBox(height: 12),
                Text(
                  'Thread 디바이스는 WiFi 정보가 필요 없습니다.\nOTBR에서 자동으로 Thread Dataset이 주입됩니다.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ],
              // Pairing Code — 항상 표시
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
              final code =
                  codeController.text.replaceAll(' ', '').replaceAll('-', '');
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

  /// Go 서버에 WiFi credentials 설정
  Future<void> _setWifiCredentials(String ssid, String password) async {
    setState(() => _status = 'WiFi credentials 설정 중...');
    final client = HttpClient();
    final request = await client.postUrl(
      Uri.parse('${widget.serverUrl}/api/wifi-credentials'),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'ssid': ssid,
      'password': password,
    }));
    final response = await request.close();
    await response.drain();
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('WiFi credentials 설정 실패: HTTP ${response.statusCode}');
    }
  }

  /// Go 서버에 commission 요청 (network_only=false)
  Future<void> _requestCommission(String code) async {
    setState(() => _status = 'Commission 요청 중...');
    final client = HttpClient();
    final request = await client.postUrl(
      Uri.parse('${widget.serverUrl}/api/commission'),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'code': code,
      'network_only': false, // B안: matterjs가 BLE 커미셔닝 수행
    }));
    final response = await request.close();
    await response.drain();

    if (response.statusCode != 200 && response.statusCode != 202) {
      throw Exception('Commission 요청 실패: HTTP ${response.statusCode}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Matter 디바이스 페어링'),
      ),
      body: Column(
        children: [
          // 상태 바
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: _commissioning
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                if (_commissioning) ...[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(_status, style: const TextStyle(fontSize: 14)),
                ),
              ],
            ),
          ),

          // 안내
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _relayConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                    size: 64,
                    color: _relayConnected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Matter 디바이스를 페어링 모드로 설정한 후\n'
                      '아래 버튼을 눌러 커미셔닝을 시작하세요.\n\n'
                      'BLE 스캔 → BTP 핸드셰이크 → PASE 인증 →\n'
                      'WiFi 전달 → on-network 커미셔닝까지\n'
                      '자동으로 진행됩니다.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  // BLE relay 재연결 버튼 (연결 실패 시)
                  if (!_relayConnected && !_commissioning) ...[
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _startRelay,
                      icon: const Icon(Icons.refresh),
                      label: const Text('BLE relay 재연결'),
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
