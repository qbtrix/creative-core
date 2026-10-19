// FillFromSurroundings.swift: remove a spot or an object by building it from
// nearby texture, then healing the seam (retouch-heal RH-4).
//
// Each hole pixel gets its own source: the centre of the `2r + 1` patch
// outside the hole (dilated by `r`) that best matches the patch around it,
// found by the seeded search in PatchSearch.swift, coarse to fine on a pyramid
// of up to three levels. The hole is then healed against the ring: its tone
// is the ring's, solved in by the heal's multigrid (`HealSolver`), and its
// grain each source's own (the source minus its local mean). All state is
// local: the same seed gives the same pixels.

extension PixelBuffer {
    /// The largest patch radius the fill uses; a larger `patchRadius` acts as this.
    static let fillMaxPatchRadius = 8
    /// Pyramid levels the fill searches, at most; a level with a side under 16 gets none under it.
    static let fillLevels = 3
    /// The radius of the window whose mean a source's grain is taken against.
    static let fillGrainRadius = 4

    /// The buffer with the pixels `mask` covers rebuilt pixel by pixel from
    /// `2r + 1` square patches (r is `patchRadius`, at most
    /// `fillMaxPatchRadius`) centred outside the mask dilated by r, then
    /// healed against the ring around it. The same `seed` gives the same
    /// pixels; an empty mask returns the input. Throws `RasterError.invalid`
    /// when the mask's size differs from the buffer's, `patchRadius` is below
    /// 1, the mask's bounds plus a one-pixel ring hold more than
    /// `maxHealPixels` pixels, or the mask covers every pixel.
    public func filledFromSurroundings(_ mask: Mask, seed: UInt64, patchRadius: Int = 3) throws -> PixelBuffer {
        guard mask.width == width, mask.height == height else {
            throw RasterError.invalid("fill mask \(mask.width)x\(mask.height) differs from buffer \(width)x\(height)")
        }
        guard patchRadius >= 1 else {
            throw RasterError.invalid("fill patch radius \(patchRadius): must be at least 1")
        }
        guard let box = try Self.coveredBounds(of: mask) else { return self }

        // The grid: the bounds plus the ring `healed` reads, clipped, checked before any work.
        let gx0 = max(box.minX - 1, 0), gx1 = min(box.maxX + 1, width - 1)
        let gy0 = max(box.minY - 1, 0), gy1 = min(box.maxY + 1, height - 1)
        let gw = gx1 - gx0 + 1, gh = gy1 - gy0 + 1, gridPixels = gw * gh
        guard gridPixels <= Self.maxHealPixels else {
            throw RasterError.invalid("fill mask bounds \(box.maxX - box.minX + 1)x\(box.maxY - box.minY + 1) "
                + "plus a 1 px ring hold \(gridPixels) pixels, over \(Self.maxHealPixels); mask a smaller area")
        }
        let r = min(patchRadius, Self.fillMaxPatchRadius)
        var cover = [Float](repeating: 0, count: gridPixels), hole = [Bool](repeating: false, count: width * height)
        for gy in 0..<gh {
            for gx in 0..<gw {
                cover[gy * gw + gx] = try mask.coverage(x: gx0 + gx, y: gy0 + gy)
                hole[(gy0 + gy) * width + gx0 + gx] = cover[gy * gw + gx] > 0
            }
        }
        var levels = [PatchLevel(width: width, height: height, pixels: components, hole: hole, source: [])]
        guard levels[0].markSources(radius: r) else {
            throw RasterError.invalid("fill mask covers every pixel: nothing outside it to fill from")
        }
        while levels.count < Self.fillLevels, let last = levels.last, min(last.width, last.height) >= 16 {
            var coarser = last.halved()
            guard coarser.markSources(radius: r) else { break }
            levels.append(coarser)
        }

        var rng = FillRandom(state: seed)
        var map: [Int] = []
        for i in levels.indices.reversed() {
            map = i == levels.count - 1
                ? [Int](repeating: -1, count: levels[i].width * levels[i].height)
                : levels[i + 1].mapUp(map, to: levels[i])
            levels[i].search(&map, radius: r, rng: &rng)
        }

        // The tone: the ring's, relaxed into the hole from the ring's mean.
        var h = [Double](repeating: 0, count: gridPixels * 4), ringMean = [Double](repeating: 0, count: 4), n = 0.0
        for i in 0..<gridPixels where cover[i] == 0 {
            let p = (gy0 + i / gw) * width + gx0 + i % gw
            for k in 0..<4 { h[i * 4 + k] = Double(components[p * 4 + k]); ringMean[k] += h[i * 4 + k] }
            n += 1
        }
        for i in 0..<gridPixels where cover[i] > 0 { for k in 0..<4 { h[i * 4 + k] = ringMean[k] / max(n, 1) } }
        return try grainedFill(levels[0], map: map, tone: h, cover: cover, grid: (gx0, gy0, gw, gh))
    }

    /// Solves `tone` into the hole (ring cells fixed, hole cells harmonic),
    /// adds each hole pixel's source grain (the source minus the mean of the
    /// unmasked pixels within `fillGrainRadius` of it) and blends feathered
    /// pixels by coverage.
    func grainedFill(_ level: PatchLevel, map: [Int], tone: [Double], cover: [Float],
                     grid: (x0: Int, y0: Int, w: Int, h: Int)) throws -> PixelBuffer {
        var tone = tone, solver = HealSolver(width: grid.w, height: grid.h)
        for i in cover.indices {
            let t = i * 4, gx = i % grid.w, gy = i / grid.w
            solver.fix(gx, gy, SIMD4(Float(tone[t]), Float(tone[t + 1]), Float(tone[t + 2]), Float(tone[t + 3])))
            if cover[i] > 0 { solver.free(gx, gy) }
        }
        solver.solve(tolerance: Self.healTolerance, maxCycles: Self.healMaxCycles)
        for i in cover.indices where cover[i] > 0 {
            let v = solver.value(i % grid.w, i / grid.w)
            for k in 0..<4 { tone[i * 4 + k] = Double(v[k]) }
        }
        var result = self
        for i in cover.indices where cover[i] > 0 {
            let x = grid.x0 + i % grid.w, y = grid.y0 + i / grid.w, s = map[y * width + x]
            let sx = s % width, sy = s / width, g = Self.fillGrainRadius
            var mean = [Double](repeating: 0, count: 4), n = 0.0
            for wy in max(sy - g, 0)...min(sy + g, height - 1) {
                for wx in max(sx - g, 0)...min(sx + g, width - 1) where !level.hole[wy * width + wx] {
                    for k in 0..<4 { mean[k] += Double(level.pixels[(wy * width + wx) * 4 + k]) }
                    n += 1
                }
            }
            func grain(_ k: Int) -> Double { Double(level.pixels[s * 4 + k]) - mean[k] / max(n, 1) }
            let p = try pixel(x: x, y: y), dest = [p.r, p.g, p.b, p.a], c = min(cover[i], 1)
            var out = [Float](repeating: 0, count: 4)
            for k in 0..<4 { out[k] = dest[k] + (Float(tone[i * 4 + k] + grain(k)) - dest[k]) * c }
            try result.setPixel(x: x, y: y, RGBA(r: out[0], g: out[1], b: out[2], a: out[3]))
        }
        return result
    }
}

/// SplitMix64, local to the fill so its search shares no state.
struct FillRandom {
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
