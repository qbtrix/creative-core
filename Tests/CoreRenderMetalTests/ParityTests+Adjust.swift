// ParityTests+Adjust.swift: MB-13 enables `ParityTests/adjust` (metal-backend). Exposure at -2, 0 and +2 EV,
// levels with black, white and gamma points and curves through 3 and 5 points, in linear and sRGB encodings,
// match the CPU on the GPU's Float16 pixels within `.standard` on the parity samples (alpha 0 and 1e-45
// included) and a tiled image, resident or evicted; the source is unchanged; invalid parameters throw the
// CPU backend's error. The develop sliders wait on MB-14. Skipped without a device; compiled out on Linux.
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
            for sample in try ParityHarness.sampleSet(for: .adjust) {
                try Self.expectAdjustParity(sample.source, on: metal, label: sample.name)
            }
            let tiled = try PixelBuffer.seeded(width: 300, height: 260, seed: 0xAD13)
            try Self.expectAdjustParity(tiled, on: metal, label: "300x260")
            metal.budgetBytes = 0
            try Self.expectAdjustParity(tiled, on: metal, label: "300x260 evicted")
            let (cpu, small) = (CPUBackend(), try PixelBuffer(width: 6, height: 4))
            let (m, c) = (try metal.surface(small), try cpu.surface(small))
            for bad in [ToneAdjustment.exposure(stops: .nan), .levels(inBlack: 0.5, inWhite: 0.5, gamma: 1, outBlack: 0, outWhite: 1),
                        .curves(points: [CurvePoint(x: 0, y: 0)])] {
                do {
                    _ = try cpu.adjusted(c, bad)
                    Issue.record("the CPU accepts \(bad)")
                } catch let expected as RenderError {
                    #expect(throws: expected) { try metal.adjusted(m, bad) }
                }
            }
            for later in [ToneAdjustment.whiteBalance(temperature: 10, tint: 0), .contrast(40),
                          .highlightsShadows(highlights: 10, shadows: 0)] {
                #expect(throws: RenderError.unsupported(.adjust)) { try metal.adjusted(m, later) }
            }
            #expect(metal.isHealthy, "an invalid or later adjustment does not fail the backend")
        } catch {
            Issue.record("adjust parity threw \(error)")
        }
    }

    @Test(.disabled("waits on MB-14")) func adjustWhiteBalance() {}
    @Test(.disabled("waits on MB-14")) func adjustContrast() {}
    @Test(.disabled("waits on MB-14")) func adjustHighlightsShadows() {}

    /// Each MB-13 adjustment of `buffer` equals the CPU's on the GPU's pixels within `.standard`.
    private static func expectAdjustParity(_ buffer: PixelBuffer, on metal: MetalBackend, label: String) throws {
        let cpu = CPUBackend()
        let source = try metal.surface(buffer)
        defer { metal.release(source) }
        let held = try metal.read(source)
        let reference = try cpu.surface(held)
        for adjustment in toneAdjustments {
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
