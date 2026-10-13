// Retouch.swift: clone, the stamp op behind a soft clone brush. Each pixel
// (x, y) is replaced by the pixel at (x + dx, y + dy), mixed by the mask's
// coverage c at (x, y): out = c * source + (1 - c) * self, on premultiplied
// components, so coverage 0 keeps a pixel exactly and coverage 1 copies it
// exactly.
// Invariants a reader must keep: the source is always read from `self`, the
// input, never from the partly written result, so overlapping source and
// destination don't smear; a pixel whose source falls outside the buffer is
// left as it is; offsets are bounded before `x + dx` so it cannot overflow.

extension PixelBuffer {
    /// The buffer with each pixel replaced by the one at (x + dx, y + dy),
    /// mixed by `mask`'s coverage at (x, y). Pixels whose source is outside
    /// the buffer are unchanged. Throws `RasterError.invalid` when the mask's
    /// size differs from the buffer's.
    public func cloned(offset: (dx: Int, dy: Int), through mask: Mask) throws -> PixelBuffer {
        guard mask.width == width, mask.height == height else {
            throw RasterError.invalid(
                "mask \(mask.width)x\(mask.height) does not match buffer \(width)x\(height)")
        }
        let (dx, dy) = offset
        // Every source is off the buffer: nothing to copy. Past this guard
        // |dx| < width and |dy| < height, so the sums below cannot overflow.
        guard dx > -width, dx < width, dy > -height, dy < height else { return self }
        var result = self
        for y in max(0, -dy)..<min(height, height - dy) {
            for x in max(0, -dx)..<min(width, width - dx) {
                let c = try mask.coverage(x: x, y: y)
                let s = try pixel(x: x + dx, y: y + dy)
                let b = try pixel(x: x, y: y)
                let keep = 1 - c
                try result.setPixel(x: x, y: y, RGBA(r: s.r * c + b.r * keep, g: s.g * c + b.g * keep,
                                                     b: s.b * c + b.b * keep, a: s.a * c + b.a * keep))
            }
        }
        return result
    }
}
