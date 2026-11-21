import Testing
@testable import OneMoreKit

/// Stands in for the Bluetooth channel: records what is sent and lets a test inject replies.
@MainActor
final class FakeTransport: ByteTransport {
    var onReceive: (([UInt8]) -> Void)?
    var onClose: (() -> Void)?
    var sent: [Frame] = []
    /// Answers each request as it is sent, like the device would. `nil` means stay silent.
    var responder: ((Frame) -> [[UInt8]])?

    func send(_ bytes: [UInt8]) throws {
        var parser = FrameParser()
        let frame = parser.feed(bytes)[0]
        sent.append(frame)
        guard let replies = responder?(frame) else { return }
        Task { @MainActor in for reply in replies { self.onReceive?(reply) } }
    }

    func close() { onClose?() }

    func inject(_ hex: String) { onReceive?([UInt8](hex: hex)!) }
}

/// A reply frame the way the SonoFlow builds it: same command and sequence, head `01 01`.
func reply(to request: Frame, _ payload: [UInt8]) -> [UInt8] {
    Frame(head: 0x01, variant: 0x01, command: request.command, sequence: request.sequence, payload: payload).bytes
}

@MainActor
struct SessionTests {
    @Test func refreshFillsStateFromRecordedSonoFlowReplies() async throws {
        let transport = FakeTransport()
        transport.responder = { request in
            switch request.command {
            case 0x4E: [reply(to: request, [UInt8](hex: "00 01 00 05 46 00 00 00 00 00")!)]
            case 0x5F: [reply(to: request, [0x01])]
            case 0x6A: [reply(to: request, [0x00])]
            case 0x77: [reply(to: request, [0x01])]
            default: []
            }
        }
        let session = Session(transport: transport, model: .sonoFlow)
        try await session.refresh()

        #expect(session.state.info?.battery(for: .sonoFlow) == 70)
        #expect(session.state.info?.firmware(for: .sonoFlow) == "1.0.5")
        #expect(session.state.listenMode == .strongANC)
        #expect(session.state.eqPreset == 0)
        #expect(session.state.dualDevice == true)
        #expect(transport.sent.map(\.sequence) == [0, 1, 2, 3])
    }

    @Test func setDualDeviceWritesWithoutReadingBack() async throws {
        let transport = FakeTransport()
        // The SonoFlow acknowledges, then restarts: nothing answers a read after that.
        transport.responder = { request in request.command == 0x76 ? [reply(to: request, [0x01])] : [] }
        let session = Session(transport: transport, model: .sonoFlow)

        try await session.setDualDevice(false)

        #expect(session.state.dualDevice == false)
        // As recorded from the SonoFlow, with the sequence numbers this session used.
        #expect(transport.sent.map(\.bytes.hex) == ["11 01 00 76 00 01 00 00 67 00"])
    }

    @Test func setListenModeHandlesThePushThatArrivesBeforeTheReply() async throws {
        let transport = FakeTransport()
        var mode: UInt8 = 1
        transport.responder = { request in
            switch request.command {
            case 0x5E:
                mode = request.payload[0]
                // Observed on hardware: an unsolicited 5F with the new mode, then the write's reply.
                let push = Frame(head: 0x01, variant: 0x01, command: 0x5F, sequence: 0x40, payload: [mode])
                return [push.bytes, reply(to: request, [0x01])]
            case 0x5F: return [reply(to: request, [mode])]
            default: return []
            }
        }
        let session = Session(transport: transport, model: .sonoFlow)
        var unsolicited: [Frame] = []
        session.unsolicitedObserver = { unsolicited.append($0) }

        try await session.setListenMode(.transparent)

        #expect(session.state.listenMode == .transparent)
        #expect(unsolicited.map(\.command) == [0x5F])
        #expect(transport.sent.map(\.command) == [0x5E, 0x5F])
    }

    @Test func setEQPresetWritesAndReadsBack() async throws {
        let transport = FakeTransport()
        var preset: UInt8 = 0
        transport.responder = { request in
            switch request.command {
            case 0x69:
                preset = request.payload[0]
                return [reply(to: request, [0x01])]
            case 0x6A: return [reply(to: request, [preset])]
            default: return []
            }
        }
        let session = Session(transport: transport, model: .sonoFlow)

        try await session.setEQPreset(0x0A)

        #expect(session.state.eqPreset == 0x0A)
        // As recorded from the SonoFlow, with the sequence numbers this session used.
        #expect(transport.sent.map(\.bytes.hex) == ["11 01 00 69 00 01 00 00 78 0A", "11 01 00 6A 00 00 00 01 7B"])
    }

    @Test func pushedModeChangeUpdatesState() {
        let transport = FakeTransport()
        let session = Session(transport: transport, model: .sonoFlow)
        transport.inject("01 01 00 5F 00 01 00 0C 52 03")
        #expect(session.state.listenMode == .transparent)
    }

    @Test func rejectsUnsupportedAndForbidden() async {
        let session = Session(transport: FakeTransport(), model: .sonoFlow)
        await #expect(throws: SessionError.unsupported(.windReduction)) {
            try await session.setListenMode(.windReduction)
        }
        await #expect(throws: SessionError.unsupportedEQPreset(0x0D)) {
            try await session.setEQPreset(0x0D)
        }
        await #expect(throws: SessionError.forbidden(command: 0x71)) {
            _ = try await session.request(0x71)
        }
    }

    @Test func rejectedWriteThrows() async {
        let transport = FakeTransport()
        transport.responder = { [reply(to: $0, [0x00])] }
        let session = Session(transport: transport, model: .sonoFlow)
        await #expect(throws: SessionError.rejected(command: 0x5E, result: [0x00])) {
            try await session.setListenMode(.off)
        }
    }

    @Test func silentDeviceTimesOut() async {
        let session = Session(transport: FakeTransport(), model: .sonoFlow)
        await #expect(throws: SessionError.timeout(command: 0x5F)) {
            _ = try await session.request(0x5F, timeout: .milliseconds(50))
        }
    }

    @Test func closingFailsOutstandingRequests() async {
        let transport = FakeTransport()
        let session = Session(transport: transport, model: .sonoFlow)
        var closed = false
        session.onClose = { closed = true }
        Task { @MainActor in transport.close() }
        await #expect(throws: SessionError.closed) {
            _ = try await session.request(0x5F, timeout: .seconds(5))
        }
        #expect(closed && session.isClosed)
    }
}
