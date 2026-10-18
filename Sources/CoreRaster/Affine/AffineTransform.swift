// AffineTransform.swift: resampling a PixelBuffer through an AffineMatrix
// (transparent outside, the ResampleFilter kernels) and flipping it exactly.
// Contract stub for affine-composite (AC-0): the signatures only, so the
// checks-first suites compile. `transformed` throws "not built" and `flipped`
// returns this buffer unchanged; the bodies land in AC-3.

extension PixelBuffer {
    /// This image mapped through `m` into a `width` x `height` buffer,
    /// sampled with `filter`; outside the source is transparent. A singular
    /// `m` throws. Stub: throws `RasterError.invalid("not built")` until AC-3.
    public func transformed(_ m: AffineMatrix, width: Int, height: Int, filter: ResampleFilter) throws -> PixelBuffer {
        throw RasterError.invalid("not built")
    }

    /// This image mirrored across `axis`. Stub: returns this buffer unchanged
    /// until AC-3.
    public func flipped(_ axis: FlipAxis) -> PixelBuffer {
        self
    }
}
