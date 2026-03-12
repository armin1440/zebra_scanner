import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:zebra_handheld_scanner/zebra_handheld_scanner.dart';

void main() {
  runApp(const MaterialApp(home: MyApp()));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformVersion = 'Unknown';
  final _zebraScannerPlugin = ZebraHandheldScanner();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _specCodeController = TextEditingController();

  bool _isConnected = false;
  String _qrCodeContent = '';
  final List<String> _scannedBarcodes = [];

  String _deviceName = "Unknown";
  String _deviceVersion = "Unknown";
  int _batteryLevel = 0;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    initPlatformState();

    _zebraScannerPlugin.setListeners(
      onScannerConnected: (connected) {
        if (!mounted) return;
        setState(() {
          _isConnected = connected;
          if (connected) {
            _qrCodeContent = '';
            _fetchDeviceInfo();
          } else {
            _deviceName = "Unknown";
            _deviceVersion = "Unknown";
            _batteryLevel = 0;
          }
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(connected ? 'Scanner Auto-Connected!' : 'Scanner connection ended.')));
      },
      onScannerAutoConnectStep: (step) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Auto-connect step: $step')));
      },
      onBarcodeScanned: (barcode) {
        if (!mounted) return;
        setState(() {
          _scannedBarcodes.insert(0, barcode);
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scanned: $barcode')));
      },
    );
  }

  Future<void> _fetchDeviceInfo() async {
    try {
      final name = await _zebraScannerPlugin.getDeviceName();
      final version = await _zebraScannerPlugin.getVersion();
      final battery = await _zebraScannerPlugin.getBatteryLevel();
      if (!mounted) return;
      setState(() {
        _deviceName = name ?? "Unknown";
        _deviceVersion = version ?? "Unknown";
        _batteryLevel = battery ?? 0;
      });
    } on PlatformException catch (e) {
      if (kDebugMode) print("Failed to get info: $e");
    }
  }

  Future<void> _requestPermissions() async {
    final granted = await _zebraScannerPlugin.requestPermissions();
    if (!mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Warning: Bluetooth/Location permissions not fully granted.')));
    }
  }

  Future<void> initPlatformState() async {
    String platformVersion;
    try {
      platformVersion = await _zebraScannerPlugin.getPlatformVersion() ?? 'Unknown platform version';
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
    });
  }

  Future<void> _autoConnectBle() async {
    try {
      final qrCode = await _zebraScannerPlugin.autoConnectBle();
      if (!mounted) return;
      setState(() {
        _qrCodeContent = qrCode;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Waiting for scanner to connect via BLE...')));
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error initiating auto-connect: ${e.message}')));
    }
  }

  Future<void> _disconnect() async {
    try {
      await _zebraScannerPlugin.disconnect();
      if (!mounted) return;
      setState(() {
        _isConnected = false;
        _deviceName = "Unknown";
        _deviceVersion = "Unknown";
        _batteryLevel = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Disconnected')));
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
    }
  }

  Future<void> _setDeviceName() async {
    if (_nameController.text.trim().isEmpty) return;
    try {
      await _zebraScannerPlugin.setDeviceName(_nameController.text.trim());
      await Future.delayed(const Duration(milliseconds: 500));
      await _fetchDeviceInfo();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device name updated!')));
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
    }
  }

  Future<void> _testBuzzer() async {
    try {
      await _zebraScannerPlugin.setBuzzer(BuzzerType.normalScan);
    } on PlatformException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
    }
  }

  Future<void> _testVibrator() async {
    try {
      await _zebraScannerPlugin.setVibrator(VibratorType.short);
    } on PlatformException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
    }
  }

  Future<void> _testLed() async {
    try {
      await _zebraScannerPlugin.setLed(LedColor.redAndGreen, durationMs: 500, blinkCount: 2);
    } on PlatformException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
    }
  }

  Future<void> _sendSpecCode() async {
    if (_specCodeController.text.trim().isEmpty) return;
    try {
      await _zebraScannerPlugin.sendSpecCode(_specCodeController.text.trim());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Spec Code Sent!')));
    } on PlatformException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _specCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Zebra Scanner Demo')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Status: ${_isConnected ? "Connected" : "Disconnected"}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: _isConnected ? Colors.green : Colors.red,
                ),
              ),
              if (_isConnected)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'Name: $_deviceName | Version: $_deviceVersion | Battery: $_batteryLevel%',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(onPressed: _autoConnectBle, child: const Text('Auto Connect BLE')),
                  ElevatedButton(
                    onPressed: _isConnected ? _disconnect : null,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                    child: const Text('Disconnect', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
              if (_isConnected) ElevatedButton(onPressed: _fetchDeviceInfo, child: const Text('Fetch Device Info')),
              if (_qrCodeContent.isNotEmpty) ...[
                const SizedBox(height: 15),
                const Text('Scan this QR Code to connect:', style: TextStyle(fontWeight: FontWeight.bold)),
                SelectableText(_qrCodeContent, style: const TextStyle(color: Colors.blue)),
              ],

              if (_isConnected) ...[
                const Divider(height: 30),
                const Text('Hardware Feedback Tests', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    spacing: 12,
                    children: [
                      ElevatedButton(onPressed: _testBuzzer, child: const Text('Buzzer (Normal)')),
                      ElevatedButton(onPressed: _testVibrator, child: const Text('Vibrator (Short)')),
                      ElevatedButton(onPressed: _testLed, child: const Text('LED (Red+Green)')),
                    ],
                  ),
                ),
              ],

              const Divider(height: 30),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      enabled: _isConnected,
                      decoration: const InputDecoration(
                        labelText: 'New Device Name',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(onPressed: _isConnected ? _setDeviceName : null, child: const Text('Set Name')),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _specCodeController,
                      enabled: _isConnected,
                      decoration: const InputDecoration(
                        labelText: 'Spec Code (e.g. HighVolume)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(onPressed: _isConnected ? _sendSpecCode : null, child: const Text('Set SpecCode')),
                ],
              ),

              const Divider(height: 30),
              const Text('Scanned Barcodes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _scannedBarcodes.length,
                itemBuilder: (context, index) {
                  return Card(
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.qr_code_scanner),
                      title: Text(_scannedBarcodes[index]),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
