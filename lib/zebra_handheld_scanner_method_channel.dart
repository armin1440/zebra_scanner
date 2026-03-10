import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'zebra_handheld_scanner_platform_interface.dart';

/// An implementation of [ZebraHandheldScannerPlatform] that uses method channels.
class MethodChannelZebraHandheldScanner extends ZebraHandheldScannerPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('zebra_handheld_scanner');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<bool> requestPermissions() async {
    final result = await methodChannel.invokeMethod<bool>('requestPermissions');
    return result ?? false;
  }

  @override
  Future<String> autoConnectBle() async {
    final result = await methodChannel.invokeMethod<String>('autoConnectBle');
    return result ?? '';
  }

  @override
  Future<void> sendCommand(String command) async {
    await methodChannel.invokeMethod<void>(
      'sendCommand',
      {'command': command},
    );
  }

  @override
  Future<String?> getDeviceName() async {
    return await methodChannel.invokeMethod<String>('getDeviceName');
  }

  @override
  Future<String?> getVersion() async {
    return await methodChannel.invokeMethod<String>('getVersion');
  }

  @override
  Future<int?> getBatteryLevel() async {
    return await methodChannel.invokeMethod<int>('getBatteryLevel');
  }

  @override
  Future<void> setDeviceName(String name) async {
    await methodChannel.invokeMethod<void>('setDeviceName', {'name': name});
  }

  @override
  Future<void> disconnect() async {
    await methodChannel.invokeMethod<void>('disconnect');
  }
}
