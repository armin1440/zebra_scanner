import 'package:flutter/material.dart';
import 'package:zebra_handheld_scanner/zebra_handheld_scanner.dart';

import '../scanner_controller.dart';
import '../widgets/barcode_preview.dart';

/// Builders from "Aggregated Barcode Instructions" and "Airport Issue Q&A":
/// the one-scan setup barcode, single-scan BA3E commands, and free combinations.
class BuildersPage extends StatefulWidget {
  const BuildersPage({super.key, required this.controller});

  final ScannerController controller;

  @override
  State<BuildersPage> createState() => _BuildersPageState();
}

/// HID modifier byte values (the manual example uses 01 for Ctrl).
const _modifiers = <String, int>{
  'None': 0x00,
  'Ctrl': 0x01,
  'Shift': 0x02,
  'Alt': 0x04,
  'GUI / Win': 0x08,
};

class _BuildersPageState extends State<BuildersPage> {
  // Initial setup
  bool _reset = true;
  bool _disableLongPress = true;
  bool _bleMode = true;
  bool _saveDefaults = false;
  bool _includePairing = false;
  final _setupNameController = TextEditingController();

  // Single-scan command
  SingleScanFunction _function = SingleScanFunction.setPrefix;
  final _textController = TextEditingController(text: '1234');
  final _countController = TextEditingController(text: '8');
  final _keyNumberController = TextEditingController(text: '1');
  final _keyCodeController = TextEditingController(text: '04');
  int _modifier = 0x01;

  // Free combination
  final _combineController = TextEditingController(text: '93, 78, AC');

  ScannerController get c => widget.controller;

  @override
  void dispose() {
    _setupNameController.dispose();
    _textController.dispose();
    _countController.dispose();
    _keyNumberController.dispose();
    _keyCodeController.dispose();
    _combineController.dispose();
    super.dispose();
  }

  ({String? code, String? error}) _tryBuild(String Function() build) {
    try {
      return (code: build(), error: null);
    } on ArgumentError catch (e) {
      return (code: null, error: '${e.message}');
    } on FormatException catch (e) {
      return (code: null, error: e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [_initialSetupCard(), _singleScanCard(), _combineCard()],
      ),
    );
  }

  Widget _initialSetupCard() {
    final hasPairingCode = c.pairingCode.startsWith(
      ScannerConfigBarcode.specCodePrefix,
    );
    final result = _tryBuild(
      () => ScannerConfigBarcode.initialSetup(
        restoreFactoryDefaults: _reset,
        disableLongPressHidDiscovery: _disableLongPress,
        bleMode: _bleMode,
        bluetoothName: _setupNameController.text,
        saveAsCustomDefaults: _saveDefaults,
        pairingCode: _includePairing && hasPairingCode ? c.pairingCode : null,
      ),
    );

    return SectionCard(
      title: 'One-scan setup',
      description:
          'Replaces the 4 setup barcodes with one: codes separated by "|", '
          'max ${ScannerConfigBarcode.maxCombinedLength} bytes.',
      children: [
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('93 – Restore defaults'),
          value: _reset,
          onChanged: (v) => setState(() => _reset = v!),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('78 – Disable 8 s long press (HID)'),
          value: _disableLongPress,
          onChanged: (v) => setState(() => _disableLongPress = v!),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('AC – BLE mode'),
          value: _bleMode,
          onChanged: (v) => setState(() => _bleMode = v!),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _setupNameController,
          maxLength: ScannerConfigBarcode.maxBluetoothNameBytes,
          decoration: const InputDecoration(
            labelText: 'BA3E05 – Bluetooth name (optional)',
            helperText: 'Scanner adds suffix: S-07 → S-07BLE',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('92 – Save as custom defaults'),
          subtitle: const Text(
            'Then 93 keeps these settings (name, long press, …)',
          ),
          value: _saveDefaults,
          onChanged: (v) => setState(() => _saveDefaults = v!),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('BA44 – Pairing code (QR4)'),
          subtitle: Text(
            hasPairingCode
                ? c.pairingCode
                : 'Start pairing on the Connect tab first',
          ),
          value: _includePairing && hasPairingCode,
          onChanged: hasPairingCode
              ? (v) => setState(() => _includePairing = v!)
              : null,
        ),
        const SizedBox(height: 8),
        _generated(
          result,
          maxLength: ScannerConfigBarcode.maxCombinedLength,
          allowSpecCode: false,
        ),
      ],
    );
  }

  Widget _singleScanCard() {
    final result = _tryBuild(_buildSingleScan);
    final isName = _function == SingleScanFunction.setBluetoothName;

    return SectionCard(
      title: 'Single-scan command (BA3E)',
      description:
          'Settings that needed two scans: %%SpecCodeBA3E + function + length + data.',
      children: [
        DropdownButtonFormField<SingleScanFunction>(
          initialValue: _function,
          decoration: const InputDecoration(
            labelText: 'Function',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final f in SingleScanFunction.values)
              DropdownMenuItem(
                value: f,
                child: Text(
                  '${f.functionCode.toString().padLeft(2, '0')} – ${f.name}',
                ),
              ),
          ],
          onChanged: (f) => setState(() => _function = f!),
        ),
        const SizedBox(height: 12),
        ..._singleScanInputs(),
        const SizedBox(height: 12),
        _generated(result, allowSpecCode: !isName),
        if (isName)
          const Text(
            'BLE: use "Bluetooth name" on the Connect tab (setBluetoothName).',
            style: TextStyle(fontSize: 12),
          ),
      ],
    );
  }

  List<Widget> _singleScanInputs() {
    switch (_function) {
      case SingleScanFunction.setPrefix:
      case SingleScanFunction.setSuffix:
      case SingleScanFunction.setGsReplacement:
      case SingleScanFunction.setBluetoothName:
        return [
          TextField(
            controller: _textController,
            decoration: InputDecoration(
              labelText: _function == SingleScanFunction.setBluetoothName
                  ? 'Name (max 16 bytes)'
                  : 'Text',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ];
      case SingleScanFunction.hideLeadingCharacters:
      case SingleScanFunction.hideTrailingCharacters:
        return [
          TextField(
            controller: _countController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Number of characters (0–64)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ];
      case SingleScanFunction.setCustomKey:
        return [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _keyNumberController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Key number',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _modifier,
                  decoration: const InputDecoration(
                    labelText: 'Modifier',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final e in _modifiers.entries)
                      DropdownMenuItem(value: e.value, child: Text(e.key)),
                  ],
                  onChanged: (v) => setState(() => _modifier = v!),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _keyCodeController,
                  decoration: const InputDecoration(
                    labelText: 'HID key (hex)',
                    hintText: '04 = A',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ];
    }
  }

  String _buildSingleScan() {
    switch (_function) {
      case SingleScanFunction.setPrefix:
        return ScannerConfigBarcode.setPrefix(_textController.text);
      case SingleScanFunction.setSuffix:
        return ScannerConfigBarcode.setSuffix(_textController.text);
      case SingleScanFunction.setGsReplacement:
        return ScannerConfigBarcode.setGsReplacement(_textController.text);
      case SingleScanFunction.setBluetoothName:
        return ScannerConfigBarcode.setBluetoothName(
          _textController.text.trim(),
        );
      case SingleScanFunction.hideLeadingCharacters:
        return ScannerConfigBarcode.hideLeadingCharacters(
          int.parse(_countController.text.trim()),
        );
      case SingleScanFunction.hideTrailingCharacters:
        return ScannerConfigBarcode.hideTrailingCharacters(
          int.parse(_countController.text.trim()),
        );
      case SingleScanFunction.setCustomKey:
        return ScannerConfigBarcode.setCustomKey(
          keyNumber: int.parse(_keyNumberController.text.trim()),
          modifier: _modifier,
          hidKeyCode: int.parse(_keyCodeController.text.trim(), radix: 16),
        );
    }
  }

  Widget _combineCard() {
    final codes = _combineController.text
        .split(RegExp(r'[,\s|]+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final result = _tryBuild(() => ScannerConfigBarcode.combine(codes));

    return SectionCard(
      title: 'Free combination',
      description:
          'Any codes, separated by comma, space or "|". '
          'Example: 97, 77, AB → %%SpecCode97|77|AB',
      children: [
        TextField(
          controller: _combineController,
          decoration: const InputDecoration(
            labelText: 'Codes',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        _generated(
          result,
          maxLength: ScannerConfigBarcode.maxCombinedLength,
          allowSpecCode: codes.length == 1,
        ),
      ],
    );
  }

  /// QR preview of a generated code, with BLE send buttons.
  ///
  /// [allowSpecCode]: the code is one hex command that fits `BA 05`.
  Widget _generated(
    ({String? code, String? error}) result, {
    int? maxLength,
    required bool allowSpecCode,
  }) {
    final code = result.code;
    if (code == null) {
      return Text(
        result.error ?? 'Invalid input',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
    return BarcodePreview(
      data: code,
      maxLength: maxLength,
      actions: [
        if (allowSpecCode)
          TextButton.icon(
            onPressed: c.isConnected
                ? () => c.run(
                    'sendSpecCode($code)',
                    () => c.plugin.sendSpecCode(code),
                  )
                : null,
            icon: const Icon(Icons.send, size: 18),
            label: const Text('Send (BA 05)'),
          ),
        TextButton.icon(
          onPressed: c.isConnected
              ? () => c.run(
                  'sendVirtualScan($code)',
                  () => c.plugin.sendVirtualScan(code),
                )
              : null,
          icon: const Icon(Icons.send_and_archive, size: 18),
          label: const Text('Send as scan (BA 04)'),
        ),
      ],
    );
  }
}
