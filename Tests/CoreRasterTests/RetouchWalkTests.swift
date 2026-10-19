// RetouchWalkTests.swift: KJ-RH, the retouch-heal walk (RH-7, packet
// docs/blueprints/core/features/retouch-heal.md). On the fixtures' 2400 x 1600
// spotted photo (a smooth light gradient under seeded grain, three dark spots
// of radius 100): spot 1 is filled from surroundings, so its luma mean is
// within 3/255 of its ring's and its variance within 25%; spot 2 is healed
// from an offset whose tone differs, so the seam along the mask's edge has no
// tone step (the mean gradient error across the edge, against the source's
// own gradients, is at most 1/255 per channel, where a plain clone's is ten
// times that); a 30-dab midtone dodge stroke across spot 3 lifts the light
// texture and leaves every pixel under luma 0.2 within 1/255; then a 20-dab
// smudge from spot 3's centre drags its dark colour out past its edge.
// Checks read only the boxes around the spots, so the walk stays quick.
import CoreRaster
import Testing

@Suite struct RetouchWalkTests {
    static let width = 2400, height = 1600
    static let tolerance: Float = 1 / 255

    static func luma(_ p: RGBA) -> Float { 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b }

    /// Every pixel of the square of half-side `r` around `spot`'s centre, clipped to the buffer.
    static func around(_ spot: RetouchFixtures.Spot, r: Int) -> [(Int, Int)] {
        let cx = Int(spot.centerX), cy = Int(spot.centerY)
        var points: [(Int, Int)] = []
        for y in max(cy - r, 0)...min(cy + r, height - 1) {
            for x in max(cx - r, 0)...min(cx + r, width - 1) { points.append((x, y)) }
        }
        return points
    }

    /// Mean and variance of the luma of the pixels `mask` fully covers near `spot`.
    static func lumaStats(_ buffer: PixelBuffer, under mask: Mask,
                          near spot: RetouchFixtures.Spot) throws -> (mean: Double, variance: Double) {
        var values: [Double] = []
        for (x, y) in around(spot, r: Int(2 * spot.radius) + 2) where try mask.coverage(x: x, y: y) == 1 {
            values.append(Double(luma(try buffer.pixel(x: x, y: y))))
        }
        let n = Double(max(values.count, 1)), mean = values.reduce(0, +) / n
        return (mean, values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n)
    }

    @Test func walk() throws {
        let photo = try RetouchFixtures.spottedPhoto(width: Self.width, height: Self.height, seed: 0x5EA1)
        #expect(photo.spots.count == 3)
        let spot1 = try #require(photo.spots.first), spot3 = try #require(photo.spots.last)
        let spot2 = photo.spots[1]
        #expect(spot1.radius == 100)

        // Spot 1: fill from surroundings matches its ring's tone and texture.
        var image = try photo.spotted.filledFromSurroundings(spot1.hole, seed: 1)
        let hole = try Self.lumaStats(image, under: spot1.hole, near: spot1)
        let ring = try Self.lumaStats(image, under: spot1.ring, near: spot1)
        #expect(abs(hole.mean - ring.mean) <= 3.0 / 255, "hole mean \(hole.mean), ring mean \(ring.mean)")
        #expect(abs(hole.variance - ring.variance) <= 0.25 * ring.variance,
                "hole variance \(hole.variance), ring variance \(ring.variance)")

        // Spot 2: heal from an offset up and to the left, where the gradient is darker.
        try healSpotTwo(&image, spot: spot2)
        for spot in [spot1, spot2] {
            #expect(try image.pixel(x: Int(spot.centerX), y: Int(spot.centerY)) != RetouchFixtures.spotColor)
        }
        #expect(try image.pixel(x: Int(spot3.centerX), y: Int(spot3.centerY)) == RetouchFixtures.spotColor)

        try dodgeAcross(&image, spot: spot3)
        try smudgeOut(&image, spot: spot3)
    }

    /// Heals spot 2 from (-300, -300) and checks the seam: the mean, over
    /// every covered pixel next to an uncovered one, of the healed step
    /// across the edge minus the source's step there.
    func healSpotTwo(_ image: inout PixelBuffer, spot: RetouchFixtures.Spot) throws {
        let (dx, dy) = (-300, -300)
        let before = image
        image = try before.healed(offset: (dx: dx, dy: dy), through: spot.hole)
        var healedError = [Double](repeating: 0, count: 3), cloneError = [Double](repeating: 0, count: 3)
        var edges = 0
        for (x, y) in Self.around(spot, r: Int(spot.radius) + 3) where try spot.hole.coverage(x: x, y: y) > 0 {
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
            where try spot.hole.coverage(x: nx, y: ny) == 0 {
                let a = try image.pixel(x: x, y: y), b = try image.pixel(x: nx, y: ny)
                let sa = try before.pixel(x: x + dx, y: y + dy), sb = try before.pixel(x: nx + dx, y: ny + dy)
                let healed = [(a.r - b.r) - (sa.r - sb.r), (a.g - b.g) - (sa.g - sb.g), (a.b - b.b) - (sa.b - sb.b)]
                // A plain clone puts the source at (x, y), so its error is the source's
                // neighbour minus the destination's.
                let clone = [sb.r - b.r, sb.g - b.g, sb.b - b.b]
                for k in 0..<3 {
                    healedError[k] += Double(healed[k])
                    cloneError[k] += Double(clone[k])
                }
                edges += 1
            }
        }
        #expect(edges > 400)
        let n = Double(max(edges, 1))
        for k in 0..<3 {
            #expect(abs(healedError[k] / n) <= Double(Self.tolerance), "channel \(k) seam step \(healedError[k] / n)")
            #expect(abs(cloneError[k] / n) > 5 * Double(Self.tolerance), "channel \(k) clone step \(cloneError[k] / n)")
        }
    }

    /// 30 midtone dodge dabs of radius 40 along spot 3's middle row, from
    /// 160 px left of its centre to 160 px right: the light texture lifts,
    /// the dark spot does not move.
    func dodgeAcross(_ image: inout PixelBuffer, spot: RetouchFixtures.Spot) throws {
        let dab = try RetouchFixtures.roundDab(radius: 40, hardness: 0.6)
        let before = image
        let cx = Int(spot.centerX), cy = Int(spot.centerY)
        for k in 0..<30 {
            try image.dodge(dab, x: cx - 160 + k * 11 - 40, y: cy - 40, range: .midtones, exposure: 0.3)
        }
        var lift = 0.0, lifted = 0, dark = 0
        for (x, y) in Self.around(spot, r: Int(2 * spot.radius) + 2) {
            let p = try before.pixel(x: x, y: y), q = try image.pixel(x: x, y: y), l = Self.luma(p)
            if l < 0.2 {
                dark += 1
                let gap = max(abs(q.r - p.r), abs(q.g - p.g), abs(q.b - p.b), abs(q.a - p.a))
                #expect(gap <= Self.tolerance, "(\(x), \(y)) at luma \(l) moved \(gap)")
            } else if l >= 0.45, l <= 0.7, abs(y - cy) <= 20, abs(x - cx) > Int(spot.radius) + 2, abs(x - cx) <= 150 {
                lift += Double(Self.luma(q) - l)
                lifted += 1
            }
        }
        #expect(dark > 20_000, "dark pixels \(dark)")
        #expect(lifted > 100 && lift / Double(max(lifted, 1)) > 5 * Double(Self.tolerance),
                "midtones lifted \(lift / Double(max(lifted, 1))) over \(lifted) pixels")
    }

    /// 20 smudge dabs of radius 16, 8 px apart, from spot 3's centre to the
    /// right: the dark colour drags past the spot's edge and fades, and
    /// nothing beyond the stroke changes.
    func smudgeOut(_ image: inout PixelBuffer, spot: RetouchFixtures.Spot) throws {
        let dab = try RetouchFixtures.roundDab(radius: 16)
        let before = image
        let cx = Int(spot.centerX), cy = Int(spot.centerY), edge = cx + Int(spot.radius)
        var smudge = SmudgeState(strength: 0.9)
        for k in 0..<20 {
            try smudge.dab(dab, x: cx + 8 * k - 16, y: cy - 16, on: &image)
        }
        /// The mean luma drop over columns `x0..<x1` of the stroke's middle rows.
        func drop(_ x0: Int, _ x1: Int) throws -> Float {
            var total: Float = 0
            for y in (cy - 4)...(cy + 4) {
                for x in x0..<x1 {
                    total += Self.luma(try before.pixel(x: x, y: y)) - Self.luma(try image.pixel(x: x, y: y))
                }
            }
            return total / Float(9 * (x1 - x0))
        }
        let near = try drop(edge + 4, edge + 20), far = try drop(edge + 40, edge + 56)
        #expect(near > 0.1, "past the edge the colour dropped \(near)")
        #expect(far >= 0 && far < near, "the drag fades: \(near) near, \(far) far")
        let end = cx + 8 * 19 + 16
        for y in (cy - 20)...(cy + 20) {
            for x in (end + 1)...(end + 40) {
                #expect(try image.pixel(x: x, y: y) == before.pixel(x: x, y: y), "(\(x), \(y)) past the stroke")
            }
        }
    }
}
