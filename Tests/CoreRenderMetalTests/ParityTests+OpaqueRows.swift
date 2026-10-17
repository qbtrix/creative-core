// ParityTests+OpaqueRows.swift: MB-6 enables `ParityTests/opaqueRows` (metal-backend) and owns this file.
// The `.composite` "opaque-rows" golden band (cut at opacity 0.8, so no row blits) matches within the golden's
// tolerance. At opacity 1 under `.normal`, a wholly opaque multi-tile source equals the CPU run on the GPU's
// pixels with zero delta, resident and evicted, and its rows are blitted; a row with one 0.999 alpha pixel
// takes the kernel and stays within `.standard`; opacity 0.37 and `.multiply` never blit. Skipped without a
// device; returns early without read-write tier 2.
#if canImport(Metal)
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CoreRaster
import CoreRender
import CoreRenderMetal
import Testing

extension ParityTests {
    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func opaqueRows() {
        do {
            let metal = try MetalBackend.onDefaultDevice()
            guard metal.supports.contains(.composite) else { return }
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("CoreRenderTests/Golden")
            let sample = try #require(try ParityHarness.sampleSet(for: .composite).first(where: { $0.name == "opaque-rows" }))
            let golden = try ParityGolden.band(from: root, op: .composite, sample: sample.name)
            let banded = try ParityHarness.compare(golden: golden, ParityHarness.render(sample, on: metal))
            #expect(banded.passed, "opaque-rows golden: \(banded)")

            let backdrop = try PixelBuffer.seeded(width: 300, height: 270, seed: 0x0B6A)
            var opaque = try PixelBuffer.seeded(width: 260, height: 200, seed: 0x0A1E)
            for y in 0..<200 { for x in 0..<260 { var p = try opaque.pixel(x: x, y: y); p.a = 1; try opaque.setPixel(x: x, y: y, p) } }
            let exact = ParityTolerance(bytes: 0, linear: 0)
            for evict in [false, true] {
                for (x, y) in [(-130, -100), (170, 170), (20, 35)] {
                    let rows = try Self.expectOpaque(opaque, onto: backdrop, x: x, y: y, mode: .normal, opacity: 1,
                                                     tolerance: exact, evict: evict, on: metal)
                    #expect(rows > 0, "opaque rows at (\(x), \(y)) evicted \(evict) are blitted")
                }
            }
            var nearly = try PixelBuffer(width: 40, height: 3, fill: RGBA(r: 0.25, g: 0.5, b: 0.75, a: 1))
            try nearly.setPixel(x: 17, y: 1, RGBA(r: 0.25, g: 0.5, b: 0.75, a: 0.999))
            let kept = try Self.expectOpaque(nearly, onto: backdrop, x: 5, y: 9, mode: .normal, opacity: 1,
                                             tolerance: .standard, evict: false, on: metal)
            #expect(kept == 2, "the row with one 0.999 alpha takes the kernel; the other two blit")
            for (mode, opacity): (BlendMode, Float) in [(.normal, 0.37), (.multiply, 1)] {
                let none = try Self.expectOpaque(opaque, onto: backdrop, x: 20, y: 35, mode: mode, opacity: opacity,
                                                 tolerance: .standard, evict: false, on: metal)
                #expect(none == 0, "\(mode) at opacity \(opacity) never blits")
            }
            #expect(metal.isHealthy)
        } catch {
            Issue.record("opaque-row parity threw \(error)")
        }
    }

    /// Metal equals the CPU on the GPU's pixels within `tolerance`; `evict` sets the budget to 0 first, so the
    /// source and backdrop tiles come from shadows. Returns the rows the fast path blitted for this composite.
    private static func expectOpaque(_ source: PixelBuffer, onto backdrop: PixelBuffer, x: Int, y: Int, mode: BlendMode,
                                     opacity: Float, tolerance: ParityTolerance, evict: Bool, on metal: MetalBackend) throws -> Int {
        let cpu = CPUBackend()
        var target = try metal.surface(backdrop)
        let s = try metal.surface(source)
        defer { metal.release(target); metal.release(s); metal.budgetBytes = Int.max }
        let (heldSource, heldBackdrop) = (try metal.read(s), try metal.read(target))
        var expected = try cpu.surface(heldBackdrop)
        try cpu.composite(try cpu.surface(heldSource), onto: &expected, x: x, y: y, mode: mode, opacity: opacity)
        if evict { metal.budgetBytes = 0 }
        let before = metal.opaqueRowsBlitted
        try metal.composite(s, onto: &target, x: x, y: y, mode: mode, opacity: opacity)
        let blitted = metal.opaqueRowsBlitted - before
        let result = try ParityHarness.compare(try metal.read(target), try cpu.read(expected), tolerance: tolerance)
        #expect(result.passed, "\(mode) at (\(x), \(y)) opacity \(opacity) evicted \(evict): \(result)")
        return blitted
    }
}
#endif
