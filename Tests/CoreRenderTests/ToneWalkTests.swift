// ToneWalkTests.swift: tone-pack TP-9, journey KJ-TP of
// docs/blueprints/core/features/tone-pack.md. One seeded 1024 x 683 "photo"
// under a warm cast goes through every colour op the journey names, each
// step through a RenderDispatcher whose preferred FakeBackend supports
// `.adjust` only: auto tone's suggestion neutralises the grey patch within
// 2/255, then vibrance 30, HSL blues -20 saturation, black and white
// default, invert twice (`==` identity), a 17³ `.cube` identity LUT (within
// 1e-5) and posterize 4 (four levels per channel). The colour cases land on
// the CPU and give their CoreRaster call's pixels with `==`; `contrast`
// lands on the fake. The fake is not a pixel reference (its `.adjust`
// leaves pixels as they are), so auto tone's two `.adjust` cases go through
// a second dispatcher over an unhealthy copy of the same fake and the same
// CPU backend: each falls back to the CPU and gives its CoreRaster call's
// pixels with `==`.
import CoreColor
import CoreRaster
import CoreRender
import Testing

@Suite struct ToneWalkTests {
    static let width = 1024, height = 683
    /// The neutral grey patch: a quarter of each side at the centre.
    static let patch = (x: width * 3 / 8, y: height * 3 / 8, width: width / 4, height: height / 4)

    /// The cast photo, the recipe of CoreRasterTests' `ToneFixtures.castPhoto`
    /// (a test target this one cannot import): a left-to-right grey ramp from
    /// 0.05 to 0.9 with ±0.03 seeded noise and ±0.02 seeded chroma, the patch
    /// a flat 0.5, then every pixel times the warm cast (1.08, 1, 0.85).
    static func castPhoto(seed: UInt64 = 0x70E) throws -> PixelBuffer {
        let cast: SIMD3<Float> = [1.08, 1.0, 0.85]
        var rng = SplitMix64(seed: seed)
        var buffer = try PixelBuffer(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let inPatch = (patch.x..<patch.x + patch.width).contains(x)
                    && (patch.y..<patch.y + patch.height).contains(y)
                let level = 0.05 + 0.85 * Float(x) / Float(width - 1) + Float.random(in: -0.03...0.03, using: &rng)
                let chroma = SIMD3<Float>(.random(in: -0.02...0.02, using: &rng), 0, .random(in: -0.02...0.02, using: &rng))
                let base = inPatch ? SIMD3<Float>(repeating: 0.5) : SIMD3(repeating: level) + chroma
                let c = (base * cast).clamped(lowerBound: .zero, upperBound: .one)
                try buffer.setPixel(x: x, y: y, RGBA(r: c.x, g: c.y, b: c.z, a: 1))
            }
        }
        return buffer
    }

    /// Straight sRGB-encoded rgb of a premultiplied linear pixel.
    static func encoded(_ p: RGBA) -> SIMD3<Double> {
        let s = p.unpremultiplied()
        return SIMD3(TransferCurve.encode(Double(s.r)), TransferCurve.encode(Double(s.g)), TransferCurve.encode(Double(s.b)))
    }

    /// The largest minus the smallest channel of the patch's mean encoded rgb.
    static func patchSpread(_ b: PixelBuffer) throws -> Double {
        var sum = SIMD3<Double>.zero
        for y in patch.y..<patch.y + patch.height {
            for x in patch.x..<patch.x + patch.width { sum += encoded(try b.pixel(x: x, y: y)) }
        }
        let mean = sum / Double(patch.width * patch.height)
        return mean.max() - mean.min()
    }

    static func pixels(_ b: PixelBuffer) throws -> [RGBA] {
        var out: [RGBA] = []
        out.reserveCapacity(b.width * b.height)
        for y in 0..<b.height {
            for x in 0..<b.width { out.append(try b.pixel(x: x, y: y)) }
        }
        return out
    }

    /// The identity 17³ as `.cube` text, red index fastest.
    static func identityCube(size: Int = 17) -> String {
        var lines = ["# tone walk", "TITLE \"identity \(size)\"", "LUT_3D_SIZE \(size)"]
        func c(_ i: Int) -> Float { Float(i) / Float(size - 1) }
        for i in 0..<size * size * size {
            lines.append("\(c(i % size)) \(c(i / size % size)) \(c(i / (size * size)))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// One step: `adjustment` through the dispatcher on `s`, which holds
    /// `input`. It must fall back to the CPU for its family and equal
    /// `direct(input)`.
    static func colorStep(_ d: RenderDispatcher, _ s: RenderSurface, _ input: PixelBuffer,
                          _ adjustment: ToneAdjustment,
                          _ direct: (PixelBuffer) throws -> PixelBuffer) throws -> (RenderSurface, PixelBuffer) {
        let out = try d.adjusted(s, adjustment)
        #expect(out.backend == d.fallback.name, "\(adjustment)")
        #expect(d.lastFallback?.op == adjustment.family, "\(adjustment)")
        let pixels = try d.read(out)
        let same = pixels == (try direct(input))  // a Bool, so a miss does not print both buffers
        #expect(same, "\(adjustment)")
        return (out, pixels)
    }

    @Test func walk() throws {
        let fake = FakeBackend(supports: [.adjust])
        let d = RenderDispatcher(preferred: fake, fallback: CPUBackend())
        let photo = try Self.castPhoto()
        #expect(try Self.patchSpread(photo) > 2.0 / 255)

        // Auto tone: the suggestion's two `.adjust` cases, white balance then
        // levels, through a dispatcher whose copy of the fake is unhealthy, so
        // both fall back to the shared CPU backend and match CoreRaster.
        let t = try AutoTone.suggest(for: photo)
        var unhealthy = fake
        unhealthy.healthy = false
        let auto = RenderDispatcher(preferred: unhealthy, fallback: d.fallback)
        var s = try auto.surface(photo), b = photo
        (s, b) = try Self.colorStep(auto, s, b, .whiteBalance(temperature: t.temperature, tint: t.tint)) {
            try $0.whiteBalance(temperature: t.temperature, tint: t.tint)
        }
        (s, b) = try Self.colorStep(auto, s, b, .levels(inBlack: t.inBlack, inWhite: t.inWhite, gamma: t.gamma,
                                                        outBlack: 0, outWhite: 1)) {
            try $0.levels(inBlack: t.inBlack, inWhite: t.inWhite, gamma: t.gamma, outBlack: 0, outWhite: 1)
        }
        #expect(auto.lastFallback?.reason == RenderDispatcher.reasonUnhealthy)
        #expect(try Self.patchSpread(b) <= 2.0 / 255, "\(t)")

        // Contrast is `.adjust`: the fake has it, so the dispatcher sends it there.
        s = try d.adjusted(s, .contrast(10))
        #expect(s.backend == "fake")
        let unchanged = try d.read(s) == b
        #expect(unchanged)

        (s, b) = try Self.colorStep(d, s, b, .vibrance(30)) { try $0.vibrance(30) }
        let blues = HSLAdjustment(blues: HSLShift(saturation: -20))
        (s, b) = try Self.colorStep(d, s, b, .hsl(blues)) { try $0.hsl(blues) }
        (s, b) = try Self.colorStep(d, s, b, .blackAndWhite(GrayMix())) { try $0.blackAndWhite(GrayMix()) }
        #expect(try Self.pixels(b).allSatisfy { $0.r == $0.g && $0.g == $0.b })

        // Invert twice is the identity: `==` on every component of 0.5 or
        // more, where 1 − c is exact in Float, and within one ulp of 1 below
        // that, where 1 − c rounds.
        let grey = b
        (s, b) = try Self.colorStep(d, s, b, .invert) { $0.inverted() }
        let changed = b != grey
        #expect(changed)
        (s, b) = try Self.colorStep(d, s, b, .invert) { $0.inverted() }
        var exact = 0, notExact = 0, worst: Float = 0
        for (p, q) in zip(try Self.pixels(b), try Self.pixels(grey)) {
            for (got, want) in [(p.r, q.r), (p.g, q.g), (p.b, q.b), (p.a, q.a)] {
                if want >= 0.5 {
                    exact += 1
                    if got != want { notExact += 1 }
                } else {
                    worst = max(worst, abs(got - want))
                }
            }
        }
        #expect(notExact == 0)
        #expect(worst <= .ulpOfOne)
        #expect(exact > Self.width * Self.height)

        // The 17³ identity LUT, read from its `.cube` text, within 1e-5.
        let lut = try CubeLUT.parse(Self.identityCube())
        #expect(lut.size == 17)
        (s, b) = try Self.colorStep(d, s, b, .lut(lut)) { try $0.applying(lut) }
        let gap = zip(try Self.pixels(b), try Self.pixels(grey)).map { p, q in
            max(abs(p.r - q.r), abs(p.g - q.g), abs(p.b - q.b), abs(p.a - q.a))
        }.max() ?? .infinity
        #expect(gap <= 1e-5)

        // Posterize 4: every channel on one of four levels (encoded 0, 1/3,
        // 2/3, 1, compared in linear), all four used.
        (s, b) = try Self.colorStep(d, s, b, .posterize(levels: 4)) { try $0.posterized(levels: 4) }
        let levels = (0...3).map { Float(TransferCurve.decode(Double($0) / 3)) }
        var used = Set<Int>(), off = 0
        for p in try Self.pixels(b) {
            for v in [p.r, p.g, p.b] {
                if let level = levels.indices.first(where: { abs(levels[$0] - v) <= 1e-5 }) {
                    used.insert(level)
                } else {
                    off += 1
                }
            }
        }
        #expect(off == 0)
        #expect(used == [0, 1, 2, 3])
        #expect(b.width == Self.width && b.height == Self.height)

        // The fake was asked for `contrast` once and never for a colour case.
        #expect(fake.calls.filter { $0 == .op(.adjust) }.count == 1)
        #expect(!fake.calls.contains(.op(.color)))
    }
}
