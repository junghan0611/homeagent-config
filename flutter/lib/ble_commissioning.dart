/// Matter BLE 커미셔닝 화면
///
/// Phase 1: BLE 스캔으로 Matter 디바이스 발견 (UUID FFF6)
/// Phase 2: BTP 핸드셰이크 + PASE (세션 키 획득)
/// Phase 3: 암호화 채널로 WiFi credentials 전달 + on-network 커미셔닝
library;

import 'dart:async';
import 'dart:convert' show jsonEncode;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'matter/btp_codec.dart';
import 'matter/btp_session.dart';
import 'matter/pase_commissioning.dart';
import 'matter/secure_session.dart';
import 'matter/wifi_commissioning.dart';

/// Matter BLE 상수
class MatterBle {
  static const serviceUuid = '0000fff6-0000-1000-8000-00805f9b34fb';
  static const c1Uuid = '18ee2ef5-263d-4559-959f-4f9c429f9d11';
  static const c2Uuid = '18ee2ef5-263d-4559-959f-4f9c429f9d12';
}

/// 발견된 Matter 디바이스 정보
class MatterBleDevice {
  final BluetoothDevice device;
  final String name;
  final int rssi;
  final int? discriminator;
  final int? vendorId;
  final int? productId;

  MatterBleDevice({
    required this.device,
    required this.name,
    required this.rssi,
    this.discriminator,
    this.vendorId,
    this.productId,
  });
}

/// Matter BLE advertisement 파싱
MatterBleDevice? parseMatterAdvertisement(ScanResult result) {
  final serviceData = result.advertisementData.serviceData;
  final matterServiceGuid = Guid(MatterBle.serviceUuid);

  int? discriminator;
  int? vendorId;
  int? productId;

  for (final entry in serviceData.entries) {
    if (entry.key == matterServiceGuid && entry.value.length >= 8) {
      final data = entry.value;
      discriminator = (data[1] | (data[2] << 8)) & 0x0FFF;
      vendorId = data[3] | (data[4] << 8);
      productId = data[5] | (data[6] << 8);
    }
  }

  return MatterBleDevice(
    device: result.device,
    name: result.device.platformName.isNotEmpty
        ? result.device.platformName
        : 'Matter Device',
    rssi: result.rssi,
    discriminator: discriminator,
    vendorId: vendorId,
    productId: productId,
  );
}

/// BLE 커미셔닝 화면
class BleCommissioningScreen extends StatefulWidget {
  final String serverUrl;
  const BleCommissioningScreen({super.key, required this.serverUrl});

  @override
  State<BleCommissioningScreen> createState() => _BleCommissioningScreenState();
}

class _BleCommissioningScreenState extends State<BleCommissioningScreen> {
  final List<MatterBleDevice> _devices = [];
  bool _scanning = false;
  String _status = '스캔 대기 중';
  StreamSubscription<List<ScanResult>>? _scanSub;

  @override
  void dispose() {
    _scanSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    _devices.clear();
    setState(() {
      _scanning = true;
      _status = 'Matter 디바이스 스캔 중...';
    });

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      setState(() {
        _status = 'Bluetooth가 꺼져 있습니다';
        _scanning = false;
      });
      return;
    }

    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final hasMatterService = r.advertisementData.serviceUuids
            .any((uuid) => uuid.toString().toLowerCase().contains('fff6'));

        if (hasMatterService) {
          final device = parseMatterAdvertisement(r);
          if (device != null) {
            final exists = _devices.any(
                (d) => d.device.remoteId == device.device.remoteId);
            if (!exists) {
              setState(() {
                _devices.add(device);
                _status = '${_devices.length}개 Matter 디바이스 발견';
              });
            }
          }
        }
      }
    });

    await FlutterBluePlus.startScan(
      withServices: [Guid(MatterBle.serviceUuid)],
      timeout: const Duration(seconds: 30),
    );

    setState(() {
      _scanning = false;
      _status = _devices.isEmpty
          ? '디바이스를 찾지 못했습니다'
          : '${_devices.length}개 디바이스 발견 — 선택하세요';
    });
  }

  /// 디바이스 선택 → PIN + WiFi 입력 → 전체 커미셔닝 실행
  Future<void> _onDeviceSelected(MatterBleDevice device) async {
    setState(() => _status = '${device.name} 선택됨');

    // 1. Setup PIN + Manual Pairing Code 입력
    final setupInfo = await _showSetupDialog(device);
    if (setupInfo == null) return;

    // 2. WiFi credentials 입력 (PASE 전에 미리 받아둠)
    final wifiInfo = await _showWifiDialog();
    if (wifiInfo == null) return;

    // 3. 전체 커미셔닝 실행 (BLE → BTP → PASE → WiFi → disconnect)
    setState(() => _status = '커미셔닝 시작...');
    await FlutterBluePlus.stopScan();

    final success = await _runFullCommissioning(
      device.device,
      setupInfo.pin,
      wifiInfo.ssid,
      wifiInfo.password,
    );

    if (!success) return;

    // 4. Go 서버에 on-network 커미셔닝 요청
    await _requestOnNetworkCommissioning(setupInfo.manualCode);
  }

  /// Setup PIN + Manual Pairing Code 입력 다이얼로그
  Future<({int pin, String manualCode})?> _showSetupDialog(
      MatterBleDevice device) async {
    final pinController = TextEditingController();
    final codeController = TextEditingController();

    return showDialog<({int pin, String manualCode})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(device.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('MAC: ${device.device.remoteId}'),
              Text('RSSI: ${device.rssi} dBm'),
              if (device.discriminator != null)
                Text('Discriminator: ${device.discriminator}'),
              const SizedBox(height: 16),
              TextField(
                controller: pinController,
                decoration: const InputDecoration(
                  labelText: 'Setup PIN',
                  hintText: '예: 5641540',
                  helperText: '디바이스 라벨의 숫자 코드',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codeController,
                decoration: const InputDecoration(
                  labelText: 'Manual Pairing Code (11자리)',
                  hintText: '예: 05641540754',
                  helperText: 'matterjs on-network 커미셔닝용',
                ),
                keyboardType: TextInputType.number,
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
              final pinText =
                  pinController.text.replaceAll('-', '').replaceAll(' ', '');
              final pin = int.tryParse(pinText);
              final code =
                  codeController.text.replaceAll('-', '').replaceAll(' ', '');
              if (pin != null && code.isNotEmpty) {
                Navigator.pop(ctx, (pin: pin, manualCode: code));
              }
            },
            child: const Text('페어링'),
          ),
        ],
      ),
    );
  }

  /// WiFi SSID/Password 입력 다이얼로그
  Future<({String ssid, String password})?> _showWifiDialog() async {
    final ssidController = TextEditingController(text: 'TP-Link_E426');
    final pwController = TextEditingController();

    return showDialog<({String ssid, String password})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('WiFi 설정'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ssidController,
              decoration: const InputDecoration(labelText: 'WiFi SSID'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pwController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              if (ssidController.text.isNotEmpty) {
                Navigator.pop(ctx, (
                  ssid: ssidController.text,
                  password: pwController.text,
                ));
              }
            },
            child: const Text('연결'),
          ),
        ],
      ),
    );
  }

  /// 전체 BLE 커미셔닝: BTP → PASE → WiFi 전달 → disconnect
  /// BLE 연결을 유지한 채 WiFi까지 보내고 나서 disconnect
  Future<bool> _runFullCommissioning(
    BluetoothDevice bleDevice,
    int pin,
    String ssid,
    String password,
  ) async {
    StreamSubscription? indicateSub;
    BtpSession? btp;

    try {
      // 1. BLE 연결
      setState(() => _status = 'BLE 연결 중...');
      await bleDevice.connect(timeout: const Duration(seconds: 15));
      await Future.delayed(const Duration(milliseconds: 500));

      final mtu = await bleDevice.requestMtu(247);
      print('[COMM] BLE connected, MTU=$mtu');

      // 2. 서비스/특성 발견
      final services = await bleDevice.discoverServices();
      final matterSvc = services.firstWhere(
        (s) => s.uuid.toString().toLowerCase().contains('fff6'),
        orElse: () => throw Exception('Matter BLE 서비스 없음'),
      );

      final c1 = matterSvc.characteristics.firstWhere(
        (c) => c.uuid.toString().toLowerCase() == MatterBle.c1Uuid,
        orElse: () => throw Exception('C1 특성 없음'),
      );
      final c2 = matterSvc.characteristics.firstWhere(
        (c) => c.uuid.toString().toLowerCase() == MatterBle.c2Uuid,
        orElse: () => throw Exception('C2 특성 없음'),
      );

      // C1 write 속성 자동 감지
      final c1WriteType = c1.properties.write ? false : true;
      print('[COMM] C1 write=${c1.properties.write} '
          'writeNoResp=${c1.properties.writeWithoutResponse} '
          'using withoutResponse=$c1WriteType');

      // 3. BTP 세션
      btp = BtpSession(
        writeToDevice: (data) => c1.write(data, withoutResponse: c1WriteType),
        disconnect: () async {
          try { await bleDevice.disconnect(); } catch (_) {}
        },
      );

      // C2 indicate 구독
      Completer<Uint8List>? handshakeCompleter;
      await c2.setNotifyValue(true);
      indicateSub = c2.onValueReceived.listen((data) {
        final bytes = Uint8List.fromList(data);
        print('[COMM] C2 rx ${bytes.length}B: '
            '${bytes.take(10).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        if (bytes.isNotEmpty && bytes[0] == 0x65 && handshakeCompleter != null) {
          handshakeCompleter!.complete(bytes);
          handshakeCompleter = null;
        } else {
          btp?.handleIncomingData(bytes);
        }
      });

      // 4. BTP 핸드셰이크
      setState(() => _status = 'BTP 핸드셰이크...');
      handshakeCompleter = Completer<Uint8List>();
      final hsReq = encodeBtpHandshakeRequest(attMtu: mtu, clientWindowSize: 6);
      print('[COMM] BTP HS req: ${hsReq.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      await c1.write(hsReq, withoutResponse: c1WriteType);

      final hsRespData = await handshakeCompleter!.future
          .timeout(const Duration(seconds: 5),
              onTimeout: () => throw Exception('BTP 핸드셰이크 타임아웃'));

      final hsResp = decodeBtpHandshakeResponse(hsRespData);
      btp.initFromHandshakeResponse(hsResp.attMtu, hsResp.windowSize);
      print('[COMM] BTP session: fragSize=${hsResp.attMtu - 3}, win=${hsResp.windowSize}');

      // 5. PASE
      setState(() => _status = 'PASE 인증 중...');
      final engine = PaseEngine(
        btp: btp,
        setupPin: pin,
        onStateChange: (state, message) {
          if (mounted) setState(() => _status = message);
        },
      );

      final paseResult = await engine.run();
      if (!paseResult.success || paseResult.sessionKey == null) {
        setState(() => _status = '❌ PASE 실패: ${paseResult.error}');
        return false;
      }

      print('[COMM] PASE success! sessionId=${paseResult.initiatorSessionId} '
          'peerSessionId=${paseResult.responderSessionId}');

      // 6. 암호화 세션 생성 + WiFi 전달 (BLE 아직 연결 상태!)
      setState(() => _status = 'WiFi credentials 전달 중...');
      final session = SecureSession.fromKe(
        paseResult.sessionKey!,
        sessionId: paseResult.initiatorSessionId,
        peerSessionId: paseResult.responderSessionId,
      );

      final wifiComm = WifiCommissioner(
        btp: btp,
        session: session,
        exchangeId: engine.exchangeId,
      );

      final wifiOk = await wifiComm.sendWifiCredentials(ssid, password);
      if (!wifiOk) {
        setState(() => _status = '❌ WiFi credentials 전달 실패');
        return false;
      }

      print('[COMM] WiFi credentials sent successfully!');
      setState(() => _status = '✅ WiFi 설정 완료');
      return true;
    } catch (e) {
      setState(() => _status = '❌ 커미셔닝 실패: $e');
      print('[COMM] Error: $e');
      return false;
    } finally {
      // 리소스 정리 — WiFi 전달 후 disconnect
      indicateSub?.cancel();
      await btp?.close();
      try { await bleDevice.disconnect(); } catch (_) {}
    }
  }

  /// Go 서버에 on-network 커미셔닝 요청
  Future<void> _requestOnNetworkCommissioning(String manualCode) async {
    setState(() => _status = 'on-network 커미셔닝 요청 중...');
    try {
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('${widget.serverUrl}/api/commission'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'code': manualCode,
        'network_only': true,
      }));
      final response = await request.close();
      final statusCode = response.statusCode;
      await response.drain();

      if (statusCode == 202) {
        setState(() => _status = '✅ 커미셔닝 진행 중 (백그라운드)');
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('커미셔닝 진행 중'),
              content: Text(
                '디바이스가 WiFi($manualCode)에 연결 후\n'
                'on-network 커미셔닝이 백그라운드에서 진행됩니다.\n\n'
                '완료되면 디바이스 목록에 나타납니다.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('확인'),
                ),
              ],
            ),
          );
        }
      } else {
        setState(() => _status = '❌ 커미셔닝 요청 실패: HTTP $statusCode');
      }
    } catch (e) {
      setState(() => _status = '❌ 커미셔닝 요청 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Matter 디바이스 페어링'),
        actions: [
          if (_scanning)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // 상태 바
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: _scanning
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Text(_status, style: const TextStyle(fontSize: 14)),
          ),

          // 디바이스 목록
          Expanded(
            child: _devices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bluetooth_searching,
                            size: 64,
                            color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 16),
                        const Text('Matter 디바이스를 페어링 모드로\n설정한 후 스캔하세요',
                            textAlign: TextAlign.center),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (ctx, i) {
                      final d = _devices[i];
                      return ListTile(
                        leading: Icon(Icons.bluetooth,
                            color: Theme.of(context).colorScheme.primary),
                        title: Text(d.name),
                        subtitle: Text(
                          'RSSI: ${d.rssi} dBm'
                          '${d.discriminator != null ? ' · Disc: ${d.discriminator}' : ''}'
                          '${d.vendorId != null ? ' · VID: 0x${d.vendorId!.toRadixString(16)}' : ''}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _onDeviceSelected(d),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scanning ? null : _startScan,
        icon: Icon(_scanning ? Icons.hourglass_top : Icons.bluetooth_searching),
        label: Text(_scanning ? '스캔 중...' : 'BLE 스캔'),
      ),
    );
  }
}
