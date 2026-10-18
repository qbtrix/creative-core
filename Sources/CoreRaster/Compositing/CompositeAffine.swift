// CompositeAffine.swift: compositing a layer onto this buffer through an
// AffineMatrix in place, touching only the transformed bounds, and those
// bounds as an integer rectangle.
// Contract stub for affine-composite (AC-0): the signatures only, so the
// checks-first suites compile. `composite(_:through:...)` throws "not built"
// before any change and `bounds` is nil; the bodies land in AC-5.

extension PixelBuffer {
    /// Composites `src` mapped through `m` onto this buffer in place, sampled
    /// with `filter` and blended with `mode` at `opacity`. Stub: throws
    /// `RasterError.invalid("not built")` and changes nothing until AC-5.
    public mutating func composite(_ src: PixelBuffer, through m: AffineMatrix, mode: BlendMode, opacity: Float,
                                   filter: ResampleFilter) throws {
        throw RasterError.invalid("not built")
    }
}

public extension AffineMatrix {
    /// The integer rectangle covering a `width` x `height` image's corners
    /// under this matrix, nil when non-finite. Stub: nil until AC-5.
    func bounds(of width: Int, _ height: Int) -> (x: Int, y: Int, width: Int, height: Int)? {
        nil
    }
}
