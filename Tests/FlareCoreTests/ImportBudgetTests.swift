// ImportBudgetTests.swift: the vector-import release budgets. A 2 MB SVG reads
// in at most 150 ms and a 5 MB Lottie file in at most 250 ms. The inputs are
// our own exports of seeded scenes, grown a layer of 50 shapes at a time until
// the file passes its size: shapes mix rectangles, rounded rectangles, ellipses
// and stars, half of them stroked, and each Lottie layer keys x, y, rotation,
// opacity and its first shape's fill at frames 0, 150 and 299, so the reader
// walks keyframes as well as paths. Debug builds skip the suite, as
// CodecBudgetTests and RenderBudgetTests do; SVGImportTests and
// LottieImportTests carry the debug checks. Times are wall-clock medians of
// `runs` after one untimed read, and each row prints
// `budget <row>: <ms> ms (budget <ms> ms; <bytes> bytes)`.
// Run: swift test -c release -Xswiftc -enable-testing --filter ImportBudgetTests
import FlareCore
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

#if DEBUG
private let optimized = false
#else
private let optimized = true
#endif

@Suite(.serialized, .enabled(if: optimized, "budgets hold for optimized builds only"))
struct ImportBudgetTests {
    static let svgBytes = 2 << 20
    static let lottieBytes = 5 << 20
    static let svgBudget: Duration = .milliseconds(150)
    static let lottieBudget: Duration = .milliseconds(250)
    static let runs = 5
    static let shapesPerLayer = 50

    /// A seeded scene of `count` layers of 50 shapes, keyed when `keyed`.
    static func scene(layers count: Int, keyed: Bool) throws -> Scene {
        var rng = SplitMix64(seed: 2026)
        var layers: [Layer] = []
        for i in 0..<count {
            var shapes: [Shape] = []
            for _ in 0..<shapesPerLayer { shapes.append(try StageBudgetTests.shape(&rng, size: 500)) }
            var layer = Layer(id: "L\(i)", name: "Layer \(i)", shapes: shapes)
            if keyed {
                for name in ["x", "y", "rotation", "opacity"] {
                    layer.tracks[name] = [0, 150, 299].map {
                        Keyframe(frame: $0, value: Double.random(in: 0...1, using: &rng) * (name == "opacity" ? 1 : 300), easing: .easeInOut)
                    }
                }
                layer.colorTracks[Layer.colorTrackKey(fillOf: 0)] = [0, 150, 299].map {
                    ColorKeyframe(frame: $0, value: Color(r: Double.random(in: 0...1, using: &rng), g: 0.4, b: 0.6), easing: .easeInOut)
                }
            }
            layers.append(layer)
        }
        return Scene(id: "budget", name: "Budget", fps: 24, durationFrames: 300, layers: layers)
    }

    /// `export` of the smallest seeded scene at least `bytes` long.
    static func grown(to bytes: Int, keyed: Bool, _ export: (Scene) throws -> Data) throws -> Data {
        let one = try export(try scene(layers: 1, keyed: keyed)).count
        var count = max(1, bytes / max(one, 1))
        var data = try export(try scene(layers: count, keyed: keyed))
        while data.count < bytes {
            count += 1
            data = try export(try scene(layers: count, keyed: keyed))
        }
        return data
    }

    static func milliseconds(_ d: Duration) -> String {
        let ms = Double(d.components.seconds) * 1e3 + Double(d.components.attoseconds) / 1e15
        return "\((ms * 1000).rounded() / 1000)"
    }

    /// Reads `data` once untimed, then gates the median of `runs` reads.
    static func check(_ row: String, _ data: Data, budget: Duration, _ read: (Data) throws -> Int) throws {
        let layers = try read(data)
        #expect(layers > 0)
        var failure: (any Error)?
        let median = StageBudgetTests.median(runs: runs) { _ in
            do { _ = try read(data) } catch { failure = error }
        }
        if let failure { throw failure }
        print("budget \(row): \(milliseconds(median)) ms (budget \(milliseconds(budget)) ms; \(data.count) bytes, \(layers) layers)")
        #expect(median <= budget, "\(row): median \(median) over \(budget)")
    }

    @Test func bigSVG() throws {
        let data = try Self.grown(to: Self.svgBytes, keyed: false) { Data(try SVGExporter.export(scene: $0, frame: 0).utf8) }
        #expect(data.count >= Self.svgBytes)
        try Self.check("import svg 2 MB", data, budget: Self.svgBudget) { try SVGImport.scene(from: $0, name: "budget").0.layers.count }
    }

    @Test func bigLottie() throws {
        let data = try Self.grown(to: Self.lottieBytes, keyed: true) { try LottieExporter.export(scene: $0) }
        #expect(data.count >= Self.lottieBytes)
        try Self.check("import lottie 5 MB", data, budget: Self.lottieBudget) { try LottieImport.document(from: $0).0.scenes.first?.layers.count ?? 0 }
    }
}
