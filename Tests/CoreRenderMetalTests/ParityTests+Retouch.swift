// ParityTests+Retouch.swift: `ParityTests/retouch` (metal-backend MB-15). Clone through rect, ellipse and polygon
// masks, with offsets inside the image, partly off each edge and wholly off each edge, matches the CPU on the GPU's
// Float16 pixels within `.standard` on the parity samples (alpha 0 and 1e-45 included) and on a multi-tile image
// (300 x 260, wider than one 256 px tile), resident and evicted; the source is unchanged; a mask of another size
// throws the CPU backend's error without failing the backend. Skipped without a device; compiled out on Linux.
#if canImport(Metal)
import CoreRaster
import CoreRender
import CoreRenderMetal
import Testing

extension ParityTests {
    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func retouch() {
        do {
            let metal = try MetalBackend.onDefaultDevice()
            #expect(metal.supports.contains(.retouch))
            for sample in try ParityHarness.sampleSet(for: .retouch) {
                guard case let .cloned(dx, dy, mask) = sample.call else { continue }
                let masks = try [("sample", mask)] + Self.cloneMasks(sample.source.width, sample.source.height)
                try Self.expectCloneParity(sample.source, masks, offsets: [(dx, dy)], on: metal, label: sample.name)
            }
            let tiled = try PixelBuffer.seeded(width: 300, height: 260, seed: 0x5E15)
            let offsets = [(37, -21), (-260, 0), (0, 250), (299, 0), (0, -259), (300, 0), (-300, 0), (0, 260), (0, -260),
                           (Int.max, 0), (0, Int.min)]
            let masks = try Self.cloneMasks(300, 260)
            try Self.expectCloneParity(tiled, masks, offsets: offsets, on: metal, label: "300x260")
            let budget = metal.budgetBytes
            defer { metal.budgetBytes = budget }
            metal.budgetBytes = 0
            try Self.expectCloneParity(tiled, masks, offsets: offsets.prefix(3), on: metal, label: "300x260 evicted")
            let (cpu, small) = (CPUBackend(), try PixelBuffer(width: 6, height: 4))
            let (m, c) = (try metal.surface(small), try cpu.surface(small))
            let wrong = try Mask(width: 5, height: 4, fill: 1)
            do {
                _ = try cpu.cloned(c, offset: (dx: 1, dy: 0), through: wrong)
                Issue.record("the CPU accepts a 5x4 mask on a 6x4 surface")
            } catch let expected as RenderError {
                #expect(throws: expected) { try metal.cloned(m, offset: (dx: 1, dy: 0), through: wrong) }
            }
            #expect(metal.isHealthy && metal.supports.contains(.retouch), "a wrong mask does not fail the backend")
        } catch {
            Issue.record("retouch parity threw \(error)")
        }
    }

    /// A soft-edged rectangle, an ellipse and a concave polygon over a `width` x `height` image.
    private static func cloneMasks(_ width: Int, _ height: Int) throws -> [(String, Mask)] {
        let (w, h) = (Double(width), Double(height))
        let polygon = [Mask.Point(x: 0.1 * w, y: 0.1 * h), Mask.Point(x: 0.9 * w, y: 0.2 * h), Mask.Point(x: 0.5 * w, y: 0.45 * h),
                       Mask.Point(x: 0.85 * w, y: 0.9 * h), Mask.Point(x: 0.15 * w, y: 0.8 * h)]
        return [
            ("rect", try Mask.rectangle(width: width, height: height, x: 0.25 * w + 0.5, y: 0.2 * h + 0.25, w: 0.5 * w, h: 0.5 * h)),
            ("ellipse", try Mask.ellipse(width: width, height: height, centerX: 0.5 * w, centerY: 0.5 * h,
                                         radiusX: 0.4 * w, radiusY: 0.35 * h)),
            ("polygon", try Mask.polygon(width: width, height: height, points: polygon)),
        ]
    }

    /// Each clone of `buffer` by each of `offsets` through each of `masks` equals the CPU's within `.standard`.
    private static func expectCloneParity(_ buffer: PixelBuffer, _ masks: [(String, Mask)], offsets: some Sequence<(Int, Int)>,
                                          on metal: MetalBackend, label: String) throws {
        let cpu = CPUBackend()
        let source = try metal.surface(buffer)
        defer { metal.release(source) }
        let held = try metal.read(source)
        let reference = try cpu.surface(held)
        for (dx, dy) in offsets {
            for (name, mask) in masks {
                let got = try metal.cloned(source, offset: (dx: dx, dy: dy), through: mask)
                defer { metal.release(got) }
                let want = try cpu.read(cpu.cloned(reference, offset: (dx: dx, dy: dy), through: mask))
                let result = try ParityHarness.compare(try metal.read(got), want, tolerance: .standard)
                #expect(result.passed, "\(label) \(name) offset (\(dx), \(dy)): \(result)")
            }
        }
        #expect(try metal.read(source) == held, "\(label): the source is unchanged")
    }
}
#endif
