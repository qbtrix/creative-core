// ToneDabs.swift: dodge, burn and sponge, the per-dab tone ops (retouch-heal
// RH-5). A dab is a mask placed with its top-left corner at (x, y); only
// pixels under it change, and alpha never does. Each pixel's weight is the
// dab's coverage there times, for dodge and burn, its tonal range's weight at
// the pixel's Rec. 709 luma (on straight linear colour). Dodge scales linear
// colour by 1 + exposure × weight, burn by 1 − exposure × weight × 0.5 (a
// linear gain, one stop apart only at exposure 1), and
// sponge scales chroma about the luma by 1 + amount × coverage; colour is
// clamped to 0...1 straight. Scaling commutes with premultiplication, so the
// ops run on premultiplied values and never round-trip alpha.

/// The band of luma a dodge or burn dab acts on. Luma is Rec. 709 on
/// straight (unpremultiplied) linear colour; the bands overlap in smooth
/// ramps and their weights sum to 1 at every luma.
public enum TonalRange: Hashable, Sendable {
    /// Luma below 0.2 fully, fading out by 0.4.
    case shadows
    /// Luma 0.4...0.6 fully, fading to zero at 0.2 and 0.8; luma at or
    /// below 0.2, or at or above 0.8, is untouched.
    case midtones
    /// Luma above 0.8 fully, fading in from 0.6.
    case highlights

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
    /// the dab's coverage times the range's weight at the pixel's luma.
    /// `exposure` in 0...1 is a linear gain, not stops: dodge multiplies by
    /// `1 + exposure × weight`, burn by `1 − exposure × weight / 2`, so the
    /// two are one stop apart only at exposure 1 (dodge doubles, clamped;
    /// burn halves). 0 changes nothing, and so does a dab placed wholly off
    /// the buffer.
    /// Throws `RasterError.invalid` for an exposure outside 0...1 or NaN.
    public mutating func dodge(_ dab: Mask, x: Int, y: Int, range: TonalRange, exposure: Float) throws {
        try ColorMath.check("dodge exposure", exposure, in: 0...1)
        try toneDab(dab, x: x, y: y, range: range, gain: exposure)
    }

    /// Darkens the pixels under `dab` (its top-left at `x`, `y`) in `range`:
    /// linear colour is multiplied by `1 − exposure × weight × 0.5`, the
    /// weight being the dab's coverage times the range's weight at the
    /// pixel's luma. `exposure` in 0...1 is a linear gain, not stops: dodge
    /// multiplies by `1 + exposure × weight`, burn by `1 − exposure × weight /
    /// 2`, so the two are one stop apart only at exposure 1 (burn halves,
    /// dodge doubles); exposure 0.5 gives ×0.75 here and ×1.5 for dodge. 0
    /// changes nothing, and so does a dab placed wholly off the buffer.
    /// Throws `RasterError.invalid` for an exposure outside 0...1 or NaN.
    public mutating func burn(_ dab: Mask, x: Int, y: Int, range: TonalRange, exposure: Float) throws {
        try ColorMath.check("burn exposure", exposure, in: 0...1)
        try toneDab(dab, x: x, y: y, range: range, gain: -0.5 * exposure)
    }

    /// Raises (`amount` above 0) or lowers (`amount` below 0) the saturation
    /// of the pixels under `dab` (its top-left at `x`, `y`), weighted by the
    /// dab's coverage. `amount` is in -1...1; 0 changes nothing, and so does
    /// a dab placed wholly off the buffer. Chroma about the pixel's luma is
    /// scaled by `1 + amount × coverage`: -1 at full coverage is grey, +1
    /// doubles chroma. Colour clamps to 0...alpha, alpha is unchanged and
    /// transparent pixels are skipped. Throws `RasterError.invalid` for an
    /// amount outside -1...1 or NaN.
    public mutating func sponge(_ dab: Mask, x: Int, y: Int, amount: Float) throws {
        try ColorMath.check("sponge amount", amount, in: -1...1)
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

    /// The buffer columns and rows under `dab` placed with its top-left at
    /// (`x`, `y`), clipped to the buffer; nil when it lies wholly off it. The
    /// placement guard keeps every sum in range for any `x`, `y`, so dab
    /// cell (`column - x`, `row - y`) is in the mask for every pair in range.
    /// Every dab op (tone dabs, smudge) walks this one rectangle.
    func dabRect(_ dab: Mask, x: Int, y: Int) -> (columns: Range<Int>, rows: Range<Int>)? {
        guard x < width, y < height, x > -dab.width, y > -dab.height else { return nil }
        return (max(x, 0)..<min(x + dab.width, width), max(y, 0)..<min(y + dab.height, height))
    }

    /// Hands `edit` each premultiplied pixel under the dab with nonzero
    /// coverage and positive alpha, then stores its colour clamped to
    /// 0...alpha with alpha kept. Dab cells off the buffer are skipped.
    private mutating func eachDabPixel(_ dab: Mask, x: Int, y: Int,
                                       _ edit: (inout RGBA, Float) -> Void) throws {
        guard let area = dabRect(dab, x: x, y: y) else { return }
        for row in area.rows {
            for column in area.columns {
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
