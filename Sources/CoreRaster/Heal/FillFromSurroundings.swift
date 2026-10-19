// FillFromSurroundings.swift: remove a spot or an object by building it from
// nearby texture, then healing the seam (retouch-heal RH-4).
//
// A seeded search draws a fixed number of candidate offsets near the mask and
// keeps only those whose source (the mask's bounds plus a one-pixel ring,
// shifted) lies on the buffer and covers no masked pixel, so nothing is ever
// copied from inside the hole. Each candidate is scored by how well the band
// of `patchRadius` pixels around the hole matches its shifted twin; the best
// one goes through `healed`, which solves its tone to meet the ring. All
// state is local: the same seed gives the same pixels.

extension PixelBuffer {
    /// Candidate offsets the search keeps at most.
    static let fillCandidates = 48
    /// Draws the search makes at most while looking for those candidates.
    static let fillDraws = 512
    /// The widest scoring band, whatever `patchRadius` asks for.
    static let fillMaxBand = 16

    /// The buffer with the pixels `mask` covers rebuilt from patches of
    /// radius `patchRadius` (a `2r + 1` square) found outside the mask, then
    /// healed against the ring around it. The same `seed` gives the same
    /// pixels; an empty mask returns the input. Throws `RasterError.invalid`
    /// when the mask's size differs from the buffer's or `patchRadius` is
    /// below 1.
    public func filledFromSurroundings(_ mask: Mask, seed: UInt64, patchRadius: Int = 3) throws -> PixelBuffer {
        guard mask.width == width, mask.height == height else {
            throw RasterError.invalid("fill mask \(mask.width)x\(mask.height) differs from buffer \(width)x\(height)")
        }
        guard patchRadius >= 1 else {
            throw RasterError.invalid("fill patch radius \(patchRadius): must be at least 1")
        }
        guard let box = try Self.coveredBounds(of: mask) else { return self }

        // The guarded source: the bounds plus the ring `healed` reads, clipped.
        let gx0 = max(box.minX - 1, 0), gx1 = min(box.maxX + 1, width - 1)
        let gy0 = max(box.minY - 1, 0), gy1 = min(box.maxY + 1, height - 1)
        let span = 4 * max(gx1 - gx0 + 1, gy1 - gy0 + 1) + min(patchRadius, Self.fillMaxBand)
        // The guarded rectangle is on the buffer, so each range holds 0.
        let dxRange = -min(gx0, span)...min(width - 1 - gx1, span)
        let dyRange = -min(gy0, span)...min(height - 1 - gy1, span)
        let band = try fillBand(mask, box: box, radius: min(patchRadius, Self.fillMaxBand))

        var rng = FillRandom(state: seed)
        var best: (score: Double, dx: Int, dy: Int)?
        var kept = 0, draws = 0
        while kept < Self.fillCandidates, draws < Self.fillDraws {
            draws += 1
            let dx = dxRange.lowerBound + rng.below(dxRange.count)
            let dy = dyRange.lowerBound + rng.below(dyRange.count)
            guard try sourceIsClear(mask, x0: gx0 + dx, y0: gy0 + dy, x1: gx1 + dx, y1: gy1 + dy, box: box) else {
                continue
            }
            kept += 1
            let score = try fillScore(band, mask: mask, dx: dx, dy: dy)
            if best.map({ score < $0.score }) ?? true { best = (score, dx, dy) }
        }
        guard let chosen = best else {
            throw RasterError.invalid("no patch outside the mask fits the buffer to fill from")
        }
        return try healed(offset: (dx: chosen.dx, dy: chosen.dy), through: mask)
    }

    /// The unmasked pixels within `radius` of the mask's bounds: the texture
    /// a candidate must match.
    func fillBand(_ mask: Mask, box: (minX: Int, minY: Int, maxX: Int, maxY: Int), radius: Int) throws -> [(Int, Int)] {
        var band: [(Int, Int)] = []
        for y in max(box.minY - radius, 0)...min(box.maxY + radius, height - 1) {
            for x in max(box.minX - radius, 0)...min(box.maxX + radius, width - 1)
            where try mask.coverage(x: x, y: y) == 0 {
                band.append((x, y))
            }
        }
        return band
    }

    /// True when the rectangle lies on the buffer and holds no masked pixel.
    /// Masked pixels all lie in `box`, so only the overlap with it is read.
    func sourceIsClear(_ mask: Mask, x0: Int, y0: Int, x1: Int, y1: Int,
                       box: (minX: Int, minY: Int, maxX: Int, maxY: Int)) throws -> Bool {
        guard x0 >= 0, y0 >= 0, x1 < width, y1 < height else { return false }
        let ox0 = max(x0, box.minX), ox1 = min(x1, box.maxX)
        let oy0 = max(y0, box.minY), oy1 = min(y1, box.maxY)
        guard ox0 <= ox1, oy0 <= oy1 else { return true }
        for y in oy0...oy1 {
            for x in ox0...ox1 where try mask.coverage(x: x, y: y) > 0 {
                return false
            }
        }
        return true
    }

    /// The mean squared colour difference between the band and the band
    /// shifted by the offset; a shifted pixel off the buffer or under the
    /// mask counts as the worst difference.
    func fillScore(_ band: [(Int, Int)], mask: Mask, dx: Int, dy: Int) throws -> Double {
        var total = 0.0
        for (x, y) in band {
            let sx = x + dx, sy = y + dy
            guard (0..<width).contains(sx), (0..<height).contains(sy), try mask.coverage(x: sx, y: sy) == 0 else {
                total += 3
                continue
            }
            let a = try pixel(x: x, y: y), b = try pixel(x: sx, y: sy)
            let dr = Double(a.r - b.r), dg = Double(a.g - b.g), db = Double(a.b - b.b)
            total += dr * dr + dg * dg + db * db
        }
        return total / Double(max(band.count, 1))
    }
}

/// SplitMix64, local to the fill so its search shares no state.
private struct FillRandom {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in `0..<bound` (0 for a bound below 1).
    mutating func below(_ bound: Int) -> Int {
        guard bound > 1 else { return 0 }
        return Int(next() % UInt64(bound))
    }
}
