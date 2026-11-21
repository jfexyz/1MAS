import AppKit
import OneMoreBluetooth
import OneMoreKit
import ServiceManagement

/// The menu bar item and its menu, in AppKit rather than SwiftUI's `MenuBarExtra`: an `NSMenu`
/// item can carry an attributed title, which is how the battery value is right-aligned (a right
/// tab stop). SwiftUI's menu style can only do that with `.badge()`, which draws a pill.
///
/// The menu is rebuilt whenever the connection's observable state changes and each time it opens,
/// so it always shows the current state.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let connection: HeadphoneConnection
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var loginItemError: String?

    init(connection: HeadphoneConnection) {
        self.connection = connection
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        observe()
    }

    /// Updates the icon and menu now, and again on the next change to anything they read.
    private func observe() {
        withObservationTracking {
            updateIcon()
            rebuildMenu()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Launch at Login's state is not observable, so read it again on opening.
        rebuildMenu()
    }

    private func updateIcon() {
        statusItem.button?.image = MenuBarIcon.image(
            mode: connection.session?.state.listenMode,
            connected: connection.session != nil
        )
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        // Label-and-value rows. Their titles are set last, once the menu's width is known.
        var aligned: [(item: NSMenuItem, label: String, value: String)] = []
        func addAligned(_ label: String, _ value: String, item: NSMenuItem? = nil) {
            let item = item ?? info("")
            menu.addItem(item)
            aligned.append((item, label, value))
        }

        if let name = connection.status.name {
            menu.addItem(info(name))
            if let session = connection.session, let info = session.state.info {
                addAligned("Battery", "\(info.battery(for: session.model))%")
            } else {
                statusLines.forEach { menu.addItem(info($0)) }
            }
        } else {
            menu.addItem(info("No supported 1MORE headphones paired"))
        }

        if let session = connection.session {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Noise Control"))
            let current = session.state.listenMode
            for mode in session.model.listenModes {
                let item = NSMenuItem(title: mode.label, action: #selector(selectListenMode(_:)), keyEquivalent: "")
                item.target = self
                item.tag = Int(mode.rawValue)
                item.state = mode == current ? .on : .off
                menu.addItem(item)
            }

            if !session.model.eqPresets.isEmpty {
                menu.addItem(.separator())
                menu.addItem(.sectionHeader(title: "Equalizer"))
                let preset = session.state.eqPreset
                for id in session.model.eqPresets {
                    let item = NSMenuItem(title: EQPreset.name(id), action: #selector(selectEQPreset(_:)), keyEquivalent: "")
                    item.target = self
                    item.tag = Int(id)
                    item.state = id == preset ? .on : .off
                    menu.addItem(item)
                }
                // A preset set elsewhere that this menu does not offer, such as Custom from the
                // vendor app: shown checked so the menu still says what is active.
                if let preset, !session.model.eqPresets.contains(preset) {
                    let item = info(EQPreset.name(preset))
                    item.state = .on
                    menu.addItem(item)
                }
            }

            if session.model.dualDevice, let on = session.state.dualDevice {
                menu.addItem(.separator())
                menu.addItem(.sectionHeader(title: "Dual Device Connection"))
                let item = NSMenuItem(title: "", action: #selector(toggleDualDevice), keyEquivalent: "")
                item.target = self
                item.state = on ? .on : .off
                addAligned(on ? "Enabled" : "Disabled", on ? "Click to Disable" : "Click to Enable", item: item)
            }

            menu.addItem(.separator())
            addAligned("Model", session.model.model)
            if let firmware = session.state.info?.firmware(for: session.model) {
                addAligned("Firmware", firmware)
            }
        }

        if let error = connection.lastError ?? loginItemError {
            menu.addItem(info("Error: \(error)"))
        }

        menu.addItem(.separator())
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        // No ⌘Q: a key equivalent gives the whole menu a column on the right, which the
        // right-aligned values cannot reach into.
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))

        alignValues(aligned)
    }

    /// A row of information: shown greyed out, like SwiftUI's text rows in a menu.
    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// Titles each row `label`, then `value` right-aligned with a tab stop at the widest title in
    /// the menu, which is the menu's right edge as long as no item has a key equivalent. The value
    /// is drawn in the disabled items' grey; so is the label, unless the item can be clicked. A
    /// highlighted item is still drawn in white.
    private func alignValues(_ rows: [(item: NSMenuItem, label: String, value: String)]) {
        let font = NSFont.menuFont(ofSize: 0)
        func width(_ text: String) -> CGFloat {
            NSAttributedString(string: text, attributes: [.font: font]).size().width
        }
        // At least this much space between a label and its value, widening the menu if need be.
        let minimumGap: CGFloat = 50
        let location = (menu.items.map { width($0.title) } + rows.map { width($0.label) + minimumGap + width($0.value) }).max() ?? 0
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: location)]
        let grey: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style, .foregroundColor: NSColor.disabledControlTextColor]
        for row in rows {
            let title = NSMutableAttributedString(
                string: "\(row.label)\t",
                attributes: row.item.isEnabled ? [.font: font, .paragraphStyle: style] : grey
            )
            title.append(NSAttributedString(string: row.value, attributes: grey))
            row.item.attributedTitle = title
        }
    }

    /// The lines in place of the battery while there is none to show.
    private var statusLines: [String] {
        switch connection.status {
        case .noDevice, .connected: []
        case .disconnected: ["Not connected"]
        case .connecting: ["Connecting…"]
        case .failed(_, let failure): ["Unable to connect"] + Self.explanation(of: failure)
        }
    }

    /// The control channel allows only one client, so another one holding it (the vendor's phone
    /// app, or the `onemore` CLI) is the usual cause of a failure. The hint about that is shown
    /// for the failures it can explain, with the specific cause below it except for a timeout,
    /// which is how an occupied channel shows up.
    private static func explanation(of failure: HeadphoneConnection.ConnectFailure) -> [String] {
        let hint = "Another app might have control"
        return switch failure {
        case .timedOut: [hint]
        case .bluetoothError(let code): [hint, "Bluetooth error \(ioReturnName(code))"]
        case .noReply: [hint, "No reply from the headphones"]
        case .connectionDropped: ["Connection dropped"]
        case .noControlService: ["Control service not found"]
        case .other(let description): [description]
        }
    }

    @objc private func selectListenMode(_ sender: NSMenuItem) {
        guard let mode = ListenMode(rawValue: UInt8(sender.tag)) else { return }
        connection.setListenMode(mode)
    }

    @objc private func selectEQPreset(_ sender: NSMenuItem) {
        connection.setEQPreset(UInt8(sender.tag))
    }

    /// Asks first, since the headphones restart to apply the change.
    @objc private func toggleDualDevice() {
        guard let on = connection.session?.state.dualDevice else { return }
        let alert = NSAlert()
        alert.messageText = on ? "Disable Dual Device Connection?" : "Enable Dual Device Connection?"
        alert.informativeText = "Changing this setting restarts the headphones. Audio will stop playing, and you may need to resume it once they reconnect."
        // Named for the change, not "Restart", which could read as restarting the Mac.
        alert.addButton(withTitle: on ? "Disable" : "Enable")
        alert.addButton(withTitle: "Cancel")
        // A menu bar app is not frontmost, and the alert would open behind other windows.
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        connection.setDualDevice(!on)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        rebuildMenu()
    }
}

private extension HeadphoneConnection.Status {
    var name: String? {
        switch self {
        case .noDevice: nil
        case .disconnected(let name), .connecting(let name), .connected(let name), .failed(let name, _): name
        }
    }
}
