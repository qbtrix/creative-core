// MaskFeather.swift: feathering a mask by a radius, the separable Gaussian of
// sigma = radius / 3 (kernel radius ceil(radius)) with clamp-to-edge taps.
// The weights and taps are `gaussianBlur`'s own (`PixelBuffer.gaussianKernel`
// and `taps`), and the passes run through the same `convolved`: a mask has one
// channel and `convolved` four, so each pass packs four lines of the mask as
// the four channels of one line (rows for the horizontal pass, columns for the
// vertical), padding past the last line with 0 and dropping it after.
// Invariants: the radius is finite and at least 0 and its kernel radius at
// most twice the larger side (as `gaussianBlur`), and every result value is a
// convex mix of input values, kept in 0...1.

extension Mask {
    /// This mask feathered: blurred by a Gaussian of sigma `radius` / 3, so a
    /// hard edge fades over about `radius` pixels each side and reads 0.5 on
    /// the edge itself. Area is kept away from the mask's border; at the
    /// border the nearest pixel repeats, so a full mask stays full. Radius 0
    /// returns this mask. Throws `RasterError.invalid` for a radius that is
    /// negative, not finite, or over twice the mask's larger side.
    public func feathered(radius: Double) throws -> Mask {
        guard radius.isFinite, radius >= 0 else {
            throw RasterError.invalid("feather radius \(radius): must be finite and at least 0")
        }
        let kernel = try PixelBuffer.gaussianKernel(sigma: radius / 3, width: width, height: height)
        guard kernel.count > 1 else { return self }
        let lanes = PixelBuffer.channels, w = width, h = height
        // Horizontal: line g holds rows 4g..<4g + 4, lane k of pixel x at (g * w + x) * 4 + k.
        let rowGroups = (h + lanes - 1) / lanes
        var packed = [Float](repeating: 0, count: rowGroups * w * lanes)
        for y in 0..<h {
            let base = (y / lanes) * w * lanes + y % lanes
            for x in 0..<w { packed[base + x * lanes] = storage[y * w + x] }
        }
        let across = PixelBuffer.convolved(packed, lines: rowGroups, newLength: w, src: (lanes, w * lanes),
                                           dst: (lanes, w * lanes), tap: PixelBuffer.taps(kernel, length: w))
        // Vertical: line g holds columns 4g..<4g + 4, lane k of pixel y at (g * h + y) * 4 + k.
        let columnGroups = (w + lanes - 1) / lanes
        packed = [Float](repeating: 0, count: columnGroups * h * lanes)
        for y in 0..<h {
            let from = (y / lanes) * w * lanes + y % lanes
            for x in 0..<w { packed[((x / lanes) * h + y) * lanes + x % lanes] = across[from + x * lanes] }
        }
        let down = PixelBuffer.convolved(packed, lines: columnGroups, newLength: h, src: (lanes, h * lanes),
                                         dst: (lanes, h * lanes), tap: PixelBuffer.taps(kernel, length: h))
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w { out[y * w + x] = min(max(down[((x / lanes) * h + y) * lanes + x % lanes], 0), 1) }
        }
        return Mask(checkedWidth: w, height: h, storage: out)
    }
}
