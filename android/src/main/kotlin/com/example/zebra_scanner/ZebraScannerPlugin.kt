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
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
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
import java.util.Collections
import java.util.IdentityHashMap
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
    /** The reconnection attempt that waits for its connect callback. Only one runs at a time. */
    private var reconnectAttempt: ScannerDevice? = null
    /** The pairing connection that waits for its connect callback. */
    private var pairingDevice: ScannerDevice? = null
    /**
     * Every SDK device that may still hold a GATT client in Android: the connected scanner and the attempts in
     * flight. The SDK connects with autoConnect, so a device that is not released reconnects by itself and holds
     * the scanner without the app knowing. Compared by identity, as several devices can have the same address.
     */
    private val openDevices: MutableSet<ScannerDevice> = Collections.newSetFromMap(IdentityHashMap())
    private var lastEmittedState: String? = null
    private val pendingConnectResults = mutableMapOf<Int, Result>()
    private var nextPendingResultId = 0
    private val reconnectRunnable = Runnable { attemptReconnect() }

    /** The scanner is connected only while the app is in the foreground. */
    private var isInForeground = false
    private val appLifecycleObserver = object : DefaultLifecycleObserver {
        override fun onStart(owner: LifecycleOwner) = onAppForeground()
        override fun onStop(owner: LifecycleOwner) = onAppBackground()
    }

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
        /**
         * Time limit of one connect() call. The SDK's own 12 s timer ends when the link comes up, and its next one
         * starts only after the MTU answer. connect() also returns without a callback when its Bluetooth check fails
         * or a connection is already running.
         */
        private const val CONNECT_TIMEOUT_MS = 20_000L
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        appContext = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "zebra_handheld_scanner")
        channel.setMethodCallHandler(this)
        // Calls onAppForeground at once when the app is already in the foreground.
        ProcessLifecycleOwner.get().lifecycle.addObserver(appLifecycleObserver)
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

    /** Makes [device] the connected scanner. Every other connection of the plugin is released. */
    private fun adoptDevice(device: ScannerDevice) {
        openDevices.filter { it !== device }.forEach { release(it) }
        reconnectAttempt = null
        pairingDevice = null
        openDevices.add(device)
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

                // Data only from the connected scanner. Any other connection is closed, never left open.
                if (connectedDevice != null && connectedDevice !== device) {
                    log("Closing a scanner connection that sent data but is not the connected scanner")
                    release(device)
                    return@post
                }

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
                    if (!canAdopt(device) || !isInForeground) {
                        log("Closing a scanner connection that sent data but cannot be adopted")
                        release(device)
                        return@post
                    }
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
                    if (connectedDevice === device) return@post
                    if (connectedDevice == null && canAdopt(device) && isInForeground) {
                        log("A previous scanner connection came back. Adopting it")
                        adoptDevice(device)
                    } else {
                        // As on iOS: a connection the plugin does not use is closed, so it cannot hold the scanner.
                        log("Closing a scanner connection that came back but cannot be adopted")
                        release(device)
                    }
                }
            }

            override fun onDisconnected() {
                mainHandler.post {
                    // A device that was disconnected on purpose or replaced is only released.
                    if (connectedDevice !== device) {
                        release(device)
                        return@post
                    }
                    log("Scanner link lost")
                    channel.invokeMethod("onScannerConnected", false)
                    clearConnectionState()
                    release(device)
                    // Lost the scanner (distance, sleep): reconnect only to it, and only in the foreground.
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
        log("startPairing() started")

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
                log("Location services are disabled, prompting user to enable them")
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
            log("startPairing() ignored because a previous call is still running")

            // Return cached QR if available
            lastBleQrCode?.let {
                log("Returning cached QR code while call is already running")
                result.success(it)
                return
            }

            result.error("BUSY", "startPairing is already running", null)
            return
        }

        isAutoConnectBleRunning = true

        try {
            // Clean previous device state before requesting a new QR
            if (connectedDevice != null) {
                log("Disconnecting previous connected device before generating QR")
                clearConnectionState()
            }
            // Pairing replaces the reconnection to the old scanner.
            stopReconnect()
            pairingDevice = null
            // Also closes the previous scanner and a previous pairing connection.
            releaseAll()

            val qrCode = ScannerAutoService.ble({ success, device ->
                log("BLE callback triggered. success=$success device=$device")

                mainHandler.post {
                    if (!isPairing) {
                        log("BLE callback ignored: pairing was cancelled")
                        return@post
                    }
                    if (success && device != null) {
                        log("Device found. Creating ScannerBleDevice")

                        val scanner = ScannerBleDevice.from(device) as ScannerDevice
                        pairingDevice = scanner

                        log("Attempting to connect to device")
                        connectWithTimeout(scanner) { connectSuccess ->
                            if (pairingDevice !== scanner) {
                                // Pairing was cancelled or started again while connecting.
                                release(scanner)
                                return@connectWithTimeout
                            }
                            pairingDevice = null
                            isPairing = false
                            if (connectSuccess && isInForeground) {
                                log("Device connected successfully")
                                adoptDevice(scanner)
                            } else if (connectSuccess) {
                                log("Device connected in the background. Reconnecting in the foreground")
                                deferToForeground(scanner)
                            } else {
                                log("Device connection FAILED")
                                release(scanner)
                                channel.invokeMethod("onScannerConnected", false)
                                emitStateIfChanged()
                            }
                        }
                    } else {
                        log("BLE scan failed or device is null")
                        isPairing = false
                        channel.invokeMethod("onScannerConnected", false)
                        emitStateIfChanged()
                    }
                }
            }, { step ->
                log("AutoConnect step received: $step")

                mainHandler.post {
                    channel.invokeMethod("onPairingStep", step)
                }
            })

            log("ScannerAutoService.ble() returned qrCode = $qrCode")

            if (!qrCode.isNullOrBlank()) {
                log("QR Code generated successfully")
                lastBleQrCode = qrCode
                isPairing = true
                result.success(qrCode)
            } else if (!lastBleQrCode.isNullOrBlank()) {
                log("SDK returned null QR. Returning cached QR code instead")
                isPairing = true
                result.success(lastBleQrCode)
            } else {
                Log.e(TAG, "QR_ERROR: SDK returned null and no cached QR code exists")
                result.error("QR_ERROR", "Failed to generate BLE auto-connect QR code", null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Exception inside startPairing()", e)

            if (!lastBleQrCode.isNullOrBlank()) {
                log("Returning cached QR code after exception")
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
        // A pairing connection still in flight would otherwise connect later, unseen.
        pairingDevice?.let { release(it) }
        pairingDevice = null
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
        if (reconnectAttempt == null) {
            mainHandler.removeCallbacks(reconnectRunnable)
            attemptReconnect()
        }
        emitStateIfChanged()
    }

    private fun attemptReconnect() {
        val mac = reconnectMac ?: return
        // In the background the reconnection waits: onAppForeground starts it again.
        if (connectedDevice != null || reconnectAttempt != null || !isInForeground) return

        val bluetoothAdapter = android.bluetooth.BluetoothAdapter.getDefaultAdapter()
        if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled) {
            mainHandler.postDelayed(reconnectRunnable, RECONNECT_RETRY_MS)
            return
        }

        try {
            val scanner = ScannerBleDevice.from(bluetoothAdapter.getRemoteDevice(mac)) as ScannerDevice
            reconnectAttempt = scanner
            log("Reconnecting to the saved scanner")
            connectWithTimeout(scanner) { connectSuccess ->
                if (reconnectAttempt !== scanner) {
                    // Cancelled (stopReconnect, background) or replaced while connecting.
                    release(scanner)
                    return@connectWithTimeout
                }
                reconnectAttempt = null
                if (reconnectMac != mac || connectedDevice != null || !isInForeground) {
                    release(scanner)
                    return@connectWithTimeout
                }
                if (connectSuccess) {
                    log("Reconnected to the saved scanner")
                    adoptDevice(scanner)
                } else {
                    log("Reconnection attempt failed. Next attempt in ${RECONNECT_RETRY_MS / 1000} s")
                    release(scanner)
                    mainHandler.postDelayed(reconnectRunnable, RECONNECT_RETRY_MS)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Exception connecting to last device", e)
            reconnectAttempt?.let { release(it) }
            reconnectAttempt = null
            mainHandler.postDelayed(reconnectRunnable, RECONNECT_RETRY_MS)
        }
    }

    /** Stops the reconnection, including the attempt in flight. */
    private fun stopReconnect() {
        reconnectMac = null
        mainHandler.removeCallbacks(reconnectRunnable)
        reconnectAttempt?.let { release(it) }
        reconnectAttempt = null
        completePendingConnectResults(false)
    }

    /**
     * Connects [device] and calls [onResult] exactly once, on the main thread. The SDK may never call back, so the
     * attempt fails after [CONNECT_TIMEOUT_MS]. The device is tracked in [openDevices] until it is released.
     */
    private fun connectWithTimeout(device: ScannerDevice, onResult: (Boolean) -> Unit) {
        openDevices.add(device)
        var isDone = false
        lateinit var timeout: Runnable
        fun finish(success: Boolean) {
            if (isDone) return
            isDone = true
            mainHandler.removeCallbacks(timeout)
            onResult(success)
        }
        timeout = Runnable {
            log("Connection attempt got no answer in ${CONNECT_TIMEOUT_MS / 1000} s")
            finish(false)
        }
        mainHandler.postDelayed(timeout, CONNECT_TIMEOUT_MS)
        try {
            device.connect { connectSuccess, error ->
                log("Connect callback triggered. success=$connectSuccess error=$error")
                mainHandler.post { finish(connectSuccess) }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Exception while connecting", e)
            mainHandler.post { finish(false) }
        }
    }

    /**
     * Closes the GATT client of [device]. The vendor SDK connects with autoConnect and closes the client after a
     * link loss only for status 133, so an open client would let Android reconnect the scanner by itself, also in
     * the background, and hold it without the app knowing. The SDK's disconnect() is the only call that closes it.
     */
    private fun release(device: ScannerDevice) {
        openDevices.remove(device)
        try {
            device.onData(null)
            device.disconnect()
        } catch (e: Exception) {
            Log.e(TAG, "Error while closing the scanner connection", e)
        }
    }

    /** Releases every connection the plugin opened. */
    private fun releaseAll() {
        openDevices.toList().forEach { release(it) }
    }

    /**
     * Keeps [device] saved without keeping it connected: it finished connecting while the app was in the
     * background, so the plugin connects to it again when the app returns to the foreground.
     */
    private fun deferToForeground(device: ScannerDevice) {
        val mac = device.address
        release(device)
        if (mac != null) {
            saveDeviceMac(mac)
            reconnectMac = mac
        }
        emitStateIfChanged()
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

    // region App lifecycle

    /**
     * The app went to the background or the device was locked. The scanner is disconnected and stays saved:
     * the state is `reconnecting` until the app returns to the foreground and the scanner connects again.
     * Pairing goes on, as on iOS.
     */
    private fun onAppBackground() {
        isInForeground = false
        mainHandler.removeCallbacks(reconnectRunnable)
        // The attempt in flight would connect in the background. onAppForeground starts a new one.
        reconnectAttempt?.let { release(it) }
        reconnectAttempt = null
        val device = connectedDevice
        if (device != null) {
            log("App in the background: disconnecting the scanner")
            val mac = device.address
            clearConnectionState()
            release(device)
            if (mac != null) reconnectMac = mac
            channel.invokeMethod("onScannerConnected", false)
        } else if (reconnectMac != null) {
            log("App in the background: reconnection paused")
        }
        emitStateIfChanged()
    }

    private fun onAppForeground() {
        isInForeground = true
        if (reconnectMac == null || connectedDevice != null) return
        log("App in the foreground: reconnecting to the saved scanner")
        mainHandler.removeCallbacks(reconnectRunnable)
        attemptReconnect()
    }

    // endregion

    // region Disconnect

    private fun disconnectAll(forget: Boolean) {
        cancelPairing()
        stopReconnect()

        val device = connectedDevice
        // Also closes connections the plugin no longer uses, so none can take the scanner back.
        clearConnectionState()
        releaseAll()
        if (device != null) channel.invokeMethod("onScannerConnected", false)

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
            log("Pairing id rotated. Effective immediately: $immediate")
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
        ProcessLifecycleOwner.get().lifecycle.removeObserver(appLifecycleObserver)
        if (isPairing) {
            try {
                ScannerAutoService.stop()
            } catch (e: Exception) {
                Log.e(TAG, "Error while stopping auto connect", e)
            }
            isPairing = false
        }
        reconnectMac = null
        reconnectAttempt = null
        pairingDevice = null
        pendingConnectResults.clear()
        clearConnectionState()
        releaseAll()
        // Also drops the reconnection and the connect time limits.
        mainHandler.removeCallbacksAndMessages(null)
        appContext = null
    }

    /** Logs to logcat and sends the line to Dart (`onLog`), as the iOS plugin does. */
    private fun log(message: String) {
        Log.d(TAG, message)
        mainHandler.post {
            if (appContext != null) channel.invokeMethod("onLog", message)
        }
    }
}
