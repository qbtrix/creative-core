// MaskFromBuffer.swift: a mask read from a buffer's alpha or luminance, the
// two track-matte sources.
// Alpha is the stored alpha (premultiplying leaves it as is); luminance is
// the Rec. 709 luma (`Histogram.luminanceWeights`) of the linear colour times
// alpha, which is the luma of the premultiplied components, so a transparent
// pixel reads 0.
// Invariants: every value is clamped to 0...1, NaN to 0, before `inverted`
// takes 1 minus it, so the mask stays valid for out-of-range pixels.

extension Mask {
    /// A mask the size of `buffer` holding each pixel's alpha or luminance
    /// (times alpha), clamped to 0...1, or 1 minus that when `inverted`.
    /// Every buffer gives a valid mask, so nothing throws today; `throws` is
    /// the contract's, for sources still to come.
    public init(from buffer: PixelBuffer, _ source: MatteSource, inverted: Bool = false) throws {
        let w = Histogram.luminanceWeights, c = buffer.components
        let values = stride(from: 0, to: c.count, by: PixelBuffer.channels).map { i -> Float in
            let v = source == .alpha ? c[i + 3] : w.r * c[i] + w.g * c[i + 1] + w.b * c[i + 2]
            let clamped: Float = v >= 1 ? 1 : v > 0 ? v : 0
            return inverted ? 1 - clamped : clamped
        }
        self.init(checkedWidth: buffer.width, height: buffer.height, storage: values)
    }
}
