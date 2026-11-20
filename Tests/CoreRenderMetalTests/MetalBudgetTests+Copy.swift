// MetalBudgetTests+Copy.swift: #833's Speed row, gated: Photo's drag frame copies its base composite once per
// region, so sixteen 1500 x 1000 copies (24 MP) of resident surfaces, waited for and released, stay at or under
// 6 ms p95 over twenty runs (after a warm-up; measured 3.2 to 4.5 ms on an M2 Pro at load average 22), with no
// tile filled from the CPU and none evicted. Released copies return their tiles to the texture pool, so after
// the warm-up no run allocates a texture. The issue's 2 ms target is not met: the blits alone are about 2 ms of
// GPU time on an M2 Pro (384 MB read and written, the bandwidth floor). The test prints the split. Optimized
// builds only, like the rest of MetalBudgetTests. Device-gated.
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
        var allocated = 0
        let clock = ContinuousClock()
        var encode: [Duration] = [], wait: [Duration] = [], release: [Duration] = [], total: [Duration] = []
        for _ in 0..<21 {  // the first run is the warm-up
            var copies: [RenderSurface] = []
            let e = try clock.measure { copies = try regions.map { try backend.copied($0) } }
            let w = clock.measure { backend.waitForCommittedWork() }
            let r = clock.measure { copies.forEach(backend.release) }
            (encode, wait, release, total) = (encode + [e], wait + [w], release + [r], total + [e + w + r])
            if encode.count == 1 { allocated = backend.pooledTextureAllocationCount }
        }
        // index 20 * 95 / 100 of the twenty timed runs, as the affine row computes it
        let p95 = { (times: [Duration]) in times.dropFirst().sorted()[19] }
        let median = { (times: [Duration]) in times.dropFirst().sorted()[10] }
        #expect(p95(total) <= .milliseconds(6), "16 x 1.5 MP copy p95 \(p95(total)), median \(median(total))")
        #expect(backend.cpuTileUploadCount == uploaded, "no copy filled a tile from the CPU")
        #expect(backend.pooledTextureAllocationCount == allocated, "every run after the warm-up reused pooled tiles")
        #expect(backend.evictedTileCount == 0, "every region stays resident")
        print("copy 16 x 1.5MP p95 \(p95(total)) median \(median(total)); encode+alloc p95 \(p95(encode)) median \(median(encode)); "
              + "GPU wait p95 \(p95(wait)) median \(median(wait)); release p95 \(p95(release)) median \(median(release))")
    }
}
#endif
