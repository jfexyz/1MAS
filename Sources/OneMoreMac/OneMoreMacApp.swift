import AppKit
import OneMoreBluetooth

/// A menu bar-only app (`LSUIElement` in its `Info.plist`): one status item, no windows.
@main
enum OneMoreMacApp {
    @MainActor static func main() {
        let connection = HeadphoneConnection()
        let menu = StatusMenu(connection: connection)
        connection.start()
        withExtendedLifetime(menu) {
            NSApplication.shared.run()
        }
    }
}
