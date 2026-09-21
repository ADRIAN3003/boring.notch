import AppKit
import SwiftUI

/// The Nothing / CMF control surface that lives in the expanded notch.
///
/// The panel deliberately uses the same small, dark surfaces as the rest of
/// Boring Notch. The full feature set is available from the two anchored
/// control popovers, while the controls people use most stay one click away.
@MainActor
struct NothingEarView: View {
    @ObservedObject private var deviceManager = DeviceManager.shared
    @State private var showingEqualizer = false
    @State private var showingAdvancedControls = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if deviceManager.state.isConnected {
                    connectedContent
                } else {
                    disconnectedContent
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
        // Padding belongs inside the tab's slot. Padding on the outside makes
        // SwiftUI report a different height for this tab than Home and Shelf.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .onAppear {
            deviceManager.start()
        }
        .onChange(of: deviceManager.state.isConnected) { _, connected in
            if !connected {
                showingEqualizer = false
                showingAdvancedControls = false
            }
        }
    }

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            connectedHeader

            HStack(spacing: 8) {
                modeControlRail

                if deviceManager.state.capabilities.supportsEqualizer {
                    Button {
                        showingEqualizer = true
                    } label: {
                        EarControlLabel(
                            title: deviceManager.state.equalizer.title,
                            symbol: "slider.horizontal.3"
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(width: 104, height: 43)
                    .earSurface()
                    .popover(isPresented: $showingEqualizer, arrowEdge: .bottom) {
                        NothingEarEqualizerPanel()
                    }
                }

                Button {
                    showingAdvancedControls = true
                } label: {
                    EarControlLabel(title: "More", symbol: "ellipsis")
                }
                .buttonStyle(.plain)
                .frame(width: 72, height: 43)
                .earSurface()
                .popover(isPresented: $showingAdvancedControls, arrowEdge: .bottom) {
                    NothingEarAdvancedPanel()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 43, maxHeight: 43, alignment: .leading)

            quickOptionsRow
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var connectedHeader: some View {
        HStack(spacing: 9) {
            EarDeviceGlyph(isConnected: true)

            VStack(alignment: .leading, spacing: 2) {
                Text(deviceManager.state.descriptor?.name ?? "Nothing Ear")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.effectiveAccent)
                        .frame(width: 5, height: 5)
                    Text(deviceManager.state.connection.label)
                    if let firmware = deviceManager.state.descriptor?.firmware,
                       !firmware.isEmpty
                    {
                        Text("·")
                            .foregroundStyle(.white.opacity(0.25))
                        Text("FW \(firmware)")
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.42))
            }

            Spacer(minLength: 8)
            batterySummary
        }
        .frame(height: 34)
    }

    @ViewBuilder
    private var modeControlRail: some View {
        HStack(spacing: 2) {
            if deviceManager.state.capabilities.supportsNoiseControl {
                EarModeSegment(
                    title: ancSegmentTitle,
                    symbol: "waveform.path.ecg",
                    isSelected: isANCSelected,
                    action: { deviceManager.setNoiseControl(deviceManager.state.noiseControl.selectedANCMode) }
                )

                if deviceManager.state.capabilities.supportsTransparency {
                    EarModeSegment(
                        title: "Ambient",
                        symbol: "ear",
                        isSelected: deviceManager.state.noiseControl == .transparency,
                        action: { deviceManager.setNoiseControl(.transparency) }
                    )
                }

                EarModeSegment(
                    title: "Off",
                    symbol: "speaker.slash",
                    isSelected: deviceManager.state.noiseControl == .off,
                    action: { deviceManager.setNoiseControl(.off) }
                )
            } else {
                EarControlLabel(title: "Listening", symbol: "waveform")
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .earSurface()
    }

    private var batterySummary: some View {
        HStack(spacing: 8) {
            CompactEarBattery(title: "L", status: deviceManager.state.leftBattery)
            CompactEarBattery(title: "R", status: deviceManager.state.rightBattery)
            CompactEarBattery(title: "C", status: deviceManager.state.caseBattery)
        }
    }

    private var quickOptionsRow: some View {
        HStack(spacing: 6) {
            if deviceManager.state.capabilities.supportsBassEnhance {
                EarOptionChip(
                    title: "Bass",
                    symbol: "waveform",
                    isOn: deviceManager.state.bassEnhanceEnabled,
                    action: {
                        deviceManager.setBass(
                            enabled: !deviceManager.state.bassEnhanceEnabled,
                            level: deviceManager.state.bassLevel
                        )
                    }
                )
            }

            if deviceManager.state.capabilities.supportsLowLatency {
                EarOptionChip(
                    title: "Low latency",
                    symbol: "timer",
                    isOn: deviceManager.state.lowLatencyEnabled,
                    action: { deviceManager.setLowLatency(!deviceManager.state.lowLatencyEnabled) }
                )
            }

            if deviceManager.state.capabilities.supportsInEarDetection {
                EarOptionChip(
                    title: "In-ear",
                    symbol: "ear",
                    isOn: deviceManager.state.inEarDetectionEnabled,
                    action: { deviceManager.setInEarDetection(!deviceManager.state.inEarDetectionEnabled) }
                )
            }

            Spacer(minLength: 2)

            if let error = deviceManager.lastError {
                Text(error)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .frame(height: 26)
    }

    private var disconnectedContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                EarDeviceGlyph(isConnected: false)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Nothing Ear")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(connectionSubtitle)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if deviceManager.state.connection == .connecting
                    || deviceManager.state.connection == .reconnecting
                {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.effectiveAccent)
                        .frame(width: 28, height: 28)
                } else {
                    EarCircleAction(symbol: "arrow.clockwise") {
                        deviceManager.refreshDiscovery()
                    }
                }
            }
            .frame(height: 34)

            if deviceManager.discoveredDevices.isEmpty {
                HStack(spacing: 9) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.effectiveAccent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("No earbuds selected")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.82))
                        Text("Pair a Nothing or CMF device, then refresh this tab.")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.46))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 11)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .earSurface()
            } else {
                VStack(spacing: 5) {
                    ForEach(Array(deviceManager.discoveredDevices.prefix(2))) { device in
                        EarDiscoveredDeviceRow(device: device) {
                            deviceManager.connect(to: device)
                        }
                    }
                }
            }

            if let error = deviceManager.lastError {
                Text(error)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var connectionSubtitle: String {
        switch deviceManager.state.connection {
        case .connecting, .reconnecting, .discovering:
            return deviceManager.state.connection.label
        case .failed:
            return "Couldn’t connect automatically"
        default:
            return "Ready to connect"
        }
    }

    private var isANCSelected: Bool {
        if case .noiseCancellation = deviceManager.state.noiseControl { return true }
        return false
    }

    private var ancSegmentTitle: String {
        guard case let .noiseCancellation(level) = deviceManager.state.noiseControl else {
            return "ANC"
        }
        return switch level {
        case 1: "ANC · Low"
        case 2: "ANC · Mid"
        case 3: "ANC · High"
        case 4: "ANC · Adaptive"
        default: "ANC"
        }
    }
}

private extension View {
    func earSurface(cornerRadius: CGFloat = 13) -> some View {
        background(
            Color.white.opacity(0.065),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
        }
    }
}

private struct EarDeviceGlyph: View {
    let isConnected: Bool

    var body: some View {
        Image(systemName: "airpodspro")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isConnected ? Color.effectiveAccent : .white.opacity(0.68))
            .frame(width: 31, height: 31)
            .background(
                isConnected ? Color.effectiveAccent.opacity(0.14) : Color.white.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
    }
}

private struct CompactEarBattery: View {
    let title: String
    let status: BatteryStatus

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 2)
                if let level = status.level {
                    Circle()
                        .trim(from: 0, to: CGFloat(level) / 100)
                        .stroke(
                            level <= 20 ? Color.orange : Color.effectiveAccent,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
                Text(status.level.map { "\($0)%" } ?? "—")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        status.level.map { $0 <= 20 ? Color.orange : .white.opacity(0.82) }
                            ?? .white.opacity(0.42)
                    )
            }

            if status.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.effectiveAccent)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct EarModeSegment: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.70))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                isSelected ? Color.effectiveAccent : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct EarControlLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.78))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EarOptionChip: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? .white : .white.opacity(0.60))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                isOn ? Color.effectiveAccent : Color.white.opacity(0.075),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(isOn ? 0.26 : 0.10), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct EarCircleAction: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.08), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }
}

private struct EarDiscoveredDeviceRow: View {
    let device: BluetoothDeviceRecord
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "airpodspro")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.effectiveAccent)
                    .frame(width: 27, height: 27)
                    .background(Color.effectiveAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(1)
                    Text(device.isConnected ? "Connected over Bluetooth" : "Nearby device")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.42))
                }

                Spacer(minLength: 6)

                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .earSurface(cornerRadius: 11)
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private struct NothingEarEqualizerPanel: View {
    @ObservedObject private var deviceManager = DeviceManager.shared

    var body: some View {
        EarPopoverContainer(
            title: "Equalizer",
            subtitle: deviceManager.state.descriptor?.name ?? "Sound profile"
        ) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(EqualizerPreset.allCases, id: \.self) { preset in
                    Button {
                        deviceManager.setEqualizer(preset)
                    } label: {
                        HStack(spacing: 8) {
                            Text(preset.title)
                            Spacer()
                            if deviceManager.state.equalizer == preset {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.effectiveAccent)
                            }
                        }
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.84))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(
                            deviceManager.state.equalizer == preset
                                ? Color.effectiveAccent.opacity(0.18)
                                : Color.white.opacity(0.055),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if deviceManager.state.capabilities.supportsCustomEQ {
                    Divider().overlay(Color.white.opacity(0.10))
                    Text("CUSTOM EQ")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.36))

                    ForEach(Array(["Bass", "Presence", "Treble"].enumerated()), id: \.offset) { index, title in
                        HStack(spacing: 8) {
                            Text(title)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.64))
                                .frame(width: 58, alignment: .leading)
                            Slider(value: customEQBinding(index: index), in: -12...12, step: 0.5)
                            Text(String(format: "%+.1f", customEQValue(at: index)))
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.48))
                                .frame(width: 34, alignment: .trailing)
                        }
                    }

                    EarPanelToggle(
                        title: "Advanced EQ",
                        symbol: "slider.horizontal.2.square",
                        isOn: deviceManager.state.advancedEQEnabled,
                        action: { deviceManager.setAdvancedEQ(!deviceManager.state.advancedEQEnabled) }
                    )
                }
            }
        }
    }

    private func customEQValue(at index: Int) -> Double {
        guard deviceManager.state.customEQ.indices.contains(index) else { return 0 }
        return deviceManager.state.customEQ[index]
    }

    private func customEQBinding(index: Int) -> Binding<Double> {
        Binding(
            get: { customEQValue(at: index) },
            set: { value in
                var levels = deviceManager.state.customEQ
                while levels.count < 3 { levels.append(0) }
                levels[index] = value
                deviceManager.setCustomEQ(levels)
            }
        )
    }
}

@MainActor
private struct NothingEarAdvancedPanel: View {
    @ObservedObject private var deviceManager = DeviceManager.shared
    @State private var caseLEDColors: [Color] = Array(repeating: .white, count: 5)

    var body: some View {
        EarPopoverContainer(
            title: "More controls",
            subtitle: deviceManager.state.descriptor?.firmware.map { "Firmware \($0)" } ?? "Device features"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if deviceManager.state.capabilities.supportsPersonalizedANC {
                    EarPanelToggle(
                        title: "Personalized ANC",
                        symbol: "waveform.path.ecg.rectangle",
                        isOn: deviceManager.state.personalizedANCEnabled,
                        action: { deviceManager.setPersonalizedANC(!deviceManager.state.personalizedANCEnabled) }
                    )
                }

                if deviceManager.state.capabilities.supportsEarTipFitTest {
                    Button {
                        deviceManager.runEarTipFitTest()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "ear")
                            Text("Run ear tip fit test")
                            Spacer()
                            if let result = deviceManager.state.earTipFitResult {
                                Text("L \(fitLabel(result.left)) · R \(fitLabel(result.right))")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.48))
                            } else {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                        }
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.horizontal, 10)
                        .frame(height: 31)
                        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if deviceManager.state.capabilities.supportsFindMyEarbuds {
                    HStack(spacing: 6) {
                        Label("Find earbuds", systemImage: "location.fill")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.78))
                        Spacer()
                        EarSmallAction(title: "L") { deviceManager.ring(.left, enabled: true) }
                        EarSmallAction(title: "R") { deviceManager.ring(.right, enabled: true) }
                        EarSmallAction(title: "Stop") { deviceManager.ring(nil, enabled: false) }
                    }
                }

                if deviceManager.state.capabilities.supportsGestures {
                    Divider().overlay(Color.white.opacity(0.10))
                    Text("GESTURES")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.36))

                    ForEach(GestureSide.allCases, id: \.self) { side in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(side.title)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.44))
                            ForEach(GestureKind.allCases, id: \.self) { kind in
                                gestureMenu(side: side, kind: kind)
                            }
                        }
                    }
                }

                if deviceManager.state.capabilities.supportsCaseLED {
                    Divider().overlay(Color.white.opacity(0.10))
                    HStack {
                        Text("Case lights")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        ForEach(0..<5, id: \.self) { index in
                            ColorPicker("", selection: ledBinding(index: index), supportsOpacity: false)
                                .labelsHidden()
                                .frame(width: 24, height: 24)
                        }
                    }
                }
            }
        }
        .onAppear(perform: hydrateLEDColors)
        .onChange(of: deviceManager.state.caseLEDColors) { _, _ in
            hydrateLEDColors()
        }
    }

    @ViewBuilder
    private func gestureMenu(side: GestureSide, kind: GestureKind) -> some View {
        let currentAction = deviceManager.state.gestures.first {
            $0.side == side && $0.kind == kind
        }?.action ?? .noAction

        Menu {
            ForEach(GestureAction.allCases, id: \.self) { action in
                Button {
                    deviceManager.setGesture(GestureSetting(side: side, kind: kind, action: action))
                } label: {
                    HStack {
                        Text(action.title)
                        if currentAction == action { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(kind.title)
                Spacer()
                Text(currentAction.title)
                    .foregroundStyle(.white.opacity(0.44))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.38))
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 9)
            .frame(height: 27)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .menuStyle(.borderlessButton)
    }

    private func ledBinding(index: Int) -> Binding<Color> {
        Binding(
            get: { caseLEDColors.indices.contains(index) ? caseLEDColors[index] : .white },
            set: { color in
                while caseLEDColors.count <= index { caseLEDColors.append(.white) }
                caseLEDColors[index] = color
                deviceManager.setCaseLEDColors(caseLEDColors.map(rgbColor(from:)))
            }
        )
    }

    private func hydrateLEDColors() {
        guard !deviceManager.state.caseLEDColors.isEmpty else { return }
        caseLEDColors = deviceManager.state.caseLEDColors.map {
            Color(red: Double($0.red) / 255, green: Double($0.green) / 255, blue: Double($0.blue) / 255)
        }
        while caseLEDColors.count < 5 { caseLEDColors.append(.white) }
    }

    private func rgbColor(from color: Color) -> RGBColor {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
        return RGBColor(
            red: UInt8((nsColor.redComponent * 255).rounded()),
            green: UInt8((nsColor.greenComponent * 255).rounded()),
            blue: UInt8((nsColor.blueComponent * 255).rounded())
        )
    }

    private func fitLabel(_ value: Int) -> String {
        switch value {
        case 0: "Good"
        case 1: "Adjust"
        default: "—"
        }
    }
}

private struct EarPopoverContainer<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    init(title: String, subtitle: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.88))
                Text(subtitle)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }

            ScrollView {
                content()
            }
            .scrollIndicators(.never)
        }
        .padding(14)
        .frame(width: 330, height: 350, alignment: .topLeading)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}

private struct EarPanelToggle: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isOn ? Color.effectiveAccent : .white.opacity(0.55))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.80))
                Spacer()
                Circle()
                    .fill(isOn ? Color.effectiveAccent : Color.white.opacity(0.14))
                    .frame(width: 16, height: 16)
                    .overlay {
                        if isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
            }
            .padding(.horizontal, 10)
            .frame(height: 31)
            .background(
                isOn ? Color.effectiveAccent.opacity(0.15) : Color.white.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct EarSmallAction: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Color.white.opacity(0.07), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.11), lineWidth: 0.7))
    }
}
