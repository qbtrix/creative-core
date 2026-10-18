// RasterGradient.swift: the raster gradient behind the gradient tool
// (fill-tools). `GradientSpace` and `RasterGradientStop` are real values;
// `PixelBuffer.gradient` is a stub until FT-5 and FT-6: it throws
// `RasterError.invalid` with a "not built yet" reason, and they fill in the
// body without changing the signature.

/// The space a gradient interpolates its stops in: linear light, or OKLab
/// (perceptual).
public enum GradientSpace: Hashable, Sendable { case linear, perceptual }

/// One stop of a raster gradient: a colour (straight alpha) at an offset.
public struct RasterGradientStop: Hashable, Sendable {
    /// Where the stop sits along the gradient, in 0...1.
    public var offset: Float
    /// The stop's colour and alpha.
    public var color: RGBA

    public init(offset: Float, color: RGBA) {
        self.offset = offset
        self.color = color
    }
}

extension PixelBuffer {
    /// A `width` x `height` buffer filled with a gradient from `a` to `b`.
    ///
    /// - Parameters:
    ///   - width: at least 1; with `height`, a size `validatedSize` accepts.
    ///   - height: at least 1.
    ///   - shape: linear, radial, angle, reflected or diamond; each maps a
    ///     pixel centre to a parameter `t`, clamped to 0...1.
    ///   - a: the start point, in pixel space; finite.
    ///   - b: the end point; finite and not equal to `a`.
    ///   - stops: 2...64 stops, sorted by offset, offsets in 0...1, colours
    ///     finite.
    ///   - space: the space the stops interpolate in.
    ///   - dither: `true` adds a deterministic ordered dither of +-0.5/255 so
    ///     an 8-bit encode does not band.
    /// - Returns: the gradient, premultiplied like any buffer.
    /// - Throws: `RasterError.invalid` for a bad size, points or stops;
    ///   until FT-5, always.
    public static func gradient(width: Int, height: Int, shape: RasterGradientShape, from a: Mask.Point, to b: Mask.Point,
                                stops: [RasterGradientStop], space: GradientSpace = .perceptual,
                                dither: Bool = true) throws -> PixelBuffer {
        throw RasterError.invalid("gradient is not built yet (fill-tools FT-5)")
    }
}
