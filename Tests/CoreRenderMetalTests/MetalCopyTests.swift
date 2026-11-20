// MetalCopyTests.swift: #833. `copied` and `blank` on Metal stay on the GPU: a 6000 x 4000 copy and blank
// add nothing to `cpuTileUploadCount` (an upload of the same size adds one per tile, so the counter is live);
// a copy reads back bit for bit equal to its source (edge tiles, evicted source tiles), is independent of it
// (a composite onto the copy leaves the source alone), and a blank reads back clear even in memory a
// released surface just used. Skipped without a device.
#if canImport(Metal)
import CoreRaster
import CoreRender
@testable import CoreRenderMetal
import Testing

private let hasDevice = MetalBackend.defaultDevice != nil

@Suite(.serialized) struct MetalCopyTests {
    @Test(.enabled(if: hasDevice)) func aCopyAndABlankOf24MegapixelsUploadNoTile() throws {
        let metal = try MetalBackend.onDefaultDevice()
        let source = try metal.surface(PixelBuffer(width: 6000, height: 4000, fill: RGBA(r: 0.25, g: 0.5, b: 0.125, a: 0.75)))
        let tiles = try SurfaceTiling(width: 6000, height: 4000).tileCount
        #expect(metal.cpuTileUploadCount == tiles, "the upload fills every tile from the CPU")
        let copy = try metal.copied(source)
        let blank = try metal.blank(width: 6000, height: 4000)
        #expect(metal.cpuTileUploadCount == tiles, "copied and blank stay on the GPU")
        #expect(copy.width == 6000 && copy.height == 4000 && blank.width == 6000 && blank.height == 4000)
    }

    @Test(.enabled(if: hasDevice)) func aCopyReadsBackBitForBitEqualToItsSource() throws {
        let metal = try MetalBackend.onDefaultDevice()
        for budget in [metal.budgetBytes, 0] {
            metal.budgetBytes = budget
            let source = try metal.surface(PixelBuffer.seeded(width: 600, height: 530, seed: 0x833))
            let copy = try metal.copied(source)
            #expect(copy != source)
            #expect(try metal.read(copy) == metal.read(source), "budget \(budget)")
        }
    }

    @Test(.enabled(if: hasDevice)) func aCompositeOntoTheCopyLeavesTheSourceAlone() throws {
        let metal = try MetalBackend.onDefaultDevice()
        guard metal.supports.contains(.composite) else { return }
        let pixels = try PixelBuffer.seeded(width: 300, height: 270, seed: 0x8331)
        let source = try metal.surface(pixels)
        var copy = try metal.copied(source)
        let red = try metal.surface(PixelBuffer(width: 300, height: 270, fill: RGBA(r: 1, g: 0, b: 0, a: 1)))
        try metal.composite(red, onto: &copy, x: 0, y: 0, mode: .normal, opacity: 1)
        #expect(try metal.read(copy) == metal.read(red))
        #expect(try metal.worstDelta(reading: source, against: pixels) <= 1e-3)
        metal.release(source)
        #expect(try metal.read(copy) == metal.read(red), "the copy outlives its source")
    }

    @Test(.enabled(if: hasDevice)) func aBlankReadsBackClearInMemoryAReleasedSurfaceUsed() throws {
        let metal = try MetalBackend.onDefaultDevice()
        for _ in 0..<3 {
            metal.release(try metal.surface(PixelBuffer(width: 700, height: 600, fill: RGBA(r: 0.9, g: 0.8, b: 0.7, a: 1))))
            let blank = try metal.blank(width: 700, height: 600)
            #expect(try metal.read(blank) == PixelBuffer(width: 700, height: 600))
        }
    }
}
#endif
