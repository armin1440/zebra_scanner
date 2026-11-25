import 'dart:convert';

import 'package:flutter/services.dart';

import 'src/config_barcode.dart';
import 'src/connection_state.dart';
import 'src/scanner_setting.dart';
import 'zebra_handheld_scanner_platform_interface.dart';

export 'src/config_barcode.dart';
export 'src/connection_state.dart';
export 'src/scanner_setting.dart';

/// Predefined buzzer sounds of the scanner.
enum BuzzerSound {
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
  const BuzzerSound(this.hexCode);
}

/// Predefined vibration lengths of the scanner.
enum VibrationLength {
  short('01'),
  medium('02'),
  long('03');

  final String hexCode;
  const VibrationLength(this.hexCode);
}

/// Predefined LED colors of the scanner.
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

class ZebraHandheldScanner {
  Future<String?> getPlatformVersion() {
    return ZebraHandheldScannerPlatform.instance.getPlatformVersion();
  }

  /// Requests the necessary Bluetooth and Location permissions natively.
  /// Returns [true] if all necessary permissions are granted.
  ///
  /// The plugin does not use Bluetooth before this call, so the system
  /// prompt appears only when you call it. Call it right before the first
  /// [startPairing] or [reconnect].
  ///
  /// * Android: asks for `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` (Android 12+)
  ///   or location (Android 11 and older).
  /// * iOS: shows the Bluetooth prompt the first time, then answers when
  ///   the user decides. Returns [false] when the user denied access.
  Future<bool> requestPermissions() {
    return ZebraHandheldScannerPlatform.instance.requestPermissions();
  }

  /// Starts BLE pairing and returns the content of the pairing QR code.
  ///
  /// Show the returned value as a QR code. The scanner that reads it connects
  /// to this phone. Listen to [setListeners] for connection events.
  ///
  /// * Android: the vendor SDK creates the code (`%%SpecCodeBA4403<id>`).
  /// * iOS: the code is `%%SpecCodeBA4403<token>`. The token is 4 random bytes
  ///   kept until [forgetScanner]. iOS connects only to a scanner that
  ///   advertises this token (service data `FD05` or manufacturer data
  ///   `0x0133`), the same identity check as the Android SDK.
  ///
  /// While pairing, a scanner that is already connected stays connected
  /// until a different scanner reads the code.
  ///
  /// [timeout] (iOS only, default 60 seconds) stops the pairing scan.
  /// Call this method again to restart it.
  Future<String> startPairing({Duration? timeout}) {
    return ZebraHandheldScannerPlatform.instance.startPairing(timeout: timeout);
  }

  /// Stops pairing (for example when the pairing screen closes).
  /// A connected scanner stays connected.
  Future<void> cancelPairing() {
    return ZebraHandheldScannerPlatform.instance.cancelPairing();
  }

  /// Starts reconnection to the saved scanner, and only to that scanner.
  ///
  /// Returns `true` when the scanner is connected within [timeout].
  /// Returns `false` when no scanner is saved, Bluetooth is off, or the
  /// timeout expires. After a timeout, the plugin keeps trying in the
  /// background (state [ScannerConnectionState.reconnecting]) until the
  /// scanner connects or you call [disconnect] or [forgetScanner].
  /// Calling this method again does not start a second connection.
  ///
  /// The scanner is connected only while the app is in the foreground. In the
  /// background (also when the device is locked) the plugin disconnects it and
  /// pauses the reconnection, which starts again when the app returns.
  Future<bool> reconnect({Duration timeout = const Duration(seconds: 5)}) {
    return ZebraHandheldScannerPlatform.instance.reconnect(timeout: timeout);
  }

  /// Returns the current connection state.
  Future<ScannerConnectionState> getConnectionState() {
    return ZebraHandheldScannerPlatform.instance.getConnectionState();
  }

  /// Sends raw bytes, written as a hex string (for example `ba0702`), to the
  /// connected scanner.
  Future<void> sendRawCommand(String command) {
    return ZebraHandheldScannerPlatform.instance.sendRawCommand(command);
  }

  /// Gets the Bluetooth name of the connected scanner.
  Future<String?> getBluetoothName() {
    return ZebraHandheldScannerPlatform.instance.getBluetoothName();
  }

  /// Gets the firmware version of the connected scanner.
  Future<String?> getFirmwareVersion() {
    return ZebraHandheldScannerPlatform.instance.getFirmwareVersion();
  }

  /// Gets the battery level (0-100) of the connected scanner.
  Future<int?> getBatteryLevel() {
    return ZebraHandheldScannerPlatform.instance.getBatteryLevel();
  }

  /// Sets a new Bluetooth name for the connected scanner (16 bytes maximum).
  ///
  /// The plugin sends `%%SpecCodeEC` and then the name, like the vendor SDK.
  /// The scanner adds the protocol suffix (for example `ScannerBLE`).
  Future<void> setBluetoothName(String name) {
    return ZebraHandheldScannerPlatform.instance.setBluetoothName(name);
  }

  /// Disconnects from the current scanner and stops pairing and reconnection.
  /// The saved scanner and the pairing token are kept, so
  /// [reconnect] can reconnect later.
  Future<void> disconnect() {
    return ZebraHandheldScannerPlatform.instance.disconnect();
  }

  /// Disconnects from the scanner and forgets it.
  ///
  /// The plugin also creates a new pairing token, so scanners that read the
  /// old pairing QR code can never connect again. Call [startPairing] to
  /// get the new QR code.
  ///
  /// Android: the new SDK id is used immediately when possible. Otherwise it
  /// is used after the next app start.
  Future<void> forgetScanner() {
    return ZebraHandheldScannerPlatform.instance.forgetScanner();
  }

  /// Plays a buzzer sound on the scanner (OP_SET_SPEAKER: 0x07).
  Future<void> beep(BuzzerSound sound) {
    return sendRawCommand('ba07${sound.hexCode}');
  }

  /// Vibrates the scanner (OP_SET_VIBRATOR: 0x08).
  Future<void> vibrate(VibrationLength length) {
    return sendRawCommand('ba08${length.hexCode}');
  }

  /// Flashes the scanner LED (OP_SET_LED: 0x0B).
  ///
  /// [duration] is sent in units of 50 ms, from 0 to 12750 ms.
  /// [blinkCount] is the number of blinks, from 0 to 255.
  Future<void> flashLed(
    LedColor color, {
    Duration duration = const Duration(milliseconds: 500),
    int blinkCount = 1,
  }) {
    int durationUnits = (duration.inMilliseconds / 50).round().clamp(0, 255);
    int blinks = blinkCount.clamp(0, 255);
    String durHex = durationUnits.toRadixString(16).padLeft(2, '0');
    String blinkHex = blinks.toRadixString(16).padLeft(2, '0');
    return sendRawCommand('ba0b${color.hexCode}$durHex$blinkHex');
  }

  /// Sends one configuration code over BLE (OP_SPEC_CODE: `BA 05 <data>`).
  ///
  /// [code] is the barcode content with or without `%%SpecCode`, for example
  /// `%%SpecCode97` or `97` (High Volume). The code is hexadecimal and is sent
  /// as raw bytes: `97` becomes `BA 05 97`, `BA1C01` becomes `BA 05 BA 1C 01`.
  ///
  /// Only one code per call (vendor limit). Throws [ArgumentError] if [code]
  /// contains `|`, is not hexadecimal, or is longer than 18 bytes.
  /// Use [sendSettings] to send several codes, or [sendVirtualScan] to
  /// send a combined barcode.
  Future<void> sendSpecCode(String code) {
    return sendRawCommand(specCodeCommand(code));
  }

  /// Returns the hex command that [sendSpecCode] sends for [code].
  static String specCodeCommand(String code) {
    final clean = ScannerConfigBarcode.stripPrefix(code);
    if (clean.isEmpty) {
      throw ArgumentError.value(code, 'code', 'Empty code');
    }
    if (clean.contains('|')) {
      throw ArgumentError.value(
        code,
        'code',
        'BLE accepts one code at a time. Use sendSettings() or sendVirtualScan()',
      );
    }
    if (!ScannerConfigBarcode.isHex(clean)) {
      throw ArgumentError.value(
        code,
        'code',
        'Must be hexadecimal (for example 97 for High Volume)',
      );
    }
    if (clean.length ~/ 2 > ScannerConfigBarcode.maxBleSpecCodeBytes) {
      throw ArgumentError.value(
        code,
        'code',
        'Longer than ${ScannerConfigBarcode.maxBleSpecCodeBytes} bytes',
      );
    }
    return 'ba05${clean.toLowerCase()}';
  }

  /// Sends one [ScannerSetting] over BLE.
  ///
  /// `%%SpecCode` settings use [sendSpecCode]. `%%EnterSet` and `%%ExitSet`
  /// use [sendVirtualScan].
  Future<void> sendSetting(ScannerSetting setting) {
    return setting.isSpecCode
        ? sendSpecCode(setting.code)
        : sendVirtualScan(setting.barcode);
  }

  /// Sends several settings over BLE, one after the other, with [gap]
  /// between them. The scanner accepts only one setting per BLE command.
  Future<void> sendSettings(
    Iterable<ScannerSetting> settings, {
    Duration gap = const Duration(milliseconds: 300),
  }) async {
    var first = true;
    for (final setting in settings) {
      if (!first) await Future<void>.delayed(gap);
      first = false;
      await sendSetting(setting);
    }
  }

  /// Restores the defaults (`%%SpecCode93`). If custom defaults were saved
  /// with [saveAsCustomDefaults], the scanner restores those values.
  Future<void> restoreFactoryDefaults() =>
      sendSetting(ScannerSetting.restoreFactoryDefaults);

  /// Saves all current settings as the custom defaults (`%%SpecCode92`).
  Future<void> saveAsCustomDefaults() =>
      sendSetting(ScannerSetting.saveAsCustomDefaults);

  /// Sends [content] to the scanner as if the scanner had read a barcode with
  /// this content (OP 0x04: `BA 04 <UTF-8 bytes>`).
  ///
  /// The vendor SDK uses this command internally, for example to send
  /// `%%SpecCodeBA4400|AC` and the new Bluetooth name. With it you can send
  /// a combined barcode such as `%%SpecCode93|78|AC` in one command.
  /// This command is not in the vendor documentation. Test it on your
  /// firmware.
  Future<void> sendVirtualScan(String content) {
    return sendRawCommand(virtualScanCommand(content));
  }

  /// Returns the hex command that [sendVirtualScan] sends for [content].
  static String virtualScanCommand(String content) {
    if (content.isEmpty) {
      throw ArgumentError.value(content, 'content', 'Must not be empty');
    }
    final hex = utf8
        .encode(content)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'ba04$hex';
  }

  /// Sends a command to the scan engine (OP_CMD_TO_LASER: 0x06).
  Future<void> sendScanEngineCommand(String command) {
    final hexData = command.codeUnits
        .map((c) => c.toRadixString(16).padLeft(2, '0'))
        .join('');
    return sendRawCommand('ba06$hexData');
  }

  /// Sets up a handler to listen to events from the native side.
  ///
  /// Each call replaces the handlers of the previous call.
  ///
  /// [onLog] receives debug messages of the native plugin: connection,
  /// pairing and reconnection steps (on iOS also what the reconnection scan
  /// sees). On Android the same lines also go to logcat (tag `BLE_AUTO`).
  void setListeners({
    Function(bool)? onScannerConnected,
    Function(int)? onPairingStep,
    Function(String)? onBarcodeScanned,
    Function(ScannerConnectionState)? onConnectionStateChanged,
    Function(String)? onLog,
  }) {
    const MethodChannel('zebra_handheld_scanner').setMethodCallHandler((
      call,
    ) async {
      switch (call.method) {
        case 'onScannerConnected':
          if (onScannerConnected != null) {
            onScannerConnected(call.arguments as bool);
          }
          break;
        case 'onConnectionStateChanged':
          if (onConnectionStateChanged != null) {
            onConnectionStateChanged(
              ScannerConnectionState.fromName(call.arguments as String?),
            );
          }
          break;
        case 'onPairingStep':
          if (onPairingStep != null) {
            onPairingStep(call.arguments as int);
          }
          break;
        case 'onLog':
          if (onLog != null) {
            onLog(call.arguments as String);
          }
          break;
        case 'onBarcodeScanned':
          if (onBarcodeScanned != null) {
            final String barcode = call.arguments as String;

            // Ignore automatic artifact scanned by Zebra on Android
            final cleaned = barcode
                .replaceAll('\r', '')
                .replaceAll('\n', '')
                .trim();

            if (cleaned.startsWith('\uFFFD') || cleaned.isEmpty) {
              break;
            }
            if (cleaned.length == 1 &&
                (barcode.startsWith('\n') || barcode.startsWith('\r'))) {
              break;
            }

            onBarcodeScanned(barcode);
          }
          break;
      }
    });
  }
}
