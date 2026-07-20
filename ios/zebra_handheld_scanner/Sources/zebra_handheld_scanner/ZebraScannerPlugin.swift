import Flutter
import UIKit
import CoreBluetooth

public class ZebraScannerPlugin: NSObject, FlutterPlugin, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    private var channel: FlutterMethodChannel
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    
    private var notifyCharacteristics: [CBCharacteristic] = []
    private var writeCharacteristics: [CBCharacteristic] = []
    
    private var batteryCharacteristic: CBCharacteristic?
    private var versionCharacteristic: CBCharacteristic?
    
    private var pendingBatteryResult: FlutterResult?
    private var pendingVersionResult: FlutterResult?
    private var pendingConnectResult: FlutterResult?
    private var connectTimeoutWorkItem: DispatchWorkItem?

    private var isScanningForAutoConnect = false

    private var barcodeBuffer = ""
    private var dispatchBarcodeWorkItem: DispatchWorkItem?

    private var isCoolingDown = false
    private var cooldownWorkItem: DispatchWorkItem?

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "zebra_handheld_scanner", binaryMessenger: registrar.messenger())
        let instance = ZebraScannerPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
            
        case "requestPermissions":
            if #available(iOS 13.1, *) {
                let auth = CBCentralManager.authorization
                result(auth == .allowedAlways || auth == .notDetermined)
            } else if #available(iOS 13.0, *) {
                let auth = centralManager.authorization
                result(auth == .allowedAlways || auth == .notDetermined)
            } else {
                result(true)
            }
            
        case "autoConnectBle":
            if centralManager.state == .poweredOn {
                isScanningForAutoConnect = true
                centralManager.scanForPeripherals(withServices: nil, options: nil)
                
                // Return a pairing barcode text or simple instructions for iOS
                let deviceName = UIDevice.current.name
                let instructions = "Please scan the BLE STC barcode to connect to: \(deviceName)"
                result(instructions)
            } else {
                result(FlutterError(code: "BLE_OFF", message: "Bluetooth is not powered on", details: nil))
            }

        case "connectToLastDevice":
            let defaults = UserDefaults.standard
            if let uuidString = defaults.string(forKey: "ZebraScannerLastDeviceUUID"),
               let uuid = UUID(uuidString: uuidString) {
                let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
                if let peripheral = peripherals.first {
                    connectedPeripheral = peripheral
                    pendingConnectResult = result
                    centralManager.connect(peripheral, options: nil)

                    // Setup a 5 second timeout for connection
                    connectTimeoutWorkItem?.cancel()
                    let workItem = DispatchWorkItem { [weak self] in
                        guard let self = self else { return }
                        if self.pendingConnectResult != nil {
                            self.centralManager.cancelPeripheralConnection(peripheral)
                            self.pendingConnectResult?(false)
                            self.pendingConnectResult = nil
                        }
                    }
                    connectTimeoutWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: workItem)
                } else {
                    result(false)
                }
            } else {
                result(false)
            }
            
        case "sendCommand":
            guard let args = call.arguments as? [String: Any],
                  let command = args["command"] as? String,
                  let peripheral = connectedPeripheral else {
                result(FlutterError(code: "NOT_CONNECTED", message: "No device connected or missing command", details: nil))
                return
            }
            
            let data = dataFromHexString(command)
            var wrote = false
            for char in writeCharacteristics {
                let type: CBCharacteristicWriteType = char.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
                peripheral.writeValue(data, for: char, type: type)
                wrote = true
            }
            
            if wrote {
                result(nil)
            } else {
                result(FlutterError(code: "NO_WRITE_CHARACTERISTIC", message: "No writable characteristic found", details: nil))
            }
            
        case "getDeviceName":
            result(connectedPeripheral?.name ?? "Unknown")
            
        case "getVersion":
            guard let peripheral = connectedPeripheral, let char = versionCharacteristic else {
                result(FlutterError(code: "UNAVAILABLE", message: "Version characteristic not found", details: nil))
                return
            }
            pendingVersionResult = result
            peripheral.readValue(for: char)
            
        case "getBatteryLevel":
            guard let peripheral = connectedPeripheral, let char = batteryCharacteristic else {
                result(FlutterError(code: "UNAVAILABLE", message: "Battery characteristic not found", details: nil))
                return
            }
            pendingBatteryResult = result
            peripheral.readValue(for: char)
            
        case "setDeviceName":
            // Not standardly supported via generic BLE without knowing the exact Zebra command. 
            result(nil)
            
        case "disconnect":
            if let peripheral = connectedPeripheral {
                centralManager.cancelPeripheralConnection(peripheral)
            }
            result(nil)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func clearConnectionState() {
        connectedPeripheral = nil
        notifyCharacteristics.removeAll()
        writeCharacteristics.removeAll()
        batteryCharacteristic = nil
        versionCharacteristic = nil
        barcodeBuffer = ""
        dispatchBarcodeWorkItem?.cancel()
        cooldownWorkItem?.cancel()
        isCoolingDown = false
    }

    private func dispatchAccumulatedBarcode() {
        dispatchBarcodeWorkItem?.cancel()
        let finalBarcode = barcodeBuffer.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        barcodeBuffer = ""

        if !finalBarcode.isEmpty && finalBarcode != "\u{FFFD}" {
            self.channel.invokeMethod("onBarcodeScanned", arguments: finalBarcode)

            self.isCoolingDown = true
            self.cooldownWorkItem?.cancel()
            let cooldown = DispatchWorkItem { [weak self] in
                self?.isCoolingDown = false
            }
            self.cooldownWorkItem = cooldown
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: cooldown)
        }
    }

    private func dataFromHexString(_ hex: String) -> Data {
        var data = Data()
        var hexStr = hex
        if hexStr.count % 2 != 0 {
            hexStr = "0" + hexStr
        }
        var index = hexStr.startIndex
        while index < hexStr.endIndex {
            let nextIndex = hexStr.index(index, offsetBy: 2)
            let byteString = String(hexStr[index..<nextIndex])
            if let byte = UInt8(byteString, radix: 16) {
                data.append(byte)
            }
            index = nextIndex
        }
        return data
    }
    
    // MARK: - CBCentralManagerDelegate
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn && isScanningForAutoConnect {
            centralManager.scanForPeripherals(withServices: nil, options: nil)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if isScanningForAutoConnect {
            let name = peripheral.name?.lowercased() ?? ""

            // iOS often appends "BLE" at the end of the Zebra scanner name.
            // We validate it using this logic, plus a proximity check to ensure it's the device scanning the screen.
            let isScanner = name.hasSuffix("ble")

            if isScanner && RSSI.intValue > -65 && RSSI.intValue != 127 {
                centralManager.stopScan()
                isScanningForAutoConnect = false
                connectedPeripheral = peripheral
                centralManager.connect(peripheral, options: nil)
            }
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Save the connected peripheral UUID
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: "ZebraScannerLastDeviceUUID")

        peripheral.delegate = self
        clearConnectionState()
        connectedPeripheral = peripheral
        
        peripheral.discoverServices(nil)

        connectTimeoutWorkItem?.cancel()
        if let result = pendingConnectResult {
            result(true)
            pendingConnectResult = nil
        }

        DispatchQueue.main.async {
            self.channel.invokeMethod("onScannerConnected", arguments: true)
        }
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectTimeoutWorkItem?.cancel()
        if let result = pendingConnectResult {
            result(false)
            pendingConnectResult = nil
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral == connectedPeripheral {
            clearConnectionState()
            
            DispatchQueue.main.async {
                self.channel.invokeMethod("onScannerConnected", arguments: false)
            }
        }
    }
    
    // MARK: - CBPeripheralDelegate
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for char in characteristics {
            let props = char.properties
            
            if props.contains(.notify) || props.contains(.indicate) {
                notifyCharacteristics.append(char)
                peripheral.setNotifyValue(true, for: char)
            }
            
            if props.contains(.write) || props.contains(.writeWithoutResponse) {
                writeCharacteristics.append(char)
            }
            
            // Battery Level Characteristic UUID is 2A19
            if char.uuid.uuidString == "2A19" || char.uuid.uuidString == "2a19" {
                batteryCharacteristic = char
            }
            
            // Firmware Revision String Characteristic UUID is 2A26
            if char.uuid.uuidString == "2A26" || char.uuid.uuidString == "2a26" {
                versionCharacteristic = char
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        // Check if this is battery
        if characteristic.uuid.uuidString == "2A19" || characteristic.uuid.uuidString == "2a19" {
            if let result = pendingBatteryResult {
                var batteryLevel: UInt8 = 0
                data.copyBytes(to: &batteryLevel, count: 1)
                result(Int(batteryLevel))
                pendingBatteryResult = nil
            }
            return
        }
        
        // Check if this is version
        if characteristic.uuid.uuidString == "2A26" || characteristic.uuid.uuidString == "2a26" {
            if let result = pendingVersionResult {
                let version = String(data: data, encoding: .utf8) ?? "Unknown"
                result(version)
                pendingVersionResult = nil
            }
            return
        }
        
        // Otherwise, assume it's scanned barcode data
        var text: String? = nil
        if let stringValue = String(data: data, encoding: .utf8), !stringValue.isEmpty {
            text = stringValue
        } else if !data.isEmpty {
            // Fallback for hex string if not valid utf8
            text = data.map { String(format: "%02x", $0) }.joined()
        }

        if let text = text {
            let cleanedChunk = text.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "").trimmingCharacters(in: .whitespacesAndNewlines)

            // Ignore the automatic scan artifact from the scanner
            if cleanedChunk.count == 2 && cleanedChunk.hasPrefix("\u{FFFD}") {
                return
            }
            if cleanedChunk == "\u{FFFD}" {
                return
            }

            DispatchQueue.main.async {
                if self.isCoolingDown {
                    return
                }

                self.barcodeBuffer += text

                self.dispatchBarcodeWorkItem?.cancel()
                let workItem = DispatchWorkItem { [weak self] in
                    self?.dispatchAccumulatedBarcode()
                }
                self.dispatchBarcodeWorkItem = workItem

                // Use a 0.25s debounce window. This is the "silence timeout" between
                // BLE packets. 0.25s is long enough to keep a single scan together,
                // but short enough to fire BEFORE a second physical scan begins.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
            }
        }
    }
}
