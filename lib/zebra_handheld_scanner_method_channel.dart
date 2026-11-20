import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'src/connection_state.dart';
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
  Future<String> startPairing({Duration? timeout}) async {
    final result = await methodChannel.invokeMethod<String>('startPairing', {
      if (timeout != null) 'timeoutMs': timeout.inMilliseconds,
    });
    return result ?? '';
  }

  @override
  Future<void> cancelPairing() async {
    await methodChannel.invokeMethod<void>('cancelPairing');
  }

  @override
  Future<bool> reconnect({
    bool requireToken = false,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final result = await methodChannel.invokeMethod<bool>('reconnect', {
      'requireToken': requireToken,
      'timeoutMs': timeout.inMilliseconds,
    });
    return result ?? false;
  }

  @override
  Future<void> sendRawCommand(String command) async {
    await methodChannel.invokeMethod<void>('sendRawCommand', {
      'command': command,
    });
  }

  @override
  Future<String?> getBluetoothName() async {
    return await methodChannel.invokeMethod<String>('getBluetoothName');
  }

  @override
  Future<String?> getFirmwareVersion() async {
    return await methodChannel.invokeMethod<String>('getFirmwareVersion');
  }

  @override
  Future<int?> getBatteryLevel() async {
    return await methodChannel.invokeMethod<int>('getBatteryLevel');
  }

  @override
  Future<void> setBluetoothName(String name) async {
    await methodChannel.invokeMethod<void>('setBluetoothName', {'name': name});
  }

  @override
  Future<void> disconnect() async {
    await methodChannel.invokeMethod<void>('disconnect');
  }

  @override
  Future<void> forgetScanner() async {
    await methodChannel.invokeMethod<void>('forgetScanner');
  }

  @override
  Future<ScannerConnectionState> getConnectionState() async {
    final state = await methodChannel.invokeMethod<String>(
      'getConnectionState',
    );
    return ScannerConnectionState.fromName(state);
  }
}
