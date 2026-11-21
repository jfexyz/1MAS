/// What one 1MORE model supports. The vendor apps key this on the exact Bluetooth name, case
/// included, so do we.
///
/// `ModelTable.swift` lists every model 1MORE's apps know, generated from PairFree's data (taken
/// from 1MORE's product list and apps, not from hardware). Only the models marked `verified` have
/// been checked on real headphones; `docs/HARDWARE.md` has the evidence. Any other device whose name
/// starts with "1MORE" gets `generic`.
public struct ModelInfo: Equatable, Hashable, Sendable {
    public enum Kind: Sendable { case headphones, earbuds }

    public var bluetoothName: String
    /// Other names the same model goes by, such as an older firmware's.
    public var aliases: [String]
    /// The model number, or "Unknown" for `generic`.
    public var model: String
    public var kind: Kind
    /// In the vendor app's order. Empty for a model without noise control.
    public var listenModes: [ListenMode]
    /// In the vendor app's order. Empty for a model without presets.
    public var eqPresets: [EQPreset]
    /// Whether the model has dual device connection (`77` read, `76` write).
    public var dualDevice: Bool
    /// Checked on real headphones, as recorded in `docs/HARDWARE.md`.
    public var verified: Bool

    public init(
        bluetoothName: String, aliases: [String] = [], model: String, kind: Kind, listenModes: [ListenMode],
        eqPresets: [EQPreset], dualDevice: Bool, verified: Bool = false
    ) {
        self.bluetoothName = bluetoothName
        self.aliases = aliases
        self.model = model
        self.kind = kind
        self.listenModes = listenModes
        self.eqPresets = eqPresets
        self.dualDevice = dualDevice
        self.verified = verified
    }

    public static let sonoFlow = known.first { $0.model == "HC905" }!

    /// A 1MORE device missing from the table, probably a newer model. Noise control is offered as
    /// the modes nearly every model with it has, and only if the device answers the mode read.
    public static func generic(bluetoothName: String) -> ModelInfo {
        ModelInfo(
            bluetoothName: bluetoothName, model: "Unknown", kind: .headphones,
            listenModes: [.off, .strongANC, .transparent], eqPresets: [], dualDevice: false
        )
    }

    public static func matching(bluetoothName name: String) -> ModelInfo? {
        if let model = known.first(where: { $0.bluetoothName == name || $0.aliases.contains(name) }) {
            return model
        }
        guard name.uppercased().hasPrefix("1MORE"), !unreachableNames.contains(name) else { return nil }
        return generic(bluetoothName: name)
    }

    /// The preset's name on this model, which can differ from the usual one.
    public func eqPresetName(_ id: UInt8) -> String {
        eqPresets.first { $0.id == id }?.name ?? EQPreset.name(id)
    }
}

public extension ListenMode {
    var label: String {
        switch self {
        case .off: "Off"
        // Starts with "A" to match the menu bar icon's letter.
        case .strongANC: "Active Noise Cancellation"
        case .mildANC: "Mild Noise Cancellation"
        case .transparent: "Transparency"
        case .windReduction: "Wind Reduction"
        case .passThrough: "Pass-Through"
        case .voiceEnhancement: "Voice Enhancement"
        case .adaptiveANC: "Adaptive Noise Cancellation"
        }
    }
}

/// An EQ preset: the ID written with `69` and read with `6A`, and its name in the vendor app.
///
/// Most models pick from one list of IDs (PairFree's PROTOCOL.md, section 4), named here as the
/// vendor app names them for the SonoFlow (2026-11-21), in title case. 0x0B is "Loud" in PairFree's
/// decompilation and "Voice Enhancement" in another vendor app; the SonoFlow's app says "Vocal
/// Booster". Two older models use `classic` instead, a list of 22 sent by position.
public struct EQPreset: Equatable, Hashable, Sendable {
    public var id: UInt8
    public var name: String

    public init(id: UInt8, name: String) {
        self.id = id
        self.name = name
    }

    public static let studio = EQPreset(id: 0x00, name: "Studio")
    public static let bassReducer = EQPreset(id: 0x01, name: "Bass Reducer")
    public static let bassBooster = EQPreset(id: 0x02, name: "Bass Booster")
    public static let acoustic = EQPreset(id: 0x03, name: "Acoustic")
    /// The HQ60's name for 0x03.
    public static let soundByLuca = EQPreset(id: 0x03, name: "Sound by LUCA")
    public static let classical = EQPreset(id: 0x04, name: "Classical")
    public static let podcast = EQPreset(id: 0x05, name: "Podcast")
    public static let deep = EQPreset(id: 0x06, name: "Deep")
    public static let electronic = EQPreset(id: 0x07, name: "Electronic")
    public static let hipHop = EQPreset(id: 0x08, name: "Hip-Hop")
    public static let lounge = EQPreset(id: 0x09, name: "Lounge")
    public static let pop = EQPreset(id: 0x0A, name: "Pop")
    public static let vocalBooster = EQPreset(id: 0x0B, name: "Vocal Booster")
    public static let custom = EQPreset(id: 0x0C, name: "Custom")
    public static let thx = EQPreset(id: 0x0D, name: "THX")

    static let standard: [EQPreset] = [
        .studio, .bassReducer, .bassBooster, .acoustic, .classical, .podcast, .deep, .electronic,
        .hipHop, .lounge, .pop, .vocalBooster, .custom, .thx,
    ]

    /// The older list of the ComfoBuds Pro and ColorBuds 2, whose IDs are positions.
    public static let classic: [EQPreset] = [
        "Default", "Bass Reducer 1", "Bass Reducer 2", "Bass Booster 1", "Bass Booster 2", "Acoustic 1",
        "Acoustic 2", "Classical 1", "Classical 2", "Podcast", "Vocal Booster", "Deep 1", "Deep 2",
        "Electronic 1", "Electronic 2", "Hip-Hop 1", "Hip-Hop 2", "Lounge 1", "Lounge 2", "Pop 1", "Pop 2",
        "Loud",
    ].enumerated().map { EQPreset(id: UInt8($0.offset), name: $0.element) }

    /// The usual name of a preset ID, for when the model is not known.
    public static func name(_ id: UInt8) -> String {
        standard.first { $0.id == id }?.name ?? "Preset \(id)"
    }
}
