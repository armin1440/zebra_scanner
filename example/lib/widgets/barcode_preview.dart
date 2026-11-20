import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Shows barcode content as a QR code that the scanner can read,
/// with the raw text, its length, and optional actions.
class BarcodePreview extends StatelessWidget {
  const BarcodePreview({
    super.key,
    required this.data,
    this.size = 200,
    this.actions = const [],
    this.maxLength,
  });

  final String data;
  final double size;
  final List<Widget> actions;

  /// Shows the length in red when it is above this value.
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    final length = utf8.encode(data).length;
    final tooLong = maxLength != null && length > maxLength!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            // Quiet zone and white background so the scanner can read it in dark mode.
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: QrImageView(
              data: data,
              size: size,
              backgroundColor: Colors.white,
              errorStateBuilder: (context, error) => SizedBox(
                width: size,
                height: size,
                child: Center(
                  child: Text(
                    'Cannot render QR: $error',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SelectableText(
          data,
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
        Text(
          maxLength == null ? '$length bytes' : '$length / $maxLength bytes',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: tooLong ? theme.colorScheme.error : null,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: data));
                ScaffoldMessenger.maybeOf(
                  context,
                )?.showSnackBar(const SnackBar(content: Text('Copied')));
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy'),
            ),
            ...actions,
          ],
        ),
      ],
    );
  }
}

/// Opens a dialog with a large QR code of [data].
Future<void> showBarcodeDialog(
  BuildContext context, {
  required String title,
  required String data,
  List<Widget> actions = const [],
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 280,
          child: BarcodePreview(data: data, size: 240, actions: actions),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// A card with a title, an optional description, and content.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    this.description,
    required this.children,
  });

  final String title;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (description != null) ...[
              const SizedBox(height: 4),
              Text(description!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}
