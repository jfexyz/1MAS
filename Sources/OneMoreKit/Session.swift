import Observation

/// A byte pipe to one device. The Bluetooth implementation lives in `OneMoreBluetooth`; tests use a
/// fake. Everything runs on the main actor, where IOBluetooth delivers its callbacks.
@MainActor
public protocol ByteTransport: AnyObject {
    var onReceive: (([UInt8]) -> Void)? { get set }
    var onClose: (() -> Void)? { get set }
    func send(_ bytes: [UInt8]) throws
    func close()
}

public enum SessionError: Error, Equatable, CustomStringConvertible {
    case timeout(command: UInt16)
    case closed
    case forbidden(command: UInt16)
    case unsupported(ListenMode)
    case rejected(command: UInt16, result: [UInt8])

    public var description: String {
        switch self {
        case .timeout(let command): "No reply to command \(hex16(command))"
        case .closed: "The connection to the headphones closed"
        case .forbidden(let command): "Command \(hex16(command)) is forbidden"
        case .unsupported(let mode): "This model does not support \(mode.label)"
        case .rejected(let command, let result): "The headphones rejected \(hex16(command)): \(result.hex)"
        }
    }
}

func hex16(_ value: UInt16) -> String {
    [UInt8(value >> 8), UInt8(value & 0xFF)].hex.filter { $0 != " " }
}

/// What we currently know about the device. Fields stay `nil` until first read.
public struct DeviceState: Equatable, Sendable {
    public var info: DeviceInfo?
    /// Raw listen-mode value; may be one `ListenMode` does not name.
    public var listenModeValue: UInt8?
    public var eqPreset: UInt8?

    public init() {}

    public var listenMode: ListenMode? { listenModeValue.flatMap(ListenMode.init(rawValue:)) }
}

/// The conversation with one device over a `ByteTransport`.
///
/// - Requests carry an incrementing sequence number; a reply is matched by command ID, oldest
///   outstanding request first. The SonoFlow echoes the sequence, but the vendor app does not rely
///   on it, so neither do we.
/// - Every frame that arrives, requested or not, updates `state`. The SonoFlow pushes a listen-mode
///   frame (`5F`) whenever the mode changes, which keeps `state` current without polling.
@MainActor
@Observable
public final class Session {
    public let model: ModelInfo
    public private(set) var state = DeviceState()
    public private(set) var isClosed = false

    /// Called with every frame sent (`outgoing == true`) and received, for logging.
    @ObservationIgnored public var frameObserver: ((Frame, _ outgoing: Bool) -> Void)?
    /// Called with every received frame that answered no request.
    @ObservationIgnored public var unsolicitedObserver: ((Frame) -> Void)?
    /// Called once when the transport closes.
    @ObservationIgnored public var onClose: (() -> Void)?

    @ObservationIgnored private let transport: ByteTransport
    @ObservationIgnored private var parser = FrameParser()
    @ObservationIgnored private var nextSequence: UInt16 = 0
    @ObservationIgnored private var nextRequestID = 0
    @ObservationIgnored private var pending: [Pending] = []

    private struct Pending {
        let id: Int
        let command: UInt16
        let continuation: CheckedContinuation<Frame, any Error>
    }

    public init(transport: ByteTransport, model: ModelInfo) {
        self.transport = transport
        self.model = model
        transport.onReceive = { [weak self] bytes in self?.receive(bytes) }
        transport.onClose = { [weak self] in self?.transportClosed() }
    }

    // MARK: High-level operations

    /// The vendor app's opening handshake. The SonoFlow works without it, so failure is ignored.
    public func handshake() async {
        _ = try? await request(Command.handshake.rawValue, payload: [0x01], timeout: .seconds(1))
    }

    /// Reads battery and firmware, listen mode, and EQ preset into `state`.
    public func refresh() async throws {
        _ = try await request(Command.deviceInfo.rawValue)
        _ = try await request(Command.getListenMode.rawValue)
        _ = try await request(Command.getEQPreset.rawValue)
    }

    public func refreshBattery() async throws {
        _ = try await request(Command.deviceInfo.rawValue)
    }

    /// Sets the listen mode, then reads it back so `state` reflects what the device did.
    public func setListenMode(_ mode: ListenMode) async throws {
        guard model.listenModes.contains(mode) else { throw SessionError.unsupported(mode) }
        let reply = try await request(Command.setListenMode.rawValue, payload: [mode.rawValue])
        guard reply.payload.first == WriteResult.success.rawValue else {
            throw SessionError.rejected(command: reply.command, result: reply.payload)
        }
        _ = try await request(Command.getListenMode.rawValue)
    }

    public func close() {
        transport.close()
        transportClosed()
    }

    // MARK: Requests

    /// Sends one request and returns the reply with the same command ID.
    public func request(
        _ command: UInt16, payload: [UInt8] = [], timeout: Duration = .seconds(3)
    ) async throws -> Frame {
        guard !Command.forbidden.contains(command) else { throw SessionError.forbidden(command: command) }
        guard !isClosed else { throw SessionError.closed }

        let frame = Frame.request(command, sequence: nextSequence, payload: payload)
        nextSequence &+= 1
        let id = nextRequestID
        nextRequestID += 1

        return try await withCheckedThrowingContinuation { continuation in
            pending.append(Pending(id: id, command: command, continuation: continuation))
            do {
                frameObserver?(frame, true)
                try transport.send(frame.bytes)
            } catch {
                resolve(id, with: .failure(error))
                return
            }
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.resolve(id, with: .failure(SessionError.timeout(command: command)))
            }
        }
    }

    private func resolve(_ id: Int, with result: Result<Frame, any Error>) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending.remove(at: index).continuation.resume(with: result)
    }

    // MARK: Incoming

    private func receive(_ bytes: [UInt8]) {
        for frame in parser.feed(bytes) {
            frameObserver?(frame, false)
            apply(frame)
            if frame.isResponse, let match = pending.first(where: { $0.command == frame.command }) {
                resolve(match.id, with: .success(frame))
            } else {
                unsolicitedObserver?(frame)
            }
        }
    }

    private func apply(_ frame: Frame) {
        switch Command(rawValue: frame.command) {
        case .deviceInfo:
            if let info = DeviceInfo(payload: frame.payload) { state.info = info }
        case .getListenMode:
            if let value = frame.payload.first { state.listenModeValue = value }
        case .getEQPreset:
            if let value = frame.payload.first { state.eqPreset = value }
        default:
            break
        }
    }

    private func transportClosed() {
        guard !isClosed else { return }
        isClosed = true
        let waiting = pending
        pending.removeAll()
        for request in waiting { request.continuation.resume(throwing: SessionError.closed) }
        onClose?()
    }
}

public extension DeviceInfo {
    /// The battery to show for a model: headphones report through the "left" fields.
    func battery(for model: ModelInfo) -> Int {
        switch model.kind {
        case .headphones: leftBattery
        case .earbuds: [leftBattery, rightBattery].filter { $0 > 0 }.min() ?? 0
        }
    }

    func firmware(for model: ModelInfo) -> String { leftVersion }
}
