import Foundation
import IOBluetooth
import OneMoreKit

let usage = """
    usage: onemore [--device NAME|ADDRESS] [--channel N] [--no-handshake] [-v] <command>

    commands:
      devices                 list paired devices whose name contains --device (default "1MORE")
      sdp [--refresh]         list the device's SDP service records and RFCOMM channels
      probe                   handshake, then read device info, listen mode, and EQ preset
      mode off|anc|transparent|<0-7>
                              set the listen mode and read it back
      raw <cmd> [payload]     send one request (hex) and print the reply
      listen <seconds>        open the channel and print anything the device sends
    """

struct Options {
    var device = "1MORE"
    var channel: BluetoothRFCOMMChannelID?
    var verbose = false
    var refresh = false
    var skipHandshake = false
    var arguments: [String] = []
}

func parseOptions() -> Options {
    var options = Options()
    var args = CommandLine.arguments.dropFirst()
    while let arg = args.popFirst() {
        switch arg {
        case "--device":
            guard let value = args.popFirst() else { fail("--device needs a value") }
            options.device = value
        case "--channel":
            guard let value = args.popFirst().flatMap({ BluetoothRFCOMMChannelID($0) }) else {
                fail("--channel needs a number")
            }
            options.channel = value
        case "-v", "--verbose": options.verbose = true
        case "--refresh": options.refresh = true
        case "--no-handshake": options.skipHandshake = true
        case "-h", "--help": print(usage); exit(0)
        default: options.arguments.append(arg)
        }
    }
    return options
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("onemore: \(message)\n".utf8))
    exit(1)
}

func matchingDevices(_ query: String) -> [IOBluetoothDevice] {
    let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
    let normalized = query.lowercased().replacingOccurrences(of: ":", with: "-")
    return paired.filter {
        ($0.name ?? "").lowercased().contains(normalized)
            || ($0.addressString ?? "").lowercased() == normalized
    }
}

func uuidString(_ uuid: IOBluetoothSDPUUID) -> String {
    let bytes = [UInt8](uuid as Data)
    return bytes.count == 2 || bytes.count == 4 ? "0x" + bytes.hex.replacingOccurrences(of: " ", with: "")
        : bytes.hex.replacingOccurrences(of: " ", with: "")
}

/// The record's ServiceClassIDList (attribute 0x0001). IOBluetooth hands back a one-element list
/// as the bare UUID element, so both shapes are handled.
func serviceClassUUIDs(_ record: IOBluetoothSDPServiceRecord) -> [IOBluetoothSDPUUID] {
    guard let element = record.getAttributeDataElement(0x0001) else { return [] }
    if let uuid = element.getUUIDValue() { return [uuid] }
    let list = (element.getArrayValue() as? [IOBluetoothSDPDataElement]) ?? []
    return list.compactMap { $0.getUUIDValue() }
}

func serviceClasses(_ record: IOBluetoothSDPServiceRecord) -> [String] {
    serviceClassUUIDs(record).map(uuidString)
}

/// Receives the result of an SDP query on the main run loop.
@MainActor
final class SDPWaiter: NSObject {
    var status: IOReturn?
    @objc func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        self.status = status
    }
}

@MainActor
func refreshSDP(_ device: IOBluetoothDevice) {
    let waiter = SDPWaiter()
    let start = device.performSDPQuery(waiter)
    guard start == kIOReturnSuccess else { fail("SDP query failed to start: \(ioReturnName(start))") }
    guard spin(timeout: 20, until: { waiter.status != nil }) else { fail("SDP query timed out") }
    if waiter.status != kIOReturnSuccess {
        print("SDP query finished with status \(ioReturnName(waiter.status!))")
    }
}

func printServices(_ device: IOBluetoothDevice) {
    let records = (device.services as? [IOBluetoothSDPServiceRecord]) ?? []
    print("\(records.count) service record(s) for \(device.name ?? "?") [\(device.addressString ?? "?")]")
    for record in records {
        var channel: BluetoothRFCOMMChannelID = 0
        let rfcomm = record.getRFCOMMChannelID(&channel) == kIOReturnSuccess ? "RFCOMM \(channel)" : "no RFCOMM"
        let name = record.getServiceName() ?? "(unnamed)"
        print("  \(name.padding(toLength: 28, withPad: " ", startingAt: 0)) \(rfcomm.padding(toLength: 10, withPad: " ", startingAt: 0)) \(serviceClasses(record).joined(separator: ", "))")
    }
}

/// The RFCOMM channel of the record whose service class is exactly Serial Port (0x1101).
///
/// Deliberately not `IOBluetoothDevice.getServiceRecord(for:)`: on the SonoFlow that returns the
/// "OTA1" firmware-update service for 0x1101, which must never be opened by accident.
func serialPortChannel(_ device: IOBluetoothDevice) -> BluetoothRFCOMMChannelID? {
    let serialPort = IOBluetoothSDPUUID(uuid16: 0x1101)!
    let records = (device.services as? [IOBluetoothSDPServiceRecord]) ?? []
    for record in records {
        let name = record.getServiceName() ?? ""
        guard !name.uppercased().contains("OTA"),
              serviceClassUUIDs(record).contains(where: { $0.isEqual(to: serialPort) })
        else { continue }
        var channel: BluetoothRFCOMMChannelID = 0
        if record.getRFCOMMChannelID(&channel) == kIOReturnSuccess { return channel }
    }
    return nil
}

@MainActor
func connect(_ device: IOBluetoothDevice, _ options: Options) throws -> RFCOMMLink {
    if options.refresh { refreshSDP(device) }
    guard let channelID = options.channel ?? serialPortChannel(device) else { throw LinkError.noSerialService }
    let records = (device.services as? [IOBluetoothSDPServiceRecord]) ?? []
    for record in records where (record.getServiceName() ?? "").uppercased().contains("OTA") {
        var channel: BluetoothRFCOMMChannelID = 0
        if record.getRFCOMMChannelID(&channel) == kIOReturnSuccess, channel == channelID {
            fail("channel \(channelID) is the firmware-update service; refusing to open it")
        }
    }
    let link = RFCOMMLink(device: device, verbose: options.verbose)
    try link.open(channelID: channelID)
    return link
}

@MainActor
func handshake(_ link: RFCOMMLink) {
    do {
        let reply = try link.request(Command.handshake.rawValue, payload: [0x01])
        print("handshake: \(reply.payload.hex)")
    } catch {
        print("handshake: \(error) (continuing)")
    }
}

func describe(_ mode: UInt8) -> String {
    ListenMode(rawValue: mode).map { "\($0) (\(mode))" } ?? "unknown (\(mode))"
}

@MainActor
func run() throws {
    let options = parseOptions()
    guard let command = options.arguments.first else { print(usage); exit(2) }
    let rest = Array(options.arguments.dropFirst())

    if command == "devices" {
        for device in matchingDevices(options.device) {
            print("\(device.name ?? "?")  \(device.addressString ?? "?")  connected: \(device.isConnected())")
        }
        return
    }

    let candidates = matchingDevices(options.device)
    guard let device = candidates.first else { throw LinkError.deviceNotFound(options.device) }
    if candidates.count > 1 { print("note: several matches, using \(device.name ?? "?")") }

    switch command {
    case "sdp":
        if options.refresh { refreshSDP(device) }
        printServices(device)

    case "probe":
        let link = try connect(device, options)
        defer { link.close() }
        if !options.skipHandshake { handshake(link) }
        let info = try link.request(Command.deviceInfo.rawValue)
        print("device info: \(info.payload.hex)")
        if let decoded = DeviceInfo(payload: info.payload) { print("  \(decoded)") }
        let mode = try link.request(Command.getListenMode.rawValue)
        print("listen mode: \(mode.payload.hex) -> \(mode.payload.first.map(describe) ?? "?")")
        let preset = try link.request(Command.getEQPreset.rawValue)
        print("EQ preset: \(preset.payload.hex)")
        link.listen(for: 1)

    case "mode":
        let names: [String: ListenMode] = ["off": .off, "anc": .strongANC, "transparent": .transparent]
        guard let arg = rest.first,
              let value = names[arg]?.rawValue ?? UInt8(arg), value <= 7
        else { fail("mode needs off, anc, transparent, or 0-7") }
        let link = try connect(device, options)
        defer { link.close() }
        if !options.skipHandshake { handshake(link) }
        let result = try link.request(Command.setListenMode.rawValue, payload: [value])
        print("set \(describe(value)): \(result.payload.hex)")
        for delay in [0.3, 1.0, 2.0] {
            link.listen(for: delay)
            let mode = try link.request(Command.getListenMode.rawValue)
            print("  read back after +\(delay)s: \(mode.payload.first.map(describe) ?? "?")")
        }

    case "raw":
        guard let cmdHex = rest.first, let cmdBytes = [UInt8](hex: cmdHex), (1...2).contains(cmdBytes.count),
              let payload = [UInt8](hex: rest.dropFirst().joined())
        else { fail("raw needs a command and an optional payload, in hex") }
        let cmd = cmdBytes.reduce(UInt16(0)) { $0 << 8 | UInt16($1) }
        guard !Command.forbidden.contains(cmd) else { fail(String(format: "%04X is forbidden", cmd)) }
        let link = try connect(device, options)
        defer { link.close() }
        if !options.skipHandshake { handshake(link) }
        let reply = try link.request(cmd, payload: payload)
        print(String(format: "%04X -> %@", cmd, reply.payload.hex))

    case "listen":
        let seconds = rest.first.flatMap(TimeInterval.init) ?? 10
        let link = try connect(device, options)
        defer { link.close() }
        if !options.skipHandshake { handshake(link) }
        link.listen(for: seconds)

    default:
        print(usage)
        exit(2)
    }
}

do {
    try MainActor.assumeIsolated { try run() }
} catch {
    fail("\(error)")
}
