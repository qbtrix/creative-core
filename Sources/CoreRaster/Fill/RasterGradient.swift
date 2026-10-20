// RasterGradient.swift: the raster gradient behind the gradient tool
// (fill-tools). Each pixel centre maps to a parameter `t` by the shape (FT-5),
// clamped to the stops (so to 0...1), and `t` picks a colour from the stops,
// interpolated in linear light or in OKLab through CoreColor, tabulated once
// per call. Alpha interpolates linearly. With `dither`, each pixel's straight
// colour then takes `GradientDither`'s ordered offset (FT-6), and the result
// is premultiplied.
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
    /// Mix the stops' linear-light sRGB components. Linear light, not the
    /// shape `RasterGradientShape.linear`.
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
    /// A `width` x `height` buffer filled with a gradient from `a` to `b`.
    ///
    /// - Parameters:
    ///   - width: at least 1; with `height`, a size `validatedSize` accepts.
    ///   - height: at least 1.
    ///   - shape: how a pixel centre maps to a parameter `t`, clamped to
    ///     0...1 (see each `RasterGradientShape` case).
    ///   - a: the start point, in pixel space; finite.
    ///   - b: the end point; finite and not equal to `a`.
    ///   - stops: 2...`maxGradientStops` stops, sorted by offset, offsets in
    ///     0...1, colours finite. Two stops at one offset make a hard edge: a
    ///     `t` exactly on it takes the later stop, as `gradientMap(_:)` does
    ///     (both read stops through `StopRamp`). Stop colours are straight
    ///     alpha in linear light (see `RasterGradientStop.color`).
    ///   - space: the space the stops interpolate in, not the shape. In
    ///     `gradient(..., shape: .linear, ..., space: .linear)` the first
    ///     `.linear` is the projection ramp and the second means linear-light
    ///     sRGB mixing; `.perceptual` mixes in OKLab.
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
                let straight = ramp.straight(at: t)
                let shown = dither ? GradientDither.dithered(straight, x: x, y: y) : straight
                let c = shown.premultiplied()
                guard c.isFinite else { throw RasterError.invalid("gradient colour \(shown): not finite in Float") }
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
    /// here: `StopRamp.segment(at:)` clamps it to the stops, which lie in 0...1.
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

/// Checked stops, with each segment's straight linear-light colour
/// tabulated once per call, so a pixel only finds its segment and lerps two
/// table entries. In linear light the mix is linear in `t`, so the lerp is
/// exact; in OKLab it is within 1e-5 of the exact mix.
private struct GradientRamp {
    let stops: StopRamp
    /// `samples + 1` straight (r, g, b, a) entries per segment, f = 0...1.
    let table: [Double]
    static let samples = 256

    init(stops: [RasterGradientStop], space: GradientSpace) throws {
        self.stops = try StopRamp(stops.map(\.offset), what: "gradient")
        for (k, stop) in stops.enumerated() where !stop.color.isFinite {
            throw RasterError.invalid("gradient stop \(k) colour \(stop.color): must be finite")
        }
        let colors = try stops.map { stop in
            let c = Color3(Double(stop.color.r), Double(stop.color.g), Double(stop.color.b))
            let inSpace = space == .perceptual
                ? try FillColor.converted(c, from: .linearSRGB, to: .oklab, what: "gradient stop colour \(c)") : c
            return (inSpace, Double(stop.color.a))
        }
        var table: [Double] = []
        table.reserveCapacity((colors.count - 1) * (Self.samples + 1) * 4)
        for ((c0, a0), (c1, a1)) in zip(colors, colors.dropFirst()) {
            for k in 0...Self.samples {
                let f = Double(k) / Double(Self.samples)
                let mixed = Color3(c0.c0 + (c1.c0 - c0.c0) * f, c0.c1 + (c1.c1 - c0.c1) * f, c0.c2 + (c1.c2 - c0.c2) * f)
                let linear = space == .perceptual
                    ? try FillColor.converted(mixed, from: .oklab, to: .linearSRGB, what: "gradient colour \(mixed)") : mixed
                table += [linear.c0, linear.c1, linear.c2, a0 + (a1 - a0) * f]
            }
        }
        self.table = table
    }

    /// The straight colour at `t`: the first stop's before it, the last
    /// stop's after it, else the mix of the two stops around `t`.
    func straight(at t: Double) -> RGBA {
        let (lo, f) = stops.segment(at: t)
        let u = f * Double(Self.samples), i = min(Int(u), Self.samples - 1), w = u - Double(i)
        let base = (lo * (Self.samples + 1) + i) * 4
        func at(_ c: Int) -> Float { Float(table[base + c] + (table[base + 4 + c] - table[base + c]) * w) }
        return RGBA(r: at(0), g: at(1), b: at(2), a: at(3))
    }
}
