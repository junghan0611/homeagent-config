/// Matter BLE 커미셔닝 화면
///
/// Phase 1: BLE 스캔으로 Matter 디바이스 발견 (UUID FFF6)
/// Phase 2: BTP 핸드셰이크 + PASE + WiFi credentials 전달 (TODO)
/// Phase 3: matterjs-server on-network 커미셔닝 호출 (TODO)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'matter/btp_codec.dart';
import 'matter/btp_session.dart';
import 'matter/pase_commissioning.dart';

/// Matter BLE 상수
class MatterBle {
  static const serviceUuid = '0000fff6-0000-1000-8000-00805f9b34fb';
  static const c1Uuid = '18ee2ef5-263d-4559-959f-4f9c429f9d11'; // write (controller→device)
  static const c2Uuid = '18ee2ef5-263d-4559-959f-4f9c429f9d12'; // indicate (device→controller)
  static const c3Uuid = '64630238-8772-45f2-b87d-748a83218f04'; // additional data
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
  // Matter BLE advertisement에서 discriminator/vendor 정보 추출
  final serviceData = result.advertisementData.serviceData;
  final matterServiceGuid = Guid(MatterBle.serviceUuid);

  // Service data에서 Matter 정보 파싱
  int? discriminator;
  int? vendorId;
  int? productId;

  for (final entry in serviceData.entries) {
    if (entry.key == matterServiceGuid && entry.value.length >= 8) {
      final data = entry.value;
      // Matter BLE advertisement format (CSA spec):
      // byte 0: version + flags
      // byte 1-2: discriminator (12 bit)
      // byte 3-4: vendor ID
      // byte 5-6: product ID
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

    // BT 어댑터 상태 확인
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
        // Matter BLE Service UUID (FFF6) 필터
        final hasMatterService = r.advertisementData.serviceUuids
            .any((uuid) => uuid.toString().toLowerCase().contains('fff6'));

        if (hasMatterService) {
          final device = parseMatterAdvertisement(r);
          if (device != null) {
            // 중복 제거
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

    // 30초 스캔 (Matter BLE service UUID 필터)
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

  Future<void> _onDeviceSelected(MatterBleDevice device) async {
    setState(() => _status = '${device.name} 선택됨');

    // Setup PIN 입력 다이얼로그
    final pinController = TextEditingController();
    final pin = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(device.name),
        content: Column(
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
                labelText: 'Setup PIN (숫자 8자리)',
                hintText: '예: 05641540',
              ),
              keyboardType: TextInputType.number,
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
              final text = pinController.text.replaceAll('-', '').replaceAll(' ', '');
              final parsed = int.tryParse(text);
              if (parsed != null) Navigator.pop(ctx, parsed);
            },
            child: const Text('페어링'),
          ),
        ],
      ),
    );

    if (pin == null) return;

    // PASE 커미셔닝 실행
    setState(() => _status = 'PASE 커미셔닝 시작...');
    await FlutterBluePlus.stopScan();

    final result = await _runPaseCommissioning(device.device, pin);

    if (result.success) {
      setState(() => _status = '✅ PASE 성공! 세션 키 획득');

      // TODO Phase 3: WiFi credentials 전달 + on-network 커미셔닝
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('PASE 성공!'),
            content: const Text(
              '디바이스와 보안 세션이 수립되었습니다.\n\n'
              'Phase 3: WiFi 설정 + on-network 커미셔닝 예정',
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
      setState(() => _status = '❌ 실패: ${result.error}');
    }
  }

  /// BLE → BTP → PASE 전체 실행 + 리소스 확실히 정리
  Future<PaseResult> _runPaseCommissioning(
      BluetoothDevice bleDevice, int pin) async {
    StreamSubscription? indicateSub;
    BtpSession? btp;

    try {
      // 1. BLE 연결
      setState(() => _status = 'BLE 연결 중...');
      await bleDevice.connect(timeout: const Duration(seconds: 15));
      await Future.delayed(const Duration(milliseconds: 500));

      final mtu = await bleDevice.requestMtu(247);

      // 2. 서비스/특성 발견
      final services = await bleDevice.discoverServices();
      final matterSvc = services.firstWhere(
        (s) => s.uuid.toString().toLowerCase().contains('fff6'),
        orElse: () => throw Exception('Matter BLE 서비스 없음'),
      );

      final c1 = matterSvc.characteristics.firstWhere(
        (c) => c.uuid.toString().toLowerCase() ==
            '18ee2ef5-263d-4559-959f-4f9c429f9d11',
        orElse: () => throw Exception('C1 특성 없음'),
      );
      final c2 = matterSvc.characteristics.firstWhere(
        (c) => c.uuid.toString().toLowerCase() ==
            '18ee2ef5-263d-4559-959f-4f9c429f9d12',
        orElse: () => throw Exception('C2 특성 없음'),
      );

      // 3. BTP 세션 생성
      btp = BtpSession(
        writeToDevice: (data) => c1.write(data, withoutResponse: false),
        disconnect: () async {
          try { await bleDevice.disconnect(); } catch (_) {}
        },
      );

      // C2 indicate 구독 — 핸드셰이크 응답과 데이터 패킷 분기
      Completer<Uint8List>? handshakeCompleter;
      await c2.setNotifyValue(true);
      indicateSub = c2.onValueReceived.listen((data) {
        final bytes = Uint8List.fromList(data);
        if (bytes.isNotEmpty && bytes[0] == 0x65 && handshakeCompleter != null) {
          // BTP 핸드셰이크 응답
          handshakeCompleter!.complete(bytes);
          handshakeCompleter = null;
        } else {
          // BTP 데이터 패킷
          btp?.handleIncomingData(bytes);
        }
      });

      // 4. BTP 핸드셰이크
      setState(() => _status = 'BTP 핸드셰이크...');
      handshakeCompleter = Completer<Uint8List>();
      final hsReq = encodeBtpHandshakeRequest(attMtu: mtu, clientWindowSize: 6);
      await c1.write(hsReq, withoutResponse: false);

      final hsRespData = await handshakeCompleter!.future
          .timeout(const Duration(seconds: 5),
              onTimeout: () => throw Exception('BTP 핸드셰이크 타임아웃'));

      final hsResp = decodeBtpHandshakeResponse(hsRespData);
      btp.initFromHandshakeResponse(hsResp.attMtu, hsResp.windowSize);

      // 5. PASE 실행
      final engine = PaseEngine(
        btp: btp,
        setupPin: pin,
        onStateChange: (state, message) {
          if (mounted) setState(() => _status = message);
        },
      );

      return await engine.run();
    } catch (e) {
      return PaseResult(success: false, error: e.toString());
    } finally {
      // 리소스 확실히 정리 — 순서 중요
      indicateSub?.cancel();
      await btp?.close();
      try { await bleDevice.disconnect(); } catch (_) {}
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
            color: _scanning ? Colors.blue.shade50 : Colors.grey.shade100,
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
                            size: 64, color: Colors.grey.shade400),
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
                        leading: const Icon(Icons.bluetooth, color: Colors.blue),
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
