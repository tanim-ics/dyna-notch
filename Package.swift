// swift-tools-version:5.9
// DynaNotch — Dynamic Island for macOS. See CLAUDE.md.
import PackageDescription

var products: [Product] = [
    .library(name: "DynaNotchCore", targets: ["DynaNotchCore"]),
]

var targets: [Target] = [
    // Pure, platform-independent logic. Builds and tests on macOS and Linux.
    .target(
        name: "DynaNotchCore",
        path: "Sources/DynaNotchCore"
    ),
    .testTarget(
        name: "DynaNotchCoreTests",
        dependencies: ["DynaNotchCore"],
        path: "Tests/DynaNotchCoreTests"
    ),
]

#if os(macOS)
products.append(.executable(name: "DynaNotch", targets: ["DynaNotch"]))
targets.append(
    .executableTarget(
        name: "DynaNotch",
        dependencies: ["DynaNotchCore"],
        path: "Sources/DynaNotch",
        linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("SwiftUI"),
            .linkedFramework("Combine"),
            .linkedFramework("CoreAudio"),
            .linkedFramework("AudioToolbox"),
            .linkedFramework("IOKit"),
            .linkedFramework("IOBluetooth"),
            .linkedFramework("EventKit"),
            .linkedFramework("ServiceManagement"),
            .linkedFramework("ApplicationServices"),
            .linkedFramework("CoreGraphics"),
            .linkedFramework("CoreMediaIO"),
            .linkedFramework("CoreLocation"),
            .linkedFramework("Carbon"),
            .linkedFramework("CoreBluetooth"),
            .linkedFramework("AVFoundation"),
        ]
    )
)
#endif

let package = Package(
    name: "DynaNotch",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets,
    swiftLanguageVersions: [.v5]
)
