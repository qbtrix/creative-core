// Bevel.swift: bevel and emboss (layer-style-engine LE-3): height from the
// alpha's distance field in four shapes and three techniques, softened, then
// lit from the bevel's angle and altitude into a highlight and a shadow layer.
// Declared now so callers compile; LE-3 builds the body. Invariants (LE-3):
// both layers are the buffer's size, clipped to the alpha (an outer bevel's to
// its complement within `size`), and out-of-range parameters throw.

extension PixelBuffer {
    /// The bevel's two light layers, each the buffer's size: where the edge faces the light, and where it faces away.
    /// Not built yet: throws until LE-3.
    public func beveled(_ bevel: Bevel) throws -> (highlight: PixelBuffer, shadow: PixelBuffer) {
        throw RasterError.invalid("beveled is not built (LE-3)")
    }
}
