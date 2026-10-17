// ParityTests+BlendSeparable.swift: MB-5 enables `ParityTests/blendSeparable` (metal-backend) and owns this
// file. All twelve separable modes at opacities 0, 0.37, 1 on the seeded parity set and on multi-tile sources
// off every edge match the CPU on the GPU's pixels within `.standard`; non-separable modes still throw
// `unsupported`. `.blendSeparable` is off at init until MB-6, so the test turns it on through the parity hook.
// Skipped without a device; returns early without read-write tier 2.
#if canImport(Metal)
import CoreRaster
import CoreRender
import CoreRenderMetal
import Testing

extension ParityTests {
    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func blendSeparable() {
        do {
            let metal = try MetalBackend.onDefaultDevice()
            #expect(!metal.supports.contains(.blendSeparable), "MB-6 enables the family at init, not MB-5")
            guard metal.enableSeparableBlendsForParity() else { return }
            let modes = BlendMode.allCases.filter { RenderOp(compositing: $0) != .blendNonSeparable }
            #expect(modes.count == 12)
            let samples = try ParityHarness.sampleSet(for: .blendSeparable)
            let (backdrop, source) = (try PixelBuffer.seeded(width: 300, height: 270, seed: 0xB1E0), try PixelBuffer.seeded(width: 260, height: 200, seed: 0x5E9A))
            let offsets = [(-130, -100), (170, -100), (-130, 170), (170, 170), (20, 35)]
            for mode in modes {
                for opacity: Float in [0, 0.37, 1] {
                    for sample in samples {
                        guard let held = sample.backdrop, case let .composite(x, y, _, _) = sample.call else { continue }
                        try Self.expectBlend(sample.source, onto: held, x: x, y: y, mode: mode, opacity: opacity, on: metal, label: sample.name)
                    }
                    for (x, y) in offsets {
                        try Self.expectBlend(source, onto: backdrop, x: x, y: y, mode: mode, opacity: opacity, on: metal, label: "260x200 on 300x270")
                    }
                }
            }
            var m = try metal.surface(try PixelBuffer.seeded(width: 5, height: 4, seed: 0x0BAD))
            let (ms, held) = (m, try metal.read(m))
            for mode in BlendMode.allCases where RenderOp(compositing: mode) == .blendNonSeparable {
                #expect(throws: RenderError.unsupported(.blendNonSeparable)) { try metal.composite(ms, onto: &m, x: 0, y: 0, mode: mode, opacity: 1) }
            }
            #expect(try metal.read(m) == held, "a rejected composite changes nothing")
            #expect(metal.isHealthy)
        } catch {
            Issue.record("separable blend parity threw \(error)")
        }
    }

    /// Metal equals the CPU through `mode` on the GPU's pixels within `.standard`.
    private static func expectBlend(_ source: PixelBuffer, onto backdrop: PixelBuffer, x: Int, y: Int, mode: BlendMode,
                                    opacity: Float, on metal: MetalBackend, label: String) throws {
        let cpu = CPUBackend()
        var target = try metal.surface(backdrop)
        let s = try metal.surface(source)
        defer { metal.release(target); metal.release(s) }
        let (heldSource, heldBackdrop) = (try metal.read(s), try metal.read(target))
        var expected = try cpu.surface(heldBackdrop)
        try cpu.composite(try cpu.surface(heldSource), onto: &expected, x: x, y: y, mode: mode, opacity: opacity)
        try metal.composite(s, onto: &target, x: x, y: y, mode: mode, opacity: opacity)
        let result = try ParityHarness.compare(try metal.read(target), try cpu.read(expected), tolerance: .standard)
        #expect(result.passed, "\(label) \(mode) at (\(x), \(y)) opacity \(opacity): \(result)")
    }
}
#endif
