// MetalSurface+Eviction.swift: moving a tile from its texture to its CPU shadow (MB-16), keeping
// MetalSurface.swift's invariants: a tile is resident or shadowed, never neither, and `residentBytes`
// counts resident tiles only. The backend calls these with its lock held. The first slice that needs an
// evicted tile's texture back adds the reverse move (shadow to a new texture, `lastUse` stamped) beside `evict`.
#if canImport(Metal)
import CoreRaster
import CoreRender
import Metal

extension MetalSurface {
    /// The indices of the tiles whose texture is resident, ascending.
    var residentTileIndices: [Int] { tiles.indices.filter { tiles[$0] != nil } }

    /// How many tiles live in their shadow with no texture.
    var evictedTileCount: Int { tiles.reduce(0) { $0 + ($1 == nil ? 1 : 0) } }

    /// Stamps every tile's `lastUse` with `clock`: a read uses the whole surface.
    func touch(_ clock: UInt64) {
        for index in lastUse.indices { lastUse[index] = clock }
    }

    /// Moves tile `index` to a new tile-sized `PixelBuffer` shadow, drops its texture and takes its
    /// bytes off `residentBytes`; a tile already evicted is a no-op. Throws `RenderError.raster` for
    /// an index outside `0..<tiling.tileCount` or a download with a non-finite component (see `read`).
    func evict(tile index: Int) throws {
        let rect = try tiling.rect(index)  // throws outside the tiling, so the subscripts are in range
        guard let texture = tiles[index] else { return }
        shadows[index] = try Self.download(texture, rect: rect, index: index)
        tiles[index] = nil
        residentBytes -= Self.bytes(of: rect)
    }
}
#endif
