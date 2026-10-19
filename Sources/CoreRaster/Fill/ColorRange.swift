// ColorRange.swift: colour sampling and the colour-range mask behind select
// by colour range (fill-tools). Stubs until FT-4: both throw
// `RasterError.invalid` with a "not built yet" reason; FT-4 fills in the
// bodies and never changes the signatures.

extension PixelBuffer {
    /// The mean colour of the (2r + 1) x (2r + 1) box centred on `p`.
    ///
    /// - Parameters:
    ///   - p: the centre pixel; must lie inside the buffer, or the call throws.
    ///   - radius: `r`, in 0...2 (0 samples the one pixel, 1 a 3 x 3 box,
    ///     2 a 5 x 5 box); any other value throws.
    /// - Returns: the mean colour, premultiplied like the buffer.
    /// - Throws: `RasterError.invalid` for a point outside the buffer or a
    ///   radius outside 0...2; until FT-4, always.
    public func sampledColor(at p: (x: Int, y: Int), radius: Int) throws -> RGBA {
        throw RasterError.invalid("sampledColor is not built yet (fill-tools FT-4)")
    }

    /// A mask covering each pixel by its OKLab distance from `color`, with a
    /// soft falloff.
    ///
    /// - Parameters:
    ///   - color: the colour to select around; must be finite.
    ///   - fuzziness: in 0...1; the distance at which coverage falls to 0.
    ///     0 gives a hard mask of exact matches.
    /// - Returns: a mask the size of the buffer, coverage in 0...1.
    /// - Throws: `RasterError.invalid` for a non-finite colour or a
    ///   fuzziness outside 0...1; until FT-4, always.
    public func colorRangeMask(around color: RGBA, fuzziness: Float) throws -> Mask {
        throw RasterError.invalid("colorRangeMask is not built yet (fill-tools FT-4)")
    }
}
