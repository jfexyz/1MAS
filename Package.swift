// swift-tools-version: 6.0
import Foundation
import PackageDescription

// The CLI embeds an Info.plist (for the Bluetooth usage description) via the linker, which needs
// an absolute path.
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

let package = Package(
    name: "1MAS",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UnoMasKit", targets: ["UnoMasKit"]),
        .library(name: "UnoMasBluetooth", targets: ["UnoMasBluetooth"]),
        .executable(name: "unomas", targets: ["unomas"]),
        // Not "UnoMas": on a case-insensitive disk that would collide with the CLI's "unomas",
        // both as a source folder and as a binary in the build directory.
        .executable(name: "UnoMasApp", targets: ["UnoMasApp"]),
    ],
    targets: [
        // Pure protocol code: framing, commands, decoding, the session. No Bluetooth, fully
        // unit-testable.
        .target(name: "UnoMasKit"),
        // IOBluetooth: device lookup, the RFCOMM transport, and connection management.
        .target(
            name: "UnoMasBluetooth",
            dependencies: ["UnoMasKit"],
            linkerSettings: [.linkedFramework("IOBluetooth")]
        ),
        // Command-line probe and control tool.
        .executableTarget(
            name: "unomas",
            dependencies: ["UnoMasKit", "UnoMasBluetooth"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "\(packageRoot)/Sources/unomas/Info.plist",
                ]),
            ]
        ),
        // The menu bar app. `scripts/build-app.sh` wraps it in an app bundle with
        // `Support/UnoMasApp/Info.plist`.
        .executableTarget(
            name: "UnoMasApp",
            dependencies: ["UnoMasKit", "UnoMasBluetooth"]
        ),
        .testTarget(name: "UnoMasKitTests", dependencies: ["UnoMasKit"]),
    ]
)
