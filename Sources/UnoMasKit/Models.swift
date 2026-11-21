/// What one 1MORE model supports. The vendor app keys this on the exact Bluetooth name, so do we.
///
/// Only models verified on hardware belong here; `docs/HARDWARE.md` has the evidence. Per-model
/// data for other models is in PairFree's `data/1more/devices.json`.
public struct ModelInfo: Equatable, Hashable, Sendable {
    public enum Kind: Sendable { case headphones, earbuds }

    public var bluetoothName: String
    public var model: String
    public var kind: Kind
    public var listenModes: [ListenMode]
    /// The EQ presets the model offers, by ID (`EQPreset.names`), in the vendor app's order.
    public var eqPresets: [UInt8]
    /// Whether the model has dual device connection (`77` read, `76` write).
    public var dualDevice: Bool

    public static let sonoFlow = ModelInfo(
        bluetoothName: "1MORE SonoFlow",
        model: "HC905",
        kind: .headphones,
        listenModes: [.off, .strongANC, .transparent],
        // Studio to Vocal Booster. Custom (0x0C) selects the custom curve, which is not editable
        // here yet.
        eqPresets: Array(0x00...0x0B),
        // PairFree's data says no, but firmware 1.0.5 has it and the vendor app shows it.
        dualDevice: true
    )

    public static let known: [ModelInfo] = [.sonoFlow]

    public static func matching(bluetoothName name: String) -> ModelInfo? {
        known.first { $0.bluetoothName == name }
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

/// EQ preset names by ID, as the vendor app lists them for the SonoFlow (2026-11-21), in title
/// case. 0x0B is "Loud" in PairFree's decompilation and "Voice Enhancement" in another vendor app;
/// if another model's app names it differently, this becomes per model.
public enum EQPreset {
    public static let names: [UInt8: String] = [
        0x00: "Studio", 0x01: "Bass Reducer", 0x02: "Bass Booster", 0x03: "Acoustic",
        0x04: "Classical", 0x05: "Podcast", 0x06: "Deep", 0x07: "Electronic", 0x08: "Hip-Hop",
        0x09: "Lounge", 0x0A: "Pop", 0x0B: "Vocal Booster", 0x0C: "Custom", 0x0D: "THX",
    ]

    public static func name(_ id: UInt8) -> String {
        names[id] ?? "Preset \(id)"
    }
}
