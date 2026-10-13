// Develop.swift: the develop-slider adjustments on a PixelBuffer: white
// balance (temperature, tint), contrast, and highlights and shadows. They run
// through the same per-pixel loop as exposure and curves (`mappingStraight` in
// `Adjustments.swift`), on straight linear values, and never change alpha.
// Invariants a reader must keep: every parameter is in `developRange` and is
// checked before any pixel is touched (else `RasterError.invalid`); all-zero
// parameters return the input unchanged, bit for bit; white balance keeps a
// neutral grey's Rec. 709 luminance; contrast keeps `midGrey` fixed and is
// monotonic; highlights move only pixels brighter than `midGrey`, shadows only
// darker ones.
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

extension PixelBuffer {
    /// The range every develop slider accepts; 0 is no change.
    public static let developRange: ClosedRange<Float> = -100...100

    /// Mid grey in linear light, the pivot of contrast and the boundary
    /// between shadows and highlights.
    static let midGrey = 0.18

    /// White balance. A positive `temperature` warms (red up, blue down); a
    /// positive `tint` pushes toward magenta (green down). At ±100 a channel
    /// moves half a stop. The gains are divided by their Rec. 709 luminance,
    /// so a neutral grey keeps its luminance. Throws for a value outside
    /// `developRange` or not finite.
    public func whiteBalance(temperature: Float, tint: Float) throws -> PixelBuffer {
        try Self.checkDevelop("temperature", temperature)
        try Self.checkDevelop("tint", tint)
        if temperature == 0, tint == 0 { return self }
        let warm = Double(temperature) / 200, magenta = Double(tint) / 200
        let r = pow(2, warm), g = pow(2, -magenta), b = pow(2, -warm)
        let w = Histogram.luminanceWeights
        let grey = Double(w.r) * r + Double(w.g) * g + Double(w.b) * b
        let gr = Float(r / grey), gg = Float(g / grey), gb = Float(b / grey)
        return try mappingStraight { RGBA(r: $0.r * gr, g: $0.g * gg, b: $0.b * gb, a: $0.a) }
    }

    /// Contrast around `midGrey`: each channel v becomes
    /// sign(v) * midGrey * (|v| / midGrey)^k with k = 2^(`amount` / 100), a
    /// straight line of slope k in log exposure, which reads as an S-curve on
    /// a display. `midGrey` keeps its value; positive amounts push values
    /// away from it, negative pull them toward it. Monotonic for every
    /// amount. Throws for an amount outside `developRange` or not finite.
    public func contrast(_ amount: Float) throws -> PixelBuffer {
        try Self.checkDevelop("contrast", amount)
        if amount == 0 { return self }
        let k = pow(2, Double(amount) / 100), pivot = Self.midGrey
        return try mappingColor { value in
            let v = Double(value)
            let mapped = pivot * pow(abs(v) / pivot, k)
            return Float(v < 0 ? -mapped : mapped)
        }
    }

    /// Highlights and shadows: an exposure change of up to one stop at ±100,
    /// weighted by the pixel's Rec. 709 luminance L. `highlights` is weighted
    /// by smoothstep(`midGrey`, 1, L), so it leaves pixels at or below mid
    /// grey alone; `shadows` by 1 - smoothstep(0, `midGrey`, L), so it leaves
    /// pixels at or above mid grey alone. All three channels share the gain,
    /// so hue is kept. Throws for a value outside `developRange` or not finite.
    public func highlightsShadows(highlights: Float, shadows: Float) throws -> PixelBuffer {
        try Self.checkDevelop("highlights", highlights)
        try Self.checkDevelop("shadows", shadows)
        if highlights == 0, shadows == 0 { return self }
        let h = Double(highlights) / 100, s = Double(shadows) / 100
        let w = Histogram.luminanceWeights
        return try mappingStraight { p in
            let lum = Double(w.r * p.r + w.g * p.g + w.b * p.b)
            let stops = h * smoothstep(Self.midGrey, 1, lum) + s * (1 - smoothstep(0, Self.midGrey, lum))
            let gain = Float(pow(2, stops))
            return RGBA(r: p.r * gain, g: p.g * gain, b: p.b * gain, a: p.a)
        }
    }

    private static func checkDevelop(_ name: String, _ value: Float) throws {
        guard developRange.contains(value) else {
            throw RasterError.invalid("\(name) \(value): must be in \(developRange)")
        }
    }
}

/// 0 at or below `edge0`, 1 at or above `edge1`, the cubic 3t² - 2t³ between.
private func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}
