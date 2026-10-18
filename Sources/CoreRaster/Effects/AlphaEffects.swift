// AlphaEffects.swift: an alpha stroke outside, inside or centred on the
// layer's edge, from a `DistanceField`. A stub until effects-engine task FX-5
// fills it: `stroked` throws `RasterError.invalid("not built")`.

extension PixelBuffer {
    /// This buffer with a `width`-pixel stroke at `position`. Not built yet: throws.
    public func stroked(color: RGBA, width: Double, position: StrokePosition) throws -> PixelBuffer {
        throw RasterError.invalid("not built")
    }
}
