/// CHIP SDK Android MethodChannel wrapper.
///
/// Dart side of the ChipBridge — calls into CHIP SDK AAR via platform channel.
/// Used for BLE commissioning on Android (no BlueZ needed).
///
/// CHIPTool pattern (pairDeviceThroughBLE):
///   1. init()
///   2. setThreadDataset() or setWifiCredentials()
///   3. pairDevice() — BLE scan → GATT connect → pairDeviceThroughBLE
///   4. openCommissioningWindow() — get PIN for python-matter-server
///   5. python-matter-server commission_on_network(pin) via Go API
///   6. unpairDevice() — remove from CHIP fabric (optional)
library;

import 'package:flutter/services.dart';

class ChipController {
  static const _channel = MethodChannel('com.homeagent/chip');

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Initialize CHIP SDK platform. Call once on app start.
  Future<void> init() async {
    if (_initialized) return;
    await _channel.invokeMethod('init');
    _initialized = true;
  }

  /// Set Thread operational dataset (hex string from OTBR).
  Future<void> setThreadDataset(String datasetHex) async {
    await _channel.invokeMethod('setThreadDataset', {'dataset': datasetHex});
  }

  /// Set WiFi credentials for WiFi device commissioning.
  Future<void> setWifiCredentials(String ssid, String password) async {
    await _channel.invokeMethod('setWifiCredentials', {
      'ssid': ssid,
      'password': password,
    });
  }

  /// BLE commission a device (CHIPTool pattern).
  /// App scans BLE → GATT connect → pairDeviceThroughBLE.
  /// Setup code is parsed for discriminator + PIN automatically.
  Future<CommissionResult> pairDevice(int nodeId, String code) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'pairDevice',
      {'nodeId': nodeId, 'code': code},
    );
    return CommissionResult(
      nodeId: (result?['nodeId'] as num?)?.toInt() ?? nodeId,
      success: result?['success'] == true,
    );
  }

  /// Open commissioning window for multi-admin handoff.
  /// Returns setupPinCode that python-matter-server needs for commission_on_network.
  Future<CommissioningWindow> openCommissioningWindow(
    int nodeId, {
    int duration = 300,
    int discriminator = 3840,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'openCommissioningWindow',
      {'nodeId': nodeId, 'duration': duration, 'discriminator': discriminator},
    );
    return CommissioningWindow(
      setupPinCode: (result?['setupPinCode'] as num?)?.toInt() ?? 0,
      manualPairingCode: result?['manualPairingCode'] as String? ?? '',
      qrCode: result?['qrCode'] as String? ?? '',
    );
  }

  /// Remove device from CHIP fabric (after python-matter-server has it).
  Future<void> unpairDevice(int nodeId) async {
    await _channel.invokeMethod('unpairDevice', {'nodeId': nodeId});
  }
}

class CommissionResult {
  final int nodeId;
  final bool success;
  const CommissionResult({required this.nodeId, required this.success});
}

class CommissioningWindow {
  final int setupPinCode;
  final String manualPairingCode;
  final String qrCode;
  const CommissioningWindow({
    required this.setupPinCode,
    required this.manualPairingCode,
    required this.qrCode,
  });
}
