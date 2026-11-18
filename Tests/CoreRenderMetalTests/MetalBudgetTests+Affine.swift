// MetalBudgetTests+Affine.swift: #829's Speed row, gated: a 24 MP layer composited through a 15 degree turn,
// a 1.3x scale and a fractional offset onto a 24 MP backdrop, both resident, `.multiply` at opacity 0.7, bilinear,
// stays at or under 6 ms p95 (captain 2026-11-18: 4 ms deferred past beta, #829 follow-up; the 498 MB floor is about 3 ms) over twenty runs (after a warm-up) with no tile evicted and no readback.
// Optimized builds only, like the rest of MetalBudgetTests. Device-gated.
#if canImport(Metal)
import CoreRaster
import CoreRender
import CoreRenderMetal
import Testing

#if DEBUG
private let optimized = false
#else
private let optimized = true
#endif

extension MetalBudgetTests {
    @Test(.enabled(if: MetalBackend.defaultDevice != nil && optimized, "24 MP affine timing needs a device and an optimized build"))
    func affineComposite24MPP95Under6ms() throws {
        let backend = try MetalBackend.onDefaultDevice()
        guard backend.supports.contains(.affine) else { return }
        let source = try backend.surface(try PixelBuffer.softAlpha(width: 6000, height: 4000, seed: 0x829C))
        var backdrop = try backend.surface(try PixelBuffer.seeded(width: 6000, height: 4000, seed: 0x829D))
        let m = turnAndScale(tx: 512.375, ty: 64.625)
        let run = { try backend.composite(source, onto: &backdrop, through: m, mode: .multiply, opacity: 0.7, filter: .bilinear) }
        try run()
        let times = try (0..<20).map { _ in try ContinuousClock().measure(run) }.sorted()
        let p95 = times[19]  // index 20 * 95 / 100, as the 4K row computes it
        #expect(p95 <= .milliseconds(6), "24 MP affine composite p95 \(p95), median \(times[10])")
        #expect(backend.affineCPUCompositeCount == 0, "every run stayed on the GPU path")
        #expect(backend.evictedTileCount == 0, "both layers stay resident: nothing to read back")
        print("affine 24MP p95 \(p95) median \(times[10]) min \(times[0])")
    }
}
#endif
