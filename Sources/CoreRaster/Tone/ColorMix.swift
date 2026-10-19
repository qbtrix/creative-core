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
    /// gray, mixed in by the tint's alpha. Out-of-range values are clamped;
    /// non-finite values throw `RasterError.invalid`.
    public func blackAndWhite(_ mix: GrayMix) throws -> PixelBuffer {
        let raw = [mix.reds, mix.yellows, mix.greens, mix.cyans, mix.blues, mix.magentas]
        for (name, w) in zip(["reds", "yellows", "greens", "cyans", "blues", "magentas"], raw) {
            try Self.checkFinite("blackAndWhite \(name)", [w])
        }
        let weights = raw.map { Double(min(max($0, -200), 300)) / 100 }
        let tint = try mix.tint.map { t in
            try Self.checkFinite("blackAndWhite tint", [t.r, t.g, t.b, t.a])
            return RGBA(r: min(max(t.r, 0), 1), g: min(max(t.g, 0), 1), b: min(max(t.b, 0), 1), a: min(max(t.a, 0), 1))
        }
        return try mappingStraight { p in
            let c = Self.encoded(p)
            let lo = c.min(), hi = c.max(), hp = ColorMath.hsl(encoded: c).h / 60
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
    /// Out-of-range values are clamped; non-finite values throw `RasterError.invalid`.
    public func channelMixer(_ m: ChannelMatrix) throws -> PixelBuffer {
        func row(_ name: String, _ r: SIMD4<Float>) throws -> SIMD4<Float> {
            try Self.checkFinite("channelMixer \(name)", [r.x, r.y, r.z, r.w])
            return r.clamped(lowerBound: [-2, -2, -2, -1], upperBound: [2, 2, 2, 1])
        }
        let red = try row("red", m.red), green = try row("green", m.green), blue = try row("blue", m.blue)
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
    /// `preserveLuminosity` the result is scaled to the input's luma L; where
    /// that scaling would push a channel above 1, the chroma is pulled toward
    /// the grey at L just far enough to fit, so L is kept exactly.
    /// Out-of-range values are clamped; non-finite values throw `RasterError.invalid`.
    public func colorBalance(_ b: ToneBalance) throws -> PixelBuffer {
        func zone(_ name: String, _ z: SIMD3<Float>) throws -> SIMD3<Float> {
            try Self.checkFinite("colorBalance \(name)", [z.x, z.y, z.z])
            return z.clamped(lowerBound: SIMD3(repeating: -100), upperBound: SIMD3(repeating: 100)) / 200
        }
        let shadow = try zone("shadows", b.shadows), mid = try zone("midtones", b.midtones)
        let highlight = try zone("highlights", b.highlights)
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
                let s = lo > 0 ? out * (l / lo) : SIMD3(repeating: l)
                // s and l are >= 0, so only a channel above 1 limits k.
                let k = s.max() > 1 ? (1 - l) / (s.max() - l) : 1
                out = l + (s - l) * k
            }
            return Self.decoded(out.clamped(lowerBound: .zero, upperBound: .one), a: p.a)
        }
    }

    /// Throws `RasterError.invalid` naming `name` unless every value is finite.
    static func checkFinite(_ name: String, _ values: [Float]) throws {
        guard values.allSatisfy(\.isFinite) else { throw RasterError.invalid("\(name) \(values): must be finite") }
    }

    /// The straight pixel's sRGB-encoded rgb, each clamped to 0...1.
    static func encoded(_ p: RGBA) -> SIMD3<Double> {
        SIMD3(TransferCurve.encode(Double(p.r)), TransferCurve.encode(Double(p.g)), TransferCurve.encode(Double(p.b)))
            .clamped(lowerBound: .zero, upperBound: .one)
    }

    /// Straight linear RGBA of encoded `c` at alpha `a`.
    static func decoded(_ c: SIMD3<Float>, a: Float) -> RGBA {
        RGBA(r: Float(TransferCurve.decode(Double(c.x))), g: Float(TransferCurve.decode(Double(c.y))),
             b: Float(TransferCurve.decode(Double(c.z))), a: a)
    }
}
