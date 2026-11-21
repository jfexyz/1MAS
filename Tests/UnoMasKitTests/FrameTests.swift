import Testing
@testable import UnoMasKit

/// Fixtures are real packets from the three public sources, so these tests pin our framing to
/// what the hardware and the vendor app actually exchange.
struct FrameTests {
    @Test("Gadgetbridge's hard-coded SonoFlow requests are sequence + header XOR", arguments: [
        // (command, sequence, payload, bytes as Gadgetbridge sends them)
        (UInt16(0x4E), UInt16(0x001C), [UInt8](), "11 01 00 4E 00 00 00 1C 42"),
        (0x5F, 0x000C, [], "11 01 00 5F 00 00 00 0C 43"),
        (0x5E, 0x0013, [0x03], "11 01 00 5E 00 01 00 13 5C 03"),
        (0x6C, 0x000D, [], "11 01 00 6C 00 00 00 0D 71"),
        (0x6B, 0x002D, [0x02], "11 01 00 6B 00 01 00 2D 57 02"),
        (0x77, 0x000C, [], "11 01 00 77 00 00 00 0C 6B"),
        (0x76, 0x000D, [0x01], "11 01 00 76 00 01 00 0D 6A 01"),
    ])
    func gadgetbridgeRequests(command: UInt16, sequence: UInt16, payload: [UInt8], expected: String) {
        #expect(Frame.request(command, sequence: sequence, payload: payload).bytes.hex == expected)
    }

    @Test func vendorHandshake() {
        // The handshake PairFree records from the vendor app.
        #expect(Frame.request(0x4D, sequence: 1, payload: [0x01]).bytes.hex
            == "11 01 00 4D 00 01 00 01 5D 01")
    }

    @Test func aeroListenModeRequest() {
        #expect(Frame.request(0x5F, sequence: 1).bytes.hex == "11 01 00 5F 00 00 00 01 4E")
    }

    @Test func parsesConcatenatedAndSplitReplies() throws {
        let listen = [UInt8](hex: "01 01 00 5F 00 01 00 0C 52 01")!
        let info = [UInt8](hex: "01 01 00 4E 00 0A 00 1C 58 00 01 03 00 3C 00 00 00 00 00")!
        let stream = listen + info

        var parser = FrameParser()
        var frames = parser.feed(stream.prefix(5))
        #expect(frames.isEmpty)
        frames += parser.feed(stream.dropFirst(5).prefix(12))
        frames += parser.feed(stream.dropFirst(17))

        #expect(frames.count == 2)
        #expect(frames[0].command == 0x5F)
        #expect(frames[0].payload == [0x01])
        #expect(frames[0].checksumIsValid)
        #expect(frames[1].command == 0x4E)
        #expect(frames[1].checksumIsValid)

        let device = try #require(DeviceInfo(payload: frames[1].payload))
        #expect(device.leftVersion == "1.3.0")
        #expect(device.leftBattery == 60)
    }

    @Test func skipsJunkAndFEFrames() {
        var parser = FrameParser()
        let junk: [UInt8] = [0x00, 0x42] + [0xFE] + Array(repeating: 0, count: 12)
        let frames = parser.feed(junk + [UInt8](hex: "01 01 00 5F 00 01 00 0C 52 03")!)
        #expect(frames.count == 1)
        #expect(frames[0].payload == [0x03])
        #expect(parser.discarded.count == 15)
    }

    @Test func aeroBatteryPayload() throws {
        let info = try #require(DeviceInfo(payload: [UInt8](hex: "00 01 04 06 62 01 04 06 5f 5f")!))
        #expect(info.leftBattery == 0x62)
        #expect(info.rightBattery == 0x5F)
        #expect(info.caseBattery == 0x5F)
    }
}
