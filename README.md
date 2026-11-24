# zebra_handheld_scanner

A Flutter plugin for easily integrating and communicating with Zebra Bluetooth BLE/SPP handheld barcode scanners natively on iOS and Android.

This plugin abstracts away the complex underlying native Bluetooth connection logic and exposes a clean, easy-to-use Dart API to discover, connect, listen to barcode scans, and send configuration commands to Zebra scanners.

## Features

- **Auto-Connect via BLE**: Automatically scan and pair with nearby Zebra BLE scanners using a simple QR code prompt mechanism.
- **Connection State Listening**: Keep track of the active connection state of your scanner directly in Flutter.
- **Real-time Barcode Scanning**: Listen to incoming barcode data instantly as soon as a barcode is scanned.
- **Read Device Information**: Fetch connected scanner details such as its Bluetooth Name, Firmware Version, and Battery Level percentage.
- **Hardware Feedback Control**: Programmatically trigger the scanner's Buzzer, Vibrator, and LED indicator lights with predefined enums.
- **Configuration Commands**: Send deep setting codes (`SpecCode`) or raw laser commands over Bluetooth directly from your app.
- **Configuration Catalog**: Every code of the Effon V8 manual as `ScannerSetting`, ready to show as a QR code or send over BLE.
- **Barcode Builders**: Combined barcodes (`%%SpecCode93|78|AC`), one-scan setup, and single-scan `BA3E` commands (prefix, suffix, GS, hidden characters, Bluetooth name, custom key).
- **Safe Pairing and Reconnection**: Token-based pairing on iOS and Android, an ownership lock, and reconnection only to the saved scanner.

## Getting Started

### 1. Installation

Add `zebra_handheld_scanner` to your `pubspec.yaml` dependencies:

```yaml
dependencies:
  zebra_handheld_scanner: ^1.0.0
```

### 2. Permissions

The plugin automatically requests the necessary runtime permissions on both Android and iOS when you call `requestPermissions()`. Ensure you have the appropriate declarations in your platform manifest files.

#### Android (`android/app/src/main/AndroidManifest.xml`)
The necessary Bluetooth and Location permissions are bundled in the plugin's manifest. You do not need to add anything extra unless your specific use-case requires it.

#### iOS (`ios/Runner/Info.plist`)
You must include the following Bluetooth usage descriptions in your app's `Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app needs access to Bluetooth to connect to and communicate with the Zebra Scanner.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>This app needs access to Bluetooth to connect to and communicate with the Zebra Scanner.</string>
<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-central</string>
</array>
```

---

## Usage Example

### Initialization & Permissions

First, initialize the plugin and request the necessary Bluetooth permissions from the user. Set up your connection listeners so your UI updates when the scanner connects/disconnects or scans a barcode.

```dart
import 'package:zebra_handheld_scanner/zebra_handheld_scanner.dart';

final _zebraScannerPlugin = ZebraHandheldScanner();

@override
void initState() {
  super.initState();
  
  // 1. Request Bluetooth/Location permissions
  _zebraScannerPlugin.requestPermissions();
  
  // 2. Setup listeners for the scanner
  _zebraScannerPlugin.setListeners(
    onScannerConnected: (bool isConnected) {
      print(isConnected ? "Scanner Connected!" : "Scanner Disconnected");
    },
    onBarcodeScanned: (String barcode) {
      print("Scanned Barcode: $barcode");
    },
    onPairingStep: (int step) {
      print("Pairing step: $step");
    },
  );
}
```

### Connecting to a Scanner

**Pairing (QR4):**
```dart
// Returns the pairing QR content (%%SpecCodeBA4403<token>). Show it as a QR code.
// Only the scanner that reads it connects.
String pairingQr = await _zebraScannerPlugin.startPairing();

// When the pairing screen closes without a connection:
await _zebraScannerPlugin.cancelPairing();
```

On iOS the token is 4 random bytes, kept until `forgetScanner()`. iOS connects only to a scanner that advertises this token.

**Reconnect to the saved scanner:**
```dart
// true if connected within the timeout. Otherwise the plugin keeps trying,
// only with the saved scanner, until disconnect() or forgetScanner().
bool ok = await _zebraScannerPlugin.reconnect();
```

On iOS the scanner is connected only while the app is in the foreground. When the app goes to the background, the device is locked or the app terminates, the plugin disconnects the scanner (or stops the reconnection) and keeps it saved. The state is `reconnecting` until the app returns and the scanner connects again.

**Connection state:**
```dart
_zebraScannerPlugin.setListeners(
  onConnectionStateChanged: (ScannerConnectionState state) {
    // idle, pairing, reconnecting, connected
  },
);
```

**Disconnect or forget:**
```dart
await _zebraScannerPlugin.disconnect();          // keeps the saved scanner
await _zebraScannerPlugin.forgetScanner();       // new token: old scanners never match again
```

### Reading Device Info

Once connected, you can fetch metadata from the Zebra scanner:

```dart
String? name = await _zebraScannerPlugin.getBluetoothName();
String? version = await _zebraScannerPlugin.getFirmwareVersion();
int? battery = await _zebraScannerPlugin.getBatteryLevel(); // Returns 0-100 percentage
```

### Hardware Feedback & Commands

You can control the physical feedback mechanisms of the scanner directly using the provided Dart Enums.

**Buzzer:**
```dart
await _zebraScannerPlugin.beep(BuzzerSound.normalScan); // Emits a low-pitched beep
await _zebraScannerPlugin.beep(BuzzerSound.errorAlert); // Emits three rapid low-pitched beeps
```

**Vibrator:**
```dart
await _zebraScannerPlugin.vibrate(VibrationLength.short);
```

**LED:**
```dart
// Flash the Red and Green LED twice, holding for 500ms each time.
await _zebraScannerPlugin.flashLed(LedColor.redAndGreen, duration: const Duration(milliseconds: 500), blinkCount: 2);
```

**Configuration codes over BLE:**
```dart
// One code per BLE command. "97" (High Volume) is sent as BA 05 97.
await _zebraScannerPlugin.sendSetting(ScannerSetting.highVolume);
await _zebraScannerPlugin.sendSpecCode('%%SpecCodeBA1C01'); // continuous scan

// Several codes, one after the other.
await _zebraScannerPlugin.sendSettings([
  ScannerSetting.disableLongPressHidDiscovery,
  ScannerSetting.sleep30Minutes,
]);

// Save the current settings as custom defaults. %%SpecCode93 then restores them.
await _zebraScannerPlugin.saveAsCustomDefaults();
```

**Configuration barcodes (scan with the scanner):**
```dart
ScannerConfigBarcode.combine(['93', '78', 'AC']);   // %%SpecCode93|78|AC (max 128 bytes)
ScannerConfigBarcode.initialSetup(pairingCode: qr); // %%SpecCode93|78|AC|BA4403…
ScannerConfigBarcode.initialSetup(bluetoothName: 'S-07', saveAsCustomDefaults: true);
                                                    // %%SpecCode93|78|AC|BA3E0504S-07|92
ScannerConfigBarcode.setPrefix('1234');             // %%SpecCodeBA3E000831323334
ScannerConfigBarcode.hideLeadingCharacters(8);      // %%SpecCodeBA3E030208
ScannerConfigBarcode.setBluetoothName('Scanner');   // %%SpecCodeBA3E0507Scanner
```

**Virtual scan (experimental):**
```dart
// The scanner handles the text like a scanned barcode (OP 0x04).
// The vendor SDK uses this command, but it is not in the vendor documents.
await _zebraScannerPlugin.sendVirtualScan('%%SpecCode93|78|AC');
```

### Disconnecting
When you are done communicating with the device:
```dart
await _zebraScannerPlugin.disconnect();
```