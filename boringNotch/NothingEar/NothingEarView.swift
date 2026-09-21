import SwiftUI

/// The compact, Boring Notch-native control surface for Nothing and CMF
/// earbuds. The protocol and Bluetooth stack live beside this view so the
/// notch stays useful even when the full settings window is closed.
@MainActor
struct NothingEarView: View {
    @ObservedObject private var deviceManager = DeviceManager.shared

    var body: some View {
        Group {
            if deviceManager.state.isConnected {
                connectedContent
            } else {
                disconnectedContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 15)
        .onAppear {
            deviceManager.start()
        }
    }

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "airpodspro")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.effectiveAccent)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

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
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.52))
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    CompactEarBattery(title: "L", status: deviceManager.state.leftBattery)
                    CompactEarBattery(title: "R", status: deviceManager.state.rightBattery)
                    CompactEarBattery(title: "C", status: deviceManager.state.caseBattery)
                }

                Button {
                    SettingsWindowController.shared.showWindow()
                } label: {
                    Image(systemName: "slider.horizontal.2.square")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Open Nothing Ear settings")
            }

            HStack(spacing: 7) {
                if deviceManager.state.capabilities.supportsNoiseControl {
                    EarModeButton(
                        title: "ANC",
                        symbol: "waveform.path.ecg",
                        isSelected: isANCSelected,
                        action: { deviceManager.setNoiseControl(.noiseCancellation(level: 1)) }
                    )

                    if deviceManager.state.capabilities.supportsTransparency {
                        EarModeButton(
                            title: "Transparency",
                            symbol: "ear",
                            isSelected: deviceManager.state.noiseControl == .transparency,
                            action: { deviceManager.setNoiseControl(.transparency) }
                        )
                    }

                    EarModeButton(
                        title: "Off",
                        symbol: "speaker.slash",
                        isSelected: deviceManager.state.noiseControl == .off,
                        action: { deviceManager.setNoiseControl(.off) }
                    )
                }

                if deviceManager.state.capabilities.supportsEqualizer {
                    Menu {
                        ForEach(EqualizerPreset.allCases, id: \.self) { preset in
                            Button {
                                deviceManager.setEqualizer(preset)
                            } label: {
                                Label(preset.title, systemImage: preset == deviceManager.state.equalizer ? "checkmark" : "")
                            }
                        }
                    } label: {
                        EarMenuLabel(title: deviceManager.state.equalizer.title, symbol: "slider.horizontal.3")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 7) {
                if deviceManager.state.capabilities.supportsBassEnhance {
                    EarToggleButton(
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
                    EarToggleButton(
                        title: "Low latency",
                        symbol: "timer",
                        isOn: deviceManager.state.lowLatencyEnabled,
                        action: { deviceManager.setLowLatency(!deviceManager.state.lowLatencyEnabled) }
                    )
                }
                if deviceManager.state.capabilities.supportsInEarDetection {
                    EarToggleButton(
                        title: "In-ear",
                        symbol: "ear",
                        isOn: deviceManager.state.inEarDetectionEnabled,
                        action: { deviceManager.setInEarDetection(!deviceManager.state.inEarDetectionEnabled) }
                    )
                }
                Spacer(minLength: 0)
                if let error = deviceManager.lastError {
                    Text(error)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange.opacity(0.85))
                        .lineLimit(1)
                }
            }
        }
    }

    private var disconnectedContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: "airpodspro")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.effectiveAccent)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nothing Ear controls")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(deviceManager.state.connection.label)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.52))
                }
                Spacer()
                Button {
                    SettingsWindowController.shared.showWindow()
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 7) {
                Image(systemName: "bluetooth")
                    .foregroundStyle(Color.effectiveAccent)
                Text("Pair a Nothing or CMF device in Bluetooth settings, then refresh here.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.60))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }

            if !deviceManager.discoveredDevices.isEmpty {
                HStack(spacing: 7) {
                    ForEach(deviceManager.discoveredDevices.prefix(2)) { device in
                        Button {
                            deviceManager.connect(to: device)
                        } label: {
                            HStack(spacing: 6) {
                                Text(device.name)
                                    .lineLimit(1)
                                Image(systemName: "arrow.right")
                            }
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 7) {
                Button("Refresh") {
                    deviceManager.refreshDiscovery()
                }
                .buttonStyle(EarTextButtonStyle())
                Button("Open settings") {
                    SettingsWindowController.shared.showWindow()
                }
                .buttonStyle(EarTextButtonStyle())
                Spacer(minLength: 0)
                if let error = deviceManager.lastError {
                    Text(error)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange.opacity(0.85))
                        .lineLimit(1)
                }
            }
        }
    }

    private var isANCSelected: Bool {
        if case .noiseCancellation = deviceManager.state.noiseControl { return true }
        return false
    }
}

private struct CompactEarBattery: View {
    let title: String
    let status: BatteryStatus

    var body: some View {
        HStack(spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.42))
            Text(status.level.map(String.init) ?? "—")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(status.level.map { $0 <= 20 ? Color.orange : .white.opacity(0.82) } ?? .white.opacity(0.42))
            if status.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.effectiveAccent)
            }
        }
        .padding(.horizontal, 5)
        .frame(height: 24)
        .background(Color.white.opacity(0.08), in: Capsule())
    }
}

private struct EarModeButton: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.78))
                    .frame(width: 42, height: 38)
                    .background(isSelected ? Color.effectiveAccent : Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.white.opacity(isSelected ? 0.32 : 0.12), lineWidth: 0.7))
                Text(title)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct EarMenuLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(.white.opacity(0.80))
        .frame(maxWidth: .infinity, minHeight: 38)
        .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 0.7))
    }
}

private struct EarToggleButton: View {
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
            .foregroundStyle(isOn ? .white : .white.opacity(0.64))
            .padding(.horizontal, 8)
            .frame(height: 25)
            .background(isOn ? Color.effectiveAccent : Color.white.opacity(0.09), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(isOn ? 0.28 : 0.12), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }
}

private struct EarTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.42 : 0.76))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 0.7))
    }
}
