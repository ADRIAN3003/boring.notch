import Combine
import Foundation

@MainActor
final class DeviceRepository: ObservableObject {
    private let defaults: UserDefaults
    private let key = "knownDevices.v1"

    @Published private(set) var knownDevices: [BluetoothDeviceRecord] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func remember(_ device: BluetoothDeviceRecord) {
        var next = device
        next.lastSeen = .now
        if let index = knownDevices.firstIndex(where: { $0.representsSamePhysicalDevice(as: device) }) {
            let existing = knownDevices[index]
            if next.rfcommChannel == nil { next.rfcommChannel = existing.rfcommChannel }
            if existing.isConnected { next.isConnected = true }
            knownDevices[index] = next
        } else {
            knownDevices.append(next)
        }
        knownDevices.sort { $0.lastSeen > $1.lastSeen }
        save()
    }

    func updateChannel(_ channel: UInt8, for address: String) {
        guard let index = knownDevices.firstIndex(where: { $0.address.caseInsensitiveCompare(address) == .orderedSame }) else { return }
        knownDevices[index].rfcommChannel = channel
        save()
    }

    func remove(address: String) {
        knownDevices.removeAll {
            $0.address.caseInsensitiveCompare(address) == .orderedSame
        }
        save()
    }

    func device(matching address: String) -> BluetoothDeviceRecord? {
        knownDevices.first { $0.address.caseInsensitiveCompare(address) == .orderedSame }
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let devices = try? JSONDecoder().decode([BluetoothDeviceRecord].self, from: data)
        else { return }
        let deduplicated = Self.deduplicate(devices)
        // A persisted `isConnected` flag is only a last-known hint and can
        // otherwise make an old RFCOMM alias look like a second live device
        // before CoreBluetooth has finished reconnecting.
        knownDevices = deduplicated.map { device in
            var device = device
            device.isConnected = false
            return device
        }
        if knownDevices.count != devices.count {
            save()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(knownDevices) else { return }
        defaults.set(data, forKey: key)
    }

    private static func deduplicate(_ devices: [BluetoothDeviceRecord]) -> [BluetoothDeviceRecord] {
        var result: [BluetoothDeviceRecord] = []

        for device in devices.sorted(by: { $0.lastSeen > $1.lastSeen }) {
            guard let index = result.firstIndex(where: { $0.representsSamePhysicalDevice(as: device) }) else {
                result.append(device)
                continue
            }

            var merged = result[index]
            // Prefer the native CoreBluetooth identity after migrating from
            // the old RFCOMM/MAC representation.
            if device.isCoreBluetoothIdentifier && !merged.isCoreBluetoothIdentifier {
                merged.address = device.address
                merged.name = device.name
            }
            merged.isConnected = merged.isConnected || device.isConnected
            merged.rfcommChannel = merged.rfcommChannel ?? device.rfcommChannel
            merged.lastSeen = max(merged.lastSeen, device.lastSeen)
            result[index] = merged
        }

        return result
    }
}

