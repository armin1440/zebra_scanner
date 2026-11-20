import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zebra_handheld_scanner/zebra_handheld_scanner.dart';

/// One line of the event log.
class LogEntry {
  LogEntry(this.message, {this.isError = false}) : time = DateTime.now();

  final DateTime time;
  final String message;
  final bool isError;

  String get timeLabel =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}:'
      '${time.second.toString().padLeft(2, '0')}';
}

/// Holds the scanner state for all pages of the example app.
class ScannerController extends ChangeNotifier {
  ScannerController({required this.messengerKey});

  final GlobalKey<ScaffoldMessengerState> messengerKey;
  final ZebraHandheldScanner plugin = ZebraHandheldScanner();

  String platformVersion = 'Unknown';
  ScannerConnectionState state = ScannerConnectionState.idle;
  bool isConnected = false;

  /// Content of the last pairing QR code.
  String pairingCode = '';

  String deviceName = 'Unknown';
  String deviceVersion = 'Unknown';
  int? batteryLevel;

  final List<String> barcodes = [];
  final List<LogEntry> log = [];

  bool get isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> init() async {
    plugin.setListeners(
      onScannerConnected: (connected) {
        isConnected = connected;
        _log('onScannerConnected: $connected');
        if (connected) {
          fetchDeviceInfo();
        } else {
          deviceName = 'Unknown';
          deviceVersion = 'Unknown';
          batteryLevel = null;
        }
        notifyListeners();
      },
      onConnectionStateChanged: (newState) {
        state = newState;
        if (newState == ScannerConnectionState.connected) {
          isConnected = true;
        } else if (newState != ScannerConnectionState.pairing) {
          isConnected = false;
        }
        _log('onConnectionStateChanged: ${newState.name}');
        notifyListeners();
      },
      onLog: (message) {
        _log('native: $message');
        notifyListeners();
      },
      onPairingStep: (step) {
        _log('onPairingStep: $step');
        notifyListeners();
      },
      onBarcodeScanned: (barcode) {
        barcodes.insert(0, barcode);
        _log('onBarcodeScanned: $barcode');
        notifyListeners();
      },
    );

    try {
      platformVersion = await plugin.getPlatformVersion() ?? 'Unknown';
      state = await plugin.getConnectionState();
    } on PlatformException catch (e) {
      _log('init failed: ${e.message}', isError: true);
    }
    notifyListeners();

    final granted = await plugin.requestPermissions();
    if (!granted) {
      showMessage('Bluetooth/Location permissions are not fully granted.');
      return;
    }
    await reconnect(silent: true);
  }

  /// Runs [action], logs the result, and shows errors in a SnackBar.
  Future<bool> run(String label, Future<void> Function() action) async {
    try {
      await action();
      _log(label);
      notifyListeners();
      return true;
    } on PlatformException catch (e) {
      _fail('$label failed: ${e.code} ${e.message ?? ''}');
    } on ArgumentError catch (e) {
      _fail('$label failed: ${e.message}');
    } catch (e) {
      _fail('$label failed: $e');
    }
    return false;
  }

  Future<void> startPairing() async {
    await run('startPairing', () async {
      pairingCode = await plugin.startPairing();
      _log('Pairing code: $pairingCode');
    });
  }

  Future<void> cancelPairing() => run('cancelPairing', plugin.cancelPairing);

  Future<void> reconnect({bool silent = false}) async {
    await run('reconnect', () async {
      final ok = await plugin.reconnect();
      _log('reconnect result: $ok');
      if (!silent) {
        showMessage(
          ok
              ? 'Reconnected.'
              : 'Not connected yet. The plugin keeps trying if a scanner is saved.',
        );
      }
    });
  }

  Future<void> disconnect() => run('disconnect', plugin.disconnect);

  Future<void> forgetScanner() async {
    final ok = await run('forgetScanner', plugin.forgetScanner);
    if (ok) {
      pairingCode = '';
      notifyListeners();
      showMessage('Scanner forgotten. Start pairing to get the new QR code.');
    }
  }

  Future<void> fetchDeviceInfo() async {
    try {
      deviceName = await plugin.getBluetoothName() ?? 'Unknown';
    } on PlatformException catch (e) {
      _log('getBluetoothName failed: ${e.message}', isError: true);
    }
    try {
      deviceVersion = await plugin.getFirmwareVersion() ?? 'Unknown';
    } on PlatformException catch (e) {
      _log('getFirmwareVersion failed: ${e.message}', isError: true);
    }
    try {
      batteryLevel = await plugin.getBatteryLevel();
    } on PlatformException catch (e) {
      _log('getBatteryLevel failed: ${e.message}', isError: true);
    }
    notifyListeners();
  }

  Future<void> sendSetting(ScannerSetting setting) =>
      run('sendSetting(${setting.barcode})', () => plugin.sendSetting(setting));

  void clearBarcodes() {
    barcodes.clear();
    notifyListeners();
  }

  void clearLog() {
    log.clear();
    notifyListeners();
  }

  void showMessage(String message) {
    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _fail(String message) {
    _log(message, isError: true);
    showMessage(message);
    notifyListeners();
  }

  void _log(String message, {bool isError = false}) {
    log.insert(0, LogEntry(message, isError: isError));
    if (log.length > 300) log.removeLast();
    if (kDebugMode) debugPrint('[scanner] $message');
  }
}
