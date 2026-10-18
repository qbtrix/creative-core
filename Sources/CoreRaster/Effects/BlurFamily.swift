// BlurFamily.swift: box blur (three running-sum passes that approach a
// Gaussian, 0 is identity) and motion blur along an angle. A stub until
// effects-engine task FX-3 fills it: both throw `RasterError.invalid("not built")`.

extension PixelBuffer {
    /// This buffer box-blurred by `radius` pixels. Not built yet: throws.
    public func boxBlurred(radius: Double) throws -> PixelBuffer {
        throw RasterError.invalid("not built")
    }

    /// This buffer blurred `distance` pixels along `degrees`. Not built yet: throws.
    public func motionBlurred(degrees: Double, distance: Double) throws -> PixelBuffer {
        throw RasterError.invalid("not built")
    }
}
