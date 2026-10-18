// ColorMap.swift: gradient map, 3D LUT apply, posterize, threshold and invert
// on a PixelBuffer, the tone-pack contract slice (docs/blueprints/core/features/tone-pack.md).
// TP-0 stub: the throwing ops throw `RasterError.invalid("not built")` and
// `inverted()` returns its input, until TP-5 fills them and turns on
// `ColorMapTests` and `ColorLUTTests`.
extension PixelBuffer {
    /// Luma mapped through 2...64 sorted stops.
    public func gradientMap(_ stops: [GradientMapStop]) throws -> PixelBuffer {
        throw RasterError.invalid("not built")
    }

    /// Trilinear lookup on sRGB-encoded values.
    public func applying(_ lut: ColorLUT) throws -> PixelBuffer {
        throw RasterError.invalid("not built")
    }

    /// `levels` in 2...255 per channel.
    public func posterized(levels: Int) throws -> PixelBuffer {
        throw RasterError.invalid("not built")
    }

    /// Black or white by luma against `level` in 0...1.
    public func thresholded(_ level: Float) throws -> PixelBuffer {
        throw RasterError.invalid("not built")
    }

    /// Each colour channel inverted; the stub returns the buffer unchanged.
    public func inverted() -> PixelBuffer {
        self
    }
}
