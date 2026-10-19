// EffectBudgetTests.swift: the effects-engine budgets (FX-9): a layer style
// (drop shadow, outside stroke and outer glow, in that order) on a 2,000 x
// 2,000 (4 MP) layer takes at most 150 ms, and denoising a 24 MP (6,000 x
// 4,000) photo at most 1.5 s. The packet's budgets are release, reported: an
// optimized build gates on them (the Mac finisher runs them there,
// `Mac-Finish-Wanted: FX-z`), and a debug build, which is what `scripts/ci`
// runs in its parallel pass, only reports, so no wall-clock check can flake
// the gate. Debug runs once, at an eighth of each side: the loops are many times
// slower there, and the debug run proves the path works and that its result
// is right, not its speed. Times are wall-clock medians of `runs`, each run's
// earlier result freed before the clock starts, printed as
// `budget <row>: <ms> ms (budget <ms> ms)` or `(report only, debug)`.
import CoreRaster
import Testing

#if DEBUG
private let optimized = false
#else
private let optimized = true
#endif

/// Debug times one run: it only reports, and its loops are slow.
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
@Suite(.serialized) struct EffectBudgetTests {
    /// Debug runs an eighth of each side.
    static let scale = optimized ? 1 : 8
    static let photo = (width: 6000 / scale, height: 4000 / scale)
    static let layerSide = 2000 / scale

    /// A `side` x `side` layer: an opaque white square inset by an eighth of
    /// the side on transparency, so every style has an edge to work from.
    static func styleLayer(side: Int) throws -> PixelBuffer {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let inset = side / 8
        for y in inset..<(side - inset) {
            for x in inset..<(side - inset) {
                let o = (y * side + x) * 4
                for k in 0..<4 { bytes[o + k] = 255 }
            }
        }
        return try PixelBuffer(rgba8: bytes, width: side, height: side)
    }

    /// An opaque `width` x `height` photo: a left-to-right grey ramp with
    /// seeded per-channel noise of about 4/255.
    static func noisyPhoto(width: Int, height: Int) throws -> PixelBuffer {
        var rng = SplitMix64(seed: 0xDE_9015E)
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let o = (y * width + x) * 4, base = 32 + 192 * x / max(1, width - 1)
                for k in 0..<3 { bytes[o + k] = UInt8(clamping: base + Int(rng.next() % 9) - 4) }
            }
        }
        return try PixelBuffer(rgba8: bytes, width: width, height: height)
    }

    /// The packet's style stack, as direct CoreRaster calls.
    static func style(_ layer: PixelBuffer) throws -> PixelBuffer {
        try layer.shadowed(color: RGBA(r: 0, g: 0, b: 0, a: 0.5), dx: 8, dy: 8, blur: 12, inner: false)
            .stroked(color: RGBA(r: 0, g: 0, b: 1, a: 1), width: 4, position: .outside)
            .glowing(color: RGBA(r: 1, g: 0.9, b: 0.4, a: 1), radius: 16, intensity: 0.75, inner: false)
    }

    @Test func photoFitsTheDenoiseCap() {
        // denoisePhoto times a full 24 MP photo in release, so the cap must admit it.
        #expect(6000 * 4000 <= PixelBuffer.maxDenoisePixels)
    }

    @Test func styleStack() throws {
        let side = Self.layerSide
        let layer = try Self.styleLayer(side: side)
        let empty = try PixelBuffer(width: 1, height: 1)
        var styled = empty
        let time = try median(free: { styled = empty }) { styled = try Self.style(layer) }
        report("layer style (shadow + stroke + glow) \(side)x\(side)", time, budget: .milliseconds(150))
        // The timed stack kept the size and drew outside the square: the
        // stroke's blue sits just past its left edge, the shadow past its
        // bottom-right corner.
        let inset = side / 8
        #expect(styled.width == side && styled.height == side)
        let stroke = try styled.pixel(x: inset - 2, y: side / 2)
        #expect(stroke.b > 0.9 && stroke.a > 0.9, "\(stroke)")
        let shadow = try styled.pixel(x: side - inset + 2, y: side - inset + 6)
        #expect(shadow.a > 0.1, "\(shadow)")
    }

    @Test func denoisePhoto() throws {
        let (w, h) = Self.photo
        let photo = try Self.noisyPhoto(width: w, height: h)
        let empty = try PixelBuffer(width: 1, height: 1)
        var clean = empty
        let time = try median(free: { clean = empty }) { clean = try photo.denoised(strength: 0.5, detail: 0.5) }
        report("denoise \(w)x\(h) photo", time, budget: .milliseconds(1_500))
        // The timed denoise kept the size and smoothed a flat-ish patch in the middle.
        #expect(clean.width == w && clean.height == h)
        var before = 0.0, after = 0.0
        for x in (w / 2)..<(w / 2 + 16) {
            let p = try photo.pixel(x: x, y: h / 2), q = try photo.pixel(x: x + 1, y: h / 2)
            let s = try clean.pixel(x: x, y: h / 2), t = try clean.pixel(x: x + 1, y: h / 2)
            before += Double(abs(p.r - q.r)); after += Double(abs(s.r - t.r))
        }
        #expect(after < before, "neighbour differences \(after) not under \(before)")
    }
}
