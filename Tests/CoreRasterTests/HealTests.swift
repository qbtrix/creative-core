// HealTests.swift: retouch-heal RH-3's acceptance, written first by RH-1
// (docs/blueprints/core/features/retouch-heal.md); RH-3 turned it on.
import CoreRaster
import Testing

/// Every pixel outside the square of half-side `r` around (`cx`, `cy`) is the same in both.
func expectSameOutside(_ a: PixelBuffer, _ b: PixelBuffer, cx: Int, cy: Int, r: Int) throws {
    for y in 0..<a.height {
        for x in 0..<a.width where abs(x - cx) > r || abs(y - cy) > r {
            #expect(try a.pixel(x: x, y: y) == b.pixel(x: x, y: y), "(\(x), \(y))")
        }
    }
}

@Suite struct HealTests {
    static let tolerance: Float = 1 / 255

    @Test func reproducesField() throws {
        let field = try RetouchFixtures.gradientField(width: 64, height: 48)
        let mask = try RetouchFixtures.disc(width: 64, height: 48, centerX: 44, centerY: 24, radius: 8)
        let healed = try field.healed(offset: (dx: -24, dy: 2), through: mask)
        for y in 0..<48 {
            for x in 0..<64 where try mask.coverage(x: x, y: y) > 0 {
                let p = try healed.pixel(x: x, y: y), f = RetouchFixtures.fieldValue(x: x, y: y)
                let gap = max(abs(p.r - f.r), abs(p.g - f.g), abs(p.b - f.b), abs(p.a - f.a))
                #expect(gap <= Self.tolerance, "(\(x), \(y)) off the field by \(gap)")
            }
        }
    }

    @Test func matchesDestinationEdge() throws {
        // The source half is the field lifted by 0.2: the same gradients, the
        // wrong tone. The edge comes from the destination, so no seam shows.
        var buffer = try RetouchFixtures.gradientField(width: 64, height: 48)
        for y in 0..<48 {
            for x in 0..<32 {
                let p = RetouchFixtures.fieldValue(x: x, y: y)
                try buffer.setPixel(x: x, y: y, RGBA(r: p.r + 0.2, g: p.g + 0.2, b: p.b + 0.2, a: 1))
            }
        }
        let mask = try RetouchFixtures.disc(width: 64, height: 48, centerX: 48, centerY: 24, radius: 8)
        let healed = try buffer.healed(offset: (dx: -32, dy: 0), through: mask)
        for y in 1..<47 {
            for x in 33..<63 where try mask.coverage(x: x, y: y) > 0 {
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where try mask.coverage(x: nx, y: ny) == 0 {
                    let a = try healed.pixel(x: x, y: y), b = try healed.pixel(x: nx, y: ny)
                    let fa = RetouchFixtures.fieldValue(x: x, y: y), fb = RetouchFixtures.fieldValue(x: nx, y: ny)
                    let error = max(abs((a.r - b.r) - (fa.r - fb.r)), abs((a.g - b.g) - (fa.g - fb.g)),
                                    abs((a.b - b.b) - (fa.b - fb.b)))
                    #expect(error <= Self.tolerance, "seam at (\(x), \(y)): gradient error \(error)")
                }
            }
        }
    }

    @Test func outsideBoundsUntouched() throws {
        let photo = try RetouchFixtures.spottedPhoto(width: 160, height: 96, seed: 31)
        let spot = try #require(photo.spots.last)
        let healed = try photo.spotted.healed(offset: (dx: -30, dy: 0), through: spot.hole)
        try expectSameOutside(healed, photo.spotted, cx: Int(spot.centerX), cy: Int(spot.centerY),
                              r: Int(spot.radius) + 2)
        #expect(healed != photo.spotted)
    }

    @Test func overMaxHealPixelsThrows() throws {
        let buffer = try PixelBuffer(width: 2001, height: 2000, fill: RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1))
        let mask = try Mask(width: 2001, height: 2000, fill: 1)
        #expect(mask.area > Double(PixelBuffer.maxHealPixels))
        #expect(throws: RasterError.self) { try buffer.healed(offset: (dx: 0, dy: 0), through: mask) }
    }

    @Test func zeroOffsetFullMaskIsIdentity() throws {
        let photo = try RetouchFixtures.spottedPhoto(width: 48, height: 32, seed: 5)
        let mask = try Mask(width: 48, height: 32, fill: 1)
        #expect(try photo.spotted.healed(offset: (dx: 0, dy: 0), through: mask) == photo.spotted)
    }

    @Test func offsetOffBufferThrows() throws {
        let field = try RetouchFixtures.gradientField(width: 64, height: 48)
        let mask = try RetouchFixtures.disc(width: 64, height: 48, centerX: 12, centerY: 24, radius: 8)
        for offset in [(dx: -15, dy: 0), (dx: 1000, dy: 0), (dx: 0, dy: 30), (dx: Int.min, dy: Int.max)] {
            #expect(throws: RasterError.self) { try field.healed(offset: offset, through: mask) }
        }
        let small = try Mask(width: 10, height: 10, fill: 1)
        #expect(throws: RasterError.self) { try field.healed(offset: (dx: 0, dy: 0), through: small) }
    }

    @Test func fuzzedInputsThrowOrHeal() throws {
        var rng = SplitMix64(seed: 0x4EA1)
        let field = try RetouchFixtures.gradientField(width: 32, height: 24)
        for _ in 0..<200 {
            let mask = try RetouchFixtures.disc(width: .random(in: 30...34, using: &rng), height: .random(in: 22...26, using: &rng),
                                                centerX: .random(in: -4...36, using: &rng),
                                                centerY: .random(in: -4...28, using: &rng),
                                                radius: .random(in: 0...12, using: &rng))
            let dx = [Int.min, Int.max, -33, 33, .random(in: -40...40, using: &rng)].randomElement(using: &rng) ?? 0
            do {
                let healed = try field.healed(offset: (dx: dx, dy: .random(in: -30...30, using: &rng)), through: mask)
                #expect(healed.width == 32 && healed.height == 24)
            } catch is RasterError {
            } catch {
                Issue.record("unexpected error \(error)")
            }
        }
    }
}
