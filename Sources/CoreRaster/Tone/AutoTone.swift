// AutoTone.swift: the levels and white balance auto tone suggests from a
// buffer's histogram, the tone-pack contract slice
// (docs/blueprints/core/features/tone-pack.md). A suggestion is applied as
// `whiteBalance(temperature:tint:)` then linear `levels` with output 0...1.
// Working space: straight linear values, clamped to 0...1, with Rec. 709 luma
// (`Histogram`). Fully transparent pixels are ignored. Degenerate input never
// throws or gives NaN: it suggests the neutral (identity) parts instead.
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

public struct AutoTone: Hashable, Sendable {
    public var inBlack: Float, inWhite: Float, gamma: Float, temperature: Float, tint: Float

    public init(inBlack: Float, inWhite: Float, gamma: Float, temperature: Float, tint: Float) {
        self.inBlack = inBlack
        self.inWhite = inWhite
        self.gamma = gamma
        self.temperature = temperature
        self.tint = tint
    }

    /// The share of pixels clipped at each end of the luma histogram.
    static let clip = 0.001
    /// The brightest share of pixels whose mean sets the white balance.
    static let brightShare = 0.05
    /// Levels whose black and white points are closer than this (a flat
    /// image) are left at identity.
    static let minimumSpan = 1.0 / 256
    static let bins = 4096

    /// Levels (black and white points at 0.1% and 99.9% of the luma
    /// histogram, a gamma that puts the median at 0.5) and a white balance
    /// that neutralises the mean of the brightest 5% of pixels with no channel
    /// at 0 or 1, mapped back through `whiteBalance`'s own gains. The levels
    /// are read after that white balance. Neutral parts: temperature and tint
    /// 0 when no pixel is in that bright set (an empty, black or blown-out
    /// buffer); levels 0, 1, 1 when every pixel is transparent or the black
    /// and white points are under 1/256 apart. Never throws for a buffer.
    public static func suggest(for buffer: PixelBuffer) throws -> AutoTone {
        let balance = try whiteBalance(for: buffer)
        let balanced = try buffer.whiteBalance(temperature: balance.temperature, tint: balance.tint)
        let luma = try Histogram(of: balanced, bins: bins).luminance
        var tone = AutoTone(inBlack: 0, inWhite: 1, gamma: 1, temperature: balance.temperature, tint: balance.tint)
        guard let black = quantile(luma, clip), let white = quantile(luma, 1 - clip),
              let median = quantile(luma, 0.5), white - black >= minimumSpan else { return tone }
        tone.inBlack = Float(black)
        tone.inWhite = Float(white)
        // Levels maps t = (median − black) / span to t^(1/gamma); 0.5 wants this gamma.
        let t = (median - black) / (white - black)
        if t > 0, t < 1 { tone.gamma = Float(min(max(log(t) / log(0.5), 0.1), 10)) }
        return tone
    }

    /// The temperature and tint whose `whiteBalance` gains make the bright
    /// set's mean grey: gains 2^(T/200), 2^(−M/200), 2^(−T/200) times one
    /// norm, so T = 100·log2(b/r) and M = 100·log2(g²/(r·b)), clamped to the
    /// slider range.
    static func whiteBalance(for buffer: PixelBuffer) throws -> (temperature: Float, tint: Float) {
        let luma = try Histogram(of: buffer, bins: bins).luminance
        guard let threshold = quantile(luma, 1 - brightShare) else { return (0, 0) }
        let c = buffer.components, w = Histogram.luminanceWeights
        var sum = SIMD3<Double>.zero, count = 0
        for i in stride(from: 0, to: c.count, by: PixelBuffer.channels) where c[i + 3] != 0 {
            let s = RGBA(r: c[i], g: c[i + 1], b: c[i + 2], a: c[i + 3]).unpremultiplied()
            let rgb = SIMD3<Double>(Double(s.r), Double(s.g), Double(s.b))
            guard rgb.min() > 0, rgb.max() < 1,
                  Double(w.r * s.r + w.g * s.g + w.b * s.b) >= threshold else { continue }
            sum += rgb
            count += 1
        }
        guard count > 0 else { return (0, 0) }
        let mean = sum / Double(count)
        let temperature = 100 * log2(mean.z / mean.x)
        let tint = 100 * log2(mean.y * mean.y / (mean.x * mean.z))
        return (Float(min(max(temperature, -100), 100)), Float(min(max(tint, -100), 100)))
    }

    /// The value below which share `p` of the counted values lie, in 0...1:
    /// the mean of that rank read from the bottom and from the top, each
    /// interpolated within its bin, so a symmetric histogram's median is its
    /// centre. Nil when nothing is counted.
    static func quantile(_ counts: [Int], _ p: Double) -> Double? {
        guard let low = rank(counts, p), let high = rank(counts.reversed(), 1 - p) else { return nil }
        return (low + 1 - high) / 2
    }

    /// The bin position, as a share of 0...1, where the running count from
    /// the first bin reaches share `p` of the total. Nil for an empty histogram.
    static func rank(_ counts: [Int], _ p: Double) -> Double? {
        let total = counts.reduce(0, +)
        guard total > 0 else { return nil }
        let target = p * Double(total)
        var below = 0.0
        for (k, n) in counts.enumerated() where n > 0 {
            if below + Double(n) >= target {
                return (Double(k) + (target - below) / Double(n)) / Double(counts.count)
            }
            below += Double(n)
        }
        return 1
    }
}
