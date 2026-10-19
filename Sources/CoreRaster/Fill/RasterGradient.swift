// RasterGradient.swift: the raster gradient behind the gradient tool
// (fill-tools). Each pixel centre maps to a parameter `t` by the shape (FT-5),
// clamped to the stops (so to 0...1), and `t` picks a colour from the stops,
// interpolated in linear light or in OKLab through CoreColor. Alpha
// interpolates linearly and the result is premultiplied. With `dither`, each
// pixel then takes `GradientDither`'s ordered offset (FT-6).
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import CoreColor

/// The space a gradient interpolates its stops in: linear light, or OKLab
/// (perceptual). Not the ramp's shape: that is `RasterGradientShape`.
public enum GradientSpace: Hashable, Sendable {
    /// Mix the stops' linear-light sRGB components.
    case linear
    /// Mix the stops in OKLab (perceptually even).
    case perceptual
}

/// One stop of a raster gradient: a colour (straight alpha) at an offset.
public struct RasterGradientStop: Hashable, Sendable {
    /// Where the stop sits along the gradient, in 0...1.
    public var offset: Float
    /// The stop's colour and alpha: straight (not premultiplied) alpha,
    /// linear-light sRGB (not sRGB-encoded). A colour read from a buffer,
    /// such as `sampledColor`'s, is premultiplied: call `.unpremultiplied()`
    /// on it before using it here.
    public var color: RGBA

    /// A stop at `offset` whose `color` is straight (not premultiplied)
    /// alpha, in linear-light sRGB.
    public init(offset: Float, color: RGBA) {
        self.offset = offset
        self.color = color
    }
}

extension PixelBuffer {
    /// The most stops a gradient takes.
    static let maxGradientStops = 64

    /// A `width` x `height` buffer filled with a gradient from `a` to `b`.
    ///
    /// - Parameters:
    ///   - width: at least 1; with `height`, a size `validatedSize` accepts.
    ///   - height: at least 1.
    ///   - shape: how a pixel centre maps to a parameter `t`, clamped to
    ///     0...1 (see each `RasterGradientShape` case).
    ///   - a: the start point, in pixel space; finite.
    ///   - b: the end point; finite and not equal to `a`.
    ///   - stops: 2...64 stops, sorted by offset, offsets in 0...1, colours
    ///     finite. Two stops at one offset make a hard edge. Stop colours are
    ///     straight alpha in linear light (see `RasterGradientStop.color`).
    ///   - space: the space the stops interpolate in.
    ///   - dither: `true` adds a deterministic ordered dither of +-0.5/255 so
    ///     an 8-bit encode does not band (`GradientDither`).
    /// - Returns: the gradient, premultiplied like any buffer.
    /// - Throws: `RasterError.invalid` for a bad size, points or stops.
    public static func gradient(width: Int, height: Int, shape: RasterGradientShape, from a: Mask.Point, to b: Mask.Point,
                                stops: [RasterGradientStop], space: GradientSpace = .perceptual,
                                dither: Bool = true) throws -> PixelBuffer {
        let pixels = try validatedSize(width: width, height: height)
        guard a.x.isFinite, a.y.isFinite, b.x.isFinite, b.y.isFinite else {
            throw RasterError.invalid("gradient points \(a), \(b): must be finite")
        }
        let (vx, vy) = (b.x - a.x, b.y - a.y)
        let length2 = vx * vx + vy * vy
        guard length2 > 0, length2.isFinite else {
            throw RasterError.invalid("gradient points \(a), \(b): must be distinct and finitely apart")
        }
        let ramp = try GradientRamp(stops: stops, space: space)
        var storage = [Float](repeating: 0, count: pixels * channels)
        for y in 0..<height {
            for x in 0..<width {
                let (dx, dy) = (Double(x) + 0.5 - a.x, Double(y) + 0.5 - a.y)
                let t = gradientT(shape, dx: dx, dy: dy, vx: vx, vy: vy, length2: length2)
                let c = dither ? GradientDither.dithered(try ramp.color(at: t), x: x, y: y) : try ramp.color(at: t)
                let i = (y * width + x) * channels
                storage[i] = c.r
                storage[i + 1] = c.g
                storage[i + 2] = c.b
                storage[i + 3] = c.a
            }
        }
        return PixelBuffer(checkedWidth: width, height: height, storage: storage)
    }

    /// The shape's `t` for a pixel centre at (`dx`, `dy`) from `a`, with
    /// `a→b` = (`vx`, `vy`) and `length2` its squared length. Not clamped
    /// here: `GradientRamp.color(at:)` clamps it to the stops, which lie in 0...1.
    static func gradientT(_ shape: RasterGradientShape, dx: Double, dy: Double,
                          vx: Double, vy: Double, length2: Double) -> Double {
        let along = (dx * vx + dy * vy) / length2
        switch shape {
        case .linear: return along
        case .radial: return (dx * dx + dy * dy).squareRoot() / length2.squareRoot()
        case .angle:
            let turn = (atan2(dy, dx) - atan2(vy, vx)) / (2 * Double.pi)
            return turn - turn.rounded(.down)
        case .reflected: return abs(along)
        case .diamond: return max(abs(along), abs((vx * dy - vy * dx) / length2))
        }
    }
}

/// Checked stops, with their colours already in the interpolation space.
private struct GradientRamp {
    let offsets: [Double]
    /// Each stop's colour in `space` (linear sRGB or OKLab) and its alpha.
    let colors: [(Color3, Double)]
    let space: GradientSpace

    init(stops: [RasterGradientStop], space: GradientSpace) throws {
        guard (2...PixelBuffer.maxGradientStops).contains(stops.count) else {
            throw RasterError.invalid("gradient has \(stops.count) stops: needs 2...\(PixelBuffer.maxGradientStops)")
        }
        var previous: Float = 0
        for (k, stop) in stops.enumerated() {
            guard (0...1).contains(stop.offset), stop.offset >= previous else {
                throw RasterError.invalid("gradient stop \(k) offset \(stop.offset): must be in 0...1 and sorted")
            }
            guard stop.color.isFinite else {
                throw RasterError.invalid("gradient stop \(k) colour \(stop.color): must be finite")
            }
            previous = stop.offset
        }
        self.space = space
        offsets = stops.map { Double($0.offset) }
        colors = try stops.map { stop in
            let c = Color3(Double(stop.color.r), Double(stop.color.g), Double(stop.color.b))
            let inSpace = space == .perceptual
                ? try FillColor.converted(c, from: .linearSRGB, to: .oklab, what: "gradient stop colour \(c)") : c
            return (inSpace, Double(stop.color.a))
        }
    }

    /// The premultiplied colour at `t` in 0...1: the first stop's before it,
    /// the last stop's after it, else the mix of the two stops around `t`.
    func color(at t: Double) throws -> RGBA {
        let last = offsets.count - 1
        let t = min(max(t, offsets[0]), offsets[last])
        guard t > offsets[0] else { return try finish(colors[0].0, colors[0].1) }
        // The segment holding t; at a hard edge the later stop wins.
        let lo = min(offsets.lastIndex { $0 <= t } ?? 0, last - 1), hi = lo + 1
        let span = offsets[hi] - offsets[lo]
        let f = span > 0 ? (t - offsets[lo]) / span : 1
        let (c0, a0) = colors[lo], (c1, a1) = colors[hi]
        let mixed = Color3(c0.c0 + (c1.c0 - c0.c0) * f, c0.c1 + (c1.c1 - c0.c1) * f, c0.c2 + (c1.c2 - c0.c2) * f)
        return try finish(mixed, a0 + (a1 - a0) * f)
    }

    /// Back to linear light, premultiplied, as a finite `RGBA`.
    private func finish(_ c: Color3, _ alpha: Double) throws -> RGBA {
        let linear = space == .perceptual
            ? try FillColor.converted(c, from: .oklab, to: .linearSRGB, what: "gradient colour \(c)") : c
        let out = RGBA(r: Float(linear.c0), g: Float(linear.c1), b: Float(linear.c2), a: Float(alpha)).premultiplied()
        guard out.isFinite else { throw RasterError.invalid("gradient colour \(out): not finite in Float") }
        return out
    }
}
