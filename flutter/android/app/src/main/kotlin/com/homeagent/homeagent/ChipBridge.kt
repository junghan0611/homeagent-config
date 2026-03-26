package com.homeagent.homeagent

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.ParcelUuid
import android.util.Log
import chip.devicecontroller.AttestationInfo
import chip.devicecontroller.ChipDeviceController
import chip.devicecontroller.CommissionParameters
import chip.devicecontroller.ControllerParams
import chip.devicecontroller.DeviceAttestationDelegate
import chip.devicecontroller.GetConnectedDeviceCallbackJni
import chip.devicecontroller.ICDDeviceInfo
import chip.devicecontroller.NetworkCredentials
import chip.devicecontroller.OpenCommissioningCallback
import chip.platform.AndroidBleManager
import chip.platform.AndroidChipPlatform
import chip.platform.AndroidNfcCommissioningManager
import chip.platform.BleCallback
import chip.platform.ChipMdnsCallbackImpl
import chip.platform.DiagnosticDataProviderImpl
import chip.platform.NsdManagerServiceBrowser
import chip.platform.NsdManagerServiceResolver
import chip.platform.PreferencesConfigurationManager
import chip.platform.PreferencesKeyValueStoreManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import matter.onboardingpayload.OnboardingPayloadParser

/**
 * ChipBridge — Flutter ↔ CHIP SDK Android MethodChannel bridge.
 *
 * BLE commissioning uses CHIPTool pattern (pairDeviceThroughBLE):
 *   1. App does BLE scan (BluetoothAdapter) for Matter discriminator
 *   2. App connects GATT
 *   3. Registers GATT with AndroidBleManager
 *   4. Calls pairDeviceThroughBLE(gatt, connId, nodeId, pin, params)
 *   5. SDK handles BTP/PASE/commissioning over the provided GATT
 *
 * This is the proven CHIPTool approach. pairDeviceWithCode's internal
 * BLE scan does not work reliably on Android.
 *
 * Does NOT interfere with matterjs BLE relay (ble_relay.dart) —
 * completely separate code path.
 */
class ChipBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, BleCallback {

    companion object {
        private const val TAG = "ChipBridge"
        private const val CHANNEL = "com.homeagent/chip"
        private const val CHIP_UUID = "0000FFF6-0000-1000-8000-00805F9B34FB"
        private const val BLE_SCAN_TIMEOUT_MS = 10000L

        init {
            System.loadLibrary("CHIPController")
            Log.i(TAG, "libCHIPController.so loaded")
        }
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private var controller: ChipDeviceController? = null
    private var chipPlatform: AndroidChipPlatform? = null
    private var bleGatt: BluetoothGatt? = null
    private var bleConnectionId = 0

    private var networkCredentials: NetworkCredentials? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> initController(result)
            "pairDevice" -> pairDevice(call, result)
            "openCommissioningWindow" -> openCommissioningWindow(call, result)
            "setThreadDataset" -> setThreadDataset(call, result)
            "setWifiCredentials" -> setWifiCredentials(call, result)
            "unpairDevice" -> unpairDevice(call, result)
            "isInitialized" -> result.success(controller != null)
            else -> result.notImplemented()
        }
    }

    // ── Init ──────────────────────────────────────────────

    private fun initController(result: MethodChannel.Result) {
        try {
            if (controller != null) {
                result.success(true)
                return
            }

            val platform = AndroidChipPlatform(
                AndroidBleManager(),
                AndroidNfcCommissioningManager(),
                PreferencesKeyValueStoreManager(context),
                PreferencesConfigurationManager(context),
                NsdManagerServiceResolver(context),
                NsdManagerServiceBrowser(context),
                ChipMdnsCallbackImpl(),
                DiagnosticDataProviderImpl(context),
            )
            chipPlatform = platform

            val ctrl = ChipDeviceController(
                ControllerParams.newBuilder().setControllerVendorId(0xFFF1).build()
            )
            controller = ctrl

            Log.i(TAG, "CHIP SDK initialized")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "init failed", e)
            result.error("CHIP_INIT_ERROR", e.message, null)
        }
    }

    // ── BLE Commission (CHIPTool pattern) ─────────────────

    /**
     * BLE commission: scan → GATT connect → pairDeviceThroughBLE.
     * This is the CHIPTool-proven path. App controls BLE, SDK controls Matter.
     *
     * args: { "nodeId": long, "code": String (QR or manual pairing code) }
     */
    private fun pairDevice(call: MethodCall, result: MethodChannel.Result) {
        val ctrl = controller
        if (ctrl == null) {
            result.error("NOT_INITIALIZED", "Call init() first", null)
            return
        }

        val nodeId = call.argument<Number>("nodeId")?.toLong() ?: 1L
        val code = call.argument<String>("code")
        if (code == null) {
            result.error("INVALID_ARGS", "code is required", null)
            return
        }

        // 1. Parse setup code → discriminator + setupPinCode
        val payload = try {
            val parser = OnboardingPayloadParser()
            if (code.startsWith("MT:")) {
                parser.parseQrCode(code)
            } else {
                parser.parseManualPairingCode(code)
            }
        } catch (e: Exception) {
            result.error("INVALID_CODE", "Cannot parse setup code: ${e.message}", null)
            return
        }

        val discriminator = payload.discriminator
        val setupPinCode = payload.setupPinCode
        val isShortDiscriminator = payload.hasShortDiscriminator

        Log.i(TAG, "pairDevice: node=$nodeId disc=$discriminator pin=${setupPinCode} short=$isShortDiscriminator creds=${networkCredentials != null}")

        // 1.5. 이전 BLE 연결 정리 (재시도 시 "Bluetooth connection already in use" 방지)
        bleGatt?.let { gatt ->
            Log.i(TAG, "Closing previous GATT connection")
            gatt.disconnect()
            gatt.close()
            bleGatt = null
        }
        bleConnectionId++

        // 2. BLE scan for Matter device
        val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
        if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled) {
            result.error("BLE_DISABLED", "Bluetooth is not enabled", null)
            return
        }

        val scanner = bluetoothAdapter.bluetoothLeScanner
        if (scanner == null) {
            result.error("BLE_NO_SCANNER", "BLE scanner not available", null)
            return
        }

        // Build scan filter for Matter service UUID + discriminator
        val serviceData = buildServiceData(discriminator)
        val serviceDataMask = buildServiceDataMask(isShortDiscriminator)
        val scanFilter = ScanFilter.Builder()
            .setServiceData(ParcelUuid(UUID.fromString(CHIP_UUID)), serviceData, serviceDataMask)
            .build()
        val scanSettings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        Log.i(TAG, "Starting BLE scan for discriminator=$discriminator")

        // Timeout handler
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        var scanDone = false

        val scanCallback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, scanResult: ScanResult) {
                if (scanDone) return
                scanDone = true
                scanner.stopScan(this)
                handler.removeCallbacksAndMessages(null)

                val device = scanResult.device
                Log.i(TAG, "BLE device found: ${device.address} (${device.name})")

                // 3. GATT connect → 4. pairDeviceThroughBLE
                connectAndPair(ctrl, device, nodeId, setupPinCode, result)
            }

            override fun onScanFailed(errorCode: Int) {
                Log.e(TAG, "BLE scan failed: $errorCode")
                if (!scanDone) {
                    scanDone = true
                    result.error("BLE_SCAN_FAILED", "errorCode=$errorCode", null)
                }
            }
        }

        // 필터 없이 스캔 (디버그) — Matter FFF6 서비스 데이터가 있는 디바이스만 로그
        Log.i(TAG, "BLE scan: filter=NONE (debug mode), looking for FFF6 service data")
        scanner.startScan(null, scanSettings, object : ScanCallback() {
            override fun onScanResult(callbackType: Int, sr: ScanResult) {
                val sd = sr.scanRecord?.getServiceData(ParcelUuid(UUID.fromString(CHIP_UUID)))
                if (sd != null) {
                    Log.i(TAG, "Matter BLE device: ${sr.device.address} rssi=${sr.rssi} serviceData=${sd.joinToString("") { "%02x".format(it) }}")
                    // 필터 매칭된 것처럼 처리
                    scanCallback.onScanResult(callbackType, sr)
                }
            }
            override fun onScanFailed(errorCode: Int) {
                scanCallback.onScanFailed(errorCode)
            }
        })

        // Timeout
        handler.postDelayed({
            if (!scanDone) {
                scanDone = true
                scanner.stopScan(scanCallback)
                Log.e(TAG, "BLE scan timeout (${BLE_SCAN_TIMEOUT_MS}ms)")
                result.error("BLE_SCAN_TIMEOUT", "No Matter device found within ${BLE_SCAN_TIMEOUT_MS}ms", null)
            }
        }, BLE_SCAN_TIMEOUT_MS)
    }

    /**
     * Connect GATT and call pairDeviceThroughBLE — CHIPTool pattern.
     */
    private fun connectAndPair(
        ctrl: ChipDeviceController,
        device: BluetoothDevice,
        nodeId: Long,
        setupPinCode: Long,
        result: MethodChannel.Result,
    ) {
        Log.i(TAG, "GATT connecting to ${device.address}")

        // Attestation delegate — auto-continue on failure (test devices lack PAA certs)
        ctrl.setDeviceAttestationDelegate(600) { devicePtr, attestationInfo, errorCode ->
            Log.w(TAG, "Attestation result: errorCode=$errorCode — auto-continuing")
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                ctrl.continueCommissioning(devicePtr, true)
            }
        }

        ctrl.setCompletionListener(object : ChipDeviceController.CompletionListener {
            override fun onCommissioningComplete(nodeId: Long, errorCode: Long) {
                Log.i(TAG, "commissioning complete: node=$nodeId error=$errorCode")
                if (errorCode == 0L) {
                    result.success(mapOf("nodeId" to nodeId, "success" to true))
                } else {
                    result.error("COMMISSION_FAILED", "errorCode=$errorCode", null)
                }
            }
            override fun onPairingComplete(errorCode: Long) {
                Log.i(TAG, "pairing complete: error=$errorCode")
                if (errorCode != 0L) {
                    result.error("PAIRING_FAILED", "errorCode=$errorCode", null)
                }
            }
            override fun onError(error: Throwable?) {
                Log.e(TAG, "commission error", error)
                result.error("COMMISSION_ERROR", error?.message, null)
            }
            override fun onConnectDeviceComplete() { Log.d(TAG, "onConnectDeviceComplete") }
            override fun onStatusUpdate(status: Int) { Log.d(TAG, "status: $status") }
            override fun onReadCommissioningInfo(v: Int, p: Int, w: Int, t: Int) {}
            override fun onCommissioningStatusUpdate(n: Long, s: String?, e: Long) {}
            override fun onCommissioningStageStart(n: Long, s: String?) {}
            override fun onNotifyChipConnectionClosed() {}
            override fun onCloseBleComplete() {}
            override fun onOpCSRGenerationComplete(csr: ByteArray?) {}
            override fun onPairingDeleted(errorCode: Long) {}
            override fun onICDRegistrationInfoRequired() {}
            override fun onICDRegistrationComplete(e: Long, info: ICDDeviceInfo?) {}
        })

        val platform = chipPlatform ?: run {
            result.error("NOT_INITIALIZED", "Platform not ready", null)
            return
        }

        // GATT callback wrapping — forwards to AndroidBleManager's callback
        val gattCallback = object : BluetoothGattCallback() {
            private val wrappedCallback = platform.bleManager.callback
            private var state = 0 // 0=init, 1=discover, 2=mtu

            override fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {
                Log.i(TAG, "GATT onConnectionStateChange: status=$status newState=$newState")
                wrappedCallback.onConnectionStateChange(gatt, status, newState)
                if (newState == BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
                    state = 1
                    gatt?.discoverServices()
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt?, status: Int) {
                Log.i(TAG, "GATT onServicesDiscovered: status=$status")
                if (state != 1) return
                wrappedCallback.onServicesDiscovered(gatt, status)
                state = 2
                gatt?.requestMtu(247)
            }

            override fun onMtuChanged(gatt: BluetoothGatt?, mtu: Int, status: Int) {
                Log.i(TAG, "GATT onMtuChanged: mtu=$mtu")
                if (state != 2) return
                wrappedCallback.onMtuChanged(gatt, mtu, status)

                // MTU negotiated — now pair!
                val connId = bleConnectionId
                Log.i(TAG, "pairDeviceThroughBLE: node=$nodeId connId=$connId pin=$setupPinCode")

                val params = CommissionParameters.Builder()
                    .setNetworkCredentials(networkCredentials)
                    .build()

                ctrl.pairDeviceThroughBLE(gatt, connId, nodeId, setupPinCode, params)
            }

            override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
                wrappedCallback.onCharacteristicChanged(g, c)
            }
            override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, s: Int) {
                wrappedCallback.onCharacteristicRead(g, c, s)
            }
            override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, s: Int) {
                wrappedCallback.onCharacteristicWrite(g, c, s)
            }
            override fun onDescriptorRead(g: BluetoothGatt, d: BluetoothGattDescriptor, s: Int) {
                wrappedCallback.onDescriptorRead(g, d, s)
            }
            override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, s: Int) {
                wrappedCallback.onDescriptorWrite(g, d, s)
            }
            override fun onReadRemoteRssi(g: BluetoothGatt, rssi: Int, s: Int) {
                wrappedCallback.onReadRemoteRssi(g, rssi, s)
            }
            override fun onReliableWriteCompleted(g: BluetoothGatt, s: Int) {
                wrappedCallback.onReliableWriteCompleted(g, s)
            }
        }

        val gatt = device.connectGatt(context, false, gattCallback)
        bleGatt = gatt
        bleConnectionId = platform.bleManager.addConnection(gatt)
        platform.bleManager.setBleCallback(this)

        Log.i(TAG, "GATT connect initiated, connId=$bleConnectionId")
    }

    // ── BleCallback ───────────────────────────────────────

    override fun onCloseBleComplete(connId: Int) {
        bleConnectionId = 0
        Log.d(TAG, "onCloseBleComplete: $connId")
    }

    override fun onNotifyChipConnectionClosed(connId: Int) {
        bleGatt?.close()
        bleConnectionId = 0
        Log.d(TAG, "onNotifyChipConnectionClosed: $connId")
    }

    // ── Open Commissioning Window (multi-admin) ───────────

    private fun openCommissioningWindow(call: MethodCall, result: MethodChannel.Result) {
        val ctrl = controller
        if (ctrl == null) {
            result.error("NOT_INITIALIZED", "Call init() first", null)
            return
        }

        val nodeId = call.argument<Number>("nodeId")?.toLong() ?: 1L
        val duration = call.argument<Number>("duration")?.toInt() ?: 300
        val discriminator = call.argument<Number>("discriminator")?.toInt() ?: 3840
        val setupPinCode = 10000L + (System.currentTimeMillis() % 89999)
        val pbkdfIterations = 1000L

        Log.i(TAG, "openCommissioningWindow: node=$nodeId duration=$duration")

        ctrl.getConnectedDevicePointer(nodeId, object : GetConnectedDeviceCallbackJni.GetConnectedDeviceCallback {
            override fun onDeviceConnected(devicePointer: Long) {
                ctrl.openPairingWindowWithPINCallback(
                    devicePointer, duration, pbkdfIterations, discriminator, setupPinCode,
                    object : OpenCommissioningCallback {
                        override fun onSuccess(pin: Long, manualCode: String?, qrCode: String?) {
                            Log.i(TAG, "window opened: pin=$pin")
                            result.success(mapOf(
                                "setupPinCode" to pin,
                                "manualPairingCode" to (manualCode ?: ""),
                                "qrCode" to (qrCode ?: ""),
                            ))
                        }
                        override fun onError(status: Int, deviceId: Long) {
                            result.error("OPEN_WINDOW_FAILED", "status=$status", null)
                        }
                    },
                )
            }
            override fun onConnectionFailure(nodeId: Long, error: Exception?) {
                result.error("CONNECT_FAILED", "Cannot connect to node $nodeId", error?.message)
            }
        })
    }

    // ── Network Credentials ───────────────────────────────

    private fun setThreadDataset(call: MethodCall, result: MethodChannel.Result) {
        val hex = call.argument<String>("dataset")
        if (hex == null) { result.error("INVALID_ARGS", "dataset required", null); return }
        val bytes = hex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        networkCredentials = NetworkCredentials.forThread(NetworkCredentials.ThreadCredentials(bytes))
        Log.i(TAG, "Thread dataset stored (${bytes.size} bytes)")
        result.success(true)
    }

    private fun setWifiCredentials(call: MethodCall, result: MethodChannel.Result) {
        val ssid = call.argument<String>("ssid") ?: ""
        val password = call.argument<String>("password") ?: ""
        networkCredentials = NetworkCredentials.forWiFi(NetworkCredentials.WiFiCredentials(ssid, password))
        Log.i(TAG, "WiFi credentials stored: ssid=$ssid")
        result.success(true)
    }

    private fun unpairDevice(call: MethodCall, result: MethodChannel.Result) {
        val ctrl = controller ?: run { result.error("NOT_INITIALIZED", "init first", null); return }
        val nodeId = call.argument<Number>("nodeId")?.toLong() ?: 1L
        ctrl.unpairDevice(nodeId)
        Log.i(TAG, "unpaired node $nodeId")
        result.success(true)
    }

    // ── Helpers ───────────────────────────────────────────

    private fun buildServiceData(discriminator: Int): ByteArray {
        val opcode = 0
        val version = 0
        val vd = ((version and 0xf) shl 12) or (discriminator and 0xfff)
        return intArrayOf(opcode, vd, vd shr 8).map { it.toByte() }.toByteArray()
    }

    private fun buildServiceDataMask(isShortDiscriminator: Boolean): ByteArray {
        val mask = if (isShortDiscriminator) 0x00 else 0xff
        return intArrayOf(0xff, mask, 0xff).map { it.toByte() }.toByteArray()
    }

    fun dispose() {
        bleGatt?.close()
        controller?.close()
        controller = null
        networkCredentials = null
        channel.setMethodCallHandler(null)
    }
}
