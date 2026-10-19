// ToneDabs.swift: dodge, burn and sponge, the per-dab tone ops (retouch-heal
// RH-5). A dab is a mask placed with its top-left corner at (x, y); only
// pixels under it change, and alpha never does. Each pixel's weight is the
// dab's coverage there times, for dodge and burn, its tonal range's weight at
// the pixel's Rec. 709 luma (on straight linear colour). Dodge scales linear
// colour by 1 + exposure × weight, burn by 1 − exposure × weight × 0.5, and
// sponge scales chroma about the luma by 1 + amount × coverage; colour is
// clamped to 0...1 straight. Scaling commutes with premultiplication, so the
// ops run on premultiplied values and never round-trip alpha.

/// The band of luma a dodge or burn dab acts on.
public enum TonalRange: Hashable, Sendable {
    case shadows, midtones, highlights

    /// How much a pixel at `luma` belongs to this range, in 0...1. Midtones
    /// is a smoothstep window: `smoothstep(0.2, 0.4, l) × (1 −
    /// smoothstep(0.6, 0.8, l))`, so 1 over 0.4...0.6 and exactly 0 at or
    /// below 0.2 and at or above 0.8 (a dodge leaves deep shadows and bright
    /// highlights alone). Shadows is `1 − smoothstep(0.2, 0.4, l)` and
    /// highlights `smoothstep(0.6, 0.8, l)`, its mirrors; the three sum to 1.
    func weight(luma l: Float) -> Float {
        switch self {
        case .shadows: return 1 - PixelBuffer.smoothstep(0.2, 0.4, l)
        case .midtones: return PixelBuffer.smoothstep(0.2, 0.4, l) * (1 - PixelBuffer.smoothstep(0.6, 0.8, l))
        case .highlights: return PixelBuffer.smoothstep(0.6, 0.8, l)
        }
    }
}

extension PixelBuffer {
    /// Lightens the pixels under `dab` (its top-left at `x`, `y`) in `range`:
    /// linear colour is multiplied by `1 + exposure × weight`, the weight being
    /// the dab's coverage times the range's weight at the pixel's luma. At
    /// full weight, exposure 1 doubles linear colour (one stop up, clamped);
    /// `burn` at the same exposure halves it. `exposure` is in 0...1; 0
    /// changes nothing, and so does a dab placed wholly off the buffer.
    /// Throws `RasterError.invalid` for an exposure outside 0...1 or NaN.
    public mutating func dodge(_ dab: Mask, x: Int, y: Int, range: TonalRange, exposure: Float) throws {
        try ColorMath.check("exposure", exposure, in: 0...1)
        try toneDab(dab, x: x, y: y, range: range, gain: exposure)
    }

    /// Darkens the pixels under `dab` (its top-left at `x`, `y`) in `range`:
    /// linear colour is multiplied by `1 − exposure × weight × 0.5`, the
    /// weight being the dab's coverage times the range's weight at the
    /// pixel's luma. At full weight, exposure 1 halves linear colour (one stop
    /// down), mirroring `dodge`, which doubles it. `exposure` is in 0...1; 0
    /// changes nothing, and so does a dab placed wholly off the buffer.
    /// Throws `RasterError.invalid` for an exposure outside 0...1 or NaN.
    public mutating func burn(_ dab: Mask, x: Int, y: Int, range: TonalRange, exposure: Float) throws {
        try ColorMath.check("exposure", exposure, in: 0...1)
        try toneDab(dab, x: x, y: y, range: range, gain: -0.5 * exposure)
    }

    /// Raises (`amount` above 0) or lowers (`amount` below 0) the saturation
    /// of the pixels under `dab` (its top-left at `x`, `y`), weighted by the
    /// dab's coverage. `amount` is in -1...1; 0 changes nothing, and so does
    /// a dab placed wholly off the buffer. Throws `RasterError.invalid` for an
    /// amount outside -1...1 or NaN.
    public mutating func sponge(_ dab: Mask, x: Int, y: Int, amount: Float) throws {
        try ColorMath.check("amount", amount, in: -1...1)
        guard amount != 0 else { return }
        try eachDabPixel(dab, x: x, y: y) { p, coverage in
            let luma = Self.luma(p)
            let k = 1 + amount * coverage
            p.r = luma + (p.r - luma) * k
            p.g = luma + (p.g - luma) * k
            p.b = luma + (p.b - luma) * k
        }
    }

    /// Scales colour by 1 + gain × coverage × range weight (gain negative
    /// for burn).
    private mutating func toneDab(_ dab: Mask, x: Int, y: Int, range: TonalRange, gain: Float) throws {
        guard gain != 0 else { return }
        try eachDabPixel(dab, x: x, y: y) { p, coverage in
            let factor = 1 + gain * coverage * range.weight(luma: Self.luma(p) / p.a)
            p.r *= factor
            p.g *= factor
            p.b *= factor
        }
    }

    /// Rec. 709 luma (`Histogram.luminanceWeights`) of a premultiplied pixel
    /// (premultiplied too).
    private static func luma(_ p: RGBA) -> Float {
        let w = Histogram.luminanceWeights
        return w.r * p.r + w.g * p.g + w.b * p.b
    }

    /// Hands `edit` each premultiplied pixel under the dab with nonzero
    /// coverage and positive alpha, then stores its colour clamped to
    /// 0...alpha with alpha kept. Dab cells off the buffer are skipped; the
    /// placement guards keep every sum below in range for any `x`, `y`.
    private mutating func eachDabPixel(_ dab: Mask, x: Int, y: Int,
                                       _ edit: (inout RGBA, Float) -> Void) throws {
        guard x < width, y < height, x > -dab.width, y > -dab.height else { return }
        let x0 = max(x, 0), x1 = min(x + dab.width, width)
        let y0 = max(y, 0), y1 = min(y + dab.height, height)
        for row in y0..<y1 {
            for column in x0..<x1 {
                let coverage = try dab.coverage(x: column - x, y: row - y)
                guard coverage > 0 else { continue }
                var p = try pixel(x: column, y: row)
                guard p.a > 0 else { continue }
                let alpha = p.a
                edit(&p, coverage)
                p.r = min(max(p.r, 0), alpha)
                p.g = min(max(p.g, 0), alpha)
                p.b = min(max(p.b, 0), alpha)
                p.a = alpha
                try setPixel(x: column, y: row, p)
            }
        }
    }
}
