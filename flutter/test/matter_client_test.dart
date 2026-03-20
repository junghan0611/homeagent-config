import 'package:flutter_test/flutter_test.dart';
import 'package:homeagent/matter_client.dart';
import 'package:homeagent/api_client.dart';

void main() {
  group('ServerInfo', () {
    test('fromJson 파싱', () {
      final info = ServerInfo.fromJson({
        'fabric_id': 1,
        'compressed_fabric_id': 123456,
        'fabric_index': 1,
        'schema_version': 12,
        'sdk_version': '0.11.0',
        'bluetooth_enabled': true,
        'thread_credentials_set': false,
      });

      expect(info.fabricId, 1);
      expect(info.sdkVersion, '0.11.0');
      expect(info.bluetoothEnabled, true);
      expect(info.threadCredentialsSet, false);
    });

    test('fromJson 누락 필드 기본값', () {
      final info = ServerInfo.fromJson({});
      expect(info.fabricId, 0);
      expect(info.sdkVersion, '');
      expect(info.bluetoothEnabled, false);
    });
  });

  group('MatterEvent', () {
    test('attribute_updated 파싱', () {
      final event = MatterEvent(
        type: 'attribute_updated',
        data: [42, '1/6/0', true],
      );

      final update = event.attributeUpdate;
      expect(update, isNotNull);
      expect(update!.nodeId, 42);
      expect(update.path, '1/6/0');
      expect(update.value, true);
    });

    test('attribute_updated — 데이터 부족 시 null', () {
      final event = MatterEvent(type: 'attribute_updated', data: [42]);
      expect(event.attributeUpdate, isNull);
    });

    test('node_added — attributeUpdate는 null', () {
      final event = MatterEvent(type: 'node_added', data: {'node_id': 1});
      expect(event.attributeUpdate, isNull);
    });
  });

  group('_nodeToDevice (static)', () {
    test('on_off_plug 변환', () {
      final device = MatterWsClient.nodeToDevice({
        'node_id': 5,
        'available': true,
        'attributes': {
          '1/29/0': [{'deviceType': 0x010A, 'revision': 1}],
          '1/6/0': true,
        },
      });

      expect(device.nodeId, 5);
      expect(device.type, 'on_off_plug');
      expect(device.available, true);
      expect(device.isOn, true);
    });

    test('temperature_sensor 변환 — 값 /100', () {
      final device = MatterWsClient.nodeToDevice({
        'node_id': 10,
        'available': true,
        'attributes': {
          '1/29/0': [{'deviceType': 0x0302, 'revision': 1}],
          '1/1026/0': 2350,
        },
      });

      expect(device.type, 'temperature_sensor');
      expect(device.temperature, 23.5);
    });

    test('dimmable_light — level 추출', () {
      final device = MatterWsClient.nodeToDevice({
        'node_id': 7,
        'available': true,
        'attributes': {
          '1/29/0': [{'deviceType': 0x0101, 'revision': 1}],
          '1/6/0': true,
          '1/8/0': 128,
        },
      });

      expect(device.type, 'dimmable_light');
      expect(device.isOn, true);
      expect(device.level, 128);
    });

    test('빈 attributes', () {
      final device = MatterWsClient.nodeToDevice({
        'node_id': 1,
        'available': false,
        'attributes': {},
      });

      expect(device.type, '');
      expect(device.available, false);
    });
  });
}
