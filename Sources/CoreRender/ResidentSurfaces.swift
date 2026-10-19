// ResidentSurfaces.swift: layer tiles kept on a backend between renders, keyed
// by layer id and tile index, so a frame uploads only the tiles whose pixels
// changed. Each entry keeps the CPU `PixelBuffer` it uploaded: a tile the app
// has not written since shares that buffer's storage, so the dirty check is
// storage identity (`sharesStorage`, constant time), and a written tile
// (copy-on-write gave it new storage) uploads with no pixel compare. Equal
// pixels in new storage upload again: wasted work, never a wrong picture. A
// tile whose components are all 0 keeps no surface (nil): there is nothing to
// composite. The kept buffers are also what `rebuild(on:)` uploads after a
// device loss, so the app never has to resend them. Any backend works; on the
// CPU an upload is a store insert. Invariants: `uploads` counts every
// surface made (sync and rebuild), never a clear tile; a replaced or pruned
// entry's surface is released on the backend that made it; two syncs of one
// key racing keep one surface and release the other. A surface handed out
// stays valid until its key is synced with other pixels, pruned or rebuilt,
// so prune and rebuild between renders, not during one. Linux-safe.
import CoreRaster

/// One layer tile: the layer's id and the tile's index in its grid.
public struct ResidentKey: Hashable, Sendable {
    public let layer: String
    public let tile: Int

    public init(layer: String, tile: Int) {
        (self.layer, self.tile) = (layer, tile)
    }
}

/// Layer tiles held on one backend across renders, uploaded only when their pixels change.
public final class ResidentSurfaces: Sendable {
    private struct Entry {
        let pixels: PixelBuffer
        /// Nil for a clear tile.
        let surface: RenderSurface?
    }

    private struct State {
        var backend: any RenderBackend
        var entries: [ResidentKey: Entry] = [:]
        var uploads = 0
    }

    private let state: Locked<State>

    /// An empty set of tiles on `backend`.
    public init(backend: any RenderBackend) {
        state = Locked(State(backend: backend))
    }

    /// The backend the tiles live on; `rebuild(on:)` moves them.
    public var backend: any RenderBackend { state.withLock { $0.backend } }
    /// Surfaces made so far, by `surface(_:pixels:)` and `rebuild(on:)`.
    public var uploads: Int { state.withLock { $0.uploads } }
    /// Tiles held, clear ones included.
    public var count: Int { state.withLock { $0.entries.count } }

    /// The surface holding `pixels` for `key`, nil when every component of
    /// `pixels` is 0. The held one when its pixels share `pixels`' storage, else
    /// `pixels` uploaded now (the old surface released). Throws what the
    /// backend's `surface(_:)` throws, leaving the old entry in place.
    public func surface(_ key: ResidentKey, pixels: PixelBuffer) throws -> RenderSurface? {
        let (backend, held) = state.withLock { ($0.backend, $0.entries[key]) }
        if let held, held.pixels.sharesStorage(with: pixels) { return held.surface }
        let made = pixels.components.allSatisfy { $0 == 0 } ? nil : try backend.surface(pixels)
        return state.withLock { state -> RenderSurface? in
            if let raced = state.entries[key], raced.pixels.sharesStorage(with: pixels), state.backend.name == backend.name {
                if let made { backend.release(made) }
                return raced.surface
            }
            if let old = state.entries[key]?.surface { state.backend.release(old) }
            state.entries[key] = Entry(pixels: pixels, surface: made)
            if made != nil { state.uploads += 1 }
            return made
        }
    }

    /// Drops every tile of a layer not in `layers`, releasing its surfaces.
    public func prune(keeping layers: Set<String>) {
        state.withLock { state in
            for (key, entry) in state.entries where !layers.contains(key.layer) {
                if let surface = entry.surface { state.backend.release(surface) }
                state.entries[key] = nil
            }
        }
    }

    /// Drops every tile, releasing its surfaces.
    public func removeAll() { prune(keeping: []) }

    /// Uploads every held tile's pixels to `backend` (a recovered backend, or
    /// a new one on a new device after a loss) and moves the set there; the
    /// old surfaces are released on the old backend. On a throw nothing moves:
    /// the surfaces made so far are released and the old backend is kept.
    public func rebuild(on backend: any RenderBackend) throws {
        let (old, entries) = state.withLock { ($0.backend, $0.entries) }
        var rebuilt: [ResidentKey: Entry] = [:]
        do {
            for (key, entry) in entries {
                rebuilt[key] = Entry(pixels: entry.pixels, surface: try entry.surface.map { _ in try backend.surface(entry.pixels) })
            }
        } catch {
            for surface in rebuilt.values.compactMap(\.surface) { backend.release(surface) }
            throw error
        }
        state.withLock { state in
            state.backend = backend
            state.entries = rebuilt
            state.uploads += rebuilt.values.filter { $0.surface != nil }.count
        }
        for surface in entries.values.compactMap(\.surface) { old.release(surface) }
    }
}
