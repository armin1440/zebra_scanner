import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'zebra_scanner_method_channel.dart';

abstract class ZebraScannerPlatform extends PlatformInterface {
  /// Constructs a ZebraScannerPlatform.
  ZebraScannerPlatform() : super(token: _token);

  static final Object _token = Object();

  static ZebraScannerPlatform _instance = MethodChannelZebraScanner();

  /// The default instance of [ZebraScannerPlatform] to use.
  ///
  /// Defaults to [MethodChannelZebraScanner].
  static ZebraScannerPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ZebraScannerPlatform] when
  /// they register themselves.
  static set instance(ZebraScannerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<bool> requestPermissions() {
    throw UnimplementedError('requestPermissions() has not been implemented.');
  }

  Future<String> autoConnectBle() {
    throw UnimplementedError('autoConnectBle() has not been implemented.');
  }

  Future<void> sendCommand(String command) {
    throw UnimplementedError('sendCommand() has not been implemented.');
  }

  Future<String?> getDeviceName() {
    throw UnimplementedError('getDeviceName() has not been implemented.');
  }

  Future<String?> getVersion() {
    throw UnimplementedError('getVersion() has not been implemented.');
  }

  Future<int?> getBatteryLevel() {
    throw UnimplementedError('getBatteryLevel() has not been implemented.');
  }

  Future<void> setDeviceName(String name) {
    throw UnimplementedError('setDeviceName() has not been implemented.');
  }

  Future<void> disconnect() {
    throw UnimplementedError('disconnect() has not been implemented.');
  }
}
