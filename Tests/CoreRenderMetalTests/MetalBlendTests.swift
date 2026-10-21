// MetalBlendTests.swift: linear dodge and linear burn on Metal (layer-style-engine LE-7). Both have a
// `blendSeparable_<mode>` kernel, and on tier 2 the GPU matches the CPU within `.standard` where they
// clamp (a dodge past 1, a burn below 0) and across seeded pixels at three opacities. Skipped without a
// device; returns early without tier 2. Compiled out on Linux.
#if canImport(Metal)
import CoreRaster
import CoreRender
import CoreRenderMetal
import Metal
import Testing

@Suite struct MetalBlendTests {
    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func linearModesMatchTheCPU() throws {
        let metal = try MetalBackend.onDefaultDevice()
        guard metal.supports.contains(.blendSeparable) else { return }
        let grey = { (v: Float) in try PixelBuffer(width: 8, height: 8, fill: RGBA(r: v, g: v, b: v, a: 1)) }
        let cases: [(PixelBuffer, PixelBuffer, String)] = [
            (try grey(0.6), try grey(0.6), "0.6 over 0.6"), (try grey(0.2), try grey(0.2), "0.2 over 0.2"),
            (try PixelBuffer.seeded(width: 40, height: 30, seed: 0x1D0D), try PixelBuffer.seeded(width: 50, height: 40, seed: 0x1B4A), "seeded"),
        ]
        for mode in [BlendMode.linearDodge, .linearBurn] {
            #expect(RenderOp(compositing: mode) == .blendSeparable)
            for (source, backdrop, label) in cases {
                for opacity: Float in [0, 0.37, 1] {
                    var target = try metal.surface(backdrop)
                    let s = try metal.surface(source)
                    defer { metal.release(target); metal.release(s) }
                    // The CPU blends what the GPU holds, so Float16 storage is not counted as drift.
                    let cpu = CPUBackend()
                    var expected = try cpu.surface(try metal.read(target))
                    try cpu.composite(try cpu.surface(try metal.read(s)), onto: &expected, x: 3, y: 2, mode: mode, opacity: opacity)
                    try metal.composite(s, onto: &target, x: 3, y: 2, mode: mode, opacity: opacity)
                    let result = try ParityHarness.compare(try metal.read(target), try cpu.read(expected), tolerance: .standard)
                    #expect(result.passed, "\(label) \(mode) opacity \(opacity): \(result)")
                }
            }
        }
        #expect(metal.isHealthy)
    }
}
#endif
