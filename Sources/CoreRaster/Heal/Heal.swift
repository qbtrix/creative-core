// Heal.swift: the true heal behind Photo's heal, spot heal and patch tools
// (retouch-heal RH-3, Photo blueprint CR-7). Texture from the buffer shifted
// by an offset is cloned through a mask and its colour solved so it meets the
// destination's edge with no seam (gradient-domain editing).
//
// The solve works on the correction `h = f - g` (f the result, g the source):
// keeping g's gradients inside the mask means `Δh = 0` there, with
// `h = destination - source` on the ring just outside the mask. A neighbour
// off the buffer is dropped (no flux across the buffer's edge). Solving for h
// rather than f keeps a zero correction exactly zero, so a heal whose source
// is the destination returns it bit for bit. Every allocation and loop is
// sized by the mask's covered bounds, never by the buffer, so a dab heals at
// dab speed on any photo; the solve is `HealSolver`'s multigrid.

extension PixelBuffer {
    /// The most pixels the bounding rectangle of a mask's covered pixels may
    /// hold for `heal` and `healed` (width × height, not the covered count);
    /// `filledFromSurroundings` counts its whole search window around that
    /// rectangle instead. Larger throws.
    public static let maxHealPixels = 4_000_000

    /// The solve stops once no correction moves by this much in a V-cycle.
    static let healTolerance: Float = 1e-5
    /// The solve never runs more V-cycles than this.
    static let healMaxCycles = 40

    /// The buffer with the source (itself shifted by `offset`) cloned through
    /// `mask` and its colour solved to match the destination along the mask's
    /// edge. Only pixels inside the mask's bounds change. The mask must match
    /// the buffer's size and its covered bounds hold at most `maxHealPixels`;
    /// otherwise, or for an offset whose source lies off the buffer, it throws
    /// `RasterError.invalid`. Pixel (x, y) takes its texture from (x + dx,
    /// y + dy), and a feathered mask blends the result by coverage.
    public func healed(offset: (dx: Int, dy: Int), through mask: Mask) throws -> PixelBuffer {
        var result = self
        try result.heal(offset: offset, through: mask)
        return result
    }

    /// `healed(offset:through:)` in place, so a brush dab pays for the dab,
    /// not for a copy of the buffer. The buffer is unchanged when it throws.
    public mutating func heal(offset: (dx: Int, dy: Int), through mask: Mask) throws {
        guard mask.width == width, mask.height == height else {
            throw RasterError.invalid("heal mask \(mask.width)x\(mask.height) differs from buffer \(width)x\(height)")
        }
        guard let box = mask.coveredRect else { return }
        guard box.width * box.height <= Self.maxHealPixels else {
            throw RasterError.invalid("heal mask's covered bounds \(box.width)x\(box.height) hold more than \(Self.maxHealPixels) pixels; heal a smaller area")
        }
        try checkHealSource(box, offset: offset)
        let (dx, dy) = offset

        // The grid: the mask's bounds plus the one-pixel ring that holds the
        // boundary values, clipped to the buffer.
        let gx0 = max(box.x - 1, 0), gx1 = min(box.x + box.width, width - 1)
        let gy0 = max(box.y - 1, 0), gy1 = min(box.y + box.height, height - 1)
        let gw = gx1 - gx0 + 1, gh = gy1 - gy0 + 1
        var cover = [Float](repeating: 0, count: gw * gh)
        var solver = HealSolver(width: gw, height: gh)
        var pixels = [SIMD4<Float>](repeating: .zero, count: gw * gh)
        var all = components
        func vector(_ x: Int, _ y: Int) -> SIMD4<Float> {
            let i = (y * width + x) * 4
            return SIMD4(all[i], all[i + 1], all[i + 2], all[i + 3])
        }
        for gy in 0..<gh {
            for gx in 0..<gw {
                let x = gx0 + gx, y = gy0 + gy, i = gy * gw + gx
                let c = try mask.coverage(x: x, y: y)
                cover[i] = c
                guard c == 0 else {
                    solver.free(gx, gy)
                    continue
                }
                let src = vector(min(max(x + dx, 0), width - 1), min(max(y + dy, 0), height - 1))
                solver.fix(gx, gy, vector(x, y) - src)
            }
        }

        solver.solve(tolerance: Self.healTolerance, maxCycles: Self.healMaxCycles)

        for gy in 0..<gh {
            for gx in 0..<gw {
                let i = gy * gw + gx
                let c = cover[i]
                let x = gx0 + gx, y = gy0 + gy, dest = vector(x, y)
                let f = c > 0 ? vector(x + dx, y + dy) + solver.value(gx, gy) : dest
                let out = c >= 1 ? f : dest + (f - dest) * c
                guard out.x.isFinite, out.y.isFinite, out.z.isFinite, out.w.isFinite else {
                    throw RasterError.invalid("heal produced a non-finite pixel at (\(x), \(y))")
                }
                pixels[i] = out
            }
        }
        all = [] // Released before the writes, so they copy nothing.
        for gy in 0..<gh {
            updateRow(x: gx0, y: gy0 + gy, count: gw) { row in
                for gx in 0..<gw {
                    for k in 0..<4 { row[gx * 4 + k] = pixels[gy * gw + gx][k] }
                }
            }
        }
    }

    /// Throws unless the source of every pixel in `box`, shifted by
    /// `offset`, lies on the buffer; overflow counts as off the buffer.
    func checkHealSource(_ box: TileRect, offset: (dx: Int, dy: Int)) throws {
        let maxX = box.x + box.width - 1, maxY = box.y + box.height - 1
        let left = box.x.addingReportingOverflow(offset.dx), right = maxX.addingReportingOverflow(offset.dx)
        let top = box.y.addingReportingOverflow(offset.dy), bottom = maxY.addingReportingOverflow(offset.dy)
        guard !left.overflow, !right.overflow, !top.overflow, !bottom.overflow,
              left.partialValue >= 0, right.partialValue < width,
              top.partialValue >= 0, bottom.partialValue < height else {
            let xs = left.overflow || right.overflow ? "overflows" : "\(left.partialValue)...\(right.partialValue)"
            let ys = top.overflow || bottom.overflow ? "overflows" : "\(top.partialValue)...\(bottom.partialValue)"
            throw RasterError.invalid("heal source x \(xs), y \(ys) is off the \(width)x\(height) buffer")
        }
    }
}
