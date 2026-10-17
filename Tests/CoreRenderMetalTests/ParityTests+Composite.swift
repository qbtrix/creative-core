// ParityTests+Composite.swift: MB-4 enables `ParityTests/compositeNormal` (metal-backend) and owns this file.
// The `.composite` sample set, rendered from its original Float32 sources, matches the checked-in goldens.
// `.normal` at opacities 0, 0.37, 1, sources off every edge and corner, wholly outside, alpha 1e-45 and onto
// itself, resident or evicted, or evicted between planning and encode, match the CPU on the GPU's pixels within
// `.standard`. Skipped without a device.
#if canImport(Metal)
import CoreRaster
import CoreRender
import CoreRenderMetal
import Metal
import Testing

extension ParityTests {
    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func compositeNormal() {
        do {
            let metal = try MetalBackend.onDefaultDevice()
            #expect(metal.supports.contains(.composite) == (metal.device.readWriteTextureSupport == .tier2), "needs read-write tier 2")
            guard metal.supports.contains(.composite) else { return }
            try Self.expectGoldens(for: .composite, on: metal)
            for sample in try ParityHarness.sampleSet(for: .composite) {
                guard let backdrop = sample.backdrop, case let .composite(x, y, .normal, opacity) = sample.call else { continue }
                try Self.expectComposite(sample.source, onto: backdrop, x: x, y: y, opacity: opacity, on: metal, label: sample.name)
            }
            let (backdrop, source) = (try PixelBuffer.seeded(width: 300, height: 270, seed: 0xBAC0), try PixelBuffer.seeded(width: 260, height: 200, seed: 0x5A11))
            let subnormal = try PixelBuffer(width: 260, height: 200, fill: RGBA(r: 1e-45, g: 1e-45, b: 1e-45, a: 1e-45))
            let edges = [-130, 20, 170].flatMap { x in [-100, 35, 170].map { (x, $0) } }
            let outside = [(300, 0), (-260, 0), (0, 270), (0, -200), (Int.min, 0), (Int.max, Int.max)]
            for opacity: Float in [0, 0.37, 1] {
                for (x, y) in edges + outside {
                    try Self.expectComposite(source, onto: backdrop, x: x, y: y, opacity: opacity, on: metal, label: "300x270")
                }
                try Self.expectComposite(subnormal, onto: backdrop, x: 20, y: 35, opacity: opacity, on: metal, label: "alpha 1e-45")
                try Self.expectComposite(backdrop, onto: backdrop, x: 7, y: 5, opacity: opacity, on: metal, label: "onto itself", itself: true)
            }
            try Self.expectEvictedMidway(source, onto: backdrop, on: metal)
            metal.budgetBytes = 0
            try [(-130, -100), (170, 170)].forEach { try Self.expectComposite(source, onto: backdrop, x: $0.0, y: $0.1, opacity: 0.37, on: metal, label: "evicted") }
            try Self.expectRejections(on: metal)
            #expect(metal.isHealthy, "a rejected composite does not fail the backend")
        } catch {
            Issue.record("composite parity threw \(error)")
        }
    }

    /// Metal equals the CPU on the GPU's pixels within `.standard`; `itself` composites the backdrop onto itself.
    private static func expectComposite(_ source: PixelBuffer, onto backdrop: PixelBuffer, x: Int, y: Int, opacity: Float,
                                        on metal: MetalBackend, label: String, itself: Bool = false) throws {
        let cpu = CPUBackend()
        var target = try metal.surface(backdrop)
        let s = itself ? target : try metal.surface(source)
        defer { metal.release(target); if !itself { metal.release(s) } }
        let (heldSource, heldBackdrop) = (try metal.read(s), try metal.read(target))
        var expected = try cpu.surface(heldBackdrop)
        let reference = itself ? expected : try cpu.surface(heldSource)
        try cpu.composite(reference, onto: &expected, x: x, y: y, mode: .normal, opacity: opacity)
        try metal.composite(s, onto: &target, x: x, y: y, mode: .normal, opacity: opacity)
        let (got, want) = (try metal.read(target), try cpu.read(expected))
        let name = "\(label) at (\(x), \(y)) opacity \(opacity)"
        let untouched = opacity == 0 || x >= backdrop.width || y >= backdrop.height
            || x <= -heldSource.width || y <= -heldSource.height
        if untouched { #expect(got == heldBackdrop, "\(name): the backdrop is unchanged") }
        let result = try ParityHarness.compare(got, want, tolerance: .standard)
        #expect(result.passed, "\(name): \(result)")
    }

    /// Every tile evicted after planning (budget 0 from the hook) is restored from its current shadow: the result
    /// still matches the CPU on the GPU's pixels and the budget holds afterwards.
    private static func expectEvictedMidway(_ source: PixelBuffer, onto backdrop: PixelBuffer, on metal: MetalBackend) throws {
        let cpu = CPUBackend()
        let (target, s) = (try metal.surface(backdrop), try metal.surface(source))
        defer { metal.release(target); metal.release(s); metal.budgetBytes = Int.max }
        var expected = try cpu.surface(try metal.read(target))
        try cpu.composite(try cpu.surface(try metal.read(s)), onto: &expected, x: 20, y: 100, mode: .normal, opacity: 0.37)
        try metal.compositeInPlace(s, onto: target, x: 20, y: 100, mode: .normal, opacity: 0.37) { metal.budgetBytes = 0 }
        #expect(metal.residentBytes <= metal.budgetBytes, "restored tiles leave again: \(metal.residentBytes)")
        let result = try ParityHarness.compare(try metal.read(target), try cpu.read(expected), tolerance: .standard)
        #expect(result.passed, "evicted between planning and encode: \(result)")
    }

    /// A bad opacity throws the CPU's error with the backdrop unchanged; an unlanded family throws `unsupported`.
    private static func expectRejections(on metal: MetalBackend) throws {
        var m = try metal.surface(try PixelBuffer.seeded(width: 5, height: 4, seed: 0x0BAD))
        let (ms, held) = (m, try metal.read(m))  // ms: the same surface as source, without overlapping access
        for opacity: Float in [-0.01, 1.01, .nan, .infinity] {
            #expect(throws: RenderError.raster("opacity \(opacity): must be a finite value in 0...1")) {
                try metal.composite(ms, onto: &m, x: 0, y: 0, mode: .normal, opacity: opacity)
            }
        }
        for mode in BlendMode.allCases where !metal.supports.contains(RenderOp(compositing: mode)) {
            #expect(throws: RenderError.unsupported(RenderOp(compositing: mode))) { try metal.composite(ms, onto: &m, x: 0, y: 0, mode: mode, opacity: 1) }
        }
        #expect(try metal.read(m) == held, "a rejected composite changes nothing")
        metal.release(m)
    }
}
#endif
