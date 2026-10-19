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
}
