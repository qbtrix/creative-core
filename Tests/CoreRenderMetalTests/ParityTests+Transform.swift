// ParityTests+Transform.swift: MB-7 enables `ParityTests/transform` (metal-backend) and owns this file.
// Each sample's `.transform` golden band (the user's Float32 source, so upload loss counts) matches within
// the golden's tolerance (`expectGoldens`, ParityTests.swift). Corner and seam crops and the three quarter
// turns are exact copies (zero delta) of the CPU backend run
// on the Float16 pixels the GPU holds, on the sample set and on a multi-tile source, resident or evicted;
// an invalid crop throws the CPU backend's error. Skipped without a device; compiled out on Linux.
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
    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func transform() {
        do {
            let metal = try MetalBackend.onDefaultDevice()
            #expect(metal.supports.contains(.transform))
            try Self.expectGoldens(for: .transform, on: metal)
            for sample in try ParityHarness.sampleSet(for: .transform) {
                try Self.expectTransformsExact(sample.source, on: metal, label: sample.name)
            }
            let tiled = try PixelBuffer.seeded(width: 300, height: 270, seed: 0x7A11)
            try Self.expectTransformsExact(tiled, on: metal, label: "300x270")
            metal.budgetBytes = 0
            try Self.expectTransformsExact(tiled, on: metal, label: "300x270 evicted")
            let (cpu, small) = (CPUBackend(), try PixelBuffer(width: 300, height: 20))
            let (m, c) = (try metal.surface(small), try cpu.surface(small))
            for (x, y, w, h) in [(-1, 0, 2, 2), (299, 0, 2, 2), (0, 19, 2, 2), (0, 0, 0, 2), (Int.min, 0, 1, 1)] {
                do {
                    _ = try cpu.cropped(c, x: x, y: y, width: w, height: h)
                    Issue.record("the CPU accepts \(w)x\(h) at (\(x), \(y))")
                } catch let expected as RenderError {
                    #expect(throws: expected) { try metal.cropped(m, x: x, y: y, width: w, height: h) }
                }
            }
            #expect(metal.isHealthy, "an invalid crop does not fail the backend")
        } catch {
            Issue.record("transform parity threw \(error)")
        }
    }

    /// Corner, seam and whole crops and the three turns of `buffer` equal the CPU's on the GPU's pixels.
    private static func expectTransformsExact(_ buffer: PixelBuffer, on metal: MetalBackend, label: String) throws {
        let cpu = CPUBackend()
        let source = try metal.surface(buffer)
        defer { metal.release(source) }
        let held = try metal.read(source)
        let reference = try cpu.surface(held)
        let (w, h) = (buffer.width, buffer.height)
        let (cw, ch) = (max(1, w * 2 / 3), max(1, h * 2 / 3))
        var crops = [(0, 0, cw, ch), (w - cw, 0, cw, ch), (0, h - ch, cw, ch), (w - cw, h - ch, cw, ch), (0, 0, w, h)]
        if w > 257 && h > 257 { crops.append((250, 250, 8, 8)) }
        var cases = try crops.map { x, y, cw, ch in
            ("crop \(cw)x\(ch) at (\(x), \(y))", try metal.cropped(source, x: x, y: y, width: cw, height: ch),
             try cpu.cropped(reference, x: x, y: y, width: cw, height: ch))
        }
        for turn in [QuarterTurn.degrees90, .degrees180, .degrees270] {
            cases.append(("\(turn)", try metal.rotated(source, turn), try cpu.rotated(reference, turn)))
        }
        for (name, got, want) in cases {
            let (a, b) = (try metal.read(got), try cpu.read(want))
            metal.release(got)
            #expect(a == b, "\(label) \(name): an exact copy")
            let result = try ParityHarness.compare(a, b, tolerance: ParityTolerance(bytes: 0, linear: 0))
            #expect(result.passed, "\(label) \(name): \(result)")
        }
        #expect(try metal.read(source) == held, "\(label): the source is unchanged")
    }
}
#endif
