// ColorAdjust.swift: vibrance, hue/saturation/lightness and per-range HSL on a
// PixelBuffer, the tone-pack contract slice (docs/blueprints/core/features/tone-pack.md).
// Working space: each op reads a pixel's hue and saturation as standard HSL
// on its straight sRGB-encoded values (CoreColor's `TransferCurve`), clamped
// to 0...1. `hueSaturation` and `hsl` also apply their shift there, then decode
// and premultiply; `vibrance` scales chroma about Rec. 709 luma on linear
// values. Alpha is never changed and an alpha-0 pixel passes through untouched.
// Parameters are checked before any pixel is touched and a non-finite one
// throws `RasterError.invalid`; neutral parameters return the input as is.
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import CoreColor

extension PixelBuffer {
    /// Saturation boost that moves low-saturation pixels most; `amount` in
    /// -100...100. A positive amount scales linear chroma about luma by
    /// 1 + amount/100 × (1 − s), with s the HSL saturation of the linear values
    /// it scales (on the encoded values a near-gamut colour would read as muted
    /// and jump to full saturation), halved for skin hues (15°–50°, read on the
    /// encoded hue a colour picker shows), and capped so
    /// no channel leaves 0...1 (or its own range when already outside);
    /// a negative amount desaturates every pixel evenly (−100 is grey at luma).
    /// Throws `RasterError.invalid` when `amount` is non-finite or outside its range.
    public func vibrance(_ amount: Float) throws -> PixelBuffer {
        try ColorMath.check("vibrance", amount, limit: 100)
        if amount == 0 { return self }
        let w = Histogram.luminanceWeights
        let a = Double(amount) / 100
        return try mappingStraight { p in
            let y = Double(w.r * p.r + w.g * p.g + w.b * p.b)
            let c = SIMD3(Double(p.r), Double(p.g), Double(p.b))
            let lo = c.min(), hi = c.max()
            var scale = 1 + a
            if a > 0 {
                let h = ColorMath.hsl(of: p).h
                let skin: Double = (15...50).contains(h) ? 0.5 : 1
                let s = hi > lo ? min(1, (hi - lo) / max(1 - abs(hi + lo - 1), .ulpOfOne)) : 0
                scale = 1 + a * (1 - s) * skin
                var cap = scale
                if lo < y { cap = min(cap, y / (y - lo)) }
                if hi > y { cap = min(cap, (max(1, hi) - y) / (hi - y)) }
                scale = max(1, cap)
            }
            let out = SIMD3(repeating: y) + (c - SIMD3(repeating: y)) * scale
            return RGBA(r: Float(out.x), g: Float(out.y), b: Float(out.z), a: p.a)
        }
    }

    /// Hue shift in degrees (-180...180), saturation and lightness in
    /// -100...100, as standard HSL on the encoded values: the hue rotates,
    /// saturation scales by 1 + saturation/100 (clamped to 0...1), and
    /// lightness blends toward white (positive) or black (negative).
    /// Throws `RasterError.invalid` when a value is non-finite or outside its range.
    public func hueSaturation(hue: Float, saturation: Float, lightness: Float) throws -> PixelBuffer {
        try ColorMath.check("hue", hue, limit: 180)
        try ColorMath.check("saturation", saturation, limit: 100)
        try ColorMath.check("lightness", lightness, limit: 100)
        if hue == 0, saturation == 0, lightness == 0 { return self }
        let shift = ColorMath.Shift(hue: Double(hue), saturation: Double(saturation), lightness: Double(lightness))
        return try mappingStraight { ColorMath.shifted($0, by: shift, from: ColorMath.hsl(of: $0)) }
    }

    /// An `HSLShift`'s `hue` is percent of a ±30° turn (100 = +30°), not
    /// degrees as in `hueSaturation`; its saturation and lightness are percent.
    /// Per-hue-range HSL shifts over eight ranges centred at 0, 30, 60, 120,
    /// 180, 240, 270 and 300 degrees. A pixel's weight per range is a raised
    /// cosine from the range's centre to each neighbouring centre, so the
    /// weights sum to 1; the shifts are summed by weight and applied as in
    /// `hueSaturation`. Out-of-range values are clamped to -100...100; a
    /// non-finite one throws `RasterError.invalid` naming its band. A grey
    /// pixel (no hue) and one whose summed shift is zero pass through untouched.
    public func hsl(_ adjustment: HSLAdjustment) throws -> PixelBuffer {
        let bands = [("reds", adjustment.reds), ("oranges", adjustment.oranges), ("yellows", adjustment.yellows),
                     ("greens", adjustment.greens), ("aquas", adjustment.aquas), ("blues", adjustment.blues),
                     ("purples", adjustment.purples), ("magentas", adjustment.magentas)]
        let shifts = try bands.map { band, r -> ColorMath.Shift in
            for (name, v) in [("hue", r.hue), ("saturation", r.saturation), ("lightness", r.lightness)] {
                guard v.isFinite else { throw RasterError.invalid("hsl \(band) \(name) \(v): must be finite") }
            }
            func clamped(_ v: Float) -> Double { Double(min(max(v, -100), 100)) }
            return ColorMath.Shift(hue: clamped(r.hue) * 0.3, saturation: clamped(r.saturation),
                                   lightness: clamped(r.lightness))
        }
        if shifts.allSatisfy(\.isZero) { return self }
        return try mappingStraight { p in
            let hsl = ColorMath.hsl(of: p)
            guard hsl.s > 0 else { return p }
            var sum = ColorMath.Shift(hue: 0, saturation: 0, lightness: 0)
            for (i, shift) in shifts.enumerated() {
                let w = ColorMath.rangeWeight(i, hue: hsl.h)
                sum = ColorMath.Shift(hue: sum.hue + w * shift.hue, saturation: sum.saturation + w * shift.saturation,
                                      lightness: sum.lightness + w * shift.lightness)
            }
            return sum.isZero ? p : ColorMath.shifted(p, by: sum, from: hsl)
        }
    }

    /// Maps each straight pixel with alpha above 0 through `transform`, which
    /// must keep alpha; alpha-0 pixels are copied as they are. Throws for a
    /// non-finite result, as `setPixel` does.
    func mappingStraight(_ transform: (RGBA) -> RGBA) throws -> PixelBuffer {
        var out = components
        let n = Self.channels
        for base in stride(from: 0, to: out.count, by: n) where out[base + 3] != 0 {
            let q = transform(RGBA(r: out[base], g: out[base + 1], b: out[base + 2], a: out[base + 3]).unpremultiplied())
                .premultiplied()
            guard q.isFinite else {
                throw RasterError.invalid("pixel \(q) at index \(base / n): components must be finite")
            }
            (out[base], out[base + 1], out[base + 2]) = (q.r, q.g, q.b)
        }
        return PixelBuffer(checkedWidth: width, height: height, storage: out)
    }
}

/// The HSL arithmetic the colour adjustments share, in Double.
enum ColorMath {
    /// A hue shift in degrees, saturation and lightness in -100...100.
    struct Shift {
        var hue, saturation, lightness: Double
        var isZero: Bool { hue == 0 && saturation == 0 && lightness == 0 }
    }

    /// Throws unless `value` is finite and within ±`limit`.
    static func check(_ name: String, _ value: Float, limit: Float) throws {
        guard value.isFinite, (-limit...limit).contains(value) else {
            throw RasterError.invalid("\(name) \(value): must be in \(-limit)...\(limit)")
        }
    }

    /// Standard HSL of a straight pixel's sRGB-encoded values, each clamped to
    /// 0...1: hue in degrees 0..<360 (0 for a grey), saturation and lightness 0...1.
    static func hsl(of p: RGBA) -> (h: Double, s: Double, l: Double) {
        func enc(_ v: Float) -> Double { min(max(TransferCurve.encode(Double(v)), 0), 1) }
        let c = SIMD3(enc(p.r), enc(p.g), enc(p.b))
        let hi = c.max(), lo = c.min(), l = (hi + lo) / 2, d = hi - lo
        guard d > 0 else { return (0, 0, l) }
        let sector = hi == c.x ? (c.y - c.z) / d : hi == c.y ? (c.z - c.x) / d + 2 : (c.x - c.y) / d + 4
        return ((sector * 60 + 360).truncatingRemainder(dividingBy: 360), d / (1 - abs(2 * l - 1)), l)
    }

    /// The straight pixel `p` (whose HSL is `hsl`) with `shift` applied:
    /// the hue rotates, saturation scales and clamps, lightness blends toward
    /// white or black; decoded back to linear, alpha kept.
    static func shifted(_ p: RGBA, by shift: Shift, from hsl: (h: Double, s: Double, l: Double)) -> RGBA {
        let h = (hsl.h + shift.hue + 360).truncatingRemainder(dividingBy: 360)
        let s = min(1, max(0, hsl.s * (1 + shift.saturation / 100)))
        let l = shift.lightness >= 0 ? hsl.l + (1 - hsl.l) * shift.lightness / 100 : hsl.l * (1 + shift.lightness / 100)
        let chroma = (1 - abs(2 * l - 1)) * s, hp = h / 60
        let x = chroma * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let rgb: SIMD3<Double> = switch Int(hp) % 6 {
        case 0: [chroma, x, 0]
        case 1: [x, chroma, 0]
        case 2: [0, chroma, x]
        case 3: [0, x, chroma]
        case 4: [x, 0, chroma]
        default: [chroma, 0, x]
        }
        let v = rgb + SIMD3(repeating: l - chroma / 2)
        func dec(_ e: Double) -> Float { Float(TransferCurve.decode(e)) }
        return RGBA(r: dec(v.x), g: dec(v.y), b: dec(v.z), a: p.a)
    }

    /// Range `i`'s distance in degrees to the previous centre and to the next
    /// (centres 0, 30, 60, 120, 180, 240, 270, 300, wrapping at 360).
    static let lower: [Double] = [60, 30, 30, 60, 60, 60, 30, 30]
    static let upper: [Double] = [30, 30, 60, 60, 60, 30, 30, 60]
    static let centres: [Double] = [0, 30, 60, 120, 180, 240, 270, 300]

    /// Range `i`'s weight at `hue`: 1 at its centre, falling by a raised cosine
    /// to 0 at each neighbouring centre, so neighbouring weights sum to 1.
    static func rangeWeight(_ i: Int, hue: Double) -> Double {
        guard centres.indices.contains(i) else { return 0 }
        let d = (hue - centres[i] + 540).truncatingRemainder(dividingBy: 360) - 180
        let span = d < 0 ? lower[i] : upper[i]
        guard abs(d) < span else { return 0 }
        return (1 + cos(Double.pi * d / span)) / 2
    }
}
