// ParityTests+Unsharp.swift: MB-12 enables `ParityTests/unsharp`. An amount, sigma, threshold grid matches the CPU
// on the GPU's Float16 pixels within `.standard` (sample set, multi-tile source, resident or evicted); a component
// within 1e-4 of the threshold may fall either side (float32 blur), so there it must be one of the rule's two
// outcomes, and rare. Invalid parameters and overflow throw the CPU's error; `.blur` is in `supports`. Device-gated.
#if canImport(Metal)
import CoreRaster
import CoreRender
import CoreRenderMetal
import Testing

extension ParityTests {
    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func unsharp() {
        do {
            let metal = try MetalBackend.onDefaultDevice()
            for sample in try ParityHarness.sampleSet(for: .blur) {
                try Self.expectUnsharpParity(sample.source, on: metal, label: sample.name)
            }
            let tiled = try PixelBuffer.seeded(width: 300, height: 270, seed: 0x5A4B)
            try Self.expectUnsharpParity(tiled, on: metal, label: "300x270")
            metal.budgetBytes = 0
            try Self.expectUnsharpParity(tiled, sigmas: [1.5], on: metal, label: "300x270 evicted")
            let (cpu, small) = (CPUBackend(), try PixelBuffer.seeded(width: 6, height: 4, seed: 0x5A))
            let (m, c) = (try metal.surface(small), try cpu.surface(small))
            for (amount, sigma, threshold) in [(.nan, 1, 0), (.infinity, 1, 0), (1, 1, -1), (1, 1, .nan), (1, 1, .infinity),
                                               (1, -1, 0), (1, .nan, 0), (1, 4.5, 0), (.nan, -1, -1), (1e39, 1, 0), (1e300, 1, 0)] as [(Double, Double, Double)] {
                do {
                    _ = try cpu.unsharpMask(c, amount: amount, sigma: sigma, threshold: threshold)
                    Issue.record("the CPU accepts amount \(amount) sigma \(sigma) threshold \(threshold)")
                } catch let expected as RenderError {
                    #expect(throws: expected) { try metal.unsharpMask(m, amount: amount, sigma: sigma, threshold: threshold) }
                }
            }
            #expect(metal.isHealthy && metal.supports.contains(.blur), "invalid parameters keep it healthy; MB-12 enables .blur")
        } catch {
            Issue.record("unsharp parity threw \(error)")
        }
    }

    /// The grid on `buffer` equals the CPU's unsharp of the GPU's pixels within `.standard`, boundary components aside;
    /// a sigma the CPU rejects throws; amount 0 or sigma 0 is exact; a new surface; the source is unchanged.
    private static func expectUnsharpParity(_ buffer: PixelBuffer, sigmas: [Double] = [0, 1.5, 6], on metal: MetalBackend,
                                            label: String) throws {
        let (cpu, source) = (CPUBackend(), try metal.surface(buffer))
        defer { metal.release(source) }
        let held = try metal.read(source), reference = try cpu.surface(held)
        for sigma in sigmas {
            guard let blurred = try? held.gaussianBlur(sigma: sigma) else {
                #expect(throws: RenderError.self) { try metal.unsharpMask(source, amount: 1, sigma: sigma, threshold: 0) }
                continue
            }
            for amount in [0, 0.6, 2.0] {
                for threshold in [0, 0.02, 0.1] {
                    let tag = "\(label) amount \(amount) sigma \(sigma) threshold \(threshold)"
                    var want = try cpu.read(cpu.unsharpMask(reference, amount: amount, sigma: sigma, threshold: threshold))
                    let got = try metal.unsharpMask(source, amount: amount, sigma: sigma, threshold: threshold)
                    defer { metal.release(got) }
                    #expect(got.id != source.id, "\(tag): a new surface")
                    let pixels = try metal.read(got)
                    if amount == 0 || sigma == 0 { #expect(pixels == held, "\(tag): the identity") }
                    let moved = try Self.acceptBoundary(&want, pixels, held, blurred, amount: amount, threshold: threshold, tag: tag)
                    #expect(moved * 1000 <= held.width * held.height * 4 + 1000, "\(tag): \(moved) boundary components")
                    let result = try ParityHarness.compare(pixels, want, tolerance: .standard)
                    #expect(result.passed, "\(tag): \(result)")
                }
            }
        }
        #expect(try metal.read(source) == held, "\(label): the source is unchanged")
    }

    /// Where a component's difference is within 1e-4 of `threshold` and its outcomes differ by over 1e-3, checks
    /// the GPU gave one of them and takes it into `want`. Returns how many it took.
    private static func acceptBoundary(_ want: inout PixelBuffer, _ pixels: PixelBuffer, _ held: PixelBuffer,
                                       _ blurred: PixelBuffer, amount: Double, threshold: Double, tag: String) throws -> Int {
        var moved = 0
        for y in 0..<held.height {
            for x in 0..<held.width {
                let (s, b, g) = (try held.pixel(x: x, y: y), try blurred.pixel(x: x, y: y), try pixels.pixel(x: x, y: y))
                var w = try want.pixel(x: x, y: y)
                for (sv, bv, gv, path) in [(s.r, b.r, g.r, \RGBA.r), (s.g, b.g, g.g, \RGBA.g), (s.b, b.b, g.b, \RGBA.b), (s.a, b.a, g.a, \RGBA.a)] {
                    let d = Double(sv) - Double(bv)
                    guard abs(abs(d) - threshold) <= 1e-4, abs(amount * d) > 1e-3 else { continue }
                    let near = { (v: Double) in abs(Double(gv) - v) <= 1e-3 + abs(v) * 1e-3 }
                    #expect(near(Double(sv)) || near(Double(sv) + amount * d), "\(tag) (\(x), \(y)): \(gv) is neither outcome")
                    w[keyPath: path] = gv
                    moved += 1
                }
                try want.setPixel(x: x, y: y, w)
            }
        }
        return moved
    }
}
#endif
