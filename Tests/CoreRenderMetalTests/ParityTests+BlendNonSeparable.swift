// ParityTests+BlendNonSeparable.swift: MB-9 enables `ParityTests/blendNonSeparable` (metal-backend) and owns
// this file. With tier 2, the sample set, rendered from the original Float32 sources (so upload loss counts),
// matches the checked-in CPU goldens within their `.nonSeparable` tolerance. Hue, saturation, color and luminosity at opacities 0, 0.37, 1 on the seeded parity set, on a
// multi-tile source off every edge and (MB-10) on the clip-colour edge rows (lum 0 and 1, greys, pure black and
// white, saturated primaries over grey, opaque and at alpha 0.6) match the CPU on the GPU's pixels within
// `.nonSeparable` through the public `composite`, which MB-10 enables at init on read-write tier 2; without
// tier 2 it throws `unsupported` for them. Skipped without a device.
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
            #expect(metal.supports.contains(.blendNonSeparable) == (metal.device.readWriteTextureSupport == .tier2))
            guard metal.supports.contains(.blendNonSeparable) else {
                var m = try metal.surface(try PixelBuffer.seeded(width: 5, height: 4, seed: 0x0BAD))
                let (ms, held) = (m, try metal.read(m))
                for mode in BlendNonSeparableModes.all {
                    #expect(throws: RenderError.unsupported(.blendNonSeparable)) { try metal.composite(ms, onto: &m, x: 0, y: 0, mode: mode, opacity: 1) }
                }
                #expect(try metal.read(m) == held, "a rejected composite changes nothing")
                return
            }
            try Self.expectGoldens(for: .blendNonSeparable, on: metal)
            let (edgeSource, edgeBackdrop) = try ClipColorEdges.pairs()
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
                    try Self.expectNonSeparable(edgeSource, onto: edgeBackdrop, x: 0, y: 0, mode: mode, opacity: opacity, on: metal, label: "clip-colour edges")
                }
            }
            #expect(metal.isHealthy)
        } catch {
            Issue.record("non-separable blend parity threw \(error)")
        }
    }

    /// Metal's public composite equals the CPU through `mode` on the GPU's pixels within `.nonSeparable`.
    private static func expectNonSeparable(_ source: PixelBuffer, onto backdrop: PixelBuffer, x: Int, y: Int, mode: BlendMode,
                                           opacity: Float, on metal: MetalBackend, label: String) throws {
        let cpu = CPUBackend()
        let (target, s) = (try metal.surface(backdrop), try metal.surface(source))
        defer { metal.release(target); metal.release(s) }
        let (heldSource, heldBackdrop) = (try metal.read(s), try metal.read(target))
        var expected = try cpu.surface(heldBackdrop)
        try cpu.composite(try cpu.surface(heldSource), onto: &expected, x: x, y: y, mode: mode, opacity: opacity)
        var placed = target
        try metal.composite(s, onto: &placed, x: x, y: y, mode: mode, opacity: opacity)
        let result = try ParityHarness.compare(try metal.read(placed), try cpu.read(expected), tolerance: .nonSeparable)
        #expect(result.passed, "\(label) \(mode) at (\(x), \(y)) opacity \(opacity): \(result)")
    }
}

/// The four modes of the `.blendNonSeparable` family.
private enum BlendNonSeparableModes {
    static let all = BlendMode.allCases.filter { RenderOp(compositing: $0) == .blendNonSeparable }
}

/// ClipColor's edge rows (MB-10): every edge colour as source over every edge colour as backdrop. Black has lum 0
/// and white lum 1 (SetLum to them clips a saturated colour low or high to exactly 0 or 1), the greys have
/// max == min (SetSat's and ClipColor's 0 / 0 guards), and the primaries and secondaries over grey leave 0...1
/// after SetLum. The second half of each axis repeats the colours premultiplied at alpha 0.6.
private enum ClipColorEdges {
    static let colors: [(Float, Float, Float)] = [
        (0, 0, 0), (1, 1, 1), (0.5, 0.5, 0.5), (0.18, 0.18, 0.18), (0.9, 0.9, 0.9),
        (1, 0, 0), (0, 1, 0), (0, 0, 1), (0, 1, 1), (1, 0, 1), (1, 1, 0), (1, 0.5, 0), (0.02, 0.98, 0.4),
    ]

    /// The source (colour index across) and backdrop (colour index down), `2 * colors.count` square.
    static func pairs() throws -> (source: PixelBuffer, backdrop: PixelBuffer) {
        let pixels = [Float(1), 0.6].flatMap { a in colors.map { RGBA(r: $0.0 * a, g: $0.1 * a, b: $0.2 * a, a: a) } }
        var (source, backdrop) = (try PixelBuffer(width: pixels.count, height: pixels.count), try PixelBuffer(width: pixels.count, height: pixels.count))
        for (y, down) in pixels.enumerated() {
            for (x, across) in pixels.enumerated() {
                try source.setPixel(x: x, y: y, across)
                try backdrop.setPixel(x: x, y: y, down)
            }
        }
        return (source, backdrop)
    }
}
#endif
