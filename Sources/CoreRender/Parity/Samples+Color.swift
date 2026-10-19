// Samples+Color.swift: the parity samples and golden pack of `RenderOp.color` (tone-pack TP-8).
// One call per colour case of `ToneAdjustment`, vibrance through invert and the LUT, each away
// from its neutral value, run on the four 9x7 edge-case sources (random, alpha 0 with color left,
// subnormal alpha, opaque rows) the older families use, bit for bit; a sample is named
// `<case>-<source>`. The LUT is a 5³ warm look built in code, so no file is read. The
// `<case>-alpha-zero` bands are all zero in display bytes (alpha 0 writes 0, 0, 0, 0), so they
// prove nothing about colour; `CPUColorTests.alphaZeroKeepsStoredColor` proves the alpha-0 contract.
import CoreColor
import CoreRaster

/// The parity inputs of `RenderOp.color`, read by `ParityHarness.sampleSet(for:)` and `ParityPack.all`.
enum ColorSamples {
    /// Every sample, in golden band order: the cases in `ToneAdjustment` order, each on the four
    /// 9x7 sources `sampleSet(for:)` gives the older families (same seeds), in its order; throws
    /// as building a buffer may.
    static var all: [ParitySample] {
        get throws {
            let names = ["random", "alpha-zero", "alpha-subnormal", "opaque-rows"]
            let alphas: [Float?] = [nil, 0, 1e-45, nil]
            let sources = try names.indices.map {
                try ParityHarness.seeded(9, 7, seed: 0x9A21 + UInt64($0), alpha: alphas[$0], opaqueRows: $0 == 3)
            }
            return try calls().flatMap { name, adjustment in
                zip(names, sources).map {
                    ParitySample(name: "\(name)-\($0.0)", call: .adjusted(adjustment), source: $0.1, backdrop: nil)
                }
            }
        }
    }

    /// The colour goldens. The CPU must reproduce them exactly (`CPUGoldenTests`); another
    /// backend's result is compared with `.standard` (2 bytes, 1e-3 linear) through
    /// `ParityHarness.compare`.
    static let packs = [ParityPack(.color, tolerance: .standard)]

    /// One named, non-neutral call per colour case.
    private static func calls() throws -> [(String, ToneAdjustment)] {
        let shifts = HSLAdjustment(reds: HSLShift(hue: 30, saturation: -40, lightness: 10),
                                   greens: HSLShift(hue: -20, saturation: 30),
                                   blues: HSLShift(hue: -50, saturation: 60, lightness: -20))
        let mixer = ChannelMatrix(red: [0.8, 0.3, -0.1, 0.02], green: [0.1, 0.9, 0, 0],
                                  blue: [0, 0.2, 0.7, 0.05], monochrome: false)
        let balance = ToneBalance(shadows: [20, 0, -15], midtones: [-10, 15, 5], highlights: [0, -5, 25],
                                  preserveLuminosity: true)
        let stops = [GradientMapStop(offset: 0, color: RGBA(r: 0.05, g: 0.1, b: 0.35, a: 1)),
                     GradientMapStop(offset: 0.5, color: RGBA(r: 0.9, g: 0.45, b: 0.1, a: 1)),
                     GradientMapStop(offset: 1, color: RGBA(r: 1, g: 0.95, b: 0.7, a: 1))]
        return [
            ("vibrance", .vibrance(60)),
            ("hueSaturation", .hueSaturation(hue: 35, saturation: 25, lightness: -10)),
            ("hsl", .hsl(shifts)),
            ("blackAndWhite", .blackAndWhite(GrayMix(tint: RGBA(r: 1, g: 0.8, b: 0.6, a: 0.5)))),
            ("channelMixer", .channelMixer(mixer)),
            ("colorBalance", .colorBalance(balance)),
            ("gradientMap", .gradientMap(stops)),
            ("lut", .lut(try warmLUT())),
            ("posterize", .posterize(levels: 4)),
            ("threshold", .threshold(0.4)),
            ("invert", .invert),
        ]
    }

    /// A 5³ warm look, red index fastest: red lifted, green a touch, blue lowered, with a
    /// red-green cross term so the lookup interpolates between unequal lattice steps.
    private static func warmLUT() throws -> ColorLUT {
        let n = 5, step = 1 / Float(n - 1)
        let table = (0..<n * n * n).map { i -> SIMD3<Float> in
            let r = Float(i % n) * step, g = Float(i / n % n) * step, b = Float(i / (n * n)) * step
            return [0.08 + 0.92 * r, 0.03 + 0.85 * g + 0.1 * r * g, 0.9 * b]
        }
        return try ColorLUT(size: n, table: table)
    }
}
