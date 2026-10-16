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
    var result = backdrop
    try result.composite(source, x: 0, y: 0, mode: mode, opacity: opacity)
    return result
}

/// Composites `source` over `backdrop` with source pixel (sx, sy) on backdrop
/// pixel (x + sx, y + sy), and returns the result. The source may be any size
/// and hang off any edge: only the overlap is visited, and a source entirely
/// outside gives back the backdrop. Throws `RasterError.invalid` when
/// `opacity` is outside 0...1 or not finite, or when a result component
/// overflows to infinity. `backdrop` is unchanged either way.
public func composite(_ source: PixelBuffer, onto backdrop: PixelBuffer, x: Int, y: Int,
                      mode: BlendMode, opacity: Float) throws -> PixelBuffer {
    var result = backdrop
    try result.composite(source, x: x, y: y, mode: mode, opacity: opacity)
    return result
}

extension PixelBuffer {
    /// Composites `source` over this buffer with source pixel (sx, sy) on
    /// pixel (x + sx, y + sy), in place. Same pixels and same throws as
    /// `composite(_:onto:x:y:mode:opacity:)`. Nothing is copied when this
    /// buffer is the only owner of its storage; when another value shares it
    /// (say a caller's `let before = layer`), the first row written copies the
    /// buffer once, as any write to a value type does.
    /// A bad opacity throws before any change. A result that overflows to
    /// infinity throws for the first such pixel in row order: the rows above
    /// it already hold the composite, the rest are untouched, and every
    /// stored component stays finite.
    public mutating func composite(_ source: PixelBuffer, x: Int, y: Int,
                                   mode: BlendMode, opacity: Float) throws {
        // NaN and the infinities are outside the range, so this also checks finiteness.
        guard (0...1).contains(opacity) else {
            throw RasterError.invalid("opacity \(opacity): must be a finite value in 0...1")
        }
        // Both bounds are checked before adding, so x + width cannot overflow.
        guard x < width, y < height, x > -source.width, y > -source.height else { return }
        let x0 = max(x, 0), x1 = min(x + source.width, width)
        let count = x1 - x0, n = count * Self.channels
        // An opaque source row under .normal at full opacity gives the source
        // itself by the formula (with ==), so it is copied in.
        let copies = mode == .normal && opacity == 1
        var scratch = [Float](repeating: 0, count: n)
        // Every pointer below covers only the clipped overlap: `n` components
        // of a source row and of a backdrop row, and `scratch` itself.
        try source.components.withUnsafeBufferPointer { src in
            try scratch.withUnsafeMutableBufferPointer { staged in
                for by in max(y, 0)..<min(y + source.height, height) {
                    let from = ((by - y) * source.width + x0 - x) * Self.channels
                    let row = UnsafeBufferPointer(rebasing: src[from..<(from + n)])
                    let opaqueRow = copies && stride(from: from + 3, to: from + n, by: 4).allSatisfy { src[$0] == 1 }
                    try updateRow(x: x0, y: by, count: count) { span in
                        if opaqueRow {
                            _ = span.update(fromContentsOf: row)
                            return
                        }
                        for k in 0..<count {
                            let i = k * Self.channels
                            let out = sourceOver(RGBA(r: row[i], g: row[i + 1], b: row[i + 2], a: row[i + 3]),
                                                RGBA(r: span[i], g: span[i + 1], b: span[i + 2], a: span[i + 3]),
                                                mode: mode, opacity: opacity)
                            guard out.isFinite else {
                                throw RasterError.invalid("pixel \(out) at (\(x0 + k), \(by)): components must be finite")
                            }
                            staged[i] = out.r
                            staged[i + 1] = out.g
                            staged[i + 2] = out.b
                            staged[i + 3] = out.a
                        }
                        _ = span.update(fromContentsOf: staged)
                    }
                }
            }
        }
    }
}

/// One premultiplied source pixel over one premultiplied backdrop pixel.
private func sourceOver(_ source: RGBA, _ b: RGBA, mode: BlendMode, opacity: Float) -> RGBA {
    let s = RGBA(r: source.r * opacity, g: source.g * opacity, b: source.b * opacity, a: source.a * opacity)
    let cs = s.unpremultiplied()
    // B(Cb, Cs) is Cs under .normal, so the backdrop's straight color is not needed.
    let blended = mode == .normal ? cs : mode.blend(backdrop: b.unpremultiplied(), source: cs)
    let mixed = RGBA(r: cs.r + b.a * (blended.r - cs.r), g: cs.g + b.a * (blended.g - cs.g),
                     b: cs.b + b.a * (blended.b - cs.b), a: s.a).premultiplied()
    let keep = 1 - s.a
    return RGBA(r: mixed.r + b.r * keep, g: mixed.g + b.g * keep, b: mixed.b + b.b * keep, a: s.a + b.a * keep)
}
