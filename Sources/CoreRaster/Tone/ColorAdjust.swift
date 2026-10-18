// ColorAdjust.swift: vibrance, hue/saturation/lightness and per-range HSL on a
// PixelBuffer, the tone-pack contract slice (docs/blueprints/core/features/tone-pack.md).
// TP-0 stub: each op throws `RasterError.invalid("not built")` until TP-3
// fills it with the packet's formulas and turns on `ColorAdjustTests`.
extension PixelBuffer {
    /// Saturation boost that moves low-saturation pixels most; `amount` in -100...100.
    public func vibrance(_ amount: Float) throws -> PixelBuffer {
        throw RasterError.invalid("not built")
    }

    /// Hue shift in degrees, saturation and lightness in -100...100.
    public func hueSaturation(hue: Float, saturation: Float, lightness: Float) throws -> PixelBuffer {
        throw RasterError.invalid("not built")
    }

    /// Per-hue-range HSL shifts over eight ranges.
    public func hsl(_ adjustment: HSLAdjustment) throws -> PixelBuffer {
        throw RasterError.invalid("not built")
    }
}
