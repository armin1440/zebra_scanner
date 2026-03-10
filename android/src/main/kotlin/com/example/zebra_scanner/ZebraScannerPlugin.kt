package com.example.zebra_scanner

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import com.lwtek.scanner.auto.ScannerAutoService
import com.lwtek.scanner.ble.ScannerBleDevice
import com.lwtek.scanner.core.ScannerDevice

/** ZebraScannerPlugin */
class ZebraScannerPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.RequestPermissionsResultListener {
    private lateinit var channel: MethodChannel
    private var connectedDevice: ScannerDevice? = null

    private var activity: Activity? = null
    private var pendingPermissionResult: Result? = null
    private val PERMISSION_REQUEST_CODE = 999

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "zebra_scanner")
        channel.setMethodCallHandler(this)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${android.os.Build.VERSION.RELEASE}")
            }
            "requestPermissions" -> {
                requestPermissions(result)
            }
            "autoConnectBle" -> {
                autoConnectBle(result)
            }
            "sendCommand" -> {
                sendCommand(call, result)
            }
            "getDeviceName" -> {
                getDeviceName(result)
            }
            "getVersion" -> {
                getVersion(result)
            }
            "getBatteryLevel" -> {
                getBatteryLevel(result)
            }
            "setDeviceName" -> {
                setDeviceName(call, result)
            }
            "disconnect" -> {
                disconnect(result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun requestPermissions(result: Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("NO_ACTIVITY", "Activity is not attached", null)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val permissionsToRequest = mutableListOf<String>()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                permissionsToRequest.add(Manifest.permission.BLUETOOTH_SCAN)
                permissionsToRequest.add(Manifest.permission.BLUETOOTH_CONNECT)
            }
            permissionsToRequest.add(Manifest.permission.ACCESS_FINE_LOCATION)

            val ungrantedPermissions = permissionsToRequest.filter {
                currentActivity.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
            }

            if (ungrantedPermissions.isEmpty()) {
                result.success(true)
            } else {
                pendingPermissionResult = result
                currentActivity.requestPermissions(
                    ungrantedPermissions.toTypedArray(),
                    PERMISSION_REQUEST_CODE
                )
            }
        } else {
            result.success(true)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val allGranted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingPermissionResult?.success(allGranted)
            pendingPermissionResult = null
            return true
        }
        return false
    }

    private fun setupDeviceDataListener(device: ScannerDevice) {
        device.onData { _, str ->
            Handler(Looper.getMainLooper()).post {
                channel.invokeMethod("onBarcodeScanned", str)
            }
        }
        device.onState(object : ScannerDevice.StateCallback() {
            override fun onConnected() {
                Handler(Looper.getMainLooper()).post {
                    channel.invokeMethod("onScannerConnected", true)
                }
            }

            override fun onDisconnected() {
                Handler(Looper.getMainLooper()).post {
                    channel.invokeMethod("onScannerConnected", false)
                    connectedDevice = null
                }
            }
        })
    }

    private fun autoConnectBle(result: Result) {
        val qrCode = ScannerAutoService.ble({ success, device ->
            Handler(Looper.getMainLooper()).post {
                if (success && device != null) {
                    val scanner = ScannerBleDevice.from(device)
                    scanner.connect { connectSuccess, _ ->
                        Handler(Looper.getMainLooper()).post {
                            if (connectSuccess) {
                                connectedDevice = scanner
                                setupDeviceDataListener(scanner)
                                channel.invokeMethod("onScannerConnected", true)
                            } else {
                                channel.invokeMethod("onScannerConnected", false)
                            }
                        }
                    }
                } else {
                    channel.invokeMethod("onScannerConnected", false)
                }
            }
        }, { step ->
            Handler(Looper.getMainLooper()).post {
                channel.invokeMethod("onScannerAutoConnectStep", step)
            }
        })

        if (qrCode != null) {
            result.success(qrCode)
        } else {
            result.error("QR_ERROR", "Failed to generate BLE auto-connect QR code", null)
        }
    }

    private fun sendCommand(call: MethodCall, result: Result) {
        val command = call.argument<String>("command")
        val device = connectedDevice
        if (command != null && device != null) {
            val length = command.length
            if (length % 2 == 0) {
                val bytes = ByteArray(length / 2)
                for (i in 0 until length step 2) {
                    bytes[i / 2] = command.substring(i, i + 2).toInt(16).toByte()
                }
                device.send(bytes)
                result.success(null)
            } else {
                result.error("INVALID_FORMAT", "Command length must be even", null)
            }
        } else {
            result.error("NOT_CONNECTED", "No device connected or command is null", null)
        }
    }

    private fun getDeviceName(result: Result) {
        val device = connectedDevice
        if (device != null) {
            device.getDeviceName { data, error ->
                Handler(Looper.getMainLooper()).post {
                    if (data != null) result.success(data.toString())
                    else result.error("ERROR", error?.toString() ?: "Unknown error", null)
                }
            }
        } else {
            result.error("NOT_CONNECTED", "No device connected", null)
        }
    }

    private fun getVersion(result: Result) {
        val device = connectedDevice
        if (device != null) {
            device.getVersion { data, error ->
                Handler(Looper.getMainLooper()).post {
                    if (data != null) result.success(data.toString())
                    else result.error("ERROR", error?.toString() ?: "Unknown error", null)
                }
            }
        } else {
            result.error("NOT_CONNECTED", "No device connected", null)
        }
    }

    private fun getBatteryLevel(result: Result) {
        val device = connectedDevice
        if (device != null) {
            device.getBatteryLevel { data, error ->
                Handler(Looper.getMainLooper()).post {
                    if (data != null) {
                        result.success(data as? Int ?: data.toString().toIntOrNull() ?: 0)
                    } else {
                        result.error("ERROR", error?.toString() ?: "Unknown error", null)
                    }
                }
            }
        } else {
            result.error("NOT_CONNECTED", "No device connected", null)
        }
    }

    private fun setDeviceName(call: MethodCall, result: Result) {
        val name = call.argument<String>("name")
        val device = connectedDevice
        if (device != null && name != null) {
            device.setDeviceName(name)
            result.success(null)
        } else {
            result.error("INVALID_ARGS", "No device connected or name is null", null)
        }
    }

    private fun disconnect(result: Result) {
        val device = connectedDevice
        if (device != null) {
            device.onData(null)
            device.disconnect()
            connectedDevice = null
            result.success(null)
        } else {
            result.success(null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        connectedDevice?.onData(null)
        connectedDevice?.disconnect()
        connectedDevice = null
    }
}
