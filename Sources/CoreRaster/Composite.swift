// Composite.swift: source-over compositing of one PixelBuffer onto another
// with a blend mode and an opacity, per W3C Compositing and Blending Level 1.
// Opacity scales the premultiplied source first. Then, per pixel, with Cs and
// Cb the straight colors and αs, αb the alphas:
//   Cs' = (1 - αb) Cs + αb B(Cb, Cs)
//   co  = αs Cs' + cb (1 - αs),   αo = αs + αb (1 - αs)   (co, cb premultiplied)
// Opacity 0 and a fully transparent source give back the backdrop exactly.
// The source sits at an integer offset and is clipped to the backdrop; the
// same-size call is the (0, 0) case.

/// Composites `source` over `backdrop` and returns the result. Throws
/// `RasterError.invalid` when the sizes differ, when `opacity` is outside
/// 0...1 or not finite, or when a result component overflows to infinity
/// (only possible for extreme out-of-range pixel values).
public func composite(_ source: PixelBuffer, onto backdrop: PixelBuffer,
                      mode: BlendMode, opacity: Float) throws -> PixelBuffer {
    guard source.width == backdrop.width, source.height == backdrop.height else {
        throw RasterError.invalid(
            "source \(source.width)x\(source.height) does not match backdrop \(backdrop.width)x\(backdrop.height)")
    }
    return try composite(source, onto: backdrop, x: 0, y: 0, mode: mode, opacity: opacity)
}

/// Composites `source` over `backdrop` with source pixel (sx, sy) on backdrop
/// pixel (x + sx, y + sy), and returns the result. The source may be any size
/// and hang off any edge: only the overlap is visited, and a source entirely
/// outside gives back the backdrop. Throws `RasterError.invalid` when
/// `opacity` is outside 0...1 or not finite, or when a result component
/// overflows to infinity.
public func composite(_ source: PixelBuffer, onto backdrop: PixelBuffer, x: Int, y: Int,
                      mode: BlendMode, opacity: Float) throws -> PixelBuffer {
    // NaN and the infinities are outside the range, so this also checks finiteness.
    guard (0...1).contains(opacity) else {
        throw RasterError.invalid("opacity \(opacity): must be a finite value in 0...1")
    }
    // Both bounds are checked before adding, so x + width cannot overflow.
    guard x < backdrop.width, y < backdrop.height, x > -source.width, y > -source.height else {
        return backdrop
    }
    var result = backdrop
    for by in max(y, 0)..<min(y + source.height, backdrop.height) {
        for bx in max(x, 0)..<min(x + source.width, backdrop.width) {
            let s = try source.pixel(x: bx - x, y: by - y)
            let b = try backdrop.pixel(x: bx, y: by)
            try result.setPixel(x: bx, y: by, sourceOver(s, b, mode: mode, opacity: opacity))
        }
    }
    return result
}

/// One premultiplied source pixel over one premultiplied backdrop pixel.
private func sourceOver(_ source: RGBA, _ b: RGBA, mode: BlendMode, opacity: Float) -> RGBA {
    let s = RGBA(r: source.r * opacity, g: source.g * opacity, b: source.b * opacity, a: source.a * opacity)
    let cs = s.unpremultiplied()
    let blended = mode.blend(backdrop: b.unpremultiplied(), source: cs)
    let mixed = RGBA(r: cs.r + b.a * (blended.r - cs.r), g: cs.g + b.a * (blended.g - cs.g),
                     b: cs.b + b.a * (blended.b - cs.b), a: s.a).premultiplied()
    let keep = 1 - s.a
    return RGBA(r: mixed.r + b.r * keep, g: mixed.g + b.g * keep, b: mixed.b + b.b * keep, a: s.a + b.a * keep)
}
