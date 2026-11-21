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
            Image(nsImage: MenuBarIcon.image(
                mode: connection.session?.state.listenMode,
                connected: connection.session != nil
            ))
        }
        .menuBarExtraStyle(.menu)
    }
}
