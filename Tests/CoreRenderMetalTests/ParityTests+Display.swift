// ParityTests+Display.swift: the display family (metal-backend MB-3). The display sample set, a
// seeded 300 x 260 image spanning four tiles and the same image with every tile evicted encode in
// sRGB and Display P3 within `ParityTolerance.standard` bytes of the CPU backend's bytes; every byte
// value per channel uploads and encodes back to itself in both spaces; `.display` is in `supports`.
// Device-gated; compiled out on Linux.
#if canImport(Metal)
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
            let cpu = CPUBackend()
            let large = try PixelBuffer.seeded(width: 300, height: 260, seed: 0xD15A)
            var images = try ParityHarness.sampleSet(for: .display).map { ($0.name, $0.source, false) }
            images += [("four-tiles", large, false), ("evicted", large, true)]
            for space in PixelBuffer.displayColorSpaces {
                for (name, image, evict) in images {
                    let expected = try cpu.display(cpu.surface(image), colorSpace: space)
                    let surface = try backend.surface(image)
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
        } catch {
            Issue.record("display parity threw \(error)")
        }
    }

    /// Rows where one channel runs 0...255 (alpha 255; the alpha row has color 255), decoded, uploaded
    /// and encoded on `backend`: true when every pixel comes back as its bytes (alpha 0 as all zeros).
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
