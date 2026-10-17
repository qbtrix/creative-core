// AdjustTable.swift: the Metal adjust kernel's data (metal-backend MB-13, MB-14): every `ToneAdjustment` as
// what CoreRaster's own adjustment gives on probe lines, never a copy of its formulas. Each probe is a row of
// opaque pixels run through `CPUBackend.adjusted`, so parameter checks and their messages are the CPU's.
// Three kinds: `gains` (exposure, white balance) keeps the per-channel factors (the CPU's output for white
// 1, 1, 1); `channel` (levels, curves, contrast) keeps a table of `steps + 1` values at x = (i / steps)^2 over
// 0...1 from grey pixels, spaced by the square root as CoreRaster's sRGB tone table is, read with linear
// interpolation, and outside 0...1 two octave tables (`below` at -x, `above` at +x) of `perOctave` steps per
// power of two for |x| from 2^`octaveMin` to 2^`octaveMax`, read by the float's exponent and mantissa, so a
// bent map past 1 (levels with a gamma other than 1, sRGB-encoded levels and curves) follows the CPU there
// too; `luma` (highlights/shadows) keeps the gain at each Rec. 709 luminance (the red output of a pixel with
// red 1, blue 0 and green setting the luminance), constant outside 0...1 where CoreRaster's smoothsteps clamp.
// Only the 0...1 probe can throw: the octave probe tolerates overflow (an octave whose value overflows on the
// CPU, which would throw for such a pixel, holds the largest finite Float with the map's direction), and the
// gains and luma kinds probe nothing outside 0...1. `apply` and `map` are the kernel in Swift
// (Shaders/AdjustShader.swift mirrors them).
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
    /// The octave tables start at |x| = 2^octaveMin; below it, down to 0, the kernel reads the line to f(0).
    public static let octaveMin = -24
    /// The octave tables end at |x| = 2^octaveMax, past any straight value of a finite half pixel
    /// (65504 / 2^-24 < 2^40); beyond it the kernel extends the last interval's line.
    public static let octaveMax = 40
    /// Linear-interpolation intervals per power of two in the octave tables.
    public static let perOctave = 128
    /// Entries of each octave table: one per interval start, plus 2^octaveMax.
    public static let octaveCount = (octaveMax - octaveMin) * perOctave + 1
    /// CoreRaster's Rec. 709 luminance weights (`Histogram.luminanceWeights`), the `luma` kind's input.
    public static let lumaWeights = SIMD3<Float>(Histogram.luminanceWeights.r, Histogram.luminanceWeights.g,
                                                 Histogram.luminanceWeights.b)

    /// How `map` (and the kernel) reads `gains`, `values`, `below` and `above`, from the adjustment's case.
    public let kind: Kind
    /// The per-channel factors for `gains`; 1, 1, 1 otherwise.
    public let gains: SIMD3<Float>
    /// `steps + 1` mapped values (or gains, for `luma`) at x = (i / steps)^2; empty for `gains`.
    public let values: [Float]
    /// For `channel`, `octaveCount` CPU values at x = -`octaveX(k)`; empty otherwise (luma is constant there).
    public let below: [Float]
    /// For `channel`, `octaveCount` CPU values at x = `octaveX(k)`; empty otherwise (luma is constant there).
    public let above: [Float]

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
        }
        let w = Histogram.luminanceWeights
        let kind = self.kind
        let ys = try Self.probe(xs, adjustment) { x in
            kind == .luma ? RGBA(r: 1, g: (x - w.r) / w.g, b: 0, a: 1) : RGBA(r: x, g: x, b: x, a: 1)
        }
        switch kind {
        case .gains:
            (gains, values, below, above) = (SIMD3(ys[steps].r, ys[steps].g, ys[steps].b), [], [], [])
        case .channel:
            (gains, values) = (SIMD3(repeating: 1), ys.map(\.r))
            below = Self.octaves(-1, zero: ys[0].r, edge: ys[0].r, adjustment)
            above = Self.octaves(1, zero: ys[0].r, edge: ys[steps].r, adjustment)
        case .luma:
            (gains, values, below, above) = (SIMD3(repeating: 1), ys.map(\.r), [], [])
        }
    }

    /// |x| of octave-table entry `k`: 2^(octaveMin + k / perOctave) times 1 + (k % perOctave) / perOctave.
    public static func octaveX(_ k: Int) -> Float {
        let fraction = Float(k % perOctave) / Float(perOctave)
        return Float(sign: .plus, exponent: octaveMin + k / perOctave, significand: 1 + fraction)
    }

    /// The CPU's output for `pixel(x)` at each of `xs`, one opaque row.
    private static func probe(_ xs: [Float], _ adjustment: ToneAdjustment, _ pixel: (Float) -> RGBA) throws -> [RGBA] {
        var row = try RenderError.mapping { try PixelBuffer(width: xs.count, height: 1) }
        for (i, x) in xs.enumerated() { try RenderError.mapping { try row.setPixel(x: i, y: 0, pixel(x)) } }
        let cpu = CPUBackend()
        let mapped = try cpu.read(cpu.adjusted(cpu.surface(row), adjustment))
        return try (0..<xs.count).map { i in try RenderError.mapping { try mapped.pixel(x: i, y: 0) } }
    }

    /// The octave table on the `sign` side: the CPU's values at sign * `octaveX(k)`. The parameters already
    /// passed the 0...1 probe, so a throw here is an overflow: that octave and every later one hold the
    /// largest finite Float in the map's direction: the sign of its last finite value less `zero` (f(0)), or of
    /// `edge` (f(1) above) less it when the first octave overflows.
    private static func octaves(_ sign: Float, zero: Float, edge: Float, _ adjustment: ToneAdjustment) -> [Float] {
        let xs = (0..<octaveCount).map { sign * octaveX($0) }
        let grey = { (x: Float) in RGBA(r: x, g: x, b: x, a: 1) }
        if let all = try? probe(xs, adjustment, grey) { return all.map(\.r) }
        var out = [Float]()
        out.reserveCapacity(octaveCount)
        var start = 0
        while start < octaveCount {
            let end = min(start + perOctave, octaveCount)
            guard let chunk = try? probe(Array(xs[start..<end]), adjustment, grey) else { break }
            out += chunk.map(\.r)
            start = end
        }
        let toward: Float = (out.last ?? edge) < zero ? -1 : 1
        return out + [Float](repeating: toward * .greatestFiniteMagnitude, count: octaveCount - out.count)
    }

    /// One value through the table, as the kernel reads it; `v` unchanged without a table. Outside 0...1 the
    /// octave table of that side, or the constant end value without one (`luma`).
    public func apply(_ v: Float) -> Float {
        let n = values.count - 1
        guard n >= 1 else { return v }
        guard v >= 0 else { return below.isEmpty ? values[0] : Self.octave(below, -v, zero: values[0]) }
        if v > 1 { return above.isEmpty ? values[n] : Self.octave(above, v, zero: values[0]) }
        let f = v.squareRoot() * Float(n)
        let i = min(Int(f), n - 1)
        return values[i] + (values[i + 1] - values[i]) * (f - Float(i))
    }

    /// `table` at |x| = `a` > 0: entry index from the float's exponent, interpolated on its mantissa; under
    /// 2^octaveMin the line from `zero` (f(0)) to the first entry, past 2^octaveMax the last interval's line.
    private static func octave(_ table: [Float], _ a: Float, zero: Float) -> Float {
        let last = table.count - 1
        guard last >= 1 else { return zero }
        let bits = a.bitPattern
        let octave = Int((bits >> 23) & 0xFF) - 127 - octaveMin
        if octave < 0 { return zero + (table[0] - zero) * (a / octaveX(0)) }
        if octave >= octaveMax - octaveMin {
            let (x0, x1) = (octaveX(last - 1), octaveX(last))
            return table[last - 1] + (table[last] - table[last - 1]) * ((a - x0) / (x1 - x0))
        }
        let f = Float(bits & 0x7F_FFFF) / Float(1 << 23) * Float(perOctave)
        let j = min(Int(f), perOctave - 1)
        let i = octave * perOctave + j
        guard i + 1 <= last else { return table[last] }
        return table[i] + (table[i + 1] - table[i]) * (f - Float(j))
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
