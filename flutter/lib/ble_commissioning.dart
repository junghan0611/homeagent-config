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
    // Phase 2: BLE 연결 + PASE + WiFi credentials
    // 지금은 정보 표시만
    setState(() => _status = '${device.name} 선택됨 (커미셔닝 준비 중...)');

    showDialog(
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
            if (device.vendorId != null)
              Text('Vendor ID: 0x${device.vendorId!.toRadixString(16)}'),
            if (device.productId != null)
              Text('Product ID: 0x${device.productId!.toRadixString(16)}'),
            const SizedBox(height: 16),
            const Text(
              'Phase 2: BLE 커미셔닝 구현 예정\n'
              '(BTP → PASE → WiFi → on-network)',
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
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
