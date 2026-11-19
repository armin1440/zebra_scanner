/// Groups of configuration codes, in the order used by the
/// "Effon Technology Configuration Barcodes V8" manual.
enum ScannerSettingCategory {
  system('System'),
  scanMode('Scanning Mode'),
  keyboardLanguage('Keyboard Language'),
  encoding('Encoding'),
  sound('Sound'),
  inventory('Real-Time / Inventory Mode'),
  sleep('Sleep'),
  vibration('Vibration'),
  transmissionSpeed('Transmission Speed'),
  workingMode('Working Mode'),
  bluetooth('Bluetooth'),
  hidKeyboard('HID Keyboard'),
  dataFormatting('Data Formatting'),
  suffix('Suffix'),
  caseConversion('Case Conversion'),
  baudRate('Physical Serial Port Baud Rate'),
  time('Time'),
  setupMode('Setup Mode');

  final String label;
  const ScannerSettingCategory(this.label);
}

/// Every configuration code listed in the
/// "Effon Technology Configuration Barcodes V8" manual, plus the
/// undocumented codes confirmed by the vendor (for example `78`).
///
/// * [barcode] is the full content of the configuration barcode
///   (for example `%%SpecCode97`). Show it as a QR code or Code 128 barcode
///   and scan it with the scanner.
/// * [code] is the part after `%%SpecCode` (for example `97`). Send it over
///   BLE with `ZebraHandheldScanner.sendSetting` or
///   `ZebraHandheldScanner.sendSpecCode`.
/// * Settings with [requiresFollowUp] need a second barcode (the value).
///   Use the single-scan builders in `ScannerConfigBarcode` instead.
enum ScannerSetting {
  // System
  displayFirmwareVersion(
    '39',
    'Display Firmware Version',
    ScannerSettingCategory.system,
  ),
  displayBatteryLevel(
    '15',
    'Display Battery Level',
    ScannerSettingCategory.system,
  ),
  restoreFactoryDefaults(
    '93',
    'Restore Factory Defaults',
    ScannerSettingCategory.system,
  ),

  /// Saves all current settings as the custom defaults.
  /// [restoreFactoryDefaults] (`%%SpecCode93`) then restores these values.
  saveAsCustomDefaults(
    '92',
    'Set as Default Mode (save current settings)',
    ScannerSettingCategory.system,
  ),

  // Scanning mode
  triggerScan('BA1C00', 'Trigger Scan', ScannerSettingCategory.scanMode),
  continuousScan('BA1C01', 'Continuous Scan', ScannerSettingCategory.scanMode),

  // Keyboard language
  usEnglish(
    '40',
    'US English (Chinese)',
    ScannerSettingCategory.keyboardLanguage,
  ),
  german('41', 'German', ScannerSettingCategory.keyboardLanguage),
  french('42', 'French', ScannerSettingCategory.keyboardLanguage),
  spanish('43', 'Spanish', ScannerSettingCategory.keyboardLanguage),
  italian('44', 'Italian', ScannerSettingCategory.keyboardLanguage),
  japanese('45', 'Japanese', ScannerSettingCategory.keyboardLanguage),
  internationalKeyboard(
    '46',
    'International Keyboard',
    ScannerSettingCategory.keyboardLanguage,
  ),
  belgianFrench(
    '47',
    'Belgian French',
    ScannerSettingCategory.keyboardLanguage,
  ),
  portuguese('48', 'Portuguese', ScannerSettingCategory.keyboardLanguage),
  ukEnglish('49', 'UK English', ScannerSettingCategory.keyboardLanguage),
  germanIos(
    '4A',
    'German iOS Keyboard (Apple German Keyboard)',
    ScannerSettingCategory.keyboardLanguage,
  ),
  brazilianPortuguese(
    '4B',
    'Brazilian Portuguese',
    ScannerSettingCategory.keyboardLanguage,
  ),
  russian('4C', 'Russian', ScannerSettingCategory.keyboardLanguage),
  czech('4D', 'Czech', ScannerSettingCategory.keyboardLanguage),
  italian142('4E', 'Italian 142', ScannerSettingCategory.keyboardLanguage),
  turkishQ('4F', 'Turkish Q', ScannerSettingCategory.keyboardLanguage),
  turkishF('50', 'Turkish F', ScannerSettingCategory.keyboardLanguage),
  swedishFinnish(
    '51',
    'Swedish/Finnish',
    ScannerSettingCategory.keyboardLanguage,
  ),
  mexicanSpanish(
    '52',
    'Mexican Spanish',
    ScannerSettingCategory.keyboardLanguage,
  ),
  danish('53', 'Danish', ScannerSettingCategory.keyboardLanguage),
  norwegian(
    '54',
    'Norwegian (Bokmål)',
    ScannerSettingCategory.keyboardLanguage,
  ),
  croatianSerbian(
    '55',
    'Croatian/Serbian',
    ScannerSettingCategory.keyboardLanguage,
  ),
  swissGerman('56', 'Swiss German', ScannerSettingCategory.keyboardLanguage),
  swissFrench('57', 'Swiss French', ScannerSettingCategory.keyboardLanguage),
  dutch('58', 'Dutch', ScannerSettingCategory.keyboardLanguage),
  hungarian('59', 'Hungarian', ScannerSettingCategory.keyboardLanguage),
  polish('5A', 'Polish', ScannerSettingCategory.keyboardLanguage),
  canadianFrench(
    '5B',
    'Canadian French',
    ScannerSettingCategory.keyboardLanguage,
  ),
  argentinianSpanish(
    '5C',
    'Argentinian Spanish (Latin American)',
    ScannerSettingCategory.keyboardLanguage,
  ),
  slovak('5D', 'Slovak', ScannerSettingCategory.keyboardLanguage),

  /// Also set [utfEncoding] when you use this keyboard.
  vietnamese('5F', 'Vietnamese', ScannerSettingCategory.keyboardLanguage),

  // Encoding
  gbkEncoding('B5', 'GBK Encoding', ScannerSettingCategory.encoding),
  utfEncoding('B4', 'UTF Encoding', ScannerSettingCategory.encoding),
  russianEncodingCp1251(
    'BA1400',
    'Russian Encoding: CP1251',
    ScannerSettingCategory.encoding,
  ),
  russianEncodingKoi8r(
    'BA1401',
    'Russian Encoding: KOI8-R',
    ScannerSettingCategory.encoding,
  ),

  // Sound
  mute('94', 'Mute', ScannerSettingCategory.sound),
  lowVolume('95', 'Low Volume', ScannerSettingCategory.sound),
  mediumVolume('96', 'Medium Volume', ScannerSettingCategory.sound),
  highVolume('97', 'High Volume', ScannerSettingCategory.sound),
  scanEngineBeep('28', 'Scan Engine Beep', ScannerSettingCategory.sound),
  mcuBeep('29', 'Main Controller (MCU) Beep', ScannerSettingCategory.sound),
  buzzerFrequency2kHz(
    '7C',
    'Buzzer Frequency: 2 kHz',
    ScannerSettingCategory.sound,
  ),
  buzzerFrequency2_7kHz(
    '7D',
    'Buzzer Frequency: 2.7 kHz',
    ScannerSettingCategory.sound,
  ),

  // Real-time and inventory mode
  realTimeMode('10', 'Enter Real-Time Mode', ScannerSettingCategory.inventory),
  inventoryMode('11', 'Enter Inventory Mode', ScannerSettingCategory.inventory),
  uploadInventoryData(
    '16',
    'Upload Inventory Data',
    ScannerSettingCategory.inventory,
  ),
  displayStoredRecordCount(
    '17',
    'Display Total Number of Stored Records',
    ScannerSettingCategory.inventory,
  ),
  clearInventoryData(
    '18',
    'Clear Inventory Data',
    ScannerSettingCategory.inventory,
  ),

  /// Recommended only for 2.4G and Virtual Bluetooth modes.
  dataLossPreventionMode(
    '12',
    'Enter Data-Loss Prevention Mode',
    ScannerSettingCategory.inventory,
  ),

  // Sleep
  sleep30Seconds(
    '30',
    'Sleep Timeout: 30 Seconds',
    ScannerSettingCategory.sleep,
  ),
  sleep1Minute('31', 'Sleep Timeout: 1 Minute', ScannerSettingCategory.sleep),
  sleep2Minutes('32', 'Sleep Timeout: 2 Minutes', ScannerSettingCategory.sleep),
  sleep5Minutes('33', 'Sleep Timeout: 5 Minutes', ScannerSettingCategory.sleep),
  sleep10Minutes(
    '34',
    'Sleep Timeout: 10 Minutes',
    ScannerSettingCategory.sleep,
  ),
  sleep30Minutes(
    '35',
    'Sleep Timeout: 30 Minutes',
    ScannerSettingCategory.sleep,
  ),
  sleep1Hour('BA180168', 'Sleep Timeout: 1 Hour', ScannerSettingCategory.sleep),
  sleep2Hours(
    'BA1802D0',
    'Sleep Timeout: 2 Hours',
    ScannerSettingCategory.sleep,
  ),

  /// Value copied from the manual and the vendor Android SDK (`0x0483`).
  sleep3Hours(
    'BA180483',
    'Sleep Timeout: 3 Hours',
    ScannerSettingCategory.sleep,
  ),
  sleep4Hours(
    'BA1805A0',
    'Sleep Timeout: 4 Hours',
    ScannerSettingCategory.sleep,
  ),
  sleep5Hours(
    'BA180708',
    'Sleep Timeout: 5 Hours',
    ScannerSettingCategory.sleep,
  ),
  sleep6Hours(
    'BA180870',
    'Sleep Timeout: 6 Hours',
    ScannerSettingCategory.sleep,
  ),
  sleep12Hours(
    'BA1810E0',
    'Sleep Timeout: 12 Hours',
    ScannerSettingCategory.sleep,
  ),
  neverSleep('36', 'Never Sleep', ScannerSettingCategory.sleep),
  sleepImmediately('38', 'Sleep Immediately', ScannerSettingCategory.sleep),

  // Vibration
  enableVibration('77', 'Enable Vibration', ScannerSettingCategory.vibration),
  disableVibration('76', 'Disable Vibration', ScannerSettingCategory.vibration),

  // Transmission speed
  fastTransmission(
    'B0',
    'Fast Transmission',
    ScannerSettingCategory.transmissionSpeed,
  ),
  mediumTransmission(
    'B1',
    'Medium-Speed Transmission',
    ScannerSettingCategory.transmissionSpeed,
  ),
  slowTransmission(
    'B2',
    'Slow Transmission',
    ScannerSettingCategory.transmissionSpeed,
  ),
  ultraSlowTransmission(
    'B3',
    'Ultra-Slow Transmission',
    ScannerSettingCategory.transmissionSpeed,
  ),

  // Working mode
  mode2_4G('A8', '2.4G Mode', ScannerSettingCategory.workingMode),
  virtualBluetoothMode(
    'A9',
    'Virtual Bluetooth Mode',
    ScannerSettingCategory.workingMode,
  ),
  bluetoothHidMode(
    'AA',
    'Bluetooth HID Mode',
    ScannerSettingCategory.workingMode,
  ),
  bluetoothSppMode(
    'AB',
    'Bluetooth SPP Mode',
    ScannerSettingCategory.workingMode,
  ),
  bluetoothBleMode(
    'AC',
    'Bluetooth BLE Mode',
    ScannerSettingCategory.workingMode,
  ),
  bluetoothHogMode(
    'AA01',
    'Bluetooth HOG Mode',
    ScannerSettingCategory.workingMode,
  ),
  androidInputMethodMode(
    'AD',
    'Android Input Method Mode',
    ScannerSettingCategory.workingMode,
  ),
  virtualSerialPortMode(
    'AE',
    'Virtual Serial Port Mode',
    ScannerSettingCategory.workingMode,
  ),
  physicalSerialPortMode(
    'A7',
    'Physical Serial Port Mode',
    ScannerSettingCategory.workingMode,
  ),
  enterPairingMode(
    '99',
    'Enter Pairing Mode',
    ScannerSettingCategory.workingMode,
  ),

  // Bluetooth
  /// Two-step code. Prefer `ScannerConfigBarcode.setBluetoothName`.
  setBluetoothName(
    'EC',
    'Set Bluetooth Name',
    ScannerSettingCategory.bluetooth,
    requiresFollowUp: true,
  ),
  readBluetoothName(
    'ED',
    'Read Bluetooth Name',
    ScannerSettingCategory.bluetooth,
  ),
  allowLongPressHidDiscovery(
    '79',
    'Allow Long-Press to Enter HID Discovery',
    ScannerSettingCategory.bluetooth,
  ),

  /// Disables the 8-second long press that switches the scanner back to HID.
  disableLongPressHidDiscovery(
    '78',
    'Disable Long-Press to Enter HID Discovery',
    ScannerSettingCategory.bluetooth,
  ),

  // HID keyboard
  toggleHidKeyboard(
    '1A',
    'Show/Hide HID Keyboard',
    ScannerSettingCategory.hidKeyboard,
  ),
  disableDoubleTapHidKeyboard(
    '7A',
    'Disable Double-Tap to Show/Hide HID Keyboard',
    ScannerSettingCategory.hidKeyboard,
  ),
  enableDoubleTapHidKeyboard(
    '7B',
    'Enable Double-Tap to Show/Hide HID Keyboard',
    ScannerSettingCategory.hidKeyboard,
  ),

  // Data formatting
  /// Two-step code. Prefer `ScannerConfigBarcode.setGsReplacement`.
  setGsReplacement(
    'EF',
    'Set GS Replacement Character',
    ScannerSettingCategory.dataFormatting,
    requiresFollowUp: true,
  ),
  disableGsReplacement(
    'EE',
    'Disable GS Character Replacement',
    ScannerSettingCategory.dataFormatting,
  ),

  /// Two-step code. Prefer `ScannerConfigBarcode.setPrefix`.
  setPrefix(
    '9A',
    'Set Prefix',
    ScannerSettingCategory.dataFormatting,
    requiresFollowUp: true,
  ),

  /// Two-step code. Prefer `ScannerConfigBarcode.setSuffix`.
  setSuffix(
    '9B',
    'Set Suffix',
    ScannerSettingCategory.dataFormatting,
    requiresFollowUp: true,
  ),
  escapeCharacterSet0(
    'BA0000',
    'Set Escape Character Set 0',
    ScannerSettingCategory.dataFormatting,
  ),
  escapeCharacterSet1(
    'BA0001',
    'Set Escape Character Set 1',
    ScannerSettingCategory.dataFormatting,
  ),
  escapeCharacterSet2(
    'BA0002',
    'Set Escape Character Set 2',
    ScannerSettingCategory.dataFormatting,
  ),
  escapeCharacterSet3(
    'BA0003',
    'Set Escape Character Set 3',
    ScannerSettingCategory.dataFormatting,
  ),

  /// Two-step code. Prefer `ScannerConfigBarcode.hideLeadingCharacters`.
  hideLeadingCharacters(
    'A0',
    'Hide Leading Characters',
    ScannerSettingCategory.dataFormatting,
    requiresFollowUp: true,
  ),

  /// Two-step code. Prefer `ScannerConfigBarcode.hideTrailingCharacters`.
  hideTrailingCharacters(
    'A1',
    'Hide Trailing Characters',
    ScannerSettingCategory.dataFormatting,
    requiresFollowUp: true,
  ),

  // Suffix
  appendCarriageReturn(
    '9C',
    'Append Carriage Return',
    ScannerSettingCategory.suffix,
  ),
  appendLineFeed('9D', 'Append Line Feed', ScannerSettingCategory.suffix),
  appendCarriageReturnLineFeed(
    '9E',
    'Append Carriage Return + Line Feed',
    ScannerSettingCategory.suffix,
  ),
  appendTab('A2', 'Append Tab', ScannerSettingCategory.suffix),
  appendNothing('9F', 'Append Nothing', ScannerSettingCategory.suffix),

  // Case conversion
  forceLowercase(
    'A3',
    'Force Lowercase',
    ScannerSettingCategory.caseConversion,
  ),
  forceUppercase(
    'A4',
    'Force Uppercase',
    ScannerSettingCategory.caseConversion,
  ),
  swapCase('A6', 'Swap Case', ScannerSettingCategory.caseConversion),
  keepCase('A5', 'Do Not Change Case', ScannerSettingCategory.caseConversion),

  // Baud rate
  baudRate4800('BA1D04', '4800', ScannerSettingCategory.baudRate),
  baudRate9600('BA1D08', '9600', ScannerSettingCategory.baudRate),
  baudRate19200('BA1D10', '19200', ScannerSettingCategory.baudRate),
  baudRate38400('BA1D20', '38400', ScannerSettingCategory.baudRate),
  baudRate57600('BA1D30', '57600', ScannerSettingCategory.baudRate),
  baudRate115200('BA1D60', '115200', ScannerSettingCategory.baudRate),

  // Time
  displayCurrentTime('1B', 'Display Current Time', ScannerSettingCategory.time),
  addTimeBeforeData(
    'C1',
    'Add Time Before Barcode Data',
    ScannerSettingCategory.time,
  ),
  addTimeAfterData(
    'C2',
    'Add Time After Barcode Data',
    ScannerSettingCategory.time,
  ),
  disableTimePrefixSuffix(
    'C0',
    'Disable Time Prefix/Suffix',
    ScannerSettingCategory.time,
  ),

  // Setup mode. These are not `%%SpecCode` codes, so they cannot be sent
  // with `sendSpecCode`. `sendSetting` sends them as a virtual scan.
  enterSetupMode(
    'EnterSet',
    'Enter Setup Mode',
    ScannerSettingCategory.setupMode,
    isSpecCode: false,
  ),
  exitSetupMode(
    'ExitSet',
    'Exit Setup Mode',
    ScannerSettingCategory.setupMode,
    isSpecCode: false,
  );

  /// The code after `%%SpecCode` (or after `%%` when [isSpecCode] is false).
  final String code;

  /// The English name used in the manual.
  final String label;

  final ScannerSettingCategory category;

  /// True for `%%SpecCode…` codes. False for `%%EnterSet` and `%%ExitSet`.
  final bool isSpecCode;

  /// True when the manual requires a second barcode after this one.
  final bool requiresFollowUp;

  const ScannerSetting(
    this.code,
    this.label,
    this.category, {
    this.isSpecCode = true,
    this.requiresFollowUp = false,
  });

  /// The full configuration barcode content, for example `%%SpecCode97`.
  String get barcode => isSpecCode ? '%%SpecCode$code' : '%%$code';

  /// All settings of [category], in manual order.
  static List<ScannerSetting> byCategory(ScannerSettingCategory category) =>
      values.where((s) => s.category == category).toList();
}
