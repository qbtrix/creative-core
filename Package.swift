// swift-tools-version: 6.1
// creative-core: the pure-Swift engines behind the creative suite apps. Every
// target must build and test on macOS and Linux, so each depends on Foundation
// only, except CoreCatalog, which also uses GRDB (the one approved dependency),
// and CoreRenderMetal, the one place Metal is allowed: its files are wrapped
// whole in `#if canImport(Metal)`, so Linux builds it as an empty module.
// No UI frameworks here.
//   FlareCore    document model, commands, timeline, file format, export (Flare)
//   CoreColor    color spaces and conversions (shared by every app)
//   CoreRaster   pixel buffers, compositing and image operations (Photo, Library, Halo)
//   CoreAsset    the shared asset model every app imports and exports
//   CoreCatalog  photo and metadata catalog over SQLite, through GRDB (Library)
//   CoreRender   the RenderBackend contract, CPU backend and dispatcher (Linux-safe)
//   CoreRenderMetal  the Metal RenderBackend (macOS only; empty on Linux)
// GRDB is pinned exactly. 7.10.0 is the first release that links against
// Ubuntu's system SQLite (built without WAL snapshots), and it needs tools 6.1,
// so 6.1 is this package's floor. On Linux the build needs libsqlite3-dev.
import PackageDescription

let package = Package(
    name: "FlareCore",
    // Apple-only floor; ignored on Linux. macOS 14 is what Swift Testing needs.
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FlareCore", targets: ["FlareCore"]),
        .library(name: "CoreColor", targets: ["CoreColor"]),
        .library(name: "CoreRaster", targets: ["CoreRaster"]),
        .library(name: "CoreAsset", targets: ["CoreAsset"]),
        .library(name: "CoreCatalog", targets: ["CoreCatalog"]),
        .library(name: "CoreRender", targets: ["CoreRender"]),
        .library(name: "CoreRenderMetal", targets: ["CoreRenderMetal"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(name: "FlareCore"),
        .target(name: "CoreColor"),
        .target(name: "CoreRaster", dependencies: ["CoreColor"]),
        .target(name: "CoreAsset"),
        .target(name: "CoreCatalog", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .target(name: "CoreRender", dependencies: ["CoreRaster", "CoreColor"]),
        .target(name: "CoreRenderMetal", dependencies: ["CoreRender"]),
        .testTarget(name: "FlareCoreTests", dependencies: ["FlareCore"]),
        .testTarget(name: "CoreColorTests", dependencies: ["CoreColor"]),
        .testTarget(name: "CoreRasterTests", dependencies: ["CoreRaster"]),
        .testTarget(name: "CoreAssetTests", dependencies: ["CoreAsset"]),
        .testTarget(
            name: "CoreCatalogTests",
            dependencies: ["CoreCatalog", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "CoreRenderTests", dependencies: ["CoreRender"]),
        .testTarget(name: "CoreRenderMetalTests", dependencies: ["CoreRenderMetal"]),
    ]
)
