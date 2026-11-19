import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebra_handheld_scanner/zebra_handheld_scanner.dart';

void main() {
  group('ScannerConfigBarcode – examples from the vendor documents', () {
    test('combine', () {
      expect(
        ScannerConfigBarcode.combine([
          '%%SpecCode97',
          '%%SpecCode77',
          '%%SpecCodeAB',
        ]),
        '%%SpecCode97|77|AB',
      );
      expect(
        ScannerConfigBarcode.combine(['93', '78', 'AC']),
        '%%SpecCode93|78|AC',
      );
    });

    test('combineSettings', () {
      expect(
        ScannerConfigBarcode.combineSettings([
          ScannerSetting.restoreFactoryDefaults,
          ScannerSetting.disableLongPressHidDiscovery,
          ScannerSetting.bluetoothBleMode,
        ]),
        '%%SpecCode93|78|AC',
      );
    });

    test('initialSetup', () {
      expect(ScannerConfigBarcode.initialSetup(), '%%SpecCode93|78|AC');
      expect(
        ScannerConfigBarcode.initialSetup(
          pairingCode: '%%SpecCodeBA440366B13FD4',
        ),
        '%%SpecCode93|78|AC|BA440366B13FD4',
      );
      expect(
        ScannerConfigBarcode.initialSetup(saveAsCustomDefaults: true),
        '%%SpecCode93|78|AC|92',
      );
    });

    test('initialSetup with a custom Bluetooth name', () {
      expect(
        ScannerConfigBarcode.initialSetup(bluetoothName: 'S-07'),
        '%%SpecCode93|78|AC|BA3E0504S-07',
      );
      // The name comes after 93 and before 92 and the pairing code.
      expect(
        ScannerConfigBarcode.initialSetup(
          bluetoothName: ' Scanner ',
          saveAsCustomDefaults: true,
          pairingCode: '%%SpecCodeBA440366B13FD4',
        ),
        '%%SpecCode93|78|AC|BA3E0507Scanner|92|BA440366B13FD4',
      );
      // Empty name is ignored.
      expect(
        ScannerConfigBarcode.initialSetup(bluetoothName: '  '),
        '%%SpecCode93|78|AC',
      );
      expect(
        () => ScannerConfigBarcode.initialSetup(bluetoothName: 'A|B'),
        throwsArgumentError,
      );
      expect(
        () => ScannerConfigBarcode.initialSetup(bluetoothName: 'x' * 17),
        throwsArgumentError,
      );
    });

    test('single-scan BA3E commands', () {
      expect(
        ScannerConfigBarcode.setPrefix('1234'),
        '%%SpecCodeBA3E000831323334',
      );
      expect(
        ScannerConfigBarcode.setSuffix('1234'),
        '%%SpecCodeBA3E010831323334',
      );
      expect(
        ScannerConfigBarcode.setGsReplacement('1'),
        '%%SpecCodeBA3E020231',
      );
      expect(
        ScannerConfigBarcode.hideLeadingCharacters(8),
        '%%SpecCodeBA3E030208',
      );
      expect(
        ScannerConfigBarcode.hideTrailingCharacters(8),
        '%%SpecCodeBA3E040208',
      );
      expect(
        ScannerConfigBarcode.setBluetoothName('Scanner'),
        '%%SpecCodeBA3E0507Scanner',
      );
      expect(
        ScannerConfigBarcode.setCustomKey(
          keyNumber: 1,
          modifier: 0x01,
          hidKeyCode: 0x04,
        ),
        '%%SpecCodeBA3E0606010104',
      );
    });
  });

  group('ScannerConfigBarcode – validation', () {
    test('combined barcode longer than 128 bytes is rejected', () {
      final codes = List.filled(60, 'AB');
      expect(() => ScannerConfigBarcode.combine(codes), throwsArgumentError);
    });

    test('non-SpecCode codes cannot be combined', () {
      expect(
        () => ScannerConfigBarcode.combine(['%%EnterSet', '97']),
        throwsArgumentError,
      );
      expect(
        () => ScannerConfigBarcode.combineSettings([
          ScannerSetting.exitSetupMode,
        ]),
        throwsArgumentError,
      );
    });

    test('empty input is rejected', () {
      expect(() => ScannerConfigBarcode.combine([]), throwsArgumentError);
      expect(() => ScannerConfigBarcode.combine(['  ']), throwsArgumentError);
    });

    test('limits', () {
      expect(
        () => ScannerConfigBarcode.setPrefix('x' * 33),
        throwsArgumentError,
      );
      expect(
        () => ScannerConfigBarcode.setBluetoothName('x' * 17),
        throwsArgumentError,
      );
      expect(
        () => ScannerConfigBarcode.hideLeadingCharacters(65),
        throwsRangeError,
      );
      expect(
        () => ScannerConfigBarcode.setCustomKeyRaw('0G'),
        throwsArgumentError,
      );
    });

    test('length byte is hexadecimal', () {
      // 16 bytes of data = 32 hex characters = 0x20.
      expect(
        ScannerConfigBarcode.setPrefix('A' * 16),
        startsWith('%%SpecCodeBA3E0020'),
      );
    });
  });

  group('ScannerSetting', () {
    test('barcodes', () {
      expect(ScannerSetting.highVolume.barcode, '%%SpecCode97');
      expect(ScannerSetting.continuousScan.barcode, '%%SpecCodeBA1C01');
      expect(ScannerSetting.enterSetupMode.barcode, '%%EnterSet');
    });

    test('all SpecCode codes are hexadecimal and fit one BLE command', () {
      for (final s in ScannerSetting.values.where((s) => s.isSpecCode)) {
        expect(ScannerConfigBarcode.isHex(s.code), isTrue, reason: s.name);
        expect(
          s.code.length ~/ 2,
          lessThanOrEqualTo(ScannerConfigBarcode.maxBleSpecCodeBytes),
        );
      }
    });

    test('codes are unique', () {
      final barcodes = ScannerSetting.values.map((s) => s.barcode).toList();
      expect(barcodes.toSet().length, barcodes.length);
    });
  });

  group('BLE commands', () {
    test('specCodeCommand sends raw hex bytes (BA 05 97 for High Volume)', () {
      expect(ZebraHandheldScanner.specCodeCommand('97'), 'ba0597');
      expect(ZebraHandheldScanner.specCodeCommand('%%SpecCode97'), 'ba0597');
      expect(ZebraHandheldScanner.specCodeCommand('BA1C01'), 'ba05ba1c01');
    });

    test('specCodeCommand rejects invalid codes', () {
      expect(
        () => ZebraHandheldScanner.specCodeCommand('HighVolume'),
        throwsArgumentError,
      );
      expect(
        () => ZebraHandheldScanner.specCodeCommand('93|78'),
        throwsArgumentError,
      );
      expect(
        () => ZebraHandheldScanner.specCodeCommand('9'),
        throwsArgumentError,
      );
      expect(
        () => ZebraHandheldScanner.specCodeCommand('AB' * 19),
        throwsArgumentError,
      );
    });

    test('virtualScanCommand sends UTF-8 bytes with OP 0x04', () {
      expect(
        ZebraHandheldScanner.virtualScanCommand('%%SpecCodeAC'),
        'ba04252553706563436f64654143',
      );
    });
  });

  group('method channel', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('zebra_handheld_scanner');
    final calls = <MethodCall>[];
    final plugin = ZebraHandheldScanner();

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            switch (call.method) {
              case 'startPairing':
                return '%%SpecCodeBA4403A1B2C3D4';
              case 'reconnect':
                return true;
              case 'getConnectionState':
                return 'reconnecting';
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('startPairing passes timeout', () async {
      final code = await plugin.startPairing(
        timeout: const Duration(seconds: 30),
      );
      expect(code, '%%SpecCodeBA4403A1B2C3D4');
      expect(calls.single.arguments, {'timeoutMs': 30000});
    });

    test('reconnect passes options', () async {
      expect(
        await plugin.reconnect(
          requireToken: true,
          timeout: const Duration(seconds: 2),
        ),
        isTrue,
      );
      expect(calls.single.arguments, {'requireToken': true, 'timeoutMs': 2000});
    });

    test('getConnectionState', () async {
      expect(
        await plugin.getConnectionState(),
        ScannerConnectionState.reconnecting,
      );
    });

    test('sendSettings sends one BLE command per setting', () async {
      await plugin.sendSettings([
        ScannerSetting.highVolume,
        ScannerSetting.enterSetupMode,
      ], gap: Duration.zero);
      expect(calls.map((c) => c.method), ['sendRawCommand', 'sendRawCommand']);
      expect(calls[0].arguments, {'command': 'ba0597'});
      expect(calls[1].arguments, {
        'command': ZebraHandheldScanner.virtualScanCommand('%%EnterSet'),
      });
    });

    test('forgetScanner and cancelPairing', () async {
      await plugin.cancelPairing();
      await plugin.forgetScanner();
      expect(calls.map((c) => c.method), ['cancelPairing', 'forgetScanner']);
    });
  });
}
