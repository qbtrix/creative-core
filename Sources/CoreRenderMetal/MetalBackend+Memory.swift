// MetalBackend+Memory.swift: the memory budget (MB-16). After every upload and budget change, tiles
// leave the GPU for their CPU shadows, least recently used first, until `residentBytes` is at or under
// `budgetBytes`. Invariants: pixels survive eviction (`read` merges resident tiles and shadows); the victim
// order is `lastUse`, the surface's `created` clock, then the tile index; a failed eviction marks the
// backend failed and stops, it never throws out of an upload.
#if canImport(Metal)
import CoreRender

extension MetalBackend {
    /// Tiles held in their CPU shadow with no texture, summed over the live surfaces.
    public var evictedTileCount: Int { withLock { surfaces.values.reduce(0) { $0 + $1.evictedTileCount } } }

    /// Evicts least recently used tiles to their shadows until `residentBytes` is at or under
    /// `budgetBytes` or no resident tile is left. Takes the lock itself: call it with the lock free.
    /// An eviction that fails (a download with a non-finite component) marks the backend failed with
    /// "eviction: <reason>" and stops; nothing is thrown and every surface stays readable.
    func evictIfNeeded() {
        let failure: String? = withLock {
            while residentBytesLocked > budget {
                guard let victim = leastRecentlyUsedTile() else { return nil }
                do { try victim.surface.evict(tile: victim.index, queue: commandQueue) } catch { return "eviction: \(error)" }
            }
            return nil
        }
        if let failure { fail(failure) }
    }

    /// The resident tile with the smallest `lastUse`, ties to the older surface then the lower
    /// index; nil when no tile is resident. Call with the lock held.
    private func leastRecentlyUsedTile() -> (surface: MetalSurface, index: Int)? {
        // `residentTileIndices` index `tiles`, which has as many entries as `lastUse`.
        let resident = surfaces.values.flatMap { surface in
            surface.residentTileIndices.map { (surface: surface, index: $0, key: (surface.lastUse[$0], surface.created, $0)) }
        }
        return resident.min { $0.key < $1.key }.map { (surface: $0.surface, index: $0.index) }
    }
}
#endif
