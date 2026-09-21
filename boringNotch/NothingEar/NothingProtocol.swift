import Foundation

enum NothingCommand: UInt16, Sendable {
    case readBattery = 49_159
    case readNoiseControl = 49_182
    case readEqualizer = 49_183
    case readPersonalizedANC = 49_184
    case readInEarDetection = 49_166
    case readLatency = 49_217
    case readFirmware = 49_218
    case readGestures = 49_176
    case readCaseLED = 49_175
    case readCustomEQ = 49_220
    case readAdvancedEQ = 49_228
    case readBassEnhance = 49_230
    case readListeningMode = 49_232

    case batteryNotification = 57_345
    case batteryNotificationAlternate = 16_391
    case noiseControlNotification = 57_347
    case noiseControlResponse = 16_414
    case equalizerResponse = 16_415
    case equalizerListeningResponse = 16_464
    case firmwareResponse = 16_450
    case inEarDetectionResponse = 16_398
    case latencyResponse = 16_449
    case personalizedANCResponse = 16_416
    case gesturesResponse = 16_408
    case advancedEQResponse = 16_460
    case bassEnhanceResponse = 16_462
    case earTipFitResponse = 57_357
    case customEQResponse = 16_452
    case caseLEDResponse = 16_407

    case setGesture = 61_443
    case setFindMyEarbuds = 61_442
    case setInEarDetection = 61_444
    case setNoiseControl = 61_455
    case setEqualizer = 61_456
    case setPersonalizedANC = 61_457
    case launchEarTipFitTest = 61_460
    case setListeningMode = 61_469
    case setCaseLED = 61_453
    case setLatency = 61_504
    case setCustomEQ = 61_505
    case setAdvancedEQ = 61_519
    case setBassEnhance = 61_521
}

struct NothingFrame: Equatable, Sendable {
    var command: UInt16
    var operationID: UInt8
    var payload: [UInt8]
    var raw: Data
}

enum NothingProtocolError: Error, LocalizedError, Sendable {
    case invalidFrame
    case invalidCRC
    case payloadTooLarge
    case transportUnavailable
    case deviceNotFound
    case channelUnavailable
    case connectionTimeout
    case bluetoothError(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidFrame: "The device returned an invalid protocol frame."
        case .invalidCRC: "The device returned a frame with an invalid checksum."
        case .payloadTooLarge: "The command payload is too large for the Nothing protocol."
        case .transportUnavailable: "The Bluetooth control channel is unavailable."
        case .deviceNotFound: "The paired Nothing device could not be found."
        case .channelUnavailable: "The Nothing control service is not available."
        case .connectionTimeout: "The Nothing device did not finish its Bluetooth handshake in time."
        case let .bluetoothError(status): "Bluetooth returned error \(status)."
        }
    }
}

struct BatteryUpdate: Equatable, Sendable {
    var left: BatteryStatus
    var right: BatteryStatus
    var caseBattery: BatteryStatus
}

struct ProtocolGesture: Equatable, Sendable {
    var device: UInt8
    var kind: UInt8
    var action: UInt8
}

enum NothingProtocolEvent: Equatable, Sendable {
    case battery(BatteryUpdate)
    case noiseControl(NoiseControlMode)
    case equalizer(EqualizerPreset)
    case customEQ([Double])
    case firmware(String)
    case inEarDetection(Bool)
    case latency(Bool)
    case personalizedANC(Bool)
    case gestures([ProtocolGesture])
    case advancedEQ(Bool)
    case bass(enabled: Bool, level: Double)
    case earTipFit(left: Int, right: Int)
    case caseLED([RGBColor])
    case listeningMode(NoiseControlMode)
}

struct NothingFrameCodec: Sendable {
    private var nextOperationID: UInt8 = 0
    private var receiveBuffer: [UInt8] = []

    mutating func makeFrame(command: NothingCommand, payload: [UInt8] = []) throws -> Data {
        try makeFrame(command: command.rawValue, payload: payload)
    }

    mutating func makeFrame(command: UInt16, payload: [UInt8] = []) throws -> Data {
        guard payload.count <= 255 else { throw NothingProtocolError.payloadTooLarge }

        nextOperationID = nextOperationID >= 249 ? 1 : nextOperationID + 1

        var header: [UInt8] = [
            0x55,
            0x60,
            0x01,
            UInt8(command & 0xff),
            UInt8((command >> 8) & 0xff),
            UInt8(payload.count),
            0x00,
            nextOperationID
        ]
        header.append(contentsOf: payload)
        let crc = Self.crc16(header)
        header.append(UInt8(crc & 0xff))
        header.append(UInt8((crc >> 8) & 0xff))
        return Data(header)
    }

    mutating func append(_ data: Data) -> [NothingFrame] {
        receiveBuffer.append(contentsOf: data)
        var frames: [NothingFrame] = []

        while receiveBuffer.count >= 8 {
            guard let start = receiveBuffer.firstIndex(of: 0x55) else {
                receiveBuffer.removeAll(keepingCapacity: true)
                break
            }
            if start > 0 {
                receiveBuffer.removeFirst(start)
            }

            guard receiveBuffer.count >= 8 else { break }
            let payloadLength = Int(receiveBuffer[5])
            let packetLength = 8 + payloadLength
            guard receiveBuffer.count >= packetLength else { break }

            let packet = Array(receiveBuffer.prefix(packetLength))
            var frameLength = packetLength
            var candidate = packet

            // SPP responses normally include CRC16. The native GATT
            // implementations used by Nothing Bar/swift-nothing-ear also
            // accept firmware responses without CRC, and some newer models
            // calculate the checksum over payload only. Support all three
            // forms while preserving stream-safe framing.
            if receiveBuffer.count >= packetLength + 2 {
                let expectedCRC = UInt16(receiveBuffer[packetLength]) | (UInt16(receiveBuffer[packetLength + 1]) << 8)
                let fullCRC = Self.crc16(packet)
                let payloadCRC = Self.crc16(Array(packet.dropFirst(8)))
                if expectedCRC == fullCRC || expectedCRC == payloadCRC {
                    frameLength += 2
                    candidate = Array(receiveBuffer.prefix(frameLength))
                } else if receiveBuffer[packetLength] != 0x55 {
                    receiveBuffer.removeFirst()
                    continue
                }
            } else if receiveBuffer.count > packetLength, receiveBuffer[packetLength] != 0x55 {
                // There may be a partial CRC at the end of this chunk.
                break
            }

            let command = UInt16(candidate[3]) | (UInt16(candidate[4]) << 8)
            let payload = Array(candidate[8..<(8 + payloadLength)])
            frames.append(NothingFrame(
                command: command,
                operationID: candidate[7],
                payload: payload,
                raw: Data(candidate)
            ))
            receiveBuffer.removeFirst(frameLength)
        }

        return frames
    }

    static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xffff
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xa001 : crc >> 1
            }
        }
        return crc
    }
}

enum NothingProtocol {
    static func event(from frame: NothingFrame) -> NothingProtocolEvent? {
        switch frame.command {
        case NothingCommand.readBattery.rawValue,
             NothingCommand.batteryNotification.rawValue,
             NothingCommand.batteryNotificationAlternate.rawValue:
            return parseBattery(frame.payload)
        case NothingCommand.readNoiseControl.rawValue,
             NothingCommand.noiseControlNotification.rawValue,
             NothingCommand.noiseControlResponse.rawValue:
            return parseNoiseControl(frame.payload)
        case NothingCommand.readEqualizer.rawValue,
             NothingCommand.equalizerResponse.rawValue,
             NothingCommand.equalizerListeningResponse.rawValue:
            guard let value = frame.payload.first else { return nil }
            return .equalizer(equalizer(for: value))
        case NothingCommand.readFirmware.rawValue,
             NothingCommand.firmwareResponse.rawValue:
            return .firmware(String(bytes: frame.payload, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? "")
        case NothingCommand.readInEarDetection.rawValue,
             NothingCommand.inEarDetectionResponse.rawValue:
            guard frame.payload.count > 2 else { return nil }
            return .inEarDetection(frame.payload[2] == 1)
        case NothingCommand.readLatency.rawValue,
             NothingCommand.latencyResponse.rawValue:
            guard let value = frame.payload.first else { return nil }
            return .latency(value == 1)
        case NothingCommand.readPersonalizedANC.rawValue,
             NothingCommand.personalizedANCResponse.rawValue:
            guard let value = frame.payload.first else { return nil }
            return .personalizedANC(value == 1)
        case NothingCommand.readGestures.rawValue,
             NothingCommand.gesturesResponse.rawValue:
            return .gestures(parseGestures(frame.payload))
        case NothingCommand.readAdvancedEQ.rawValue,
             NothingCommand.advancedEQResponse.rawValue:
            guard let value = frame.payload.first else { return nil }
            return .advancedEQ(value == 1)
        case NothingCommand.readBassEnhance.rawValue,
             NothingCommand.bassEnhanceResponse.rawValue:
            guard frame.payload.count > 1 else { return nil }
            return .bass(enabled: frame.payload[0] == 1, level: Double(frame.payload[1]) / 2)
        case NothingCommand.launchEarTipFitTest.rawValue,
             NothingCommand.earTipFitResponse.rawValue:
            guard frame.payload.count > 1 else { return nil }
            return .earTipFit(left: Int(frame.payload[0]), right: Int(frame.payload[1]))
        case NothingCommand.readCustomEQ.rawValue,
             NothingCommand.customEQResponse.rawValue:
            return .customEQ(parseCustomEQ(frame.payload))
        case NothingCommand.readCaseLED.rawValue,
             NothingCommand.caseLEDResponse.rawValue:
            return .caseLED(parseLEDColors(frame.payload))
        case NothingCommand.readListeningMode.rawValue:
            guard let value = frame.payload.first else { return nil }
            return .listeningMode(listeningMode(for: value))
        default:
            return nil
        }
    }

    static func initialReadCommands() -> [NothingCommand] {
        [
            .readBattery,
            .readEqualizer,
            .readListeningMode,
            .readFirmware,
            .readInEarDetection,
            .readLatency,
            .readPersonalizedANC,
            .readGestures,
            .readNoiseControl,
            .readAdvancedEQ,
            .readBassEnhance,
            .readCustomEQ,
            .readCaseLED
        ]
    }

    static func equalizer(for rawValue: UInt8) -> EqualizerPreset {
        switch rawValue {
        case 0: .balanced
        case 1: .moreBass
        case 2: .moreTreble
        case 3: .voice
        default: .custom
        }
    }

    static func listeningMode(for rawValue: UInt8) -> NoiseControlMode {
        switch rawValue {
        case 0: .off
        case 1: .transparency
        case 2...6: .noiseCancellation(level: Int(rawValue) - 1)
        default: .unknown(rawValue: Int(rawValue))
        }
    }

    static func noiseControl(for rawValue: UInt8) -> NoiseControlMode {
        switch rawValue {
        // Ear Web and SwiftNothingEar both use these bytes for the ANC
        // command family.  0x05/0x07 are Off/Transparency; 0x01...0x04
        // are High/Mid/Low/Adaptive.  The previous implementation used the
        // listening-mode values here, so tapping Off or Ambient sent bytes
        // that Nothing Ear (a) simply ignored, and tapping ANC sent 0x05
        // (Off).
        case 0x05: .off
        case 0x07: .transparency
        case 0x03: .noiseCancellation(level: 1) // Low
        case 0x02: .noiseCancellation(level: 2) // Mid
        case 0x01: .noiseCancellation(level: 3) // High
        case 0x04: .noiseCancellation(level: 4) // Adaptive
        default: .unknown(rawValue: Int(rawValue))
        }
    }

    static func commandForNoiseControl(_ mode: NoiseControlMode, codec: inout NothingFrameCodec) throws -> Data {
        let rawValue: UInt8
        switch mode {
        case .off: rawValue = 0x05
        case .transparency: rawValue = 0x07
        case let .noiseCancellation(level):
            rawValue = switch level {
            case 1: 0x03 // Low
            case 2: 0x02 // Mid
            case 3: 0x01 // High
            case 4: 0x04 // Adaptive
            default: 0x04
            }
        case let .unknown(value): rawValue = UInt8(clamping: value)
        }
        return try codec.makeFrame(command: .setNoiseControl, payload: [0x01, rawValue, 0x00])
    }

    static func commandForListeningMode(_ mode: NoiseControlMode, codec: inout NothingFrameCodec) throws -> Data {
        let rawValue: UInt8
        switch mode {
        case .off: rawValue = 0
        case .transparency: rawValue = 1
        case let .noiseCancellation(level): rawValue = UInt8(clamping: level + 1)
        case let .unknown(rawValueValue): rawValue = UInt8(clamping: rawValueValue)
        }
        return try codec.makeFrame(command: .setListeningMode, payload: [rawValue, 0x00])
    }

    static func commandForEqualizer(_ preset: EqualizerPreset, codec: inout NothingFrameCodec) throws -> Data {
        let value: UInt8 = switch preset {
        case .balanced: 0
        case .moreBass: 1
        case .moreTreble: 2
        case .voice: 3
        case .custom: 4
        }
        return try codec.makeFrame(command: .setEqualizer, payload: [value, 0x00])
    }

    static func commandForBass(enabled: Bool, level: Double, codec: inout NothingFrameCodec) throws -> Data {
        let boundedLevel = UInt8(clamping: Int((level * 2).rounded()))
        return try codec.makeFrame(command: .setBassEnhance, payload: [enabled ? 1 : 0, boundedLevel])
    }

    static func commandForCustomEQ(_ levels: [Double], codec: inout NothingFrameCodec) throws -> Data {
        let normalized = Array(levels.prefix(3)) + Array(repeating: 0, count: max(0, 3 - levels.count))
        var payload = Array(repeating: UInt8(0), count: 49)
        payload[0] = 0x03

        let highestValue = -normalized.prefix(3).max()!
        let totalBytes = encodedEQFloat(highestValue, isTotal: true)
        for index in 0..<4 {
            payload[1 + index] = totalBytes[index]
        }

        for band in 0..<3 {
            let bandBytes = encodedEQFloat(normalized[band], isTotal: false)
            for index in 0..<4 {
                payload[6 + (band * 13) + index] = bandBytes[index]
            }
        }
        return try codec.makeFrame(command: .setCustomEQ, payload: payload)
    }

    static func commandForCaseLED(_ colors: [RGBColor], codec: inout NothingFrameCodec) throws -> Data {
        var payload = [UInt8(5)]
        for index in 0..<5 {
            let color = index < colors.count ? colors[index] : RGBColor(red: 255, green: 255, blue: 255)
            payload.append(UInt8(index + 1))
            payload.append(color.red)
            payload.append(color.green)
            payload.append(color.blue)
        }
        return try codec.makeFrame(command: .setCaseLED, payload: payload)
    }

    static func commandForToggle(command: NothingCommand, enabled: Bool, codec: inout NothingFrameCodec) throws -> Data {
        switch command {
        case .setInEarDetection:
            return try codec.makeFrame(command: command, payload: [0x01, 0x01, enabled ? 1 : 0])
        case .setLatency:
            return try codec.makeFrame(command: command, payload: [enabled ? 1 : 2, 0x00])
        case .setPersonalizedANC:
            return try codec.makeFrame(command: command, payload: [enabled ? 1 : 0])
        case .setAdvancedEQ:
            return try codec.makeFrame(command: command, payload: [enabled ? 1 : 0, 0x00])
        default:
            return try codec.makeFrame(command: command, payload: [enabled ? 1 : 0])
        }
    }

    static func commandForFindMyEarbuds(side: BatterySide?, ringing: Bool, codec: inout NothingFrameCodec) throws -> Data {
        guard let side else {
            return try codec.makeFrame(command: .setFindMyEarbuds, payload: [ringing ? 1 : 0])
        }
        let device: UInt8 = side == .left ? 2 : 3
        return try codec.makeFrame(command: .setFindMyEarbuds, payload: [device, ringing ? 1 : 0])
    }

    static func commandForGesture(_ setting: GestureSetting, codec: inout NothingFrameCodec) throws -> Data {
        let device: UInt8 = setting.side == .left ? 2 : 3
        let kind: UInt8 = switch setting.kind {
        case .doubleTap: 2
        case .tripleTap: 3
        case .tapAndHold: 7
        case .doubleTapAndHold: 9
        }
        let action: UInt8 = switch setting.action {
        case .playPause: 2
        case .skipBack: 8
        case .skipForward: 9
        case .voiceAssistant: 11
        case .noiseControl: 10
        case .volumeUp: 18
        case .volumeDown: 19
        case .noAction: 1
        }
        return try codec.makeFrame(command: .setGesture, payload: [0x01, device, 0x01, kind, action])
    }

    static func commandForEarTipFitTest(codec: inout NothingFrameCodec) throws -> Data {
        try codec.makeFrame(command: .launchEarTipFitTest, payload: [0x01])
    }

    private static func parseBattery(_ payload: [UInt8]) -> NothingProtocolEvent? {
        guard let count = payload.first else { return nil }
        var left = BatteryStatus()
        var right = BatteryStatus()
        var caseBattery = BatteryStatus()
        for index in 0..<Int(count) {
            let offset = 1 + (index * 2)
            guard payload.count > offset + 1 else { break }
            let side = payload[offset]
            let raw = payload[offset + 1]
            let battery = BatteryStatus(level: Int(raw & 0x7f), isCharging: raw & 0x80 != 0, isConnected: true)
            switch side {
            case 0x02: left = battery
            case 0x03: right = battery
            case 0x04: caseBattery = battery
            default: continue
            }
        }
        return .battery(BatteryUpdate(left: left, right: right, caseBattery: caseBattery))
    }

    private static func parseNoiseControl(_ payload: [UInt8]) -> NothingProtocolEvent? {
        guard payload.count > 1 else { return nil }
        return .noiseControl(noiseControl(for: payload[1]))
    }

    private static func parseGestures(_ payload: [UInt8]) -> [ProtocolGesture] {
        guard let count = payload.first else { return [] }
        return (0..<Int(count)).compactMap { index in
            let offset = 1 + index * 4
            guard payload.count > offset + 3 else { return nil }
            return ProtocolGesture(device: payload[offset], kind: payload[offset + 2], action: payload[offset + 3])
        }
    }

    private static func parseCustomEQ(_ payload: [UInt8]) -> [Double] {
        var values: [Double] = []
        for band in 0..<3 {
            let offset = 6 + band * 13
            guard payload.count >= offset + 4 else { break }
            let bytes = Array(payload[offset..<(offset + 4)]).reversed()
            let bitPattern = bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            var value = Double(Float(bitPattern: bitPattern))
            if payload[offset] == 0x80 && payload[offset + 1] == 0 && payload[offset + 2] == 0 && payload[offset + 3] == 0 {
                value = -value
            }
            values.append(value)
        }
        return values.count == 3 ? [values[2], values[0], values[1]] : values
    }

    private static func encodedEQFloat(_ value: Double, isTotal: Bool) -> [UInt8] {
        let floatValue = Float(value)
        let bitPattern = floatValue.bitPattern
        var bytes: [UInt8] = [
            UInt8((bitPattern >> 24) & 0xff),
            UInt8((bitPattern >> 16) & 0xff),
            UInt8((bitPattern >> 8) & 0xff),
            UInt8(bitPattern & 0xff)
        ]
        if value != 0, bytes[0] == 0, bytes[1] == 0, bytes[2] == 0 {
            bytes[3] |= 0x80
        }
        bytes.reverse()
        if isTotal, value >= 0 {
            return [0x00, 0x00, 0x00, 0x80]
        }
        return bytes
    }

    private static func parseLEDColors(_ payload: [UInt8]) -> [RGBColor] {
        guard let count = payload.first else { return [] }
        return (0..<Int(count)).compactMap { index in
            let offset = 2 + index * 4
            guard payload.count > offset + 2 else { return nil }
            return RGBColor(red: payload[offset], green: payload[offset + 1], blue: payload[offset + 2])
        }
    }
}
