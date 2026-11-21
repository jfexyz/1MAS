import OneMoreBluetooth
import OneMoreKit
import SwiftUI

@main
struct OneMoreMacApp: App {
    @State private var connection: HeadphoneConnection

    init() {
        let connection = HeadphoneConnection()
        connection.start()
        _connection = State(initialValue: connection)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(connection: connection)
        } label: {
            Image(systemName: menuBarSymbol)
        }
        .menuBarExtraStyle(.menu)
    }

    /// The icon follows the listen mode, so the current mode is visible without opening the menu.
    private var menuBarSymbol: String {
        switch connection.session?.state.listenMode {
        case .strongANC, .mildANC, .adaptiveANC, .windReduction: "headphones.circle.fill"
        case .transparent, .passThrough, .voiceEnhancement: "ear"
        case .off, nil: "headphones"
        }
    }
}
