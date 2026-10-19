// PatchSearch.swift: the seeded per-pixel patch search behind fill from
// surroundings (retouch-heal RH-4), the published randomized patch
// correspondence method: random start, propagation from scan-order neighbours
// and a random search in shrinking windows, five iterations. A source centre
// is only ever outside the hole dilated by `r`, so nothing comes from the hole.

/// One pyramid level: premultiplied components (the hole holding the current
/// estimate), which pixels are hole and which may be a patch's source centre.
struct PatchLevel {
    let width: Int
    let height: Int
    var pixels: [Float]
    let hole: [Bool]
    var source: [Bool]

    /// Search iterations per level.
    static let iterations = 5

    /// Marks as sources the pixels farther than `radius` (Chebyshev) from
    /// every hole pixel, or, when the dilation leaves none, every pixel
    /// outside the hole. False when not one pixel lies outside the hole.
    mutating func markSources(radius: Int) -> Bool {
        var near = [Int](repeating: 0, count: width * height)
        for y in 0..<height {
            var run = 0
            for x in 0..<(width + radius) {
                if x < width, hole[y * width + x] { run += 1 }
                if x - 2 * radius - 1 >= 0, hole[y * width + x - 2 * radius - 1] { run -= 1 }
                if x - radius >= 0 { near[y * width + x - radius] = run }
            }
        }
        var dilated = [Bool](repeating: false, count: width * height)
        for x in 0..<width {
            var run = 0
            for y in 0..<(height + radius) {
                if y < height { run += near[y * width + x] }
                if y - 2 * radius - 1 >= 0 { run -= near[(y - 2 * radius - 1) * width + x] }
                if y - radius >= 0 { dilated[(y - radius) * width + x] = run > 0 }
            }
        }
        source = dilated.map { !$0 }
        if !source.contains(true) { source = hole.map { !$0 } }
        return source.contains(true)
    }

    /// Fills `map` (a source index per hole pixel, -1 or a stale source to
    /// draw again) by the search, and the hole's pixels with their sources'.
    mutating func search(_ map: inout [Int], radius: Int, rng: inout FillRandom) {
        let holes = hole.indices.filter { hole[$0] }
        for p in holes where map[p] < 0 || !source[map[p]] { map[p] = randomSource(&rng) }
        for p in holes { copy(map[p], to: p) }
        for iteration in 0..<Self.iterations {
            let step = iteration % 2 == 0 ? 1 : -1
            for p in step > 0 ? holes : holes.reversed() {
                let px = p % width, py = p / width
                var best = map[p], bestD = distance(p, best, radius: radius, bound: .infinity)
                func consider(_ cx: Int, _ cy: Int) {
                    guard (0..<width).contains(cx), (0..<height).contains(cy), source[cy * width + cx] else { return }
                    let d = distance(p, cy * width + cx, radius: radius, bound: bestD)
                    if d < bestD { (best, bestD) = (cy * width + cx, d) }
                }
                for (nx, ny) in [(px - step, py), (px, py - step)]
                where (0..<width).contains(nx) && (0..<height).contains(ny) && hole[ny * width + nx] {
                    let s = map[ny * width + nx]
                    consider(s % width + px - nx, s / width + py - ny)
                }
                var w = max(width, height)
                while w >= 1 {
                    consider(best % width + rng.below(2 * w + 1) - w, best / width + rng.below(2 * w + 1) - w)
                    w /= 2
                }
                map[p] = best
                copy(best, to: p)
            }
        }
    }

    /// The mean squared difference of the `2r + 1` patches around `p` and
    /// `s`, over the offsets where both lie on the level; infinity once the
    /// sum shows it cannot come under `bound`.
    func distance(_ p: Int, _ s: Int, radius r: Int, bound: Float) -> Float {
        let px = p % width, py = p / width, sx = s % width, sy = s / width
        let cutoff = bound * Float((2 * r + 1) * (2 * r + 1))
        var sum: Float = 0, count = 0
        for dy in max(-r, -py, -sy)...min(r, height - 1 - py, height - 1 - sy) {
            for dx in max(-r, -px, -sx)...min(r, width - 1 - px, width - 1 - sx) {
                let a = ((py + dy) * width + px + dx) * 4, b = ((sy + dy) * width + sx + dx) * 4
                for k in 0..<4 {
                    let d = pixels[a + k] - pixels[b + k]
                    sum += d * d
                }
                count += 1
            }
            if sum > cutoff { return .infinity }
        }
        return sum / Float(max(count, 1))
    }

    /// A seeded random source centre: a few draws, then the next source on.
    func randomSource(_ rng: inout FillRandom) -> Int {
        var i = rng.below(width * height), steps = 0
        for _ in 0..<32 where !source[i] { i = rng.below(width * height) }
        while !source[i], steps < width * height { (i, steps) = ((i + 1) % (width * height), steps + 1) }
        return i
    }

    mutating func copy(_ s: Int, to p: Int) { for k in 0..<4 { pixels[p * 4 + k] = pixels[s * 4 + k] } }

    /// The level at half the size: each pixel the mean of its children, a
    /// hole where any child is one.
    func halved() -> PatchLevel {
        let w = (width + 1) / 2, h = (height + 1) / 2
        var pixels = [Float](repeating: 0, count: w * h * 4), hole = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var n: Float = 0
                for cy in (2 * y)..<min(2 * y + 2, height) {
                    for cx in (2 * x)..<min(2 * x + 2, width) {
                        let c = cy * width + cx
                        hole[y * w + x] = hole[y * w + x] || self.hole[c]
                        for k in 0..<4 { pixels[(y * w + x) * 4 + k] += self.pixels[c * 4 + k] }
                        n += 1
                    }
                }
                for k in 0..<4 { pixels[(y * w + x) * 4 + k] /= n }
            }
        }
        return PatchLevel(width: w, height: h, pixels: pixels, hole: hole, source: [])
    }

    /// The map for the level twice this size (`finer`): each hole pixel takes
    /// its parent's source, shifted to the same child; -1 where there is none.
    func mapUp(_ map: [Int], to finer: PatchLevel) -> [Int] {
        var up = [Int](repeating: -1, count: finer.width * finer.height)
        for p in up.indices where finer.hole[p] {
            let x = p % finer.width, y = p / finer.width, s = map[(y / 2) * width + x / 2]
            guard s >= 0 else { continue }
            let sx = 2 * (s % width) + x % 2, sy = 2 * (s / width) + y % 2
            if sx < finer.width, sy < finer.height { up[p] = sy * finer.width + sx }
        }
        return up
    }
}
