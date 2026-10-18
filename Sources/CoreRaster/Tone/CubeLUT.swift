// CubeLUT.swift: the `.cube` 3D LUT text reader, the tone-pack contract slice
// (docs/blueprints/core/features/tone-pack.md). Accepts LUT_3D_SIZE 2...65 and
// DOMAIN_MIN/MAX 0...1 only.
// TP-0 stub: `parse` throws `RasterError.invalid("not built")` until TP-5
// fills it and turns on `ColorLUTTests`.
public enum CubeLUT {
    /// The LUT a `.cube` text describes; throws `RasterError.invalid` on damaged text.
    public static func parse(_ text: String) throws -> ColorLUT {
        throw RasterError.invalid("not built")
    }
}
