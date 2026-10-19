// AffineBudgetTests.swift: the affine-composite budgets (AC-8, quality rows
// "Commit a transform" and "Live transform drag"): a 12 MP (4000 x 3000)
// layer composited through a rotate-scale onto a 12 MP backdrop takes at
// most 140 ms with bilinear and 260 ms with Lanczos-3, and a 2 MP (1920 x
// 1080) preview layer through-composited onto a 2 MP preview at most 12 ms.
// The packet's budgets are release, reported: an optimized build gates on
// them (the Mac finisher runs them there), and a debug build, which is what
// `scripts/ci` runs in its parallel pass, only reports, so no wall-clock
// check can flake the gate. Debug also runs an eighth of each side, once: the
// loops are many times slower there, and the debug run proves the path works and
// that its result is right, not its speed. Times are wall-clock medians of
// `runs`, each run starting on its own copy of the backdrop, written once
// untimed, printed as `budget <row>: <ms> ms (budget <ms> ms)` or
// `(report only, debug)`.
import CoreRaster
import Testing
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

#if DEBUG
private let optimized = false
#else
private let optimized = true
#endif

/// Debug times one run: it only reports.
private let runs = optimized ? 3 : 1

private func milliseconds(_ d: Duration) -> String {
    let ms = Double(d.components.seconds) * 1e3 + Double(d.components.attoseconds) / 1e15
    return "\((ms * 1000).rounded() / 1000)"
}

/// The median of `runs` timings of `body`, each after an untimed `free`.
private func median(free: () -> Void, _ body: () throws -> Void) throws -> Duration {
    let clock = ContinuousClock()
    var wall: [Duration] = []
    for _ in 0..<runs {
        free()
        wall.append(try clock.measure(body))
    }
    return wall.sorted()[runs / 2]
}

/// Prints `row` and, in an optimized build, expects `time` within `budget`.
private func report(_ row: String, _ time: Duration, budget: Duration) {
    let suffix = optimized ? "budget \(milliseconds(budget)) ms" : "report only, debug; budget \(milliseconds(budget)) ms in release"
    print("budget \(row): \(milliseconds(time)) ms (\(suffix))")
    if optimized { #expect(time <= budget, "\(row): median \(time) over \(budget)") }
}

/// Serialized, so no two large runs share cores or memory bandwidth.
@Suite(.serialized) struct AffineBudgetTests {
    /// Debug runs an eighth of each side.
    static let scale = optimized ? 1 : 8

    /// Scale `s` and rotate `degrees` about the centre of a `width` x
    /// `height` layer, which stays where it was.
    static func rotateScale(width: Int, height: Int, scale s: Double, degrees: Double) -> AffineMatrix {
        let t = degrees * .pi / 180
        let (a, b, c, d) = (s * cos(t), s * sin(t), -s * sin(t), s * cos(t))
        let cx = Double(width) / 2, cy = Double(height) / 2
        return AffineMatrix(a: a, b: b, c: c, d: d, tx: cx - (a * cx + c * cy), ty: cy - (b * cx + d * cy))
    }

    /// The median time to composite `layer` through `m` onto a fresh copy of
    /// `backdrop`, and the last run's result.
    static func time(_ layer: PixelBuffer, through m: AffineMatrix, onto backdrop: PixelBuffer,
                     filter: ResampleFilter) throws -> (Duration, PixelBuffer) {
        let corner = try backdrop.pixel(x: 0, y: 0)
        var out = backdrop
        let time = try median(free: {
            out = backdrop
            try? out.setPixel(x: 0, y: 0, corner)
        }) {
            try out.composite(layer, through: m, mode: .normal, opacity: 1, filter: filter)
        }
        return (time, out)
    }

    /// The timed composite drew the layer at the centre and left the backdrop
    /// where the layer cannot reach: column 0, left of the turned layer's
    /// write box at both sizes, checked at mid-height (not the corner the
    /// untimed copy writes).
    static func checkPlaced(_ out: PixelBuffer, backdrop: PixelBuffer, m: AffineMatrix, layer: PixelBuffer,
                            filter: ResampleFilter) throws {
        let wide = try #require(m.writeBounds(of: layer.width, layer.height, filter: filter))
        #expect(wide.x > 0, "write box \(wide) reaches column 0")
        #expect(out != backdrop)
        let (mx, my) = (out.width / 2, out.height / 2)
        #expect(try out.pixel(x: mx, y: my) != backdrop.pixel(x: mx, y: my))
        #expect(try out.pixel(x: 0, y: my) == backdrop.pixel(x: 0, y: my))
    }

    @Test(arguments: [(ResampleFilter.bilinear, 140), (.lanczos3, 260)])
    func commit12MP(filter: ResampleFilter, budget: Int) throws {
        let (w, h) = (4000 / Self.scale, 3000 / Self.scale)
        let layer = try AffineFixtures.layer(seed: 0xAC8, width: w, height: h, border: 0, block: 64 / Self.scale)
        let backdrop = try PixelBuffer(width: w, height: h, fill: RGBA(r: 1, g: 1, b: 1, a: 1))
        let m = Self.rotateScale(width: w, height: h, scale: 0.8, degrees: 20)
        let (time, out) = try Self.time(layer, through: m, onto: backdrop, filter: filter)
        report("commit \(w)x\(h) rotate-scale onto \(w)x\(h), \(filter)", time, budget: .milliseconds(budget))
        try Self.checkPlaced(out, backdrop: backdrop, m: m, layer: layer, filter: filter)
    }

    @Test func previewDrag() throws {
        let (w, h) = (1920 / Self.scale, 1080 / Self.scale)
        let layer = try AffineFixtures.layer(seed: 0xAC9, width: w, height: h, border: 0, block: 32 / Self.scale)
        let backdrop = try AffineFixtures.layer(seed: 0xACA, width: w, height: h, border: 0, block: 48 / Self.scale)
        let m = Self.rotateScale(width: w, height: h, scale: 0.7, degrees: 12)
        let (time, out) = try Self.time(layer, through: m, onto: backdrop, filter: .bilinear)
        report("preview drag \(w)x\(h) through-composite, bilinear", time, budget: .milliseconds(12))
        try Self.checkPlaced(out, backdrop: backdrop, m: m, layer: layer, filter: .bilinear)
    }
}
