// Retouch.swift: clone, the stamp op behind a soft clone brush. Each pixel
// (x, y) is replaced by the pixel at (x + dx, y + dy), mixed by the mask's
// coverage c at (x, y): out = c * source + (1 - c) * self, on premultiplied
// components, so coverage 0 keeps a pixel exactly and coverage 1 copies it
// exactly.
// Invariants a reader must keep: the source is always read from `self`, the
// input, never from the partly written result, so overlapping source and
// destination don't smear; a pixel whose source falls outside the buffer is
// left as it is; offsets are bounded before `x + dx` so it cannot overflow;
// only pixels inside the mask's covered bounds are visited, so a dab costs
// its bounds plus one copy of the buffer, not a pass of per-pixel checks.

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
        // Only pixels the mask covers change: limit the mix to its covered
        // bounds, clipped to where the source stays on the buffer (issue #257).
        guard let covered = mask.coveredBounds else { return self }
        let minX = max(0, -dx, covered.x), maxX = min(width, width - dx, covered.x + covered.width)
        let minY = max(0, -dy, covered.y), maxY = min(height, height - dy, covered.y + covered.height)
        guard minX < maxX, minY < maxY else { return self }
        let input = components
        let coverage = mask.values
        let channels = Self.channels
        var output = input
        for y in minY..<maxY {
            for x in minX..<maxX {
                let c = coverage[y * width + x]
                let keep = 1 - c
                let b = (y * width + x) * channels
                let s = ((y + dy) * width + x + dx) * channels
                let mixed = RGBA(r: input[s] * c + input[b] * keep, g: input[s + 1] * c + input[b + 1] * keep,
                                 b: input[s + 2] * c + input[b + 2] * keep, a: input[s + 3] * c + input[b + 3] * keep)
                guard mixed.isFinite else {
                    throw RasterError.invalid("pixel \(mixed) at (\(x), \(y)): components must be finite")
                }
                output[b] = mixed.r
                output[b + 1] = mixed.g
                output[b + 2] = mixed.b
                output[b + 3] = mixed.a
            }
        }
        return PixelBuffer(checkedWidth: width, height: height, storage: output)
    }
}
