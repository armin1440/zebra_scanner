import Flutter
import UIKit
import CoreBluetooth
import Security

/// BLE plugin for the scanner on iOS.
///
/// Connection rules (see docs/iOS_Scanner_Identity_Report.html, sections 6–8):
/// - Pairing: the QR code is `%%SpecCodeBA4403<token>`. The token is 4 random
///   bytes, kept until `forgetScanner`. Only a scanner that advertises
///   this token becomes a candidate (R1). After a 1.5 s window the saved
///   scanner wins, else the strongest RSSI.
/// - Ownership lock: only the connected scanner (the owner) can send data
///   (R5). Any other connection is cancelled (R3/R4). Discovery is ignored
///   when no pairing or reconnection scan is running (R2).
/// - Reconnection: only to the saved scanner (R6), optionally also checking
///   the token. It runs until the scanner connects, or until
///   `disconnect` / `forgetScanner` (R7). When iOS no longer knows the saved
///   scanner, a scan finds it again by its identifier (Apple's reconnection
///   order: known peripherals, then connected peripherals, then scan).
/// - Two addresses: in pairing mode (after it reads the pairing QR code) the
///   scanner advertises the token from a temporary address. Otherwise it
///   advertises from its own address, with the address in its manufacturer
///   data and without the token. iOS gives the two addresses different
///   identifiers. So after each connection the plugin asks the scanner for its
///   address (as the Android SDK does), and the reconnection scan finds the
///   scanner by this address.
/// - Scanning runs only while needed, only in the foreground, and restarts
///   every 30 s so iOS reports devices again.
public class ZebraScannerPlugin: NSObject, FlutterPlugin, CBCentralManagerDelegate, CBPeripheralDelegate {

    // MARK: - Constants

    private static let lastDeviceKey = "ZebraScannerLastDeviceUUID"
    private static let pairingTokenKey = "ZebraScannerPairingToken"
    /// Bluetooth address of the saved scanner (12 hex characters).
    private static let macKey = "ZebraScannerMac"
    /// Mode byte of the `%%SpecCodeBA44` command for BLE (same as the Android SDK).
    private static let pairingModeBle = "03"
    private static let defaultPairingTimeout: TimeInterval = 60
    private static let candidateWindow: TimeInterval = 1.5
    private static let candidateConnectTimeout: TimeInterval = 10
    private static let tokenReconnectConnectTimeout: TimeInterval = 10
    private static let reconnectRetryDelay: TimeInterval = 2
    private static let scanRestartInterval: TimeInterval = 30
    private static let invalidRssi = 127

    /// Vendor GATT service, and its command characteristic (same as the Android SDK).
    private static let vendorServiceUuid = CBUUID(string: "FEEA")
    private static let vendorCommandUuid = CBUUID(string: "2AA2")
    /// First byte of every vendor command and of its answer.
    private static let vendorHeader: UInt8 = 0xBA
    /// Vendor queries. The scanner has no standard Battery (2A19) or Firmware
    /// Revision (2A26) characteristic. These are the bytes of the Android SDK.
    private static let nameQuery = Data([0xBA, 0x09, 0x00, 0x58, 0x10])
    private static let versionQuery = Data([0xBA, 0x0A, 0x00, 0x01])
    private static let batteryQuery = Data([0xBA, 0x0A, 0x00, 0x02])
    /// Asks for the Bluetooth address, like the Android SDK in BLE mode
    /// (`%%SpecCodeBA0803`). The answer is the address as 12 ASCII hex
    /// characters, with no 0xBA header.
    private static let macQuery = Data([0xBA, 0x05, 0xBA, 0x08, 0x03])
    private static let queryResponseTimeout: TimeInterval = 3
    private static let gattReadyTimeout: TimeInterval = 10

    /// A vendor query that waits for the answer of the scanner.
    private struct DeviceQuery {
        let command: Data
        /// Returns nil when the packet is not a valid answer.
        let parse: (Data) -> Any?
        /// Value to return when the scanner does not answer, or nil for an error.
        let fallback: () -> Any?
        let result: FlutterResult
        /// True when the answer has no 0xBA header. Then a packet that does
        /// not parse is handled as barcode data.
        var rawAnswer = false
    }

    // MARK: - State

    private let channel: FlutterMethodChannel
    private var centralManager: CBCentralManager!

    /// The connected scanner. Only this scanner may send data.
    private var ownerPeripheral: CBPeripheral?
    /// The saved scanner that the plugin tries to reconnect to.
    private var reconnectTarget: CBPeripheral?
    /// Identifier of the saved scanner while iOS has no peripheral for it.
    /// iOS forgets scanners that are not bonded (for example after a reboot
    /// or a Bluetooth reset). A scan finds the scanner again.
    private var unresolvedReconnectId: UUID?
    private var reconnectRequiresToken = false
    /// True while a token reconnection has found the scanner and connects to it.
    private var tokenReconnectInFlight = false
    private var tokenReconnectTimeoutWorkItem: DispatchWorkItem?
    /// Last time the reconnection scan logged each identifier.
    private var lastDiscoveryLog: [UUID: Date] = [:]

    /// The scanner selected during pairing, while its connection is pending.
    private var pairingCandidate: CBPeripheral?
    private var isPairing = false
    private var candidates: [UUID: (peripheral: CBPeripheral, rssi: Int)] = [:]
    private var candidateWindowWorkItem: DispatchWorkItem?
    private var candidateConnectTimeoutWorkItem: DispatchWorkItem?
    private var pairingTimeoutWorkItem: DispatchWorkItem?

    private var isScanning = false
    private var scanRestartTimer: Timer?
    private var isInForeground = true

    /// Peripherals that the plugin disconnects on purpose. Their disconnect
    /// events do not start a reconnection.
    private var intentionalDisconnects = Set<UUID>()

    private var pendingConnectResults: [Int: FlutterResult] = [:]
    private var nextPendingResultId = 0
    private var lastEmittedState: String?
    private var cachedToken: Data?

    // GATT state of the owner
    private var notifyCharacteristics: [CBCharacteristic] = []
    private var writeCharacteristics: [CBCharacteristic] = []
    /// 2AA2 of the vendor service. When found, commands go only here.
    private var commandCharacteristic: CBCharacteristic?
    /// Queries run one at a time: the answer has no id, so the first
    /// answer belongs to the active query (same as the Android SDK).
    private var queuedQueries: [DeviceQuery] = []
    private var activeQuery: DeviceQuery?
    private var queryTimeoutWorkItem: DispatchWorkItem?
    private var gattReadyTimeoutWorkItem: DispatchWorkItem?

    private var barcodeBuffer = ""
    private var dispatchBarcodeWorkItem: DispatchWorkItem?
    private var isCoolingDown = false
    private var cooldownWorkItem: DispatchWorkItem?

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
        self.isInForeground = UIApplication.shared.applicationState != .background

        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "zebra_handheld_scanner", binaryMessenger: registrar.messenger())
        let instance = ZebraScannerPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    // MARK: - Method channel

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]

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

        case "startPairing":
            let timeout = (args?["timeoutMs"] as? Int).map { TimeInterval($0) / 1000 } ?? Self.defaultPairingTimeout
            startPairing(timeout: timeout, result: result)

        case "cancelPairing":
            if isPairing {
                endPairing()
                emitStateIfChanged()
            }
            result(nil)

        case "reconnect":
            let requireToken = args?["requireToken"] as? Bool ?? false
            let timeoutMs = args?["timeoutMs"] as? Int ?? 5000
            reconnect(requireToken: requireToken, timeoutMs: timeoutMs, result: result)

        case "getConnectionState":
            result(currentStateName)

        case "sendRawCommand":
            guard let command = args?["command"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing command", details: nil))
                return
            }
            guard ownerPeripheral != nil else {
                result(FlutterError(code: "NOT_CONNECTED", message: "No device connected", details: nil))
                return
            }
            if write(Self.dataFromHexString(command)) {
                result(nil)
            } else {
                result(FlutterError(code: "NO_WRITE_CHARACTERISTIC", message: "No writable characteristic found", details: nil))
            }

        case "getBluetoothName":
            // Answer: 2-byte header, then the name up to the first 0x00.
            // iOS often has no name for the scanner (CBPeripheral.name is nil
            // when the advertisement has no local name), so it is only the fallback.
            enqueueQuery(DeviceQuery(
                command: Self.nameQuery,
                parse: { Self.responseText($0) },
                fallback: { [weak self] in self?.ownerPeripheral?.name },
                result: result))

        case "getFirmwareVersion":
            // Answer: 2-byte header, then the version text.
            enqueueQuery(DeviceQuery(
                command: Self.versionQuery,
                parse: { Self.responseText($0) },
                fallback: { nil },
                result: result))

        case "getBatteryLevel":
            // Answer: 2-byte header, then the level (0-100) in one byte.
            enqueueQuery(DeviceQuery(
                command: Self.batteryQuery,
                parse: { $0.count > 2 ? Int($0[$0.startIndex + 2]) : nil },
                fallback: { nil },
                result: result))

        case "setBluetoothName":
            setBluetoothName(args?["name"] as? String, result: result)

        case "disconnect":
            disconnectAll(forget: false)
            result(nil)

        case "forgetScanner":
            disconnectAll(forget: true)
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Pairing

    private func startPairing(timeout: TimeInterval, result: @escaping FlutterResult) {
        switch centralManager.state {
        case .poweredOff:
            result(FlutterError(code: "BLE_OFF", message: "Bluetooth is not powered on", details: nil))
            return
        case .unauthorized:
            result(FlutterError(code: "BLE_UNAUTHORIZED", message: "Bluetooth permission is not granted", details: nil))
            return
        case .unsupported:
            result(FlutterError(code: "BLE_UNSUPPORTED", message: "Bluetooth LE is not supported", details: nil))
            return
        default:
            // .poweredOn, or .unknown / .resetting: the scan starts when Bluetooth is ready.
            break
        }

        isPairing = true
        resetCandidates()

        pairingTimeoutWorkItem?.cancel()
        let timeoutItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isPairing else { return }
            self.endPairing()
            self.emitStateIfChanged()
        }
        pairingTimeoutWorkItem = timeoutItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

        updateScan(forceRestart: true)
        emitStateIfChanged()

        result("%%SpecCodeBA44" + Self.pairingModeBle + Self.hexString(pairingToken()))
    }

    /// Stops pairing. A connected owner stays connected.
    private func endPairing() {
        isPairing = false
        pairingTimeoutWorkItem?.cancel()
        pairingTimeoutWorkItem = nil
        resetCandidates()
        candidateConnectTimeoutWorkItem?.cancel()
        candidateConnectTimeoutWorkItem = nil
        if let candidate = pairingCandidate {
            pairingCandidate = nil
            cancelConnection(candidate)
        }
        updateScan()
    }

    private func resetCandidates() {
        candidates.removeAll()
        candidateWindowWorkItem?.cancel()
        candidateWindowWorkItem = nil
    }

    private func collectCandidate(_ peripheral: CBPeripheral, rssi: Int) {
        if let existing = candidates[peripheral.identifier] {
            candidates[peripheral.identifier] = (peripheral, max(existing.rssi, rssi))
        } else {
            candidates[peripheral.identifier] = (peripheral, rssi)
        }

        if candidateWindowWorkItem == nil {
            let item = DispatchWorkItem { [weak self] in
                self?.chooseCandidate()
            }
            candidateWindowWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.candidateWindow, execute: item)
        }
    }

    /// Saved scanner first, else the strongest RSSI.
    private func chooseCandidate() {
        candidateWindowWorkItem = nil
        guard isPairing, pairingCandidate == nil, !candidates.isEmpty else { return }

        let chosen: CBPeripheral
        if let savedId = savedDeviceId, let saved = candidates[savedId] {
            chosen = saved.peripheral
        } else if let strongest = candidates.values.max(by: { $0.rssi < $1.rssi }) {
            chosen = strongest.peripheral
        } else {
            return
        }
        candidates.removeAll()

        pairingCandidate = chosen
        updateScan()
        intentionalDisconnects.remove(chosen.identifier)
        centralManager.connect(chosen, options: nil)

        candidateConnectTimeoutWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, let candidate = self.pairingCandidate,
                  candidate.identifier == chosen.identifier else { return }
            self.pairingCandidate = nil
            self.cancelConnection(candidate)
            self.updateScan(forceRestart: true)
        }
        candidateConnectTimeoutWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.candidateConnectTimeout, execute: item)
    }

    // MARK: - Reconnection

    private var savedDeviceId: UUID? {
        guard let value = UserDefaults.standard.string(forKey: Self.lastDeviceKey) else { return nil }
        return UUID(uuidString: value)
    }

    private func reconnect(requireToken: Bool, timeoutMs: Int, result: @escaping FlutterResult) {
        guard let savedId = savedDeviceId else {
            log("reconnect: no saved scanner")
            result(false)
            return
        }
        if let owner = ownerPeripheral, owner.identifier == savedId {
            result(true)
            return
        }
        guard centralManager.state == .poweredOn else {
            log("reconnect: Bluetooth state is \(centralManager.state.rawValue), not poweredOn")
            result(false)
            return
        }

        if reconnectTarget?.identifier != savedId {
            if let old = reconnectTarget {
                reconnectTarget = nil
                cancelConnection(old)
            }
            tokenReconnectInFlight = false
            if let peripheral = knownPeripheral(savedId) {
                log("reconnect: iOS knows \(savedId) (state \(peripheral.state.rawValue)), connection pending")
                reconnectTarget = peripheral
                unresolvedReconnectId = nil
            } else {
                log("reconnect: iOS does not know \(savedId), scanning for it")
                unresolvedReconnectId = savedId
            }
        }

        if requireToken != reconnectRequiresToken {
            if requireToken, let target = reconnectTarget {
                // Drop the direct pending connection. The token scan replaces it.
                cancelConnection(target)
            }
            tokenReconnectTimeoutWorkItem?.cancel()
            tokenReconnectInFlight = false
            reconnectRequiresToken = requireToken
        }

        addPendingConnectResult(result, timeoutMs: timeoutMs)
        startReconnect()
    }

    /// The peripheral of the saved scanner, if iOS still knows it or has a
    /// connection to it (for example from another app).
    private func knownPeripheral(_ id: UUID) -> CBPeripheral? {
        centralManager.retrievePeripherals(withIdentifiers: [id]).first
            ?? centralManager.retrieveConnectedPeripherals(withServices: [Self.vendorServiceUuid])
                .first { $0.identifier == id }
    }

    private var savedMac: Data? {
        guard let hex = UserDefaults.standard.string(forKey: Self.macKey) else { return nil }
        let mac = Self.dataFromHexString(hex)
        return mac.count == 6 ? mac : nil
    }

    /// The scanner advertises from its own address: the target becomes this
    /// peripheral. After the connection, its identifier is the saved one.
    private func switchReconnectTarget(to peripheral: CBPeripheral) {
        if let old = reconnectTarget {
            reconnectTarget = nil
            cancelConnection(old)
        }
        unresolvedReconnectId = nil
        tokenReconnectTimeoutWorkItem?.cancel()
        tokenReconnectInFlight = false
        reconnectTarget = peripheral
        if reconnectRequiresToken {
            // The token check of the scan decides.
            updateScan()
        } else {
            startReconnect()
        }
    }

    private func startReconnect() {
        defer { emitStateIfChanged() }
        guard let target = reconnectTarget, ownerPeripheral == nil,
              centralManager.state == .poweredOn else {
            updateScan()
            return
        }
        if !reconnectRequiresToken {
            // Pending connection: iOS connects when the scanner advertises,
            // with no timeout, also in the background.
            intentionalDisconnects.remove(target.identifier)
            centralManager.connect(target, options: nil)
        }
        updateScan()
    }

    private func retryReconnect(after delay: TimeInterval) {
        guard let target = reconnectTarget else { return }
        let targetId = target.identifier
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.ownerPeripheral == nil,
                  self.reconnectTarget?.identifier == targetId else { return }
            self.startReconnect()
        }
    }

    private func connectTokenReconnectTarget(_ target: CBPeripheral) {
        tokenReconnectInFlight = true
        updateScan()
        intentionalDisconnects.remove(target.identifier)
        centralManager.connect(target, options: nil)

        tokenReconnectTimeoutWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, self.tokenReconnectInFlight,
                  self.reconnectTarget?.identifier == target.identifier else { return }
            self.tokenReconnectInFlight = false
            self.cancelConnection(target)
            self.updateScan(forceRestart: true)
        }
        tokenReconnectTimeoutWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.tokenReconnectConnectTimeout, execute: item)
    }

    private func addPendingConnectResult(_ result: @escaping FlutterResult, timeoutMs: Int) {
        let id = nextPendingResultId
        nextPendingResultId += 1
        pendingConnectResults[id] = result
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(max(0, timeoutMs))) { [weak self] in
            if let pending = self?.pendingConnectResults.removeValue(forKey: id) {
                pending(false)
            }
        }
    }

    private func completePendingConnectResults(_ value: Bool) {
        let results = Array(pendingConnectResults.values)
        pendingConnectResults.removeAll()
        results.forEach { $0(value) }
    }

    // MARK: - Disconnect

    private func disconnectAll(forget: Bool) {
        endPairing()

        tokenReconnectTimeoutWorkItem?.cancel()
        tokenReconnectInFlight = false
        unresolvedReconnectId = nil
        if let target = reconnectTarget {
            reconnectTarget = nil
            cancelConnection(target)
        }
        completePendingConnectResults(false)

        if let owner = ownerPeripheral {
            ownerPeripheral = nil
            resetGattState()
            cancelConnection(owner)
            channel.invokeMethod("onScannerConnected", arguments: false)
        }

        if forget {
            UserDefaults.standard.removeObject(forKey: Self.lastDeviceKey)
            UserDefaults.standard.removeObject(forKey: Self.macKey)
            rotatePairingToken()
        }

        updateScan()
        emitStateIfChanged()
    }

    private func cancelConnection(_ peripheral: CBPeripheral) {
        intentionalDisconnects.insert(peripheral.identifier)
        centralManager.cancelPeripheralConnection(peripheral)
    }

    // MARK: - Owner

    private func adoptOwner(_ peripheral: CBPeripheral) {
        log("connected to \(peripheral.identifier)")
        intentionalDisconnects.remove(peripheral.identifier)
        resetGattState()
        ownerPeripheral = peripheral
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.lastDeviceKey)

        peripheral.delegate = self
        peripheral.discoverServices(nil)
        // First in the queue: it runs as soon as the command service is ready.
        enqueueQuery(DeviceQuery(
            command: Self.macQuery,
            parse: { Self.parseMac($0) },
            fallback: { nil },
            result: { [weak self] value in
                guard let self = self else { return }
                guard let mac = value as? Data else {
                    self.log("mac: the scanner did not answer")
                    return
                }
                UserDefaults.standard.set(Self.hexString(mac), forKey: Self.macKey)
                self.log("mac: \(Self.hexString(mac))")
            },
            rawAnswer: true))

        updateScan()
        completePendingConnectResults(true)
        channel.invokeMethod("onScannerConnected", arguments: true)
        emitStateIfChanged()
    }

    private func resetGattState() {
        notifyCharacteristics.removeAll()
        writeCharacteristics.removeAll()
        commandCharacteristic = nil
        failQueries(code: "NOT_CONNECTED", message: "Scanner disconnected", useFallback: false)
        barcodeBuffer = ""
        dispatchBarcodeWorkItem?.cancel()
        cooldownWorkItem?.cancel()
        isCoolingDown = false
    }

    private func setBluetoothName(_ name: String?, result: @escaping FlutterResult) {
        guard let name = name, !name.isEmpty else {
            result(FlutterError(code: "INVALID_ARGS", message: "Name is empty", details: nil))
            return
        }
        guard ownerPeripheral != nil, !writeCharacteristics.isEmpty else {
            result(FlutterError(code: "NOT_CONNECTED", message: "No device connected", details: nil))
            return
        }
        // Same sequence as the vendor Android SDK: "Set Bluetooth Name"
        // (%%SpecCodeEC), then the name as a virtual scan (OP 0x04).
        _ = write(Data([0xBA, 0x05, 0xEC]))
        let nameBytes = Data(name.utf8.prefix(16))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            _ = self?.write(Data([0xBA, 0x04]) + nameBytes)
        }
        result(nil)
    }

    private func write(_ data: Data) -> Bool {
        guard let peripheral = ownerPeripheral else { return false }
        var wrote = false
        let targets = commandCharacteristic.map { [$0] } ?? writeCharacteristics
        for char in targets {
            let type: CBCharacteristicWriteType = char.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            peripheral.writeValue(data, for: char, type: type)
            wrote = true
        }
        return wrote
    }

    // MARK: - Vendor queries

    /// True when a command can be sent and its answer received. With the
    /// vendor service, this needs 2AA2 and a notifying characteristic of it.
    private var isGattReady: Bool {
        guard let services = ownerPeripheral?.services else { return false }
        if services.contains(where: { $0.uuid == Self.vendorServiceUuid }) {
            return commandCharacteristic != nil && notifyCharacteristics.contains {
                $0.isNotifying && $0.service?.uuid == Self.vendorServiceUuid
            }
        }
        return !writeCharacteristics.isEmpty && notifyCharacteristics.contains { $0.isNotifying }
    }

    private func enqueueQuery(_ query: DeviceQuery) {
        guard ownerPeripheral != nil else {
            query.result(FlutterError(code: "NOT_CONNECTED", message: "No device connected", details: nil))
            return
        }
        queuedQueries.append(query)
        if !isGattReady && gattReadyTimeoutWorkItem == nil {
            // Queries can come right after the connection, before service discovery.
            let item = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.gattReadyTimeoutWorkItem = nil
                if !self.isGattReady {
                    self.failQueries(code: "NO_WRITE_CHARACTERISTIC",
                                     message: "The scanner command service is not available",
                                     useFallback: true)
                }
            }
            gattReadyTimeoutWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.gattReadyTimeout, execute: item)
        }
        sendNextQuery()
    }

    private func sendNextQuery() {
        guard activeQuery == nil, !queuedQueries.isEmpty, isGattReady else { return }
        gattReadyTimeoutWorkItem?.cancel()
        gattReadyTimeoutWorkItem = nil

        let query = queuedQueries.removeFirst()
        activeQuery = query
        _ = write(query.command)

        let item = DispatchWorkItem { [weak self] in
            self?.finishActiveQuery(with: nil)
        }
        queryTimeoutWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.queryResponseTimeout, execute: item)
    }

    /// Completes the active query. A nil value means no answer: the fallback is used.
    private func finishActiveQuery(with value: Any?) {
        queryTimeoutWorkItem?.cancel()
        queryTimeoutWorkItem = nil
        guard let query = activeQuery else { return }
        activeQuery = nil
        if let value = value ?? query.fallback() {
            query.result(value)
        } else {
            query.result(FlutterError(code: "TIMEOUT", message: "The scanner did not answer", details: nil))
        }
        sendNextQuery()
    }

    private func failQueries(code: String, message: String, useFallback: Bool) {
        queryTimeoutWorkItem?.cancel()
        queryTimeoutWorkItem = nil
        gattReadyTimeoutWorkItem?.cancel()
        gattReadyTimeoutWorkItem = nil
        let queries = (activeQuery.map { [$0] } ?? []) + queuedQueries
        activeQuery = nil
        queuedQueries.removeAll()
        for query in queries {
            if useFallback, let value = query.fallback() {
                query.result(value)
            } else {
                query.result(FlutterError(code: code, message: message, details: nil))
            }
        }
    }

    /// The Bluetooth address in the answer to `macQuery`: 12 ASCII hex
    /// characters (the Android SDK reads the first 12 bytes). Also accepts
    /// them after a 2-byte 0xBA header.
    private static func parseMac(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        for offset in [0, 2] where bytes.count >= offset + 12 {
            if offset == 2 && bytes[0] != vendorHeader { continue }
            guard let text = String(bytes: bytes[offset..<offset + 12], encoding: .ascii),
                  text.allSatisfy(\.isHexDigit) else { continue }
            return dataFromHexString(text)
        }
        return nil
    }

    /// True when the manufacturer data contains the address, in either byte order.
    private static func advertisesMac(_ mac: Data, _ advertisementData: [String: Any]) -> Bool {
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else { return false }
        return data.range(of: mac) != nil || data.range(of: Data(mac.reversed())) != nil
    }

    /// Text after the 2-byte answer header, up to the first 0x00.
    private static func responseText(_ data: Data) -> String? {
        let payload = Data(data.dropFirst(2).prefix { $0 != 0 })
        guard let text = String(data: payload, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    // MARK: - Scanning

    private var needsPairingScan: Bool {
        isPairing && pairingCandidate == nil
    }

    private var needsReconnectScan: Bool {
        // The scan finds the scanner by its address when it advertises from an
        // identifier other than the target (see the two addresses above).
        guard ownerPeripheral == nil, !tokenReconnectInFlight else { return false }
        return unresolvedReconnectId != nil || reconnectTarget != nil
    }

    private func updateScan(forceRestart: Bool = false) {
        let shouldScan = centralManager.state == .poweredOn && isInForeground
            && (needsPairingScan || needsReconnectScan)
        if shouldScan {
            if !isScanning || forceRestart {
                startScan()
            }
        } else if isScanning {
            stopScan()
        }
    }

    private func startScan() {
        let options: [String: Any] = [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        if isScanning {
            centralManager.stopScan()
        }
        centralManager.scanForPeripherals(withServices: nil, options: options)
        isScanning = true
        log("scan: started (pairing=\(needsPairingScan) reconnect=\(needsReconnectScan))")

        scanRestartTimer?.invalidate()
        scanRestartTimer = Timer.scheduledTimer(withTimeInterval: Self.scanRestartInterval, repeats: true) { [weak self] _ in
            guard let self = self, self.isScanning else { return }
            self.centralManager.stopScan()
            self.centralManager.scanForPeripherals(withServices: nil, options: options)
        }
    }

    private func stopScan() {
        centralManager.stopScan()
        isScanning = false
        log("scan: stopped")
        scanRestartTimer?.invalidate()
        scanRestartTimer = nil
    }

    @objc private func appDidEnterBackground() {
        isInForeground = false
        updateScan()
    }

    @objc private func appWillEnterForeground() {
        isInForeground = true
        updateScan(forceRestart: true)
    }

    // MARK: - Token

    private func pairingToken() -> Data {
        if let token = cachedToken {
            return token
        }
        if let hex = UserDefaults.standard.string(forKey: Self.pairingTokenKey) {
            let data = Self.dataFromHexString(hex)
            if data.count == 4 {
                cachedToken = data
                return data
            }
        }
        return rotatePairingToken()
    }

    @discardableResult
    private func rotatePairingToken() -> Data {
        var bytes = [UInt8](repeating: 0, count: 4)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            for index in bytes.indices {
                bytes[index] = UInt8.random(in: 0...255)
            }
        }
        let data = Data(bytes)
        UserDefaults.standard.set(Self.hexString(data), forKey: Self.pairingTokenKey)
        cachedToken = data
        return data
    }

    /// True when the advertisement contains the token of this phone:
    /// service data of UUID FD05, or manufacturer data (company 0x0133).
    /// The Android SDK checks the same two places.
    private func advertisesToken(_ advertisementData: [String: Any]) -> Bool {
        let token = pairingToken()
        if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            for (_, data) in serviceData where data.range(of: token) != nil {
                return true
            }
        }
        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
           manufacturerData.range(of: token) != nil {
            return true
        }
        return false
    }

    // MARK: - State

    private var currentStateName: String {
        if isPairing { return "pairing" }
        if ownerPeripheral != nil { return "connected" }
        if reconnectTarget != nil || unresolvedReconnectId != nil { return "reconnecting" }
        return "idle"
    }

    /// Writes to the device log and sends the message to Dart (`onLog`).
    private func log(_ message: String) {
        NSLog("[ZebraScanner] %@", message)
        channel.invokeMethod("onLog", arguments: message)
    }

    /// Diagnostics: logs every advertisement that looks like the scanner
    /// (saved identifier, token, service data FD05, manufacturer 0x0133,
    /// service FEEA, or "BLE" in the name), with its raw data.
    /// At most once every 5 s for each identifier.
    private func logDiscovery(_ peripheral: CBPeripheral, _ advertisementData: [String: Any], rssi: Int) {
        let id = peripheral.identifier
        let savedId = reconnectTarget?.identifier ?? unresolvedReconnectId ?? savedDeviceId
        let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? [:]
        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let serviceUuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        let hasToken = advertisesToken(advertisementData)
        let looksLikeScanner = hasToken
            || serviceData.keys.contains(CBUUID(string: "FD05"))
            || manufacturerData.map { $0.count >= 2 && $0[$0.startIndex] == 0x33 && $0[$0.startIndex + 1] == 0x01 } == true
            || serviceUuids.contains(Self.vendorServiceUuid)
            || name?.range(of: "BLE", options: .caseInsensitive) != nil
        guard id == savedId || looksLikeScanner else { return }
        let now = Date()
        if let last = lastDiscoveryLog[id], now.timeIntervalSince(last) < 5 { return }
        lastDiscoveryLog[id] = now

        let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue
        let serviceDataText = serviceData.map { "\($0.key)=\(Self.hexString($0.value))" }.joined(separator: ",")
        log("scan: \(id == savedId ? "SAVED" : "other") \(id) name=\(name ?? "-") rssi=\(rssi)"
            + " connectable=\(connectable.map { "\($0)" } ?? "?") token=\(hasToken)"
            + " sd=[\(serviceDataText)] mfr=\(manufacturerData.map { Self.hexString($0) } ?? "-")"
            + " uuids=\(serviceUuids.map { $0.uuidString })")
    }

    private func emitStateIfChanged() {
        let state = currentStateName
        guard state != lastEmittedState else { return }
        lastEmittedState = state
        channel.invokeMethod("onConnectionStateChanged", arguments: state)
    }

    // MARK: - Barcode data

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

    // MARK: - Hex helpers

    private static func dataFromHexString(_ hex: String) -> Data {
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

    private static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }

    private func isOwner(_ peripheral: CBPeripheral) -> Bool {
        ownerPeripheral?.identifier == peripheral.identifier
    }

    // MARK: - CBCentralManagerDelegate

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if reconnectTarget != nil {
                startReconnect()
            }
            updateScan(forceRestart: true)
        case .poweredOff, .resetting, .unauthorized, .unsupported:
            // iOS stops scans and drops connections. Keep the saved scanner as
            // the reconnection target for when Bluetooth is back.
            isScanning = false
            scanRestartTimer?.invalidate()
            scanRestartTimer = nil
            candidateConnectTimeoutWorkItem?.cancel()
            pairingCandidate = nil
            tokenReconnectTimeoutWorkItem?.cancel()
            tokenReconnectInFlight = false
            if let owner = ownerPeripheral {
                ownerPeripheral = nil
                resetGattState()
                reconnectTarget = owner
                channel.invokeMethod("onScannerConnected", arguments: false)
            }
        default:
            break
        }
        emitStateIfChanged()
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let rssi = RSSI.intValue
        guard rssi != Self.invalidRssi else { return }
        if needsPairingScan || needsReconnectScan {
            logDiscovery(peripheral, advertisementData, rssi: rssi)
        }

        if needsPairingScan {
            if isOwner(peripheral) { return }
            if advertisesToken(advertisementData) {
                collectCandidate(peripheral, rssi: rssi)
            }
            return
        }

        if needsReconnectScan {
            if let mac = savedMac, peripheral.identifier != reconnectTarget?.identifier,
               Self.advertisesMac(mac, advertisementData) {
                log("reconnect: found \(Self.hexString(mac)) as \(peripheral.identifier)")
                switchReconnectTarget(to: peripheral)
                return
            }
            if let id = unresolvedReconnectId {
                guard peripheral.identifier == id else { return }
                if reconnectRequiresToken && !advertisesToken(advertisementData) { return }
                log("reconnect: found \(id) by scan")
                unresolvedReconnectId = nil
                reconnectTarget = peripheral
                if reconnectRequiresToken {
                    connectTokenReconnectTarget(peripheral)
                } else {
                    startReconnect()
                }
                return
            }
            if reconnectRequiresToken, let target = reconnectTarget {
                guard peripheral.identifier == target.identifier, advertisesToken(advertisementData) else { return }
                connectTokenReconnectTarget(target)
            }
            return
        }

        // Idle or connected: discovery is ignored.
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let id = peripheral.identifier

        // Pairing: the operator read the QR code with this scanner on purpose.
        if let candidate = pairingCandidate, candidate.identifier == id {
            candidateConnectTimeoutWorkItem?.cancel()
            pairingCandidate = nil
            // The address of the new scanner comes after the connection.
            UserDefaults.standard.removeObject(forKey: Self.macKey)
            if let old = ownerPeripheral, old.identifier != id {
                ownerPeripheral = nil
                resetGattState()
                cancelConnection(old)
            }
            if let target = reconnectTarget, target.identifier != id {
                cancelConnection(target)
            }
            reconnectTarget = nil
            unresolvedReconnectId = nil
            tokenReconnectTimeoutWorkItem?.cancel()
            tokenReconnectInFlight = false
            endPairing()
            adoptOwner(peripheral)
            return
        }

        // Reconnection: only the saved scanner.
        if ownerPeripheral == nil, let target = reconnectTarget, target.identifier == id {
            reconnectTarget = nil
            tokenReconnectTimeoutWorkItem?.cancel()
            tokenReconnectInFlight = false
            if isPairing {
                endPairing()
            }
            adoptOwner(peripheral)
            return
        }

        if isOwner(peripheral) {
            return
        }

        // Any other connection is not allowed.
        cancelConnection(peripheral)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let id = peripheral.identifier
        if let candidate = pairingCandidate, candidate.identifier == id {
            candidateConnectTimeoutWorkItem?.cancel()
            pairingCandidate = nil
            updateScan(forceRestart: true)
            return
        }
        if let target = reconnectTarget, target.identifier == id {
            log("reconnect: connection to \(id) failed: \(error?.localizedDescription ?? "no error")")
            tokenReconnectTimeoutWorkItem?.cancel()
            tokenReconnectInFlight = false
            retryReconnect(after: Self.reconnectRetryDelay)
        }
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let id = peripheral.identifier
        let intentional = intentionalDisconnects.remove(id) != nil

        if isOwner(peripheral) {
            ownerPeripheral = nil
            resetGattState()
            channel.invokeMethod("onScannerConnected", arguments: false)
            if !intentional {
                // Lost the owner (distance, sleep, metal): reconnect only to it.
                reconnectTarget = peripheral
                tokenReconnectInFlight = false
                startReconnect()
            }
            emitStateIfChanged()
            return
        }

        if intentional {
            return
        }

        if let candidate = pairingCandidate, candidate.identifier == id {
            candidateConnectTimeoutWorkItem?.cancel()
            pairingCandidate = nil
            updateScan(forceRestart: true)
            return
        }

        if let target = reconnectTarget, target.identifier == id {
            log("reconnect: \(id) disconnected: \(error?.localizedDescription ?? "no error")")
            tokenReconnectTimeoutWorkItem?.cancel()
            tokenReconnectInFlight = false
            retryReconnect(after: Self.reconnectRetryDelay)
        }
    }

    // MARK: - CBPeripheralDelegate

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard isOwner(peripheral), let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard isOwner(peripheral), let characteristics = service.characteristics else { return }

        for char in characteristics {
            let props = char.properties

            if props.contains(.notify) || props.contains(.indicate) {
                notifyCharacteristics.append(char)
                peripheral.setNotifyValue(true, for: char)
            }

            if props.contains(.write) || props.contains(.writeWithoutResponse) {
                writeCharacteristics.append(char)
                if service.uuid == Self.vendorServiceUuid && char.uuid == Self.vendorCommandUuid {
                    commandCharacteristic = char
                }
            }
        }
        sendNextQuery()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard isOwner(peripheral) else { return }
        sendNextQuery()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // Data only from the owner. A stale connection cannot send barcodes.
        guard isOwner(peripheral), let data = characteristic.value else { return }

        // Answer to a vendor query: it starts with 0xBA, which cannot start
        // UTF-8 barcode text. A packet that does not parse (for example the
        // acknowledgement of a setting) is dropped, and the query keeps waiting.
        if let query = activeQuery, data.first == Self.vendorHeader || query.rawAnswer {
            if let value = query.parse(data) {
                finishActiveQuery(with: value)
                return
            }
            if data.first == Self.vendorHeader { return }
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

            if isCoolingDown {
                return
            }

            barcodeBuffer += text

            dispatchBarcodeWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.dispatchAccumulatedBarcode()
            }
            dispatchBarcodeWorkItem = workItem

            // Use a 0.25s debounce window. This is the "silence timeout" between
            // BLE packets. 0.25s is long enough to keep a single scan together,
            // but short enough to fire BEFORE a second physical scan begins.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
        }
    }
}
