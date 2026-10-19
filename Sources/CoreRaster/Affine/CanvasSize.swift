// CanvasSize.swift: resizing a PixelBuffer's canvas around a CanvasAnchor,
// padding with transparent pixels when it grows and cropping when it shrinks.
// The image moves by the size change times the anchor's place on each axis
// (0 for left or top, 0.5 for the middle, 1 for right or bottom), rounded
// down, so a shrink crops by the same rule a grow pads by. That move is a
// whole-pixel translation, which `transformed` copies row by row with no
// filtering, so every output pixel is a source pixel or clear.
// Invariants: the new size passed `validatedSize`; both sizes are at most
// `maxPixels`, so the size change and the offset fit in Int and in Double.

extension PixelBuffer {
    /// This image on a `width` x `height` canvas: grows with transparent
    /// pixels, shrinks by cropping. The image's top-left moves by
    /// (`width` - old width, `height` - old height) times the anchor's place
    /// (0, 0.5 or 1 per axis), rounded down. Throws `RasterError.invalid` for
    /// a size `validatedSize` rejects.
    public func padded(width newW: Int, height newH: Int, anchor: CanvasAnchor) throws -> PixelBuffer {
        _ = try Self.validatedSize(width: newW, height: newH)
        let (fx, fy) = anchor.place
        let dx = Self.anchorOffset(change: newW - width, place: fx)
        let dy = Self.anchorOffset(change: newH - height, place: fy)
        let move = AffineMatrix(a: 1, b: 0, c: 0, d: 1, tx: dx, ty: dy)
        return try transformed(move, width: newW, height: newH, filter: .bilinear)
    }

    /// Where the image's first column (or row) lands when that axis changes
    /// by `change` pixels with the anchor at `place` (0, 0.5 or 1): rounded
    /// down, so the middle of an odd change sits one pixel nearer the start.
    private static func anchorOffset(change: Int, place: Double) -> Double {
        (Double(change) * place).rounded(.down)
    }
}

extension CanvasAnchor {
    /// The anchor's place along x and y: 0 at the left or top, 0.5 in the
    /// middle, 1 at the right or bottom.
    fileprivate var place: (x: Double, y: Double) {
        switch self {
        case .topLeft: (0, 0)
        case .top: (0.5, 0)
        case .topRight: (1, 0)
        case .left: (0, 0.5)
        case .center: (0.5, 0.5)
        case .right: (1, 0.5)
        case .bottomLeft: (0, 1)
        case .bottom: (0.5, 1)
        case .bottomRight: (1, 1)
        }
    }
}
