// AffineTransform.swift: resampling a PixelBuffer through an AffineMatrix
// (transparent outside, the ResampleFilter kernels) and flipping it exactly.
// Output pixel (x, y) is sampled at its centre (x + 0.5, y + 0.5) mapped
// through the inverse matrix; source pixel i's centre is at i + 0.5. A map
// whose linear part is a signed permutation (identity, flips, quarter turns)
// with a whole-pixel translation takes every output centre to a source
// centre, so it copies pixels instead of filtering them: whole rows for a pure
// translation, one pixel at a time otherwise. Any other map runs the filter
// as one 2-D kernel over premultiplied values: taps outside the source read
// transparent and the weights are divided by the whole kernel's sum, as
// `rotated(degrees:filter:)` does, and each axis's kernel widens by how far
// one output step moves in the source along it, as `resized` widens when
// shrinking. Invariants: the output size passed `validatedSize`, the matrix
// is finite and invertible, and every output component is finite.

extension PixelBuffer {
    /// This image mapped through `m` into a `width` x `height` buffer,
    /// sampled with `filter`; outside the source is transparent. Throws
    /// `RasterError.invalid` for a size `validatedSize` rejects, a matrix with
    /// a non-finite entry or no finite inverse, or a lanczos3 overshoot that
    /// is not finite.
    public func transformed(_ m: AffineMatrix, width outW: Int, height outH: Int, filter: ResampleFilter) throws -> PixelBuffer {
        _ = try Self.validatedSize(width: outW, height: outH)
        guard [m.a, m.b, m.c, m.d, m.tx, m.ty].allSatisfy(\.isFinite), let inv = m.inverse else {
            throw RasterError.invalid("transform by \(m): the matrix must be finite and invertible")
        }
        if let copy = exactCopy(m, inverse: inv, width: outW, height: outH) { return copy }
        let output = sampled(inv, width: outW, height: outH, filter: filter)
        guard output.allSatisfy(\.isFinite) else {
            throw RasterError.invalid("transform by \(m) with \(filter): lanczos3 overshoot made a component non-finite; use .bilinear or keep components finite")
        }
        return PixelBuffer(checkedWidth: outW, height: outH, storage: output)
    }

    /// This image mirrored across `axis`: horizontal swaps left and right,
    /// vertical swaps top and bottom. Pixels are copied, never filtered.
    public func flipped(_ axis: FlipAxis) -> PixelBuffer {
        let input = components
        let c = Self.channels
        var output: [Float] = []
        output.reserveCapacity(input.count)
        for y in 0..<height {
            for x in 0..<width {
                let (sx, sy) = axis == .horizontal ? (width - 1 - x, y) : (x, height - 1 - y)
                let s = (sy * width + sx) * c
                output.append(contentsOf: input[s..<(s + c)])
            }
        }
        return PixelBuffer(checkedWidth: width, height: height, storage: output)
    }

    /// The output when `m` takes every pixel centre to a pixel centre: its
    /// linear part has one entry of ±1 per row and column, and its
    /// translation is whole and within `maxPixels` (so every index below fits
    /// in Int). Nil for any other map.
    private func exactCopy(_ m: AffineMatrix, inverse inv: AffineMatrix, width outW: Int, height outH: Int) -> PixelBuffer? {
        let limit = Double(Self.maxPixels)
        guard [m.a, m.b, m.c, m.d].allSatisfy({ $0 == 0 || abs($0) == 1 }),
              (m.a == 0) == (m.d == 0), (m.b == 0) == (m.c == 0), (m.a == 0) != (m.b == 0),
              m.tx == m.tx.rounded(), m.ty == m.ty.rounded(), abs(m.tx) <= limit, abs(m.ty) <= limit else {
            return nil
        }
        let c = Self.channels
        let input = components
        if m == .identity, (outW, outH) == (width, height) { return self }
        var output = [Float](repeating: 0, count: outW * outH * c)
        if m.a == 1, m.d == 1 {
            // A translation: output row y is source row y - dy, shifted dx columns.
            let dx = Int(m.tx), dy = Int(m.ty)
            let x0 = max(0, dx), x1 = min(outW, width + dx)
            let y0 = max(0, dy), y1 = min(outH, height + dy)
            guard x0 < x1, y0 < y1 else { return PixelBuffer(checkedWidth: outW, height: outH, storage: output) }
            for y in y0..<y1 {
                let from = ((y - dy) * width + (x0 - dx)) * c, to = (y * outW + x0) * c
                output.replaceSubrange(to..<(to + (x1 - x0) * c), with: input[from..<(from + (x1 - x0) * c)])
            }
        } else {
            for y in 0..<outH {
                for x in 0..<outW {
                    let p = inv.centre(x, y)
                    let sx = Int(p.x.rounded(.down)), sy = Int(p.y.rounded(.down))
                    guard (0..<width).contains(sx), (0..<height).contains(sy) else { continue }
                    let from = (sy * width + sx) * c, to = (y * outW + x) * c
                    for k in 0..<c { output[to + k] = input[from + k] }
                }
            }
        }
        return PixelBuffer(checkedWidth: outW, height: outH, storage: output)
    }

    /// The filtered output: for each output pixel, the source point under
    /// its centre through `inv`, read with `filter`'s kernel. Components may
    /// be non-finite only after a lanczos3 overshoot on extreme values.
    private func sampled(_ inv: AffineMatrix, width outW: Int, height outH: Int, filter: ResampleFilter) -> [Float] {
        // How far one output step moves along each source axis, at least 1;
        // capped at the source's size along that axis, past which the kernel
        // already reaches every pixel on it, so a huge shrink costs no more
        // taps than the source has.
        let stretchX = min(max((inv.a * inv.a + inv.c * inv.c).squareRoot(), 1), Double(width))
        let stretchY = min(max((inv.b * inv.b + inv.d * inv.d).squareRoot(), 1), Double(height))
        let reachX = filter.radius * stretchX, reachY = filter.radius * stretchY
        let input = components
        let c = Self.channels
        var output = [Float](repeating: 0, count: outW * outH * c)
        var wx = [Double](repeating: 0, count: Int(2 * reachX) + 2)
        var wy = [Double](repeating: 0, count: Int(2 * reachY) + 2)
        var sum = [Double](repeating: 0, count: c)
        for y in 0..<outH {
            for x in 0..<outW {
                let p = inv.centre(x, y)
                // In source pixel indices: pixel i's centre is at i + 0.5.
                let u = p.x - 0.5, v = p.y - 0.5
                // Far outside (or NaN from huge entries) reads nothing: stays clear.
                guard u > -reachX - 1, u < Double(width) + reachX,
                      v > -reachY - 1, v < Double(height) + reachY else { continue }
                let kx = filter.kernel(at: u, stretch: stretchX, reach: reachX, into: &wx)
                let ky = filter.kernel(at: v, stretch: stretchY, reach: reachY, into: &wy)
                let total = kx.total * ky.total
                let (x0, x1) = (max(kx.first, 0), min(kx.last, width - 1))
                let (y0, y1) = (max(ky.first, 0), min(ky.last, height - 1))
                guard total != 0, x0 <= x1, y0 <= y1 else { continue }
                let cols = x0...x1, rows = y0...y1
                for k in 0..<c { sum[k] = 0 }
                for j in rows where wy[j - ky.first] != 0 {
                    for i in cols {
                        let w = wy[j - ky.first] * wx[i - kx.first]
                        let base = (j * width + i) * c
                        for k in 0..<c { sum[k] += w * Double(input[base + k]) }
                    }
                }
                let base = (y * outW + x) * c
                for k in 0..<c { output[base + k] = Float(sum[k] / total) }
            }
        }
        return output
    }
}

extension ResampleFilter {
    /// The taps within `reach` of `centre` along one axis, inside the source
    /// or not: their weights, scaled by `stretch`, written from `weights[0]`,
    /// with the first and last tap index and the weights' sum. `weights`
    /// holds at least `Int(2 * reach) + 2` entries, and `centre` is within
    /// `reach + 1` of a line no longer than `PixelBuffer.maxPixels`.
    fileprivate func kernel(at centre: Double, stretch: Double, reach: Double,
                            into weights: inout [Double]) -> (first: Int, last: Int, total: Double) {
        let first = Int((centre - reach).rounded(.up))
        let last = max(first, Int((centre + reach).rounded(.down)))
        var total = 0.0
        for i in first...last {
            weights[i - first] = weight((Double(i) - centre) / stretch)
            total += weights[i - first]
        }
        return (first, last, total)
    }
}

extension AffineMatrix {
    /// Where the centre of pixel (`x`, `y`) lands under this map.
    func centre(_ x: Int, _ y: Int) -> (x: Double, y: Double) {
        let px = Double(x) + 0.5, py = Double(y) + 0.5
        return (a * px + c * py + tx, b * px + d * py + ty)
    }
}
