import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebra_handheld_scanner_example/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zebra_handheld_scanner');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'getPlatformVersion':
              return 'Test 1.0';
            case 'getConnectionState':
              return 'idle';
            case 'requestPermissions':
              return true;
            case 'reconnect':
              return false;
            case 'startPairing':
              return '%%SpecCodeBA4403A1B2C3D4';
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('all tabs render', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ScannerDemoApp());
    await tester.pumpAndSettle();
    expect(find.text('Start pairing'), findsOneWidget);

    for (final label in [
      'Settings',
      'Builders',
      'Console',
      'Scans',
      'Connect',
    ]) {
      await tester.tap(find.widgetWithText(NavigationDestination, label));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('pairing shows a QR code', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ScannerDemoApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start pairing'));
    // Simulate the native state event.
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'zebra_handheld_scanner',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('onConnectionStateChanged', 'pairing'),
          ),
          (_) {},
        );
    await tester.pumpAndSettle();

    expect(find.text('%%SpecCodeBA4403A1B2C3D4'), findsWidgets);
  });

  testWidgets('settings selection builds a combined barcode', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ScannerDemoApp());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, 'Settings'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'sound');
    await tester.pumpAndSettle();
    await tester.tap(find.text('High Volume'));
    await tester.tap(find.text('Mute'));
    await tester.pumpAndSettle();

    expect(find.text('%%SpecCode97|94'), findsOneWidget);
  });
}
