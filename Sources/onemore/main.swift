import Foundation
import IOBluetooth
import OneMoreBluetooth
import OneMoreKit

let usage = """
    usage: onemore [--device NAME|ADDRESS] [--channel N] [--no-handshake] [-v] <command>

    commands:
      devices                 list paired devices whose name contains --device (default "1MORE")
      sdp [--refresh]         list the device's SDP service records and RFCOMM channels
      probe                   read device info, listen mode, and EQ preset
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

func log(_ message: String) {
    FileHandle.standardError.write(Data("[link] \(message)\n".utf8))
}

func matchingDevices(_ query: String) -> [IOBluetoothDevice] {
    let normalized = query.lowercased().replacingOccurrences(of: ":", with: "-")
    return DeviceDirectory.pairedDevices().filter {
        ($0.name ?? "").lowercased().contains(normalized)
            || ($0.addressString ?? "").lowercased() == normalized
    }
}

func uuidString(_ uuid: IOBluetoothSDPUUID) -> String {
    let bytes = [UInt8](uuid as Data)
    let digits = bytes.hex.replacingOccurrences(of: " ", with: "")
    return bytes.count <= 4 ? "0x" + digits : digits
}

func printServices(_ device: IOBluetoothDevice) {
    let records = DeviceDirectory.serviceRecords(device)
    print("\(records.count) service record(s) for \(device.name ?? "?") [\(device.addressString ?? "?")]")
    for record in records {
        let rfcomm = DeviceDirectory.rfcommChannel(record).map { "RFCOMM \($0)" } ?? "no RFCOMM"
        let name = record.getServiceName() ?? "(unnamed)"
        let classes = DeviceDirectory.serviceClassUUIDs(record).map(uuidString).joined(separator: ", ")
        print("  \(name.padding(toLength: 28, withPad: " ", startingAt: 0)) "
            + "\(rfcomm.padding(toLength: 10, withPad: " ", startingAt: 0)) \(classes)")
    }
}

func describe(_ mode: UInt8) -> String {
    ListenMode(rawValue: mode).map { "\($0.label) (\(mode))" } ?? "unknown (\(mode))"
}

@MainActor
func openSession(_ device: IOBluetoothDevice, _ options: Options) async throws -> Session {
    if options.refresh { try await DeviceDirectory.refreshServices(device) }
    guard let channelID = options.channel ?? DeviceDirectory.serialPortChannel(device) else {
        throw BluetoothError.noSerialService
    }
    if options.verbose { log("opening RFCOMM channel \(channelID)") }
    let transport = try await RFCOMMTransport.open(device: device, channelID: channelID)
    if options.verbose {
        transport.byteObserver = { bytes, outgoing in log("\(outgoing ? "->" : "<-") \(bytes.hex)") }
    }
    // Unknown models get the SonoFlow's table; the CLI is for probing, so it does not refuse them.
    let model = ModelInfo.matching(bluetoothName: device.name ?? "") ?? .sonoFlow
    let session = Session(transport: transport, model: model)
    session.unsolicitedObserver = { frame in
        print(String(format: "unsolicited %04X: %@", frame.command, frame.payload.hex))
    }
    if !options.skipHandshake {
        let reply = try? await session.request(Command.handshake.rawValue, payload: [0x01], timeout: .seconds(1))
        print("handshake: \(reply?.payload.hex ?? "no reply")")
    }
    return session
}

@MainActor
func run() async throws {
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
    guard let device = candidates.first else { fail("no paired device matches \"\(options.device)\"") }
    if candidates.count > 1 { print("note: several matches, using \(device.name ?? "?")") }

    switch command {
    case "sdp":
        if options.refresh { try await DeviceDirectory.refreshServices(device) }
        printServices(device)

    case "probe":
        let session = try await openSession(device, options)
        defer { session.close() }
        let info = try await session.request(Command.deviceInfo.rawValue)
        print("device info: \(info.payload.hex)")
        if let decoded = DeviceInfo(payload: info.payload) { print("  \(decoded)") }
        let mode = try await session.request(Command.getListenMode.rawValue)
        print("listen mode: \(mode.payload.hex) -> \(mode.payload.first.map(describe) ?? "?")")
        let preset = try await session.request(Command.getEQPreset.rawValue)
        print("EQ preset: \(preset.payload.hex) -> \(preset.payload.first.map(EQPreset.name) ?? "?")")
        try await Task.sleep(for: .seconds(1))

    case "mode":
        let names: [String: ListenMode] = ["off": .off, "anc": .strongANC, "transparent": .transparent]
        guard let arg = rest.first, let value = names[arg]?.rawValue ?? UInt8(arg), value <= 7 else {
            fail("mode needs off, anc, transparent, or 0-7")
        }
        let session = try await openSession(device, options)
        defer { session.close() }
        // Raw request rather than Session.setListenMode, so values outside the model table can be
        // probed too.
        let result = try await session.request(Command.setListenMode.rawValue, payload: [value])
        print("set \(describe(value)): \(result.payload.hex)")
        for delay in [0.3, 1.0, 2.0] {
            try await Task.sleep(for: .seconds(delay))
            let mode = try await session.request(Command.getListenMode.rawValue)
            print("  read back after +\(delay)s: \(mode.payload.first.map(describe) ?? "?")")
        }

    case "raw":
        guard let cmdHex = rest.first, let cmdBytes = [UInt8](hex: cmdHex), (1...2).contains(cmdBytes.count),
              let payload = [UInt8](hex: rest.dropFirst().joined())
        else { fail("raw needs a command and an optional payload, in hex") }
        let cmd = cmdBytes.reduce(UInt16(0)) { $0 << 8 | UInt16($1) }
        let session = try await openSession(device, options)
        defer { session.close() }
        let reply = try await session.request(cmd, payload: payload)
        print(String(format: "%04X -> %@", cmd, reply.payload.hex))

    case "listen":
        let seconds = rest.first.flatMap(Double.init) ?? 10
        let session = try await openSession(device, options)
        defer { session.close() }
        try await Task.sleep(for: .seconds(seconds))

    default:
        print(usage)
        exit(2)
    }
}

// IOBluetooth delivers its callbacks through the main run loop, so the work runs as a main-actor
// task while the run loop spins.
Task { @MainActor in
    do {
        try await run()
        exit(0)
    } catch {
        fail("\(error)")
    }
}
RunLoop.main.run()
