// AlphaEffects+Light.swift: outer and inner glow and drop and inner shadow,
// from the layer's blurred alpha, composited under (outer) or over (inner)
// the layer. A stub until effects-engine task FX-6 fills it: both throw
// `RasterError.invalid("not built")`.

extension PixelBuffer {
    /// This buffer with a glow of `radius` pixels. Not built yet: throws.
    public func glowing(color: RGBA, radius: Double, intensity: Double, inner: Bool) throws -> PixelBuffer {
        throw RasterError.invalid("not built")
    }

    /// This buffer with a shadow offset by (dx, dy). Not built yet: throws.
    public func shadowed(color: RGBA, dx: Double, dy: Double, blur: Double, inner: Bool) throws -> PixelBuffer {
        throw RasterError.invalid("not built")
    }
}
