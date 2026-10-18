// EffectFixtures.swift: reference images and analytic expectations for the
// effects-engine suites (FX-2): an anti-aliased disc with its area, a 1 px
// vertical line, a noisy flat patch with a step edge (seeded SplitMix64 noise),
// and a text-like glyph mask, plus the measurements the checks read (alpha sum,
// occupied rows and columns, centroid, region mean and standard deviation, the
// 10-90% rise of an edge). Buffers are linear, premultiplied, like PixelBuffer.
import CoreRaster
import Testing

enum EffectFixtures {
    static let white = RGBA(r: 1, g: 1, b: 1, a: 1)

    /// An integer pixel rectangle, `x0..<x1` by `y0..<y1`.
    struct Region: Equatable { var x0, y0, x1, y1: Int }

    /// The exact area of a disc of `radius` pixels: pi r^2.
    static func discArea(radius: Double) -> Double { Double.pi * radius * radius }

    /// The exact area of the ring between `inner` and `outer` radii.
    static func ringArea(inner: Double, outer: Double) -> Double {
        discArea(radius: outer) - discArea(radius: max(0, inner))
    }

    /// A `size` x `size` buffer with a `color` disc of `radius` centred on the
    /// middle, anti-aliased by 4 x 4 supersampling, so its alpha sum is pi r^2
    /// to well under 1%.
    static func disc(size: Int = 64, radius: Double = 16, color: RGBA = white) throws -> PixelBuffer {
        var buffer = try PixelBuffer(width: size, height: size)
        let c = Double(size) / 2
        for y in 0..<size {
            for x in 0..<size {
                var hits = 0
                for sy in 0..<4 {
                    for sx in 0..<4 {
                        let px = Double(x) + (Double(sx) + 0.5) / 4 - c
                        let py = Double(y) + (Double(sy) + 0.5) / 4 - c
                        if px * px + py * py <= radius * radius { hits += 1 }
                    }
                }
                let k = Float(hits) / 16
                guard k > 0 else { continue }
                try buffer.setPixel(x: x, y: y, RGBA(r: color.r * k, g: color.g * k, b: color.b * k, a: color.a * k))
            }
        }
        return buffer
    }

    /// A transparent buffer with one opaque `color` column at `x`, full height.
    static func verticalLine(width: Int = 32, height: Int = 16, x: Int = 16, color: RGBA = white) throws -> PixelBuffer {
        var buffer = try PixelBuffer(width: width, height: height)
        for y in 0..<height { try buffer.setPixel(x: x, y: y, color) }
        return buffer
    }

    /// The left and right grey levels of `noisyStep`, and its noise std.
    static let stepLow: Float = 0.25, stepHigh: Float = 0.75, stepSigma: Float = 0.05

    /// An opaque grey patch: `stepLow` left of the column `width / 2`,
    /// `stepHigh` from it on, plus seeded noise of std about `stepSigma` per
    /// channel (a sum of four uniforms, near Gaussian). Same seed, same pixels.
    static func noisyStep(width: Int = 64, height: Int = 32, seed: UInt64 = 0xEFF_EC75) throws -> PixelBuffer {
        var rng = SplitMix64(seed: seed)
        var buffer = try PixelBuffer(width: width, height: height)
        // Each uniform in -1...1 has variance 1/3; four of them sum to variance 4/3.
        let scale = stepSigma / (Float(4) / 3).squareRoot()
        func noise() -> Float {
            var s: Float = 0
            for _ in 0..<4 { s += .random(in: -1...1, using: &rng) }
            return s * scale
        }
        for y in 0..<height {
            for x in 0..<width {
                let v = x < width / 2 ? stepLow : stepHigh
                try buffer.setPixel(x: x, y: y, RGBA(r: v + noise(), g: v + noise(), b: v + noise(), a: 1))
            }
        }
        return buffer
    }

    /// The opaque rectangles of a text-like glyph pair, "E" then "T", 3 px
    /// strokes on a 40 x 28 canvas, disjoint so their areas add.
    static let glyphStrokes: [Region] = [
        Region(x0: 4, y0: 4, x1: 7, y1: 24),    // E stem
        Region(x0: 7, y0: 4, x1: 16, y1: 7),    // E top arm
        Region(x0: 7, y0: 12, x1: 14, y1: 15),  // E middle arm
        Region(x0: 7, y0: 21, x1: 16, y1: 24),  // E bottom arm
        Region(x0: 20, y0: 4, x1: 36, y1: 7),   // T bar
        Region(x0: 26, y0: 7, x1: 29, y1: 24),  // T stem
    ]

    /// The glyph mask: `glyphStrokes` opaque in `color`, the rest transparent.
    static func glyphMask(color: RGBA = white) throws -> PixelBuffer {
        var buffer = try PixelBuffer(width: 40, height: 28)
        for r in glyphStrokes {
            for y in r.y0..<r.y1 { for x in r.x0..<r.x1 { try buffer.setPixel(x: x, y: y, color) } }
        }
        return buffer
    }

    /// The glyph's opaque pixel count.
    static var glyphArea: Int { glyphStrokes.reduce(0) { $0 + ($1.x1 - $1.x0) * ($1.y1 - $1.y0) } }

    // MARK: Measurements

    /// The sum of every pixel's alpha (premultiplied coverage).
    static func alphaSum(_ b: PixelBuffer) throws -> Double {
        var sum = 0.0
        for y in 0..<b.height { for x in 0..<b.width { sum += Double(try b.pixel(x: x, y: y).a) } }
        return sum
    }

    /// The columns and rows holding any alpha above `threshold`.
    static func occupied(_ b: PixelBuffer, threshold: Float = 1e-6) throws -> (columns: Set<Int>, rows: Set<Int>) {
        var columns = Set<Int>(), rows = Set<Int>()
        for y in 0..<b.height {
            for x in 0..<b.width where try b.pixel(x: x, y: y).a > threshold {
                columns.insert(x)
                rows.insert(y)
            }
        }
        return (columns, rows)
    }

    /// The alpha-weighted centroid, or nil for a fully transparent buffer.
    static func centroid(_ b: PixelBuffer) throws -> (x: Double, y: Double)? {
        var sum = 0.0, sx = 0.0, sy = 0.0
        for y in 0..<b.height {
            for x in 0..<b.width {
                let a = Double(try b.pixel(x: x, y: y).a)
                sum += a; sx += a * Double(x); sy += a * Double(y)
            }
        }
        return sum > 0 ? (sx / sum, sy / sum) : nil
    }

    /// The mean and standard deviation of the red channel over `region`.
    static func stats(_ b: PixelBuffer, _ region: Region) throws -> (mean: Double, std: Double) {
        var values: [Double] = []
        for y in region.y0..<region.y1 { for x in region.x0..<region.x1 { values.append(Double(try b.pixel(x: x, y: y).r)) } }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return (mean, variance.squareRoot())
    }

    /// The 10-90% rise of row `y`'s red channel from `low` to `high`, in
    /// pixels: the distance from the last column under 10% to the first over
    /// 90%. Nil when the row never crosses both levels.
    static func rise(_ b: PixelBuffer, row y: Int, low: Float = stepLow, high: Float = stepHigh) throws -> Int? {
        let lo = low + (high - low) * 0.1, hi = low + (high - low) * 0.9
        var lastLow: Int?, firstHigh: Int?
        for x in 0..<b.width {
            let v = try b.pixel(x: x, y: y).r
            if v < lo, firstHigh == nil { lastLow = x }
            if v > hi, firstHigh == nil, lastLow != nil { firstHigh = x }
        }
        guard let l = lastLow, let h = firstHigh else { return nil }
        return h - l
    }
}

@Suite struct EffectFixtureTests {
    @Test func fixturesBuildDeterministically() throws {
        let disc = try EffectFixtures.disc(radius: 16)
        #expect(disc == (try EffectFixtures.disc(radius: 16)))
        #expect(try EffectFixtures.noisyStep() == EffectFixtures.noisyStep())
        #expect(try EffectFixtures.noisyStep(seed: 1) != EffectFixtures.noisyStep(seed: 2))
        let line = try EffectFixtures.occupied(EffectFixtures.verticalLine())
        #expect(line.columns == [16] && line.rows.count == 16)
        #expect(try EffectFixtures.alphaSum(EffectFixtures.glyphMask()) == Double(EffectFixtures.glyphArea))
    }

    @Test func discAreaMatchesPiRSquared() throws {
        for r in [8.0, 16, 24] {
            let sum = try EffectFixtures.alphaSum(EffectFixtures.disc(radius: r))
            let area = EffectFixtures.discArea(radius: r)
            #expect(abs(sum - area) / area < 0.01)
        }
    }

    @Test func noisyStepHasItsLevelsAndNoise() throws {
        let step = try EffectFixtures.noisyStep()
        let left = try EffectFixtures.stats(step, .init(x0: 0, y0: 0, x1: 28, y1: 32))
        let right = try EffectFixtures.stats(step, .init(x0: 36, y0: 0, x1: 64, y1: 32))
        #expect(abs(left.mean - 0.25) < 0.01 && abs(right.mean - 0.75) < 0.01)
        #expect(abs(left.std - 0.05) < 0.01 && abs(right.std - 0.05) < 0.01)
        for y in [0, 15, 31] { #expect(try EffectFixtures.rise(step, row: y).map { (1...4).contains($0) } == true) }
        #expect(try EffectFixtures.centroid(EffectFixtures.disc()).map { abs($0.x - 31.5) < 1e-3 && abs($0.y - 31.5) < 1e-3 } == true)
    }
}
