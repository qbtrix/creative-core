// ColorMap.swift: gradient map, 3D LUT apply, posterize, threshold and invert
// on a PixelBuffer, the tone-pack contract slice (docs/blueprints/core/features/tone-pack.md).
// Working space: `gradientMap`, `applying`, `posterized` and `thresholded`
// run on straight sRGB-encoded values (CoreColor's `TransferCurve`), clamped
// to 0...1, with Rec. 709 luma on those values, then decode and premultiply
// (`mappingStraight`); `inverted` runs on the linear premultiplied components.
// Alpha is never changed and an alpha-0 pixel passes through untouched.
// Parameters are checked before any pixel is touched and a bad one throws
// `RasterError.invalid`.
extension PixelBuffer {
    /// The stop counts a gradient map accepts.
    private static let gradientStops = 2...64

    /// Rec. 709 luma of the sRGB-encoded (not linear) straight colour, 0...1,
    /// mapped through 2...64 stops, sorted by offset (equal offsets make a
    /// hard edge), each offset finite and in 0...1. Between two stops the
    /// encoded colour is interpolated linearly; below the first stop or above
    /// the last, that stop's colour holds. Stop colours are clamped to 0...1.
    public func gradientMap(_ stops: [GradientMapStop]) throws -> PixelBuffer {
        guard Self.gradientStops.contains(stops.count) else {
            throw RasterError.invalid("gradientMap with \(stops.count) stops: needs \(Self.gradientStops)")
        }
        // Each error names the failing stop by its index in `stops`.
        for (i, s) in stops.enumerated() {
            guard s.offset.isFinite, (0...1).contains(s.offset) else {
                throw RasterError.invalid("gradientMap stop \(i) offset \(s.offset): must be in 0...1")
            }
            if i > 0, s.offset < stops[i - 1].offset {
                throw RasterError.invalid("gradientMap stop \(i) offset \(s.offset): below stop \(i - 1) offset "
                    + "\(stops[i - 1].offset), stops must be sorted by offset")
            }
            try Self.checkFinite("gradientMap stop \(i) colour", [s.color.r, s.color.g, s.color.b])
        }
        let offsets = stops.map(\.offset)
        let colors = stops.map {
            SIMD3($0.color.r, $0.color.g, $0.color.b).clamped(lowerBound: .zero, upperBound: .one)
        }
        let luma = Self.lumaWeights
        return try mappingStraight { p in
            let l = (SIMD3<Float>(Self.encoded(p)) * luma).sum()
            var hi = 0
            while hi < offsets.count, offsets[hi] < l { hi += 1 }
            let out: SIMD3<Float>
            if hi == 0 {
                out = colors[0]
            } else if hi == offsets.count {
                out = colors[hi - 1]
            } else {
                let t = (l - offsets[hi - 1]) / (offsets[hi] - offsets[hi - 1])
                out = colors[hi - 1] + (colors[hi] - colors[hi - 1]) * t
            }
            return Self.decoded(out, a: p.a)
        }
    }

    /// Trilinear lookup on the encoded values; the result is clamped to 0...1.
    /// The `ColorLUT` is validated when it is made and the result is clamped,
    /// so this throws `RasterError.invalid` only for a non-finite result, which
    /// a valid buffer and LUT cannot produce.
    public func applying(_ lut: ColorLUT) throws -> PixelBuffer {
        let n = lut.size, table = lut.table
        // Table offset of one step along red, green and blue: red fastest.
        let step = SIMD3(1, n, n * n)
        return try mappingStraight { p in
            let x = Self.encoded(p) * Double(n - 1)
            let i = SIMD3(min(Int(x.x), n - 2), min(Int(x.y), n - 2), min(Int(x.z), n - 2))
            let f = x - SIMD3(Double(i.x), Double(i.y), Double(i.z))
            let base = (i &* step).wrappedSum()
            func at(_ dr: Int, _ dg: Int, _ db: Int) -> SIMD3<Double> {
                SIMD3<Double>(table[base + dr * step.x + dg * step.y + db * step.z])
            }
            func lerp(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ t: Double) -> SIMD3<Double> { a + (b - a) * t }
            let g0 = lerp(lerp(at(0, 0, 0), at(1, 0, 0), f.x), lerp(at(0, 1, 0), at(1, 1, 0), f.x), f.y)
            let g1 = lerp(lerp(at(0, 0, 1), at(1, 0, 1), f.x), lerp(at(0, 1, 1), at(1, 1, 1), f.x), f.y)
            let out = lerp(g0, g1, f.z).clamped(lowerBound: .zero, upperBound: .one)
            return Self.decoded(SIMD3<Float>(out), a: p.a)
        }
    }

    /// The level counts posterize accepts.
    private static let posterLevels = 2...255

    /// Each encoded channel rounded to the nearer of `levels` evenly spaced
    /// values in 0...1; `levels` in 2...255.
    public func posterized(levels: Int) throws -> PixelBuffer {
        guard Self.posterLevels.contains(levels) else {
            throw RasterError.invalid("posterize levels \(levels): must be in \(Self.posterLevels)")
        }
        let steps = Float(levels - 1)
        return try mappingStraight { p in
            let c = SIMD3<Float>(Self.encoded(p)) * steps
            return Self.decoded(c.rounded(.toNearestOrAwayFromZero) / steps, a: p.a)
        }
    }

    /// White where the encoded luma is at least `level` (0...1), else black.
    public func thresholded(_ level: Float) throws -> PixelBuffer {
        guard level.isFinite, (0...1).contains(level) else {
            throw RasterError.invalid("threshold \(level): must be in 0...1")
        }
        let luma = Self.lumaWeights
        return try mappingStraight { p in
            let l = (SIMD3<Float>(Self.encoded(p)) * luma).sum()
            let v: Float = l >= level ? 1 : 0
            return RGBA(r: v, g: v, b: v, a: p.a)
        }
    }

    /// Inverts in linear premultiplied space (not sRGB-encoded): each colour
    /// component c becomes a − c against its own alpha a, which is 1 minus the
    /// straight linear colour, so inverting twice gives the input back. Alpha is
    /// kept, and an alpha-0 pixel passes through untouched, whatever colour it
    /// stores. An a − c that overflows a finite input is clamped to the largest
    /// finite Float, so the result stays finite.
    public func inverted() -> PixelBuffer {
        var out = components
        let big = Float.greatestFiniteMagnitude
        func invert(_ a: Float, _ c: Float) -> Float { min(max(a - c, -big), big) }
        for base in stride(from: 0, to: out.count, by: Self.channels) where out[base + 3] != 0 {
            let a = out[base + 3]
            (out[base], out[base + 1], out[base + 2]) = (invert(a, out[base]), invert(a, out[base + 1]), invert(a, out[base + 2]))
        }
        return PixelBuffer(checkedWidth: width, height: height, storage: out)
    }

    /// Rec. 709 luma weights as a vector.
    private static var lumaWeights: SIMD3<Float> {
        let w = Histogram.luminanceWeights
        return SIMD3(w.r, w.g, w.b)
    }
}
