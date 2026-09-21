import AppKit
import Combine
import Foundation

struct DeviceEvent: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case connected
        case disconnected
        case noiseControl
        case lowBattery
        case refreshed
    }

    let id: UUID
    let kind: Kind
    let title: String
    let detail: String?

    init(kind: Kind, title: String, detail: String? = nil) {
        self.id = UUID()
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

@MainActor
final class DeviceManager: ObservableObject {
    static let shared = DeviceManager()
    @Published private(set) var state: DeviceState = .empty
    @Published private(set) var discoveredDevices: [BluetoothDeviceRecord] = []
    @Published private(set) var lastError: String?
    @Published private(set) var lastEvent: DeviceEvent?

    let repository: DeviceRepository
    let bluetoothState: BluetoothStateMonitor

    private let transport: BluetoothTransport
    private var protocolCodec = NothingFrameCodec()
    private var decoder = NothingFrameCodec()
    private var eventTask: Task<Void, Never>?
    private var adapterTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var isStarted = false
    private var isUserDisconnect = false
    private var retryAttempt = 0

    init(
        transport: BluetoothTransport? = nil,
        repository: DeviceRepository? = nil,
        bluetoothState: BluetoothStateMonitor? = nil
    ) {
        self.transport = transport ?? CoreBluetoothNothingTransport()
        self.repository = repository ?? DeviceRepository()
        self.bluetoothState = bluetoothState ?? BluetoothStateMonitor()
    }

    deinit {
        eventTask?.cancel()
        adapterTask?.cancel()
        pollingTask?.cancel()
        retryTask?.cancel()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        isUserDisconnect = false
        observeTransport()
        observeAdapter()
        observeWakeEvents()
        refreshDiscovery()
        startPolling()
        autoReconnectKnownDevice()
    }

    func refreshDiscovery() {
        discoveredDevices = Self.deduplicate(transport.discover())
        if state.connection == .disconnected {
            state.descriptor = nil
        }
    }

    func connect(to device: BluetoothDeviceRecord) {
        isUserDisconnect = false
        retryTask?.cancel()
        retryAttempt = 0
        repository.remember(device)
        setConnectingState(for: device)

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await transport.connect(to: device)
                finishConnection(using: device)
            } catch {
                failConnection(error, device: device)
            }
        }
    }

    func disconnect() {
        isUserDisconnect = true
        retryTask?.cancel()
        retryAttempt = 0
        if let descriptor = state.descriptor {
            repository.remember(BluetoothDeviceRecord(
                address: descriptor.address,
                name: descriptor.name,
                isConnected: false,
                rfcommChannel: descriptor.rfcommChannel
            ))
        }
        transport.disconnect()
        state.connection = .disconnected
        state.leftBattery = .unavailable
        state.rightBattery = .unavailable
        state.caseBattery = .unavailable
        state.lastUpdated = .now
    }

    func removeKnownDevice(_ device: BluetoothDeviceRecord) {
        if state.descriptor?.address.caseInsensitiveCompare(device.address) == .orderedSame {
            disconnect()
        }
        repository.remove(address: device.address)
    }

    func setNoiseControl(_ mode: NoiseControlMode) {
        guard state.isConnected else { return }
        state.noiseControl = mode
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let usesListeningMode = state.descriptor?.name.lowercased().contains("headphone") == true
                let frame = usesListeningMode
                    ? try NothingProtocol.commandForListeningMode(mode, codec: &protocolCodec)
                    : try NothingProtocol.commandForNoiseControl(mode, codec: &protocolCodec)
                try transport.write(frame)
                publishEvent(.init(kind: .noiseControl, title: mode.title))
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func setEqualizer(_ preset: EqualizerPreset) {
        guard state.isConnected else { return }
        state.equalizer = preset
        send { try NothingProtocol.commandForEqualizer(preset, codec: &self.protocolCodec) }
    }

    func setBass(enabled: Bool, level: Double) {
        guard state.isConnected else { return }
        state.bassEnhanceEnabled = enabled
        state.bassLevel = min(max(level, 0), 10)
        send { try NothingProtocol.commandForBass(enabled: enabled, level: level, codec: &self.protocolCodec) }
    }

    func setCustomEQ(_ levels: [Double]) {
        guard state.isConnected, state.capabilities.supportsCustomEQ else { return }
        state.customEQ = Array(levels.prefix(3))
        state.equalizer = .custom
        send { try NothingProtocol.commandForCustomEQ(levels, codec: &self.protocolCodec) }
    }

    func setCaseLEDColors(_ colors: [RGBColor]) {
        guard state.isConnected, state.capabilities.supportsCaseLED else { return }
        state.caseLEDColors = colors
        send { try NothingProtocol.commandForCaseLED(colors, codec: &self.protocolCodec) }
    }

    func setInEarDetection(_ enabled: Bool) {
        guard state.isConnected else { return }
        state.inEarDetectionEnabled = enabled
        send { try NothingProtocol.commandForToggle(command: .setInEarDetection, enabled: enabled, codec: &self.protocolCodec) }
    }

    func setLowLatency(_ enabled: Bool) {
        guard state.isConnected else { return }
        state.lowLatencyEnabled = enabled
        send { try NothingProtocol.commandForToggle(command: .setLatency, enabled: enabled, codec: &self.protocolCodec) }
    }

    func setPersonalizedANC(_ enabled: Bool) {
        guard state.isConnected else { return }
        state.personalizedANCEnabled = enabled
        send { try NothingProtocol.commandForToggle(command: .setPersonalizedANC, enabled: enabled, codec: &self.protocolCodec) }
    }

    func setAdvancedEQ(_ enabled: Bool) {
        guard state.isConnected else { return }
        state.advancedEQEnabled = enabled
        send { try NothingProtocol.commandForToggle(command: .setAdvancedEQ, enabled: enabled, codec: &self.protocolCodec) }
    }

    func setGesture(_ setting: GestureSetting) {
        guard state.isConnected else { return }
        if let index = state.gestures.firstIndex(where: { $0.id == setting.id }) {
            state.gestures[index] = setting
        } else {
            state.gestures.append(setting)
        }
        send { try NothingProtocol.commandForGesture(setting, codec: &self.protocolCodec) }
    }

    func ring(_ side: BatterySide?, enabled: Bool) {
        guard state.isConnected else { return }
        send { try NothingProtocol.commandForFindMyEarbuds(side: side, ringing: enabled, codec: &self.protocolCodec) }
    }

    func runEarTipFitTest() {
        guard state.isConnected else { return }
        send { try NothingProtocol.commandForEarTipFitTest(codec: &self.protocolCodec) }
    }

    func refreshState() {
        guard state.isConnected else {
            refreshDiscovery()
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            for command in NothingProtocol.initialReadCommands() {
                do {
                    let frame = try protocolCodec.makeFrame(command: command)
                    try transport.write(frame)
                } catch {
                    lastError = error.localizedDescription
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func send(_ makeFrame: @escaping () throws -> Data) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try transport.write(makeFrame())
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func observeTransport() {
        let transport = self.transport
        eventTask = Task { @MainActor [weak self] in
            for await event in transport.events {
                guard let self else { return }
                handleTransportEvent(event)
            }
        }
    }

    private func observeAdapter() {
        let states = bluetoothState.states
        adapterTask = Task { @MainActor [weak self] in
            for await adapterState in states {
                guard let self else { return }
                if adapterState == .poweredOff || adapterState == .unauthorized || adapterState == .unsupported {
                    if state.isConnected { transport.disconnect() }
                    state.connection = .disconnected
                } else if adapterState == .poweredOn, state.connection == .disconnected {
                    autoReconnectKnownDevice()
                }
            }
        }
    }

    private func observeWakeEvents() {
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDiscovery()
                self?.autoReconnectKnownDevice()
            }
        }
    }

    private func startPolling() {
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard let self, !Task.isCancelled else { return }
                refreshDiscovery()
                if state.connection == .connected {
                    refreshState()
                } else if state.connection == .disconnected {
                    autoReconnectKnownDevice()
                }
            }
        }
    }

    private func autoReconnectKnownDevice() {
        guard !isUserDisconnect, state.connection != .connected, state.connection != .connecting, state.connection != .reconnecting else { return }
        let known = repository.knownDevices
        guard let candidate = known.first else { return }
        let discovered = discoveredDevices.first(where: { $0.representsSamePhysicalDevice(as: candidate) }) ?? candidate
        connectAutomatically(to: discovered)
    }

    private func connectAutomatically(to device: BluetoothDeviceRecord) {
        isUserDisconnect = false
        repository.remember(device)
        setConnectingState(for: device)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await transport.connect(to: device)
                finishConnection(using: device)
            } catch {
                failConnection(error, device: device)
            }
        }
    }

    private func setConnectingState(for device: BluetoothDeviceRecord) {
        state.descriptor = DeviceDescriptor(
            address: device.address,
            name: device.name,
            model: device.name,
            firmware: state.descriptor?.firmware,
            rfcommChannel: device.rfcommChannel,
            lastSeen: .now
        )
        state.connection = retryAttempt > 0 ? .reconnecting : .connecting
        state.lastUpdated = .now
        lastError = nil
    }

    private func finishConnection(using device: BluetoothDeviceRecord) {
        retryTask?.cancel()
        retryAttempt = 0
        let current = transport.currentDevice
        let connectedRecord = current ?? device
        if state.connection == .connected,
           state.descriptor?.address.caseInsensitiveCompare(connectedRecord.address) == .orderedSame {
            return
        }
        repository.remember(connectedRecord)
        if let channel = connectedRecord.rfcommChannel {
            repository.updateChannel(channel, for: connectedRecord.address)
        }
        state.descriptor = DeviceDescriptor(
            address: connectedRecord.address,
            name: connectedRecord.name,
            model: connectedRecord.name,
            firmware: state.descriptor?.firmware,
            rfcommChannel: connectedRecord.rfcommChannel,
            lastSeen: .now
        )
        state.connection = .connected
        state.lastUpdated = .now
        publishEvent(.init(kind: .connected, title: connectedRecord.name, detail: "Ready in the notch"))
        refreshState()
    }

    private func failConnection(_ error: Error, device: BluetoothDeviceRecord) {
        lastError = error.localizedDescription
        state.connection = .failed
        state.lastUpdated = .now
        scheduleRetry(for: device)
    }

    private func scheduleRetry(for device: BluetoothDeviceRecord) {
        guard !isUserDisconnect else { return }
        retryTask?.cancel()
        retryAttempt += 1
        let delay = min(pow(2.0, Double(retryAttempt - 1)), 60.0)
        state.connection = .reconnecting
        retryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled, !isUserDisconnect else { return }
            refreshDiscovery()
            connectAutomatically(to: device)
        }
    }

    private func handleTransportEvent(_ event: TransportEvent) {
        switch event {
        case .connected:
            if let current = transport.currentDevice {
                finishConnection(using: current)
            }
        case let .disconnected(reason):
            guard !isUserDisconnect else { return }
            state.connection = .reconnecting
            state.lastUpdated = .now
            publishEvent(.init(kind: .disconnected, title: "Device disconnected", detail: reason))
            if let descriptor = state.descriptor {
                scheduleRetry(for: BluetoothDeviceRecord(
                    address: descriptor.address,
                    name: descriptor.name,
                    rfcommChannel: descriptor.rfcommChannel
                ))
            }
        case let .discovered(device):
            if let index = discoveredDevices.firstIndex(where: { $0.representsSamePhysicalDevice(as: device) }) {
                let existing = discoveredDevices[index]
                // Preserve a live native identity over a stale alias emitted
                // by the adapter while it is still warming up.
                discoveredDevices[index] = existing.isConnected && !device.isConnected ? existing : device
            } else {
                discoveredDevices.append(device)
                discoveredDevices.sort {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            }
        case let .bytes(data):
            let frames = decoder.append(data)
            frames.compactMap(NothingProtocol.event(from:)).forEach(apply)
        case .adapterState:
            break
        }
    }

    private func apply(_ event: NothingProtocolEvent) {
        switch event {
        case let .battery(update):
            let wasLow = [state.leftBattery.level, state.rightBattery.level].compactMap { $0 }.contains { $0 <= 20 }
            state.leftBattery = update.left
            state.rightBattery = update.right
            state.caseBattery = update.caseBattery
            let isLow = [update.left.level, update.right.level].compactMap { $0 }.contains { $0 <= 20 }
            if isLow && !wasLow {
                publishEvent(.init(kind: .lowBattery, title: "Battery running low", detail: "One of your earbuds is below 20%"))
            }
        case let .noiseControl(mode), let .listeningMode(mode):
            state.noiseControl = mode
        case let .equalizer(preset):
            state.equalizer = preset
        case let .customEQ(levels):
            state.customEQ = levels
            state.equalizer = .custom
        case let .firmware(version):
            if var descriptor = state.descriptor {
                descriptor.firmware = version
                state.descriptor = descriptor
            }
        case let .inEarDetection(enabled):
            state.inEarDetectionEnabled = enabled
        case let .latency(enabled):
            state.lowLatencyEnabled = enabled
        case let .personalizedANC(enabled):
            state.personalizedANCEnabled = enabled
        case let .gestures(gestures):
            state.gestures = gestures.compactMap(mapGesture)
        case let .advancedEQ(enabled):
            state.advancedEQEnabled = enabled
        case let .bass(enabled, level):
            state.bassEnhanceEnabled = enabled
            state.bassLevel = level
        case let .earTipFit(left, right):
            state.earTipFitResult = EarTipFitResult(left: left, right: right)
        case let .caseLED(colors):
            state.caseLEDColors = colors
        }
        state.lastUpdated = .now
    }

    private func mapGesture(_ gesture: ProtocolGesture) -> GestureSetting? {
        let side: GestureSide
        switch gesture.device {
        case 2: side = .left
        case 3: side = .right
        default: return nil
        }
        let kind: GestureKind? = switch gesture.kind {
        case 2: .doubleTap
        case 3: .tripleTap
        case 7: .tapAndHold
        case 9: .doubleTapAndHold
        default: nil
        }
        guard let kind else { return nil }
        let action: GestureAction = switch gesture.action {
        case 2: .playPause
        case 8: .skipBack
        case 9: .skipForward
        case 10, 20, 21, 22: .noiseControl
        case 11: .voiceAssistant
        case 18: .volumeUp
        case 19: .volumeDown
        default: .noAction
        }
        return GestureSetting(side: side, kind: kind, action: action)
    }

    private func publishEvent(_ event: DeviceEvent) {
        lastEvent = event
    }

    private static func deduplicate(_ devices: [BluetoothDeviceRecord]) -> [BluetoothDeviceRecord] {
        var result: [BluetoothDeviceRecord] = []
        for device in devices {
            guard let index = result.firstIndex(where: { $0.representsSamePhysicalDevice(as: device) }) else {
                result.append(device)
                continue
            }
            let existing = result[index]
            result[index] = existing.isConnected && !device.isConnected ? existing : device
        }
        return result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
