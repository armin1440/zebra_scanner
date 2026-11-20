import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'src/connection_state.dart';
import 'zebra_handheld_scanner_method_channel.dart';

abstract class ZebraHandheldScannerPlatform extends PlatformInterface {
  /// Constructs a ZebraHandheldScannerPlatform.
  ZebraHandheldScannerPlatform() : super(token: _token);

  static final Object _token = Object();

  static ZebraHandheldScannerPlatform _instance =
      MethodChannelZebraHandheldScanner();

  /// The default instance of [ZebraHandheldScannerPlatform] to use.
  ///
  /// Defaults to [MethodChannelZebraHandheldScanner].
  static ZebraHandheldScannerPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ZebraHandheldScannerPlatform] when
  /// they register themselves.
  static set instance(ZebraHandheldScannerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<bool> requestPermissions() {
    throw UnimplementedError('requestPermissions() has not been implemented.');
  }

  Future<String> startPairing({Duration? timeout}) {
    throw UnimplementedError('startPairing() has not been implemented.');
  }

  Future<void> cancelPairing() {
    throw UnimplementedError('cancelPairing() has not been implemented.');
  }

  Future<bool> reconnect({
    bool requireToken = false,
    Duration timeout = const Duration(seconds: 5),
  }) {
    throw UnimplementedError('reconnect() has not been implemented.');
  }

  Future<void> sendRawCommand(String command) {
    throw UnimplementedError('sendRawCommand() has not been implemented.');
  }

  Future<String?> getBluetoothName() {
    throw UnimplementedError('getBluetoothName() has not been implemented.');
  }

  Future<String?> getFirmwareVersion() {
    throw UnimplementedError('getFirmwareVersion() has not been implemented.');
  }

  Future<int?> getBatteryLevel() {
    throw UnimplementedError('getBatteryLevel() has not been implemented.');
  }

  Future<void> setBluetoothName(String name) {
    throw UnimplementedError('setBluetoothName() has not been implemented.');
  }

  Future<void> disconnect() {
    throw UnimplementedError('disconnect() has not been implemented.');
  }

  Future<void> forgetScanner() {
    throw UnimplementedError('forgetScanner() has not been implemented.');
  }

  Future<ScannerConnectionState> getConnectionState() {
    throw UnimplementedError('getConnectionState() has not been implemented.');
  }
}
