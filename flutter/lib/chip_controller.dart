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

import 'dart:async' show TimeoutException;

import 'package:flutter/services.dart';

class ChipController {
  static const _channel = MethodChannel('com.homeagent/chip');

  /// BLE 커미셔닝 타임아웃 (BLE scan + GATT + PASE + credential setup)
  static const _pairTimeout = Duration(seconds: 120);

  /// openCommissioningWindow 타임아웃 (CASE 연결 + window open)
  static const _windowTimeout = Duration(seconds: 30);

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
    assert(datasetHex.isNotEmpty, 'Thread dataset hex must not be empty');
    await _channel.invokeMethod('setThreadDataset', {'dataset': datasetHex});
  }

  /// Set WiFi credentials for WiFi device commissioning.
  Future<void> setWifiCredentials(String ssid, String password) async {
    assert(ssid.isNotEmpty, 'WiFi SSID must not be empty');
    await _channel.invokeMethod('setWifiCredentials', {
      'ssid': ssid,
      'password': password,
    });
  }

  /// BLE commission a device (CHIPTool pattern).
  /// App scans BLE → GATT connect → pairDeviceThroughBLE.
  /// Setup code is parsed for discriminator + PIN automatically.
  ///
  /// INV-2: nodeId > 0 (CHIP SDK 요구)
  Future<CommissionResult> pairDevice(int nodeId, String code) async {
    if (nodeId <= 0) {
      throw ArgumentError('nodeId must be > 0, got $nodeId');
    }
    if (code.isEmpty) {
      throw ArgumentError('pairing code must not be empty');
    }

    final result = await _channel.invokeMapMethod<String, dynamic>(
      'pairDevice',
      {'nodeId': nodeId, 'code': code},
    ).timeout(_pairTimeout);

    final resultNodeId = (result?['nodeId'] as num?)?.toInt();
    if (resultNodeId == null || resultNodeId <= 0) {
      throw PlatformException(
        code: 'INVALID_RESULT',
        message: 'pairDevice returned invalid nodeId: $resultNodeId',
      );
    }

    return CommissionResult(
      nodeId: resultNodeId,
      success: result?['success'] == true,
    );
  }

  /// Open commissioning window for multi-admin handoff.
  /// Returns setupPinCode that python-matter-server needs for commission_on_network.
  ///
  /// INV-1: setupPinCode ∈ [1, 99999998] (Matter spec)
  Future<CommissioningWindow> openCommissioningWindow(
    int nodeId, {
    int duration = 300,
    int discriminator = 3840,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'openCommissioningWindow',
      {'nodeId': nodeId, 'duration': duration, 'discriminator': discriminator},
    ).timeout(_windowTimeout);

    final pin = (result?['setupPinCode'] as num?)?.toInt();
    if (pin == null || pin <= 0 || pin > 99999998) {
      throw PlatformException(
        code: 'INVALID_PIN',
        message: 'setupPinCode invalid: $pin (expected 1..99999998)',
      );
    }

    return CommissioningWindow(
      setupPinCode: pin,
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


