import 'package:flutter_test/flutter_test.dart';
import 'package:homeagent/api_client.dart';

void main() {
  group('Device 모델 파싱', () {
    test('기본 필드 파싱', () {
      final d = Device.fromJson({
        'node_id': 6,
        'name': 'Smart Plug',
        'room': '거실',
        'type': 'on_off_plug',
        'available': true,
        'state': {'on': true},
      });

      expect(d.nodeId, 6);
      expect(d.name, 'Smart Plug');
      expect(d.room, '거실');
      expect(d.type, 'on_off_plug');
      expect(d.available, true);
      expect(d.isOn, true);
      expect(d.isSensor, false);
    });

    test('누락 필드 기본값', () {
      final d = Device.fromJson({});

      expect(d.nodeId, 0);
      expect(d.name, 'Unknown');
      expect(d.room, '');
      expect(d.type, '');
      expect(d.available, false);
      expect(d.isOn, false);
    });

    test('contact_sensor — contactOpen', () {
      final d = Device.fromJson({
        'node_id': 1,
        'name': '도어센서',
        'type': 'contact_sensor',
        'available': true,
        'state': {'contact': true},
      });

      expect(d.isContactSensor, true);
      expect(d.isSensor, true);
      expect(d.contactOpen, true);
    });

    test('contact_sensor — 닫힘', () {
      final d = Device.fromJson({
        'node_id': 1,
        'name': '도어센서',
        'type': 'contact_sensor',
        'available': true,
        'state': {'contact': false},
      });

      expect(d.contactOpen, false);
    });

    test('dimmable_light — level/isDimmable', () {
      final d = Device.fromJson({
        'node_id': 3,
        'name': '조명',
        'type': 'dimmable_light',
        'available': true,
        'state': {'on': true, 'level': 75},
      });

      expect(d.isDimmable, true);
      expect(d.isColorTemp, false);
      expect(d.level, 75);
      expect(d.isSensor, false);
    });

    test('color_temp_light — isColorTemp/isDimmable 둘 다', () {
      final d = Device.fromJson({
        'node_id': 4,
        'name': '색온도 조명',
        'type': 'color_temp_light',
        'available': true,
        'state': {'on': true, 'level': 50, 'color_temp': 300},
      });

      expect(d.isDimmable, true);
      expect(d.isColorTemp, true);
      expect(d.colorTemp, 300);
    });

    test('extended_color_light — isDimmable/isColorTemp', () {
      final d = Device.fromJson({
        'node_id': 5,
        'name': 'RGB 조명',
        'type': 'extended_color_light',
        'available': true,
        'state': {'on': true, 'level': 80},
      });

      expect(d.isDimmable, true);
      expect(d.isColorTemp, true);
    });

    test('temperature_sensor — temperature/humidity', () {
      final d = Device.fromJson({
        'node_id': 10,
        'name': '온습도 센서',
        'type': 'temperature_sensor',
        'available': true,
        'state': {'temperature': 23.5, 'humidity': 45.0},
      });

      expect(d.isTemperatureSensor, true);
      expect(d.isSensor, true);
      expect(d.temperature, 23.5);
      expect(d.humidity, 45.0);
    });

    test('humidity_sensor', () {
      final d = Device.fromJson({
        'node_id': 11,
        'name': '습도 센서',
        'type': 'humidity_sensor',
        'available': true,
        'state': {'humidity': 60},
      });

      expect(d.isHumiditySensor, true);
      expect(d.isSensor, true);
      expect(d.humidity, 60);
    });

    test('temperature null 안전', () {
      final d = Device.fromJson({
        'type': 'temperature_sensor',
        'state': {},
      });
      expect(d.temperature, isNull);
      expect(d.humidity, isNull);
    });

    test('level 기본값 0', () {
      final d = Device.fromJson({
        'type': 'dimmable_light',
        'state': {'on': true},
      });
      expect(d.level, 0);
    });
  });

  group('SseEvent 파싱', () {
    test('device_state 이벤트', () {
      final e = SseEvent.fromJson({
        'type': 'device_state',
        'device_id': 6,
        'key': 'on',
        'value': true,
      });

      expect(e.type, 'device_state');
      expect(e.deviceId, 6);
      expect(e.key, 'on');
      expect(e.value, true);
    });

    test('device_added 이벤트', () {
      final e = SseEvent.fromJson({
        'type': 'device_added',
        'device_id': 10,
      });

      expect(e.type, 'device_added');
      expect(e.deviceId, 10);
    });

    test('device_removed 이벤트', () {
      final e = SseEvent.fromJson({
        'type': 'device_removed',
        'device_id': 3,
      });

      expect(e.type, 'device_removed');
      expect(e.deviceId, 3);
    });

    test('snapshot 이벤트 — rawJson으로 devices 접근', () {
      final json = {
        'type': 'snapshot',
        'devices': [
          {'node_id': 6, 'name': 'Plug', 'type': 'on_off_plug', 'available': true, 'state': {'on': false}},
        ],
      };
      final e = SseEvent.fromJson(json);

      expect(e.type, 'snapshot');
      // Go SSE는 snapshot에서 devices를 최상위에 넣음 (value 아님)
      expect(e.rawJson['devices'], isA<List>());
      expect((e.rawJson['devices'] as List).length, 1);
      // value는 null일 수 있음
      expect(e.value, isNull);
    });

    test('snapshot 이벤트 — value에 devices가 있는 경우도 처리', () {
      final e = SseEvent.fromJson({
        'type': 'snapshot',
        'value': {
          'devices': [
            {'node_id': 6, 'name': 'Plug', 'type': 'on_off_plug', 'available': true, 'state': {'on': false}},
          ],
        },
      });

      expect(e.type, 'snapshot');
      // rawJson.devices가 없으면 value.devices fallback
      final devicesRaw = e.rawJson['devices'] ?? e.value?['devices'];
      expect(devicesRaw, isA<List>());
    });

    test('commission_error 이벤트', () {
      final e = SseEvent.fromJson({
        'type': 'commission_error',
        'key': 'error',
        'value': 'timeout',
      });

      expect(e.type, 'commission_error');
      expect(e.key, 'error');
      expect(e.value, 'timeout');
    });

    test('누락 필드 기본값', () {
      final e = SseEvent.fromJson({});
      expect(e.type, '');
      expect(e.deviceId, 0);
      expect(e.key, '');
      expect(e.value, isNull);
      expect(e.rawJson, isA<Map>());
    });
  });

  group('Device 타입 분류', () {
    final types = {
      'on_off_plug': (sensor: false, dimmable: false),
      'dimmable_light': (sensor: false, dimmable: true),
      'color_temp_light': (sensor: false, dimmable: true),
      'extended_color_light': (sensor: false, dimmable: true),
      'contact_sensor': (sensor: true, dimmable: false),
      'temperature_sensor': (sensor: true, dimmable: false),
      'humidity_sensor': (sensor: true, dimmable: false),
    };

    for (final entry in types.entries) {
      test('${entry.key} — sensor=${entry.value.sensor}, dimmable=${entry.value.dimmable}', () {
        final d = Device.fromJson({'type': entry.key, 'state': {}});
        expect(d.isSensor, entry.value.sensor);
        expect(d.isDimmable, entry.value.dimmable);
      });
    }

    test('알 수 없는 타입 — 기본 동작', () {
      final d = Device.fromJson({'type': 'unknown_thing', 'state': {}});
      expect(d.isSensor, false);
      expect(d.isDimmable, false);
    });
  });
}
