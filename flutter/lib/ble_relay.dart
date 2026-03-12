/// BLE Relay — Flutter ↔ matterjs-server BLE 바이트 중계
///
/// Flutter가 Android BLE API로 실제 BLE 작업을 수행하고,
/// WebSocket으로 matterjs-server의 RemoteBleInterface에 바이트를 중계.
///
/// WS 프로토콜:
///   ← ble_scan_start/stop       (matterjs → Flutter)
///   → ble_scan_result            (Flutter → matterjs)
///   ← ble_connect {address}      (matterjs → Flutter)
///   → ble_connected {address, mtu} (Flutter → matterjs)
///   ← ble_write {address, data}  (matterjs → Flutter → BLE C1)
///   → ble_data {address, data}   (BLE C2 → Flutter → matterjs)
///   ← ble_disconnect {address}   (matterjs → Flutter)
///   → ble_disconnected {address} (Flutter → matterjs)
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Matter BLE 상수
class _MatterBle {
  static const serviceUuid = '0000fff6-0000-1000-8000-00805f9b34fb';
  static const c1Uuid = '18ee2ef5-263d-4559-959f-4f9c429f9d11';
  static const c2Uuid = '18ee2ef5-263d-4559-959f-4f9c429f9d12';
}

/// BLE relay 상태 콜백
typedef BleRelayStatusCallback = void Function(String status);

/// BLE Relay — matterjs-server와 BLE 바이트 중계
class BleRelay {
  final String wsUrl;
  final BleRelayStatusCallback? onStatus;

  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  StreamSubscription? _scanSub;
  StreamSubscription? _c2Sub;

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _c1;
  BluetoothCharacteristic? _c2;
  bool _c1WriteWithoutResponse = false;

  BleRelay({required this.wsUrl, this.onStatus});

  /// BLE 어댑터 상태 확인
  Future<bool> checkBleAdapter() async {
    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      onStatus?.call('⚠️ BLE가 꺼져있습니다. 설정에서 블루투스를 켜세요.');
      return false;
    }
    return true;
  }

  /// WS 연결 시작
  Future<void> connect() async {
    // BLE 어댑터 상태 확인
    final bleReady = await checkBleAdapter();
    if (!bleReady) {
      throw Exception('블루투스가 꺼져있습니다. 설정에서 블루투스를 켜세요.');
    }

    onStatus?.call('BLE relay 연결 중... ($wsUrl)');

    try {
      _ws = WebSocketChannel.connect(Uri.parse(wsUrl));
      // WebSocketChannel.connect는 즉시 반환. ready를 기다려야 실제 연결 확인.
      await _ws!.ready;
    } catch (e) {
      final msg = 'matterjs BLE 서버($wsUrl)에 연결할 수 없습니다. '
          '서버가 실행 중인지 확인하세요.';
      onStatus?.call('❌ $msg');
      throw Exception(msg);
    }

    _wsSub = _ws!.stream.listen(
      (raw) {
        try {
          final msg = jsonDecode(raw as String) as Map<String, dynamic>;
          _handleCommand(msg);
        } catch (e) {
          print('[BLE-RELAY] parse error: $e');
        }
      },
      onError: (e) {
        onStatus?.call('❌ BLE relay 연결 오류: $e');
        _cleanup();
      },
      onDone: () {
        onStatus?.call('BLE relay 연결 종료 — 서버 연결이 끊어졌습니다');
        _cleanup();
      },
    );

    onStatus?.call('✅ BLE relay 연결됨');
  }

  /// WS 연결 종료
  Future<void> disconnect() async {
    await _cleanup();
    await _wsSub?.cancel();
    _wsSub = null;
    await _ws?.sink.close();
    _ws = null;
  }

  /// matterjs-server에서 온 명령 처리
  void _handleCommand(Map<String, dynamic> msg) {
    final cmd = msg['cmd'] as String?;
    print('[BLE-RELAY] ← matterjs: cmd=$cmd addr=${msg['address'] ?? 'n/a'}');
    switch (cmd) {
      case 'ble_scan_start':
        _startScan();
        break;
      case 'ble_scan_stop':
        _stopScan();
        break;
      case 'ble_connect':
        _connectDevice(msg['address'] as String);
        break;
      case 'ble_write':
        _writeToDevice(
          msg['address'] as String,
          (msg['data'] as List).cast<int>(),
        );
        break;
      case 'ble_disconnect':
        _disconnectDevice(msg['address'] as String?);
        break;
    }
  }

  /// BLE 스캔 시작 — Matter 서비스(FFF6) 필터
  void _startScan() {
    onStatus?.call('BLE 스캔 시작...');
    _scanSub?.cancel();

    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final hasMatter = r.advertisementData.serviceUuids
            .any((uuid) => uuid.toString().toLowerCase().contains('fff6'));
        if (!hasMatter) continue;

        // FFF6 서비스 데이터 추출
        // Android에서 serviceData key 포맷이 다를 수 있으므로 fff6 포함 여부로 매칭
        final serviceData = r.advertisementData.serviceData;
        List<int>? matterData;

        for (final entry in serviceData.entries) {
          final keyStr = entry.key.toString().toLowerCase();
          if (keyStr.contains('fff6')) {
            matterData = entry.value.toList();
            break;
          }
        }

        if (matterData == null) {
          // serviceUuids에는 있지만 serviceData에 없는 경우
          print('[BLE-RELAY] FFF6 service found but no serviceData for '
              '${r.device.remoteId} (keys: ${serviceData.keys.map((k) => k.toString()).join(", ")})');
          continue;
        }

        print('[BLE-RELAY] scan: ${r.device.remoteId} rssi=${r.rssi} '
            'data=${matterData.map((b) => b.toRadixString(16).padLeft(2, "0")).join(" ")}');

        _send({
          'event': 'ble_scan_result',
          'address': r.device.remoteId.toString(),
          'serviceData': matterData,
          'rssi': r.rssi,
          'name': r.device.platformName,
        });
      }
    });

    FlutterBluePlus.startScan(
      withServices: [Guid(_MatterBle.serviceUuid)],
      timeout: const Duration(seconds: 60),
    );
  }

  void _stopScan() {
    FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    _scanSub = null;
    onStatus?.call('BLE 스캔 중지');
  }

  /// BLE 디바이스 연결
  Future<void> _connectDevice(String address) async {
    onStatus?.call('BLE 연결 중: $address');
    try {
      final device = BluetoothDevice.fromId(address);
      await device.connect(timeout: const Duration(seconds: 15));
      await Future.delayed(const Duration(milliseconds: 500));

      final mtu = await device.requestMtu(247);

      // 서비스/특성 발견
      final services = await device.discoverServices();
      final matterSvc = services.firstWhere(
        (s) => s.uuid.toString().toLowerCase().contains('fff6'),
        orElse: () => throw Exception('Matter 서비스 없음'),
      );

      _c1 = matterSvc.characteristics.firstWhere(
        (c) => c.uuid.toString().toLowerCase() == _MatterBle.c1Uuid,
        orElse: () => throw Exception('C1 특성 없음'),
      );
      _c2 = matterSvc.characteristics.firstWhere(
        (c) => c.uuid.toString().toLowerCase() == _MatterBle.c2Uuid,
        orElse: () => throw Exception('C2 특성 없음'),
      );

      // Matter BTP spec: C1은 Write Without Response 사용
      // C1 특성이 writeWithoutResponse를 지원하면 반드시 사용
      _c1WriteWithoutResponse = _c1!.properties.writeWithoutResponse;
      print('[BLE-RELAY] C1 properties: write=${_c1!.properties.write} '
          'writeWithoutResponse=${_c1!.properties.writeWithoutResponse} '
          '→ using withoutResponse=$_c1WriteWithoutResponse');

      // C2 indicate 구독
      // Matter BTP spec: C2는 indicate(0x0002) 사용. notify(0x0001) 아님.
      // FlutterBluePlus 기본 동작: 양쪽 다 지원하면 notify 선택 → BTP 실패.
      // forceIndications: true로 CCCD 0x0002 강제 (Android only).
      print('[BLE-RELAY] C2 properties: notify=${_c2!.properties.notify} '
          'indicate=${_c2!.properties.indicate} '
          '→ forceIndications=true');
      await _c2!.setNotifyValue(true, forceIndications: true);
      _c2Sub = _c2!.onValueReceived.listen((data) {
        print('[BLE-RELAY] C2 indicate: ${data.map((b) => b.toRadixString(16).padLeft(2, "0")).join(" ")} (${data.length} bytes)');
        _send({
          'event': 'ble_data',
          'address': address,
          'data': data,
        });
      });

      _connectedDevice = device;
      onStatus?.call('BLE 연결됨: $address (MTU=$mtu)');

      _send({
        'event': 'ble_connected',
        'address': address,
        'mtu': mtu,
      });
    } catch (e) {
      onStatus?.call('BLE 연결 실패: $e');
      _send({
        'event': 'ble_disconnected',
        'address': address,
        'error': e.toString(),
      });
    }
  }

  /// C1에 데이터 쓰기
  Future<void> _writeToDevice(String address, List<int> data) async {
    if (_c1 == null) {
      print('[BLE-RELAY] C1 not available for write');
      return;
    }
    try {
      print('[BLE-RELAY] C1 write: ${data.map((b) => b.toRadixString(16).padLeft(2, "0")).join(" ")} '
          '(${data.length} bytes, withoutResponse=$_c1WriteWithoutResponse)');
      await _c1!.write(data, withoutResponse: _c1WriteWithoutResponse);
      print('[BLE-RELAY] C1 write OK');
    } catch (e) {
      print('[BLE-RELAY] C1 write error: $e');
      _send({
        'event': 'ble_disconnected',
        'address': address,
        'error': e.toString(),
      });
    }
  }

  /// BLE 디바이스 연결 해제
  Future<void> _disconnectDevice(String? address) async {
    onStatus?.call('BLE 연결 해제');
    await _c2Sub?.cancel();
    _c2Sub = null;
    try {
      await _connectedDevice?.disconnect();
    } catch (_) {}
    _connectedDevice = null;
    _c1 = null;
    _c2 = null;

    if (address != null) {
      _send({'event': 'ble_disconnected', 'address': address});
    }
  }

  /// WS로 메시지 전송
  void _send(Map<String, dynamic> msg) {
    final json = jsonEncode(msg);
    print('[BLE-RELAY] → matterjs: event=${msg['event']} (${json.length} chars)');
    _ws?.sink.add(json);
  }

  /// 리소스 정리 — BLE 리소스를 확실히 해제해야 2회 연속 커미셔닝이 가능
  Future<void> _cleanup() async {
    _stopScan();
    await _c2Sub?.cancel();
    _c2Sub = null;
    _c1WriteWithoutResponse = false;
    try {
      await _connectedDevice?.disconnect();
    } catch (e) {
      print('[BLE-RELAY] cleanup disconnect error (무시): $e');
    }
    _connectedDevice = null;
    _c1 = null;
    _c2 = null;
  }
}
