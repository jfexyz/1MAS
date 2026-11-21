import Foundation
import IOBluetooth
import OneMoreKit

/// Finding devices and their channels.
public enum DeviceDirectory {
    public static func pairedDevices() -> [IOBluetoothDevice] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
    }

    /// Paired devices whose Bluetooth name is a known model.
    public static func knownDevices() -> [(device: IOBluetoothDevice, model: ModelInfo)] {
        pairedDevices().compactMap { device in
            ModelInfo.matching(bluetoothName: device.name ?? "").map { (device, $0) }
        }
    }

    public static func serviceRecords(_ device: IOBluetoothDevice) -> [IOBluetoothSDPServiceRecord] {
        (device.services as? [IOBluetoothSDPServiceRecord]) ?? []
    }

    /// The record's ServiceClassIDList (attribute 0x0001). IOBluetooth hands back a one-element list
    /// as the bare UUID element, so both shapes are handled.
    public static func serviceClassUUIDs(_ record: IOBluetoothSDPServiceRecord) -> [IOBluetoothSDPUUID] {
        guard let element = record.getAttributeDataElement(0x0001) else { return [] }
        if let uuid = element.getUUIDValue() { return [uuid] }
        let list = (element.getArrayValue() as? [IOBluetoothSDPDataElement]) ?? []
        return list.compactMap { $0.getUUIDValue() }
    }

    public static func rfcommChannel(_ record: IOBluetoothSDPServiceRecord) -> BluetoothRFCOMMChannelID? {
        var channel: BluetoothRFCOMMChannelID = 0
        return record.getRFCOMMChannelID(&channel) == kIOReturnSuccess ? channel : nil
    }

    static func isFirmwareUpdate(_ record: IOBluetoothSDPServiceRecord) -> Bool {
        (record.getServiceName() ?? "").uppercased().contains("OTA")
    }

    /// RFCOMM channels belonging to firmware-update services. Never opened.
    public static func firmwareUpdateChannels(_ device: IOBluetoothDevice) -> Set<BluetoothRFCOMMChannelID> {
        Set(serviceRecords(device).filter(isFirmwareUpdate).compactMap(rfcommChannel))
    }

    /// The RFCOMM channel of the record whose service class is exactly Serial Port (0x1101).
    ///
    /// Deliberately not `IOBluetoothDevice.getServiceRecord(for:)`: on the SonoFlow that returns the
    /// "OTA1" firmware-update service for 0x1101, which must never be opened by accident.
    public static func serialPortChannel(_ device: IOBluetoothDevice) -> BluetoothRFCOMMChannelID? {
        let serialPort = IOBluetoothSDPUUID(uuid16: 0x1101)!
        let channels = serviceRecords(device)
            .filter { !isFirmwareUpdate($0) && serviceClassUUIDs($0).contains { $0.isEqual(to: serialPort) } }
            .compactMap(rfcommChannel)
        return channels.first
    }

    /// Refreshes the device's SDP records from the device itself.
    @MainActor
    public static func refreshServices(_ device: IOBluetoothDevice, timeout: Duration = .seconds(20)) async throws {
        let waiter = SDPWaiter()
        try await waiter.run(device, timeout: timeout)
    }
}

@MainActor
private final class SDPWaiter: NSObject {
    private var continuation: CheckedContinuation<Void, any Error>?

    func run(_ device: IOBluetoothDevice, timeout: Duration) async throws {
        let timeoutTask = Task { [weak self] in
            try await Task.sleep(for: timeout)
            self?.finish(.failure(BluetoothError.openTimedOut))
        }
        defer { timeoutTask.cancel() }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let status = device.performSDPQuery(self)
            if status != kIOReturnSuccess { finish(.failure(BluetoothError.openFailed(status))) }
        }
    }

    @objc func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        finish(status == kIOReturnSuccess ? .success(()) : .failure(BluetoothError.openFailed(status)))
    }

    private func finish(_ result: Result<Void, any Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
