// ParityTests+Blur.swift: MB-11 enables `ParityTests/blur`. The sample set, rendered from the original Float32
// sources (so upload loss counts), matches the checked-in CPU blur goldens within their tolerance. Gaussian blur at sigma 0, 0.5, 3, 20 matches the CPU
// on the GPU's Float16 pixels within `.standard` on the sample set and a multi-tile source, resident or evicted;
// sigma 0 is the identity; a constant image stays constant to its corners (clamp-to-edge: a border never reads
// black); an invalid sigma throws the CPU backend's error; `.blur` is in `supports` (MB-12 added it); an image over
// the device's buffer limit (forced smaller) throws `unsupported(.blur)` and the backend stays healthy. Skipped without a device; compiled out on Linux.
#if canImport(Metal)
import CoreRaster
import CoreRender
import CoreRenderMetal
import Testing

extension ParityTests {
    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func blur() {
        do {
            let metal = try MetalBackend.onDefaultDevice()
            try Self.expectGoldens(for: .blur, on: metal)
            let sigmas = [0, 0.5, 3, 20]
            for sample in try ParityHarness.sampleSet(for: .blur) {
                try Self.expectBlurParity(sample.source, sigmas: sigmas, on: metal, label: sample.name)
            }
            let tiled = try PixelBuffer.seeded(width: 300, height: 270, seed: 0xB10B)
            try Self.expectBlurParity(tiled, sigmas: sigmas, on: metal, label: "300x270")
            let fill = RGBA(r: 0.25, g: 0.5, b: 0.125, a: 0.75)
            try Self.expectEdgesKeepTheFill(try PixelBuffer(width: 300, height: 270, fill: fill), on: metal)
            metal.budgetBytes = 0
            try Self.expectBlurParity(tiled, sigmas: [0, 3, 20], on: metal, label: "300x270 evicted")
            try Self.expectEdgesKeepTheFill(try PixelBuffer(width: 300, height: 270, fill: fill), on: metal)
            let (cpu, small) = (CPUBackend(), try PixelBuffer.seeded(width: 6, height: 4, seed: 0xB1))
            let (m, c) = (try metal.surface(small), try cpu.surface(small))
            for sigma in [-1, -0.001, .nan, .infinity, 4.5, 1e300] {
                do {
                    _ = try cpu.gaussianBlur(c, sigma: sigma)
                    Issue.record("the CPU accepts sigma \(sigma)")
                } catch let expected as RenderError {
                    #expect(throws: expected) { try metal.gaussianBlur(m, sigma: sigma) }
                }
            }
            #expect(metal.isHealthy, "an invalid sigma does not fail the backend")
            #expect(metal.supports.contains(.blur), "MB-12 enables .blur")
        } catch {
            Issue.record("blur parity threw \(error)")
        }
    }

    /// Each sigma of `buffer` equals the CPU's blur of the GPU's pixels within `.standard`; a sigma the CPU
    /// rejects for this size throws the same error; sigma 0 gives the pixels back exactly; the source is unchanged.
    private static func expectBlurParity(_ buffer: PixelBuffer, sigmas: [Double], on metal: MetalBackend,
                                         label: String) throws {
        let cpu = CPUBackend()
        let source = try metal.surface(buffer)
        defer { metal.release(source) }
        let held = try metal.read(source)
        let reference = try cpu.surface(held)
        for sigma in sigmas {
            let want: PixelBuffer
            do { want = try cpu.read(cpu.gaussianBlur(reference, sigma: sigma)) } catch let expected as RenderError {
                #expect(throws: expected) { try metal.gaussianBlur(source, sigma: sigma) }
                continue
            }
            let got = try metal.gaussianBlur(source, sigma: sigma)
            defer { metal.release(got) }
            #expect(got.id != source.id, "\(label) sigma \(sigma): a new surface")
            let pixels = try metal.read(got)
            if sigma == 0 { #expect(pixels == held, "\(label): sigma 0 is the identity") }
            let result = try ParityHarness.compare(pixels, want, tolerance: .standard)
            #expect(result.passed, "\(label) sigma \(sigma): \(result)")
        }
        #expect(try metal.read(source) == held, "\(label): the source is unchanged")
    }

    /// A constant image (exact in Float16) keeps its value at every corner and edge midpoint: a tap past the
    /// border repeats the edge pixel instead of reading black.
    private static func expectEdgesKeepTheFill(_ buffer: PixelBuffer, on metal: MetalBackend) throws {
        let source = try metal.surface(buffer)
        defer { metal.release(source) }
        let fill = try buffer.pixel(x: 0, y: 0)
        let (w, h) = (buffer.width, buffer.height)
        for sigma in [0.5, 3, 20] {
            let got = try metal.gaussianBlur(source, sigma: sigma)
            defer { metal.release(got) }
            let pixels = try metal.read(got)
            for (x, y) in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (w / 2, 0), (0, h / 2), (w - 1, h / 2), (w / 2, h - 1)] {
                let p = try pixels.pixel(x: x, y: y)
                let worst = max(abs(p.r - fill.r), abs(p.g - fill.g), abs(p.b - fill.b), abs(p.a - fill.a))
                #expect(worst <= 1.0 / 1024, "sigma \(sigma) at (\(x), \(y)) reads \(p), not \(fill)")
            }
        }
    }
}

extension ParityTests {
    /// A valid image one byte over the buffer limit throws `unsupported(.blur)` (a device limit: blur on the CPU),
    /// not `raster`; the backend stays healthy; at the limit it runs; an invalid sigma still throws the CPU's error.
    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func blurOverTheDeviceLimit() throws {
        let metal = try MetalBackend.onDefaultDevice()
        let (cpu, buffer) = (CPUBackend(), try PixelBuffer.seeded(width: 300, height: 260, seed: 0xB1F))
        let source = try metal.surface(buffer)
        let limit = 300 * 260 * 16
        #expect(throws: RenderError.unsupported(.blur)) { try metal.blur(source, sigma: 3, bufferLimit: limit - 1) }
        #expect(metal.isHealthy, "a device limit does not fail the backend")
        let got = try metal.read(metal.blur(source, sigma: 3, bufferLimit: limit))
        let want = try cpu.read(cpu.gaussianBlur(cpu.surface(metal.read(source)), sigma: 3))
        #expect(try ParityHarness.compare(got, want, tolerance: .standard).passed, "at the limit it blurs")
        do {
            _ = try cpu.gaussianBlur(cpu.surface(buffer), sigma: -1)
            Issue.record("the CPU accepts sigma -1")
        } catch let expected as RenderError {
            #expect(throws: expected) { try metal.blur(source, sigma: -1, bufferLimit: 0) }
        }
    }
}
#endif
