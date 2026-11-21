import Foundation
import IOBluetooth
import OneMoreKit

enum LinkError: Error, CustomStringConvertible {
    case deviceNotFound(String)
    case noSerialService
    case openFailed(IOReturn)
    case writeFailed(IOReturn)
    case timeout(String)
    case closed

    var description: String {
        switch self {
        case .deviceNotFound(let query): "No paired device matches \"\(query)\""
        case .noSerialService: "No Serial Port (0x1101) service in the device's SDP records"
        case .openFailed(let code): "Opening the RFCOMM channel failed: \(ioReturnName(code))"
        case .writeFailed(let code): "Write failed: \(ioReturnName(code))"
        case .timeout(let what): "Timed out waiting for \(what)"
        case .closed: "The device closed the channel"
        }
    }
}

func ioReturnName(_ code: IOReturn) -> String {
    String(format: "0x%08X", UInt32(bitPattern: code))
}

/// Pumps the main run loop, where IOBluetooth delivers its callbacks, until `done` or timeout.
@MainActor
func spin(timeout: TimeInterval, until done: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !done() {
        if Date() >= deadline { return false }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    return true
}

/// Synchronous-looking request/response over one RFCOMM channel, for the CLI.
@MainActor
final class RFCOMMLink: NSObject, @preconcurrency IOBluetoothRFCOMMChannelDelegate {
    let device: IOBluetoothDevice
    let verbose: Bool
    private var channel: IOBluetoothRFCOMMChannel?
    private var openStatus: IOReturn?
    private var isClosed = false
    private var parser = FrameParser()
    private var inbox: [Frame] = []
    private var nextSequence: UInt16 = 0

    init(device: IOBluetoothDevice, verbose: Bool) {
        self.device = device
        self.verbose = verbose
    }

    func open(channelID: BluetoothRFCOMMChannelID) throws {
        log("opening RFCOMM channel \(channelID)")
        // Found on hardware (macOS 27.2): opening the channel before the run loop has turned at all
        // never completes, and `openRFCOMMChannelSync` fails with kIOReturnError. A short warm-up
        // makes the async open succeed every time. Exact cause unknown; the app will have a live
        // run loop anyway.
        _ = spin(timeout: 1, until: { false })
        var opened: IOBluetoothRFCOMMChannel?
        let status = device.openRFCOMMChannelAsync(&opened, withChannelID: channelID, delegate: self)
        guard status == kIOReturnSuccess else { throw LinkError.openFailed(status) }
        channel = opened
        guard spin(timeout: 10, until: { openStatus != nil }) else {
            throw LinkError.timeout("the channel to open")
        }
        guard openStatus == kIOReturnSuccess else { throw LinkError.openFailed(openStatus!) }
        log("channel open, MTU \(channel?.getMTU() ?? 0)")
    }

    func close() {
        _ = channel?.close()
        channel = nil
    }

    /// Sends a request and waits for the first reply carrying the same command ID. Other frames
    /// arriving meanwhile are printed as unsolicited.
    func request(_ command: UInt16, payload: [UInt8] = [], timeout: TimeInterval = 3) throws -> Frame {
        guard !Command.forbidden.contains(command) else {
            fatalError(String(format: "refusing forbidden command %04X", command))
        }
        try send(Frame.request(command, sequence: takeSequence(), payload: payload))
        var reply: Frame?
        let ok = spin(timeout: timeout) {
            if let index = inbox.firstIndex(where: { $0.command == command && $0.isResponse }) {
                reply = inbox.remove(at: index)
            }
            return reply != nil || isClosed
        }
        drainUnsolicited()
        if let reply { return reply }
        if isClosed { throw LinkError.closed }
        precondition(!ok)
        throw LinkError.timeout(String(format: "a reply to %04X", command))
    }

    /// Waits and prints whatever the device sends unprompted.
    func listen(for seconds: TimeInterval) {
        _ = spin(timeout: seconds) { isClosed }
        drainUnsolicited()
    }

    private func send(_ frame: Frame) throws {
        guard let channel else { throw LinkError.closed }
        var bytes = frame.bytes
        log("-> \(bytes.hex)")
        let status = bytes.withUnsafeMutableBytes {
            channel.writeSync($0.baseAddress, length: UInt16($0.count))
        }
        guard status == kIOReturnSuccess else { throw LinkError.writeFailed(status) }
    }

    private func takeSequence() -> UInt16 {
        defer { nextSequence &+= 1 }
        return nextSequence
    }

    private func drainUnsolicited() {
        for frame in inbox {
            print(String(format: "unsolicited %04X: %@", frame.command, frame.payload.hex))
        }
        inbox.removeAll()
    }

    private func log(_ message: String) {
        if verbose { FileHandle.standardError.write(Data("[link] \(message)\n".utf8)) }
    }

    // MARK: IOBluetoothRFCOMMChannelDelegate

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        openStatus = error
    }

    func rfcommChannelData(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!,
        length dataLength: Int
    ) {
        let bytes = [UInt8](UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
        log("<- \(bytes.hex)")
        let frames = parser.feed(bytes)
        for frame in frames where !frame.checksumIsValid {
            log(String(format: "note: bad checksum on %04X", frame.command))
        }
        inbox += frames
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        log("channel closed")
        isClosed = true
    }
}
