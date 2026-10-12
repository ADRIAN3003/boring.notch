import AppKit
import Defaults
import SwiftUI

/// The Nothing / CMF control surface that lives in the expanded notch.
///
/// Laid out like the music player on the home tab: a square device tile on
/// the left, title and status in the same type styles as song and artist, a
/// battery row that mirrors the playback slider, and a toolbar underneath.
/// Everything that isn't used daily lives in the two anchored popovers.
@MainActor
struct NothingEarView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var deviceManager = DeviceManager.shared
    @State private var showingSound = false
    @State private var showingMore = false

    private var state: DeviceState { deviceManager.state }

    var body: some View {
        HStack(alignment: .top) {
            EarDeviceArtwork(isConnected: state.isConnected)
                .padding(.all, 5)

            Group {
                if state.isConnected {
                    connectedContent
                } else {
                    disconnectedContent
                }
            }
            .padding(.top, 10)
            .padding(.leading, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // Padding belongs inside the tab's slot. Padding on the outside makes
        // SwiftUI report a different height for this tab than Home and Shelf.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            deviceManager.start()
            updatePopoverActivity()
        }
        .onDisappear {
            vm.isEarPopoverActive = false
        }
        .onChange(of: showingSound) { _, _ in
            updatePopoverActivity()
        }
        .onChange(of: showingMore) { _, _ in
            updatePopoverActivity()
        }
        .onChange(of: state.isConnected) { _, connected in
            if !connected {
                showingSound = false
                showingMore = false
            }
        }
    }

    // MARK: - Connected

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(state.descriptor?.name ?? "Nothing Ear")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(connectedSubtitle)
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }

            HStack(spacing: 14) {
                EarBatteryGauge(title: "Left", status: state.leftBattery)
                EarBatteryGauge(title: "Right", status: state.rightBattery)
                EarBatteryGauge(title: "Case", status: state.caseBattery)
            }
            .padding(.top, 10)

            Spacer(minLength: 0)

            toolbar
        }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            if state.capabilities.supportsNoiseControl {
                EarModeSwitcher()
            }

            Spacer(minLength: 0)

            if let error = deviceManager.lastError {
                errorLabel(error)
            }

            if hasSoundControls {
                HoverButton(
                    icon: "slider.horizontal.3",
                    iconColor: showingSound ? .effectiveAccent : .primary,
                    scale: .medium
                ) {
                    showingSound.toggle()
                }
                .help("Sound")
                .popover(isPresented: $showingSound, arrowEdge: .bottom) {
                    NothingEarSoundPanel()
                }
            }

            HoverButton(
                icon: "ellipsis",
                iconColor: showingMore ? .effectiveAccent : .primary,
                scale: .medium
            ) {
                showingMore.toggle()
            }
            .help("More controls")
            .popover(isPresented: $showingMore, arrowEdge: .bottom) {
                NothingEarMorePanel(onDismiss: { showingMore = false })
            }
        }
        .frame(height: 30)
        .padding(.bottom, 4)
    }

    private var connectedSubtitle: String {
        var parts: [String] = []
        if state.capabilities.supportsNoiseControl {
            parts.append(state.noiseControl.title)
        }
        if state.capabilities.supportsEqualizer {
            parts.append(state.equalizer.title)
        }
        return parts.isEmpty ? state.connection.label : parts.joined(separator: " · ")
    }

    private var hasSoundControls: Bool {
        state.capabilities.supportsEqualizer
            || state.capabilities.supportsCustomEQ
            || state.capabilities.supportsBassEnhance
    }

    // MARK: - Disconnected

    private var disconnectedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Nothing Ear")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(connectionSubtitle)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 30, height: 30)
                } else {
                    HoverButton(icon: "arrow.clockwise", scale: .medium) {
                        deviceManager.refreshDiscovery()
                    }
                    .help("Look for devices")
                }
            }

            if deviceManager.discoveredDevices.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pair a Nothing or CMF device in Bluetooth settings, then refresh.")
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.65))
                        .lineLimit(2)

                    Button(action: openBluetoothSettings) {
                        Label("Bluetooth Settings", systemImage: "gearshape")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.effectiveAccent)
                }
                .padding(.top, 10)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(deviceManager.discoveredDevices.prefix(2))) { device in
                        EarDiscoveredDeviceRow(device: device) {
                            deviceManager.connect(to: device)
                        }
                    }
                }
                .padding(.top, 6)
                .padding(.leading, -8)
            }

            Spacer(minLength: 0)

            if let error = deviceManager.lastError {
                errorLabel(error)
                    .padding(.bottom, 4)
            }
        }
    }

    private var isBusy: Bool {
        state.connection == .connecting
            || state.connection == .reconnecting
            || state.connection == .discovering
    }

    private var connectionSubtitle: String {
        switch state.connection {
        case .connecting, .reconnecting, .discovering:
            return state.connection.label + "…"
        case .failed:
            return "Couldn’t connect automatically"
        default:
            return deviceManager.discoveredDevices.isEmpty ? "No earbuds found" : "Choose your earbuds"
        }
    }

    // MARK: - Helpers

    private func errorLabel(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func openBluetoothSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
            NSWorkspace.shared.open(url)
        }
    }

    private func updatePopoverActivity() {
        vm.isEarPopoverActive = showingSound || showingMore
    }
}

// MARK: - Notch components

/// Stands in for the album art on the home tab: same corner radius, same
/// "paused" shrink when nothing is connected, and the same accent glow as the
/// album-art lighting effect.
private struct EarDeviceArtwork: View {
    let isConnected: Bool

    private var cornerRadius: CGFloat {
        Defaults[.cornerRadiusScaling]
            ? MusicPlayerImageSizes.cornerRadiusInset.opened
            : MusicPlayerImageSizes.cornerRadiusInset.closed
    }

    var body: some View {
        ZStack {
            if Defaults[.lightingEffect] {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.effectiveAccent)
                    .scaleEffect(x: 1.1, y: 1.2)
                    .blur(radius: 40)
                    .opacity(isConnected ? 0.35 : 0)
            }

            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.14), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Image(systemName: "airpodspro")
                        .font(.system(size: 46, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isConnected ? Color.white : Color.gray)
                }
        }
        .aspectRatio(1, contentMode: .fit)
        .scaleEffect(isConnected ? 1 : 0.85)
        .animation(.smooth, value: isConnected)
    }
}

/// A battery level drawn the same way as the music progress bar, with the
/// colours `BatteryView` uses for low and charging states.
private struct EarBatteryGauge: View {
    let title: String
    let status: BatteryStatus

    private var fill: Color {
        guard let level = status.level else { return .clear }
        if status.isCharging { return .green }
        if level <= 20 { return .red }
        return .white
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.gray.opacity(0.3))
                    Capsule()
                        .fill(fill)
                        .frame(width: geometry.size.width * CGFloat(status.level ?? 0) / 100)
                }
            }
            .frame(height: 5)

            HStack(spacing: 3) {
                Text(title)
                Spacer(minLength: 2)
                if status.isCharging {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.green)
                }
                Text(status.level.map { "\($0)%" } ?? "—")
                    .monospacedDigit()
            }
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
        .animation(.smooth, value: status)
    }
}

/// Noise control modes, drawn like the tab switcher in the notch header.
@MainActor
private struct EarModeSwitcher: View {
    @ObservedObject private var deviceManager = DeviceManager.shared
    @Namespace private var animation

    private struct Mode: Identifiable {
        let id: String
        let title: String
        let target: NoiseControlMode
        let isSelected: Bool
    }

    private var modes: [Mode] {
        let current = deviceManager.state.noiseControl
        var modes: [Mode] = []

        let ancSelected: Bool = {
            if case .noiseCancellation = current { return true }
            return false
        }()
        modes.append(Mode(id: "anc", title: "Noise Cancelling", target: current.selectedANCMode, isSelected: ancSelected))

        if deviceManager.state.capabilities.supportsTransparency {
            modes.append(Mode(id: "transparency", title: "Transparency", target: .transparency, isSelected: current == .transparency))
        }

        modes.append(Mode(id: "off", title: "Off", target: .off, isSelected: current == .off))
        return modes
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(modes) { mode in
                Button {
                    deviceManager.setNoiseControl(mode.target)
                } label: {
                    Text(mode.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(mode.isSelected ? .white : .gray)
                .background {
                    if mode.isSelected {
                        Capsule()
                            .fill(Color(nsColor: .secondarySystemFill))
                            .matchedGeometryEffect(id: "capsule", in: animation)
                    }
                }
            }
        }
        .clipShape(Capsule())
        .animation(.smooth, value: deviceManager.state.noiseControl)
    }
}

private struct EarDiscoveredDeviceRow: View {
    let device: BluetoothDeviceRecord
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "airpodspro")
                    .foregroundStyle(.gray)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 0) {
                    Text(device.name)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(device.isConnected ? "Connected to this Mac" : "Nearby")
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.65))
                }

                Spacer(minLength: 6)

                Text("Connect")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.effectiveAccent)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isHovering ? Color.gray.opacity(0.2) : .clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.3)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Popovers

/// Shared chrome for both popovers, matching `BatteryMenuView`.
private struct EarPopover<Content: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            content()
        }
        .padding()
        .frame(width: 290)
        .tint(.effectiveAccent)
    }
}

private struct EarSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
    }
}

private struct EarToggleRow: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
    }
}

@MainActor
private struct NothingEarSoundPanel: View {
    @ObservedObject private var deviceManager = DeviceManager.shared

    private var state: DeviceState { deviceManager.state }

    var body: some View {
        EarPopover(title: "Sound", detail: state.capabilities.supportsEqualizer ? state.equalizer.title : nil) {
            if state.capabilities.supportsEqualizer {
                VStack(alignment: .leading, spacing: 6) {
                    EarSectionHeader(title: "Equalizer")
                    Picker("Equalizer", selection: Binding(
                        get: { state.equalizer },
                        set: { deviceManager.setEqualizer($0) }
                    )) {
                        ForEach(EqualizerPreset.allCases, id: \.self) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    .font(.subheadline)
                }
            }

            if state.capabilities.supportsCustomEQ {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    EarSectionHeader(title: "Custom EQ")
                    ForEach(Array(["Bass", "Mid", "Treble"].enumerated()), id: \.offset) { index, title in
                        EarSliderRow(
                            title: title,
                            value: customEQBinding(index: index),
                            range: -12...12,
                            format: "%+.1f dB"
                        )
                    }
                    EarToggleRow(
                        title: "Advanced EQ",
                        systemImage: "slider.vertical.3",
                        isOn: Binding(
                            get: { state.advancedEQEnabled },
                            set: { deviceManager.setAdvancedEQ($0) }
                        )
                    )
                    .padding(.top, 2)
                }
            }

            if state.capabilities.supportsBassEnhance {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    EarToggleRow(
                        title: "Bass Enhance",
                        systemImage: "speaker.wave.3",
                        isOn: Binding(
                            get: { state.bassEnhanceEnabled },
                            set: { deviceManager.setBass(enabled: $0, level: state.bassLevel) }
                        )
                    )
                    if state.bassEnhanceEnabled {
                        EarSliderRow(
                            title: "Level",
                            value: Binding(
                                get: { state.bassLevel },
                                set: { deviceManager.setBass(enabled: true, level: $0) }
                            ),
                            range: 0...10,
                            format: "%.1f"
                        )
                    }
                }
            }
        }
    }

    private func customEQBinding(index: Int) -> Binding<Double> {
        Binding(
            get: { state.customEQ.indices.contains(index) ? state.customEQ[index] : 0 },
            set: { value in
                var levels = state.customEQ
                while levels.count < 3 { levels.append(0) }
                levels[index] = value
                deviceManager.setCustomEQ(levels)
            }
        )
    }
}

private struct EarSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline)
                .frame(width: 48, alignment: .leading)
            Slider(value: $value, in: range, step: 0.5)
                .controlSize(.small)
            Text(String(format: format, value))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }
}

@MainActor
private struct NothingEarMorePanel: View {
    let onDismiss: () -> Void

    @ObservedObject private var deviceManager = DeviceManager.shared
    @State private var caseLEDColors: [Color] = Array(repeating: .white, count: 5)
    @State private var showingGestures = false

    private var state: DeviceState { deviceManager.state }
    private var capabilities: DeviceCapabilities { state.capabilities }

    var body: some View {
        EarPopover(
            title: state.descriptor?.name ?? "Nothing Ear",
            detail: state.descriptor?.firmware.flatMap { $0.isEmpty ? nil : "v\($0)" }
        ) {
            if capabilities.supportsANCStrength || capabilities.supportsPersonalizedANC {
                VStack(alignment: .leading, spacing: 6) {
                    EarSectionHeader(title: "Noise Cancelling")
                    if capabilities.supportsANCStrength {
                        Picker("Strength", selection: ancLevelBinding) {
                            Text("Low").tag(1)
                            Text("Mid").tag(2)
                            Text("High").tag(3)
                            Text("Adaptive").tag(4)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                    }
                    if capabilities.supportsPersonalizedANC {
                        EarToggleRow(
                            title: "Personalized ANC",
                            systemImage: "person.crop.circle.badge.checkmark",
                            isOn: Binding(
                                get: { state.personalizedANCEnabled },
                                set: { deviceManager.setPersonalizedANC($0) }
                            )
                        )
                    }
                }
            }

            if capabilities.supportsLowLatency || capabilities.supportsInEarDetection {
                VStack(alignment: .leading, spacing: 6) {
                    EarSectionHeader(title: "Listening")
                    if capabilities.supportsLowLatency {
                        EarToggleRow(
                            title: "Low Latency",
                            systemImage: "gamecontroller",
                            isOn: Binding(
                                get: { state.lowLatencyEnabled },
                                set: { deviceManager.setLowLatency($0) }
                            )
                        )
                    }
                    if capabilities.supportsInEarDetection {
                        EarToggleRow(
                            title: "In-Ear Detection",
                            systemImage: "ear",
                            isOn: Binding(
                                get: { state.inEarDetectionEnabled },
                                set: { deviceManager.setInEarDetection($0) }
                            )
                        )
                    }
                }
            }

            if capabilities.supportsFindMyEarbuds || capabilities.supportsEarTipFitTest {
                VStack(alignment: .leading, spacing: 8) {
                    EarSectionHeader(title: "Tools")

                    if capabilities.supportsFindMyEarbuds {
                        HStack(spacing: 6) {
                            Label("Find Earbuds", systemImage: "speaker.wave.2")
                                .font(.subheadline)
                            Spacer()
                            Button("Left") { deviceManager.ring(.left, enabled: true) }
                            Button("Right") { deviceManager.ring(.right, enabled: true) }
                            Button("Stop") { deviceManager.ring(nil, enabled: false) }
                        }
                        .controlSize(.small)
                    }

                    if capabilities.supportsEarTipFitTest {
                        HStack(spacing: 6) {
                            Label("Ear Tip Fit", systemImage: "ear.badge.checkmark")
                                .font(.subheadline)
                            Spacer()
                            if let result = state.earTipFitResult {
                                Text("L \(fitLabel(result.left)) · R \(fitLabel(result.right))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Button("Test") { deviceManager.runEarTipFitTest() }
                        }
                        .controlSize(.small)
                    }
                }
            }

            if capabilities.supportsCaseLED {
                HStack(spacing: 4) {
                    Label("Case Lights", systemImage: "light.max")
                        .font(.subheadline)
                    Spacer()
                    ForEach(0..<5, id: \.self) { index in
                        ColorPicker("", selection: ledBinding(index: index), supportsOpacity: false)
                            .labelsHidden()
                    }
                }
            }

            if capabilities.supportsGestures {
                DisclosureGroup(isExpanded: $showingGestures) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(GestureSide.allCases, id: \.self) { side in
                            VStack(alignment: .leading, spacing: 4) {
                                EarSectionHeader(title: side.title)
                                ForEach(GestureKind.allCases, id: \.self) { kind in
                                    Picker(kind.title, selection: gestureBinding(side: side, kind: kind)) {
                                        ForEach(GestureAction.allCases, id: \.self) { action in
                                            Text(action.title).tag(action)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .controlSize(.small)
                                    .font(.subheadline)
                                }
                            }
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Label("Gestures", systemImage: "hand.tap")
                        .font(.subheadline)
                }
            }

            Divider()

            Button(action: openSettings) {
                Label("Nothing Ear Settings", systemImage: "gearshape")
                    .fontWeight(.regular)
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
            .padding(.vertical, 2)
        }
        .onAppear(perform: hydrateLEDColors)
        .onChange(of: state.caseLEDColors) { _, _ in
            hydrateLEDColors()
        }
    }

    private var ancLevelBinding: Binding<Int> {
        Binding(
            get: {
                if case let .noiseCancellation(level) = state.noiseControl { return level }
                if case let .noiseCancellation(level) = state.noiseControl.selectedANCMode { return level }
                return 4
            },
            set: { deviceManager.setNoiseControl(.noiseCancellation(level: $0)) }
        )
    }

    private func gestureBinding(side: GestureSide, kind: GestureKind) -> Binding<GestureAction> {
        Binding(
            get: {
                state.gestures.first(where: { $0.side == side && $0.kind == kind })?.action ?? .noAction
            },
            set: { action in
                deviceManager.setGesture(GestureSetting(side: side, kind: kind, action: action))
            }
        )
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
        guard !state.caseLEDColors.isEmpty else { return }
        caseLEDColors = state.caseLEDColors.map {
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

    private func openSettings() {
        onDismiss()
        DispatchQueue.main.async {
            SettingsWindowController.shared.showWindow()
        }
    }
}
