// ParityTests+Adjust.swift: `ParityTests/adjust` (metal-backend MB-13, MB-14). Exposure at -2, 0 and +2 EV,
// levels with black, white and gamma points and curves through 3 and 5 points, in linear and sRGB encodings,
// and the develop rows (white balance warm, cool and tinted; contrast at -100, 0 and +100; a highlights/shadows
// grid over -100, 0 and +100) match the CPU on the GPU's Float16 pixels within `.standard` on the parity samples
// (alpha 0 and 1e-45 included) and a tiled image, resident or evicted; the source is unchanged; invalid
// parameters throw the CPU backend's error. Skipped without a device; compiled out on Linux.
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

    /// MB-14: contrast at the slider's ends and 0, values outside 0...1 included (the line of slope 1 + amount/200).
    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func adjustContrast() throws {
        try Self.expectAdjustParity([.contrast(-100), .contrast(0), .contrast(35), .contrast(100)], on: MetalBackend.onDefaultDevice())
    }

    /// MB-14: highlights and shadows over the grid of the slider's ends and 0.
    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func adjustHighlightsShadows() throws {
        let grid = [-100, 0, 100].flatMap { h in
            [-100, 0, 100].map { ToneAdjustment.highlightsShadows(highlights: Float(h), shadows: Float($0)) }
        }
        try Self.expectAdjustParity(grid, on: MetalBackend.onDefaultDevice())
    }

    /// `adjustments` on the parity samples, then a tiled image resident and evicted, on a fresh budget.
    private static func expectAdjustParity(_ adjustments: [ToneAdjustment], on metal: MetalBackend) throws {
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
