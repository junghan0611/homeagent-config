package com.homeagent.homeagent

import android.bluetooth.BluetoothGatt
import android.content.Context
import android.util.Log
import chip.devicecontroller.ChipDeviceController
import chip.devicecontroller.ControllerParams
import chip.devicecontroller.GetConnectedDeviceCallbackJni
import chip.devicecontroller.NetworkCredentials
import chip.devicecontroller.OpenCommissioningCallback
import chip.platform.AndroidBleManager
import chip.platform.AndroidChipPlatform
import chip.platform.ChipMdnsCallbackImpl
import chip.platform.DiagnosticDataProviderImpl
import chip.platform.NsdManagerServiceBrowser
import chip.platform.NsdManagerServiceResolver
import chip.platform.PreferencesConfigurationManager
import chip.platform.PreferencesKeyValueStoreManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * ChipBridge — Flutter ↔ CHIP SDK Android MethodChannel bridge.
 *
 * Exposes BLE commissioning (pairDeviceWithCode) and multi-admin
 * (openCommissioningWindow) to Dart via "com.homeagent/chip" channel.
 *
 * CHIP SDK Android uses Android BLE HAL directly — no BlueZ needed.
 */
class ChipBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "ChipBridge"
        private const val CHANNEL = "com.homeagent/chip"
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private var controller: ChipDeviceController? = null
    private var platform: AndroidChipPlatform? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> initController(result)
            "pairDeviceWithCode" -> pairDeviceWithCode(call, result)
            "openCommissioningWindow" -> openCommissioningWindow(call, result)
            "setThreadDataset" -> setThreadDataset(call, result)
            "setWifiCredentials" -> setWifiCredentials(call, result)
            "unpairDevice" -> unpairDevice(call, result)
            "isInitialized" -> result.success(controller != null)
            else -> result.notImplemented()
        }
    }

    /**
     * Initialize CHIP SDK platform + device controller.
     * Must be called once before any commissioning.
     */
    private fun initController(result: MethodChannel.Result) {
        try {
            if (controller != null) {
                result.success(true)
                return
            }

            val chipPlatform = AndroidChipPlatform(
                AndroidBleManager(),
                PreferencesKeyValueStoreManager(context),
                PreferencesConfigurationManager(context),
                NsdManagerServiceResolver(context),
                NsdManagerServiceBrowser(context),
                ChipMdnsCallbackImpl(),
                DiagnosticDataProviderImpl(context),
            )
            platform = chipPlatform

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

    /**
     * BLE commission a device using setup code (QR or manual pairing code).
     * CHIP SDK handles BLE scan → BTP → PASE → network config → complete.
     *
     * args: { "nodeId": long, "code": String }
     */
    private fun pairDeviceWithCode(call: MethodCall, result: MethodChannel.Result) {
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

        Log.i(TAG, "pairDeviceWithCode: node=$nodeId code=${code.take(4)}...")

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
            }

            override fun onError(error: Throwable?) {
                Log.e(TAG, "commission error", error)
                result.error("COMMISSION_ERROR", error?.message, null)
            }

            // Unused callbacks
            override fun onStatusUpdate(status: Int) {}
            override fun onReadCommissioningInfo(
                vendorId: Int, productId: Int, wifiEndpointId: Int, threadEndpointId: Int
            ) {}
            override fun onCommissioningStatusUpdate(nodeId: Long, stage: String?, errorCode: Long) {}
            override fun onNotifyChipConnectionClosed() {}
            override fun onCloseBleComplete() {}
            override fun onOpCSRGenerationComplete(csr: ByteArray?) {}
            override fun onPairingDeleted(errorCode: Long) {}
            override fun onICDRegistrationInfoRequired() {}
            override fun onICDRegistrationComplete(errorCode: Long, icdNodeId: Long) {}
        })

        ctrl.pairDeviceWithCode(
            nodeId,
            code,
            true,   // discoverOnce
            false,  // useOnlyOnNetworkDiscovery = false → BLE 활성화
            null,   // networkCredentials set separately via setThread/WiFi
        )
    }

    /**
     * Open commissioning window for multi-admin handoff.
     * After BLE commission, call this so python-matter-server can
     * commission_on_network with the returned PIN.
     *
     * args: { "nodeId": long, "duration": int (seconds), "discriminator": int }
     */
    private fun openCommissioningWindow(call: MethodCall, result: MethodChannel.Result) {
        val ctrl = controller
        if (ctrl == null) {
            result.error("NOT_INITIALIZED", "Call init() first", null)
            return
        }

        val nodeId = call.argument<Number>("nodeId")?.toLong() ?: 1L
        val duration = call.argument<Number>("duration")?.toInt() ?: 300
        val discriminator = call.argument<Number>("discriminator")?.toInt() ?: 3840

        Log.i(TAG, "openCommissioningWindow: node=$nodeId duration=$duration")

        val setupPinCode = 10000L + (System.currentTimeMillis() % 89999)  // random 5-8 digit PIN
        val pbkdfIterations = 1000L  // PBKDF2 iteration count (min 1000)

        ctrl.getConnectedDevicePointer(nodeId, object : GetConnectedDeviceCallbackJni.GetConnectedDeviceCallback {
            override fun onDeviceConnected(devicePointer: Long) {
                // Signature: (devicePtr, duration, iteration, discriminator, setupPinCode, callback)
                ctrl.openPairingWindowWithPINCallback(
                    devicePointer,
                    duration,
                    pbkdfIterations,
                    discriminator.toLong(),
                    setupPinCode,
                    object : OpenCommissioningCallback {
                        override fun onSuccess(setupPinCode: Long, manualPairingCode: String?, qrCode: String?) {
                            Log.i(TAG, "window opened: pin=$setupPinCode")
                            result.success(mapOf(
                                "setupPinCode" to setupPinCode,
                                "manualPairingCode" to (manualPairingCode ?: ""),
                                "qrCode" to (qrCode ?: ""),
                            ))
                        }

                        override fun onError(status: Int, deviceId: Long) {
                            Log.e(TAG, "openWindow failed: status=$status")
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

    /**
     * Set Thread operational dataset for Thread device commissioning.
     * args: { "dataset": String (hex) }
     */
    private fun setThreadDataset(call: MethodCall, result: MethodChannel.Result) {
        val ctrl = controller
        if (ctrl == null) {
            result.error("NOT_INITIALIZED", "Call init() first", null)
            return
        }
        val hex = call.argument<String>("dataset")
        if (hex == null) {
            result.error("INVALID_ARGS", "dataset is required", null)
            return
        }
        val bytes = hex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        ctrl.setThreadOperationalDataset(bytes)
        Log.i(TAG, "Thread dataset set (${bytes.size} bytes)")
        result.success(true)
    }

    /**
     * Set WiFi credentials for WiFi device commissioning.
     * args: { "ssid": String, "password": String }
     */
    private fun setWifiCredentials(call: MethodCall, result: MethodChannel.Result) {
        val ctrl = controller
        if (ctrl == null) {
            result.error("NOT_INITIALIZED", "Call init() first", null)
            return
        }
        val ssid = call.argument<String>("ssid") ?: ""
        val password = call.argument<String>("password") ?: ""
        ctrl.setWiFiCredentials(ssid, password)
        Log.i(TAG, "WiFi credentials set: ssid=$ssid")
        result.success(true)
    }

    /**
     * Remove a device from this fabric.
     * args: { "nodeId": long }
     */
    private fun unpairDevice(call: MethodCall, result: MethodChannel.Result) {
        val ctrl = controller
        if (ctrl == null) {
            result.error("NOT_INITIALIZED", "Call init() first", null)
            return
        }
        val nodeId = call.argument<Number>("nodeId")?.toLong() ?: 1L
        ctrl.unpairDevice(nodeId)
        Log.i(TAG, "unpaired node $nodeId")
        result.success(true)
    }

    fun dispose() {
        controller?.close()
        controller = null
        channel.setMethodCallHandler(null)
    }
}
