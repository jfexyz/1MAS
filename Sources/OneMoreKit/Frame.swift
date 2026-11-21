/// One 1MORE protocol frame.
///
/// Wire layout, all multi-byte fields big-endian:
///
///     head(2) | command(2) | length(2) | sequence(2) | xor(1) | payload(length)
///
/// - `head` is `11 01` from the host to newer models (`11 00` to some older ones); replies start
///   with `01`.
/// - `xor` is the XOR of the eight header bytes before it. It does not cover the payload.
///
/// Sources: PairFree's `docs/1more/PROTOCOL.md` (decompiled vendor apps), aero-q32-console's
/// `docs/PROTOCOL.md` (wire captures), and Gadgetbridge's hard-coded SonoFlow packets, which all
/// agree on this layout.
public struct Frame: Equatable, Hashable, Sendable {
    public static let headerLength = 9

    public var head: UInt8
    public var variant: UInt8
    public var command: UInt16
    public var sequence: UInt16
    public var payload: [UInt8]
    /// The checksum byte as received. Always correct on frames this side builds.
    public var checksum: UInt8

    public init(head: UInt8, variant: UInt8, command: UInt16, sequence: UInt16, payload: [UInt8]) {
        self.head = head
        self.variant = variant
        self.command = command
        self.sequence = sequence
        self.payload = payload
        self.checksum = 0
        self.checksum = Self.xor(headerWithoutChecksum)
    }

    /// A host-to-device request, as newer models expect it.
    public static func request(_ command: UInt16, sequence: UInt16, payload: [UInt8] = []) -> Frame {
        Frame(head: 0x11, variant: 0x01, command: command, sequence: sequence, payload: payload)
    }

    public var isRequest: Bool { head == 0x11 }
    public var isResponse: Bool { head == 0x01 }
    public var checksumIsValid: Bool { checksum == Self.xor(headerWithoutChecksum) }

    public var bytes: [UInt8] { headerWithoutChecksum + [checksum] + payload }

    private var headerWithoutChecksum: [UInt8] {
        let length = UInt16(payload.count)
        return [
            head, variant,
            UInt8(command >> 8), UInt8(command & 0xFF),
            UInt8(length >> 8), UInt8(length & 0xFF),
            UInt8(sequence >> 8), UInt8(sequence & 0xFF),
        ]
    }

    static func xor(_ bytes: [UInt8]) -> UInt8 { bytes.reduce(0, ^) }
}

/// Splits a byte stream into frames. Replies can arrive several to a read, or split across reads.
///
/// The vendor app ignores the checksum on replies, so this does too, but keeps it on the frame for
/// inspection. Bytes that cannot start a frame are skipped, as are the unexplained 13-byte frames
/// starting `FE` that PairFree documents.
public struct FrameParser: Sendable {
    private var buffer: [UInt8] = []
    /// Bytes thrown away while resynchronising, for diagnostics.
    public private(set) var discarded: [UInt8] = []

    public init() {}

    public mutating func feed(_ bytes: some Sequence<UInt8>) -> [Frame] {
        buffer.append(contentsOf: bytes)
        var frames: [Frame] = []
        while let first = buffer.first {
            if first == 0xFE {
                guard buffer.count >= 13 else { break }
                discard(13)
                continue
            }
            guard first == 0x01 || first == 0x11 else {
                discard(1)
                continue
            }
            guard buffer.count >= Frame.headerLength else { break }
            let length = Int(buffer[4]) << 8 | Int(buffer[5])
            let total = Frame.headerLength + length
            guard buffer.count >= total else { break }
            var frame = Frame(
                head: buffer[0],
                variant: buffer[1],
                command: UInt16(buffer[2]) << 8 | UInt16(buffer[3]),
                sequence: UInt16(buffer[6]) << 8 | UInt16(buffer[7]),
                payload: Array(buffer[Frame.headerLength..<total])
            )
            frame.checksum = buffer[8]
            frames.append(frame)
            buffer.removeFirst(total)
        }
        return frames
    }

    private mutating func discard(_ count: Int) {
        discarded.append(contentsOf: buffer.prefix(count))
        buffer.removeFirst(count)
    }
}
