// CanvasSize.swift: resizing a PixelBuffer's canvas around a CanvasAnchor,
// padding with transparent pixels when it grows and cropping when it shrinks.
// Contract stub for affine-composite (AC-0): the signature only, so the
// checks-first suites compile. `padded` throws "not built"; the body lands
// in AC-4.

extension PixelBuffer {
    /// This image on a `width` x `height` canvas, placed at `anchor`; a
    /// smaller size crops. Stub: throws `RasterError.invalid("not built")`
    /// until AC-4.
    public func padded(width: Int, height: Int, anchor: CanvasAnchor) throws -> PixelBuffer {
        throw RasterError.invalid("not built")
    }
}
