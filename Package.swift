// swift-tools-version: 6.0
// creative-core: the pure-Swift engines behind the creative suite apps. Every
// target must build and test on macOS and Linux, so each depends on Foundation
// only. No UI frameworks here.
//   FlareCore   document model, commands, timeline, file format, export (Flare)
//   CoreColor   color spaces and conversions (shared by every app)
//   CoreRaster  pixel buffers, compositing and image operations (Photo, Library, Halo)
import PackageDescription

let package = Package(
    name: "FlareCore",
    // Apple-only floor; ignored on Linux. macOS 14 is what Swift Testing needs.
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FlareCore", targets: ["FlareCore"]),
        .library(name: "CoreColor", targets: ["CoreColor"]),
        .library(name: "CoreRaster", targets: ["CoreRaster"]),
    ],
    targets: [
        .target(name: "FlareCore"),
        .target(name: "CoreColor"),
        .target(name: "CoreRaster", dependencies: ["CoreColor"]),
        .testTarget(name: "FlareCoreTests", dependencies: ["FlareCore"]),
        .testTarget(name: "CoreColorTests", dependencies: ["CoreColor"]),
        .testTarget(name: "CoreRasterTests", dependencies: ["CoreRaster"]),
    ]
)
