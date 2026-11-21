import OneMoreBluetooth
import OneMoreKit
import ServiceManagement
import SwiftUI

/// The menu bar menu. In `.menu` style, text rows render as disabled menu items and the inline
/// picker as a checkmarked section.
struct MenuContent: View {
    let connection: HeadphoneConnection
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    var body: some View {
        Text(headline)

        if let session = connection.session {
            Picker("Noise Control", selection: listenModeBinding(session)) {
                ForEach(session.model.listenModes, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.inline)

            Divider()
            if let preset = session.state.eqPreset {
                Text("EQ: \(EQPreset.name(preset))")
            }
            if let firmware = session.state.info?.firmware(for: session.model) {
                Text("Firmware \(firmware)")
            }
        }

        if let error = connection.lastError ?? loginItemError {
            Text("Error: \(error)")
        }

        Divider()
        Toggle("Launch at Login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
        Button("Quit") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var headline: String {
        switch connection.status {
        case .noDevice:
            "No supported 1MORE headphones paired"
        case .disconnected(let name):
            "\(name): not connected"
        case .connecting(let name):
            "Connecting to \(name)…"
        case .connected(let name):
            if let session = connection.session, let info = session.state.info {
                "\(name) — \(info.battery(for: session.model))%"
            } else {
                name
            }
        case .failed(let name, let reason):
            "Can't reach \(name): \(reason)"
        }
    }

    private func listenModeBinding(_ session: Session) -> Binding<ListenMode> {
        Binding(
            get: { session.state.listenMode ?? .off },
            set: { connection.setListenMode($0) }
        )
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
