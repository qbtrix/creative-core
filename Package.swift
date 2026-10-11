// swift-tools-version: 6.0
// FlareCore: the pure-Swift engine behind Flare (document model, commands,
// timeline, easing, file format). It must build and test on macOS and Linux,
// so the library depends on Foundation only. No UI frameworks here.
import PackageDescription

let package = Package(
    name: "FlareCore",
    // Apple-only floor; ignored on Linux. macOS 14 is what Swift Testing needs.
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FlareCore", targets: ["FlareCore"]),
    ],
    targets: [
        .target(name: "FlareCore"),
        .testTarget(name: "FlareCoreTests", dependencies: ["FlareCore"]),
    ]
)
