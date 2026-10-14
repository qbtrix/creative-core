// Adjustments.swift: tone adjustments on a PixelBuffer: exposure, levels,
// curves, and the develop sliders (white balance, contrast, highlights and
// shadows). Each one maps every pixel through one function on unpremultiplied
// linear values (`RGBA.unpremultiplied`), then premultiplies again
// (`RGBA.premultiplied`), all in `mappingPixels`. Levels and curves can read
// sRGB-encoded values instead (`ToneEncoding.sRGB`, CoreColor's
// TransferCurve): each channel is encoded, mapped, and decoded back to linear,
// so their parameters mean what a display shows. Alpha is never changed. Develop
// sliders take -100...100 with 0 as no change. Parameters are checked
// before any pixel is touched and throw `RasterError.invalid`; identity
// parameters return the input unchanged, bit for bit; a result component that
// overflows to infinity throws, as `setPixel` would.
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import CoreColor

/// The values levels and curves read and write: linear light, or the
/// sRGB-encoded values a display shows (mid grey near 0.5), the way photo
/// editors' tone controls work.
public enum ToneEncoding: Hashable, Sendable {
    case linear
    case sRGB
}

/// One control point of a tone curve: input `x` maps to output `y`.
public struct CurvePoint: Hashable, Sendable {
    public var x: Float
    public var y: Float

    public init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }
}

extension PixelBuffer {
    /// Multiplies every linear color value by 2^`stops`. Throws for a
    /// non-finite `stops` or a result that overflows.
    public func exposure(stops: Float) throws -> PixelBuffer {
        guard stops.isFinite else {
            throw RasterError.invalid("exposure \(stops) stops: must be finite")
        }
        if stops == 0 { return self }
        let factor = Float(pow(2, Double(stops)))
        guard factor.isFinite else {
            throw RasterError.invalid("exposure \(stops) stops: factor overflows")
        }
        return try mappingColor { $0 * factor }
    }

    /// Levels: values at or below `inBlack` become `outBlack`, `inWhite`
    /// becomes `outWhite`, with `gamma` (over 1 brightens) applied between.
    /// Values above `inWhite` are not clipped. With `encoding` `.sRGB` every
    /// parameter is an sRGB-encoded value. Throws for a non-finite
    /// parameter, `inBlack >= inWhite` or `gamma <= 0`.
    public func levels(inBlack: Float, inWhite: Float, gamma: Float,
                       outBlack: Float, outWhite: Float, encoding: ToneEncoding = .linear) throws -> PixelBuffer {
        let params = [inBlack, inWhite, gamma, outBlack, outWhite]
        guard params.allSatisfy(\.isFinite) else {
            throw RasterError.invalid("levels \(params): every parameter must be finite")
        }
        guard inBlack < inWhite else {
            throw RasterError.invalid("levels: inBlack \(inBlack) must be below inWhite \(inWhite)")
        }
        guard gamma > 0 else {
            throw RasterError.invalid("levels: gamma \(gamma) must be above 0")
        }
        if params == [0, 1, 1, 0, 1] { return self }
        let inRange = Double(inWhite) - Double(inBlack)
        let outRange = Double(outWhite) - Double(outBlack)
        let exponent = 1 / Double(gamma)
        return try mappingColor(encoding) { value in
            let t = max((Double(value) - Double(inBlack)) / inRange, 0)
            return Float(Double(outBlack) + outRange * pow(t, exponent))
        }
    }

    /// Curves: a monotone cubic (Fritsch-Carlson) through `points`, applied to
    /// each color channel. Outside the first and last x the curve continues in
    /// a straight line along its end tangent. With `encoding` `.sRGB` the
    /// points are sRGB-encoded values. Throws for fewer than 2 points,
    /// a non-finite coordinate, an x outside 0...1, or x not strictly increasing.
    public func curves(points: [CurvePoint], encoding: ToneEncoding = .linear) throws -> PixelBuffer {
        let curve = try MonotoneCurve(points)
        if points.allSatisfy({ $0.x == $0.y }) { return self }
        return try mappingColor(encoding, curve.value)
    }

    /// White balance: per-channel gains on linear color. A positive
    /// `temperature` warms (red up, blue down); a positive `tint` pushes toward
    /// magenta (green down). At 100 a channel moves by half a stop before the
    /// gains are scaled so their Rec. 709 luminance is 1, which keeps a neutral
    /// grey's luminance. Both in -100...100.
    public func whiteBalance(temperature: Float, tint: Float) throws -> PixelBuffer {
        try Self.checkSlider("temperature", temperature)
        try Self.checkSlider("tint", tint)
        if temperature == 0, tint == 0 { return self }
        let warm = Double(temperature) / 200, magenta = Double(tint) / 200
        let r = pow(2, warm), g = pow(2, -magenta), b = pow(2, -warm)
        let w = Histogram.luminanceWeights
        let norm = Double(w.r) * r + Double(w.g) * g + Double(w.b) * b
        let gains = (r: Float(r / norm), g: Float(g / norm), b: Float(b / norm))
        return try mappingPixels { RGBA(r: $0.r * gains.r, g: $0.g * gains.g, b: $0.b * gains.b, a: $0.a) }
    }

    /// Contrast: an S curve through 0, mid grey (0.18, kept exactly) and 1 (a
    /// `MonotoneCurve`, as in `curves`), so it is monotonic. Positive `amount`
    /// pushes values away from mid grey, negative pulls them toward it.
    /// Outside 0...1 (unclipped linear values) it continues in a straight line
    /// from 0 and from 1 with slope 1 + amount/200, so those values move the
    /// same way: over 1 for more contrast, under 1 for less. -100...100.
    public func contrast(_ amount: Float) throws -> PixelBuffer {
        try Self.checkSlider("contrast", amount)
        if amount == 0 { return self }
        let push = amount / 200
        let curve = try MonotoneCurve([
            CurvePoint(x: 0, y: 0),
            CurvePoint(x: 0.09, y: 0.09 * (1 - push)),
            CurvePoint(x: 0.18, y: 0.18),
            CurvePoint(x: 0.59, y: 0.59 + 0.41 * push),
            CurvePoint(x: 1, y: 1),
        ])
        let outerSlope = 1 + push
        // Tabulated once over 0...1 and read with linear interpolation:
        // evaluating the curve for every channel of every pixel took 24 MP
        // over 1 s (issue #255). Every control point's x is a table entry, so
        // each step lies inside one cubic piece and stays within 1e-6 of it.
        let steps = Self.contrastTableSteps
        let table = (0...steps).map { curve.value(Float($0) / Float(steps)) }
        // A local function rather than `mappingColor`'s closure, so the
        // compiler can inline the table read into the pixel loop.
        func channel(_ value: Float) -> Float {
            if value > 1 { return 1 + outerSlope * (value - 1) }
            // A NaN fails this test too, so it maps to NaN and throws.
            guard value >= 0 else { return outerSlope * value }
            let f = value * Float(steps)
            let i = min(Int(f), steps - 1)
            let low = Double(table[i])
            // Interpolated in Double so it never rounds past the next entry.
            return Float(low + (Double(table[i + 1]) - low) * Double(f - Float(i)))
        }
        return try mappingPixels { RGBA(r: channel($0.r), g: channel($0.g), b: channel($0.b), a: $0.a) }
    }

    /// Steps in contrast's curve table: a multiple of 100, so its control
    /// points at 0.09, 0.18 and 0.59 fall on entries.
    static let contrastTableSteps = 4000

    /// Highlights and shadows: an exposure change of up to one stop at 100,
    /// weighted per pixel by its Rec. 709 luminance with a smoothstep falloff.
    /// `highlights` acts above mid grey (0.18) and `shadows` below 0.5, so
    /// each leaves the other end of the range alone. Both in -100...100.
    public func highlightsShadows(highlights: Float, shadows: Float) throws -> PixelBuffer {
        try Self.checkSlider("highlights", highlights)
        try Self.checkSlider("shadows", shadows)
        if highlights == 0, shadows == 0 { return self }
        let w = Histogram.luminanceWeights
        return try mappingPixels { p in
            let luma = w.r * p.r + w.g * p.g + w.b * p.b
            let stops = highlights / 100 * Self.smoothstep(0.18, 1, luma)
                + shadows / 100 * (1 - Self.smoothstep(0, 0.5, luma))
            let gain = Float(pow(2, Double(stops)))
            return RGBA(r: p.r * gain, g: p.g * gain, b: p.b * gain, a: p.a)
        }
    }

    /// Throws unless `value` is a finite develop-slider value in -100...100.
    private static func checkSlider(_ name: String, _ value: Float) throws {
        guard value.isFinite, (-100...100).contains(value) else {
            throw RasterError.invalid("\(name) \(value): must be in -100...100")
        }
    }

    /// 0 at or below `edge0`, 1 at or above `edge1`, a smooth cubic between.
    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Steps in the table an sRGB tone mapping reads for values in 0...1.
    static let toneTableSteps = 4096

    /// Maps each straight color channel through `transfer`, keeping alpha.
    /// With `.sRGB`, `transfer` sees and returns encoded values. The whole
    /// encode, map, decode is tabulated once over 0...1, at steps even in the
    /// value's square root, and read with linear interpolation there (two pows
    /// per value made it five times slower); values outside 0...1 are mapped
    /// exactly.
    private func mappingColor(_ encoding: ToneEncoding = .linear, _ transfer: (Float) -> Float) throws -> PixelBuffer {
        try withoutActuallyEscaping(transfer) { transfer in
            let channel: (Float) -> Float
            switch encoding {
            case .linear:
                channel = transfer
            case .sRGB:
                let exact = { (v: Float) -> Float in Float(TransferCurve.decode(Double(transfer(Float(TransferCurve.encode(Double(v))))))) }
                let steps = Self.toneTableSteps
                // Spaced by the square root of the value, so the steps near
                // black, where the transfer curve is steepest, are fine.
                let table = (0...steps).map { (i: Int) -> Float in
                    let u = Float(i) / Float(steps)
                    return exact(u * u)
                }
                channel = { v in
                    guard v >= 0, v <= 1 else { return exact(v) }
                    let f = v.squareRoot() * Float(steps)
                    let i = min(Int(f), steps - 1)
                    return table[i] + (table[i + 1] - table[i]) * (f - Float(i))
                }
            }
            return try mappingPixels { RGBA(r: channel($0.r), g: channel($0.g), b: channel($0.b), a: $0.a) }
        }
    }

    /// Maps each straight pixel through `transform`, which must keep alpha.
    /// One pass over the storage, without the per-pixel bounds checks of
    /// `pixel` / `setPixel` (issue #248), writing each result once into new
    /// storage rather than into a copy of the input (issue #255: the copy cost
    /// as much as the mapping on 24 MP); like `setPixel` it throws for a
    /// non-finite result.
    @inline(__always)
    private func mappingPixels(_ transform: (RGBA) -> RGBA) throws -> PixelBuffer {
        let source = components
        let channels = Self.channels
        let storage = try [Float](unsafeUninitializedCapacity: source.count) { output, initialized in
            for i in stride(from: 0, to: source.count, by: channels) {
                let p = RGBA(r: source[i], g: source[i + 1], b: source[i + 2], a: source[i + 3])
                let mapped = transform(p.unpremultiplied()).premultiplied()
                guard mapped.isFinite else {
                    let n = i / channels
                    throw RasterError.invalid("pixel \(mapped) at (\(n % width), \(n / width)): components must be finite")
                }
                output[i] = mapped.r
                output[i + 1] = mapped.g
                output[i + 2] = mapped.b
                output[i + 3] = mapped.a
                // Counted per pixel, so a throw leaves no uninitialized element counted.
                initialized = i + channels
            }
        }
        return PixelBuffer(checkedWidth: width, height: height, storage: storage)
    }
}

/// A piecewise cubic Hermite curve with Fritsch-Carlson tangents, so it is
/// monotone wherever its control points are. Computed in Double.
struct MonotoneCurve {
    private let xs: [Double]
    private let ys: [Double]
    private let tangents: [Double]

    init(_ points: [CurvePoint]) throws {
        guard points.count >= 2 else {
            throw RasterError.invalid("curve has \(points.count) points: needs at least 2")
        }
        for (i, p) in points.enumerated() {
            guard p.x.isFinite, p.y.isFinite, (0...1).contains(p.x) else {
                throw RasterError.invalid("curve point \(i) (\(p.x), \(p.y)): x must be in 0...1, y finite")
            }
            if i > 0, points[i - 1].x >= p.x {
                throw RasterError.invalid("curve point \(i): x \(p.x) must be above the previous x")
            }
        }
        let xs = points.map { Double($0.x) }
        let ys = points.map { Double($0.y) }
        let secants: [Double] = (0..<(xs.count - 1)).map { k in
            let rise = ys[k + 1] - ys[k]
            return rise / (xs[k + 1] - xs[k])
        }
        var m = [Double](repeating: 0, count: xs.count)
        m[0] = secants[0]
        m[xs.count - 1] = secants[secants.count - 1]
        for k in 1..<(xs.count - 1) where secants[k - 1] * secants[k] > 0 {
            m[k] = (secants[k - 1] + secants[k]) / 2
        }
        for (k, d) in secants.enumerated() {
            if d == 0 {
                m[k] = 0
                m[k + 1] = 0
                continue
            }
            let alpha: Double = m[k] / d, beta: Double = m[k + 1] / d
            let length = alpha * alpha + beta * beta
            if length > 9 {
                let tau: Double = 3 / length.squareRoot()
                m[k] = tau * alpha * d
                m[k + 1] = tau * beta * d
            }
        }
        self.xs = xs
        self.ys = ys
        tangents = m
    }

    /// The curve's value at `v`.
    func value(_ v: Float) -> Float {
        let x = Double(v)
        let last = xs.count - 1
        if x <= xs[0] { return Float(ys[0] + tangents[0] * (x - xs[0])) }
        if x >= xs[last] { return Float(ys[last] + tangents[last] * (x - xs[last])) }
        // Binary search for the segment k with xs[k] <= x < xs[k + 1].
        var lo = 0, hi = last
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if xs[mid] <= x { lo = mid } else { hi = mid }
        }
        let h = xs[hi] - xs[lo]
        let t = (x - xs[lo]) / h
        let t2 = t * t, t3 = t2 * t
        let h00 = 2 * t3 - 3 * t2 + 1, h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2, h11 = t3 - t2
        return Float(h00 * ys[lo] + h10 * h * tangents[lo] + h01 * ys[hi] + h11 * h * tangents[hi])
    }
}
