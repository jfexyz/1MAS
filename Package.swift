// swift-tools-version: 6.0
import Foundation
import PackageDescription

// The CLI embeds an Info.plist (for the Bluetooth usage description) via the linker, which needs
// an absolute path.
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

let package = Package(
    name: "1more-mac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OneMoreKit", targets: ["OneMoreKit"]),
        .executable(name: "onemore", targets: ["onemore"]),
    ],
    targets: [
        // Pure protocol code: framing, commands, decoding. No Bluetooth, fully unit-testable.
        .target(name: "OneMoreKit"),
        // Command-line probe and control tool, talking RFCOMM through IOBluetooth.
        .executableTarget(
            name: "onemore",
            dependencies: ["OneMoreKit"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "\(packageRoot)/Sources/onemore/Info.plist",
                ]),
            ]
        ),
        .testTarget(name: "OneMoreKitTests", dependencies: ["OneMoreKit"]),
    ]
)
