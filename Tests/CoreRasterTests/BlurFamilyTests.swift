// BlurFamilyTests.swift: effects-engine FX-3's acceptance, written first (FX-1),
// on since FX-3 built `boxBlurred` and `motionBlurred`: zero is identity,
// energy is kept, motion runs along its angle in degrees, transparency never
// tints an edge, bad parameters throw. `EffectFuzz` serves every effects suite.
import CoreRaster
import Testing

/// Seeded parameter draws and the never-crash check for the effects suites.
enum EffectFuzz {
    /// A draw from `range` most of the time, else NaN, an infinity or a value
    /// past either end, so every guard is exercised.
    static func value(_ rng: inout SplitMix64, in range: ClosedRange<Double>) -> Double {
        switch rng.next() % 8 {
        case 0: return .nan
        case 1: return rng.next() % 2 == 0 ? .infinity : -.infinity
        case 2: return range.upperBound + .random(in: 0.001...1_000, using: &rng)
        case 3: return range.lowerBound - .random(in: 0.001...1_000, using: &rng)
        default: return .random(in: range, using: &rng)
        }
    }

    /// `body(input)` either throws `RasterError` or returns a buffer of the
    /// same size with finite pixels.
    static func expectThrowsOrKeepsSize(_ input: PixelBuffer, _ body: (PixelBuffer) throws -> PixelBuffer) throws {
        do {
            let out = try body(input)
            #expect(out.width == input.width && out.height == input.height)
            for y in 0..<out.height { for x in 0..<out.width { #expect(try out.pixel(x: x, y: y).isFinite) } }
        } catch is RasterError {}
    }
}

@Suite struct BlurFamilyTests {
    let red = RGBA(r: 1, g: 0, b: 0, a: 1)

    /// A transparent `width` x `height` buffer with one opaque white pixel.
    func dot(width: Int = 32, height: Int = 32, x: Int = 16, y: Int = 16) throws -> PixelBuffer {
        var b = try PixelBuffer(width: width, height: height)
        try b.setPixel(x: x, y: y, EffectFixtures.white)
        return b
    }

    @Test func zeroIsIdentity() throws {
        let b = try EffectFixtures.noisyStep(width: 12, height: 9)
        #expect(try b.boxBlurred(radius: 0) == b)
        for degrees in [0.0, 33, 90, 270] { #expect(try b.motionBlurred(degrees: degrees, distance: 0) == b) }
    }

    @Test func boxKeepsEnergy() throws {
        let disc = try EffectFixtures.disc(size: 64, radius: 16)
        let before = try EffectFixtures.alphaSum(disc)
        for radius in [1.0, 2.5, 4] {
            let blurred = try disc.boxBlurred(radius: radius)
            #expect(abs(try EffectFixtures.alphaSum(blurred) - before) / before <= 1e-4)
            #expect(try EffectFixtures.occupied(blurred).columns.count > EffectFixtures.occupied(disc).columns.count)
        }
    }

    @Test func motionSpreadsTen() throws {
        let line = try EffectFixtures.verticalLine(width: 32, height: 16, x: 16)
        let blurred = try line.motionBlurred(degrees: 0, distance: 9)
        let occupied = try EffectFixtures.occupied(blurred)
        #expect(occupied.columns.count == 10 && occupied.columns.contains(16))
        if let lo = occupied.columns.min(), let hi = occupied.columns.max() { #expect(hi - lo == 9) }
        #expect(occupied.rows == Set(0..<16))
        #expect(abs(try EffectFixtures.alphaSum(blurred) - 16) <= 16e-4)
    }

    @Test func horizontalSpreadsColumns() throws {
        for (degrees, alongX) in [(0.0, true), (180, true), (90, false), (270, false)] {
            let o = try EffectFixtures.occupied(dot().motionBlurred(degrees: degrees, distance: 9))
            #expect(alongX ? o.rows == [16] && o.columns.count == 10 : o.columns == [16] && o.rows.count == 10, "\(degrees)")
        }
    }

    @Test func noBleedFromTransparent() throws {
        var half = try PixelBuffer(width: 24, height: 12)
        for y in 0..<12 { for x in 0..<12 { try half.setPixel(x: x, y: y, red) } }
        for blurred in [try half.boxBlurred(radius: 3), try half.motionBlurred(degrees: 0, distance: 7)] {
            for y in 0..<12 {
                for x in 0..<24 where try blurred.pixel(x: x, y: y).a > 1e-3 {
                    let u = try blurred.pixel(x: x, y: y).unpremultiplied()
                    #expect(abs(u.r - 1) <= 1e-3 && abs(u.g) <= 1e-3 && abs(u.b) <= 1e-3, "(\(x), \(y))")
                }
            }
        }
    }

    @Test func overCapThrows() throws {
        let b = try dot(width: 8, height: 8, x: 4, y: 4)
        for bad in [2_000.0, 1_000.5, -1, .nan, .infinity] {
            #expect(throws: RasterError.self) { try b.boxBlurred(radius: bad) }
            #expect(throws: RasterError.self) { try b.motionBlurred(degrees: 0, distance: bad) }
        }
        #expect(throws: RasterError.self) { try b.motionBlurred(degrees: .nan, distance: 3) }
    }

    @Test func fuzzNeverCrashes() throws {
        var rng = SplitMix64(seed: 0xB1_0F)
        let input = try dot(width: 8, height: 8, x: 3, y: 5)
        for _ in 0..<200 {
            let radius = EffectFuzz.value(&rng, in: 0...1_000), distance = EffectFuzz.value(&rng, in: 0...1_000)
            let degrees = EffectFuzz.value(&rng, in: -720...720)
            try EffectFuzz.expectThrowsOrKeepsSize(input) { try $0.boxBlurred(radius: radius) }
            try EffectFuzz.expectThrowsOrKeepsSize(input) { try $0.motionBlurred(degrees: degrees, distance: distance) }
        }
    }
}
