import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeagent/api_client.dart';
import 'package:homeagent/widgets/device_card.dart';
import 'package:homeagent/theme.dart';

/// DeviceCard를 MaterialApp 안에서 렌더링하는 헬퍼
Widget _wrap(Device device, {void Function(int, String, {dynamic value})? onCommand}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(
      body: SizedBox(
        width: 200,
        height: 200,
        child: DeviceCard(device: device, onCommand: onCommand),
      ),
    ),
  );
}

void main() {
  group('DeviceCard 타입별 렌더링', () {
    testWidgets('on_off_plug — 이름 + 켜짐 표시', (tester) async {
      final d = Device.fromJson({
        'node_id': 6,
        'name': '거실 플러그',
        'type': 'on_off_plug',
        'available': true,
        'state': {'on': true},
      });

      await tester.pumpWidget(_wrap(d));

      expect(find.text('거실 플러그'), findsOneWidget);
      expect(find.byIcon(Icons.power), findsOneWidget);
      expect(find.textContaining('켜짐'), findsOneWidget);
    });

    testWidgets('on_off_plug — 꺼짐 표시', (tester) async {
      final d = Device.fromJson({
        'node_id': 6,
        'name': '플러그',
        'type': 'on_off_plug',
        'available': true,
        'state': {'on': false},
      });

      await tester.pumpWidget(_wrap(d));
      expect(find.textContaining('꺼짐'), findsOneWidget);
    });

    testWidgets('dimmable_light — 밝기 슬라이더', (tester) async {
      final d = Device.fromJson({
        'node_id': 3,
        'name': '조명',
        'type': 'dimmable_light',
        'available': true,
        'state': {'on': true, 'level': 50},
      });

      await tester.pumpWidget(_wrap(d));

      expect(find.byIcon(Icons.lightbulb), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.textContaining('50%'), findsOneWidget);
    });

    testWidgets('dimmable_light 꺼짐 — 슬라이더 없음', (tester) async {
      final d = Device.fromJson({
        'node_id': 3,
        'name': '조명',
        'type': 'dimmable_light',
        'available': true,
        'state': {'on': false, 'level': 50},
      });

      await tester.pumpWidget(_wrap(d));
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('color_temp_light — lightbulb 아이콘 + 슬라이더', (tester) async {
      final d = Device.fromJson({
        'node_id': 4,
        'name': '색온도 조명',
        'type': 'color_temp_light',
        'available': true,
        'state': {'on': true, 'level': 80, 'color_temp': 300},
      });

      await tester.pumpWidget(_wrap(d));

      expect(find.byIcon(Icons.lightbulb), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('extended_color_light — lightbulb 아이콘', (tester) async {
      final d = Device.fromJson({
        'node_id': 5,
        'name': 'RGB 조명',
        'type': 'extended_color_light',
        'available': true,
        'state': {'on': true, 'level': 60},
      });

      await tester.pumpWidget(_wrap(d));
      expect(find.byIcon(Icons.lightbulb), findsOneWidget);
    });

    testWidgets('contact_sensor — 열림 상태', (tester) async {
      final d = Device.fromJson({
        'node_id': 1,
        'name': '현관문',
        'type': 'contact_sensor',
        'available': true,
        'state': {'contact': true},
      });

      await tester.pumpWidget(_wrap(d));

      expect(find.byIcon(Icons.sensor_door), findsOneWidget);
      expect(find.textContaining('열림'), findsOneWidget);
      // 센서는 탭 불가 — Slider 없음
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('contact_sensor — 닫힘 상태', (tester) async {
      final d = Device.fromJson({
        'node_id': 1,
        'name': '현관문',
        'type': 'contact_sensor',
        'available': true,
        'state': {'contact': false},
      });

      await tester.pumpWidget(_wrap(d));
      expect(find.textContaining('닫힘'), findsOneWidget);
    });

    testWidgets('temperature_sensor — 온도 큰 숫자', (tester) async {
      final d = Device.fromJson({
        'node_id': 10,
        'name': '온도 센서',
        'type': 'temperature_sensor',
        'available': true,
        'state': {'temperature': 23.5},
      });

      await tester.pumpWidget(_wrap(d));

      expect(find.byIcon(Icons.thermostat), findsOneWidget);
      expect(find.text('23.5°'), findsOneWidget);
    });

    testWidgets('humidity_sensor — 습도 큰 숫자', (tester) async {
      final d = Device.fromJson({
        'node_id': 11,
        'name': '습도 센서',
        'type': 'humidity_sensor',
        'available': true,
        'state': {'humidity': 60},
      });

      await tester.pumpWidget(_wrap(d));

      expect(find.byIcon(Icons.water_drop), findsOneWidget);
      // 큰 숫자(60%) + subtitle(60%) 두 곳에 표시됨
      expect(find.text('60%'), findsNWidgets(2));
    });

    testWidgets('오프라인 디바이스 — cloud_off 아이콘', (tester) async {
      final d = Device.fromJson({
        'node_id': 6,
        'name': '오프라인 플러그',
        'type': 'on_off_plug',
        'available': false,
        'state': {'on': false},
      });

      await tester.pumpWidget(_wrap(d));
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });

    testWidgets('알 수 없는 타입 — devices_other 아이콘', (tester) async {
      final d = Device.fromJson({
        'node_id': 99,
        'name': '미지의 기기',
        'type': 'unknown_type',
        'available': true,
        'state': {'on': true},
      });

      await tester.pumpWidget(_wrap(d));
      expect(find.byIcon(Icons.devices_other), findsOneWidget);
    });
  });

  group('DeviceCard 인터랙션', () {
    testWidgets('on_off_plug 탭 → onCommand 호출', (tester) async {
      String? calledCommand;
      int? calledNodeId;

      final d = Device.fromJson({
        'node_id': 6,
        'name': '플러그',
        'type': 'on_off_plug',
        'available': true,
        'state': {'on': true},
      });

      await tester.pumpWidget(_wrap(d, onCommand: (nodeId, command, {value}) {
        calledNodeId = nodeId;
        calledCommand = command;
      }));

      await tester.tap(find.byType(InkWell));
      expect(calledNodeId, 6);
      expect(calledCommand, 'off'); // on→off 토글
    });

    testWidgets('센서 탭 불가 — onCommand 미호출', (tester) async {
      bool called = false;

      final d = Device.fromJson({
        'node_id': 1,
        'name': '센서',
        'type': 'contact_sensor',
        'available': true,
        'state': {'contact': true},
      });

      await tester.pumpWidget(_wrap(d, onCommand: (_, __, {value}) {
        called = true;
      }));

      await tester.tap(find.byType(Card));
      expect(called, false);
    });
  });
}
