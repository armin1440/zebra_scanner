/// Connection state reported by the native plugin.
enum ScannerConnectionState {
  /// Not connected. No pairing and no reconnection in progress.
  idle,

  /// Pairing is in progress. The app shows the pairing QR code and waits for
  /// a scanner to read it.
  pairing,

  /// The saved scanner is not connected. The plugin tries to reconnect to it
  /// (and only to it) in the background.
  reconnecting,

  /// A scanner is connected.
  connected;

  static ScannerConnectionState fromName(String? name) =>
      ScannerConnectionState.values.firstWhere(
        (s) => s.name == name,
        orElse: () => ScannerConnectionState.idle,
      );
}
