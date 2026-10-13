// Adjustments.swift: tone adjustments on a PixelBuffer: exposure, levels and
// curves, plus the shared per-pixel loop (`mappingStraight`) that the develop
// adjustments in `Develop.swift` use too. Each one maps every color channel through one transfer function on
// unpremultiplied linear values (`RGBA.unpremultiplied`), then premultiplies
// again (`RGBA.premultiplied`). Alpha is never changed. Parameters are checked
// before any pixel is touched and throw `RasterError.invalid`; identity
// parameters return the input unchanged, bit for bit; a result component that
// overflows to infinity throws (from `setPixel`).
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

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
    /// Values above `inWhite` are not clipped. Throws for a non-finite
    /// parameter, `inBlack >= inWhite` or `gamma <= 0`.
    public func levels(inBlack: Float, inWhite: Float, gamma: Float,
                       outBlack: Float, outWhite: Float) throws -> PixelBuffer {
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
        return try mappingColor { value in
            let t = max((Double(value) - Double(inBlack)) / inRange, 0)
            return Float(Double(outBlack) + outRange * pow(t, exponent))
        }
    }

    /// Curves: a monotone cubic (Fritsch-Carlson) through `points`, applied to
    /// each color channel. Outside the first and last x the curve continues in
    /// a straight line along its end tangent. Throws for fewer than 2 points,
    /// a non-finite coordinate, an x outside 0...1, or x not strictly increasing.
    public func curves(points: [CurvePoint]) throws -> PixelBuffer {
        let curve = try MonotoneCurve(points)
        if points.allSatisfy({ $0.x == $0.y }) { return self }
        return try mappingColor(curve.value)
    }

    /// Maps each straight color channel through `transfer`, keeping alpha.
    func mappingColor(_ transfer: (Float) -> Float) throws -> PixelBuffer {
        try mappingStraight { RGBA(r: transfer($0.r), g: transfer($0.g), b: transfer($0.b), a: $0.a) }
    }

    /// The one per-pixel loop of the tone adjustments (here and in
    /// `Develop.swift`): maps each unpremultiplied pixel's color through
    /// `transform`, keeping its alpha, and premultiplies the result again.
    func mappingStraight(_ transform: (RGBA) -> RGBA) throws -> PixelBuffer {
        var result = self
        for y in 0..<height {
            for x in 0..<width {
                let p = try pixel(x: x, y: y).unpremultiplied()
                var mapped = transform(p)
                mapped.a = p.a
                try result.setPixel(x: x, y: y, mapped.premultiplied())
            }
        }
        return result
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
