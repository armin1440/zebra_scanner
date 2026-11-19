import 'package:flutter/material.dart';

import 'pages/builders_page.dart';
import 'pages/connection_page.dart';
import 'pages/console_page.dart';
import 'pages/settings_page.dart';
import 'scanner_controller.dart';

void main() {
  runApp(const ScannerDemoApp());
}

class ScannerDemoApp extends StatefulWidget {
  const ScannerDemoApp({super.key});

  @override
  State<ScannerDemoApp> createState() => _ScannerDemoAppState();
}

class _ScannerDemoAppState extends State<ScannerDemoApp> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  late final ScannerController _controller = ScannerController(
    messengerKey: _messengerKey,
  );

  @override
  void initState() {
    super.initState();
    _controller.init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zebra Scanner Demo',
      scaffoldMessengerKey: _messengerKey,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: HomePage(controller: _controller),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final ScannerController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;

  static const _titles = [
    'Connect',
    'Settings',
    'Builders',
    'Console',
    'Scans',
  ];

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final pages = [
      ConnectionPage(controller: c),
      SettingsPage(controller: c),
      BuildersPage(controller: c),
      ConsolePage(controller: c),
      ScansPage(controller: c),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Zebra Scanner · ${_titles[_index]}'),
        actions: [
          ListenableBuilder(
            listenable: c,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                avatar: Icon(
                  c.isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                  size: 18,
                  color: c.isConnected ? Colors.green : null,
                ),
                label: Text(c.state.name),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.bluetooth), label: 'Connect'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Settings'),
          NavigationDestination(icon: Icon(Icons.build), label: 'Builders'),
          NavigationDestination(icon: Icon(Icons.terminal), label: 'Console'),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Scans',
          ),
        ],
      ),
    );
  }
}
