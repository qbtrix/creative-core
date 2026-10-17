// ParityTests+Resample.swift: MB-8 enables `ParityTests/resample`. Each sample's `.resample` golden band matches
// within the golden's tolerance. Both filters, up and down, with either axis or both kept at their length (the
// skipped pass, in both pass orders), match the CPU on the GPU's Float16 pixels within `.standard`, resident or
// evicted; a 16xN to Nx16 resize whose max(w) x max(h) is over `maxBufferLength` still runs; a constant stays
// exactly constant; an invalid size throws the CPU backend's error. Skipped without a device; compiled out on Linux.
#if canImport(Metal)
import CoreRaster
import CoreRender
import CoreRenderMetal
import Testing

extension ParityTests {
    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func resample() {
        do {
            let metal = try MetalBackend.onDefaultDevice()
            try Self.expectGoldens(for: .resample, on: metal)
            for sample in try ParityHarness.sampleSet(for: .resample) {
                try Self.expectResampleParity(sample.source, sizes: [(13, 5), (4, 3), (9, 3), (13, 7)], on: metal, label: sample.name)
            }
            let tiled = try PixelBuffer.seeded(width: 300, height: 270, seed: 0x5A3E)
            let sizes = [(1, 1), (37, 23), (150, 300), (301, 269), (520, 290), (300, 150), (300, 400), (150, 270),
                         (520, 270), (300, 270)]
            try Self.expectResampleParity(tiled, sizes: sizes, on: metal, label: "300x270")
            let constant = try PixelBuffer(width: 300, height: 270, fill: RGBA(r: 0.25, g: 0.5, b: 0.125, a: 0.75))
            try Self.expectConstant(constant, sizes: sizes, on: metal)
            metal.budgetBytes = 0
            try Self.expectResampleParity(tiled, sizes: [(37, 23), (520, 290), (300, 150), (150, 270)], on: metal,
                                          label: "300x270 evicted")
            try Self.expectConstant(constant, sizes: [(150, 300)], on: metal)
            let n = 400_000 // max(w) x max(h) x 16 bytes is over any GPU's limit; every real buffer is 16n pixels.
            #expect(n * n * 16 > metal.device.maxBufferLength)
            try Self.expectResampleParity(PixelBuffer.seeded(width: 16, height: n, seed: 0x1A7E), sizes: [(n, 16)], on: metal,
                                          label: "16x\(n)")
            let (cpu, small) = (CPUBackend(), try PixelBuffer(width: 6, height: 4))
            let (m, c) = (try metal.surface(small), try cpu.surface(small))
            for (w, h) in [(0, 4), (4, 0), (-3, 2), (Int.max, 2), (PixelBuffer.maxPixels, 2)] {
                do {
                    _ = try cpu.resampled(c, width: w, height: h, filter: .bilinear)
                    Issue.record("the CPU accepts \(w)x\(h)")
                } catch let expected as RenderError {
                    #expect(throws: expected) { try metal.resampled(m, width: w, height: h, filter: .bilinear) }
                }
            }
            #expect(metal.isHealthy, "an invalid size does not fail the backend")
        } catch {
            Issue.record("resample parity threw \(error)")
        }
    }

    /// Both filters of `buffer` at each size equal the CPU's on the GPU's pixels within `.standard`.
    private static func expectResampleParity(_ buffer: PixelBuffer, sizes: [(Int, Int)], on metal: MetalBackend,
                                             label: String) throws {
        let cpu = CPUBackend()
        let source = try metal.surface(buffer)
        defer { metal.release(source) }
        let held = try metal.read(source)
        let reference = try cpu.surface(held)
        for filter in [ResampleFilter.bilinear, .lanczos3] {
            for (w, h) in sizes {
                let got = try metal.resampled(source, width: w, height: h, filter: filter)
                defer { metal.release(got) }
                let result = try ParityHarness.compare(try metal.read(got), try cpu.read(cpu.resampled(reference, width: w, height: h, filter: filter)), tolerance: .standard)
                #expect(result.passed, "\(label) \(filter) to \(w)x\(h): \(result)")
            }
        }
        #expect(try metal.read(source) == held, "\(label): the source is unchanged")
    }

    /// A constant image (every value exact in Float16) resamples to exactly the same constant.
    private static func expectConstant(_ buffer: PixelBuffer, sizes: [(Int, Int)], on metal: MetalBackend) throws {
        let source = try metal.surface(buffer)
        defer { metal.release(source) }
        let fill = try buffer.pixel(x: 0, y: 0)
        for filter in [ResampleFilter.bilinear, .lanczos3] {
            for (w, h) in sizes {
                let got = try metal.resampled(source, width: w, height: h, filter: filter)
                defer { metal.release(got) }
                #expect(try metal.read(got) == PixelBuffer(width: w, height: h, fill: fill), "constant \(filter) to \(w)x\(h)")
            }
        }
    }
}
#endif
