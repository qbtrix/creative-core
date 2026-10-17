// ParityTests+Display.swift: the display family (MB-3). The sample set, rendered from the original Float32
// sources (so upload loss counts), matches the checked-in display goldens within their tolerance; the sample
// set, a four-tile image and the same image evicted encode within `ParityTolerance.standard` of the CPU run on
// the GPU's Float16 pixels, in sRGB and P3, and every byte per channel round-trips; a non-display space
// throws the CPU backend's exact error, and with a foreign surface both throw `surfaceMismatch` (surface
// first). The golden loop is `expectGoldens` in ParityTests.swift. Device-gated; compiled out on Linux.
#if canImport(Metal)
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CoreColor
import CoreRaster
import CoreRender
import CoreRenderMetal
import Testing

extension ParityTests {
    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func display() {
        do {
            let backend = try MetalBackend.onDefaultDevice()
            #expect(backend.supports.contains(.display))
            try Self.expectGoldens(for: .display, on: backend)
            let cpu = CPUBackend()
            let large = try PixelBuffer.seeded(width: 300, height: 260, seed: 0xD15A)
            var images = try ParityHarness.sampleSet(for: .display).map { ($0.name, $0.source, false) }
            images += [("four-tiles", large, false), ("evicted", large, true)]
            for space in PixelBuffer.displayColorSpaces {
                for (name, image, evict) in images {
                    // The CPU runs on the Float16 pixels the GPU holds: alpha 1e-45 stores as 0 there.
                    let surface = try backend.surface(image)
                    let expected = try cpu.display(cpu.surface(backend.read(surface)), colorSpace: space)
                    if evict { backend.budgetBytes = 0 }
                    let got = try backend.display(surface, colorSpace: space)
                    backend.release(surface)
                    backend.budgetBytes = Int.max
                    let worst = zip(got, expected).map { abs(Int($0) - Int($1)) }.max() ?? 0
                    #expect(got.count == expected.count, "\(name) in \(space.rawValue)")
                    #expect(worst <= Int(ParityTolerance.standard.bytes), "\(name) in \(space.rawValue): worst \(worst)")
                }
                #expect(try Self.roundTrip(on: backend, in: space), "every byte per channel in \(space.rawValue)")
            }
            try Self.expectDisplayErrorsLikeCPU(on: backend)
        } catch {
            Issue.record("display parity threw \(error)")
        }
    }

    /// A non-display space throws the CPU's exact error on the GPU's pixels, and a foreign surface with a bad
    /// space throws `surfaceMismatch` on both, so the surface is checked first; the backend stays healthy.
    private static func expectDisplayErrorsLikeCPU(on metal: MetalBackend) throws {
        let cpu = CPUBackend()
        let surface = try metal.surface(PixelBuffer.seeded(width: 3, height: 2, seed: 0xBAD5))
        defer { metal.release(surface) }
        let reference = try cpu.surface(metal.read(surface))
        for space in ColorSpace.allCases where !PixelBuffer.displayColorSpaces.contains(space) {
            do {
                _ = try cpu.display(reference, colorSpace: space)
                Issue.record("the CPU displays in \(space.rawValue)")
            } catch let expected as RenderError {
                #expect(throws: expected) { try metal.display(surface, colorSpace: space) }
            }
            // Each backend gets the other's handle: a foreign surface.
            #expect(throws: RenderError.surfaceMismatch) { try metal.display(reference, colorSpace: space) }
            #expect(throws: RenderError.surfaceMismatch) { try cpu.display(surface, colorSpace: space) }
        }
        #expect(metal.isHealthy, "a bad space does not fail the backend")
    }

    /// True when rows where one channel runs 0...255 upload and encode back to their bytes (alpha 0: zeros).
    static func roundTrip(on backend: MetalBackend, in space: ColorSpace) throws -> Bool {
        var bytes: [UInt8] = []
        for channel in 0..<4 {
            for v in 0...255 {
                var px: [UInt8] = channel == 3 ? [255, 255, 255, 0] : [0, 0, 0, 255]
                px[channel] = UInt8(v)
                bytes += px
            }
        }
        let surface = try backend.surface(PixelBuffer(rgba8: bytes, width: 256, height: 4, colorSpace: space))
        defer { backend.release(surface) }
        let got = try backend.display(surface, colorSpace: space)
        bytes.replaceSubrange((3 * 256 * 4)..<(3 * 256 * 4 + 4), with: [0, 0, 0, 0])
        return got == bytes
    }
}
#endif
