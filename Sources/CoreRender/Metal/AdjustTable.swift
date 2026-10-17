// AdjustTable.swift: the Metal adjust kernel's data (metal-backend MB-13, MB-14): every `ToneAdjustment` as
// what CoreRaster's own adjustment gives on a probe line, never a copy of its formulas. The probe is one row
// of opaque pixels run through `CPUBackend.adjusted`, so parameter checks and their messages are the CPU's.
// Three kinds: `gains` (exposure, white balance) keeps the per-channel factors (the CPU's output for white
// 1, 1, 1); `channel` (levels, curves, contrast) keeps a table of `steps + 1` values at x = (i / steps)^2 over
// 0...1 from grey pixels, spaced by the square root as CoreRaster's sRGB tone table is, read with linear
// interpolation, and outside 0...1 the line through the CPU's values at -1 and 0 (below) or 1 and 2 (above);
// `luma` (highlights/shadows) keeps the gain at each Rec. 709 luminance (the red output of a pixel with red 1,
// blue 0 and green setting the luminance), constant outside 0...1 where CoreRaster's smoothsteps clamp. Every
// MB-14 case is exact outside 0...1: white balance is a factor, contrast a line of slope 1 + amount/200 from
// 0 and from 1, highlights/shadows a constant gain. The secant is a bound only for linear curves and levels
// that bend past 1 (a gamma other than 1) and for sRGB-encoded maps (MB-13). `apply` and `map` are the kernel
// in Swift (Shaders/AdjustShader.swift mirrors them).
import CoreRaster

/// One tone adjustment as the Float data the Metal adjust kernel uploads.
public struct AdjustTable: Equatable, Sendable {
    /// How the kernel reads the table; the raw value is `AdjustParams.kind` in the shader.
    public enum Kind: UInt32, Sendable {
        /// Straight color times `gains`, per channel.
        case gains = 0
        /// Each straight color channel through the table.
        case channel = 1
        /// Straight color times the table's gain at the pixel's luminance (`lumaWeights`).
        case luma = 2
    }

    /// Table intervals over 0...1: CoreRaster's `toneTableSteps`.
    public static let steps = 4096
    /// CoreRaster's Rec. 709 luminance weights (`Histogram.luminanceWeights`), the `luma` kind's input.
    public static let lumaWeights = SIMD3<Float>(Histogram.luminanceWeights.r, Histogram.luminanceWeights.g,
                                                 Histogram.luminanceWeights.b)

    public let kind: Kind
    /// The per-channel factors for `gains`; 1, 1, 1 otherwise.
    public let gains: SIMD3<Float>
    /// `steps + 1` mapped values (or gains, for `luma`) at x = (i / steps)^2; empty for `gains`.
    public let values: [Float]
    /// Slope of the map below 0 (the CPU's f(0) - f(-1)); 0 for `luma`.
    public let below: Float
    /// Slope of the map above 1 (the CPU's f(2) - f(1)); 0 for `luma`.
    public let above: Float

    /// The table for `adjustment`. Throws the CPU backend's `RenderError.raster` for invalid parameters.
    public init(_ adjustment: ToneAdjustment) throws {
        switch adjustment {
        case .exposure, .whiteBalance: kind = .gains
        case .levels, .curves, .contrast: kind = .channel
        case .highlightsShadows: kind = .luma
        }
        let steps = Self.steps
        let xs = (0...steps).map { (i: Int) -> Float in
            let u = Float(i) / Float(steps)
            return u * u
        } + [-1, 2]
        let w = Histogram.luminanceWeights
        var probe = try RenderError.mapping { try PixelBuffer(width: xs.count, height: 1) }
        for (i, x) in xs.enumerated() {
            let pixel = kind == .luma ? RGBA(r: 1, g: (x - w.r) / w.g, b: 0, a: 1) : RGBA(r: x, g: x, b: x, a: 1)
            try RenderError.mapping { try probe.setPixel(x: i, y: 0, pixel) }
        }
        let cpu = CPUBackend()
        let mapped = try cpu.read(cpu.adjusted(cpu.surface(probe), adjustment))
        let ys = try (0..<xs.count).map { i in try RenderError.mapping { try mapped.pixel(x: i, y: 0) } }
        switch kind {
        case .gains:
            (gains, values, below, above) = (SIMD3(ys[steps].r, ys[steps].g, ys[steps].b), [], 0, 0)
        case .channel:
            (gains, values) = (SIMD3(repeating: 1), ys[0...steps].map(\.r))
            (below, above) = (ys[0].r - ys[steps + 1].r, ys[steps + 2].r - ys[steps].r)
        case .luma:
            (gains, values, below, above) = (SIMD3(repeating: 1), ys[0...steps].map(\.r), 0, 0)
        }
    }

    /// One value through the table, as the kernel reads it; `v` unchanged without a table.
    public func apply(_ v: Float) -> Float {
        let n = values.count - 1
        guard n >= 1 else { return v }
        guard v >= 0 else { return values[0] + below * v }
        if v > 1 { return values[n] + above * (v - 1) }
        let f = v.squareRoot() * Float(n)
        let i = min(Int(f), n - 1)
        return values[i] + (values[i + 1] - values[i]) * (f - Float(i))
    }

    /// One premultiplied pixel, as the kernel maps it: CoreRaster's alpha guard (alpha 0 gives zeros),
    /// unpremultiply, the kind's map on the straight color, premultiply; alpha unchanged.
    public func map(_ p: RGBA) -> RGBA {
        let s = p.unpremultiplied()
        let c = SIMD3(s.r, s.g, s.b)
        let out: SIMD3<Float>
        switch kind {
        case .gains: out = c * gains
        case .channel: out = SIMD3(apply(c.x), apply(c.y), apply(c.z))
        case .luma:
            let w = Self.lumaWeights
            out = c * apply(w.x * c.x + w.y * c.y + w.z * c.z)
        }
        return RGBA(r: out.x, g: out.y, b: out.z, a: s.a).premultiplied()
    }
}
