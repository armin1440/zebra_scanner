# zebra_scanner

A Flutter plugin for easily integrating and communicating with Zebra Bluetooth BLE/SPP barcode scanners natively on iOS and Android.

This plugin abstracts away the complex underlying native Bluetooth connection logic and exposes a clean, easy-to-use Dart API to discover, connect, listen to barcode scans, and send configuration commands to Zebra scanners.

## Features

- **Auto-Connect via BLE**: Automatically scan and pair with nearby Zebra BLE scanners using a simple QR code prompt mechanism.
- **Connection State Listening**: Keep track of the active connection state of your scanner directly in Flutter.
- **Real-time Barcode Scanning**: Listen to incoming barcode data instantly as soon as a barcode is scanned.
- **Read Device Information**: Fetch connected scanner details such as its Bluetooth Name, Firmware Version, and Battery Level percentage.
- **Hardware Feedback Control**: Programmatically trigger the scanner's Buzzer, Vibrator, and LED indicator lights with predefined enums.
- **Configuration Commands**: Send deep setting codes (`SpecCode`) or raw laser commands over Bluetooth directly from your app.

## Getting Started

### 1. Installation

Add `zebra_scanner` to your `pubspec.yaml` dependencies:

```yaml
dependencies:
  zebra_scanner: ^0.0.1
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
import 'package:zebra_scanner/zebra_scanner.dart';

final _zebraScannerPlugin = ZebraScanner();

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
    onScannerAutoConnectStep: (int step) {
      print("Auto-connect step: $step");
    },
  );
}
```

### Connecting to a Scanner

You can either connect to a previously bonded scanner (Android), or initiate an Auto-Connect sequence.

**Auto Connect (BLE):**
```dart
// Initiates scanning for nearby BLE scanners.
// It returns instructions or a QR Code text string that needs to be scanned by the physical Zebra scanner to pair.
String pairingQrText = await _zebraScannerPlugin.autoConnectBle();
```

### Reading Device Info

Once connected, you can fetch metadata from the Zebra scanner:

```dart
String? name = await _zebraScannerPlugin.getDeviceName();
String? version = await _zebraScannerPlugin.getVersion();
int? battery = await _zebraScannerPlugin.getBatteryLevel(); // Returns 0-100 percentage
```

### Hardware Feedback & Commands

You can control the physical feedback mechanisms of the scanner directly using the provided Dart Enums.

**Buzzer:**
```dart
await _zebraScannerPlugin.setBuzzer(BuzzerType.normalScan); // Emits a low-pitched beep
await _zebraScannerPlugin.setBuzzer(BuzzerType.errorAlert); // Emits three rapid low-pitched beeps
```

**Vibrator:**
```dart
await _zebraScannerPlugin.setVibrator(VibratorType.short);
```

**LED:**
```dart
// Flash the Red and Green LED twice, holding for 500ms each time.
await _zebraScannerPlugin.setLed(LedColor.redAndGreen, durationMs: 500, blinkCount: 2);
```

**Custom Setting Codes:**
```dart
// Send a configuration setting code (e.g. Volume to High)
await _zebraScannerPlugin.sendSpecCode("HighVolume");
```

### Disconnecting
When you are done communicating with the device:
```dart
await _zebraScannerPlugin.disconnect();
```