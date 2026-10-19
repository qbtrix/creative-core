// GradientDither.swift: the ordered dither a raster gradient adds (fill-tools
// FT-6) so its 8-bit display encode does not band. Each pixel gets an offset
// of -0.5...+0.5 of one 8-bit step, read from a fixed 8 x 8 Bayer threshold
// matrix by (x, y), so a render is the same every time and on every platform.
// The offset is added to the sRGB-encoded straight colour, where the 8-bit
// encode quantises, then decoded back to linear light: averaged over the
// matrix, the bytes keep the gradient's value.
import CoreColor

enum GradientDither {
    /// The 8 x 8 Bayer index matrix, row-major: each of 0...63 once, so the
    /// thresholds spread evenly over one 8-bit step in both axes.
    static let matrix: [Int] = [
        0, 32, 8, 40, 2, 34, 10, 42,
        48, 16, 56, 24, 50, 18, 58, 26,
        12, 44, 4, 36, 14, 46, 6, 38,
        60, 28, 52, 20, 62, 30, 54, 22,
        3, 35, 11, 43, 1, 33, 9, 41,
        51, 19, 59, 27, 49, 17, 57, 25,
        15, 47, 7, 39, 13, 45, 5, 37,
        63, 31, 55, 23, 61, 29, 53, 21,
    ]

    /// The dither's full width, in encoded units: one 8-bit step, so offsets
    /// run from -0.5/255 to +0.5/255.
    static let amplitude = 1.0 / 255

    /// The encoded offset for the pixel at (`x`, `y`), in -0.5...0.5 of
    /// `amplitude`. `x` and `y` are non-negative pixel indices.
    static func offset(x: Int, y: Int) -> Double {
        let index = matrix[(y & 7) * 8 + (x & 7)]
        return ((Double(index) + 0.5) / 64 - 0.5) * amplitude
    }

    /// `color` (premultiplied, linear light) with the pixel's offset added to
    /// each sRGB-encoded straight channel. A transparent pixel, or one the
    /// dither would push out of Float's range, comes back unchanged.
    static func dithered(_ color: RGBA, x: Int, y: Int) -> RGBA {
        guard color.a > 0 else { return color }
        let d = offset(x: x, y: y)
        let s = color.unpremultiplied()
        func shift(_ v: Float) -> Float { Float(TransferCurve.decode(TransferCurve.encode(Double(v)) + d)) }
        let out = RGBA(r: shift(s.r), g: shift(s.g), b: shift(s.b), a: s.a).premultiplied()
        return out.isFinite ? out : color
    }
}
