@preconcurrency import CoreBluetooth
import Foundation

enum BluetoothAdapterState: String, Sendable {
    case unknown
    case resetting
    case unsupported
    case unauthorized
    case poweredOff
    case poweredOn
}

enum TransportEvent: Sendable {
    case connected
    case disconnected(reason: String?)
    case discovered(BluetoothDeviceRecord)
    case bytes(Data)
    case adapterState(BluetoothAdapterState)
}

@MainActor
protocol BluetoothTransport: AnyObject {
    var events: AsyncStream<TransportEvent> { get }
    var currentDevice: BluetoothDeviceRecord? { get }
    func discover() -> [BluetoothDeviceRecord]
    func connect(to device: BluetoothDeviceRecord) async throws
    func disconnect()
    func write(_ data: Data) throws
}

@MainActor
final class BluetoothStateMonitor: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate {
    @Published private(set) var state: BluetoothAdapterState = .unknown
    private var centralManager: CBCentralManager?
    private var stateContinuation: AsyncStream<BluetoothAdapterState>.Continuation?

    lazy var states: AsyncStream<BluetoothAdapterState> = {
        AsyncStream { continuation in
            stateContinuation = continuation
            continuation.yield(state)
        }
    }()

    override init() {
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let nextState: BluetoothAdapterState = switch central.state {
        case .unknown: .unknown
        case .resetting: .resetting
        case .unsupported: .unsupported
        case .unauthorized: .unauthorized
        case .poweredOff: .poweredOff
        case .poweredOn: .poweredOn
        @unknown default: .unknown
        }
        state = nextState
        stateContinuation?.yield(nextState)
    }
}

