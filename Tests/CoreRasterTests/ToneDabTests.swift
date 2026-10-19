// ToneDabTests.swift: retouch-heal RH-5's acceptance, written first by RH-1
// (docs/blueprints/core/features/retouch-heal.md), turned on by RH-5.
import CoreRaster
import Testing

/// A dab op under test (dodge, burn or sponge) applied at (x, y).
fileprivate typealias DabOp = (inout PixelBuffer, Mask, Int, Int) throws -> Void

/// Max minus min of a pixel's colour channels.
private func chroma(_ p: RGBA) -> Float { max(p.r, p.g, p.b) - min(p.r, p.g, p.b) }

@Suite fileprivate struct ToneDabTests {
    static let side = 8, tolerance: Float = 1 / 255

    /// The tone patches after `op` dabs each one with a full square dab.
    static func patchesAfter(_ op: DabOp) throws -> PixelBuffer {
        var buffer = try RetouchFixtures.tonePatches(side: side)
        let dab = try Mask(width: side, height: side, fill: 1)
        for i in 0..<4 { try op(&buffer, dab, i * side, 0) }
        return buffer
    }

    /// The pixel at the centre of patch `index`.
    static func centre(_ buffer: PixelBuffer, patch index: Int) throws -> RGBA {
        try buffer.pixel(x: index * side + side / 2, y: side / 2)
    }

    /// Patch 1 (luma 0.5) moved past the tolerance in `direction`; patches 0 and 2 (0.1, 0.95) stayed.
    static func expectMidtonesOnly(_ out: PixelBuffer, direction: Float) throws {
        #expect(try (centre(out, patch: 1).r - 0.5) * direction > tolerance)
        #expect(try abs(centre(out, patch: 0).r - 0.1) <= tolerance)
        #expect(try abs(centre(out, patch: 2).r - 0.95) <= tolerance)
    }

    @Test func midtonesOnly() throws {
        try Self.expectMidtonesOnly(try Self.patchesAfter { try $0.dodge($1, x: $2, y: $3, range: .midtones, exposure: 1) },
                                    direction: 1)
    }

    @Test func burnMirrors() throws {
        try Self.expectMidtonesOnly(try Self.patchesAfter { try $0.burn($1, x: $2, y: $3, range: .midtones, exposure: 1) },
                                    direction: -1)
    }

    /// Shadows and highlights mirror the midtone window: each moves only its own patch.
    @Test func shadowsAndHighlightsOnly() throws {
        let lit = try Self.patchesAfter { try $0.dodge($1, x: $2, y: $3, range: .highlights, exposure: 1) }
        #expect(try Self.centre(lit, patch: 2).r - 0.95 > Self.tolerance)
        #expect(try abs(Self.centre(lit, patch: 0).r - 0.1) <= Self.tolerance)
        #expect(try abs(Self.centre(lit, patch: 1).r - 0.5) <= Self.tolerance)
        let dark = try Self.patchesAfter { try $0.burn($1, x: $2, y: $3, range: .shadows, exposure: 1) }
        #expect(try 0.1 - Self.centre(dark, patch: 0).r > Self.tolerance)
        #expect(try abs(Self.centre(dark, patch: 1).r - 0.5) <= Self.tolerance)
        #expect(try abs(Self.centre(dark, patch: 2).r - 0.95) <= Self.tolerance)
    }

    /// Dodge multiplies linear colour by 1 + exposure × weight, burn by
    /// 1 − exposure × weight × 0.5, a linear gain and not stops: at full
    /// weight on patch 1 (luma 0.5, midtone weight 1), exposure 1 doubles
    /// (dodge) or halves (burn), but exposure 0.5 gives ×1.5 and ×0.75.
    @Test func dodgeBurnMagnitude() throws {
        let cases: [(DabOp, Float)] = [
            ({ try $0.dodge($1, x: $2, y: $3, range: .midtones, exposure: 0.5) }, 0.75),
            ({ try $0.dodge($1, x: $2, y: $3, range: .midtones, exposure: 1) }, 1),
            ({ try $0.burn($1, x: $2, y: $3, range: .midtones, exposure: 1) }, 0.25),
            ({ try $0.burn($1, x: $2, y: $3, range: .midtones, exposure: 0.5) }, 0.375),
        ]
        for (op, expected) in cases {
            let p = try Self.centre(Self.patchesAfter(op), patch: 1)
            #expect(abs(p.r - expected) <= Self.tolerance, "got \(p.r), expected \(expected)")
            #expect(p.r == p.g && p.g == p.b)
        }
    }

    /// The range weight reads straight luma, not premultiplied, and colour
    /// clamps to alpha: straight grey 0.5 at alpha 0.5 is a full midtone, so
    /// exposure 1 doubles it to alpha; a translucent highlight never passes alpha.
    @Test func translucentUsesStraightLuma() throws {
        let dab = try Mask(width: 4, height: 4, fill: 1)
        var mid = try PixelBuffer(width: 4, height: 4, fill: RGBA(r: 0.25, g: 0.25, b: 0.25, a: 0.5))
        try mid.dodge(dab, x: 0, y: 0, range: .midtones, exposure: 1)
        let m = try mid.pixel(x: 1, y: 1)
        #expect(abs(m.r - 0.5) <= Self.tolerance, "midtone r \(m.r)")
        #expect(m.a == 0.5)
        var high = try PixelBuffer(width: 4, height: 4, fill: RGBA(r: 0.45, g: 0.45, b: 0.45, a: 0.5))
        try high.dodge(dab, x: 0, y: 0, range: .highlights, exposure: 1)
        let h = try high.pixel(x: 1, y: 1)
        #expect(h.r <= h.a && h.g <= h.a && h.b <= h.a, "highlight \(h)")
        #expect(abs(h.r - 0.5) <= Self.tolerance)
    }

    @Test func spongeRaisesAndGreys() throws {
        let richer = try Self.patchesAfter { try $0.sponge($1, x: $2, y: $3, amount: 1) }
        #expect(try chroma(Self.centre(richer, patch: 3)) > chroma(RetouchFixtures.tint) + Self.tolerance)
        let grey = try Self.patchesAfter { try $0.sponge($1, x: $2, y: $3, amount: -1) }
        #expect(try chroma(Self.centre(grey, patch: 3)) <= Self.tolerance)
    }

    @Test func dabCoverageWeights() throws {
        let grey = RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1)
        var buffer = try PixelBuffer(width: 20, height: 20, fill: grey)
        try buffer.dodge(try RetouchFixtures.roundDab(radius: 10, hardness: 0.5), x: 0, y: 0, range: .midtones, exposure: 1)
        let centre = try buffer.pixel(x: 10, y: 10).r - 0.5, feather = try buffer.pixel(x: 17, y: 10).r - 0.5
        #expect(feather > 0 && feather < centre, "centre lift \(centre), feather lift \(feather)")
        #expect(try buffer.pixel(x: 0, y: 0) == grey)
    }

    /// Sponge weights by coverage: at amount -1 the hard centre of a
    /// feathered dab goes grey while a feathered pixel keeps some chroma.
    @Test func spongeCoverageWeights() throws {
        var buffer = try PixelBuffer(width: 20, height: 20, fill: RetouchFixtures.tint)
        try buffer.sponge(try RetouchFixtures.roundDab(radius: 10, hardness: 0.5), x: 0, y: 0, amount: -1)
        let input = chroma(RetouchFixtures.tint)
        let centre = try chroma(buffer.pixel(x: 10, y: 10)), feather = try chroma(buffer.pixel(x: 17, y: 10))
        #expect(centre <= Self.tolerance, "centre chroma \(centre)")
        #expect(feather > Self.tolerance && feather < input - Self.tolerance, "feather chroma \(feather) of \(input)")
    }

    /// A fully transparent pixel has no straight luma; every op leaves it clear.
    @Test func transparentPixelsUntouched() throws {
        let input = try PixelBuffer(width: 8, height: 8, fill: .clear)
        let dab = try Mask(width: 8, height: 8, fill: 1)
        for op: DabOp in [{ try $0.dodge($1, x: $2, y: $3, range: .midtones, exposure: 1) },
                          { try $0.burn($1, x: $2, y: $3, range: .shadows, exposure: 1) },
                          { try $0.sponge($1, x: $2, y: $3, amount: 1) }] {
            var out = input
            try op(&out, dab, 0, 0)
            #expect(out == input)
        }
    }

    @Test func alphaNeverChanges() throws {
        let input = try PixelBuffer(width: 16, height: 16, fill: RGBA(r: 0.3, g: 0.2, b: 0.05, a: 0.4))
        let dab = try RetouchFixtures.roundDab(radius: 8, hardness: 0.6)
        for op: DabOp in [{ try $0.dodge($1, x: $2, y: $3, range: .shadows, exposure: 0.8) },
                          { try $0.burn($1, x: $2, y: $3, range: .highlights, exposure: 0.8) },
                          { try $0.sponge($1, x: $2, y: $3, amount: 0.7) }] {
            var out = input
            try op(&out, dab, 0, 0)
            for y in 0..<16 {
                for x in 0..<16 { #expect(try out.pixel(x: x, y: y).a == 0.4) }
            }
        }
    }

    @Test func zeroStrengthIsIdentity() throws {
        let input = try RetouchFixtures.tonePatches(side: Self.side)
        for range in [TonalRange.shadows, .midtones, .highlights] {
            #expect(try Self.patchesAfter { try $0.dodge($1, x: $2, y: $3, range: range, exposure: 0) } == input)
            #expect(try Self.patchesAfter { try $0.burn($1, x: $2, y: $3, range: range, exposure: 0) } == input)
        }
        #expect(try Self.patchesAfter { try $0.sponge($1, x: $2, y: $3, amount: 0) } == input)
    }

    @Test func outsideBoundsUntouched() throws {
        let photo = try RetouchFixtures.spottedPhoto(width: 40, height: 30, seed: 11)
        var out = photo.clean
        let dab = try RetouchFixtures.roundDab(radius: 6)
        try out.dodge(dab, x: 9, y: 7, range: .highlights, exposure: 1)
        try out.burn(dab, x: 9, y: 7, range: .shadows, exposure: 1)
        try out.sponge(dab, x: 9, y: 7, amount: -0.5)
        try expectSameOutside(out, photo.clean, cx: 15, cy: 13, r: 6)
        #expect(out != photo.clean)
    }

    @Test func fuzzedStrengthsThrowOrDab() throws {
        var rng = SplitMix64(seed: 0xD0D6)
        let strengths: [Float] = [.nan, .infinity, -.infinity, -1.5, -1, -0.1, 0, 0.5, 1, 1.1]
        let positions = [Int.min, -20, -3, 0, 5, 30, Int.max]
        let dab = try RetouchFixtures.roundDab(radius: 4)
        for _ in 0..<300 {
            var buffer = try RetouchFixtures.tonePatches(side: 8)
            let s = strengths.randomElement(using: &rng) ?? 0, op = Int.random(in: 0..<3, using: &rng)
            let x = positions.randomElement(using: &rng) ?? 0, y = positions.randomElement(using: &rng) ?? 0
            do {
                switch op {
                case 0: try buffer.dodge(dab, x: x, y: y, range: .midtones, exposure: s)
                case 1: try buffer.burn(dab, x: x, y: y, range: .shadows, exposure: s)
                default: try buffer.sponge(dab, x: x, y: y, amount: s)
                }
                #expect((op == 2 ? -1...1 : 0...1).contains(s), "op \(op) took strength \(s)")
            } catch is RasterError {
            } catch {
                Issue.record("unexpected error \(error)")
            }
        }
    }
}
