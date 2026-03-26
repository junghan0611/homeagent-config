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

        val nodeId = call.argument<Number>("nodeId")?.toLong()
        if (nodeId == null || nodeId <= 0) {
            result.error("INVALID_ARGS", "nodeId required (> 0)", null)
            return
        }
        val code = call.argument<String>("code")
        if (code.isNullOrEmpty()) {
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
        cleanupBle()
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

        // 스캔 콜백 — 단일 객체로 등록+정지 (이전: anonymous wrapper가 stopScan 누락)
        val actualScanCallback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, sr: ScanResult) {
                val sd = sr.scanRecord?.getServiceData(ParcelUuid(UUID.fromString(CHIP_UUID)))
                if (sd == null) return
                if (scanDone) return
                scanDone = true
                scanner.stopScan(this)  // this = 실제 등록된 콜백
                handler.removeCallbacksAndMessages(null)

                val device = sr.device
                Log.i(TAG, "BLE device found: ${device.address} (${device.name}) serviceData=${sd.joinToString("") { "%02x".format(it) }}")

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

        Log.i(TAG, "BLE scan: looking for Matter FFF6 service data")
        scanner.startScan(null, scanSettings, actualScanCallback)

        // Timeout
        handler.postDelayed({
            if (!scanDone) {
                scanDone = true
                scanner.stopScan(actualScanCallback)
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

        // #9: networkCredentials null 경고
        if (networkCredentials == null) {
            Log.w(TAG, "networkCredentials is null — commissioning may fail for Thread/WiFi devices")
        }

        // #8: Attestation 타임아웃을 Dart 타임아웃(120s)에 맞춤
        ctrl.setDeviceAttestationDelegate(120) { devicePtr, attestationInfo, errorCode ->
            Log.w(TAG, "Attestation result: errorCode=$errorCode — auto-continuing")
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                ctrl.continueCommissioning(devicePtr, true)
            }
        }

        // #1: result 이중 호출 방지 — MethodChannel result는 한 번만 사용 가능
        var resultSent = false
        fun sendSuccess(data: Map<String, Any>) {
            if (!resultSent) { resultSent = true; result.success(data) }
        }
        fun sendError(code: String, message: String) {
            if (!resultSent) { resultSent = true; cleanupBle(); result.error(code, message, null) }
        }

        ctrl.setCompletionListener(object : ChipDeviceController.CompletionListener {
            override fun onCommissioningComplete(nodeId: Long, errorCode: Long) {
                Log.i(TAG, "commissioning complete: node=$nodeId error=$errorCode")
                cleanupBle()
                if (errorCode == 0L) {
                    sendSuccess(mapOf("nodeId" to nodeId, "success" to true))
                } else {
                    sendError("COMMISSION_FAILED", "errorCode=$errorCode")
                }
            }
            override fun onPairingComplete(errorCode: Long) {
                Log.i(TAG, "pairing complete: error=$errorCode")
                if (errorCode != 0L) {
                    sendError("PAIRING_FAILED", "errorCode=$errorCode")
                }
            }
            override fun onError(error: Throwable?) {
                Log.e(TAG, "commission error", error)
                sendError("COMMISSION_ERROR", error?.message ?: "unknown error")
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
        var gattRetryCount = 0
        val maxGattRetries = 3

        val gattCallback = object : BluetoothGattCallback() {
            private val wrappedCallback = platform.bleManager.callback
            private var state = 0 // 0=init, 1=discover, 2=mtu

            override fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {
                Log.i(TAG, "GATT onConnectionStateChange: status=$status newState=$newState")

                // status=133 (GATT_ERROR) — Android BLE 일시적 에러, 재시도
                if (status == 133) {
                    if (gattRetryCount < maxGattRetries) {
                        gattRetryCount++
                        Log.w(TAG, "GATT status=133, retry $gattRetryCount/$maxGattRetries after 1s")
                        // #4: GATT 재시도 시 이전 연결 BleManager에서도 제거
                        gatt?.close()
                        try { platform.bleManager.removeConnection(bleConnectionId) } catch (_: Exception) {}
                        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                            val newGatt = device.connectGatt(context, false, this)
                            bleGatt = newGatt
                            bleConnectionId = platform.bleManager.addConnection(newGatt)
                            Log.i(TAG, "GATT retry connect, connId=$bleConnectionId")
                        }, 1000L)
                    } else {
                        Log.e(TAG, "GATT status=133, $maxGattRetries retries exhausted")
                        sendError("GATT_RETRY_EXHAUSTED",
                            "GATT connection failed after $maxGattRetries retries (status=133)")
                    }
                    return
                }

                // #5: GATT 실패 (non-133, non-0) — disconnected 시 명시적 에러 반환
                if (newState == BluetoothProfile.STATE_DISCONNECTED && status != BluetoothGatt.GATT_SUCCESS) {
                    Log.e(TAG, "GATT disconnected with error: status=$status")
                    sendError("GATT_FAILED", "GATT connection failed: status=$status")
                    return
                }

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
        Log.d(TAG, "onNotifyChipConnectionClosed: $connId")
        // cleanupBle()로 통일 — GATT close + BleManager removeConnection 포함
        cleanupBle()
    }

    // ── Open Commissioning Window (multi-admin) ───────────

    private fun openCommissioningWindow(call: MethodCall, result: MethodChannel.Result) {
        val ctrl = controller
        if (ctrl == null) {
            result.error("NOT_INITIALIZED", "Call init() first", null)
            return
        }

        val nodeId = call.argument<Number>("nodeId")?.toLong()
        if (nodeId == null || nodeId <= 0) {
            result.error("INVALID_ARGS", "nodeId required (> 0)", null)
            return
        }
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
                        override fun onSuccess(deviceId: Long, manualCode: String?, qrCode: String?) {
                            // onSuccess 첫 파라미터는 deviceId, PIN이 아님!
                            // setupPinCode는 openPairingWindowWithPINCallback에 넘긴 값 사용
                            Log.i(TAG, "window opened: deviceId=$deviceId setupPinCode=$setupPinCode manual=$manualCode")
                            result.success(mapOf(
                                "setupPinCode" to setupPinCode,
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
        if (hex.isNullOrEmpty()) { result.error("INVALID_ARGS", "dataset required", null); return }
        // #2: hex 파싱 방어 — 홀수 길이, 비hex 문자 체크
        if (hex.length % 2 != 0) { result.error("INVALID_ARGS", "dataset hex must be even length, got ${hex.length}", null); return }
        val bytes = try {
            hex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        } catch (e: NumberFormatException) {
            result.error("INVALID_ARGS", "dataset contains non-hex characters: ${e.message}", null)
            return
        }
        networkCredentials = NetworkCredentials.forThread(NetworkCredentials.ThreadCredentials(bytes))
        Log.i(TAG, "Thread dataset stored (${bytes.size} bytes)")
        result.success(true)
    }

    private fun setWifiCredentials(call: MethodCall, result: MethodChannel.Result) {
        // #6: 빈 ssid 방어
        val ssid = call.argument<String>("ssid")
        if (ssid.isNullOrEmpty()) { result.error("INVALID_ARGS", "ssid required", null); return }
        val password = call.argument<String>("password") ?: ""
        networkCredentials = NetworkCredentials.forWiFi(NetworkCredentials.WiFiCredentials(ssid, password))
        Log.i(TAG, "WiFi credentials stored: ssid=$ssid")
        result.success(true)
    }

    private fun unpairDevice(call: MethodCall, result: MethodChannel.Result) {
        val ctrl = controller ?: run { result.error("NOT_INITIALIZED", "init first", null); return }
        // #3: nodeId 기본값 1 제거 — null이면 에러
        val nodeId = call.argument<Number>("nodeId")?.toLong()
        if (nodeId == null || nodeId <= 0) { result.error("INVALID_ARGS", "nodeId required (> 0)", null); return }
        // #7: unpairDevice 예외 처리
        try {
            ctrl.unpairDevice(nodeId)
            Log.i(TAG, "unpaired node $nodeId")
            result.success(true)
        } catch (e: Exception) {
            Log.w(TAG, "unpairDevice($nodeId) failed: ${e.message}")
            result.error("UNPAIR_FAILED", e.message, null)
        }
    }

    // ── Helpers ───────────────────────────────────────────

    /**
     * BLE GATT + AndroidBleManager 정리.
     * OS GATT 객체를 닫고, AndroidBleManager 내부 connection 리스트에서도 제거.
     * 이전 연결이 남아있으면 2차 pairDevice 시 "connection already in use" 에러 발생.
     */
    private fun cleanupBle() {
        bleGatt?.let { gatt ->
            val connId = bleConnectionId
            Log.i(TAG, "cleanupBle: disconnect + close GATT + notify SDK, connId=$connId")
            gatt.disconnect()
            gatt.close()
            try {
                chipPlatform?.bleManager?.removeConnection(connId)
            } catch (e: Exception) {
                Log.w(TAG, "cleanupBle: removeConnection failed: ${e.message}")
            }
            // SDK 내부 BLE 상태 해제 — 이것 없으면 "Bluetooth connection already in use"
            try {
                controller?.onCloseBleComplete(connId)
                controller?.onNotifyChipConnectionClosed(connId)
            } catch (e: Exception) {
                Log.w(TAG, "cleanupBle: SDK BLE notify failed: ${e.message}")
            }
            bleGatt = null
            bleConnectionId = 0
        }
    }

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
        cleanupBle()
        controller?.close()
        controller = null
        networkCredentials = null
        channel.setMethodCallHandler(null)
    }
}
