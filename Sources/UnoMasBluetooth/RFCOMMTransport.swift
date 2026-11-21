import Foundation
import IOBluetooth
import UnoMasKit

public enum BluetoothError: Error, CustomStringConvertible {
    case noSerialService
    case firmwareUpdateChannel(BluetoothRFCOMMChannelID)
    case openFailed(IOReturn)
    case openTimedOut
    case writeFailed(IOReturn)
    case notOpen

    public var description: String {
        switch self {
        case .noSerialService: "The device has no Serial Port service"
        case .firmwareUpdateChannel(let id): "Channel \(id) is the firmware-update service; refusing to open it"
        case .openFailed(let code): "Opening the channel failed (\(ioReturnName(code)))"
        case .openTimedOut: "Opening the channel timed out"
        case .writeFailed(let code): "Writing to the channel failed (\(ioReturnName(code)))"
        case .notOpen: "The channel is not open"
        }
    }
}

public func ioReturnName(_ code: IOReturn) -> String {
    String(format: "0x%08X", UInt32(bitPattern: code))
}

/// An open RFCOMM channel to a device, as a `ByteTransport`.
@MainActor
public final class RFCOMMTransport: NSObject, ByteTransport, @preconcurrency IOBluetoothRFCOMMChannelDelegate {
    public var onReceive: (([UInt8]) -> Void)?
    public var onClose: (() -> Void)?
    /// Raw bytes in both directions, for logging.
    public var byteObserver: (([UInt8], _ outgoing: Bool) -> Void)?

    private var channel: IOBluetoothRFCOMMChannel?
    private var openContinuation: CheckedContinuation<Void, any Error>?

    /// Opens `channelID` on `device`, refusing the firmware-update service.
    ///
    /// Found on hardware: if the open is issued before the main run loop has turned for a while
    /// after launch, it never completes (and the sync variant fails with kIOReturnError). Opening
    /// from a task on a live run loop, after `warmUp`, works every time.
    public static func open(
        device: IOBluetoothDevice, channelID: BluetoothRFCOMMChannelID,
        warmUp: Duration = .seconds(1), timeout: Duration = .seconds(10)
    ) async throws -> RFCOMMTransport {
        if DeviceDirectory.firmwareUpdateChannels(device).contains(channelID) {
            throw BluetoothError.firmwareUpdateChannel(channelID)
        }
        try await Task.sleep(for: warmUp)
        let transport = RFCOMMTransport()
        try await transport.open(device: device, channelID: channelID, timeout: timeout)
        return transport
    }

    private func open(device: IOBluetoothDevice, channelID: BluetoothRFCOMMChannelID, timeout: Duration) async throws {
        let timeoutTask = Task { [weak self] in
            try await Task.sleep(for: timeout)
            self?.finishOpen(.failure(BluetoothError.openTimedOut))
        }
        defer { timeoutTask.cancel() }
        try await withCheckedThrowingContinuation { continuation in
            openContinuation = continuation
            var opened: IOBluetoothRFCOMMChannel?
            let status = device.openRFCOMMChannelAsync(&opened, withChannelID: channelID, delegate: self)
            channel = opened
            if status != kIOReturnSuccess { finishOpen(.failure(BluetoothError.openFailed(status))) }
        }
    }

    private func finishOpen(_ result: Result<Void, any Error>) {
        guard let continuation = openContinuation else { return }
        openContinuation = nil
        if case .failure = result {
            _ = channel?.close()
            channel = nil
        }
        continuation.resume(with: result)
    }

    public func send(_ bytes: [UInt8]) throws {
        guard let channel else { throw BluetoothError.notOpen }
        byteObserver?(bytes, true)
        var buffer = bytes
        let status = buffer.withUnsafeMutableBytes {
            channel.writeSync($0.baseAddress, length: UInt16($0.count))
        }
        guard status == kIOReturnSuccess else { throw BluetoothError.writeFailed(status) }
    }

    public func close() {
        guard let channel else { return }
        self.channel = nil
        _ = channel.close()
        onClose?()
    }

    // MARK: IOBluetoothRFCOMMChannelDelegate

    public func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        finishOpen(error == kIOReturnSuccess ? .success(()) : .failure(BluetoothError.openFailed(error)))
    }

    public func rfcommChannelData(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!,
        length dataLength: Int
    ) {
        let bytes = [UInt8](UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
        byteObserver?(bytes, false)
        onReceive?(bytes)
    }

    public func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        finishOpen(.failure(BluetoothError.openFailed(kIOReturnNotOpen)))
        guard channel != nil else { return }
        channel = nil
        onClose?()
    }
}
