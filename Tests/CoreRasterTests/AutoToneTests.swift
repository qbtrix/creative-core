// AutoToneTests.swift: tone-pack TP-6's acceptance, written first (TP-1 of
// docs/blueprints/core/features/tone-pack.md): `AutoTone.suggest`. A suggestion
// is applied as `whiteBalance` then `levels` (linear, output 0...1).
import CoreRaster
import Testing

@Suite struct AutoToneTests {
    static func expectIdentity(_ t: AutoTone, _ name: String) {
        let values = [t.inBlack, t.inWhite, t.gamma, t.temperature, t.tint]
        #expect(values.allSatisfy { $0.isFinite }, "\(name): \(t)")
        #expect(zip(values, [0, 1, 1, 0, 0] as [Float]).allSatisfy { abs($0 - $1) <= 1e-3 }, "\(name): \(t)")
    }

    /// The mean straight encoded rgb of the cast photo's grey patch.
    static func patchMean(_ b: PixelBuffer, _ photo: ToneFixtures.CastPhoto) throws -> SIMD3<Double> {
        let p = photo.patch
        var sum = SIMD3<Double>.zero
        for y in p.y..<p.y + p.height {
            for x in p.x..<p.x + p.width { sum += ToneCheck.encoded(try b.pixel(x: x, y: y)) }
        }
        return sum / Double(p.width * p.height)
    }

    @Test func castNeutralised() throws {
        let photo = try ToneFixtures.castPhoto()
        let t = try AutoTone.suggest(for: photo.buffer)
        let fixed = try photo.buffer.whiteBalance(temperature: t.temperature, tint: t.tint)
            .levels(inBlack: t.inBlack, inWhite: t.inWhite, gamma: t.gamma, outBlack: 0, outWhite: 1)
        #expect(ToneCheck.spread(try Self.patchMean(photo.buffer, photo)) > 2.0 / 255)
        #expect(ToneCheck.spread(try Self.patchMean(fixed, photo)) <= 2.0 / 255, "\(t)")
    }

    /// A linear grey ramp, symmetric about 0.5, with 3 columns (0.3%) at
    /// each of 0 and 1: the 0.1% points are 0 and 1, the median 0.5.
    @Test func rampIsIdentity() throws {
        var ramp = try PixelBuffer(width: 1024, height: 4)
        for y in 0..<4 {
            for x in 0..<1024 {
                let v = min(1, max(0, Float(x - 2) / 1019))
                try ramp.setPixel(x: x, y: y, RGBA(r: v, g: v, b: v, a: 1))
            }
        }
        Self.expectIdentity(try AutoTone.suggest(for: ramp), "ramp")
    }

    @Test func blackSuggestsIdentity() throws {
        let black = try PixelBuffer(width: 32, height: 32, fill: RGBA(r: 0, g: 0, b: 0, a: 1))
        Self.expectIdentity(try AutoTone.suggest(for: black), "black")
        Self.expectIdentity(try AutoTone.suggest(for: PixelBuffer(width: 32, height: 32)), "transparent")
    }

    /// A grey ramp over 0.2...0.6 whose lower half fills 0.2...0.3 and upper
    /// half 0.3...0.6, so the median is 0.3: black ≈ 0.2, white ≈ 0.6, and
    /// t = 0.25 wants gamma log(0.25)/log(0.5) = 2, which lifts the median to 0.5.
    @Test func levelsStretchAndCentreMedian() throws {
        var ramp = try PixelBuffer(width: 1024, height: 4)
        for y in 0..<4 {
            for x in 0..<1024 {
                let low = 0.2 + 0.1 * (Float(x) + 0.5) / 512, high = 0.3 + 0.3 * (Float(x - 512) + 0.5) / 512
                let v = x < 512 ? low : high
                try ramp.setPixel(x: x, y: y, RGBA(r: v, g: v, b: v, a: 1))
            }
        }
        let t = try AutoTone.suggest(for: ramp)
        #expect(abs(t.inBlack - 0.2) <= 1e-2, "\(t)")
        #expect(abs(t.inWhite - 0.6) <= 1e-2, "\(t)")
        #expect(abs(t.gamma - 2) <= 1e-2, "\(t)")
        #expect(abs(t.temperature) <= 1e-3 && abs(t.tint) <= 1e-3, "\(t)")
        let fixed = try ramp.whiteBalance(temperature: t.temperature, tint: t.tint)
            .levels(inBlack: t.inBlack, inWhite: t.inWhite, gamma: t.gamma, outBlack: 0, outWhite: 1)
        var row = [Float]()
        for x in 0..<1024 { row.append(try fixed.pixel(x: x, y: 0).r) }
        row.sort()
        let median = (row[511] + row[512]) / 2
        #expect(abs(median - 0.5) <= 1e-2, "median \(median), \(t)")
    }

    /// Applies `t` as a suggestion is applied: white balance, then levels.
    static func applied(_ t: AutoTone, to b: PixelBuffer) throws -> PixelBuffer {
        try b.whiteBalance(temperature: t.temperature, tint: t.tint)
            .levels(inBlack: t.inBlack, inWhite: t.inWhite, gamma: t.gamma, outBlack: 0, outWhite: 1)
    }

    /// The cast photo with its right-most 10% of columns a warm white whose
    /// red clips: the whole top 5% by luma is clipped, so only the
    /// non-clipped pixels can set the balance.
    @Test func castNeutralisedWithClippedHighlights() throws {
        let photo = try ToneFixtures.castPhoto()
        var b = photo.buffer
        for y in 0..<b.height {
            for x in b.width - b.width / 10..<b.width { try b.setPixel(x: x, y: y, RGBA(r: 1, g: 0.95, b: 0.8, a: 1)) }
        }
        let t = try AutoTone.suggest(for: b)
        #expect(t.temperature != 0, "\(t)")
        #expect(ToneCheck.spread(try Self.patchMean(try Self.applied(t, to: b), photo)) <= 2.0 / 255, "\(t)")
    }

    /// The cast photo with a seeded 3% of pixels a bright, strongly cast
    /// colour whose red is clamped to 1: they must stay out of the balance.
    @Test func clippedHighlightsIgnored() throws {
        let photo = try ToneFixtures.castPhoto()
        var b = photo.buffer, rng = SplitMix64(seed: 0xC11)
        for _ in 0..<b.width * b.height * 3 / 100 {
            let x = Int.random(in: 0..<b.width, using: &rng), y = Int.random(in: 0..<b.height, using: &rng)
            let p = photo.patch
            if (p.x..<p.x + p.width).contains(x), (p.y..<p.y + p.height).contains(y) { continue }
            try b.setPixel(x: x, y: y, RGBA(r: 1, g: 0.9, b: 0.5, a: 1))
        }
        let t = try AutoTone.suggest(for: b)
        #expect(ToneCheck.spread(try Self.patchMean(try Self.applied(t, to: b), photo)) <= 2.0 / 255, "\(t)")
    }

    /// A cool lower 94% (greys 0.2...0.6) under a warm top 6% (grey 0.8):
    /// the brightest 5% are all warm, so the balance neutralises the warm
    /// highlight and cools the picture.
    @Test func balanceReadsBrightestFivePercent() throws {
        let cool: SIMD3<Float> = [0.85, 1, 1.08], warm: SIMD3<Float> = [1.08, 1, 0.85]
        var b = try PixelBuffer(width: 100, height: 20)
        for y in 0..<20 {
            for x in 0..<100 {
                let c = x < 94 ? SIMD3(repeating: 0.2 + 0.4 * Float(x) / 93) * cool : SIMD3(repeating: 0.8) * warm
                try b.setPixel(x: x, y: y, RGBA(r: c.x, g: c.y, b: c.z, a: 1))
            }
        }
        let t = try AutoTone.suggest(for: b)
        #expect(t.temperature < 0, "\(t)")
        let balanced = try b.whiteBalance(temperature: t.temperature, tint: t.tint)
        #expect(ToneCheck.spread(ToneCheck.encoded(try balanced.pixel(x: 99, y: 0))) <= 2.0 / 255, "\(t)")
    }

    /// A cast far past the sliders (bright-set gains 2.5, 1, 0.3) suggests
    /// the slider ends, not values `whiteBalance` refuses.
    @Test func extremeCastClampsToSliderRange() throws {
        var b = try PixelBuffer(width: 16, height: 16)
        for y in 0..<16 {
            for x in 0..<16 {
                let c = SIMD3(repeating: 0.1 + 0.2 * Float(x) / 15) * SIMD3<Float>(2.5, 1, 0.3)
                try b.setPixel(x: x, y: y, RGBA(r: c.x, g: c.y, b: c.z, a: 1))
            }
        }
        let t = try AutoTone.suggest(for: b)
        #expect(t.temperature == -100, "\(t)")
        #expect(abs(t.tint) <= 100, "\(t)")
    }

    /// A finite component so large that the balance's gain overflows it
    /// throws a typed error instead of giving an infinite pixel.
    @Test func overflowingComponentThrows() throws {
        var b = try PixelBuffer(width: 16, height: 16, fill: RGBA(r: 0.54, g: 0.5, b: 0.425, a: 1))
        try b.setPixel(x: 0, y: 0, RGBA(r: 0.5, g: 0.5, b: Float.greatestFiniteMagnitude / 1.01, a: 1))
        #expect(throws: RasterError.self) { try AutoTone.suggest(for: b) }
    }
}
