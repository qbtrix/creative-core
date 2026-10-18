// DenoiseClarityTests.swift: effects-engine FX-4's acceptance, written first
// (FX-1), disabled until FX-4 builds `denoised` and `clarity`: denoise cuts
// noise 60% and keeps the edge, clarity moves contrast and not the mean or
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

    @Test(.disabled("waits on FX-4")) func zeroIsIdentity() throws {
        let step = try EffectFixtures.noisyStep()
        for detail in [0.0, 0.5, 1] { #expect(try step.denoised(strength: 0, detail: detail) == step) }
        for radius in [1.0, 30] { #expect(try step.clarity(amount: 0, radius: radius) == step) }
    }

    @Test(.disabled("waits on FX-4")) func noiseDrops() throws {
        let step = try EffectFixtures.noisyStep()
        let out = try step.denoised(strength: 1, detail: 0)
        for region in [left, right] {
            let before = try EffectFixtures.stats(step, region), after = try EffectFixtures.stats(out, region)
            #expect(after.std <= 0.4 * before.std)
            #expect(abs(after.mean - before.mean) <= 0.01)
        }
    }

    @Test(.disabled("waits on FX-4")) func edgeKept() throws {
        // The clean step rises in 1 px (column 31 to 32); denoised, within 1 px of that.
        let out = try EffectFixtures.noisyStep().denoised(strength: 1, detail: 0)
        for y in 0..<32 {
            let rise = try EffectFixtures.rise(out, row: y)
            #expect(rise.map { $0 <= 2 } == true, "row \(y) rises over \(String(describing: rise)) px")
        }
    }

    @Test(.disabled("waits on FX-4")) func clarityRaisesContrastKeepsMean() throws {
        let grey = try texture(0.4...0.6, seed: 0xC1A_7)
        let before = try EffectFixtures.stats(grey, all)
        let up = try EffectFixtures.stats(grey.clarity(amount: 50, radius: 30), all)
        #expect(up.std > before.std * 1.05)
        #expect(abs(up.mean - before.mean) <= 1.0 / 255)
        let down = try EffectFixtures.stats(grey.clarity(amount: -50, radius: 30), all)
        #expect(down.std < before.std * 0.95)
        #expect(abs(down.mean - before.mean) <= 1.0 / 255)
    }

    @Test(.disabled("waits on FX-4")) func highlightsUnclipped() throws {
        // Luma at the ends has mid-tone weight 0, so full clarity can't push it past 0...1.
        for levels: ClosedRange<Float> in [0.96...1, 0...0.04] {
            let out = try texture(levels, seed: 0x416_4).clarity(amount: 100, radius: 30)
            for y in 0..<64 { for x in 0..<64 { #expect((-1e-6...(1 + 1e-6)).contains(try out.pixel(x: x, y: y).r)) } }
        }
    }

    @Test(.disabled("waits on FX-4")) func overCapThrows() throws {
        let b = try PixelBuffer(width: 8, height: 8, fill: RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1))
        for bad in [1.5, -0.1, .nan, .infinity] {
            #expect(throws: RasterError.self) { try b.denoised(strength: bad, detail: 0.5) }
            #expect(throws: RasterError.self) { try b.denoised(strength: 0.5, detail: bad) }
        }
        for bad in [100.5, -101, .nan, -.infinity] { #expect(throws: RasterError.self) { try b.clarity(amount: bad, radius: 30) } }
        for bad in [2_000.0, -1, .nan] { #expect(throws: RasterError.self) { try b.clarity(amount: 30, radius: bad) } }
    }

    @Test(.disabled("waits on FX-4")) func fuzzNeverCrashes() throws {
        var rng = SplitMix64(seed: 0xDE_401)
        let input = try EffectFixtures.noisyStep(width: 8, height: 8)
        for _ in 0..<200 {
            let strength = EffectFuzz.value(&rng, in: 0...1), detail = EffectFuzz.value(&rng, in: 0...1)
            let amount = EffectFuzz.value(&rng, in: -100...100), radius = EffectFuzz.value(&rng, in: 0...1_000)
            try EffectFuzz.expectThrowsOrKeepsSize(input) { try $0.denoised(strength: strength, detail: detail) }
            try EffectFuzz.expectThrowsOrKeepsSize(input) { try $0.clarity(amount: amount, radius: radius) }
        }
    }
}
