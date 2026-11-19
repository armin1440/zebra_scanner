import 'package:flutter/material.dart';
import 'package:zebra_handheld_scanner/zebra_handheld_scanner.dart';

import '../scanner_controller.dart';
import '../widgets/barcode_preview.dart';

/// Raw BLE commands and the event log.
class ConsolePage extends StatefulWidget {
  const ConsolePage({super.key, required this.controller});

  final ScannerController controller;

  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends State<ConsolePage> {
  final _specCodeController = TextEditingController(text: '97');
  final _barcodeController = TextEditingController(text: '%%SpecCode97|77');
  final _rawController = TextEditingController(text: 'ba0702');

  ScannerController get c => widget.controller;

  @override
  void dispose() {
    _specCodeController.dispose();
    _barcodeController.dispose();
    _rawController.dispose();
    super.dispose();
  }

  String _preview(String Function() build) {
    try {
      return '→ ${build()}';
    } on ArgumentError catch (e) {
      return '✗ ${e.message}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: 'Setting code (BA 05)',
            description:
                'One code per command, hex, max 18 bytes. '
                '"97" (High Volume) is sent as BA 05 97.',
            children: [
              _commandRow(
                controller: _specCodeController,
                label: 'Code, e.g. 97 or %%SpecCodeBA1C01',
                preview: _preview(
                  () => ZebraHandheldScanner.specCodeCommand(
                    _specCodeController.text,
                  ),
                ),
                onSend: () => c.run(
                  'sendSpecCode(${_specCodeController.text})',
                  () => c.plugin.sendSpecCode(_specCodeController.text),
                ),
              ),
            ],
          ),
          SectionCard(
            title: 'Virtual scan (BA 04)',
            description:
                'The scanner handles the text like a scanned barcode. '
                'Used by the vendor SDK. Use it to test combined codes over BLE.',
            children: [
              _commandRow(
                controller: _barcodeController,
                label: 'Barcode content',
                preview: _preview(
                  () => ZebraHandheldScanner.virtualScanCommand(
                    _barcodeController.text,
                  ),
                ),
                onSend: () => c.run(
                  'sendVirtualScan(${_barcodeController.text})',
                  () => c.plugin.sendVirtualScan(_barcodeController.text),
                ),
              ),
            ],
          ),
          SectionCard(
            title: 'Raw command',
            description: 'Hex bytes, for example ba0702 (buzzer).',
            children: [
              _commandRow(
                controller: _rawController,
                label: 'Hex',
                onSend: () => c.run(
                  'sendRawCommand(${_rawController.text})',
                  () => c.plugin.sendRawCommand(_rawController.text.trim()),
                ),
              ),
            ],
          ),
          SectionCard(
            title: 'Quick actions',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: c.isConnected
                        ? () => c.run(
                            'saveAsCustomDefaults',
                            c.plugin.saveAsCustomDefaults,
                          )
                        : null,
                    child: const Text('Save as custom defaults (92)'),
                  ),
                  OutlinedButton(
                    onPressed: c.isConnected
                        ? () => c.run(
                            'restoreFactoryDefaults',
                            c.plugin.restoreFactoryDefaults,
                          )
                        : null,
                    child: const Text('Restore defaults (93)'),
                  ),
                ],
              ),
            ],
          ),
          _logCard(context),
        ],
      ),
    );
  }

  Widget _commandRow({
    required TextEditingController controller,
    required String label,
    required VoidCallback onSend,
    String? preview,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                style: const TextStyle(fontFamily: 'monospace'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: c.isConnected ? onSend : null,
              child: const Text('Send'),
            ),
          ],
        ),
        if (preview != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              preview,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _logCard(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return SectionCard(
      title: 'Event log',
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: c.log.isEmpty ? null : c.clearLog,
            child: const Text('Clear'),
          ),
        ),
        if (c.log.isEmpty) const Text('No events yet.'),
        for (final entry in c.log.take(100))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '${entry.timeLabel}  ${entry.message}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: entry.isError ? errorColor : null,
              ),
            ),
          ),
      ],
    );
  }
}

/// Scanned barcodes.
class ScansPage extends StatelessWidget {
  const ScansPage({super.key, required this.controller});

  final ScannerController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.barcodes.isEmpty) {
          return const Center(
            child: Text('Scan a barcode with the connected scanner.'),
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(child: Text('${controller.barcodes.length} scans')),
                  TextButton(
                    onPressed: controller.clearBarcodes,
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: controller.barcodes.length,
                itemBuilder: (context, index) {
                  final barcode = controller.barcodes[index];
                  return Card(
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.qr_code_scanner),
                      title: SelectableText(barcode),
                      subtitle: Text('${barcode.length} characters'),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
