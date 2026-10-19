// CompositeAffine.swift: compositing a layer onto this buffer through an
// AffineMatrix in place, touching only the transformed bounds widened by the
// filter's reach, and those bounds as an integer rectangle.
// The through-composite is `transformed` and the offset composite run over
// that box alone: the layer is resampled into a buffer the size of the box
// clipped to this one (the matrix moved by the box's origin, so each backdrop
// pixel samples the same source point it would in a full-size copy), then
// composited at that origin with the existing row blend. The box is the
// corner bounds plus every pixel the kernel can reach past a hard edge, so
// the result equals transform-then-composite. No full-size intermediate is
// built, and rows outside the box are never written.
// Invariants: a bad opacity or a non-finite or singular matrix throws before
// any change, even for a layer mapped off this buffer; bounds come from all
// four corners and are clamped in Double before they become Int, so a huge
// matrix cannot overflow.

extension PixelBuffer {
    /// Composites `src` mapped through `m` onto this buffer in place, sampled
    /// with `filter` as `transformed` samples and blended with `mode` at
    /// `opacity` as `composite(_:x:y:mode:opacity:)` blends. Only the
    /// pixels inside `m.bounds(of: src.width, src.height)`, widened on every
    /// side by how far `filter`'s kernel reaches in this buffer's pixels, are
    /// visited; a layer mapped wholly off this buffer changes nothing. Throws
    /// `RasterError.invalid`, with this buffer unchanged, for an opacity
    /// outside 0...1 or not finite, a matrix with a non-finite entry or no
    /// finite inverse, or a matrix that maps a corner of `src` outside the
    /// finite range; a result that overflows to infinity throws as the offset
    /// composite does.
    public mutating func composite(_ src: PixelBuffer, through m: AffineMatrix, mode: BlendMode, opacity: Float,
                                   filter: ResampleFilter) throws {
        guard (0...1).contains(opacity) else {
            throw RasterError.invalid("opacity \(opacity): must be a finite value in 0...1")
        }
        guard [m.a, m.b, m.c, m.d, m.tx, m.ty].allSatisfy(\.isFinite), let inv = m.inverse else {
            throw RasterError.invalid("composite through \(m): the matrix must be finite and invertible")
        }
        guard let box = m.bounds(of: src.width, src.height) else {
            throw RasterError.invalid("composite through \(m): the layer's \(src.width)x\(src.height) corners map outside the finite range; reduce the matrix's scale")
        }
        let pad = Self.reach(of: m, inverse: inv, width: src.width, height: src.height, filter: filter)
        // Clipped to this buffer; the clamps in `bounds` and `reach` keep these sums in range.
        let x0 = max(box.x - pad.x, 0), x1 = min(box.x + box.width + pad.x, width)
        let y0 = max(box.y - pad.y, 0), y1 = min(box.y + box.height + pad.y, height)
        guard x0 < x1, y0 < y1 else { return }
        let local = AffineMatrix(a: m.a, b: m.b, c: m.c, d: m.d, tx: m.tx - Double(x0), ty: m.ty - Double(y0))
        let piece = try src.transformed(local, width: x1 - x0, height: y1 - y0, filter: filter)
        try composite(piece, x: x0, y: y0, mode: mode, opacity: opacity)
    }

    /// How many of this buffer's pixels past the corner bounds `filter` can
    /// give coverage, per axis. `transformed` reads a source point within
    /// `radius · stretch` source pixels of a tap (stretch is how far one
    /// output step moves in the source, at least 1 and at most the source's
    /// size); that reach maps forward through `m`'s linear part, plus one
    /// pixel for the centre offset. Clamped to 2^52, so the sums above fit in Int.
    private static func reach(of m: AffineMatrix, inverse inv: AffineMatrix, width: Int, height: Int,
                              filter: ResampleFilter) -> (x: Int, y: Int) {
        let stretchX = min(max((inv.a * inv.a + inv.c * inv.c).squareRoot(), 1), Double(max(width, 1)))
        let stretchY = min(max((inv.b * inv.b + inv.d * inv.d).squareRoot(), 1), Double(max(height, 1)))
        let rx = filter.radius * stretchX, ry = filter.radius * stretchY
        let limit = 4_503_599_627_370_496.0  // 2^52
        func pad(_ v: Double) -> Int { Int(min(v.rounded(.up) + 1, limit)) }
        return (pad(abs(m.a) * rx + abs(m.c) * ry), pad(abs(m.b) * rx + abs(m.d) * ry))
    }
}

public extension AffineMatrix {
    /// The integer rectangle covering a `width` x `height` image's four
    /// corners under this matrix: the corners' least x and y rounded down,
    /// their greatest rounded up. Nil when an entry or a corner is not
    /// finite. Edges are clamped to ±2^52 first, so the result and
    /// `x + width` always fit in Int.
    func bounds(of width: Int, _ height: Int) -> (x: Int, y: Int, width: Int, height: Int)? {
        let w = Double(width), h = Double(height)
        let xs = [tx, a * w + tx, c * h + tx, a * w + c * h + tx]
        let ys = [ty, b * w + ty, d * h + ty, b * w + d * h + ty]
        guard (xs + ys).allSatisfy(\.isFinite), let left = xs.min(), let right = xs.max(),
              let top = ys.min(), let bottom = ys.max() else { return nil }
        let limit = 4_503_599_627_370_496.0  // 2^52
        func edge(_ v: Double, _ rule: FloatingPointRoundingRule) -> Int { Int(min(max(v.rounded(rule), -limit), limit)) }
        let x = edge(left, .down), y = edge(top, .down)
        return (x, y, edge(right, .up) - x, edge(bottom, .up) - y)
    }
}
