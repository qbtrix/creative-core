// MetalTilingTests.swift: tile eviction under `budgetBytes` on a real device (MB-16): the LRU tiles leave
// the GPU for their shadows, `read` still matches the upload, reads count as use, releasing an evicted
// surface drops its shadows. Device-gated; compiled out on Linux.
#if canImport(Metal)
import CoreRaster
import CoreRender
import CoreRenderMetal
import Testing

@Suite struct MetalTilingTests {
    /// One full 256 x 256 rgba16Float tile.
    private static let tileBytes = 256 * 256 * 8
    /// A 600 x 600 surface: 4 full tiles, 4 edge tiles of 256 x 88 or 88 x 256, one 88 x 88 corner.
    private static let surfaceBytes = 600 * 600 * 8

    private static func buffer(seed: UInt64) throws -> PixelBuffer { try .seeded(width: 600, height: 600, seed: seed) }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func evictionKeepsUnderTheBudgetAndKeepsPixels() throws {
        let backend = try MetalBackend.onDefaultDevice()
        #expect(backend.budgetBytes >= Self.tileBytes, "the default budget holds at least one tile")
        backend.budgetBytes = 3 * Self.tileBytes
        let buffer = try Self.buffer(seed: 16)
        let surface = try backend.surface(buffer)
        // Index order on equal `lastUse`: tiles 0, 1 (full), 2 (88 x 256) and 3 (full) go, 1,753,088
        // bytes, and the remaining 1,126,912 (one full tile, three edge tiles, the corner) fit.
        #expect(backend.evictedTileCount == 4)
        #expect(backend.residentBytes == Self.surfaceBytes - 3 * Self.tileBytes - 256 * 88 * 8)
        #expect(try backend.worstDelta(reading: surface, against: buffer) <= 1e-3, "eviction keeps pixels")
        backend.budgetBytes = 0
        #expect(backend.evictedTileCount == 9 && backend.residentBytes == 0, "lowering the budget evicts at once")
        #expect(try backend.worstDelta(reading: surface, against: buffer) <= 1e-3, "a surface wholly in shadow reads")
        backend.release(surface)
        #expect(backend.evictedTileCount == 0 && backend.residentBytes == 0)
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func oldestSurfaceIsEvictedFirstAndReleaseDropsItsShadows() throws {
        let backend = try MetalBackend.onDefaultDevice()
        backend.budgetBytes = 2 * Self.surfaceBytes
        let first = try Self.buffer(seed: 17)
        let a = try backend.surface(first)
        let b = try backend.surface(Self.buffer(seed: 18))
        #expect(backend.evictedTileCount == 0, "two surfaces fill the budget exactly")
        _ = try backend.surface(Self.buffer(seed: 19))
        #expect(backend.evictedTileCount == 9 && backend.residentBytes == backend.budgetBytes)
        #expect(try backend.worstDelta(reading: a, against: first) <= 1e-3, "the evicted surface still reads")
        backend.release(a)
        #expect(backend.evictedTileCount == 0, "every evicted tile was the first surface's")
        #expect(backend.residentBytes == backend.budgetBytes, "releasing shadows frees no texture bytes")
        backend.release(b)
        #expect(backend.residentBytes == Self.surfaceBytes)
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func readingASurfaceMarksItUsed() throws {
        let backend = try MetalBackend.onDefaultDevice()
        backend.budgetBytes = 2 * Self.surfaceBytes
        let a = try backend.surface(Self.buffer(seed: 20))
        let b = try backend.surface(Self.buffer(seed: 21))
        _ = try backend.read(a)
        _ = try backend.surface(Self.buffer(seed: 22))
        #expect(backend.evictedTileCount == 9)
        backend.release(b)
        #expect(backend.evictedTileCount == 0, "the unread surface went before the one read after it")
    }
}
#endif
