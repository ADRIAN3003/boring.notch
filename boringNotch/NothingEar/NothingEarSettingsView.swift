import AppKit
import SwiftUI

@MainActor
struct NothingEarSettingsView: View {
    @ObservedObject private var deviceManager = DeviceManager.shared
    @State private var caseLEDColors: [Color] = Array(repeating: .white, count: 5)

    var body: some View {
        Form {
            connectionSection
            if deviceManager.state.isConnected {
                quickSettingsSection
                advancedSettingsSection
                gesturesSection
                findMyEarbudsSection
            } else {
                pairingSection
            }
            privacySection
        }
        .formStyle(.grouped)
        .tint(.effectiveAccent)
        .navigationTitle("Nothing Ear")
        .onAppear {
            deviceManager.start()
            hydrateLEDColors()
        }
        .onChange(of: deviceManager.state.caseLEDColors) { _, _ in
            hydrateLEDColors()
        }
    }

    private var connectionSection: some View {
        Section("Connection") {
            HStack(spacing: 10) {
                Image(systemName: deviceManager.state.isConnected ? "airpodspro" : "waveform")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(deviceManager.state.isConnected ? Color.effectiveAccent : .secondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(deviceManager.state.descriptor?.name ?? "No Nothing / CMF device connected")
                        .fontWeight(.semibold)
                    Text(deviceManager.state.connection.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if deviceManager.state.isConnected {
                    Button("Refresh") { deviceManager.refreshState() }
                    Button("Disconnect") { deviceManager.disconnect() }
                } else {
                    Button("Refresh") { deviceManager.refreshDiscovery() }
                }
            }

            if let error = deviceManager.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var pairingSection: some View {
        Section("Known devices") {
            if deviceManager.discoveredDevices.isEmpty && deviceManager.repository.knownDevices.isEmpty {
                Text("Pair your earbuds in System Settings → Bluetooth, then press Refresh.")
                    .foregroundStyle(.secondary)
            }

            ForEach(deviceManager.discoveredDevices) { device in
                deviceRow(device, discovered: true)
            }

            ForEach(deviceManager.repository.knownDevices) { device in
                if !deviceManager.discoveredDevices.contains(where: { $0.representsSamePhysicalDevice(as: device) }) {
                    deviceRow(device, discovered: false)
                }
            }
        }
    }

    private func deviceRow(_ device: BluetoothDeviceRecord, discovered: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "airpodspro")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .lineLimit(1)
                Text(discovered ? "Discovered" : "Saved device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Connect") {
                deviceManager.connect(to: device)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            if !discovered {
                Button {
                    deviceManager.removeKnownDevice(device)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var quickSettingsSection: some View {
        Section("Listening") {
            if deviceManager.state.capabilities.supportsNoiseControl {
                HStack {
                    Label("Noise control", systemImage: "waveform.path.ecg")
                    Spacer()
                    Menu(deviceManager.state.noiseControl.title) {
                        Button("Off") { deviceManager.setNoiseControl(.off) }
                        if deviceManager.state.capabilities.supportsTransparency {
                            Button("Transparency") { deviceManager.setNoiseControl(.transparency) }
                        }
                        if deviceManager.state.capabilities.supportsANCStrength {
                            ForEach(1...4, id: \.self) { level in
                                Button(NoiseControlMode.noiseCancellation(level: level).title) {
                                    deviceManager.setNoiseControl(.noiseCancellation(level: level))
                                }
                            }
                        } else {
                            Button("Noise cancellation") {
                                deviceManager.setNoiseControl(deviceManager.state.noiseControl.selectedANCMode)
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                }
            }

            if deviceManager.state.capabilities.supportsEqualizer {
                Picker("Equalizer", selection: Binding(
                    get: { deviceManager.state.equalizer },
                    set: { deviceManager.setEqualizer($0) }
                )) {
                    ForEach(EqualizerPreset.allCases, id: \.self) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
            }

            if deviceManager.state.capabilities.supportsBassEnhance {
                Toggle("Bass Enhance", isOn: Binding(
                    get: { deviceManager.state.bassEnhanceEnabled },
                    set: { deviceManager.setBass(enabled: $0, level: deviceManager.state.bassLevel) }
                ))
                HStack {
                    Text("Bass level")
                    Slider(value: Binding(
                        get: { deviceManager.state.bassLevel },
                        set: { deviceManager.setBass(enabled: deviceManager.state.bassEnhanceEnabled, level: $0) }
                    ), in: 0...10, step: 0.5)
                    Text(deviceManager.state.bassLevel, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }
            }

            if deviceManager.state.capabilities.supportsLowLatency {
                Toggle("Low latency", isOn: Binding(
                    get: { deviceManager.state.lowLatencyEnabled },
                    set: { deviceManager.setLowLatency($0) }
                ))
            }

            if deviceManager.state.capabilities.supportsInEarDetection {
                Toggle("In-ear detection", isOn: Binding(
                    get: { deviceManager.state.inEarDetectionEnabled },
                    set: { deviceManager.setInEarDetection($0) }
                ))
            }
        }
    }

    @ViewBuilder
    private var advancedSettingsSection: some View {
        if deviceManager.state.capabilities.supportsCustomEQ
            || deviceManager.state.capabilities.supportsPersonalizedANC
            || deviceManager.state.capabilities.supportsEarTipFitTest
            || deviceManager.state.capabilities.supportsCaseLED
        {
            Section("Advanced") {
                if deviceManager.state.capabilities.supportsCustomEQ {
                    ForEach(Array(["Bass", "Presence", "Treble"].enumerated()), id: \.offset) { index, title in
                        HStack {
                            Text(title)
                                .frame(width: 72, alignment: .leading)
                            Slider(value: customEQBinding(index: index), in: -12...12, step: 0.5)
                            Text(deviceManager.state.customEQ[nothingSafe: index] ?? 0, format: .number.precision(.fractionLength(1)))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                    if deviceManager.state.capabilities.supportsCustomEQ {
                        Toggle("Advanced EQ", isOn: Binding(
                            get: { deviceManager.state.advancedEQEnabled },
                            set: { deviceManager.setAdvancedEQ($0) }
                        ))
                    }
                }

                if deviceManager.state.capabilities.supportsPersonalizedANC {
                    Toggle("Personalized ANC", isOn: Binding(
                        get: { deviceManager.state.personalizedANCEnabled },
                        set: { deviceManager.setPersonalizedANC($0) }
                    ))
                }

                if deviceManager.state.capabilities.supportsEarTipFitTest {
                    HStack {
                        Button("Run ear tip fit test") { deviceManager.runEarTipFitTest() }
                        Spacer()
                        if let result = deviceManager.state.earTipFitResult {
                            Text("L \(fitLabel(result.left)) · R \(fitLabel(result.right))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if deviceManager.state.capabilities.supportsCaseLED {
                    ForEach(0..<5, id: \.self) { index in
                        ColorPicker("Case LED \(index + 1)", selection: ledBinding(index: index), supportsOpacity: false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var gesturesSection: some View {
        if deviceManager.state.capabilities.supportsGestures {
            Section("Gestures") {
                ForEach(GestureSide.allCases, id: \.self) { side in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(side.title)
                            .font(.headline)
                        ForEach(GestureKind.allCases, id: \.self) { kind in
                            Picker(kind.title, selection: gestureBinding(side: side, kind: kind)) {
                                ForEach(GestureAction.allCases, id: \.self) { action in
                                    Text(action.title).tag(action)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    @ViewBuilder
    private var findMyEarbudsSection: some View {
        if deviceManager.state.capabilities.supportsFindMyEarbuds {
            Section("Find My Earbuds") {
                HStack(spacing: 8) {
                    Button("Ring left") { deviceManager.ring(.left, enabled: true) }
                    Button("Ring right") { deviceManager.ring(.right, enabled: true) }
                    Button("Stop") { deviceManager.ring(nil, enabled: false) }
                }
            }
        }
    }

    private var privacySection: some View {
        Section {
            Label {
                Text("Bluetooth control stays local to this Mac. Feature availability depends on the earbud model and firmware.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func customEQBinding(index: Int) -> Binding<Double> {
        Binding(
            get: { deviceManager.state.customEQ[nothingSafe: index] ?? 0 },
            set: { value in
                var levels = deviceManager.state.customEQ
                while levels.count < 3 { levels.append(0) }
                levels[index] = value
                deviceManager.setCustomEQ(levels)
            }
        )
    }

    private func gestureBinding(side: GestureSide, kind: GestureKind) -> Binding<GestureAction> {
        Binding(
            get: {
                deviceManager.state.gestures.first(where: { $0.side == side && $0.kind == kind })?.action ?? .noAction
            },
            set: { action in
                deviceManager.setGesture(GestureSetting(side: side, kind: kind, action: action))
            }
        )
    }

    private func ledBinding(index: Int) -> Binding<Color> {
        Binding(
            get: { caseLEDColors[nothingSafe: index] ?? .white },
            set: { color in
                if caseLEDColors.count <= index {
                    caseLEDColors += Array(repeating: .white, count: index + 1 - caseLEDColors.count)
                }
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

private extension Array {
    subscript(nothingSafe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
