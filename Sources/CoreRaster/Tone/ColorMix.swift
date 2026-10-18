// ColorMix.swift: black and white, channel mixer and colour balance on a
// PixelBuffer, the tone-pack contract slice (docs/blueprints/core/features/tone-pack.md).
// Working space: `blackAndWhite` and `colorBalance` run on straight
// sRGB-encoded values (CoreColor's `TransferCurve`), clamped to 0...1, with
// Rec. 709 luma on those values; `channelMixer` runs on straight linear values.
// Alpha is never changed and an alpha-0 pixel passes through untouched
// (`mappingStraight`). Parameters are checked before any pixel is touched: a
// non-finite one throws `RasterError.invalid`, an out-of-range one is clamped
// to its type's range. Neutral parameters return the input as is.
import CoreColor

extension PixelBuffer {
    /// Gray from six hue-range weights (reds, yellows, greens, cyans, blues,
    /// magentas at hues 0, 60, ..., 300; percent, clamped to -200...300). On
    /// the encoded values gray = min + (max − min) × w, with w the two
    /// neighbouring ranges' weights interpolated linearly by hue, so a pure
    /// primary or secondary is its range's weight and a grey keeps its value.
    /// The tint, when set, is the W3C soft-light of the tint colour over the
    /// gray, mixed in by the tint's alpha.
    public func blackAndWhite(_ mix: GrayMix) throws -> PixelBuffer {
        let raw = [mix.reds, mix.yellows, mix.greens, mix.cyans, mix.blues, mix.magentas]
        try Self.checkFinite("blackAndWhite weight", raw)
        let weights = raw.map { Double(min(max($0, -200), 300)) / 100 }
        var tint: RGBA?
        if let t = mix.tint {
            try Self.checkFinite("blackAndWhite tint", [t.r, t.g, t.b, t.a])
            tint = RGBA(r: min(max(t.r, 0), 1), g: min(max(t.g, 0), 1), b: min(max(t.b, 0), 1), a: min(max(t.a, 0), 1))
        }
        return try mappingStraight { p in
            let c = Self.encoded(p)
            let lo = c.min(), hi = c.max(), hp = ColorMath.hsl(of: p).h / 60
            let i = Int(hp) % 6
            let f = hp - Double(Int(hp))
            let w = weights[i] * (1 - f) + weights[(i + 1) % 6] * f
            let gray = Float(min(max(lo + (hi - lo) * w, 0), 1))
            var out = SIMD3<Float>(repeating: gray)
            if let tint {
                let soft = BlendMode.softLight.blend(backdrop: RGBA(r: gray, g: gray, b: gray, a: 1), source: tint)
                out += (SIMD3(soft.r, soft.g, soft.b) - out) * tint.a
            }
            return Self.decoded(out, a: p.a)
        }
    }

    /// Each output channel as a weighted sum of the straight linear inputs
    /// plus a constant (weights clamped to -2...2, constant to -1...1), the
    /// result clamped to 0...1. `monochrome` writes the red row's sum to all
    /// three channels. The identity matrix returns the input as is.
    public func channelMixer(_ m: ChannelMatrix) throws -> PixelBuffer {
        func row(_ r: SIMD4<Float>) throws -> SIMD4<Float> {
            try Self.checkFinite("channelMixer", [r.x, r.y, r.z, r.w])
            return r.clamped(lowerBound: [-2, -2, -2, -1], upperBound: [2, 2, 2, 1])
        }
        let red = try row(m.red), green = try row(m.green), blue = try row(m.blue)
        if !m.monochrome, red == [1, 0, 0, 0], green == [0, 1, 0, 0], blue == [0, 0, 1, 0] { return self }
        return try mappingStraight { p in
            let v = SIMD4(p.r, p.g, p.b, 1)
            func sum(_ row: SIMD4<Float>) -> Float { min(max((row * v).sum(), 0), 1) }
            if m.monochrome {
                let gray = sum(red)
                return RGBA(r: gray, g: gray, b: gray, a: p.a)
            }
            return RGBA(r: sum(red), g: sum(green), b: sum(blue), a: p.a)
        }
    }

    /// Shifts per tonal zone on the encoded values. Each component is clamped
    /// to -100...100; zone weights over the input's luma L are
    /// shadows 1 − smoothstep(0, 0.33, L), highlights smoothstep(0.66, 1, L)
    /// and midtones the rest, so they sum to 1. A channel's summed shift d
    /// (100 in a zone of weight 1 is 0.5) moves it toward 1 by d × (1 − c)
    /// when positive and toward 0 by |d| × c when negative. With
    /// `preserveLuminosity` the result is scaled to the input's luma.
    public func colorBalance(_ b: ToneBalance) throws -> PixelBuffer {
        func zone(_ z: SIMD3<Float>) throws -> SIMD3<Float> {
            try Self.checkFinite("colorBalance", [z.x, z.y, z.z])
            return z.clamped(lowerBound: SIMD3(repeating: -100), upperBound: SIMD3(repeating: 100)) / 200
        }
        let shadow = try zone(b.shadows), mid = try zone(b.midtones), highlight = try zone(b.highlights)
        if shadow == .zero, mid == .zero, highlight == .zero { return self }
        let lw = Histogram.luminanceWeights, luma = SIMD3(lw.r, lw.g, lw.b)
        return try mappingStraight { p in
            let c = SIMD3<Float>(Self.encoded(p))
            let l = (c * luma).sum()
            let shadows = 1 - Self.smoothstep(0, 0.33, l)
            let highlights = Self.smoothstep(0.66, 1, l)
            let d = shadow * shadows + mid * (1 - shadows - highlights) + highlight * highlights
            var out = c + d * c.replacing(with: 1 - c, where: d .> 0)
            if b.preserveLuminosity {
                let lo = (out * luma).sum()
                out = lo > 0 ? out * (l / lo) : SIMD3(repeating: l)
            }
            return Self.decoded(out.clamped(lowerBound: .zero, upperBound: .one), a: p.a)
        }
    }

    /// Throws `RasterError.invalid` naming `name` unless every value is finite.
    private static func checkFinite(_ name: String, _ values: [Float]) throws {
        guard values.allSatisfy(\.isFinite) else { throw RasterError.invalid("\(name) \(values): must be finite") }
    }

    /// The straight pixel's sRGB-encoded rgb, each clamped to 0...1.
    private static func encoded(_ p: RGBA) -> SIMD3<Double> {
        SIMD3(TransferCurve.encode(Double(p.r)), TransferCurve.encode(Double(p.g)), TransferCurve.encode(Double(p.b)))
            .clamped(lowerBound: .zero, upperBound: .one)
    }

    /// Straight linear RGBA of encoded `c` at alpha `a`.
    private static func decoded(_ c: SIMD3<Float>, a: Float) -> RGBA {
        RGBA(r: Float(TransferCurve.decode(Double(c.x))), g: Float(TransferCurve.decode(Double(c.y))),
             b: Float(TransferCurve.decode(Double(c.z))), a: a)
    }
}
