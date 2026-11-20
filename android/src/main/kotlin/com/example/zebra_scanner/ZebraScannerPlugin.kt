package com.example.zebra_scanner

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
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
import java.io.File
import java.lang.reflect.Modifier
import java.util.Locale
import java.util.UUID

/** ZebraScannerPlugin */
class ZebraScannerPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.RequestPermissionsResultListener {
    private lateinit var channel: MethodChannel
    private var appContext: Context? = null
    private var connectedDevice: ScannerDevice? = null

    private var activity: Activity? = null
    private var pendingPermissionResult: Result? = null
    private val PERMISSION_REQUEST_CODE = 999
    private var lastBleQrCode: String? = null
    private var isAutoConnectBleRunning = false

    // Connection state
    private var isPairing = false
    /** MAC address of the saved scanner while the plugin tries to reconnect to it. */
    private var reconnectMac: String? = null
    private var reconnectAttemptInFlight = false
    private var lastEmittedState: String? = null
    private val pendingConnectResults = mutableMapOf<Int, Result>()
    private var nextPendingResultId = 0
    private val reconnectRunnable = Runnable { attemptReconnect() }

    private val barcodeBuffer = StringBuilder()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var isCoolingDown = false
    private val cooldownRunnable = Runnable { isCoolingDown = false }

    private val dispatchBarcodeRunnable = Runnable {
        dispatchAccumulatedBarcode()
    }

    companion object {
        private const val TAG = "BLE_AUTO"
        private const val PREFS_NAME = "ZebraScannerPrefs"
        private const val PREF_LAST_MAC = "last_device_mac"
        /** File where the vendor SDK keeps the pairing id of this installation. */
        private const val SDK_ID_FILE = "LW_AUTO_INSTALLATION"
        /** Obfuscated vendor SDK class that caches the pairing id. */
        private const val SDK_ID_HOLDER_CLASS = "lwautoif.lwautonew"
        private const val RECONNECT_RETRY_MS = 5000L
        private const val RECONNECT_AFTER_DROP_MS = 1000L
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        appContext = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "zebra_handheld_scanner")
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
            "startPairing" -> {
                startPairing(result)
            }
            "cancelPairing" -> {
                cancelPairing()
                result.success(null)
            }
            "reconnect" -> {
                reconnect(call, result)
            }
            "getConnectionState" -> {
                result.success(currentState())
            }
            "sendRawCommand" -> {
                sendRawCommand(call, result)
            }
            "getBluetoothName" -> {
                getBluetoothName(result)
            }
            "getFirmwareVersion" -> {
                getFirmwareVersion(result)
            }
            "getBatteryLevel" -> {
                getBatteryLevel(result)
            }
            "setBluetoothName" -> {
                setBluetoothName(call, result)
            }
            "disconnect" -> {
                disconnectAll(forget = false)
                result.success(null)
            }
            "forgetScanner" -> {
                disconnectAll(forget = true)
                result.success(null)
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
            } else {
                permissionsToRequest.add(Manifest.permission.ACCESS_FINE_LOCATION)
                permissionsToRequest.add(Manifest.permission.ACCESS_COARSE_LOCATION)
            }

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

    // region Preferences

    private fun prefs() = (activity ?: appContext)
        ?.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun saveDeviceMac(macAddress: String?) {
        if (macAddress == null) return
        prefs()?.edit()?.putString(PREF_LAST_MAC, macAddress)?.apply()
    }

    private fun savedDeviceMac(): String? = prefs()?.getString(PREF_LAST_MAC, null)

    // endregion

    // region State

    private fun currentState(): String = when {
        isPairing -> "pairing"
        connectedDevice != null -> "connected"
        reconnectMac != null -> "reconnecting"
        else -> "idle"
    }

    private fun emitStateIfChanged() {
        val state = currentState()
        if (state == lastEmittedState) return
        lastEmittedState = state
        channel.invokeMethod("onConnectionStateChanged", state)
    }

    // endregion

    private fun clearConnectionState() {
        connectedDevice = null
        barcodeBuffer.setLength(0)
        mainHandler.removeCallbacks(dispatchBarcodeRunnable)
        mainHandler.removeCallbacks(cooldownRunnable)
        isCoolingDown = false
    }

    private fun dispatchAccumulatedBarcode() {
        mainHandler.removeCallbacks(dispatchBarcodeRunnable)
        val finalBarcode = barcodeBuffer.toString().replace("\r", "").replace("\n", "").trim()
        barcodeBuffer.setLength(0) // Clear the buffer

        if (finalBarcode.isNotEmpty() && finalBarcode != "�") {
            channel.invokeMethod("onBarcodeScanned", finalBarcode)

            // Ignore trailing packets or repeated scans for 1.5 seconds
            isCoolingDown = true
            mainHandler.removeCallbacks(cooldownRunnable)
            mainHandler.postDelayed(cooldownRunnable, 1500)
        }
    }

    /** Makes [device] the connected scanner. */
    private fun adoptDevice(device: ScannerDevice) {
        connectedDevice = device
        saveDeviceMac(device.address)
        reconnectMac = null
        mainHandler.removeCallbacks(reconnectRunnable)
        setupDeviceDataListener(device)
        completePendingConnectResults(true)
        channel.invokeMethod("onScannerConnected", true)
        emitStateIfChanged()
    }

    /**
     * True if [device] may become the connected scanner without a new pairing:
     * it must be the saved scanner. A forgotten scanner is never adopted again.
     */
    private fun canAdopt(device: ScannerDevice): Boolean {
        val mac = device.address ?: return false
        return !isPairing && mac == savedDeviceMac()
    }

    private fun setupDeviceDataListener(device: ScannerDevice) {
        device.onData { _, str ->
            mainHandler.post {
                if (str == null) return@post
                val text = str as? String ?: return@post

                // Data only from the connected scanner.
                if (connectedDevice != null && connectedDevice !== device) return@post

                val cleanedChunk = text.replace("\r", "").replace("\n", "").trim()

                // Ignore the automatic scan artifact from the scanner
                if (cleanedChunk.length == 2 && cleanedChunk.startsWith("�")) {
                    return@post
                }
                if (cleanedChunk == "�") {
                    return@post
                }

                // If we receive data, the device is definitely connected
                if (connectedDevice == null) {
                    if (!canAdopt(device)) return@post
                    adoptDevice(device)
                }

                if (isCoolingDown) {
                    return@post
                }

                // Append the chunk to the barcode buffer
                barcodeBuffer.append(text)

                mainHandler.removeCallbacks(dispatchBarcodeRunnable)
                // Use a 250ms debounce window. This is the "silence timeout" between
                // BLE packets. 250ms is long enough to keep a single scan together,
                // but short enough to fire BEFORE a second physical scan begins.
                mainHandler.postDelayed(dispatchBarcodeRunnable, 250)
            }
        }
        device.onState(object : ScannerDevice.StateCallback() {
            override fun onConnected() {
                mainHandler.post {
                    if (connectedDevice == null && canAdopt(device)) {
                        adoptDevice(device)
                    }
                }
            }

            override fun onDisconnected() {
                mainHandler.post {
                    // A device that was disconnected on purpose or replaced is ignored.
                    if (connectedDevice !== device) return@post
                    channel.invokeMethod("onScannerConnected", false)
                    clearConnectionState()
                    // Lost the scanner (distance, sleep): reconnect only to it.
                    val mac = device.address
                    if (mac != null && !isPairing) {
                        reconnectMac = mac
                        mainHandler.removeCallbacks(reconnectRunnable)
                        mainHandler.postDelayed(reconnectRunnable, RECONNECT_AFTER_DROP_MS)
                    }
                    emitStateIfChanged()
                }
            }
        })
    }

    private fun startPairing(result: Result) {
        Log.d(TAG, "startPairing() started")

        val currentActivity = activity
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S && currentActivity != null) {
            val locationManager = currentActivity.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            val isLocationEnabled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                locationManager.isLocationEnabled
            } else {
                val mode = Settings.Secure.getInt(currentActivity.contentResolver, Settings.Secure.LOCATION_MODE, Settings.Secure.LOCATION_MODE_OFF)
                mode != Settings.Secure.LOCATION_MODE_OFF
            }

            if (!isLocationEnabled) {
                Log.w(TAG, "Location services are disabled, prompting user to enable them")
                try {
                    currentActivity.startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
                } catch (e: Exception) {
                    currentActivity.startActivity(Intent(Settings.ACTION_SETTINGS))
                }
                result.error("LOCATION_DISABLED", "Location services are disabled. Please enable them and try again.", null)
                return
            }
        }

        if (isAutoConnectBleRunning) {
            Log.w(TAG, "startPairing() ignored because a previous call is still running")

            // Return cached QR if available
            lastBleQrCode?.let {
                Log.d(TAG, "Returning cached QR code while call is already running")
                result.success(it)
                return
            }

            result.error("BUSY", "startPairing is already running", null)
            return
        }

        isAutoConnectBleRunning = true

        try {
            // Clean previous device state before requesting a new QR
            connectedDevice?.let { device ->
                try {
                    Log.d(TAG, "Disconnecting previous connected device before generating QR")
                    device.onData(null)
                    device.disconnect()
                } catch (e: Exception) {
                    Log.e(TAG, "Error while disconnecting previous device", e)
                } finally {
                    clearConnectionState()
                }
            }
            // Pairing replaces the reconnection to the old scanner.
            stopReconnect()

            val qrCode = ScannerAutoService.ble({ success, device ->
                Log.d(TAG, "BLE callback triggered. success=$success device=$device")

                mainHandler.post {
                    if (success && device != null) {
                        Log.d(TAG, "Device found. Creating ScannerBleDevice")

                        val scanner = ScannerBleDevice.from(device)

                        Log.d(TAG, "Attempting to connect to device")
                        scanner.connect { connectSuccess, error ->
                            Log.d(TAG, "Connect callback triggered. success=$connectSuccess error=$error")

                            mainHandler.post {
                                isPairing = false
                                if (connectSuccess) {
                                    Log.d(TAG, "Device connected successfully")
                                    adoptDevice(scanner)
                                } else {
                                    Log.e(TAG, "Device connection FAILED")
                                    channel.invokeMethod("onScannerConnected", false)
                                    emitStateIfChanged()
                                }
                            }
                        }
                    } else {
                        Log.e(TAG, "BLE scan failed or device is null")
                        isPairing = false
                        channel.invokeMethod("onScannerConnected", false)
                        emitStateIfChanged()
                    }
                }
            }, { step ->
                Log.d(TAG, "AutoConnect step received: $step")

                mainHandler.post {
                    channel.invokeMethod("onPairingStep", step)
                }
            })

            Log.d(TAG, "ScannerAutoService.ble() returned qrCode = $qrCode")

            if (!qrCode.isNullOrBlank()) {
                Log.d(TAG, "QR Code generated successfully")
                lastBleQrCode = qrCode
                isPairing = true
                result.success(qrCode)
            } else if (!lastBleQrCode.isNullOrBlank()) {
                Log.w(TAG, "SDK returned null QR. Returning cached QR code instead")
                isPairing = true
                result.success(lastBleQrCode)
            } else {
                Log.e(TAG, "QR_ERROR: SDK returned null and no cached QR code exists")
                result.error("QR_ERROR", "Failed to generate BLE auto-connect QR code", null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Exception inside startPairing()", e)

            if (!lastBleQrCode.isNullOrBlank()) {
                Log.w(TAG, "Returning cached QR code after exception")
                isPairing = true
                result.success(lastBleQrCode)
            } else {
                result.error("QR_ERROR", e.message ?: "Unknown BLE auto connect error", null)
            }
        } finally {
            isAutoConnectBleRunning = false
            emitStateIfChanged()
        }
    }

    private fun cancelPairing() {
        if (!isPairing) return
        try {
            ScannerAutoService.stop()
        } catch (e: Exception) {
            Log.e(TAG, "Error while stopping auto connect", e)
        }
        isPairing = false
        emitStateIfChanged()
    }

    // region Reconnection

    private fun reconnect(call: MethodCall, result: Result) {
        val timeoutMs = call.argument<Int>("timeoutMs") ?: 5000

        val macAddress = savedDeviceMac()
        if (macAddress == null) {
            result.success(false)
            return
        }

        val current = connectedDevice
        if (current != null && current.address == macAddress) {
            result.success(true)
            return
        }

        val bluetoothAdapter = android.bluetooth.BluetoothAdapter.getDefaultAdapter()
        if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled) {
            result.success(false)
            return
        }

        reconnectMac = macAddress
        addPendingConnectResult(result, timeoutMs)
        // Only one connection attempt at a time. Repeated calls wait for it.
        if (!reconnectAttemptInFlight) {
            mainHandler.removeCallbacks(reconnectRunnable)
            attemptReconnect()
        }
        emitStateIfChanged()
    }

    private fun attemptReconnect() {
        val mac = reconnectMac ?: return
        if (connectedDevice != null || reconnectAttemptInFlight) return

        val bluetoothAdapter = android.bluetooth.BluetoothAdapter.getDefaultAdapter()
        if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled) {
            mainHandler.postDelayed(reconnectRunnable, RECONNECT_RETRY_MS)
            return
        }

        try {
            val scanner = ScannerBleDevice.from(bluetoothAdapter.getRemoteDevice(mac)) as ScannerDevice
            reconnectAttemptInFlight = true
            scanner.connect { connectSuccess, _ ->
                mainHandler.post {
                    reconnectAttemptInFlight = false
                    if (reconnectMac != mac || connectedDevice != null) {
                        // Cancelled or replaced while connecting.
                        if (connectSuccess && connectedDevice !== scanner) {
                            scanner.onData(null)
                            scanner.disconnect()
                        }
                        return@post
                    }
                    if (connectSuccess) {
                        adoptDevice(scanner)
                    } else {
                        mainHandler.postDelayed(reconnectRunnable, RECONNECT_RETRY_MS)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Exception connecting to last device", e)
            reconnectAttemptInFlight = false
            mainHandler.postDelayed(reconnectRunnable, RECONNECT_RETRY_MS)
        }
    }

    private fun stopReconnect() {
        reconnectMac = null
        mainHandler.removeCallbacks(reconnectRunnable)
        completePendingConnectResults(false)
    }

    private fun addPendingConnectResult(result: Result, timeoutMs: Int) {
        val id = nextPendingResultId++
        pendingConnectResults[id] = result
        mainHandler.postDelayed({
            pendingConnectResults.remove(id)?.success(false)
        }, timeoutMs.toLong().coerceAtLeast(0))
    }

    private fun completePendingConnectResults(value: Boolean) {
        val results = pendingConnectResults.values.toList()
        pendingConnectResults.clear()
        results.forEach { it.success(value) }
    }

    // endregion

    // region Disconnect

    private fun disconnectAll(forget: Boolean) {
        cancelPairing()
        stopReconnect()

        connectedDevice?.let { device ->
            connectedDevice = null
            try {
                device.onData(null)
                device.disconnect()
            } catch (e: Exception) {
                Log.e(TAG, "Error while disconnecting", e)
            }
            clearConnectionState()
            channel.invokeMethod("onScannerConnected", false)
        }

        if (forget) {
            prefs()?.edit()?.remove(PREF_LAST_MAC)?.apply()
            lastBleQrCode = null
            try {
                // The next startPairing() must create a QR code with the new id.
                ScannerAutoService.stop()
            } catch (e: Exception) {
                Log.e(TAG, "Error while stopping auto connect", e)
            }
            val immediate = rotateSdkPairingId()
            Log.d(TAG, "Pairing id rotated. Effective immediately: $immediate")
        }

        emitStateIfChanged()
    }

    /**
     * Gives this installation a new pairing id, so scanners that read the old
     * QR code never match again.
     *
     * The vendor SDK stores the id in [SDK_ID_FILE] and caches it in a lazy
     * value. The file is always rewritten. The cached value is replaced by
     * reflection when possible. Returns true if the new id is used now, false
     * if it is used after the next app start.
     */
    private fun rotateSdkPairingId(): Boolean {
        val context = appContext ?: activity?.applicationContext ?: return false
        val newUuid = UUID.randomUUID().toString()
        try {
            File(context.filesDir, SDK_ID_FILE).writeText(newUuid, Charsets.UTF_8)
        } catch (e: Exception) {
            Log.e(TAG, "Cannot write the SDK pairing id file", e)
            return false
        }
        val newId = newUuid.take(8).uppercase(Locale.ROOT)

        return try {
            val holder = Class.forName(SDK_ID_HOLDER_CLASS)
            for (field in holder.declaredFields) {
                if (!Modifier.isStatic(field.modifiers) || !Lazy::class.java.isAssignableFrom(field.type)) continue
                field.isAccessible = true
                val lazy = field.get(null) as? Lazy<*> ?: continue
                // Not read yet: the SDK reads the new file on first use.
                if (!lazy.isInitialized()) return true
                val oldValue = lazy.value
                for (valueField in lazy.javaClass.declaredFields) {
                    if (Modifier.isStatic(valueField.modifiers)) continue
                    valueField.isAccessible = true
                    if (valueField.get(lazy) === oldValue) {
                        valueField.set(lazy, newId)
                        return lazy.value == newId
                    }
                }
            }
            false
        } catch (e: Throwable) {
            Log.w(TAG, "Cannot replace the cached SDK pairing id. It changes after the next app start.", e)
            false
        }
    }

    // endregion

    private fun sendRawCommand(call: MethodCall, result: Result) {
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

    private fun getBluetoothName(result: Result) {
        val device = connectedDevice
        if (device != null) {
            device.getDeviceName { data, error ->
                mainHandler.post {
                    if (data != null) result.success(data.toString())
                    else result.error("ERROR", error?.toString() ?: "Unknown error", null)
                }
            }
        } else {
            result.error("NOT_CONNECTED", "No device connected", null)
        }
    }

    private fun getFirmwareVersion(result: Result) {
        val device = connectedDevice
        if (device != null) {
            device.getVersion { data, error ->
                mainHandler.post {
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
                mainHandler.post {
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

    private fun setBluetoothName(call: MethodCall, result: Result) {
        val name = call.argument<String>("name")
        val device = connectedDevice
        if (device != null && name != null) {
            device.setDeviceName(name)
            result.success(null)
        } else {
            result.error("INVALID_ARGS", "No device connected or name is null", null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        mainHandler.removeCallbacks(reconnectRunnable)
        reconnectMac = null
        pendingConnectResults.clear()
        connectedDevice?.onData(null)
        connectedDevice?.disconnect()
        clearConnectionState()
        appContext = null
    }
}
