// ParityTests+BlendNonSeparable.swift: MB-9 enables `ParityTests/blendNonSeparable` (metal-backend) and owns
// this file. Hue, saturation, color and luminosity at opacities 0, 0.37, 1 on the seeded parity set and on a
// multi-tile source off every edge match the CPU on the GPU's pixels within `.nonSeparable`, through the
// in-place composite after the parity hook (MB-10 enables the family at init); the public `composite` still
// throws `unsupported` for them. Skipped without a device; returns early without read-write tier 2.
#if canImport(Metal)
import CoreRaster
import CoreRender
import CoreRenderMetal
import Metal
import Testing

extension ParityTests {
    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func blendNonSeparable() {
        do {
            let metal = try MetalBackend.onDefaultDevice()
            #expect(BlendNonSeparableModes.all == [.hue, .saturation, .color, .luminosity])
            var m = try metal.surface(try PixelBuffer.seeded(width: 5, height: 4, seed: 0x0BAD))
            let (ms, held) = (m, try metal.read(m))
            for mode in BlendNonSeparableModes.all {
                #expect(throws: RenderError.unsupported(.blendNonSeparable)) { try metal.composite(ms, onto: &m, x: 0, y: 0, mode: mode, opacity: 1) }
            }
            #expect(try metal.read(m) == held, "a rejected composite changes nothing")
            #expect(metal.enableNonSeparableBlendsForParity() == (metal.device.readWriteTextureSupport == .tier2))
            guard metal.supports.contains(.blendNonSeparable) else { return }
            let samples = try ParityHarness.sampleSet(for: .blendNonSeparable)
            let (backdrop, source) = (try PixelBuffer.seeded(width: 300, height: 270, seed: 0xB1E1), try PixelBuffer.seeded(width: 260, height: 200, seed: 0x5E9B))
            for mode in BlendNonSeparableModes.all {
                for opacity: Float in [0, 0.37, 1] {
                    for sample in samples {
                        guard let held = sample.backdrop, case let .composite(x, y, _, _) = sample.call else { continue }
                        try Self.expectNonSeparable(sample.source, onto: held, x: x, y: y, mode: mode, opacity: opacity, on: metal, label: sample.name)
                    }
                    for (x, y) in [(-130, -100), (170, 170), (20, 35)] {
                        try Self.expectNonSeparable(source, onto: backdrop, x: x, y: y, mode: mode, opacity: opacity, on: metal, label: "260x200 on 300x270")
                    }
                }
            }
            #expect(metal.isHealthy)
        } catch {
            Issue.record("non-separable blend parity threw \(error)")
        }
    }

    /// Metal's in-place composite equals the CPU through `mode` on the GPU's pixels within `.nonSeparable`.
    private static func expectNonSeparable(_ source: PixelBuffer, onto backdrop: PixelBuffer, x: Int, y: Int, mode: BlendMode,
                                           opacity: Float, on metal: MetalBackend, label: String) throws {
        let cpu = CPUBackend()
        let (target, s) = (try metal.surface(backdrop), try metal.surface(source))
        defer { metal.release(target); metal.release(s) }
        let (heldSource, heldBackdrop) = (try metal.read(s), try metal.read(target))
        var expected = try cpu.surface(heldBackdrop)
        try cpu.composite(try cpu.surface(heldSource), onto: &expected, x: x, y: y, mode: mode, opacity: opacity)
        try metal.compositeInPlace(s, onto: target, x: x, y: y, mode: mode, opacity: opacity)
        let result = try ParityHarness.compare(try metal.read(target), try cpu.read(expected), tolerance: .nonSeparable)
        #expect(result.passed, "\(label) \(mode) at (\(x), \(y)) opacity \(opacity): \(result)")
    }
}

/// The four modes of the `.blendNonSeparable` family.
private enum BlendNonSeparableModes {
    static let all = BlendMode.allCases.filter { RenderOp(compositing: $0) == .blendNonSeparable }
}
#endif
