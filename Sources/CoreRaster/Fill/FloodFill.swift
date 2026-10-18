// FloodFill.swift: the flood-fill mask behind the paint bucket and the magic
// wand (fill-tools). A stub until FT-3: `floodMask` throws
// `RasterError.invalid` with a "not built yet" reason; FT-3 fills in the body
// and never changes the signature.

/// Which neighbours a contiguous flood fill steps to: the four edge
/// neighbours, or all eight including the diagonals.
public enum Connectivity: Hashable, Sendable { case four, eight }

extension PixelBuffer {
    /// A mask of the pixels a fill from `seed` takes.
    ///
    /// - Parameters:
    ///   - seed: the starting pixel; must lie inside the buffer
    ///     (`0..<width`, `0..<height`), or the call throws.
    ///   - tolerance: `.exact`, or `.within(t)` with `t` in 0...1, an OKLab
    ///     distance (alpha as a fourth axis) from the seed's colour.
    ///   - contiguous: `true` takes only pixels connected to the seed;
    ///     `false` takes every matching pixel in the buffer.
    ///   - connectivity: the neighbours a contiguous fill steps to.
    ///   - antiAlias: `true` gives the rejected pixels next to taken ones a
    ///     one-pixel soft edge of coverage in 0...1.
    /// - Returns: a mask the size of the buffer, coverage in 0...1.
    /// - Throws: `RasterError.invalid` for a seed outside the buffer or a
    ///   tolerance outside 0...1; until FT-3, always.
    public func floodMask(from seed: (x: Int, y: Int), tolerance: FillTolerance, contiguous: Bool = true,
                          connectivity: Connectivity = .four, antiAlias: Bool = true) throws -> Mask {
        throw RasterError.invalid("floodMask is not built yet (fill-tools FT-3)")
    }
}
