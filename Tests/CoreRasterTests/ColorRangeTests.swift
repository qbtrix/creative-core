// ColorRangeTests.swift: fill-tools FT-4's acceptance, written first (FT-1); FT-4
// removes the `.disabled` traits. Distances come from `FillCheck` (FloodFillTests).
import CoreRaster
import Testing

@Suite struct ColorRangeTests {
    /// The packet's falloff: `1 - smoothstep(0, f, d)`.
    private func falloff(_ d: Double, fuzziness f: Double) -> Double {
        let x = min(max(d / f, 0), 1)
        return 1 - x * x * (3 - 2 * x)
    }

    @Test(.disabled("waits on FT-4"))
    func fuzzinessZeroCoversOnlyExactMatches() throws {
        let scene = try FillScene()
        let mask = try scene.buffer.colorRangeMask(around: FillScene.colorC, fuzziness: 0)
        #expect(mask.width == scene.buffer.width && mask.height == scene.buffer.height)
        for y in 0..<mask.height {
            for x in 0..<mask.width {
                let want: Float = scene.regionC.contains(x: x, y: y) ? 1 : 0
                #expect(try mask.coverage(x: x, y: y) == want, "(\(x), \(y))")
            }
        }
    }

    /// Fuzziness 0.2 around C: C is covered fully, the ring (about 0.18 from
    /// C) fades but is not gone, and every pixel follows the smoothstep of its
    /// own distance, reaching 0 by distance 0.2.
    @Test(.disabled("waits on FT-4"))
    func fallsOffWithDistance() throws {
        let scene = try FillScene()
        let mask = try scene.buffer.colorRangeMask(around: FillScene.colorC, fuzziness: 0.2)
        for p in FillCheck.pixels(scene.regionC) { #expect(try mask.coverage(x: p.x, y: p.y) == 1) }
        let ring = try mask.coverage(x: scene.regionC.x, y: scene.regionC.y - 1)
        #expect(ring > 0 && ring < 0.1, "ring coverage \(ring)")
        for y in 0..<mask.height {
            for x in 0..<mask.width {
                let d = try FillCheck.distance(scene.buffer.pixel(x: x, y: y), FillScene.colorC)
                let got = Double(try mask.coverage(x: x, y: y))
                #expect(abs(got - falloff(d, fuzziness: 0.2)) < 1e-4, "(\(x), \(y)) at distance \(d)")
                if d >= 0.2 { #expect(got == 0) }
            }
        }
        // A row stepping from C to A in tenths: coverage never rises with distance.
        var ramp = try PixelBuffer(width: 11, height: 1)
        for k in 0...10 {
            let f = Float(k) / 10, (a, c) = (FillScene.colorA, FillScene.colorC)
            try ramp.setPixel(x: k, y: 0, RGBA(r: c.r + (a.r - c.r) * f, g: c.g + (a.g - c.g) * f,
                                               b: c.b + (a.b - c.b) * f, a: 1))
        }
        let rampMask = try ramp.colorRangeMask(around: FillScene.colorC, fuzziness: 0.2)
        let values = try (0...10).map { try rampMask.coverage(x: $0, y: 0) }
        #expect(values[0] == 1 && values[10] == 0)
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 >= $1 }, "\(values)")
        #expect(values[2] > 0.5 && values[2] < 1, "\(values)")
    }

    @Test(.disabled("waits on FT-4"))
    func threeByThreeMean() throws {
        let noise = try FillFixtures.noise()
        for (x, y, r) in [(3, 3, 1), (1, 1, 1), (5, 2, 1), (3, 3, 2)] {
            let got = try noise.sampledColor(at: (x: x, y: y), radius: r)
            let want = try FillFixtures.boxMean(noise, x: x, y: y, radius: r)
            for (g, w) in [(got.r, want.r), (got.g, want.g), (got.b, want.b), (got.a, want.a)] {
                #expect(abs(g - w) < 1e-5, "(\(x), \(y)) radius \(r): \(got) vs \(want)")
            }
        }
        #expect(try noise.sampledColor(at: (x: 3, y: 3), radius: 0) == noise.pixel(x: 3, y: 3))
    }

    @Test(.disabled("waits on FT-4"))
    func badArgumentsThrow() throws {
        let noise = try FillFixtures.noise()
        for radius in [3, -1, Int.max] {
            #expect(throws: RasterError.self) { try noise.sampledColor(at: (x: 3, y: 3), radius: radius) }
        }
        for p in [(x: 7, y: 0), (x: 0, y: 7), (x: -1, y: 3)] {
            #expect(throws: RasterError.self) { try noise.sampledColor(at: p, radius: 0) }
        }
        for f: Float in [-0.01, 1.01, .nan] {
            #expect(throws: RasterError.self) { try noise.colorRangeMask(around: FillScene.colorA, fuzziness: f) }
        }
        #expect(throws: RasterError.self) { try noise.colorRangeMask(around: RGBA(r: .nan, g: 0, b: 0, a: 1), fuzziness: 0.2) }
    }

    /// Seeded colours and fuzziness, in and out of range: the mask throws
    /// `RasterError` or has coverage in 0...1, and two runs are `==`.
    @Test(.disabled("waits on FT-4"))
    func fuzzedArgumentsThrowOrStayInRange() throws {
        let noise = try FillFixtures.noise()
        var rng = SplitMix64(seed: 0xF7_04)
        for _ in 0..<100 {
            let color = RGBA(r: .random(in: -0.5...1.5, using: &rng), g: .random(in: 0...1, using: &rng),
                             b: .random(in: 0...1, using: &rng), a: .random(in: 0...1, using: &rng))
            let f = Float.random(in: -0.2...1.2, using: &rng)
            do {
                let mask = try noise.colorRangeMask(around: color, fuzziness: f)
                #expect(mask == (try noise.colorRangeMask(around: color, fuzziness: f)) && (0...49).contains(mask.area))
            } catch is RasterError {
                continue
            }
        }
    }
}
