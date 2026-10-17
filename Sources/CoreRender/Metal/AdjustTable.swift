// AdjustTable.swift: the Metal adjust kernel's data (metal-backend MB-13): exposure, levels and curves as
// what CoreRaster's own adjustment gives on a probe line, never a copy of its formulas. The probe is one
// row of opaque grey pixels run through `CPUBackend.adjusted`, so parameter checks and their messages are
// the CPU's. Exposure keeps the factor (the value at 1); levels and curves keep a table of `steps + 1`
// values at x = (i / steps)^2 over 0...1, spaced by the square root as CoreRaster's sRGB tone table is,
// read with linear interpolation, and outside 0...1 the line through the CPU's values at -1 and 0 (below)
// or 1 and 2 (above). `apply` and `map` are the kernel in Swift (Shaders/AdjustShader.swift mirrors
// them). White balance, contrast and highlights/shadows throw `unsupported(.adjust)` until MB-14.
import CoreRaster

/// One tone adjustment as the Float data the Metal adjust kernel uploads.
public struct AdjustTable: Equatable, Sendable {
    /// Table intervals over 0...1: CoreRaster's `toneTableSteps`.
    public static let steps = 4096

    /// The exposure factor; 1 for a table.
    public let scale: Float
    /// `steps + 1` mapped values at x = (i / steps)^2; empty for exposure.
    public let values: [Float]
    /// Slope of the map below 0 (the CPU's f(0) - f(-1)).
    public let below: Float
    /// Slope of the map above 1 (the CPU's f(2) - f(1)).
    public let above: Float

    /// The table for `adjustment`. Throws `unsupported(.adjust)` for the develop cases (MB-14) and the
    /// CPU backend's `RenderError.raster` for invalid parameters.
    public init(_ adjustment: ToneAdjustment) throws {
        switch adjustment {
        case .exposure, .levels, .curves: break
        case .whiteBalance, .contrast, .highlightsShadows: throw RenderError.unsupported(.adjust)
        }
        let steps = Self.steps
        let xs = (0...steps).map { (i: Int) -> Float in
            let u = Float(i) / Float(steps)
            return u * u
        } + [-1, 2]
        var probe = try RenderError.mapping { try PixelBuffer(width: xs.count, height: 1) }
        for (i, x) in xs.enumerated() {
            try RenderError.mapping { try probe.setPixel(x: i, y: 0, RGBA(r: x, g: x, b: x, a: 1)) }
        }
        let cpu = CPUBackend()
        let mapped = try cpu.read(cpu.adjusted(cpu.surface(probe), adjustment))
        let ys = try (0..<xs.count).map { i in try RenderError.mapping { try mapped.pixel(x: i, y: 0).r } }
        if case .exposure = adjustment {
            (scale, values, below, above) = (ys[steps], [], 0, 0)
        } else {
            (scale, values) = (1, Array(ys[0...steps]))
            (below, above) = (ys[0] - ys[steps + 1], ys[steps + 2] - ys[steps])
        }
    }

    /// One straight color value through the map, as the kernel reads it.
    public func apply(_ v: Float) -> Float {
        let n = values.count - 1
        guard n >= 1 else { return v * scale }
        guard v >= 0 else { return values[0] + below * v }
        if v > 1 { return values[n] + above * (v - 1) }
        let f = v.squareRoot() * Float(n)
        let i = min(Int(f), n - 1)
        return values[i] + (values[i + 1] - values[i]) * (f - Float(i))
    }

    /// One premultiplied pixel, as the kernel maps it: CoreRaster's alpha guard (alpha 0 gives zeros),
    /// unpremultiply, `apply` per color channel, premultiply; alpha unchanged.
    public func map(_ p: RGBA) -> RGBA {
        let s = p.unpremultiplied()
        return RGBA(r: apply(s.r), g: apply(s.g), b: apply(s.b), a: s.a).premultiplied()
    }
}
