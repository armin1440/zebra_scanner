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
    
    private var isScanningForAutoConnect = false

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "zebra_scanner", binaryMessenger: registrar.messenger())
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
            // Basic heuristic: Connect to a discovered device that has a name (likely the scanner turning on)
            if !name.isEmpty {
                centralManager.stopScan()
                isScanningForAutoConnect = false
                connectedPeripheral = peripheral
                centralManager.connect(peripheral, options: nil)
            }
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        notifyCharacteristics.removeAll()
        writeCharacteristics.removeAll()
        batteryCharacteristic = nil
        versionCharacteristic = nil
        
        peripheral.discoverServices(nil)
        
        DispatchQueue.main.async {
            self.channel.invokeMethod("onScannerConnected", arguments: true)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral == connectedPeripheral {
            connectedPeripheral = nil
            notifyCharacteristics.removeAll()
            writeCharacteristics.removeAll()
            batteryCharacteristic = nil
            versionCharacteristic = nil
            
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
        if let stringValue = String(data: data, encoding: .utf8), !stringValue.isEmpty {
            DispatchQueue.main.async {
                self.channel.invokeMethod("onBarcodeScanned", arguments: stringValue)
            }
        } else if !data.isEmpty {
            // Fallback for hex string if not valid utf8
            let hexString = data.map { String(format: "%02x", $0) }.joined()
            DispatchQueue.main.async {
                self.channel.invokeMethod("onBarcodeScanned", arguments: hexString)
            }
        }
    }
}
