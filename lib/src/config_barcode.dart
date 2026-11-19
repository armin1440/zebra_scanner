import 'dart:convert';

import 'scanner_setting.dart';

/// Function codes of the single-scan command `%%SpecCodeBA3E<XX><YY><DD…>`
/// (see "Aggregated Barcode Instructions").
enum SingleScanFunction {
  setPrefix(0x00),
  setSuffix(0x01),
  setGsReplacement(0x02),
  hideLeadingCharacters(0x03),
  hideTrailingCharacters(0x04),
  setBluetoothName(0x05),
  setCustomKey(0x06);

  final int functionCode;
  const SingleScanFunction(this.functionCode);
}

/// Builds the content of configuration barcodes.
///
/// Show the result as a QR code (or Code 128) and scan it with the scanner.
/// Most results can also be sent over BLE with
/// `ZebraHandheldScanner.sendSpecCode` (one command at a time, at most
/// [maxBleSpecCodeBytes] bytes).
class ScannerConfigBarcode {
  ScannerConfigBarcode._();

  /// Prefix of every configuration code.
  static const String specCodePrefix = '%%SpecCode';

  /// Maximum length of a combined configuration barcode (vendor answer).
  static const int maxCombinedLength = 128;

  /// Maximum data length of the BLE "setting command" (`BA 05 <data>`).
  static const int maxBleSpecCodeBytes = 18;

  /// Maximum prefix or suffix length, in bytes.
  static const int maxPrefixSuffixBytes = 32;

  /// Maximum number of characters the scanner can hide.
  static const int maxHiddenCharacters = 64;

  /// Maximum Bluetooth name length, in bytes.
  static const int maxBluetoothNameBytes = 16;

  /// Removes the `%%SpecCode` prefix, if present, and surrounding spaces.
  static String stripPrefix(String code) {
    final trimmed = code.trim();
    return trimmed.startsWith(specCodePrefix)
        ? trimmed.substring(specCodePrefix.length)
        : trimmed;
  }

  /// Combines several configuration codes into one barcode.
  ///
  /// Each code can be given with or without `%%SpecCode`.
  /// Example: `combine(['93', '78', 'AC'])` returns `%%SpecCode93|78|AC`.
  ///
  /// Throws [ArgumentError] if [codes] is empty, if a code is not a
  /// `%%SpecCode` code (for example `%%EnterSet`), or if the result is longer
  /// than [maxCombinedLength] bytes.
  static String combine(Iterable<String> codes) {
    final parts = <String>[];
    for (final raw in codes) {
      final trimmed = raw.trim();
      if (trimmed.startsWith('%%') && !trimmed.startsWith(specCodePrefix)) {
        throw ArgumentError.value(
          raw,
          'codes',
          'Only %%SpecCode codes can be combined',
        );
      }
      final code = stripPrefix(trimmed);
      if (code.isEmpty) {
        throw ArgumentError.value(raw, 'codes', 'Empty code');
      }
      if (code.contains('|')) {
        throw ArgumentError.value(raw, 'codes', 'A code must not contain "|"');
      }
      parts.add(code);
    }
    if (parts.isEmpty) {
      throw ArgumentError.value(
        codes,
        'codes',
        'At least one code is required',
      );
    }
    final result = '$specCodePrefix${parts.join('|')}';
    final length = utf8.encode(result).length;
    if (length > maxCombinedLength) {
      throw ArgumentError(
        'Combined barcode is $length bytes. The maximum is $maxCombinedLength bytes.',
      );
    }
    return result;
  }

  /// Combines several [ScannerSetting] values into one barcode.
  static String combineSettings(Iterable<ScannerSetting> settings) => combine(
    settings.map((s) {
      if (!s.isSpecCode) {
        throw ArgumentError.value(
          s,
          'settings',
          '${s.barcode} cannot be combined',
        );
      }
      return s.code;
    }),
  );

  /// Builds the one-scan setup barcode used before pairing.
  ///
  /// By default it returns `%%SpecCode93|78|AC`: restore defaults, disable
  /// the long press that switches back to HID, and enter BLE mode.
  ///
  /// [bluetoothName] sets a custom Bluetooth name (max 16 bytes, no `|`),
  /// added as `BA3E05…` after `93`, because `93` restores the default name.
  /// With [saveAsCustomDefaults], the name is saved before `92`, so a later
  /// `93` keeps it. Example with name `S-07`:
  /// `%%SpecCode93|78|AC|BA3E0504S-07`.
  ///
  /// [pairingCode] is the value returned by `startPairing`
  /// (`%%SpecCodeBA44…`). When it is given, it is appended as the last code so
  /// that one scan also starts the connection. The vendor SDK sends
  /// `BA44` inside combined codes, but this combination is not confirmed by
  /// the vendor documentation. Test it on your firmware.
  static String initialSetup({
    bool restoreFactoryDefaults = true,
    bool disableLongPressHidDiscovery = true,
    bool bleMode = true,
    String? bluetoothName,
    bool saveAsCustomDefaults = false,
    Iterable<String> extraCodes = const [],
    String? pairingCode,
  }) {
    final name = bluetoothName?.trim() ?? '';
    final codes = <String>[
      if (restoreFactoryDefaults) ScannerSetting.restoreFactoryDefaults.code,
      if (disableLongPressHidDiscovery)
        ScannerSetting.disableLongPressHidDiscovery.code,
      if (bleMode) ScannerSetting.bluetoothBleMode.code,
      if (name.isNotEmpty) setBluetoothName(name),
      ...extraCodes,
      if (saveAsCustomDefaults) ScannerSetting.saveAsCustomDefaults.code,
      if (pairingCode != null && pairingCode.trim().isNotEmpty) pairingCode,
    ];
    return combine(codes);
  }

  /// Builds a single-scan command: `%%SpecCodeBA3E` + function + length + data.
  ///
  /// [data] is the DD part. It must be hexadecimal, except for
  /// [SingleScanFunction.setBluetoothName] where it is plain text.
  /// The length (YY) is the number of characters in [data], written as two
  /// hexadecimal digits. The manual only shows lengths below 10, where hex
  /// and decimal are the same. Test longer values on your firmware.
  static String singleScan(SingleScanFunction function, String data) {
    if (function != SingleScanFunction.setBluetoothName && !isHex(data)) {
      throw ArgumentError.value(
        data,
        'data',
        'Must be an even number of hex digits',
      );
    }
    if (data.length > 0xFF) {
      throw ArgumentError.value(data, 'data', 'Too long');
    }
    return '${specCodePrefix}BA3E${_hexByte(function.functionCode)}${_hexByte(data.length)}$data';
  }

  /// Example: `setPrefix('1234')` returns `%%SpecCodeBA3E000831323334`.
  static String setPrefix(String text) {
    _checkBytes(text, maxPrefixSuffixBytes, 'text');
    return singleScan(SingleScanFunction.setPrefix, textToHex(text));
  }

  /// Example: `setSuffix('1234')` returns `%%SpecCodeBA3E010831323334`.
  static String setSuffix(String text) {
    _checkBytes(text, maxPrefixSuffixBytes, 'text');
    return singleScan(SingleScanFunction.setSuffix, textToHex(text));
  }

  /// Example: `setGsReplacement('1')` returns `%%SpecCodeBA3E020231`.
  static String setGsReplacement(String replacement) {
    if (replacement.isEmpty) {
      throw ArgumentError.value(
        replacement,
        'replacement',
        'Must not be empty',
      );
    }
    return singleScan(
      SingleScanFunction.setGsReplacement,
      textToHex(replacement),
    );
  }

  /// Example: `hideLeadingCharacters(8)` returns `%%SpecCodeBA3E030208`.
  static String hideLeadingCharacters(int count) {
    _checkRange(count, 0, maxHiddenCharacters, 'count');
    return singleScan(
      SingleScanFunction.hideLeadingCharacters,
      _hexByte(count),
    );
  }

  /// Example: `hideTrailingCharacters(8)` returns `%%SpecCodeBA3E040208`.
  static String hideTrailingCharacters(int count) {
    _checkRange(count, 0, maxHiddenCharacters, 'count');
    return singleScan(
      SingleScanFunction.hideTrailingCharacters,
      _hexByte(count),
    );
  }

  /// Example: `setBluetoothName('Scanner')` returns `%%SpecCodeBA3E0507Scanner`.
  ///
  /// The scanner adds the protocol suffix (`ScannerBLE`, `ScannerSPP`, …).
  static String setBluetoothName(String name) {
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Must not be empty');
    }
    _checkBytes(name, maxBluetoothNameBytes, 'name');
    if (name.contains('|')) {
      throw ArgumentError.value(name, 'name', 'Must not contain "|"');
    }
    return singleScan(SingleScanFunction.setBluetoothName, name);
  }

  /// Configures a custom key.
  ///
  /// The manual gives one example: custom key 1 as Ctrl+A is
  /// `%%SpecCodeBA3E0606010104`. The data is read as
  /// key number (`01`), modifier (`01` = Ctrl) and HID key code (`04` = A).
  /// Use [setCustomKeyRaw] for other layouts.
  static String setCustomKey({
    required int keyNumber,
    required int modifier,
    required int hidKeyCode,
  }) {
    _checkRange(keyNumber, 0, 0xFF, 'keyNumber');
    _checkRange(modifier, 0, 0xFF, 'modifier');
    _checkRange(hidKeyCode, 0, 0xFF, 'hidKeyCode');
    return singleScan(
      SingleScanFunction.setCustomKey,
      '${_hexByte(keyNumber)}${_hexByte(modifier)}${_hexByte(hidKeyCode)}',
    );
  }

  /// Configures a custom key with raw hexadecimal data.
  static String setCustomKeyRaw(String hexData) =>
      singleScan(SingleScanFunction.setCustomKey, hexData.toUpperCase());

  /// Converts [text] to uppercase hex of its UTF-8 bytes. `'1234'` → `'31323334'`.
  static String textToHex(String text) => utf8
      .encode(text)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();

  /// True when [value] is an even number of hex digits (empty is allowed).
  static bool isHex(String value) =>
      value.length.isEven && RegExp(r'^[0-9a-fA-F]*$').hasMatch(value);

  static String _hexByte(int value) =>
      value.toRadixString(16).padLeft(2, '0').toUpperCase();

  static void _checkBytes(String text, int max, String name) {
    final length = utf8.encode(text).length;
    if (length > max) {
      throw ArgumentError.value(
        text,
        name,
        'Is $length bytes. The maximum is $max bytes.',
      );
    }
  }

  static void _checkRange(int value, int min, int max, String name) {
    if (value < min || value > max) {
      throw RangeError.range(value, min, max, name);
    }
  }
}
