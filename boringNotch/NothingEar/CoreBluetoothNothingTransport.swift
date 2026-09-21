import Foundation
@preconcurrency import CoreBluetooth

/// CoreBluetooth transport used by Nothing Bar and swift-nothing-ear.
///
/// The earbuds expose their control protocol over the proprietary FD90 GATT
/// service. The browser project uses the same protocol over SPP, but the
/// native macOS path is BLE/GATT and therefore does not depend on a guessed
/// RFCOMM channel.
@MainActor
final class CoreBluetoothNothingTransport: NSObject, BluetoothTransport, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    private static let fastPairUUID = CBUUID(string: "FE2C")
    private static let controlServiceUUID = CBUUID(string: "FD90")

    private static let standardServiceUUIDs: Set<String> = [
        "1800", "1801", "180A", "180F",
        "1844", "1846", "184D", "184E", "184F", "1850", "1853", "1855",
        "FE2C"
    ]

    private var centralManager: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var records: [String: BluetoothDeviceRecord] = [:]
    private var isScanning = false

    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var writeType: CBCharacteristicWriteType = .withResponse

    private var connectionContinuation: CheckedContinuation<Void, Error>?
    private var pendingDevice: BluetoothDeviceRecord?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var candidateServiceCount = 0
    private var isDisconnecting = false

    private(set) var currentDevice: BluetoothDeviceRecord?

    private let eventContinuation: AsyncStream<TransportEvent>.Continuation
    let events: AsyncStream<TransportEvent>

    override init() {
        var continuation: AsyncStream<TransportEvent>.Continuation!
        events = AsyncStream { continuation = $0 }
        eventContinuation = continuation
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }

    func discover() -> [BluetoothDeviceRecord] {
        guard centralManager.state == .poweredOn else {
            return sortedRecords
        }

        registerConnectedPeripherals()
        startScanIfNeeded()
        return sortedRecords
    }

    func connect(to device: BluetoothDeviceRecord) async throws {
        disconnect()
        isDisconnecting = false

        guard centralManager.state == .poweredOn else {
            throw NothingProtocolError.transportUnavailable
        }
        guard let peripheral = peripheral(for: device.address) else {
            throw NothingProtocolError.deviceNotFound
        }

        connectedPeripheral = peripheral
        pendingDevice = device
        peripheral.delegate = self

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connectionContinuation = continuation
            connectionTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.failPendingConnection(with: .connectionTimeout)
            }

            if peripheral.state == .connected {
                beginServiceDiscovery(for: peripheral)
            } else {
                centralManager.connect(peripheral, options: nil)
            }
        }
    }

    func disconnect() {
        isDisconnecting = true
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil

        connectionContinuation?.resume(throwing: NothingProtocolError.transportUnavailable)
        connectionContinuation = nil

        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        candidateServiceCount = 0

        if currentDevice != nil {
            eventContinuation.yield(.disconnected(reason: "Closed by application"))
        }
        currentDevice = nil
        pendingDevice = nil
    }

    func write(_ data: Data) throws {
        guard let peripheral = connectedPeripheral,
              peripheral.state == .connected,
              let characteristic = writeCharacteristic else {
            throw NothingProtocolError.transportUnavailable
        }
        guard !data.isEmpty else { return }

        let maximumLength = peripheral.maximumWriteValueLength(for: writeType)
        let chunkLength = maximumLength > 0 ? maximumLength : data.count
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkLength, data.count)
            peripheral.writeValue(Data(data[offset..<end]), for: characteristic, type: writeType)
            offset = end
        }
    }

    private var sortedRecords: [BluetoothDeviceRecord] {
        records.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func startScanIfNeeded() {
        guard !isScanning else { return }

        // FE2C is the Fast Pair service used by Nothing devices. A nil
        // service filter is intentional here: macOS can hide that UUID from
        // advertisements while the device is already paired, so we filter
        // by the factory name in didDiscover as a compatible fallback.
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        isScanning = true
    }

    private func registerConnectedPeripherals() {
        var connected: [UUID: CBPeripheral] = [:]
        for serviceUUID in [Self.fastPairUUID, Self.controlServiceUUID] {
            for peripheral in centralManager.retrieveConnectedPeripherals(withServices: [serviceUUID]) {
                connected[peripheral.identifier] = peripheral
            }
        }

        for peripheral in connected.values {
            register(peripheral, isConnected: true)
        }
    }

    private func register(_ peripheral: CBPeripheral, isConnected: Bool = false, advertisedName: String? = nil) {
        peripherals[peripheral.identifier] = peripheral
        let name = [advertisedName, peripheral.name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "Nothing device"
        let record = BluetoothDeviceRecord(
            address: peripheral.identifier.uuidString,
            name: name,
            isConnected: isConnected || peripheral.state == .connected,
            lastSeen: .now
        )
        records[record.address] = record
        eventContinuation.yield(.discovered(record))
    }

    private func peripheral(for address: String) -> CBPeripheral? {
        if let peripheral = peripherals.values.first(where: { $0.identifier.uuidString.caseInsensitiveCompare(address) == .orderedSame }) {
            return peripheral
        }
        guard let identifier = UUID(uuidString: address), centralManager.state == .poweredOn else {
            return nil
        }
        let retrieved = centralManager.retrievePeripherals(withIdentifiers: [identifier]).first
        if let retrieved {
            peripherals[retrieved.identifier] = retrieved
        }
        return retrieved
    }

    private func beginServiceDiscovery(for peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    private func finishConnection() {
        guard let continuation = connectionContinuation,
              let peripheral = connectedPeripheral else { return }

        connectionContinuation = nil
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil

        let name = pendingDevice?.name ?? peripheral.name ?? "Nothing device"
        let record = BluetoothDeviceRecord(
            address: peripheral.identifier.uuidString,
            name: name,
            isConnected: true,
            lastSeen: .now
        )
        records[record.address] = record
        currentDevice = record
        pendingDevice = nil
        isDisconnecting = false
        eventContinuation.yield(.connected)
        continuation.resume()
    }

    private func failPendingConnection(with error: NothingProtocolError) {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        candidateServiceCount = 0

        let continuation = connectionContinuation
        connectionContinuation = nil
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        pendingDevice = nil
        continuation?.resume(throwing: error)
    }

    private func candidateServices(from services: [CBService]) -> [CBService] {
        let exact = services.filter { $0.uuid == Self.controlServiceUUID }
        if !exact.isEmpty { return exact }

        return services.filter {
            !Self.standardServiceUUIDs.contains($0.uuid.uuidString.uppercased())
        }
    }

    private func selectCharacteristics(from characteristics: [CBCharacteristic]) -> (write: CBCharacteristic, notify: CBCharacteristic?)? {
        let write = characteristics.first(where: { $0.properties.contains(.write) })
            ?? characteristics.first(where: { $0.properties.contains(.writeWithoutResponse) })
        guard let write else { return nil }

        let notify = characteristics.first(where: { $0.properties.contains(.notify) })
            ?? characteristics.first(where: { $0.properties.contains(.indicate) })
        return (write, notify)
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state: BluetoothAdapterState = switch central.state {
        case .unknown: .unknown
        case .resetting: .resetting
        case .unsupported: .unsupported
        case .unauthorized: .unauthorized
        case .poweredOff: .poweredOff
        case .poweredOn: .poweredOn
        @unknown default: .unknown
        }
        eventContinuation.yield(.adapterState(state))

        if central.state == .poweredOn {
            registerConnectedPeripherals()
            startScanIfNeeded()
        } else if connectionContinuation != nil {
            failPendingConnection(with: .transportUnavailable)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let advertisesFastPair = serviceUUIDs.contains(Self.fastPairUUID)
        let name = advertisedName ?? peripheral.name ?? ""
        guard advertisesFastPair || Self.looksLikeNothingDevice(name) else { return }
        register(peripheral, advertisedName: advertisedName)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isScanning = false
        central.stopScan()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        beginServiceDiscovery(for: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        failPendingConnection(with: .bluetoothError(Int32((error as NSError?)?.code ?? -1)))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard connectedPeripheral?.identifier == peripheral.identifier else { return }
        let wasApplicationDisconnect = isDisconnecting
        connectedPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        candidateServiceCount = 0
        currentDevice = nil

        if connectionContinuation != nil {
            failPendingConnection(with: .transportUnavailable)
        }
        if !wasApplicationDisconnect {
            let detail = error.map { "Bluetooth error \(($0 as NSError).code)" }
            eventContinuation.yield(.disconnected(reason: detail))
        }
        isDisconnecting = false
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else {
            failPendingConnection(with: .channelUnavailable)
            return
        }

        let candidates = candidateServices(from: services)
        candidateServiceCount = candidates.count
        guard !candidates.isEmpty else {
            failPendingConnection(with: .channelUnavailable)
            return
        }
        for service in candidates {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        defer { candidateServiceCount = max(candidateServiceCount - 1, 0) }
        guard error == nil, let characteristics = service.characteristics else {
            if candidateServiceCount <= 1 { failPendingConnection(with: .channelUnavailable) }
            return
        }
        guard let selected = selectCharacteristics(from: characteristics) else {
            if candidateServiceCount <= 1 { failPendingConnection(with: .channelUnavailable) }
            return
        }

        writeCharacteristic = selected.write
        writeType = selected.write.properties.contains(.write) ? .withResponse : .withoutResponse
        notifyCharacteristic = selected.notify

        if let notifyCharacteristic {
            peripheral.setNotifyValue(true, for: notifyCharacteristic)
        } else {
            finishConnection()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == notifyCharacteristic?.uuid else { return }
        if error == nil && characteristic.isNotifying {
            finishConnection()
        } else {
            failPendingConnection(with: .channelUnavailable)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value, !data.isEmpty else { return }
        eventContinuation.yield(.bytes(data))
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let error else { return }
        eventContinuation.yield(.disconnected(reason: "Bluetooth write failed: \((error as NSError).code)"))
    }

    private static func looksLikeNothingDevice(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return normalized.contains("nothing")
            || normalized.contains("cmf")
            || normalized.hasPrefix("ear")
            || normalized.hasPrefix("headphone")
    }
}

