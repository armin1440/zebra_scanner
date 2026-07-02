## 0.0.12

* Added check for location services being enabled on Android 11 and below before generating BLE connection QR code, automatically prompting the user to enable it if disabled.

## 0.0.11

* Added `ACCESS_COARSE_LOCATION` permission support for Android 11 and below to fix BLE auto-connect on older Android versions (like Android 9).

## 0.0.10

* Added `connectToLastDevice` feature to automatically reconnect to the last connected scanner on both Android and iOS.

## 0.0.9

* iOS: Update BLE autoconnect to exclusively filter scanners whose Bluetooth name ends with "BLE".

## 0.0.8

* Ignore auto sent strings in onBarcodeScanned

## 0.0.7

* Return device info even after waking up from dormancy mode 

## 0.0.6

* Improved filtering for automatic invalid scan artifacts on Android

## 0.0.5

* ignored \r\n- in android

## 0.0.4

* lowered dart sdk version to 3.10.1

## 0.0.3

* Cache qr code in autoConnectBle response in Android

## 0.0.2

* Fixed channel name

## 0.0.1

* initial release
