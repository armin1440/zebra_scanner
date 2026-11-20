import 'package:flutter/material.dart';
import 'package:zebra_handheld_scanner/zebra_handheld_scanner.dart';

import '../scanner_controller.dart';
import '../widgets/barcode_preview.dart';

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key, required this.controller});

  final ScannerController controller;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final _nameController = TextEditingController();

  /// Show the setup codes and the pairing code in one QR code.
  bool _combineWithSetup = false;
  final _setupNameController = TextEditingController();

  ScannerController get c => widget.controller;

  @override
  void dispose() {
    _nameController.dispose();
    _setupNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _statusCard(context),
          _pairingCard(context),
          _reconnectCard(),
          if (c.isConnected) _deviceNameCard(),
          if (c.isConnected) _feedbackCard(),
        ],
      ),
    );
  }

  Widget _statusCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (color, icon) = switch (c.state) {
      ScannerConnectionState.connected => (
        Colors.green,
        Icons.bluetooth_connected,
      ),
      ScannerConnectionState.reconnecting => (
        Colors.orange,
        Icons.bluetooth_searching,
      ),
      ScannerConnectionState.pairing => (colors.primary, Icons.qr_code_2),
      ScannerConnectionState.idle => (colors.outline, Icons.bluetooth_disabled),
    };

    return SectionCard(
      title: 'Status',
      description: 'Platform: ${c.platformVersion}',
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                c.state.name.toUpperCase(),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            if (c.state == ScannerConnectionState.pairing && c.isConnected)
              const Chip(label: Text('Scanner still connected')),
          ],
        ),
        if (c.state == ScannerConnectionState.reconnecting) ...[
          const SizedBox(height: 8),
          const Text(
            'The saved scanner is asleep or out of range. '
            'Press the trigger to wake it. The plugin reconnects only to this scanner.',
          ),
        ],
        if (c.isConnected) ...[
          const Divider(height: 24),
          Text('Name: ${c.deviceName}'),
          Text('Version: ${c.deviceVersion}'),
          Text(
            'Battery: ${c.batteryLevel == null ? 'Unknown' : '${c.batteryLevel}%'}',
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: c.fetchDeviceInfo,
              icon: const Icon(Icons.refresh),
              label: const Text('Fetch device info'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _pairingCard(BuildContext context) {
    final isPairing = c.state == ScannerConnectionState.pairing;
    String? qrData;
    String? qrError;
    if (isPairing && c.pairingCode.isNotEmpty) {
      if (_combineWithSetup &&
          c.pairingCode.startsWith(ScannerConfigBarcode.specCodePrefix)) {
        try {
          qrData = ScannerConfigBarcode.initialSetup(
            bluetoothName: _setupNameController.text,
            pairingCode: c.pairingCode,
          );
        } on ArgumentError catch (e) {
          qrError = '${e.message}';
        }
      } else {
        qrData = c.pairingCode;
      }
    }

    return SectionCard(
      title: 'Pairing (QR4)',
      description:
          'Start pairing, then scan the QR code with the scanner. '
          'Only the scanner that reads it connects.',
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Combine with setup codes'),
          subtitle: const Text(
            'One QR: %%SpecCode93|78|AC|BA44… (reset, disable long press, BLE mode, pair)',
          ),
          value: _combineWithSetup,
          onChanged: (value) => setState(() => _combineWithSetup = value),
        ),
        if (_combineWithSetup)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: _setupNameController,
              maxLength: ScannerConfigBarcode.maxBluetoothNameBytes,
              decoration: const InputDecoration(
                labelText: 'Bluetooth name (optional)',
                helperText: 'Adds BA3E05<name> after 93',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: c.startPairing,
              icon: const Icon(Icons.qr_code),
              label: Text(isPairing ? 'Restart pairing' : 'Start pairing'),
            ),
            OutlinedButton(
              onPressed: isPairing ? c.cancelPairing : null,
              child: const Text('Cancel pairing'),
            ),
          ],
        ),
        if (qrData != null) ...[
          const SizedBox(height: 16),
          BarcodePreview(
            data: qrData,
            maxLength: _combineWithSetup
                ? ScannerConfigBarcode.maxCombinedLength
                : null,
          ),
        ],
        if (qrError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              qrError,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  Widget _reconnectCard() {
    return SectionCard(
      title: 'Reconnect / Disconnect',
      description:
          'Disconnect keeps the saved scanner. '
          'Forget also creates a new pairing token, so old scanners never match again.',
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Require token on reconnect (iOS)'),
          subtitle: const Text(
            'Reconnect only if the saved scanner still advertises this phone\'s token.',
          ),
          value: c.requireToken,
          onChanged: c.isIOS
              ? (value) => setState(() => c.requireToken = value)
              : null,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: c.isConnected ? null : () => c.reconnect(),
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('Reconnect last'),
            ),
            OutlinedButton.icon(
              onPressed: c.state == ScannerConnectionState.idle
                  ? null
                  : c.disconnect,
              icon: const Icon(Icons.link_off),
              label: const Text('Disconnect'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              onPressed: () => _confirmForget(context),
              icon: const Icon(Icons.delete_forever),
              label: const Text('Forget & disconnect'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmForget(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forget scanner?'),
        content: const Text(
          'The saved scanner and the pairing token are deleted. '
          'You must scan a new pairing QR code to connect again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (ok == true) await c.forgetScanner();
  }

  Widget _deviceNameCard() {
    return SectionCard(
      title: 'Bluetooth name',
      description:
          'Sends %%SpecCodeEC and then the name (max 16 bytes). '
          'The scanner adds the suffix (BLE, SPP, HID).',
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nameController,
                maxLength: 16,
                decoration: const InputDecoration(
                  labelText: 'New name',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                final name = _nameController.text.trim();
                if (name.isEmpty) return;
                c.run('setBluetoothName($name)', () async {
                  await c.plugin.setBluetoothName(name);
                  await Future<void>.delayed(const Duration(milliseconds: 500));
                  await c.fetchDeviceInfo();
                });
              },
              child: const Text('Set'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _feedbackCard() {
    return SectionCard(
      title: 'Hardware feedback',
      children: [
        const Text('Buzzer'),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final type in BuzzerSound.values)
              OutlinedButton(
                onPressed: () =>
                    c.run('beep(${type.name})', () => c.plugin.beep(type)),
                child: Text(type.name),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Vibrator'),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (final type in VibrationLength.values)
              OutlinedButton(
                onPressed: () => c.run(
                  'vibrate(${type.name})',
                  () => c.plugin.vibrate(type),
                ),
                child: Text(type.name),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('LED (500 ms, 2 blinks)'),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final color in LedColor.values)
              OutlinedButton(
                onPressed: () => c.run(
                  'flashLed(${color.name})',
                  () => c.plugin.flashLed(
                    color,
                    duration: const Duration(milliseconds: 500),
                    blinkCount: 2,
                  ),
                ),
                child: Text(color.name),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('"Ready" signal (after reconnect)'),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () => c.run('ready signal', () async {
              await c.plugin.beep(BuzzerSound.settingCode);
              await c.plugin.flashLed(
                LedColor.blue,
                duration: const Duration(seconds: 1),
              );
            }),
            child: const Text('Beep + blue LED'),
          ),
        ),
      ],
    );
  }
}
