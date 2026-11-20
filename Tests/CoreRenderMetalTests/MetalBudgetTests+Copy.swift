// MetalBudgetTests+Copy.swift: #833's Speed row, gated: Photo's drag frame copies its base composite once per
// region, so sixteen 1500 x 1000 copies (24 MP) on resident surfaces take at most 2 ms p95 over twenty runs
// (after a warm-up), with no tile filled from the CPU and none evicted. The timed span includes the GPU work:
// each run ends by waiting for the last copy's command buffer. Optimized builds only, like the rest of
// MetalBudgetTests. Device-gated.
#if canImport(Metal)
import CoreRaster
import CoreRender
@testable import CoreRenderMetal
import Testing

#if DEBUG
private let optimized = false
#else
private let optimized = true
#endif

extension MetalBudgetTests {
    @Test(.enabled(if: MetalBackend.defaultDevice != nil && optimized, "24 MP copy timing needs a device and an optimized build"))
    func sixteenRegionCopyOf24MPP95Under2ms() throws {
        let backend = try MetalBackend.onDefaultDevice()
        let regions = try (0..<16).map { index in
            try backend.surface(PixelBuffer(width: 1500, height: 1000, fill: RGBA(r: Float(index) / 16, g: 0.5, b: 0.25, a: 1)))
        }
        let uploaded = backend.cpuTileUploadCount
        let run = {
            let copies = try regions.map { try backend.copied($0) }
            backend.waitForCommittedWork()
            copies.forEach(backend.release)
        }
        try run()
        let times = try (0..<20).map { _ in try ContinuousClock().measure(run) }.sorted()
        let p95 = times[19]  // index 20 * 95 / 100, as the affine row computes it
        #expect(p95 <= .milliseconds(2), "16 x 1.5 MP copy p95 \(p95), median \(times[10])")
        #expect(backend.cpuTileUploadCount == uploaded, "no copy filled a tile from the CPU")
        #expect(backend.evictedTileCount == 0, "every region stays resident")
        print("copy 16 x 1.5MP p95 \(p95) median \(times[10]) min \(times[0])")
    }
}
#endif
