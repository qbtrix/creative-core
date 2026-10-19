// CompositeAffine.swift: compositing a layer onto this buffer through an
// AffineMatrix in place, touching only `AffineMatrix.writeBounds` (the
// transformed bounds widened by the filter's reach), and those bounds as
// integer rectangles.
// The through-composite walks the write box, clipped to this buffer, one row
// at a time: each backdrop row is resampled with `transformed` into a one-row
// buffer (the matrix moved by the row's origin, so each backdrop pixel
// samples the same source point it would in a full-size copy), then blended
// at that row with the existing row blend. The box is the corner bounds plus
// every pixel the kernel can reach past a hard edge, so the result equals
// transform-then-composite. Peak extra memory is one box row: no full-size
// intermediate is built, and pixels outside the box are never written.
// Invariants: a bad opacity or a non-finite or singular matrix throws before
// any change, even for a layer mapped off this buffer; bounds come from all
// four corners, and bounds and reach are clamped in Double to 2^52 before
// they become Int, so a huge matrix cannot overflow; the walk and
// `writeBounds` share one formula.

extension PixelBuffer {
    /// Composites `src` mapped through `m` onto this buffer in place, sampled
    /// with `filter` as `transformed` samples and blended with `mode` at
    /// `opacity` as `composite(_:x:y:mode:opacity:)` blends. `m` maps `src`'s
    /// pixel coordinates to this buffer's (forward, as in the RenderBackend
    /// contract); pixel (x, y) is sampled at its centre (x + 0.5, y + 0.5).
    /// Only the pixels inside `m.writeBounds(of: src.width, src.height,
    /// filter: filter)` are visited; a layer mapped wholly off this buffer
    /// changes nothing. Throws `RasterError.invalid`, with this buffer
    /// unchanged, for an opacity outside 0...1 or not finite, a matrix with a
    /// non-finite entry or a singular one (`checkedInverse` says which), or a
    /// matrix that maps a corner of `src` outside the finite range. A
    /// lanczos3 overshoot that is not finite, or a result that overflows to
    /// infinity, throws `RasterError.invalid` at the first such pixel in row
    /// order, after the walk began: the box's rows above it already hold the
    /// composite, its row and the rest are untouched, and every component
    /// stays finite. Checking that first would resample the box twice, so
    /// the call does not. Extra memory is one box row, never a full-size copy.
    public mutating func composite(_ src: PixelBuffer, through m: AffineMatrix, mode: BlendMode, opacity: Float,
                                   filter: ResampleFilter) throws {
        guard (0...1).contains(opacity) else {
            throw RasterError.invalid("opacity \(opacity): must be a finite value in 0...1")
        }
        let inv = try m.checkedInverse(for: "composite through \(m)")
        guard let wide = m.writeBounds(of: src.width, src.height, filter: filter, inverse: inv) else {
            throw RasterError.invalid("composite through \(m): the layer's \(src.width)x\(src.height) corners map outside the finite range; reduce the matrix's scale")
        }
        // Clipped to this buffer; the clamps in `bounds` and `reach` keep these sums in range.
        let x0 = max(wide.x, 0), x1 = min(wide.x + wide.width, width)
        let y0 = max(wide.y, 0), y1 = min(wide.y + wide.height, height)
        guard x0 < x1, y0 < y1 else { return }
        for y in y0..<y1 {
            let local = AffineMatrix(a: m.a, b: m.b, c: m.c, d: m.d, tx: m.tx - Double(x0), ty: m.ty - Double(y))
            let row: PixelBuffer
            do {
                row = try src.transformed(local, width: x1 - x0, height: 1, filter: filter)
            } catch {
                // Size and invertibility passed above, so the resample's only throw left is the overshoot.
                throw RasterError.invalid("composite through \(m) with \(filter): lanczos3 overshoot made a component non-finite; use .bilinear or keep components finite")
            }
            try composite(row, x: x0, y: y, mode: mode, opacity: opacity)
        }
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

    /// The rectangle of a backdrop that `PixelBuffer.composite(_:through:
    /// mode:opacity:filter:)` may change when it composites a `width` x
    /// `height` layer through this matrix with `filter`: `bounds(of:_:)`
    /// widened on every side by how far `filter`'s kernel reaches in the
    /// backdrop's pixels, not clipped to the backdrop. Every pixel outside
    /// it is left as it was, even when the composite throws. Nil when this
    /// matrix is singular or `bounds` is nil. Every edge and `x + width`
    /// fits in Int.
    func writeBounds(of width: Int, _ height: Int, filter: ResampleFilter) -> (x: Int, y: Int, width: Int, height: Int)? {
        inverse.flatMap { writeBounds(of: width, height, filter: filter, inverse: $0) }
    }

    /// `writeBounds(of:_:filter:)` with this matrix's inverse already found.
    internal func writeBounds(of width: Int, _ height: Int, filter: ResampleFilter,
                              inverse inv: AffineMatrix) -> (x: Int, y: Int, width: Int, height: Int)? {
        guard let box = bounds(of: width, height) else { return nil }
        let pad = Self.reach(of: self, inverse: inv, width: width, height: height, filter: filter)
        return (box.x - pad.x, box.y - pad.y, box.width + 2 * pad.x, box.height + 2 * pad.y)
    }

    /// How many backdrop pixels past the corner bounds `filter` can give
    /// coverage, per axis. `transformed` reads a source point within
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
