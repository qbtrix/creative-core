// MaskBudgetTests.swift: the masks-mattes budgets (MM-9, quality rows "Masked
// composite cost" and "Marching ants per frame", and MM-9's feather row) on
// 24 MP (6000 x 4000): a layer composited through a feathered ellipse
// selection onto a backdrop takes at most 1.3 x the same composite unmasked;
// feathering the selection by radius 20 takes at most 250 ms; its contours
// at most 60 ms. Release, reported, as AffineBudgetTests: an optimized build
// gates on them (the Mac finisher runs them there); a debug build, which
// `scripts/ci` runs in its parallel pass, runs an eighth of each side once
// and only reports, so no wall-clock check can flake the gate, and still
// checks each result. Times are wall-clock medians of `runs`, each composite
// on its own untimed copy of the backdrop, printed as
// `budget <row>: <ms> ms (...)`.
import CoreRaster
import Testing

#if DEBUG
private let optimized = false
#else
private let optimized = true
#endif

/// Debug times one run: it only reports.
private let runs = optimized ? 5 : 1

private func milliseconds(_ d: Duration) -> Double {
    let ms = Double(d.components.seconds) * 1e3 + Double(d.components.attoseconds) / 1e15
    return (ms * 1000).rounded() / 1000
}

/// The median of `runs` timings of `body`, each after an untimed `free`.
private func median(free: () -> Void = {}, _ body: () throws -> Void) throws -> Duration {
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
@Suite(.serialized) struct MaskBudgetTests {
    /// 24 MP in an optimized build; debug runs an eighth of each side.
    static let (width, height) = optimized ? (6000, 4000) : (750, 500)

    /// A hard selection: the ellipse inscribed in the frame.
    static func selection() throws -> Mask {
        try Mask.ellipse(width: width, height: height, centerX: Double(width) / 2, centerY: Double(height) / 2,
                         radiusX: Double(width) / 2 - 1, radiusY: Double(height) / 2 - 1)
    }

    @Test func maskedCompositeCost() throws {
        let (w, h) = (Self.width, Self.height)
        let mask = try Self.selection().feathered(radius: 20)
        let layer = try PixelBuffer(width: w, height: h, fill: RGBA(r: 0.2, g: 0.5, b: 0.8, a: 0.9))
        let backdrop = try PixelBuffer(width: w, height: h, fill: RGBA(r: 1, g: 1, b: 1, a: 1))
        // Each run starts on its own copy: one untimed pixel write makes it.
        let corner = try backdrop.pixel(x: 0, y: 0)
        var out = backdrop
        let fresh = { out = backdrop; try? out.setPixel(x: 0, y: 0, corner) }
        let plain = try median(free: fresh) {
            try out.composite(layer, x: 0, y: 0, mode: .normal, opacity: 0.8)
        }
        let unmasked = out
        let masked = try median(free: fresh) {
            try out.composite(layer, x: 0, y: 0, mode: .normal, opacity: 0.8, mask: mask, maskX: 0, maskY: 0)
        }
        let ratio = milliseconds(masked) / max(milliseconds(plain), 1e-3)
        let note = optimized ? "budget 1.3" : "report only, debug; budget 1.3 in release"
        print("budget masked composite \(w)x\(h): \(milliseconds(masked)) ms vs unmasked \(milliseconds(plain)) ms, \(ratio) x (\(note))")
        if optimized { #expect(ratio <= 1.3, "masked \(masked) over 1.3 x unmasked \(plain)") }
        // Full coverage at the centre is the unmasked pixel; none at the corner leaves the backdrop.
        #expect(try out.pixel(x: w / 2, y: h / 2) == unmasked.pixel(x: w / 2, y: h / 2))
        #expect(try out.pixel(x: w - 1, y: h - 1) == backdrop.pixel(x: w - 1, y: h - 1))
    }

    @Test func featherFast() throws {
        let hard = try Self.selection()
        var soft = hard
        let time = try median { soft = try hard.feathered(radius: 20) }
        report("feather \(Self.width)x\(Self.height) radius 20", time, budget: .milliseconds(250))
        #expect(abs(soft.area - hard.area) <= 0.01 * hard.area)
        #expect(try soft.coverage(x: 0, y: Self.height / 2) > 0 && soft.coverage(x: 0, y: Self.height / 2) < 0.5)
    }

    @Test func contoursFast() throws {
        let mask = try Self.selection()
        var rings: [[Mask.Point]] = []
        let time = try median { rings = mask.contours() }
        report("contours \(Self.width)x\(Self.height) selection", time, budget: .milliseconds(60))
        #expect(rings.count == 1 && (rings.first?.count ?? 0) > Self.width + Self.height)
    }
}
