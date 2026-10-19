// AlphaEffects.swift: an alpha stroke outside, inside or centred on the
// layer's edge. The shape is the alpha >= 0.5 set; the distance to its edge is
// measured to the anti-aliased edge, not between pixel centres: every edge
// pixel (alpha strictly between 0 and 1, or a 0 / 1 pixel beside its
// opposite) gets a sub-pixel edge point from its alpha and its 3 x 3 alpha
// gradient (Gustavson and Strand, "Anti-aliased Euclidean distance
// transform", Pattern Recognition Letters, 2011), `DistanceField.transform`
// finds each pixel's nearest edge pixel exactly, and the distance is the
// nearest of the edge points of it and its eight neighbours. Coverage is
// smoothstep(w + 0.5, w - 0.5, distance), a one-pixel ramp at the stroke's far
// side. Outside goes under the layer, inside goes over it clipped to its
// alpha, centre (w / 2 each side) goes over it. Beyond the buffer reads as
// transparent. Invariants: width is finite and in 0...1,000 (0 is identity),
// the colour is finite, every output component is finite.

extension PixelBuffer {
    /// The widest stroke, in pixels.
    static let maxStrokeWidth = 1_000.0

    /// This buffer with a `width`-pixel stroke of premultiplied `color` at
    /// `position` on the layer's edge, the boundary of its alpha >= 0.5 set:
    /// `.outside` and `.inside` are `width` wide on one side, `.center` is
    /// `width` wide in total, `width` / 2 each side (see `StrokePosition`).
    /// Width 0 returns the buffer unchanged. Throws `RasterError.invalid` for
    /// a width that is not finite or not in 0...1,000, a colour that is not
    /// finite, a buffer too large to pad for the effect (its one-pixel
    /// padded copy passes `maxPixels`), or a result that overflows.
    public func stroked(color: RGBA, width strokeWidth: Double, position: StrokePosition) throws -> PixelBuffer {
        guard strokeWidth.isFinite, strokeWidth >= 0, strokeWidth <= Self.maxStrokeWidth else {
            throw RasterError.invalid("stroke width \(strokeWidth): must be finite and in 0...\(Int(Self.maxStrokeWidth))")
        }
        guard color.isFinite else { throw RasterError.invalid("stroke color \(color): must be finite") }
        guard strokeWidth > 0 else { return self }
        let distance = try edgeDistances(cause: "stroke width \(strokeWidth)")
        let src = components, c = Self.channels
        var out = src
        let paint = [color.r, color.g, color.b, color.a]
        for i in 0..<(width * height) {
            let o = i * c, layerAlpha = src[o + 3], inShape = layerAlpha >= 0.5
            let cover: Float
            switch position {
            case .outside: cover = inShape ? 1 : Self.coverage(edge: distance[i], width: strokeWidth)
            case .inside: cover = (inShape ? Self.coverage(edge: distance[i], width: strokeWidth) : 1) * layerAlpha
            case .center: cover = Self.coverage(edge: distance[i], width: strokeWidth / 2)
            }
            guard cover > 0 else { continue }
            if position == .outside {
                // Under the layer: the stroke shows where the layer is not opaque.
                for k in 0..<c { out[o + k] = src[o + k] + paint[k] * cover * (1 - layerAlpha) }
            } else {
                let strokeAlpha = paint[3] * cover
                for k in 0..<c { out[o + k] = paint[k] * cover + src[o + k] * (1 - strokeAlpha) }
            }
            guard (o..<(o + c)).allSatisfy({ out[$0].isFinite }) else {
                throw RasterError.invalid("stroke of color \(color): result overflows")
            }
        }
        return PixelBuffer(checkedWidth: width, height: height, storage: out)
    }

    /// The stroke's coverage at `edge` pixels from its near side, `width` wide:
    /// smoothstep(width + 0.5, width - 0.5, edge), 1 inside and 0 past it.
    static func coverage(edge: Double, width: Double) -> Float {
        let t = min(max(width + 0.5 - edge, 0), 1)
        return Float(t * t * (3 - 2 * t))
    }

    /// The size of this buffer padded by `pad` pixels a side, the work buffer
    /// of the effect `cause` names (e.g. "shadow at offset (40.0, 0.0)").
    /// Throws `RasterError.invalid` naming the effect, the padded size and the
    /// fix when the padded size passes `maxPixels`; `remedy` is what to reduce
    /// besides the buffer ("offset", or nil when the padding is fixed).
    static func paddedWorkSize(width: Int, height: Int, pad: Int, cause: String,
                               remedy: String?) throws -> (width: Int, height: Int) {
        let pw = width + 2 * pad, ph = height + 2 * pad
        do { _ = try validatedSize(width: pw, height: ph) } catch {
            let fix = remedy.map { "the \($0) or the buffer" } ?? "the buffer"
            throw RasterError.invalid("\(cause) on \(width)x\(height): padded work buffer \(pw)x\(ph) "
                + "exceeds \(maxPixels) pixels; reduce \(fix)")
        }
        return (pw, ph)
    }

    /// Every pixel's distance to the anti-aliased alpha edge (+infinity when
    /// there is no edge), worked on a copy padded by one transparent pixel so
    /// a shape touching the border has an edge there. `cause` names the
    /// effect in the error when that copy is too large.
    func edgeDistances(cause: String) throws -> [Double] {
        let (pw, ph) = try Self.paddedWorkSize(width: width, height: height, pad: 1, cause: cause, remedy: nil)
        let src = components, c = Self.channels
        var alpha = [Double](repeating: 0, count: pw * ph)
        for y in 0..<height {
            for x in 0..<width { alpha[(y + 1) * pw + x + 1] = min(max(Double(src[(y * width + x) * c + 3]), 0), 1) }
        }
        /// The padded alpha at (x, y), 0 past the padding.
        func a(_ x: Int, _ y: Int) -> Double { x >= 0 && x < pw && y >= 0 && y < ph ? alpha[y * pw + x] : 0 }
        var seeds = [Bool](repeating: false, count: pw * ph)
        var points = [Double](repeating: 0, count: 2 * pw * ph)
        let r2 = 2.0.squareRoot()
        for y in 0..<ph {
            for x in 0..<pw {
                let v = a(x, y), i = y * pw + x, opposite = v >= 1 ? 0.0 : 1
                guard (v > 0 && v < 1) || a(x - 1, y) == opposite || a(x + 1, y) == opposite
                    || a(x, y - 1) == opposite || a(x, y + 1) == opposite else { continue }
                seeds[i] = true
                let gx = a(x + 1, y - 1) + r2 * a(x + 1, y) + a(x + 1, y + 1) - a(x - 1, y - 1) - r2 * a(x - 1, y) - a(x - 1, y + 1)
                let gy = a(x - 1, y + 1) + r2 * a(x, y + 1) + a(x + 1, y + 1) - a(x - 1, y - 1) - r2 * a(x, y - 1) - a(x + 1, y - 1)
                let g = (gx * gx + gy * gy).squareRoot()
                // The gradient points inward; a positive offset puts the edge inward of the centre.
                let d = g > 0 ? Self.edgeOffset(alpha: v, abs(gx) / g, abs(gy) / g) / g : 0
                points[2 * i] = Double(x) + d * gx
                points[2 * i + 1] = Double(y) + d * gy
            }
        }
        let nearest = DistanceField.transform(seeds: seeds, width: pw, height: ph, border: false).nearest
        var distance = [Double](repeating: .infinity, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let n = nearest[(y + 1) * pw + x + 1]
                guard n >= 0 else { continue }
                let nx = n % pw, ny = n / pw
                var best = Double.infinity
                for qy in max(ny - 1, 0)...min(ny + 1, ph - 1) {
                    for qx in max(nx - 1, 0)...min(nx + 1, pw - 1) where seeds[qy * pw + qx] {
                        let j = 2 * (qy * pw + qx)
                        let dx = Double(x + 1) - points[j], dy = Double(y + 1) - points[j + 1]
                        best = min(best, (dx * dx + dy * dy).squareRoot())
                    }
                }
                distance[y * width + x] = best
            }
        }
        return distance
    }

    /// The distance from a pixel's centre to a straight edge through it that
    /// leaves `alpha` of the pixel covered, along the edge's unit normal
    /// (`gx`, `gy`, both >= 0): positive when the centre is uncovered.
    static func edgeOffset(alpha: Double, _ gx: Double, _ gy: Double) -> Double {
        let (u, v) = gx >= gy ? (gx, gy) : (gy, gx)
        let a1 = 0.5 * v / u
        if alpha < a1 { return 0.5 * (u + v) - (2 * u * v * alpha).squareRoot() }
        if alpha < 1 - a1 { return (0.5 - alpha) * u }
        return -0.5 * (u + v) + (2 * u * v * (1 - alpha)).squareRoot()
    }
}
