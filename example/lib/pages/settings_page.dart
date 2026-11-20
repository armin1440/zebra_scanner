import 'package:flutter/material.dart';
import 'package:zebra_handheld_scanner/zebra_handheld_scanner.dart';

import '../scanner_controller.dart';
import '../widgets/barcode_preview.dart';

/// All configuration codes of the manual. Each code can be shown as a QR
/// code or sent over BLE. Selected codes can be combined into one barcode.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final ScannerController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _searchController = TextEditingController();
  final List<ScannerSetting> _selected = [];
  String _query = '';

  ScannerController get c => widget.controller;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(ScannerSetting s) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return s.label.toLowerCase().contains(q) ||
        s.barcode.toLowerCase().contains(q) ||
        s.category.label.toLowerCase().contains(q);
  }

  void _toggle(ScannerSetting s) {
    setState(
      () => _selected.contains(s) ? _selected.remove(s) : _selected.add(s),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search settings (name or code)',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                          _searchController.clear();
                          _query = '';
                        }),
                      ),
              ),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
          ),
          if (!c.isConnected)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'Not connected: you can show QR codes, but not send over BLE.',
              ),
            ),
          Expanded(child: _list(context)),
          if (_selected.isNotEmpty) _selectionBar(context),
        ],
      ),
    );
  }

  Widget _list(BuildContext context) {
    final groups = <Widget>[];
    for (final category in ScannerSettingCategory.values) {
      final settings = ScannerSetting.byCategory(
        category,
      ).where(_matches).toList();
      if (settings.isEmpty) continue;
      groups.add(
        ExpansionTile(
          // New key when search starts or ends, so initiallyExpanded applies.
          key: ValueKey('${category.name}-${_query.isNotEmpty}'),
          title: Text(category.label),
          subtitle: Text('${settings.length} codes'),
          initiallyExpanded: _query.isNotEmpty,
          children: [for (final s in settings) _tile(context, s)],
        ),
      );
    }
    if (groups.isEmpty) {
      return const Center(child: Text('No settings match.'));
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: groups,
    );
  }

  Widget _tile(BuildContext context, ScannerSetting s) {
    final selected = _selected.contains(s);
    return ListTile(
      dense: true,
      leading: Checkbox(
        value: selected,
        onChanged: s.isSpecCode ? (_) => _toggle(s) : null,
      ),
      title: Text(s.label),
      subtitle: Text(
        s.requiresFollowUp
            ? '${s.barcode}  ·  needs a second barcode (see Builders)'
            : s.barcode,
        style: const TextStyle(fontFamily: 'monospace'),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Show QR',
            icon: const Icon(Icons.qr_code),
            onPressed: () =>
                showBarcodeDialog(context, title: s.label, data: s.barcode),
          ),
          IconButton(
            tooltip: s.isSpecCode
                ? 'Send over BLE (BA 05)'
                : 'Send over BLE as virtual scan (BA 04)',
            icon: const Icon(Icons.send),
            onPressed: c.isConnected ? () => c.sendSetting(s) : null,
          ),
        ],
      ),
      onTap: s.isSpecCode ? () => _toggle(s) : null,
    );
  }

  Widget _selectionBar(BuildContext context) {
    String? combined;
    String? error;
    try {
      combined = ScannerConfigBarcode.combineSettings(_selected);
    } on ArgumentError catch (e) {
      error = '${e.message}';
    }

    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_selected.length} selected',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(_selected.clear),
                    child: const Text('Clear'),
                  ),
                ],
              ),
              Text(
                combined ?? error ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: error == null
                      ? null
                      : Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: combined == null
                        ? null
                        : () => showBarcodeDialog(
                            context,
                            title: 'Combined barcode',
                            data: combined!,
                            actions: [
                              if (c.isConnected)
                                TextButton.icon(
                                  onPressed: () => c.run(
                                    'sendVirtualScan($combined)',
                                    () => c.plugin.sendVirtualScan(combined!),
                                  ),
                                  icon: const Icon(Icons.send, size: 18),
                                  label: const Text('Send (BA 04)'),
                                ),
                            ],
                          ),
                    icon: const Icon(Icons.qr_code),
                    label: const Text('Combined QR'),
                  ),
                  OutlinedButton(
                    onPressed: c.isConnected
                        ? () => c.run(
                            'sendSettings(${_selected.length})',
                            () => c.plugin.sendSettings(List.of(_selected)),
                          )
                        : null,
                    child: const Text('Send one by one (BA 05)'),
                  ),
                  OutlinedButton(
                    onPressed: c.isConnected && combined != null
                        ? () => c.run(
                            'sendVirtualScan($combined)',
                            () => c.plugin.sendVirtualScan(combined!),
                          )
                        : null,
                    child: const Text('Send combined (BA 04)'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
