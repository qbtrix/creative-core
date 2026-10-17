// MetalBudgetTests.swift: the packet's Memory and Speed rows (MB-16), reported rather than gated:
// 4K x 20 layers stay under the default `budgetBytes`; a 4K `.normal` composite's p95 stays at or under 4 ms (MB-4). Serialized
// so no two 4K runs share memory; the memory test needs an optimized build (twenty per-pixel 4K
// conversions take minutes in debug), and the Mac finisher runs both on release. Device-gated.
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

@Suite(.serialized) struct MetalBudgetTests {
    /// Twenty 4096 x 2160 layers, uploaded from one seeded buffer (the backend copies on upload),
    /// never push `residentBytes` over the default budget, and the last one reads back within Float16.
    @Test(.enabled(if: MetalBackend.defaultDevice != nil && optimized, "4K x 20 needs a device and an optimized build"))
    func twentyFourKLayersStayUnderTheBudget() throws {
        let backend = try MetalBackend.onDefaultDevice()
        let layer = try PixelBuffer.seeded(width: 4096, height: 2160, seed: 2160)
        var last: RenderSurface?
        for index in 0..<20 {
            last = try backend.surface(layer)
            #expect(backend.residentBytes <= backend.budgetBytes, "layer \(index): \(backend.residentBytes) resident")
        }
        guard let last else { throw RenderError.deviceLost("no surface uploaded") }
        let worst = try backend.worstDelta(reading: last, against: layer)
        #expect(worst <= 1e-3, "worst delta \(worst) with \(backend.evictedTileCount) tiles evicted")
    }

    /// The packet's Speed row: a 4K `.normal` composite's p95 over thirty runs (after a warm-up) at or under
    /// 4 ms on release, reported by the Mac finisher; skipped in debug and without `.composite`.
    @Test(.enabled(if: MetalBackend.defaultDevice != nil && optimized, "4K composite timing needs a device and an optimized build"))
    func fourKCompositeP95Under4ms() throws {
        let backend = try MetalBackend.onDefaultDevice()
        guard backend.supports.contains(.composite) else { return }
        let source = try backend.surface(try PixelBuffer.seeded(width: 4096, height: 2160, seed: 4096))
        var backdrop = try backend.surface(try PixelBuffer.seeded(width: 4096, height: 2160, seed: 2160))
        try backend.composite(source, onto: &backdrop, x: 0, y: 0, mode: .normal, opacity: 0.37)
        let times = try (0..<30).map { _ in
            try ContinuousClock().measure { try backend.composite(source, onto: &backdrop, x: 0, y: 0, mode: .normal, opacity: 0.37) }
        }.sorted()
        let p95 = times[28]  // the 29th of 30: index 30 * 95 / 100 rounded down
        #expect(p95 <= .milliseconds(4), "4K composite p95 \(p95)")
    }
}
#endif
