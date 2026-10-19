// FillFromSurroundings.swift: remove a spot or an object by building it from
// nearby texture, then healing the seam (retouch-heal RH-4).
//
// Each hole pixel gets its own source: the centre of the `2r + 1` patch
// outside the hole (dilated by `r`) that best matches the patch around it,
// found by the seeded search in PatchSearch.swift, coarse to fine on a pyramid
// of up to three levels. The matches make the filled source g, which is then
// healed against the ring as `healed` heals its source: the correction
// `h = f - g` is 0 on the ring, and inside the hole its Laplacian is the
// sources' own steps less g's, so f keeps each source's gradients (edges and
// texture alike), heals the tone seams between matches, keeps a step over
// `fillStructureStep` as an edge, and meets the ring. Every array is sized by a
// search window around the mask's bounds, never by the buffer. All state is
// local: the same seed gives the same pixels.

extension PixelBuffer {
    /// The largest patch radius the fill uses; a larger `patchRadius` acts as this.
    static let fillMaxPatchRadius = 8
    /// Pyramid levels the fill searches, at most; a level with a side under 16 gets none under it.
    static let fillLevels = 3
    /// The least context, in pixels past the patch radius, the search window
    /// adds on each side of the mask's bounds; bounds whose longer side is
    /// over twice this get half that side instead.
    static let fillContext = 32
    /// The least step, per channel, between two filled pixels that the heal
    /// keeps as an edge; a smaller one is a seam and takes the sources' steps.
    static let fillStructureStep: Float = 0.25

    /// The buffer with the pixels `mask` covers rebuilt pixel by pixel from
    /// `2r + 1` pixel square patches centred outside the mask dilated by r,
    /// then healed against the ring around it. `patchRadius` is r in pixels,
    /// 1...8; larger values act as 8. Sources come from a search window: the
    /// mask's covered bounds plus r and max(32, half the bounds' longer side)
    /// pixels on each side, clipped to the buffer. The same `seed` gives the
    /// same pixels; an empty mask returns the input, and a feathered mask
    /// blends the fill by coverage. Throws `RasterError.invalid` when the
    /// mask's size differs from the buffer's, `patchRadius` is below 1, the
    /// search window holds more than `maxHealPixels` pixels, or the mask
    /// covers the whole window.
    public func filledFromSurroundings(_ mask: Mask, seed: UInt64, patchRadius: Int = 3) throws -> PixelBuffer {
        guard mask.width == width, mask.height == height else {
            throw RasterError.invalid("fill mask \(mask.width)x\(mask.height) differs from buffer \(width)x\(height)")
        }
        guard patchRadius >= 1 else {
            throw RasterError.invalid("fill patch radius \(patchRadius): must be at least 1")
        }
        guard let box = mask.coveredRect else { return self }
        let r = min(patchRadius, Self.fillMaxPatchRadius)

        // The window, checked before any work; every array below is its size or the grid's.
        let margin = r + max(Self.fillContext, max(box.width, box.height) / 2)
        let wx0 = max(box.x - margin, 0), wx1 = min(box.x + box.width + margin, width)
        let wy0 = max(box.y - margin, 0), wy1 = min(box.y + box.height + margin, height)
        let ww = wx1 - wx0, windowPixels = ww * (wy1 - wy0)
        guard windowPixels <= Self.maxHealPixels else {
            throw RasterError.invalid("fill mask bounds \(box.width)x\(box.height) plus their search window "
                + "hold \(windowPixels) pixels, over \(Self.maxHealPixels); mask a smaller area")
        }
        // The grid, in window coordinates: the bounds plus the ring the heal reads, clipped.
        let gx0 = max(box.x - 1, 0) - wx0, gx1 = min(box.x + box.width, width - 1) - wx0
        let gy0 = max(box.y - 1, 0) - wy0, gy1 = min(box.y + box.height, height - 1) - wy0
        let gw = gx1 - gx0 + 1, gh = gy1 - gy0 + 1
        var cover = [Float](repeating: 0, count: gw * gh), hole = [Bool](repeating: false, count: windowPixels)
        for gy in 0..<gh {
            for gx in 0..<gw {
                cover[gy * gw + gx] = try mask.coverage(x: wx0 + gx0 + gx, y: wy0 + gy0 + gy)
                hole[(gy0 + gy) * ww + gx0 + gx] = cover[gy * gw + gx] > 0
            }
        }
        var pixels: [Float] = [], all = components
        pixels.reserveCapacity(windowPixels * 4)
        for y in wy0..<wy1 { pixels += all[((y * width + wx0) * 4)..<((y * width + wx1) * 4)] }
        all = []
        var levels = [PatchLevel(width: ww, height: wy1 - wy0, pixels: pixels, hole: hole, source: [])]
        guard levels[0].markSources(radius: r) else {
            throw RasterError.invalid("fill mask covers every pixel of its search window: nothing outside it to fill from")
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
        return try healedFill(levels[0], map: map, cover: cover, origin: (wx0, wy0), grid: (gx0, gy0, gw, gh))
    }

    /// Heals the filled source g (`level`'s pixels, each hole pixel holding
    /// its match's) against the ring: a hole pixel's guidance is its source's
    /// steps to the source's neighbours. Feathered pixels blend by coverage.
    /// `grid` is in window coordinates; `origin` is the window's corner.
    func healedFill(_ level: PatchLevel, map: [Int], cover: [Float], origin: (x: Int, y: Int),
                    grid: (x0: Int, y0: Int, w: Int, h: Int)) throws -> PixelBuffer {
        let w = level.width
        func g(_ x: Int, _ y: Int) -> SIMD4<Float> {
            let i = (min(max(y, 0), level.height - 1) * w + min(max(x, 0), w - 1)) * 4
            return SIMD4(level.pixels[i], level.pixels[i + 1], level.pixels[i + 2], level.pixels[i + 3])
        }
        var solver = HealSolver(width: grid.w, height: grid.h)
        for i in cover.indices where cover[i] > 0 {
            let gx = i % grid.w, gy = i / grid.w, x = grid.x0 + gx, y = grid.y0 + gy, s = map[y * w + x]
            var rhs = SIMD4<Float>.zero
            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)]
            where (0..<grid.w).contains(gx + dx) && (0..<grid.h).contains(gy + dy) {
                // The step to q is p's source's step there. Between two hole
                // pixels it is the smaller of the two sources' steps, so a seam
                // between sources of different tone heals away, unless g's own
                // step is over fillStructureStep: then it is an edge g carries.
                var step = g(x, y) - g(s % w + dx, s / w + dy)
                if cover[(gy + dy) * grid.w + gx + dx] > 0 {
                    let t = map[(y + dy) * w + x + dx], other = g(t % w - dx, t / w - dy) - g(x + dx, y + dy)
                    let own = g(x, y) - g(x + dx, y + dy), edge = Self.fillStructureStep
                    step.replace(with: other, where: other * other .< step * step)
                    step.replace(with: own, where: own * own .> SIMD4(repeating: edge * edge))
                }
                rhs += step + g(x + dx, y + dy) - g(x, y)
            }
            solver.free(gx, gy)
            solver.load(gx, gy, rhs: rhs)
        }
        solver.solve(tolerance: Self.healTolerance, maxCycles: Self.healMaxCycles)
        var result = self
        for i in cover.indices where cover[i] > 0 {
            let gx = i % grid.w, gy = i / grid.w, x = origin.x + grid.x0 + gx, y = origin.y + grid.y0 + gy
            let p = try pixel(x: x, y: y), dest = SIMD4(p.r, p.g, p.b, p.a), c = min(cover[i], 1)
            let out = dest + (g(grid.x0 + gx, grid.y0 + gy) + solver.value(gx, gy) - dest) * c
            guard out.x.isFinite, out.y.isFinite, out.z.isFinite, out.w.isFinite else {
                throw RasterError.invalid("fill produced a non-finite pixel at (\(x), \(y))")
            }
            try result.setPixel(x: x, y: y, RGBA(r: out.x, g: out.y, b: out.z, a: out.w))
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
