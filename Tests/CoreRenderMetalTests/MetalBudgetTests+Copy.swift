// MetalBudgetTests+Copy.swift: #833's Speed row, gated: Photo's drag frame copies its base composite once per
// region, so sixteen 1500 x 1000 copies (24 MP) of resident surfaces, waited for and released, stay at or under
// 12 ms p95 over twenty runs (after a warm-up; measured 7.7 ms on a quiet M2 Pro, 10 to 10.7 ms at load average 13),
// with no tile filled from the CPU and none evicted. The issue's 2 ms target is not met: the blits alone are
// about 2.1 ms of GPU time on an M2 Pro (384 MB read and written, the bandwidth floor), and most of the rest is
// allocating and freeing 384 tile textures per frame, which a texture pool would remove (the follow-up). The
// test prints the split. Optimized builds only, like the rest of MetalBudgetTests. Device-gated.
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
    func sixteenRegionCopyOf24MPStaysInItsBudget() throws {
        let backend = try MetalBackend.onDefaultDevice()
        let regions = try (0..<16).map { index in
            try backend.surface(PixelBuffer(width: 1500, height: 1000, fill: RGBA(r: Float(index) / 16, g: 0.5, b: 0.25, a: 1)))
        }
        let uploaded = backend.cpuTileUploadCount
        let clock = ContinuousClock()
        var encode: [Duration] = [], wait: [Duration] = [], release: [Duration] = [], total: [Duration] = []
        for _ in 0..<21 {  // the first run is the warm-up
            var copies: [RenderSurface] = []
            let e = try clock.measure { copies = try regions.map { try backend.copied($0) } }
            let w = clock.measure { backend.waitForCommittedWork() }
            let r = clock.measure { copies.forEach(backend.release) }
            (encode, wait, release, total) = (encode + [e], wait + [w], release + [r], total + [e + w + r])
        }
        // index 20 * 95 / 100 of the twenty timed runs, as the affine row computes it
        let p95 = { (times: [Duration]) in times.dropFirst().sorted()[19] }
        let median = { (times: [Duration]) in times.dropFirst().sorted()[10] }
        #expect(p95(total) <= .milliseconds(12), "16 x 1.5 MP copy p95 \(p95(total)), median \(median(total))")
        #expect(backend.cpuTileUploadCount == uploaded, "no copy filled a tile from the CPU")
        #expect(backend.evictedTileCount == 0, "every region stays resident")
        print("copy 16 x 1.5MP p95 \(p95(total)) median \(median(total)); encode+alloc p95 \(p95(encode)) median \(median(encode)); "
              + "GPU wait p95 \(p95(wait)) median \(median(wait)); release p95 \(p95(release)) median \(median(release))")
    }
}
#endif
