import Foundation

enum ConnectionState: String, Codable, Equatable, Sendable {
    case disconnected
    case discovering
    case connecting
    case connected
    case reconnecting
    case sleeping
    case failed

    var label: String {
        switch self {
        case .disconnected: "Not connected"
        case .discovering: "Looking for device"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .reconnecting: "Reconnecting"
        case .sleeping: "Sleeping"
        case .failed: "Connection failed"
        }
    }
}

enum StatusPlacement: String, CaseIterable, Codable, Sendable, Identifiable {
    case notch
    case sides
    case both

    var id: Self { self }

    var title: String {
        switch self {
        case .notch: "Inside notch"
        case .sides: "On notch sides"
        case .both: "Notch and sides"
        }
    }

    var description: String {
        switch self {
        case .notch: "Keep connection and battery status inside the expanded notch."
        case .sides: "Show status around the physical notch, like Boring Notch."
        case .both: "Show the compact side status and the full notch status."
        }
    }
}

enum BatterySide: String, Codable, Sendable {
    case left
    case right
    case caseBattery = "case"
}

struct BatteryStatus: Equatable, Codable, Sendable {
    var level: Int?
    var isCharging: Bool
    var isConnected: Bool

    init(level: Int? = nil, isCharging: Bool = false, isConnected: Bool = false) {
        self.level = level.map { min(max($0, 0), 100) }
        self.isCharging = isCharging
        self.isConnected = isConnected
    }

    static let unavailable = BatteryStatus()
}

enum NoiseControlMode: Equatable, Codable, Sendable {
    case off
    case transparency
    case noiseCancellation(level: Int)
    case unknown(rawValue: Int)

    private enum CodingKeys: String, CodingKey {
        case kind
        case level
        case rawValue
    }

    private enum Kind: String, Codable {
        case off
        case transparency
        case noiseCancellation
        case unknown
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .off:
            self = .off
        case .transparency:
            self = .transparency
        case .noiseCancellation:
            self = .noiseCancellation(level: try container.decode(Int.self, forKey: .level))
        case .unknown:
            self = .unknown(rawValue: try container.decode(Int.self, forKey: .rawValue))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .off:
            try container.encode(Kind.off, forKey: .kind)
        case .transparency:
            try container.encode(Kind.transparency, forKey: .kind)
        case let .noiseCancellation(level):
            try container.encode(Kind.noiseCancellation, forKey: .kind)
            try container.encode(level, forKey: .level)
        case let .unknown(rawValue):
            try container.encode(Kind.unknown, forKey: .kind)
            try container.encode(rawValue, forKey: .rawValue)
        }
    }

    var title: String {
        switch self {
        case .off: "Off"
        case .transparency: "Transparency"
        case let .noiseCancellation(level): "ANC " + String(level)
        case let .unknown(rawValue): "Mode " + String(rawValue)
        }
    }

    var shortTitle: String {
        switch self {
        case .off: "Off"
        case .transparency: "Transparency"
        case .noiseCancellation: "ANC"
        case .unknown: "Noise control"
        }
    }
}

enum EqualizerPreset: String, Codable, CaseIterable, Sendable {
    case balanced
    case moreBass
    case moreTreble
    case voice
    case custom

    var title: String {
        switch self {
        case .balanced: "Balanced"
        case .moreBass: "More bass"
        case .moreTreble: "More treble"
        case .voice: "Voice"
        case .custom: "Custom"
        }
    }
}

enum GestureSide: String, Codable, CaseIterable, Sendable {
    case left
    case right

    var title: String { rawValue.capitalized }
}

enum GestureKind: String, Codable, CaseIterable, Sendable {
    case doubleTap
    case tripleTap
    case tapAndHold
    case doubleTapAndHold

    var title: String {
        switch self {
        case .doubleTap: "Double tap"
        case .tripleTap: "Triple tap"
        case .tapAndHold: "Tap and hold"
        case .doubleTapAndHold: "Double tap and hold"
        }
    }
}

enum GestureAction: String, Codable, CaseIterable, Sendable {
    case playPause
    case skipBack
    case skipForward
    case voiceAssistant
    case noiseControl
    case volumeUp
    case volumeDown
    case noAction

    var title: String {
        switch self {
        case .playPause: "Play / pause"
        case .skipBack: "Skip back"
        case .skipForward: "Skip forward"
        case .voiceAssistant: "Voice assistant"
        case .noiseControl: "Noise control"
        case .volumeUp: "Volume up"
        case .volumeDown: "Volume down"
        case .noAction: "No action"
        }
    }
}

struct GestureSetting: Identifiable, Equatable, Codable, Sendable {
    var id: String { "\(side.rawValue)-\(kind.rawValue)" }
    var side: GestureSide
    var kind: GestureKind
    var action: GestureAction
    var noiseControlModes: Set<String> = []
}

struct RGBColor: Equatable, Codable, Sendable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
}

struct EarTipFitResult: Equatable, Codable, Sendable {
    var left: Int
    var right: Int
}

struct DeviceCapabilities: Equatable, Codable, Sendable {
    var supportsBattery: Bool
    var supportsNoiseControl: Bool
    var supportsANCStrength: Bool
    var supportsPersonalizedANC: Bool
    var supportsTransparency: Bool
    var supportsEqualizer: Bool
    var supportsCustomEQ: Bool
    var supportsBassEnhance: Bool
    var supportsLowLatency: Bool
    var supportsInEarDetection: Bool
    var supportsMultipoint: Bool
    var supportsGestures: Bool
    var supportsFindMyEarbuds: Bool
    var supportsEarTipFitTest: Bool
    var supportsSpatialAudio: Bool
    var supportsCaseLED: Bool

    static let unknown = DeviceCapabilities(
        supportsBattery: true,
        supportsNoiseControl: false,
        supportsANCStrength: false,
        supportsPersonalizedANC: false,
        supportsTransparency: false,
        supportsEqualizer: false,
        supportsCustomEQ: false,
        supportsBassEnhance: false,
        supportsLowLatency: false,
        supportsInEarDetection: false,
        supportsMultipoint: false,
        supportsGestures: false,
        supportsFindMyEarbuds: false,
        supportsEarTipFitTest: false,
        supportsSpatialAudio: false,
        supportsCaseLED: false
    )

    static func inferred(for name: String) -> DeviceCapabilities {
        let normalized = name.lowercased()
        let isNothing = normalized.contains("nothing") || normalized.contains("ear")
        let isCMF = normalized.contains("cmf")

        guard isNothing || isCMF else { return .unknown }

        let hasANC = !normalized.contains("stick") && !normalized.contains("open")
        let hasAdvancedANC = normalized.contains("ear (2)") || normalized.contains("ear 2") || normalized.contains("ear (a)") || normalized.contains("ear a") || normalized.contains("ear")
        let hasCustomEQ = !normalized.contains("headphone")
        let hasBass = normalized.contains("ear") || normalized.contains("buds")
        let hasFitTest = normalized.contains("ear (2)") || normalized.contains("ear 2") || normalized.contains("ear (a)") || normalized.contains("ear a")
        let hasCaseLED = normalized.contains("ear (1)") || normalized.contains("ear 1")
        let isHeadphone = normalized.contains("headphone") || normalized.contains("neckband")

        return DeviceCapabilities(
            supportsBattery: true,
            supportsNoiseControl: hasANC,
            supportsANCStrength: hasANC,
            supportsPersonalizedANC: hasAdvancedANC,
            supportsTransparency: hasANC,
            supportsEqualizer: true,
            supportsCustomEQ: hasCustomEQ,
            supportsBassEnhance: hasBass,
            supportsLowLatency: !isHeadphone,
            supportsInEarDetection: !isHeadphone && !normalized.contains("open"),
            supportsMultipoint: normalized.contains("ear") || normalized.contains("headphone"),
            supportsGestures: true,
            supportsFindMyEarbuds: !isHeadphone,
            supportsEarTipFitTest: hasFitTest,
            supportsSpatialAudio: normalized.contains("headphone (1)") || normalized.contains("headphone 1"),
            supportsCaseLED: hasCaseLED
        )
    }
}

struct BluetoothDeviceRecord: Identifiable, Equatable, Codable, Sendable {
    var id: String { address }
    var address: String
    var name: String
    var isConnected: Bool
    var rfcommChannel: UInt8?
    var lastSeen: Date

    init(address: String, name: String, isConnected: Bool = false, rfcommChannel: UInt8? = nil, lastSeen: Date = .now) {
        self.address = address.uppercased()
        self.name = name
        self.isConnected = isConnected
        self.rfcommChannel = rfcommChannel
        self.lastSeen = lastSeen
    }

    /// CoreBluetooth uses a UUID while the old RFCOMM transport used a
    /// colon/dash-separated Bluetooth address. Both can describe the same
    /// paired Nothing device after an upgrade, so the UI must not expose both
    /// identities as separate earbuds.
    var normalizedName: String {
        name
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    var isCoreBluetoothIdentifier: Bool {
        UUID(uuidString: address) != nil
    }

    func representsSamePhysicalDevice(as other: BluetoothDeviceRecord) -> Bool {
        if address.caseInsensitiveCompare(other.address) == .orderedSame { return true }
        guard !normalizedName.isEmpty, normalizedName == other.normalizedName else { return false }

        // Keep same-name CoreBluetooth peripherals separate only when they
        // are genuinely distinct native identities. A legacy MAC address and
        // a CoreBluetooth UUID are the migration alias that caused the
        // duplicate Ear (a) rows.
        return isCoreBluetoothIdentifier != other.isCoreBluetoothIdentifier
            || !isCoreBluetoothIdentifier && !other.isCoreBluetoothIdentifier
    }
}

struct DeviceDescriptor: Identifiable, Equatable, Codable, Sendable {
    var id: String { address }
    var address: String
    var name: String
    var model: String
    var firmware: String?
    var rfcommChannel: UInt8?
    var lastSeen: Date

    var capabilities: DeviceCapabilities {
        DeviceCapabilities.inferred(for: model.isEmpty ? name : model)
    }
}

struct DeviceState: Equatable, Codable, Sendable {
    var descriptor: DeviceDescriptor?
    var connection: ConnectionState
    var leftBattery: BatteryStatus
    var rightBattery: BatteryStatus
    var caseBattery: BatteryStatus
    var noiseControl: NoiseControlMode
    var equalizer: EqualizerPreset
    var customEQ: [Double]
    var bassEnhanceEnabled: Bool
    var bassLevel: Double
    var lowLatencyEnabled: Bool
    var inEarDetectionEnabled: Bool
    var personalizedANCEnabled: Bool
    var gestures: [GestureSetting]
    var earTipFitResult: EarTipFitResult?
    var advancedEQEnabled: Bool
    var caseLEDColors: [RGBColor]
    var lastUpdated: Date

    static let empty = DeviceState(
        descriptor: nil,
        connection: .disconnected,
        leftBattery: .unavailable,
        rightBattery: .unavailable,
        caseBattery: .unavailable,
        noiseControl: .off,
        equalizer: .balanced,
        customEQ: [0, 0, 0],
        bassEnhanceEnabled: false,
        bassLevel: 0,
        lowLatencyEnabled: false,
        inEarDetectionEnabled: false,
        personalizedANCEnabled: false,
        gestures: [],
        earTipFitResult: nil,
        advancedEQEnabled: false,
        caseLEDColors: [],
        lastUpdated: .now
    )

    var capabilities: DeviceCapabilities { descriptor?.capabilities ?? .unknown }
    var isConnected: Bool { connection == .connected }
}

