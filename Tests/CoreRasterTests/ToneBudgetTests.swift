// ToneBudgetTests.swift: the tone-pack budgets (TP-9, quality row "Slider
// drag on a preview"): on a 24 MP (6000 x 4000) cast photo each colour op
// takes at most 120 ms and the 33³ LUT at most 180 ms, and on a 2 MP
// (1600 x 1250) preview each colour op takes at most 12 ms. The packet's
// budgets are release, reported: every build runs every row and prints
// `budget <row>: <ms> ms (<mode>; budget <ms> ms)`; only a macOS release
// build (the Mac finisher) expects the budget, so neither Linux release nor
// the debug build `scripts/ci` runs can flake on a wall-clock check. Debug
// runs an eighth of each side: the loops are many times slower there, and
// the debug run proves the path works and that its result is right, not its
// speed. Times are wall-clock medians of `runs`, each run's earlier result
// freed before the clock starts. Linux release medians, 24 MP / 2 MP (ms),
// 4 cores at load ~9, after the banded loop (before it, in brackets):
// vibrance 2372 / 182 [3867 / 272], hueSaturation 3909 / 329 [6298 / 557],
// hsl 2068 / 172 [6302 / 583], blackAndWhite 3632 / 291 [8039 / 722],
// channelMixer 482 / 46 [621 / 44], colorBalance 3763 / 385 [6145 / 522],
// gradientMap 2679 / 291 [4828 / 482], lut 3430 / 322 [6115 / 526],
// posterize 2806 / 245 [4400 / 354], threshold 1592 / 141 [2458 / 178],
// invert 383 / 29 [442 / 43]. Every row still misses its budget on Linux:
// the per-pixel sRGB encode and decode (`pow`) dominates and must stay bit-exact.
import CoreRaster
import Testing

#if DEBUG
private let optimized = false
#else
private let optimized = true
#endif

private let runs = 3

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

/// The budgets gate only in a macOS release build, where the Mac finisher runs them.
#if os(macOS)
private let gated = optimized
#else
private let gated = false
#endif

/// Prints `row` always and, when `gated`, expects `time` within `budget`.
private func report(_ row: String, _ time: Duration, budget: Duration) {
    let mode = gated ? "gated" : optimized ? "report only, release off macOS" : "report only, debug"
    print("budget \(row): \(milliseconds(time)) ms (\(mode); budget \(milliseconds(budget)) ms)")
    if gated { #expect(time <= budget, "\(row): median \(time) over \(budget)") }
}

/// One timed colour op, by name, with its settings from the KJ-TP walk.
enum ToneBudgetOp: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case vibrance, hueSaturation, hsl, blackAndWhite, channelMixer, colorBalance
    case gradientMap, lut, posterize, threshold, invert

    var testDescription: String { rawValue }

    /// The warm look 33³, parsed once.
    static let warm33: ColorLUT? = try? CubeLUT.parse(ToneFixtures.warm33)

    /// The 24 MP budget: 180 ms for the 33³ LUT, 120 ms for every other op.
    var fullBudget: Duration { self == .lut ? .milliseconds(180) : .milliseconds(120) }

    func apply(_ b: PixelBuffer) throws -> PixelBuffer {
        switch self {
        case .vibrance: return try b.vibrance(30)
        case .hueSaturation: return try b.hueSaturation(hue: 20, saturation: -15, lightness: 10)
        case .hsl: return try b.hsl(HSLAdjustment(blues: HSLShift(saturation: -20)))
        case .blackAndWhite: return try b.blackAndWhite(GrayMix())
        case .channelMixer:
            return try b.channelMixer(ChannelMatrix(red: [0.8, 0.2, 0, 0], green: [0, 1, 0, 0.05],
                                                    blue: [0.1, 0, 0.9, 0], monochrome: false))
        case .colorBalance:
            return try b.colorBalance(ToneBalance(shadows: [10, 0, -10], midtones: .zero, highlights: [0, 0, 15],
                                                  preserveLuminosity: true))
        case .gradientMap:
            return try b.gradientMap([GradientMapStop(offset: 0, color: RGBA(r: 0.1, g: 0, b: 0.3, a: 1)),
                                      GradientMapStop(offset: 1, color: RGBA(r: 1, g: 0.9, b: 0.6, a: 1))])
        case .lut:
            guard let lut = Self.warm33 else { throw RasterError.invalid("warm look 33 did not parse") }
            return try b.applying(lut)
        case .posterize: return try b.posterized(levels: 4)
        case .threshold: return try b.thresholded(0.5)
        case .invert: return b.inverted()
        }
    }
}

/// Serialized, so no two large runs share cores or memory bandwidth.
@Suite(.serialized) struct ToneBudgetTests {
    /// Debug runs an eighth of each side.
    static let scale = optimized ? 1 : 8

    /// Times `op` on a `width` x `height` cast photo against `budget`, then
    /// checks the timed result: full size, and each op is per pixel, so a
    /// sampled pixel equals the op on that one pixel alone.
    static func run(_ op: ToneBudgetOp, _ size: String, width: Int, height: Int, budget: Duration) throws {
        let photo = try ToneFixtures.castPhoto(width: width, height: height).buffer
        let empty = try PixelBuffer(width: 1, height: 1)
        var out = empty
        let time = try median(free: { out = empty }) { out = try op.apply(photo) }
        report("\(op.rawValue) \(size) \(width)x\(height)", time, budget: budget)
        #expect(out.width == width && out.height == height)
        for (x, y) in [(0, 0), (width / 2, height / 2), (width - 1, height - 1), (width / 5, height * 4 / 5)] {
            let one = try op.apply(PixelBuffer(width: 1, height: 1, fill: try photo.pixel(x: x, y: y)))
            #expect(try out.pixel(x: x, y: y) == one.pixel(x: 0, y: 0), "\(op.rawValue) at (\(x), \(y))")
        }
    }

    @Test(arguments: ToneBudgetOp.allCases)
    func fullSize(_ op: ToneBudgetOp) throws {
        try Self.run(op, "24 MP", width: 6000 / Self.scale, height: 4000 / Self.scale, budget: op.fullBudget)
    }

    @Test(arguments: ToneBudgetOp.allCases)
    func preview(_ op: ToneBudgetOp) throws {
        try Self.run(op, "2 MP preview", width: 1600 / Self.scale, height: 1250 / Self.scale, budget: .milliseconds(12))
    }
}
