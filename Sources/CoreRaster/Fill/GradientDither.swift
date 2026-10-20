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

    /// `s` (straight alpha, linear light) with the pixel's offset added to
    /// each sRGB-encoded channel; alpha is kept. A transparent pixel, or one
    /// the dither would push out of Float's range, comes back unchanged.
    static func dithered(_ s: RGBA, x: Int, y: Int) -> RGBA {
        guard s.a > 0 else { return s }
        let d = offset(x: x, y: y)
        func shift(_ v: Float) -> Float { Float(decode(encode(Double(v)) + d)) }
        let out = RGBA(r: shift(s.r), g: shift(s.g), b: shift(s.b), a: s.a)
        return out.isFinite ? out : s
    }

    /// Steps of the transfer tables over 0...1. The encode curve bends hard
    /// just above its linear toe, so it gets the finer table: either table's
    /// lerp error is under 1e-3 of an 8-bit step.
    private static let encodeSteps = 16384, decodeSteps = 4096
    private static let encodeTable = table(encodeSteps, TransferCurve.encode)
    private static let decodeTable = table(decodeSteps, TransferCurve.decode)

    private static func table(_ steps: Int, _ curve: (Double) -> Double) -> [Double] {
        (0...steps).map { curve(Double($0) / Double(steps)) }
    }

    /// `TransferCurve.encode`, read from a table in 0...1 (exact outside it).
    static func encode(_ v: Double) -> Double { lookup(encodeTable, encodeSteps, v) ?? TransferCurve.encode(v) }

    /// `TransferCurve.decode`, read from a table in 0...1 (exact outside it).
    static func decode(_ v: Double) -> Double { lookup(decodeTable, decodeSteps, v) ?? TransferCurve.decode(v) }

    /// The table's lerp at `v`, or nil when `v` is outside 0...1 or NaN.
    private static func lookup(_ table: [Double], _ steps: Int, _ v: Double) -> Double? {
        guard v >= 0, v <= 1 else { return nil }
        let u = v * Double(steps), i = min(Int(u), steps - 1), w = u - Double(i)
        return table[i] + (table[i + 1] - table[i]) * w
    }
}
