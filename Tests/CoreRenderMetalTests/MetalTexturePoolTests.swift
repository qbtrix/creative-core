// MetalTexturePoolTests.swift: freed tile textures are reused. A second copy-and-blank cycle of a frame's
// regions allocates no new texture; a reused tile never shows its old pixels (a blank reads clear, a copy and a
// tone pass read their source); the pool stays inside the budget and drains when residents need the room.
// Skipped without a device.
#if canImport(Metal)
import CoreRaster
import CoreRender
@testable import CoreRenderMetal
import Testing

private let hasDevice = MetalBackend.defaultDevice != nil

@Suite(.serialized) struct MetalTexturePoolTests {
    @Test(.enabled(if: hasDevice)) func aSecondCopyAndBlankCycleAllocatesNoTexture() throws {
        let metal = try MetalBackend.onDefaultDevice()
        let regions = try (0..<4).map { try metal.surface(PixelBuffer.seeded(width: 600, height: 530, seed: UInt64($0))) }
        func cycle() throws {
            let made = try regions.map { try metal.copied($0) } + regions.map { _ in try metal.blank(width: 600, height: 530) }
            made.forEach(metal.release)
        }
        try cycle()
        let first = metal.pooledTextureAllocationCount
        #expect(first > 0)
        try cycle()
        #expect(metal.pooledTextureAllocationCount == first, "the second cycle reuses the first's tiles")
    }

    @Test(.enabled(if: hasDevice)) func aReusedTileNeverShowsItsOldPixels() throws {
        let metal = try MetalBackend.onDefaultDevice()
        let old = try metal.surface(PixelBuffer.seeded(width: 600, height: 530, seed: 0x900D))
        let pixels = try PixelBuffer.seeded(width: 600, height: 530, seed: 0xF00D)
        let source = try metal.surface(pixels)
        metal.release(try metal.copied(old))
        let allocated = metal.pooledTextureAllocationCount
        let blank = try metal.blank(width: 600, height: 530)
        #expect(metal.pooledTextureAllocationCount == allocated, "the blank took the freed copy's tiles")
        #expect(try metal.read(blank) == PixelBuffer(width: 600, height: 530))
        metal.release(blank)
        metal.release(try metal.copied(old))
        let copy = try metal.copied(source)
        #expect(try metal.read(copy) == metal.read(source))
        metal.release(copy)
        metal.release(try metal.copied(old))
        let toned = try metal.adjusted(source, tone: ToneProgram([]))
        #expect(try metal.read(toned) == metal.read(source))
        #expect(metal.pooledTextureAllocationCount == allocated, "every output above reused pooled tiles")
    }

    @Test(.enabled(if: hasDevice)) func thePoolStaysInsideTheBudgetAndDrainsForResidents() throws {
        let metal = try MetalBackend.onDefaultDevice()
        let source = try metal.surface(PixelBuffer(width: 1000, height: 1000, fill: RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1)))
        metal.release(try metal.copied(source))
        #expect(metal.pooledTextureBytes == 1000 * 1000 * MetalSurface.bytesPerPixel)
        metal.budgetBytes = metal.residentBytes + 1
        #expect(metal.pooledTextureBytes == 0, "residents plus the pool went over the budget: the pool drains first")
        #expect(metal.evictedTileCount == 0)
        metal.release(try metal.copied(source))
        #expect(metal.residentBytes + metal.pooledTextureBytes <= metal.budgetBytes, "freed tiles are pooled only into room the budget leaves")
    }
}
#endif
