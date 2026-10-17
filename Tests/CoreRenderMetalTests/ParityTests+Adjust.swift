// ParityTests+Adjust.swift: `ParityTests/adjust` (metal-backend MB-13, MB-14). Exposure at -2, 0 and +2 EV,
// levels with black, white and gamma points and curves through 3 and 5 points, in linear and sRGB encodings,
// and the develop rows (white balance warm, cool and tinted; contrast at -100, 0 and +100; a highlights/shadows
// grid over -100, 0 and +100) match the CPU on the GPU's Float16 pixels within `.standard` on the parity samples
// (alpha 0 and 1e-45 included) and a tiled image, resident or evicted, and within 1e-3 relative (the half's own
// precision) on an image of straight values outside 0...1 at alpha 1 and 0.5, which runs the kernel's octave
// tables and constant luma gain; exposure +8 there reaches the half range's clamp; the source is unchanged;
// invalid parameters throw the CPU backend's error. Skipped without a device; compiled out on Linux.
#if canImport(Metal)
import CoreRaster
import CoreRender
import CoreRenderMetal
import Testing

extension ParityTests {
    /// The MB-13 rows of the proving test.
    static let toneAdjustments: [ToneAdjustment] = [
        .exposure(stops: -2), .exposure(stops: 0), .exposure(stops: 2),
        .levels(inBlack: 0.1, inWhite: 0.9, gamma: 1.6, outBlack: 0.05, outWhite: 0.95),
        .levels(inBlack: 0.05, inWhite: 0.8, gamma: 0.7, outBlack: 0, outWhite: 1, encoding: .sRGB),
        .curves(points: [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.4, y: 0.6), CurvePoint(x: 1, y: 1)]),
        .curves(points: [CurvePoint(x: 0, y: 0.05), CurvePoint(x: 0.25, y: 0.2), CurvePoint(x: 0.5, y: 0.55),
                         CurvePoint(x: 0.75, y: 0.8), CurvePoint(x: 1, y: 0.95)], encoding: .sRGB),
    ]

    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func adjust() {
        do {
            let metal = try MetalBackend.onDefaultDevice()
            try Self.expectAdjustParity(toneAdjustments, on: metal)
            let (cpu, small) = (CPUBackend(), try PixelBuffer(width: 6, height: 4))
            let (m, c) = (try metal.surface(small), try cpu.surface(small))
            for bad in [ToneAdjustment.exposure(stops: .nan), .levels(inBlack: 0.5, inWhite: 0.5, gamma: 1, outBlack: 0, outWhite: 1),
                        .curves(points: [CurvePoint(x: 0, y: 0)]), .whiteBalance(temperature: 101, tint: 0), .contrast(.nan),
                        .highlightsShadows(highlights: 0, shadows: -100.5)] {
                do {
                    _ = try cpu.adjusted(c, bad)
                    Issue.record("the CPU accepts \(bad)")
                } catch let expected as RenderError {
                    #expect(throws: expected) { try metal.adjusted(m, bad) }
                }
            }
            #expect(metal.isHealthy && metal.supports.contains(.adjust), "an invalid adjustment does not fail the backend")
        } catch {
            Issue.record("adjust parity threw \(error)")
        }
    }

    /// MB-14: white balance warm, cool, magenta and green-cool, as the CPU applies its gains.
    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func adjustWhiteBalance() throws {
        try Self.expectAdjustParity([.whiteBalance(temperature: 60, tint: 0), .whiteBalance(temperature: -60, tint: 0),
                                     .whiteBalance(temperature: 0, tint: 45), .whiteBalance(temperature: -100, tint: -100)],
                                    on: MetalBackend.onDefaultDevice())
    }

    /// MB-14: contrast at the slider's ends and 0, values outside 0...1 included (`outOfRange`, the line of
    /// slope 1 + amount/200 from 0 and 1).
    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func adjustContrast() throws {
        try Self.expectAdjustParity([.contrast(-100), .contrast(0), .contrast(35), .contrast(100)], on: MetalBackend.onDefaultDevice())
    }

    /// Exposure far enough that the CPU's values pass the half range: the GPU writes them clamped to it.
    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func adjustExposureReachesTheHalfClamp() throws {
        let metal = try MetalBackend.onDefaultDevice()
        try Self.expectOutOfRangeParity([.exposure(stops: 8), .exposure(stops: -8)], on: metal)
    }

    /// MB-14: highlights and shadows over the grid of the slider's ends and 0.
    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func adjustHighlightsShadows() throws {
        let grid = [-100, 0, 100].flatMap { h in
            [-100, 0, 100].map { ToneAdjustment.highlightsShadows(highlights: Float(h), shadows: Float($0)) }
        }
        try Self.expectAdjustParity(grid, on: MetalBackend.onDefaultDevice())
    }

    /// Straight values outside 0...1 (and -0, 0.25 and 1 for the edges), Float16-exact at alpha 1 and 0.5,
    /// one value per pixel in every channel and a mixed pixel per row, so each side of every kind's map runs.
    static func outOfRange() throws -> PixelBuffer {
        let values: [Float] = [-1000, -300, -16, -3, -1.5, -0.5, -0.0, 0.25, 1, 1.5, 4, 7, 16, 300, 1000]
        var buffer = try PixelBuffer(width: values.count + 1, height: 2)
        for (y, a) in [Float(1), 0.5].enumerated() {
            for (x, v) in values.enumerated() { try buffer.setPixel(x: x, y: y, RGBA(r: v * a, g: v * a, b: v * a, a: a)) }
            try buffer.setPixel(x: values.count, y: y, RGBA(r: 1.5 * a, g: -0.5 * a, b: 7 * a, a: a))
        }
        return buffer
    }

    /// Each of `adjustments` of `outOfRange` equals the CPU's, its values clamped to the finite half range as
    /// the kernel writes them, within 1e-3 of each component's size (at least 1): absolute 1e-3 cannot hold
    /// for half values above 2, whose spacing is 2^-10 of their size.
    private static func expectOutOfRangeParity(_ adjustments: [ToneAdjustment], on metal: MetalBackend) throws {
        let cpu = CPUBackend()
        let source = try metal.surface(outOfRange())
        defer { metal.release(source) }
        let reference = try cpu.surface(metal.read(source))
        for adjustment in adjustments {
            let got = try metal.adjusted(source, adjustment)
            defer { metal.release(got) }
            let (g, w) = (try metal.read(got), try cpu.read(cpu.adjusted(reference, adjustment)))
            for y in 0..<w.height {
                for x in 0..<w.width {
                    let (p, q) = (try g.pixel(x: x, y: y), try w.pixel(x: x, y: y))
                    for (a, b) in [(p.r, q.r), (p.g, q.g), (p.b, q.b), (p.a, q.a)] {
                        let want = min(max(b, -65504), 65504)
                        #expect(abs(a - want) <= 1e-3 * max(1, abs(want)), "outOfRange \(adjustment) at (\(x), \(y)): \(p) vs \(q)")
                    }
                }
            }
        }
    }

    /// `adjustments` on the parity samples, on `outOfRange`, then a tiled image resident and evicted, on a
    /// fresh budget.
    private static func expectAdjustParity(_ adjustments: [ToneAdjustment], on metal: MetalBackend) throws {
        try expectOutOfRangeParity(adjustments, on: metal)
        for sample in try ParityHarness.sampleSet(for: .adjust) {
            try expectAdjustParity(sample.source, adjustments, on: metal, label: sample.name)
        }
        let tiled = try PixelBuffer.seeded(width: 300, height: 260, seed: 0xAD13)
        try expectAdjustParity(tiled, adjustments, on: metal, label: "300x260")
        let budget = metal.budgetBytes
        defer { metal.budgetBytes = budget }
        metal.budgetBytes = 0
        try expectAdjustParity(tiled, adjustments, on: metal, label: "300x260 evicted")
    }

    /// Each of `adjustments` of `buffer` equals the CPU's on the GPU's pixels within `.standard`.
    private static func expectAdjustParity(_ buffer: PixelBuffer, _ adjustments: [ToneAdjustment], on metal: MetalBackend,
                                           label: String) throws {
        let cpu = CPUBackend()
        let source = try metal.surface(buffer)
        defer { metal.release(source) }
        let held = try metal.read(source)
        let reference = try cpu.surface(held)
        for adjustment in adjustments {
            let got = try metal.adjusted(source, adjustment)
            defer { metal.release(got) }
            let want = try cpu.read(cpu.adjusted(reference, adjustment))
            let result = try ParityHarness.compare(try metal.read(got), want, tolerance: .standard)
            #expect(result.passed, "\(label) \(adjustment): \(result)")
        }
        #expect(try metal.read(source) == held, "\(label): the source is unchanged")
    }
}
#endif
