// import 'package:flutter_test/flutter_test.dart';
// import 'package:zebra_scanner/zebra_scanner.dart';
// import 'package:zebra_scanner/zebra_scanner_platform_interface.dart';
// import 'package:zebra_scanner/zebra_scanner_method_channel.dart';
// import 'package:plugin_platform_interface/plugin_platform_interface.dart';
//
// class MockZebraScannerPlatform
//     with MockPlatformInterfaceMixin
//     implements ZebraScannerPlatform {
//   @override
//   Future<String?> getPlatformVersion() => Future.value('42');
// }
//
// void main() {
//   final ZebraScannerPlatform initialPlatform = ZebraScannerPlatform.instance;
//
//   test('$MethodChannelZebraScanner is the default instance', () {
//     expect(initialPlatform, isInstanceOf<MethodChannelZebraScanner>());
//   });
//
//   test('getPlatformVersion', () async {
//     ZebraScanner zebraScannerPlugin = ZebraScanner();
//     MockZebraScannerPlatform fakePlatform = MockZebraScannerPlatform();
//     ZebraScannerPlatform.instance = fakePlatform;
//
//     expect(await zebraScannerPlugin.getPlatformVersion(), '42');
//   });
// }
