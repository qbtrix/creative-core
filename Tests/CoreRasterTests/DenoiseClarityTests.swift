// DenoiseClarityTests.swift: effects-engine FX-4's acceptance, written first
// (FX-1), on since FX-4 built `denoised` and `clarity`: denoise cuts noise
// 60% and keeps the edge, clarity moves contrast and not the mean or
// the ends, zero is identity, bad parameters throw.
import CoreRaster
import Testing

@Suite struct DenoiseClarityTests {
    /// The noisy step's flat halves, clear of the edge at column 32.
    let left = EffectFixtures.Region(x0: 0, y0: 0, x1: 28, y1: 32)
    let right = EffectFixtures.Region(x0: 36, y0: 0, x1: 64, y1: 32)
    let all = EffectFixtures.Region(x0: 0, y0: 0, x1: 64, y1: 64)

    /// An opaque 64 x 64 grey texture: seeded values in `levels`, grey per pixel.
    func texture(_ levels: ClosedRange<Float>, seed: UInt64) throws -> PixelBuffer {
        var rng = SplitMix64(seed: seed)
        var b = try PixelBuffer(width: 64, height: 64)
        for i in 0..<64 * 64 {
            let v = Float.random(in: levels, using: &rng)
            try b.setPixel(x: i % 64, y: i / 64, RGBA(r: v, g: v, b: v, a: 1))
        }
        return b
    }

    @Test func zeroIsIdentity() throws {
        let step = try EffectFixtures.noisyStep()
        for detail in [0.0, 0.5, 1] { #expect(try step.denoised(strength: 0, detail: detail) == step) }
        for radius in [1.0, 30] { #expect(try step.clarity(amount: 0, radius: radius) == step) }
    }

    @Test func noiseDrops() throws {
        let step = try EffectFixtures.noisyStep()
        let out = try step.denoised(strength: 1, detail: 0)
        for region in [left, right] {
            let before = try EffectFixtures.stats(step, region), after = try EffectFixtures.stats(out, region)
            #expect(after.std <= 0.4 * before.std)
            #expect(abs(after.mean - before.mean) <= 0.01)
        }
    }

    @Test func edgeKept() throws {
        // The clean step rises in 1 px (column 31 to 32); denoised, within 1 px of that.
        let out = try EffectFixtures.noisyStep().denoised(strength: 1, detail: 0)
        for y in 0..<32 {
            let rise = try EffectFixtures.rise(out, row: y)
            #expect(rise.map { $0 <= 2 } == true, "row \(y) rises over \(String(describing: rise)) px")
        }
    }

    @Test func denoiseCoversLinesPastTheBandCount() throws {
        // The bilateral runs its rows (then its transposed columns) in 64
        // parallel bands, each striding through every 64th line. A region
        // past row and column 64 is smoothed only if every band reaches its
        // later lines in both passes.
        let step = try EffectFixtures.noisyStep(width: 160, height: 140)
        let far = EffectFixtures.Region(x0: 100, y0: 100, x1: 140, y1: 130)
        let before = try EffectFixtures.stats(step, far)
        let after = try EffectFixtures.stats(step.denoised(strength: 1, detail: 0), far)
        #expect(after.std <= 0.4 * before.std, "std \(after.std) of \(before.std) past line 64")
    }

    @Test func detailOneSmoothsOnlyEqualGuides() throws {
        // Detail 1 is range sigma 0: only taps with exactly the centre's luma
        // weigh in. Every noisy pixel's luma differs, so nothing smooths.
        let step = try EffectFixtures.noisyStep()
        let out = try step.denoised(strength: 1, detail: 1)
        for region in [left, right] {
            let before = try EffectFixtures.stats(step, region), after = try EffectFixtures.stats(out, region)
            #expect(after.std >= 0.9 * before.std, "std \(after.std) of \(before.std) at detail 1")
        }
    }

    @Test func chromaSmoothedAtTwiceSigma() throws {
        // Equal luma everywhere, colour noise per pixel: only the chroma pass
        // acts. At strength 0.5 (sigma 3) a Gaussian of sigma 6 leaves about
        // 0.05 of iid noise's std, one of sigma 3 about 0.09.
        var rng = SplitMix64(seed: 0xC4_0A)
        var b = try PixelBuffer(width: 64, height: 64)
        let w = Histogram.luminanceWeights
        for i in 0..<64 * 64 {
            let r = Float.random(in: 0.2...0.8, using: &rng), blue = Float.random(in: 0.2...0.8, using: &rng)
            try b.setPixel(x: i % 64, y: i / 64, RGBA(r: r, g: (0.5 - w.r * r - w.b * blue) / w.g, b: blue, a: 1))
        }
        let middle = EffectFixtures.Region(x0: 16, y0: 16, x1: 48, y1: 48)
        let before = try EffectFixtures.stats(b, middle)
        let after = try EffectFixtures.stats(b.denoised(strength: 0.5, detail: 0), middle)
        #expect(after.std <= 0.07 * before.std, "chroma std \(after.std) of \(before.std)")
    }

    @Test func transparentLendsNoColour() throws {
        // An opaque red square on clear: averaging premultiplied colour over
        // alpha keeps its edge pure red, not diluted toward black.
        var b = try PixelBuffer(width: 32, height: 32)
        for y in 8..<24 { for x in 8..<24 { try b.setPixel(x: x, y: y, RGBA(r: 1, g: 0, b: 0, a: 1)) } }
        let out = try b.denoised(strength: 1, detail: 0.5)
        for i in 8..<24 {
            for (x, y) in [(8, i), (23, i), (i, 8), (i, 23)] {
                let p = try out.pixel(x: x, y: y)
                #expect(abs(p.a - 1) <= 1e-6)
                #expect(abs(p.r - 1) <= 1e-4 && abs(p.g) <= 1e-4 && abs(p.b) <= 1e-4, "(\(x), \(y)) is \(p)")
            }
        }
    }

    @Test func clarityOverflowThrows() throws {
        // A mid-grey pixel among near-transparent ones of huge negative red:
        // its blurred straight red is about -3e40, past Float's range.
        var b = try PixelBuffer(width: 61, height: 61, fill: RGBA(r: -3e38, g: 0, b: 0, a: 0.01))
        try b.setPixel(x: 30, y: 30, RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1))
        #expect(throws: RasterError.self) { try b.clarity(amount: 100, radius: 30) }
    }

    @Test func clarityOverflowNamesTheSource() throws {
        // The amount is valid; the overflow comes from the source's huge components.
        var b = try PixelBuffer(width: 61, height: 61, fill: RGBA(r: -3e38, g: 0, b: 0, a: 0.01))
        try b.setPixel(x: 30, y: 30, RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1))
        let error = #expect(throws: RasterError.self) { try b.clarity(amount: 100, radius: 30) }
        guard case .invalid(let why) = try #require(error) else { return }
        #expect(why.contains("source pixel components") && !why.contains("amount 100"), "\(why)")
    }

    @Test func denoiseOverflowThrows() throws {
        // Opaque black among pixels of alpha 1/128, premultiplied red 3e38 and
        // luma exactly 0, so every guide is 0 and they all weigh in: the
        // centre's straight red averages toward 3e38 x 128, past Float's range.
        let w = Histogram.luminanceWeights, r: Float = 3e38, g = -(w.r * r) / w.g
        var blue = -(w.r * r + w.g * g) / w.b
        for _ in 0..<4_096 where w.r * r + w.g * g + w.b * blue != 0 {
            blue = w.r * r + w.g * g + w.b * blue > 0 ? blue.nextDown : blue.nextUp
        }
        try #require(w.r * r + w.g * g + w.b * blue == 0)
        var b = try PixelBuffer(width: 15, height: 15, fill: RGBA(r: r, g: g, b: blue, a: 1.0 / 128))
        try b.setPixel(x: 7, y: 7, RGBA(r: 0, g: 0, b: 0, a: 1))
        let error = #expect(throws: RasterError.self) { try b.denoised(strength: 1, detail: 1) }
        guard case .invalid(let why) = try #require(error) else { return }
        #expect(why.contains("source pixel components"), "\(why)")
    }

    @Test func denoiseOverItsPixelCapThrows() throws {
        // One row one pixel past the cap: cheap to build, refused before denoise allocates.
        let b = try PixelBuffer(width: PixelBuffer.maxDenoisePixels + 1, height: 1)
        let error = #expect(throws: RasterError.self) { try b.denoised(strength: 0.5, detail: 0.5) }
        guard case .invalid(let why) = try #require(error) else { return }
        #expect(why.contains("\(PixelBuffer.maxDenoisePixels + 1)x1"), "\(why)")
    }

    @Test func extremeValuesThrowOrStayFinite() throws {
        // Components anywhere in Float's range, alphas from 1e-30 to 1.
        var rng = SplitMix64(seed: 0xE7_7E3E)
        for _ in 0..<40 {
            var b = try PixelBuffer(width: 9, height: 9)
            for i in 0..<81 {
                var a = Float.random(in: 0.1...1, using: &rng)
                for _ in 0..<rng.next() % 30 { a *= 0.1 }
                // Drawn in Double: Float's own -max...max spans an infinite width.
                let m = Double(Float.greatestFiniteMagnitude)
                var part = [Float](repeating: 0, count: 3)
                for k in 0..<3 { part[k] = Float(Double.random(in: -m...m, using: &rng)) }
                try b.setPixel(x: i % 9, y: i / 9, RGBA(r: part[0], g: part[1], b: part[2], a: a))
            }
            try EffectFuzz.expectThrowsOrKeepsSize(b) { try $0.denoised(strength: 1, detail: 0.5) }
            try EffectFuzz.expectThrowsOrKeepsSize(b) { try $0.clarity(amount: 100, radius: 6) }
        }
    }

    @Test func clarityRaisesContrastKeepsMean() throws {
        let grey = try texture(0.4...0.6, seed: 0xC1A_7)
        let before = try EffectFixtures.stats(grey, all)
        let up = try EffectFixtures.stats(grey.clarity(amount: 50, radius: 30), all)
        #expect(up.std > before.std * 1.05)
        #expect(abs(up.mean - before.mean) <= 1.0 / 255)
        let down = try EffectFixtures.stats(grey.clarity(amount: -50, radius: 30), all)
        #expect(down.std < before.std * 0.95)
        #expect(abs(down.mean - before.mean) <= 1.0 / 255)
    }

    @Test func highlightsUnclipped() throws {
        // Luma at the ends has mid-tone weight 0, so full clarity can't push it past 0...1.
        for levels: ClosedRange<Float> in [0.96...1, 0...0.04] {
            let out = try texture(levels, seed: 0x416_4).clarity(amount: 100, radius: 30)
            for y in 0..<64 { for x in 0..<64 { #expect((-1e-6...(1 + 1e-6)).contains(try out.pixel(x: x, y: y).r)) } }
        }
    }

    @Test func overCapThrows() throws {
        let b = try PixelBuffer(width: 8, height: 8, fill: RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1))
        for bad in [1.5, -0.1, .nan, .infinity] {
            #expect(throws: RasterError.self) { try b.denoised(strength: bad, detail: 0.5) }
            #expect(throws: RasterError.self) { try b.denoised(strength: 0.5, detail: bad) }
        }
        for bad in [100.5, -101, .nan, -.infinity] { #expect(throws: RasterError.self) { try b.clarity(amount: bad, radius: 30) } }
        for bad in [2_000.0, -1, .nan] { #expect(throws: RasterError.self) { try b.clarity(amount: 30, radius: bad) } }
    }

    /// The radius cap is inclusive: 1,000 is accepted, the next Double up
    /// throws. Past twice the larger side less one the kernel is capped, so
    /// on an 8 x 8 buffer radius 1,000 blurs exactly as radius 15 does.
    @Test func clarityRadiusCapIsInclusive() throws {
        let small = try EffectFixtures.noisyStep(width: 8, height: 8)
        let capped = try small.clarity(amount: 50, radius: 1_000)
        #expect(capped == (try small.clarity(amount: 50, radius: 15)) && capped != small)
        let past = 1_000.0.nextUp
        #expect(throws: RasterError.invalid("clarity radius \(past): must be finite and in 0...1000")) {
            try small.clarity(amount: 50, radius: past)
        }
    }

    @Test func fuzzNeverCrashes() throws {
        var rng = SplitMix64(seed: 0xDE_401)
        let input = try EffectFixtures.noisyStep(width: 8, height: 8)
        for _ in 0..<200 {
            let strength = EffectFuzz.value(&rng, in: 0...1), detail = EffectFuzz.value(&rng, in: 0...1)
            let amount = EffectFuzz.value(&rng, in: -100...100), radius = EffectFuzz.value(&rng, in: 0...1_000)
            try EffectFuzz.expectThrowsOrKeepsSize(input) { try $0.denoised(strength: strength, detail: detail) }
            try EffectFuzz.expectThrowsOrKeepsSize(input) { try $0.clarity(amount: amount, radius: radius) }
        }
    }

    @Test func denoiseCapErrorNamesTheLimitAndRemedy() throws {
        // The cap is denoise's own, not `maxPixels`: the error names it and how to get under it.
        let b = try PixelBuffer(width: PixelBuffer.maxDenoisePixels + 1, height: 1)
        let error = #expect(throws: RasterError.self) { try b.applying(.denoise(strength: 0.5, detail: 0.5)) }
        guard case .invalid(let why) = try #require(error) else { return }
        #expect(why.contains("maxDenoisePixels (\(PixelBuffer.maxDenoisePixels))") && why.contains("tiles"), "\(why)")
    }
}
