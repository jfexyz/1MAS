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
        var batteryRow: (label: String, value: String)?

        if let name = connection.status.name {
            let model = ModelInfo.matching(bluetoothName: name)?.model
            menu.addItem(info([name, model].compactMap { $0 }.joined(separator: " ")))
            if let session = connection.session, let info = session.state.info {
                batteryRow = ("Battery", "\(info.battery(for: session.model))%")
            } else if let status = statusLine {
                menu.addItem(info(status))
            }
        } else {
            menu.addItem(info("No supported 1MORE headphones paired"))
        }
        // Placed after the rows above; its title is set below, once the menu's width is known.
        let batteryItem = batteryRow.map { _ in info("") }
        if let batteryItem { menu.addItem(batteryItem) }

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
            if let firmware = session.state.info?.firmware(for: session.model) {
                menu.addItem(info("Firmware \(firmware)"))
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
        // right-aligned battery value cannot reach into.
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))

        if let batteryItem, let batteryRow {
            batteryItem.attributedTitle = rightAligned(batteryRow.label, batteryRow.value)
        }
    }

    /// A row of information: shown greyed out, like SwiftUI's text rows in a menu.
    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// `label`, then `value` ending at the right edge of the menu's widest other title, which is
    /// the menu's right edge as long as no item has a key equivalent.
    private func rightAligned(_ label: String, _ value: String) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        func width(_ text: String) -> CGFloat {
            NSAttributedString(string: text, attributes: [.font: font]).size().width
        }
        let widest = menu.items.map { width($0.title) }.max() ?? 0
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: max(widest, width("\(label)  \(value)")))]
        return NSAttributedString(string: "\(label)\t\(value)", attributes: [
            .font: font,
            .paragraphStyle: style,
            .foregroundColor: NSColor.disabledControlTextColor,
        ])
    }

    /// The second line while there is no battery to show.
    private var statusLine: String? {
        switch connection.status {
        case .noDevice, .connected: nil
        case .disconnected: "Not connected"
        case .connecting: "Connecting…"
        case .failed(_, let reason): "Can't connect: \(reason)"
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
