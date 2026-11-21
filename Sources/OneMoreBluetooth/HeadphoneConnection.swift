import Foundation
import IOBluetooth
import Observation
import OneMoreKit

/// Keeps a `Session` open to whichever known 1MORE device is connected to this Mac.
///
/// - Connects at `start()` if a known device is already connected, and again whenever one connects
///   (macOS reports every Bluetooth connection; others are ignored).
/// - Retries a failed open a few times while the device stays connected, and reconnects if the
///   channel drops while the device is still connected.
/// - Re-reads the battery every few minutes; listen-mode changes arrive as pushes.
///
/// Note that only one host can hold the device's serial channel. While this is connected, the
/// vendor app on a phone cannot reach the headphones.
@MainActor
@Observable
public final class HeadphoneConnection {
    public enum Status: Equatable, Sendable {
        /// No known model is paired with this Mac.
        case noDevice
        /// A known model is paired but not connected.
        case disconnected(name: String)
        case connecting(name: String)
        case connected(name: String)
        /// Connected over Bluetooth, but the control channel could not be opened.
        case failed(name: String, failure: ConnectFailure)
    }

    /// Why the control channel could not be opened, from the last of the connection attempts.
    public enum ConnectFailure: Equatable, Sendable {
        /// Opening the channel never completed: usually another client holds it.
        case timedOut
        case bluetoothError(IOReturn)
        /// The channel opened, but the first read got no answer.
        case noReply
        /// The channel closed during the first read.
        case connectionDropped
        /// The device lists no Serial Port service.
        case noControlService
        case other(String)

        init(_ error: any Error) {
            switch error {
            case BluetoothError.openTimedOut: self = .timedOut
            case BluetoothError.openFailed(let code), BluetoothError.writeFailed(let code): self = .bluetoothError(code)
            case BluetoothError.noSerialService: self = .noControlService
            case BluetoothError.notOpen, SessionError.closed: self = .connectionDropped
            case SessionError.timeout: self = .noReply
            default: self = .other("\(error)")
            }
        }
    }

    public private(set) var status: Status = .noDevice
    public private(set) var session: Session?
    /// The most recent error from a user action, for display. Cleared on the next success.
    public var lastError: String?

    @ObservationIgnored public var batteryInterval: Duration = .seconds(300)
    @ObservationIgnored private var connectTarget: NotificationTarget?
    @ObservationIgnored private var disconnectTarget: NotificationTarget?
    @ObservationIgnored private var connectNotification: IOBluetoothUserNotification?
    @ObservationIgnored private var disconnectNotification: IOBluetoothUserNotification?
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    public init() {}

    public func start() {
        guard connectTarget == nil else { return }
        let target = NotificationTarget { [weak self] device in
            guard ModelInfo.matching(bluetoothName: device.name ?? "") != nil else { return }
            // Give the audio profiles a moment to come up before opening the control channel.
            self?.connectIfPossible(after: .seconds(2))
        }
        connectTarget = target
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: target, selector: #selector(NotificationTarget.fired(_:device:)))
        connectIfPossible(after: .zero)
    }

    public func setListenMode(_ mode: ListenMode) {
        guard let session else { return }
        Task {
            do {
                try await session.setListenMode(mode)
                lastError = nil
            } catch {
                lastError = "\(error)"
            }
        }
    }

    // MARK: Connecting

    private func connectIfPossible(after delay: Duration) {
        guard session == nil, connectTask == nil else { return }
        let known = DeviceDirectory.knownDevices()
        guard let (device, model) = known.first(where: { $0.device.isConnected() }) else {
            status = known.first.map { .disconnected(name: $0.device.name ?? $0.model.bluetoothName) } ?? .noDevice
            return
        }
        connectTask = Task {
            await connect(device, model: model, after: delay)
            connectTask = nil
        }
    }

    private func connect(_ device: IOBluetoothDevice, model: ModelInfo, after delay: Duration) async {
        let name = device.name ?? model.bluetoothName
        status = .connecting(name: name)
        try? await Task.sleep(for: delay)

        var failure = ConnectFailure.other("")
        for attempt in 1...3 {
            do {
                if DeviceDirectory.serialPortChannel(device) == nil {
                    try await DeviceDirectory.refreshServices(device)
                }
                guard let channel = DeviceDirectory.serialPortChannel(device) else {
                    throw BluetoothError.noSerialService
                }
                let transport = try await RFCOMMTransport.open(device: device, channelID: channel)
                let session = Session(transport: transport, model: model)
                await session.handshake()
                do {
                    try await session.refresh()
                } catch {
                    session.close()
                    throw error
                }
                adopt(session, device: device, name: name)
                return
            } catch {
                failure = ConnectFailure(error)
                guard device.isConnected() else { break }
                try? await Task.sleep(for: .seconds(2 * attempt))
            }
        }
        status = device.isConnected() ? .failed(name: name, failure: failure) : .disconnected(name: name)
    }

    private func adopt(_ session: Session, device: IOBluetoothDevice, name: String) {
        self.session = session
        status = .connected(name: name)
        session.onClose = { [weak self] in self?.sessionClosed(device: device, name: name) }

        let target = NotificationTarget { [weak self] _ in self?.session?.close() }
        disconnectTarget = target
        disconnectNotification = device.register(
            forDisconnectNotification: target, selector: #selector(NotificationTarget.fired(_:device:)))

        pollTask = Task { [weak self, batteryInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: batteryInterval)
                try? await self?.session?.refreshBattery()
            }
        }
    }

    private func sessionClosed(device: IOBluetoothDevice, name: String) {
        session = nil
        pollTask?.cancel()
        pollTask = nil
        disconnectNotification?.unregister()
        disconnectNotification = nil
        disconnectTarget = nil
        if device.isConnected() {
            connectIfPossible(after: .seconds(3))
        } else {
            status = .disconnected(name: name)
        }
    }
}

/// Receives IOBluetooth's selector-based device notifications on the main thread.
@MainActor
private final class NotificationTarget: NSObject {
    private let handler: (IOBluetoothDevice) -> Void

    init(_ handler: @escaping (IOBluetoothDevice) -> Void) {
        self.handler = handler
    }

    @objc func fired(_ notification: IOBluetoothUserNotification!, device: IOBluetoothDevice!) {
        if let device { handler(device) }
    }
}
