// FillFromSurroundingsTests.swift: retouch-heal RH-4's acceptance, written
// first by RH-1 (docs/blueprints/core/features/retouch-heal.md).
import CoreRaster
import Testing

/// Mean and variance of the luma of the pixels `mask` fully covers.
private func lumaStats(_ buffer: PixelBuffer, under mask: Mask) throws -> (mean: Double, variance: Double) {
    var values: [Double] = []
    for y in 0..<buffer.height {
        for x in 0..<buffer.width where try mask.coverage(x: x, y: y) == 1 {
            let p = try buffer.pixel(x: x, y: y)
            values.append(0.2126 * Double(p.r) + 0.7152 * Double(p.g) + 0.0722 * Double(p.b))
        }
    }
    let n = Double(max(values.count, 1)), mean = values.reduce(0, +) / n
    return (mean, values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n)
}

@Suite struct FillFromSurroundingsTests {
    static func spotOne() throws -> (photo: RetouchFixtures.SpottedPhoto, spot: RetouchFixtures.Spot) {
        let photo = try RetouchFixtures.spottedPhoto(width: 160, height: 96, seed: 7)
        return (photo, try #require(photo.spots.first))
    }

    @Test func toneMeetsRing() throws {
        let (photo, spot) = try Self.spotOne()
        let filled = try photo.spotted.filledFromSurroundings(spot.hole, seed: 1)
        let hole = try lumaStats(filled, under: spot.hole), ring = try lumaStats(filled, under: spot.ring)
        #expect(abs(hole.mean - ring.mean) <= 3.0 / 255, "hole mean \(hole.mean), ring mean \(ring.mean)")

        // On a smooth field every patch has the wrong tone; the heal still
        // lands each hole pixel on the field.
        let field = try RetouchFixtures.gradientField(width: 64, height: 48)
        let disc = try RetouchFixtures.disc(width: 64, height: 48, centerX: 32, centerY: 24, radius: 6)
        let smooth = try field.filledFromSurroundings(disc, seed: 1)
        for y in 0..<48 {
            for x in 0..<64 where try disc.coverage(x: x, y: y) > 0 {
                let p = try smooth.pixel(x: x, y: y), f = RetouchFixtures.fieldValue(x: x, y: y)
                let gap = max(abs(p.r - f.r), abs(p.g - f.g), abs(p.b - f.b))
                #expect(gap <= 1.0 / 255, "(\(x), \(y)) off the field by \(gap)")
            }
        }
    }

    @Test func textureMatchesRing() throws {
        let (photo, spot) = try Self.spotOne()
        let filled = try photo.spotted.filledFromSurroundings(spot.hole, seed: 1)
        let hole = try lumaStats(filled, under: spot.hole), ring = try lumaStats(filled, under: spot.ring)
        #expect(abs(hole.variance - ring.variance) <= 0.25 * ring.variance,
                "hole variance \(hole.variance), ring variance \(ring.variance)")
    }

    @Test func seedChangesFill() throws {
        let (photo, spot) = try Self.spotOne()
        let a = try photo.spotted.filledFromSurroundings(spot.hole, seed: 42)
        #expect(try photo.spotted.filledFromSurroundings(spot.hole, seed: 42) == a)
        #expect(try photo.spotted.filledFromSurroundings(spot.hole, seed: 43) != a)
    }

    @Test func neverCopiesFromHole() throws {
        // A one-pixel checkerboard in the hole is far sharper than the grain (steps
        // under 0.4): texture copied from inside keeps its steps through the heal.
        let (photo, spot) = try Self.spotOne()
        var checkered = photo.spotted
        for y in 0..<96 {
            for x in 0..<160 where try spot.hole.coverage(x: x, y: y) > 0 {
                let v: Float = (x + y) % 2 == 0 ? 0 : 1
                try checkered.setPixel(x: x, y: y, RGBA(r: v, g: v, b: v, a: 1))
            }
        }
        // Many seeds, so a search that let a patch overlap the hole would pick one.
        for seed: UInt64 in 9..<41 {
            let filled = try checkered.filledFromSurroundings(spot.hole, seed: seed)
            for y in 0..<96 {
                for x in 1..<160 where try spot.hole.coverage(x: x, y: y) == 1 && spot.hole.coverage(x: x - 1, y: y) == 1 {
                    let d = try filled.pixel(x: x, y: y).g - filled.pixel(x: x - 1, y: y).g
                    #expect(abs(d) <= 0.45, "seed \(seed) (\(x), \(y)) step \(d) is the hole's checkerboard")
                }
            }
        }
    }

    @Test func emptyMaskIsIdentity() throws {
        let (photo, _) = try Self.spotOne()
        #expect(try photo.spotted.filledFromSurroundings(Mask(width: 160, height: 96), seed: 3) == photo.spotted)
    }

    @Test func outsideBoundsUntouched() throws {
        let (photo, spot) = try Self.spotOne()
        let filled = try photo.spotted.filledFromSurroundings(spot.hole, seed: 5)
        try expectSameOutside(filled, photo.spotted, cx: Int(spot.centerX), cy: Int(spot.centerY),
                              r: Int(spot.radius) + 2)
    }

    @Test func fillsWhereNoTranslationFits() throws {
        // A hole spanning most of the width, and two holes in opposite corners:
        // no single shift of the bounds lies clear of the mask on the buffer.
        let photo = try RetouchFixtures.spottedPhoto(width: 48, height: 32, seed: 3)
        let wide = try Mask.ellipse(width: 48, height: 32, centerX: 24, centerY: 16, radiusX: 20, radiusY: 10)
        var corners = try RetouchFixtures.disc(width: 48, height: 32, centerX: 6, centerY: 6, radius: 4)
        try corners.add(RetouchFixtures.disc(width: 48, height: 32, centerX: 42, centerY: 26, radius: 4))
        for mask in [wide, corners] {
            let filled = try photo.clean.filledFromSurroundings(mask, seed: 1)
            let hole = try lumaStats(filled, under: mask), clean = try lumaStats(photo.clean, under: mask)
            #expect(abs(hole.mean - clean.mean) <= 0.03, "hole mean \(hole.mean), clean mean \(clean.mean)")
        }
    }

    @Test func patchRadiusSetsPatchSize() throws {
        let (photo, spot) = try Self.spotOne()
        let one = try photo.spotted.filledFromSurroundings(spot.hole, seed: 4, patchRadius: 1)
        let three = try photo.spotted.filledFromSurroundings(spot.hole, seed: 4, patchRadius: 3)
        #expect(one != three)
        // Radii past the cap act as the cap.
        #expect(try photo.spotted.filledFromSurroundings(spot.hole, seed: 4, patchRadius: 8)
            == photo.spotted.filledFromSurroundings(spot.hole, seed: 4, patchRadius: 64))
    }

    @Test func fullMaskThrowsWithReason() throws {
        let photo = try RetouchFixtures.spottedPhoto(width: 16, height: 12, seed: 3)
        let all = try Mask(width: 16, height: 12, fill: 1)
        #expect { try photo.spotted.filledFromSurroundings(all, seed: 1) } throws: { error in
            "\(error)".contains("covers every pixel")
        }
    }

    @Test func sparseMaskOverCapThrowsEarly() throws {
        // Two dots in opposite corners: their bounds hold 2100 x 2100 pixels,
        // over maxHealPixels, so the fill throws before any search.
        let buffer = try PixelBuffer(width: 2100, height: 2100, fill: RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1))
        var mask = try Mask(width: 2100, height: 2100)
        try mask.add(Mask.ellipse(width: 2100, height: 2100, centerX: 0.5, centerY: 0.5, radiusX: 0.5, radiusY: 0.5))
        try mask.add(Mask.ellipse(width: 2100, height: 2100, centerX: 2099.5, centerY: 2099.5, radiusX: 0.5, radiusY: 0.5))
        let clock = ContinuousClock(), start = clock.now
        #expect { try buffer.filledFromSurroundings(mask, seed: 1) } throws: { error in
            "\(error)".contains("2100x2100")
        }
        #expect(clock.now - start < .seconds(20))
    }

    @Test func picksBestMatch() throws {
        // Fine grain on the left, black and white stripes 4 px wide on the right:
        // a hole in the grain fills with grain, not stripes.
        var rng = SplitMix64(seed: 0xBE57)
        var buffer = try PixelBuffer(width: 96, height: 64)
        for y in 0..<64 {
            for x in 0..<96 {
                let v = x < 64 ? 0.5 + Float.random(in: -0.04...0.04, using: &rng) : Float(x / 4 % 2)
                try buffer.setPixel(x: x, y: y, RGBA(r: v, g: v, b: v, a: 1))
            }
        }
        let hole = try RetouchFixtures.disc(width: 96, height: 64, centerX: 24, centerY: 32, radius: 5)
        var ring = try RetouchFixtures.disc(width: 96, height: 64, centerX: 24, centerY: 32, radius: 10)
        try ring.subtract(hole)
        for seed: UInt64 in 1...4 {
            let filled = try buffer.filledFromSurroundings(hole, seed: seed)
            let inHole = try lumaStats(filled, under: hole), around = try lumaStats(filled, under: ring)
            #expect(abs(inHole.variance - around.variance) <= 0.5 * around.variance,
                    "seed \(seed): hole variance \(inHole.variance), ring variance \(around.variance)")
        }
    }

    @Test func fuzzedInputsThrowOrFill() throws {
        var rng = SplitMix64(seed: 0xF111)
        let photo = try RetouchFixtures.spottedPhoto(width: 32, height: 24, seed: 2)
        for _ in 0..<60 {
            let w = Int.random(in: 31...33, using: &rng), h = Int.random(in: 23...25, using: &rng)
            let mask = try RetouchFixtures.disc(width: w, height: h, centerX: .random(in: -4...36, using: &rng),
                                                centerY: .random(in: -4...28, using: &rng), radius: .random(in: 0...20, using: &rng))
            let radius = [Int.min, -1, 0, 1, 3, 40, Int.max].randomElement(using: &rng) ?? 3
            do {
                let filled = try photo.spotted.filledFromSurroundings(mask, seed: rng.next(), patchRadius: radius)
                #expect(w == 32 && h == 24 && radius >= 1 && filled.width == 32 && filled.height == 24)
            } catch is RasterError {
            } catch {
                Issue.record("unexpected error \(error)")
            }
        }
    }
}
