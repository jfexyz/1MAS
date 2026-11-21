/// Command IDs. A read and its write are separate IDs; the reply to either carries the same ID.
public enum Command: UInt16, CaseIterable, Sendable {
    /// Sent first after connecting, payload `01`. The vendor app waits for a `01` reply.
    case handshake = 0x004D
    /// Battery and firmware versions. See `DeviceInfo`.
    case deviceInfo = 0x004E
    case setListenMode = 0x005E
    case getListenMode = 0x005F
    case setEQPreset = 0x0069
    case getEQPreset = 0x006A
    case setCustomEQ = 0x0053
    case getCustomEQ = 0x0054
    case setConnectionMode = 0x006B
    case getConnectionMode = 0x006C
    case setDualDevice = 0x0076
    case getDualDevice = 0x0077

    /// Commands this code refuses to send whatever the caller asks: firmware update (`71`–`73`),
    /// "delete music" (`49`), and `4F`, which the vendor app never sends.
    public static let forbidden: Set<UInt16> = [0x0049, 0x004F, 0x0071, 0x0072, 0x0073]
}

/// Single-byte result of a write.
public enum WriteResult: UInt8, Sendable {
    case failure = 0
    case success = 1
    /// Earbuds only: both buds must be connected.
    case needsBothSides = 2
}

/// Listen (noise-control) mode values. Which ones a model accepts varies; the SonoFlow (HC905) is
/// documented with `off`, `strongANC`, and `transparent` only.
public enum ListenMode: UInt8, CaseIterable, Sendable {
    case off = 0
    case strongANC = 1
    case mildANC = 2
    case transparent = 3
    case windReduction = 4
    case passThrough = 5
    case voiceEnhancement = 6
    case adaptiveANC = 7
}

/// Payload of `deviceInfo` (`4E`), 10 bytes:
/// left-is-master, left version (3), left battery, right version (3), right battery, case battery.
/// Headphones report through the "left" fields. Battery is a percentage, 0 meaning absent.
public struct DeviceInfo: Equatable, Sendable {
    public var leftIsMaster: Bool
    public var leftVersion: String
    public var leftBattery: Int
    public var rightVersion: String
    public var rightBattery: Int
    public var caseBattery: Int

    public init?(payload: [UInt8]) {
        guard payload.count >= 10 else { return nil }
        func version(_ range: Range<Int>) -> String {
            payload[range].map { String($0, radix: 16) }.joined(separator: ".")
        }
        leftIsMaster = payload[0] != 0
        leftVersion = version(1..<4)
        leftBattery = Int(payload[4])
        rightVersion = version(5..<8)
        rightBattery = Int(payload[8])
        caseBattery = Int(payload[9])
    }
}

public extension Array where Element == UInt8 {
    /// Upper-case hex bytes separated by spaces, e.g. `11 01 00 5F`. Foundation-free on purpose.
    var hex: String {
        map { byte in
            let digits = String(byte, radix: 16, uppercase: true)
            return byte < 0x10 ? "0" + digits : digits
        }.joined(separator: " ")
    }

    init?(hex: String) {
        let digits = hex.filter { !$0.isWhitespace && $0 != ":" }
        guard digits.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            guard let byte = UInt8(digits[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = bytes
    }
}
