## 1.0.3

* iOS: the scanner is now connected only while the app is in the foreground. Before, the pending connection had no timeout, so iOS reconnected the scanner while the app was in the background or the device was locked. When the app goes to the background, the device is locked or the app terminates, the plugin now disconnects a connected scanner (`onScannerConnected(false)`) or cancels the pending reconnection. The scanner stays saved, the state is `reconnecting`, and the reconnection starts again when the app returns.

## 1.0.2

* **Breaking:** removed the `requireToken` option of `reconnect`. Android ignored it. On iOS the scanner advertises the token only in pairing mode, from a temporary address, so with `requireToken: true` it never reconnected after a disconnect. `reconnect` now always reconnects to the saved scanner without checking the token.
* Example app: removed the "Require token on reconnect (iOS)" switch.

## 1.0.1

* iOS: the plugin no longer creates its `CBCentralManager` at app launch, so the Bluetooth permission prompt no longer appears when the app starts. It appears on the first `requestPermissions` call.
* iOS: `requestPermissions` now shows the Bluetooth prompt and waits for the answer. Before, it returned `true` when the user was not asked yet, and `false` was never possible until the user had denied access.

## 1.0.0

* **Breaking:** `sendSpecCode` now sends the code as raw hex bytes (`97` → `BA 05 97`), as the vendor documents and SDK do. Non-hex values such as `HighVolume` throw `ArgumentError`.
* Added `ScannerSetting`: all configuration codes of the Effon V8 manual (plus `78`), with `sendSetting` / `sendSettings`.
* Added `ScannerConfigBarcode`: combined barcodes (`%%SpecCode93|78|AC`, max 128 bytes), one-scan setup barcode (optionally with a custom Bluetooth name and the pairing code), and single-scan `BA3E` builders (prefix, suffix, GS replacement, hide leading/trailing characters, Bluetooth name, custom key).
* Added `sendVirtualScan` (OP `0x04`), `saveAsCustomDefaults` (`92`) and `restoreFactoryDefaults` (`93`).
* Added connection states (`idle`, `pairing`, `reconnecting`, `connected`) with `onConnectionStateChanged` and `getConnectionState`.
* Added `cancelPairing` and `forgetScanner` (forgets the scanner and creates a new pairing token).
* `reconnect` (was `connectToLastDevice`) is idempotent and keeps reconnecting to the saved scanner only. New options: `requireToken` (iOS) and `timeout`.
* **Breaking:** renamed methods:
  * `autoConnectBle` → `startPairing`
  * `connectToLastDevice` → `reconnect`
  * `sendCommand` → `sendRawCommand`
  * `getDeviceName` / `setDeviceName` → `getBluetoothName` / `setBluetoothName`
  * `getVersion` → `getFirmwareVersion`
  * `setBuzzer(BuzzerType)` → `beep(BuzzerSound)`
  * `setVibrator(VibratorType)` → `vibrate(VibrationLength)`
  * `setLed(color, durationMs:)` → `flashLed(color, duration: Duration)`
  * `sendLaserCommand` → `sendScanEngineCommand`
  * `setListeners(onScannerAutoConnectStep:)` → `setListeners(onPairingStep:)`
* **Breaking:** iOS pairing QR code is now `%%SpecCodeBA4403<token>` instead of plain text. iOS connects only to the scanner that advertises the token of this phone. The old name + RSSI filter is removed.
* iOS: ownership lock. A second scanner cannot replace the connected scanner, data from other connections is ignored, and scanning stops when it is not needed.
* iOS: `reconnect` now finds the scanner by its Bluetooth address. In pairing mode the scanner advertises the token from a temporary address; afterwards it advertises from its own address, which iOS reports under a different identifier. The saved identifier was the temporary one, so `reconnect` never connected after a disconnect, with or without `requireToken`. After each connection the plugin now asks the scanner for its address (`BA 05 BA 08 03`, as the Android SDK does), and the reconnection scan matches it in the manufacturer data.
* iOS: `reconnect` also works when iOS no longer knows the saved scanner (after a reboot or a Bluetooth reset). The plugin then checks connected peripherals and scans for the saved identifier.
* iOS: new `onLog` listener in `setListeners` with debug messages of the reconnection.
* iOS: `setBluetoothName` is implemented.
* iOS: `getBluetoothName`, `getFirmwareVersion` and `getBatteryLevel` now ask the scanner with the vendor commands (`BA 09 00 58 10`, `BA 0A 00 01`, `BA 0A 00 02`), as the Android SDK does. Before, they read `CBPeripheral.name` (often nil, so "Unknown") and the standard characteristics 2A26 / 2A19, which the scanner does not have. Commands now go only to the vendor command characteristic (FEEA / 2AA2) when the scanner has it.
* Android: automatic reconnection after the scanner drops, and the SDK pairing id is rotated on `forgetScanner`.

## 0.0.13

* Added a 250ms debounce buffer to properly reconstruct fragmented barcodes over BLE.
* Added a 1.5-second cooldown after successful scans to prevent duplicate or trailing artifact scans.
* Improved connection state cleanup on disconnects for both Android and iOS.

## 0.0.12

* Added check for location services being enabled on Android 11 and below before generating BLE connection QR code, automatically prompting the user to enable it if disabled.

## 0.0.11

* Added `ACCESS_COARSE_LOCATION` permission support for Android 11 and below to fix BLE auto-connect on older Android versions (like Android 9).

## 0.0.10

* Added `connectToLastDevice` feature to automatically reconnect to the last connected scanner on both Android and iOS.

## 0.0.9

* iOS: Update BLE autoconnect to exclusively filter scanners whose Bluetooth name ends with "BLE".

## 0.0.8

* Ignore auto sent strings in onBarcodeScanned

## 0.0.7

* Return device info even after waking up from dormancy mode 

## 0.0.6

* Improved filtering for automatic invalid scan artifacts on Android

## 0.0.5

* ignored \r\n- in android

## 0.0.4

* lowered dart sdk version to 3.10.1

## 0.0.3

* Cache qr code in autoConnectBle response in Android

## 0.0.2

* Fixed channel name

## 0.0.1

* initial release
