// swift-tools-version: 6.0
import Foundation
import PackageDescription

// The CLI embeds an Info.plist (for the Bluetooth usage description) via the linker, which needs
// an absolute path.
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

let package = Package(
    name: "1more-for-mac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OneMoreKit", targets: ["OneMoreKit"]),
        .library(name: "OneMoreBluetooth", targets: ["OneMoreBluetooth"]),
        .executable(name: "onemore", targets: ["onemore"]),
        .executable(name: "OneMoreMac", targets: ["OneMoreMac"]),
    ],
    targets: [
        // Pure protocol code: framing, commands, decoding, the session. No Bluetooth, fully
        // unit-testable.
        .target(name: "OneMoreKit"),
        // IOBluetooth: device lookup, the RFCOMM transport, and connection management.
        .target(
            name: "OneMoreBluetooth",
            dependencies: ["OneMoreKit"],
            linkerSettings: [.linkedFramework("IOBluetooth")]
        ),
        // Command-line probe and control tool.
        .executableTarget(
            name: "onemore",
            dependencies: ["OneMoreKit", "OneMoreBluetooth"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "\(packageRoot)/Sources/onemore/Info.plist",
                ]),
            ]
        ),
        // The menu bar app. `scripts/build-app.sh` wraps it in an app bundle with
        // `Support/OneMoreMac/Info.plist`.
        .executableTarget(
            name: "OneMoreMac",
            dependencies: ["OneMoreKit", "OneMoreBluetooth"]
        ),
        .testTarget(name: "OneMoreKitTests", dependencies: ["OneMoreKit"]),
    ]
)
