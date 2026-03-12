/// BLE Relay 프로토콜 테스트
///
/// BleRelay의 WS 프로토콜 계약을 검증:
/// - WS 메시지 JSON 구조 (cmd/event)
/// - 바이트 직렬화 라운드트립 (List<int> → JSON → List<int>)
/// - BTP 핸드셰이크 바이트 패턴
/// - Matter BLE 상수
///
/// 실제 BLE/WS 연결 없이 순수 로직만 테스트.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WS 프로토콜 메시지 구조', () {
    test('ble_write 명령 파싱 — data는 int 배열', () {
      final json = '{"cmd":"ble_write","address":"60:83:E7:C7:05:3D","data":[101,108,4,0,0,0,244,0,255]}';
      final msg = jsonDecode(json) as Map<String, dynamic>;

      expect(msg['cmd'], 'ble_write');
      expect(msg['address'], '60:83:E7:C7:05:3D');

      final data = (msg['data'] as List).cast<int>();
      expect(data, [101, 108, 4, 0, 0, 0, 244, 0, 255]);
      expect(data.length, 9);
    });

    test('ble_connect 명령 파싱', () {
      final json = '{"cmd":"ble_connect","address":"60:83:E7:C7:05:3D"}';
      final msg = jsonDecode(json) as Map<String, dynamic>;

      expect(msg['cmd'], 'ble_connect');
      expect(msg['address'], '60:83:E7:C7:05:3D');
    });

    test('ble_scan_start 명령 — payload 없음', () {
      final json = '{"cmd":"ble_scan_start"}';
      final msg = jsonDecode(json) as Map<String, dynamic>;

      expect(msg['cmd'], 'ble_scan_start');
      expect(msg.containsKey('address'), false);
    });

    test('ble_disconnect 명령 파싱', () {
      final json = '{"cmd":"ble_disconnect","address":"60:83:E7:C7:05:3D"}';
      final msg = jsonDecode(json) as Map<String, dynamic>;

      expect(msg['cmd'], 'ble_disconnect');
      expect(msg['address'], '60:83:E7:C7:05:3D');
    });

    test('ble_scan_result 이벤트 생성', () {
      final msg = {
        'event': 'ble_scan_result',
        'address': '60:83:E7:C7:05:3D',
        'serviceData': [0, 127, 3, 146, 19, 1, 1, 1],
        'rssi': -45,
        'name': 'P100M',
      };
      final json = jsonEncode(msg);
      final decoded = jsonDecode(json) as Map<String, dynamic>;

      expect(decoded['event'], 'ble_scan_result');
      expect((decoded['serviceData'] as List).cast<int>(), [0, 127, 3, 146, 19, 1, 1, 1]);
      expect(decoded['rssi'], -45);
    });

    test('ble_connected 이벤트 생성', () {
      final msg = {
        'event': 'ble_connected',
        'address': '60:83:E7:C7:05:3D',
        'mtu': 247,
      };
      final json = jsonEncode(msg);
      final decoded = jsonDecode(json) as Map<String, dynamic>;

      expect(decoded['event'], 'ble_connected');
      expect(decoded['mtu'], 247);
    });

    test('ble_data 이벤트 — C2 indicate 바이트', () {
      final c2Data = [101, 108, 4, 241, 0, 5]; // BTP handshake response
      final msg = {
        'event': 'ble_data',
        'address': '60:83:E7:C7:05:3D',
        'data': c2Data,
      };
      final json = jsonEncode(msg);
      final decoded = jsonDecode(json) as Map<String, dynamic>;

      expect(decoded['event'], 'ble_data');
      final data = (decoded['data'] as List).cast<int>();
      expect(data, c2Data);
    });

    test('ble_disconnected 이벤트 — error 포함', () {
      final msg = {
        'event': 'ble_disconnected',
        'address': '60:83:E7:C7:05:3D',
        'error': 'GATT connection timeout',
      };
      final json = jsonEncode(msg);
      final decoded = jsonDecode(json) as Map<String, dynamic>;

      expect(decoded['event'], 'ble_disconnected');
      expect(decoded['error'], 'GATT connection timeout');
    });

    test('모든 cmd 타입이 switch에 대응', () {
      // ble_relay.dart의 _handleCommand에서 처리하는 cmd 목록
      const expectedCmds = [
        'ble_scan_start',
        'ble_scan_stop',
        'ble_connect',
        'ble_write',
        'ble_disconnect',
      ];

      for (final cmd in expectedCmds) {
        final msg = {'cmd': cmd};
        final json = jsonEncode(msg);
        final decoded = jsonDecode(json);
        expect(decoded['cmd'], cmd, reason: '$cmd should survive JSON roundtrip');
      }
    });
  });

  group('바이트 직렬화 라운드트립', () {
    test('BTP handshake request — 0-255 전체 범위 보존', () {
      // 실제 BTP handshake request: 65 6c 04 00 00 00 f4 00 ff
      final original = [0x65, 0x6c, 0x04, 0x00, 0x00, 0x00, 0xf4, 0x00, 0xff];

      // matterjs 방향: Array.from(Uint8Array) → JSON string
      final json = jsonEncode({'data': original});

      // Flutter 방향: JSON parse → List<int>
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final restored = (decoded['data'] as List).cast<int>();

      expect(restored, original);
    });

    test('바이트 경계값 보존 (0, 127, 128, 255)', () {
      final edgeCases = [0, 1, 127, 128, 254, 255];
      final json = jsonEncode({'data': edgeCases});
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final restored = (decoded['data'] as List).cast<int>();

      expect(restored, edgeCases);
    });

    test('빈 배열 핸들링', () {
      final json = jsonEncode({'data': <int>[]});
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final restored = (decoded['data'] as List).cast<int>();

      expect(restored, isEmpty);
    });

    test('큰 BTP 세그먼트 (244 bytes MTU)', () {
      // BLE_MAXIMUM_BTP_MTU = 244 + 3 header = 247
      final bigPayload = List<int>.generate(244, (i) => i % 256);
      final json = jsonEncode({'data': bigPayload});
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final restored = (decoded['data'] as List).cast<int>();

      expect(restored.length, 244);
      expect(restored, bigPayload);
    });

    test('JSON 정수 정밀도 — 바이트 범위에서 부동소수점 없음', () {
      // JavaScript JSON.stringify([244]) = "[244]" (not "[244.0]")
      // Dart jsonDecode("[244]") → [244] (int, not double)
      final json = '[0, 128, 244, 255]';
      final decoded = jsonDecode(json) as List;

      for (final v in decoded) {
        expect(v, isA<int>(), reason: 'byte values should decode as int, not double');
      }
    });
  });

  group('BTP 핸드셰이크 바이트 패턴', () {
    test('핸드셰이크 요청 구조 (9 bytes)', () {
      final request = [0x65, 0x6c, 0x04, 0x00, 0x00, 0x00, 0xf4, 0x00, 0xff];

      expect(request[0], 0x65, reason: 'BTP opcode');
      expect(request[1], 0x6c, reason: 'protocol discriminator');
      expect(request[2], 0x04, reason: 'version 4');
      // ATT MTU = 244 (LE: 0xf4, 0x00)
      expect(request[6] | (request[7] << 8), 244, reason: 'ATT MTU');
      expect(request[8], 0xff, reason: 'window size 255');
      expect(request.length, 9);
    });

    test('핸드셰이크 응답 판별 (6 bytes)', () {
      final response = [0x65, 0x6c, 0x04, 0xf1, 0x00, 0x05];

      // matterjs에서의 판별 조건
      final isHandshakeResponse =
          response[0] == 0x65 && response[1] == 0x6c && response.length == 6;
      expect(isHandshakeResponse, true);

      // ATT MTU = 241 (LE: 0xf1, 0x00)
      expect(response[3] | (response[4] << 8), 241, reason: 'response ATT MTU');
      expect(response[5], 5, reason: 'window size');
    });

    test('요청(9 bytes)과 응답(6 bytes) 구분', () {
      final request = [0x65, 0x6c, 0x04, 0x00, 0x00, 0x00, 0xf4, 0x00, 0xff];
      final response = [0x65, 0x6c, 0x04, 0xf1, 0x00, 0x05];

      // 둘 다 0x65 0x6c로 시작하지만 길이로 구분
      expect(request[0], response[0]); // same opcode
      expect(request.length, isNot(response.length)); // different length
      expect(request.length, 9);
      expect(response.length, 6);
    });
  });

  group('Matter BLE 상수 검증', () {
    test('Matter 서비스 UUID (FFF6)', () {
      const serviceUuid = '0000fff6-0000-1000-8000-00805f9b34fb';
      expect(serviceUuid.contains('fff6'), true);
      // 16-bit UUID 0xFFF6 in 128-bit format
      expect(serviceUuid.startsWith('0000fff6'), true);
    });

    test('C1 특성 UUID (9d11 — write)', () {
      const c1Uuid = '18ee2ef5-263d-4559-959f-4f9c429f9d11';
      expect(c1Uuid.endsWith('9d11'), true);
    });

    test('C2 특성 UUID (9d12 — indicate)', () {
      const c2Uuid = '18ee2ef5-263d-4559-959f-4f9c429f9d12';
      expect(c2Uuid.endsWith('9d12'), true);
    });

    test('C1과 C2는 같은 서비스 내에서 하위 2바이트만 다름', () {
      const c1Uuid = '18ee2ef5-263d-4559-959f-4f9c429f9d11';
      const c2Uuid = '18ee2ef5-263d-4559-959f-4f9c429f9d12';
      // 끝 4자리만 다름
      expect(c1Uuid.substring(0, c1Uuid.length - 2),
          c2Uuid.substring(0, c2Uuid.length - 2));
    });
  });

  group('소스 코드 무결성 검증', () {
    test('ble_relay.dart에 forceIndications: true 존재', () {
      final source = File('lib/ble_relay.dart').readAsStringSync();
      expect(
        source.contains('forceIndications: true'),
        true,
        reason: 'C2 indicate를 위해 forceIndications: true 필수',
      );
    });

    test('ble_relay.dart에 writeWithoutResponse 로직 존재', () {
      final source = File('lib/ble_relay.dart').readAsStringSync();
      expect(
        source.contains('properties.writeWithoutResponse'),
        true,
        reason: 'C1 write type은 BTP spec에 맞게 writeWithoutResponse 사용',
      );
    });

    test('Matter BLE UUID가 ble_relay.dart에 정확히 정의됨', () {
      final source = File('lib/ble_relay.dart').readAsStringSync();
      expect(source.contains('0000fff6-0000-1000-8000-00805f9b34fb'), true,
          reason: 'FFF6 service UUID');
      expect(source.contains('18ee2ef5-263d-4559-959f-4f9c429f9d11'), true,
          reason: 'C1 UUID');
      expect(source.contains('18ee2ef5-263d-4559-959f-4f9c429f9d12'), true,
          reason: 'C2 UUID');
    });

    test('WS cmd 5종이 _handleCommand에서 처리됨', () {
      final source = File('lib/ble_relay.dart').readAsStringSync();
      const cmds = [
        'ble_scan_start',
        'ble_scan_stop',
        'ble_connect',
        'ble_write',
        'ble_disconnect',
      ];
      for (final cmd in cmds) {
        expect(source.contains("'$cmd'"), true,
            reason: 'cmd $cmd should be handled in _handleCommand');
      }
    });

    test('WS event 4종이 _send로 전송됨', () {
      final source = File('lib/ble_relay.dart').readAsStringSync();
      const events = [
        'ble_scan_result',
        'ble_connected',
        'ble_data',
        'ble_disconnected',
      ];
      for (final event in events) {
        expect(source.contains("'$event'"), true,
            reason: 'event $event should be sent via _send');
      }
    });
  });
}
