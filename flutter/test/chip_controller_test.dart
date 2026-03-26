import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeagent/chip_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ChipController chip;
  late List<MethodCall> calls;

  setUp(() {
    chip = ChipController();
    calls = [];

    // Mock MethodChannel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.homeagent/chip'),
      (MethodCall call) async {
        calls.add(call);
        switch (call.method) {
          case 'init':
            return true;
          case 'pairDevice':
            return {'nodeId': call.arguments['nodeId'], 'success': true};
          case 'openCommissioningWindow':
            return {
              'setupPinCode': 12345678,
              'manualPairingCode': '35987600055',
              'qrCode': 'MT:abc',
            };
          case 'setThreadDataset':
          case 'setWifiCredentials':
          case 'unpairDevice':
            return true;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.homeagent/chip'),
      null,
    );
  });

  group('INV-1: setupPinCode 검증', () {
    test('유효한 PIN 반환 시 정상 동작', () async {
      await chip.init();
      final window = await chip.openCommissioningWindow(1);
      expect(window.setupPinCode, 12345678);
      expect(window.manualPairingCode, '35987600055');
    });

    test('PIN=0 반환 시 PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.homeagent/chip'),
        (call) async {
          if (call.method == 'init') return true;
          if (call.method == 'openCommissioningWindow') {
            return {'setupPinCode': 0, 'manualPairingCode': '', 'qrCode': ''};
          }
          return null;
        },
      );

      await chip.init();
      expect(
        () => chip.openCommissioningWindow(1),
        throwsA(isA<PlatformException>()),
      );
    });

    test('PIN=null 반환 시 PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.homeagent/chip'),
        (call) async {
          if (call.method == 'init') return true;
          if (call.method == 'openCommissioningWindow') {
            return {'manualPairingCode': '', 'qrCode': ''};
          }
          return null;
        },
      );

      await chip.init();
      expect(
        () => chip.openCommissioningWindow(1),
        throwsA(isA<PlatformException>()),
      );
    });

    test('PIN > 99999998 시 PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.homeagent/chip'),
        (call) async {
          if (call.method == 'init') return true;
          if (call.method == 'openCommissioningWindow') {
            return {
              'setupPinCode': 99999999,
              'manualPairingCode': '',
              'qrCode': '',
            };
          }
          return null;
        },
      );

      await chip.init();
      expect(
        () => chip.openCommissioningWindow(1),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('INV-2: nodeId 검증', () {
    test('nodeId=0 시 ArgumentError', () async {
      await chip.init();
      expect(
        () => chip.pairDevice(0, '05641540754'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('nodeId<0 시 ArgumentError', () async {
      await chip.init();
      expect(
        () => chip.pairDevice(-1, '05641540754'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('빈 코드 시 ArgumentError', () async {
      await chip.init();
      expect(
        () => chip.pairDevice(1, ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('유효한 nodeId+code 시 정상 동작', () async {
      await chip.init();
      final result = await chip.pairDevice(42, '05641540754');
      expect(result.nodeId, 42);
      expect(result.success, true);
    });
  });

  group('INV-5: pairDevice 결과 검증', () {
    test('SDK가 nodeId=0 반환 시 PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.homeagent/chip'),
        (call) async {
          if (call.method == 'init') return true;
          if (call.method == 'pairDevice') {
            return {'nodeId': 0, 'success': true};
          }
          return null;
        },
      );

      await chip.init();
      expect(
        () => chip.pairDevice(1, '05641540754'),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('MethodChannel 호출 검증', () {
    test('init은 한번만 호출', () async {
      await chip.init();
      await chip.init(); // 두 번째 호출
      final initCalls = calls.where((c) => c.method == 'init').length;
      expect(initCalls, 1);
    });

    test('setThreadDataset 인자 전달', () async {
      await chip.init();
      await chip.setThreadDataset('0e080000');
      final call = calls.firstWhere((c) => c.method == 'setThreadDataset');
      expect(call.arguments['dataset'], '0e080000');
    });

    test('setWifiCredentials 인자 전달', () async {
      await chip.init();
      await chip.setWifiCredentials('MyWiFi', 'password123');
      final call = calls.firstWhere((c) => c.method == 'setWifiCredentials');
      expect(call.arguments['ssid'], 'MyWiFi');
      expect(call.arguments['password'], 'password123');
    });
  });
}
