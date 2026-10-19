// AlphaEffects+Light.swift: outer and inner glow and drop and inner shadow,
// from the layer's blurred alpha. Outer: the layer's alpha, blurred, offset by
// (dx, dy) (+y is down), times the premultiplied colour and the intensity,
// composited under the layer. Inner: the inverted alpha (1 - a), blurred and
// offset the same way, clipped by the layer's alpha, composited over it. A
// glow is a shadow with no offset. The blur is FX-3's `boxBlurred(radius:
// reach / 3)`: three box passes of radius r = reach / 3 reach `reach` pixels
// and approach a Gaussian of sigma sqrt(r (r + 1)), about reach / 3, at a cost
// that does not grow with the reach. It runs on a mask padded with the
// outside value (0, or 1 for inner), so past the buffer reads as transparent.
// Invariants: colour and offsets finite, radius and blur finite and in
// 0...1,000, intensity finite and in 0...1 (0 is identity), every output
// component finite.

extension PixelBuffer {
    /// The widest glow radius or shadow blur, in pixels.
    static let maxLightReach = 1_000.0

    /// This buffer with a glow of premultiplied `color` reaching `radius`
    /// pixels (about a Gaussian of sigma `radius` / 3) at `intensity`: outside and under
    /// the layer, or inside it from its edges when `inner`. Intensity 0
    /// returns the buffer unchanged. Throws `RasterError.invalid` for a colour
    /// that is not finite, a radius not finite or not in 0...1,000, an
    /// intensity not finite or not in 0...1, a buffer too large to pad for
    /// the effect (its padded work copy passes `maxWorkPixels`), or a result that
    /// overflows.
    public func glowing(color: RGBA, radius: Double, intensity: Double, inner: Bool) throws -> PixelBuffer {
        guard intensity.isFinite, intensity >= 0, intensity <= 1 else {
            throw RasterError.invalid("glow intensity \(intensity): must be finite and in 0...1")
        }
        return try lit(color: color, dx: 0, dy: 0, reach: radius, scale: intensity, inner: inner,
                       effect: "glow", reachName: "radius")
    }

    /// This buffer with a shadow of premultiplied `color` (its alpha is the
    /// opacity) offset by (`dx`, `dy`) pixels, +y down, blurred by `blur`
    /// pixels (about a Gaussian of sigma `blur` / 3): a drop shadow under the layer, or
    /// an inner shadow over it, clipped to its alpha, when `inner`. Throws
    /// `RasterError.invalid` for a colour or offset that is not finite, a blur
    /// not finite or not in 0...1,000, a buffer too large to pad for the
    /// effect (its copy padded for the blur and offset passes `maxWorkPixels`),
    /// or a result that overflows.
    public func shadowed(color: RGBA, dx: Double, dy: Double, blur: Double, inner: Bool) throws -> PixelBuffer {
        guard dx.isFinite, dy.isFinite else {
            throw RasterError.invalid("shadow offset (\(dx), \(dy)): dx and dy must be finite")
        }
        return try lit(color: color, dx: dx, dy: dy, reach: blur, scale: 1, inner: inner,
                       effect: "shadow", reachName: "blur")
    }

    /// The shared body: the (inverted when `inner`) alpha blurred over
    /// `reach` pixels, read at an offset of (`dx`, `dy`), scaled by `scale`,
    /// tinted with `color` and composited under (outer) or over (inner).
    private func lit(color: RGBA, dx: Double, dy: Double, reach: Double, scale: Double, inner: Bool,
                     effect: String, reachName: String) throws -> PixelBuffer {
        guard color.isFinite else { throw RasterError.invalid("\(effect) color \(color): must be finite") }
        guard reach.isFinite, reach >= 0, reach <= Self.maxLightReach else {
            throw RasterError.invalid("\(effect) \(reachName) \(reach): must be finite and in 0...\(Int(Self.maxLightReach))")
        }
        guard scale > 0 else { return self }
        let work = Self.lightWork(effect: effect, reachName: reachName, reach: reach, dx: dx, dy: dy)
        let mask = try blurredAlpha(reach: reach, inner: inner, pad: work.pad, cause: work.cause, remedy: work.remedy)
        let src = components, c = Self.channels
        var out = src
        let paint = [color.r, color.g, color.b, color.a]
        for y in 0..<height {
            for x in 0..<width {
                let o = (y * width + x) * c, layerAlpha = src[o + 3]
                var cover = Float(mask.sample(Double(x) - dx, Double(y) - dy) * scale)
                if inner { cover *= layerAlpha }
                guard cover > 0 else { continue }
                if inner {
                    let lightAlpha = paint[3] * cover
                    for k in 0..<c { out[o + k] = paint[k] * cover + src[o + k] * (1 - lightAlpha) }
                } else {
                    for k in 0..<c { out[o + k] = src[o + k] + paint[k] * cover * (1 - layerAlpha) }
                }
                guard (o..<(o + c)).allSatisfy({ out[$0].isFinite }) else {
                    throw RasterError.invalid("\(effect) of color \(color): result overflows")
                }
            }
        }
        return PixelBuffer(checkedWidth: width, height: height, storage: out)
    }

    /// The padding a side of a glow or shadow's work buffer, and the words
    /// its too-large error uses (see `paddedWorkSize`). Two pixels make the
    /// edge-extending blur read the outside value past the buffer; more lets
    /// an offset (the larger of |`dx`|, |`dy`|) pull in the blur that spills
    /// past the edge, up to the blur's reach + 3 (beyond it the mask is the
    /// outside value). The offset is compared as a Double, so it never
    /// overflows Int. The error names only what sets the padding: nothing but
    /// the buffer for a glow (its padding is fixed), the offset alone when it
    /// is within the reach + 3, else the reach and the offset.
    static func lightWork(effect: String, reachName: String, reach: Double, dx: Double,
                          dy: Double) -> (pad: Int, cause: String, remedy: String?) {
        let offset = max(abs(dx), abs(dy))
        let pad = Int(min(offset, reach + 3).rounded(.up)) + 2
        guard offset > 0 else { return (pad, effect, nil) }
        let at = " at offset (\(dx), \(dy))"
        guard reach + 3 < offset else { return (pad, effect + at, "offset") }
        return (pad, "\(effect) \(reachName) \(reach)\(at)", "\(reachName), the offset")
    }

    /// The layer's alpha (or 1 - alpha when `inner`) clamped to 0...1,
    /// padded by `pad` pixels with its outside value and box blurred three
    /// times by `reach` / 3 (see `lightWork`). `cause` and `remedy` name the
    /// effect in the error when the padded copy is too large.
    private func blurredAlpha(reach: Double, inner: Bool, pad: Int, cause: String,
                              remedy: String?) throws -> LightMask {
        let (pw, ph) = try Self.paddedWorkSize(width: width, height: height, pad: pad, cause: cause, remedy: remedy)
        let outside: Float = inner ? 1 : 0, c = Self.channels, src = components
        var padded = [Float](repeating: outside, count: pw * ph * c)
        for y in 0..<height {
            for x in 0..<width {
                let a = min(max(src[(y * width + x) * c + 3], 0), 1)
                padded[((y + pad) * pw + x + pad) * c + 3] = inner ? 1 - a : a
            }
        }
        let blurred = try PixelBuffer(checkedWidth: pw, height: ph, storage: padded).boxBlurred(radius: reach / 3)
        let data = blurred.components
        return LightMask(values: (0..<(pw * ph)).map { Double(data[$0 * c + 3]) }, width: pw, height: ph,
                         pad: pad, outside: Double(outside))
    }
}

/// A blurred, padded alpha mask read bilinearly in the layer's pixel
/// coordinates; anything past the padding reads as `outside`.
private struct LightMask {
    let values: [Double]
    let width: Int, height: Int, pad: Int
    let outside: Double

    /// The mask at layer point (`x`, `y`). The point is range-checked as a
    /// Double before any Int conversion, so a huge offset reads `outside`.
    func sample(_ x: Double, _ y: Double) -> Double {
        let px = x + Double(pad), py = y + Double(pad)
        guard px > -1, py > -1, px < Double(width), py < Double(height) else { return outside }
        let fx = px.rounded(.down), fy = py.rounded(.down)
        let wx = px - fx, wy = py - fy, x0 = Int(fx), y0 = Int(fy)
        func at(_ qx: Int, _ qy: Int) -> Double {
            qx >= 0 && qx < width && qy >= 0 && qy < height ? values[qy * width + qx] : outside
        }
        return (1 - wy) * ((1 - wx) * at(x0, y0) + wx * at(x0 + 1, y0)) + wy * ((1 - wx) * at(x0, y0 + 1) + wx * at(x0 + 1, y0 + 1))
    }
}
