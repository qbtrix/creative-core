// ColorRangeTests.swift: fill-tools FT-4's acceptance for `sampledColor` and
// `colorRangeMask`. Distances come from `FillCheck` (FloodFillTests).
import CoreRaster
import Testing

@Suite struct ColorRangeTests {
    /// The packet's falloff: `1 - smoothstep(0, f, d)`.
    private func falloff(_ d: Double, fuzziness f: Double) -> Double {
        let x = min(max(d / f, 0), 1)
        return 1 - x * x * (3 - 2 * x)
    }

    @Test
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

    /// Fuzziness 0.2 around C: C is covered fully, the ring (about 0.137 from
    /// C) fades but is not gone, and every pixel follows the smoothstep of its
    /// own distance, reaching 0 by distance 0.2.
    @Test
    func fallsOffWithDistance() throws {
        let scene = try FillScene()
        let mask = try scene.buffer.colorRangeMask(around: FillScene.colorC, fuzziness: 0.2)
        for p in FillCheck.pixels(scene.regionC) { #expect(try mask.coverage(x: p.x, y: p.y) == 1) }
        let ring = try mask.coverage(x: scene.regionC.x, y: scene.regionC.y - 1)
        #expect(abs(Double(ring) - falloff(0.137, fuzziness: 0.2)) < 0.01, "ring coverage \(ring)")
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

    /// Alpha is a fourth axis of the straight colours: B at alpha 0.8 is 0.2
    /// from B, so fuzziness 0 skips it and fuzziness 0.4 gives falloff(0.2, 0.4).
    @Test
    func alphaIsFourthAxis() throws {
        let image = try FillFixtures.alphaPair()
        let hard = try image.colorRangeMask(around: FillScene.colorB, fuzziness: 0)
        #expect(hard.area == 2)
        #expect(try hard.coverage(x: 2, y: 0) == 0)
        let soft = try image.colorRangeMask(around: FillScene.colorB, fuzziness: 0.4)
        #expect(abs(Double(try soft.coverage(x: 2, y: 0)) - falloff(0.2, fuzziness: 0.4)) < 1e-4)
    }

    /// The bucket and colour range measure one distance: for seeded pairs,
    /// some partly transparent, a fill at `.within(t)` takes the second pixel
    /// exactly when d <= t, and colour range covers it exactly when d < t,
    /// with d the packet's distance (`FillCheck.distance`).
    @Test
    func floodAndRangeShareDistance() throws {
        var rng = SplitMix64(seed: 0xF7_05)
        for _ in 0..<200 {
            func color() -> RGBA {
                RGBA(r: .random(in: 0...1, using: &rng), g: .random(in: 0...1, using: &rng),
                     b: .random(in: 0...1, using: &rng), a: Bool.random(using: &rng) ? 1 : .random(in: 0.05...1, using: &rng))
                    .premultiplied()
            }
            let (p, q) = (color(), color())
            let t = Float.random(in: 0.01...1, using: &rng)
            let d = try FillCheck.distance(p, q)
            guard abs(d - Double(t)) > 1e-5 else { continue }
            var pair = try PixelBuffer(width: 2, height: 1)
            try pair.setPixel(x: 0, y: 0, p)
            try pair.setPixel(x: 1, y: 0, q)
            let flood = try pair.floodMask(from: (x: 0, y: 0), tolerance: .within(t), antiAlias: false)
            let range = try pair.colorRangeMask(around: p, fuzziness: t)
            #expect((try flood.coverage(x: 1, y: 0) == 1) == (d <= Double(t)), "d \(d), t \(t)")
            #expect((try range.coverage(x: 1, y: 0) > 0) == (d < Double(t)), "d \(d), t \(t)")
        }
    }

    @Test
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

    /// The box clips at the buffer's edge: the mean is over its in-bounds pixels.
    @Test
    func boxClipsAtEdge() throws {
        let noise = try FillFixtures.noise()
        let corner = try noise.sampledColor(at: (x: 0, y: 0), radius: 1)
        let quad = try [(0, 0), (1, 0), (0, 1), (1, 1)].map { try noise.pixel(x: $0.0, y: $0.1) }
        let want = quad.reduce(RGBA.clear) { RGBA(r: $0.r + $1.r / 4, g: $0.g + $1.g / 4, b: $0.b + $1.b / 4, a: $0.a + $1.a / 4) }
        for (g, w) in [(corner.r, want.r), (corner.g, want.g), (corner.b, want.b), (corner.a, want.a)] {
            #expect(abs(g - w) < 1e-5, "\(corner) vs \(want)")
        }
        let edge = try noise.sampledColor(at: (x: 6, y: 3), radius: 2)
        let box = try (1...5).flatMap { y in try (4...6).map { try noise.pixel(x: $0, y: y) } }
        let meanR = box.reduce(Float(0)) { $0 + $1.r } / Float(box.count)
        #expect(abs(edge.r - meanR) < 1e-5 && abs(edge.a - 1) < 1e-6)
    }

    @Test
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

    /// A finite colour that overflows Float on unpremultiplying (a component
    /// far above a tiny alpha) is named as that, never as "not finite", as
    /// the colour and as a buffer pixel; seeded tiny alphas throw or pass.
    @Test
    func overflowingColourSaysUnpremultiplied() throws {
        let noise = try FillFixtures.noise()
        func message(_ body: () throws -> Mask) -> String? {
            do { _ = try body(); return nil } catch RasterError.invalid(let m) { return m } catch { return "other: \(error)" }
        }
        let tiny = RGBA(r: 1, g: 0, b: 0, a: 1e-40)
        var image = noise
        try image.setPixel(x: 2, y: 1, tiny)
        for got in [message { try noise.colorRangeMask(around: tiny, fuzziness: 0.1) },
                    message { try image.colorRangeMask(around: FillScene.colorA, fuzziness: 0.1) }] {
            let m = try #require(got)
            #expect(m.contains("unpremultiplied") && !m.contains("is not finite"), "\(m)")
        }
        #expect(message { try image.colorRangeMask(around: FillScene.colorA, fuzziness: 0.1) }?.contains("pixel (2, 1)") == true)
        var rng = SplitMix64(seed: 0xF7_0F)
        for _ in 0..<200 {
            let a = Float(bitPattern: UInt32.random(in: 1...0x0100_0000, using: &rng))  // subnormal to ~1e-38
            let c = RGBA(r: .random(in: 0...1e3, using: &rng), g: .random(in: 0...1, using: &rng), b: 0, a: a)
            if let m = message({ try noise.colorRangeMask(around: c, fuzziness: 0.2) }) {
                #expect(!m.hasPrefix("other: ") && !m.contains("is not finite"), "\(m)")
            }
        }
    }

    /// Seeded colours and fuzziness, in and out of range: the mask throws
    /// `RasterError` or has coverage in 0...1, and two runs are `==`.
    @Test
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
