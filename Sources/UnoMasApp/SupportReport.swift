import Foundation
import UnoMasKit

/// A link to a new issue on the device support form (`.github/ISSUE_TEMPLATE/device-support.yml`),
/// with every field the app can know already filled in, by the form's field IDs. What is left for
/// the person is whether the controls worked.
///
/// The raw replies matter most: they show what the headphones answered, which a person could not
/// easily find out, and what a model table entry needs. The Bluetooth address is left out, as it
/// identifies the person's device and adds nothing.
@MainActor
enum SupportReport {
    static let newIssue = "https://github.com/jfexyz/1MAS/issues/new"

    static func url(session: Session, bluetoothName: String) -> URL {
        let model = session.model
        let known = model.model == "Unknown" ? bluetoothName : model.model
        var components = URLComponents(string: newIssue)!
        components.queryItems = [
            URLQueryItem(name: "template", value: "device-support.yml"),
            URLQueryItem(name: "title", value: "Device support: \(known)"),
            URLQueryItem(name: "model", value: model.model == "Unknown" ? "" : model.model),
            URLQueryItem(name: "bluetooth-name", value: bluetoothName),
            URLQueryItem(name: "firmware", value: session.state.info?.firmware(for: model) ?? ""),
            URLQueryItem(name: "macos", value: ProcessInfo.processInfo.operatingSystemVersionString),
            URLQueryItem(name: "mac", value: macModel),
            URLQueryItem(name: "app-version", value: appVersion),
            URLQueryItem(name: "replies", value: replies(session)),
        ]
        // URLComponents leaves "+" as it is, which GitHub reads as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    /// One line per read: the command, its raw reply, and what the app made of it.
    static func replies(_ session: Session) -> String {
        let model = session.model
        let state = session.state
        func line(_ command: Command, _ name: String, has: Bool, meaning: (UInt8) -> String) -> String {
            let label = "\(String(format: "%04X", command.rawValue)) \(name)"
            guard has else { return "\(label): not read (not on this model)" }
            guard let payload = session.replies[command.rawValue] else { return "\(label): no answer" }
            return "\(label): \(payload.hex)" + (payload.first.map { " (\(meaning($0)))" } ?? "")
        }
        var lines = ["Model table: \(model.model == "Unknown" ? "not listed, generic profile" : "\(model.model), untested")"]
        if let payload = session.replies[Command.deviceInfo.rawValue] {
            let battery = state.info.map { "battery \($0.battery(for: model))%, firmware \($0.firmware(for: model))" }
            lines.append("004E device info: \(payload.hex)" + (battery.map { " (\($0))" } ?? ""))
        }
        lines.append(line(.getListenMode, "listen mode", has: !model.listenModes.isEmpty) {
            ListenMode(rawValue: $0)?.label ?? "unknown mode"
        })
        lines.append(line(.getEQPreset, "EQ preset", has: !model.eqPresets.isEmpty) { model.eqPresetName($0) })
        lines.append(line(.getDualDevice, "dual device", has: model.dualDevice) { $0 == 0 ? "off" : "on" })
        return lines.joined(separator: "\n")
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// The Mac's model identifier, such as "Mac15,12": Bluetooth hardware differs between Macs.
    static var macModel: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "" }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
