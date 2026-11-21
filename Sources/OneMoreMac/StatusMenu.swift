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
        func addAligned(_ label: String, _ value: String) {
            let item = info("")
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

            menu.addItem(.separator())
            if let preset = session.state.eqPreset {
                menu.addItem(info("EQ: \(EQPreset.name(preset))"))
            }
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
    /// the menu, which is the menu's right edge as long as no item has a key equivalent.
    private func alignValues(_ rows: [(item: NSMenuItem, label: String, value: String)]) {
        let font = NSFont.menuFont(ofSize: 0)
        func width(_ text: String) -> CGFloat {
            NSAttributedString(string: text, attributes: [.font: font]).size().width
        }
        let location = (menu.items.map { width($0.title) } + rows.map { width("\($0.label)    \($0.value)") }).max() ?? 0
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: location)]
        for row in rows {
            row.item.attributedTitle = NSAttributedString(string: "\(row.label)\t\(row.value)", attributes: [
                .font: font,
                .paragraphStyle: style,
                .foregroundColor: NSColor.disabledControlTextColor,
            ])
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
