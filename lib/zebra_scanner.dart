import 'zebra_scanner_platform_interface.dart';
import 'package:flutter/services.dart';

/// Predefined buzzer sound types for the scanner
enum BuzzerType {
  normalScan('02'),
  settingCode('04'),
  errorAlert('06'),
  warehousePrompt('08'),
  powerOff('0b'),
  pairingFailure('0c'),
  powerOn('0d'),
  lowBattery('0e'),
  invalidSettingCode('11');

  final String hexCode;
  const BuzzerType(this.hexCode);
}

/// Predefined vibration feedback types for the scanner
enum VibratorType {
  short('01'),
  medium('02'),
  long('03');

  final String hexCode;
  const VibratorType(this.hexCode);
}

/// Predefined LED color configurations for the scanner
enum LedColor {
  red('01'),
  green('02'),
  redAndGreen('03'),
  blue('04'),
  redAndBlue('05'),
  greenAndBlue('06'),
  redGreenAndBlue('07');

  final String hexCode;
  const LedColor(this.hexCode);
}

class ZebraScanner {
  Future<String?> getPlatformVersion() {
    return ZebraScannerPlatform.instance.getPlatformVersion();
  }

  /// Requests the necessary Bluetooth and Location permissions natively.
  /// Returns [true] if all necessary permissions are granted.
  Future<bool> requestPermissions() {
    return ZebraScannerPlatform.instance.requestPermissions();
  }

  /// Initiates BLE auto-connection and returns a QR code string.
  /// Listen to the 'zebra_scanner' method channel for connection events.
  Future<String> autoConnectBle() {
    return ZebraScannerPlatform.instance.autoConnectBle();
  }

  /// Sends an arbitrary hex command string (e.g. "ba0515") to the connected scanner.
  Future<void> sendCommand(String command) {
    return ZebraScannerPlatform.instance.sendCommand(command);
  }

  /// Gets the device name of the connected scanner.
  Future<String?> getDeviceName() {
    return ZebraScannerPlatform.instance.getDeviceName();
  }

  /// Gets the version of the connected scanner.
  Future<String?> getVersion() {
    return ZebraScannerPlatform.instance.getVersion();
  }

  /// Gets the battery level (0-100) of the connected scanner.
  Future<int?> getBatteryLevel() {
    return ZebraScannerPlatform.instance.getBatteryLevel();
  }

  /// Sets a new device name for the connected scanner.
  Future<void> setDeviceName(String name) {
    return ZebraScannerPlatform.instance.setDeviceName(name);
  }

  /// Disconnects from the current scanner.
  Future<void> disconnect() {
    return ZebraScannerPlatform.instance.disconnect();
  }

  /// Sets the scanner's speaker buzzer sound type (OP_SET_SPEAKER: 0x07).
  Future<void> setBuzzer(BuzzerType type) {
    return sendCommand('ba07${type.hexCode}');
  }

  /// Sets the scanner's vibration feedback (OP_SET_VIBRATOR: 0x08).
  Future<void> setVibrator(VibratorType type) {
    return sendCommand('ba08${type.hexCode}');
  }

  /// Sets the scanner's LED color, duration, and blink count (OP_SET_LED: 0x0B).
  /// [durationMs] must be in milliseconds (e.g., 500ms = 10 units of 50ms). Max is 255 units (12750ms).
  /// [blinkCount] is the number of blinks (0 to 255).
  Future<void> setLed(LedColor color, {int durationMs = 500, int blinkCount = 1}) {
    int durationUnits = (durationMs / 50).round().clamp(0, 255);
    int blinks = blinkCount.clamp(0, 255);
    String durHex = durationUnits.toRadixString(16).padLeft(2, '0');
    String blinkHex = blinks.toRadixString(16).padLeft(2, '0');
    return sendCommand('ba0b${color.hexCode}$durHex$blinkHex');
  }

  /// Sends a specific setting configuration code to the scanner (OP_SPEC_CODE: 0x05).
  /// Automatically strips '%%SpecCode' if it is passed in, as the scanner
  /// expects just the underlying text encoded as ASCII bytes.
  Future<void> sendSpecCode(String code) {
    final cleanCode = code.replaceFirst('%%SpecCode', '');
    final hexData = cleanCode.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join('');
    return sendCommand('ba05$hexData');
  }

  /// Sends a scan head control command (OP_CMD_TO_LASER: 0x06).
  Future<void> sendLaserCommand(String command) {
    final hexData = command.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join('');
    return sendCommand('ba06$hexData');
  }

  /// Sets up a handler to listen to events from the native side
  void setListeners({
    Function(bool)? onScannerConnected,
    Function(int)? onScannerAutoConnectStep,
    Function(String)? onBarcodeScanned,
  }) {
    const MethodChannel('zebra_scanner').setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onScannerConnected':
          if (onScannerConnected != null) {
            onScannerConnected(call.arguments as bool);
          }
          break;
        case 'onScannerAutoConnectStep':
          if (onScannerAutoConnectStep != null) {
            onScannerAutoConnectStep(call.arguments as int);
          }
          break;
        case 'onBarcodeScanned':
          if (onBarcodeScanned != null) {
            onBarcodeScanned(call.arguments as String);
          }
          break;
      }
    });
  }
}
