// MetalTexturePool.swift: tile textures for surfaces the GPU fills whole (blank, copy, tone, crop, rotate),
// counted so tests can see how many new textures a frame allocates.
#if canImport(Metal)
import CoreRender
import Foundation
import Metal

/// Tile textures for no-fill surfaces. Its own lock: callers hold the backend's lock or not.
final class TexturePool: @unchecked Sendable {
    private let lock = NSLock()
    private var allocations = 0

    /// A `width` x `height` tile texture, newly allocated. Throws `RenderError.deviceLost` when the device gives none.
    func texture(width: Int, height: Int, device: any MTLDevice) throws -> any MTLTexture {
        let texture = try MetalSurface.makeTexture(width: width, height: height, device: device)
        lock.withLock { allocations += 1 }
        return texture
    }

    /// Takes back a freed surface's tiles; `room` is the bytes the backend's budget leaves free.
    func put(_ textures: [any MTLTexture], room: Int) {}

    /// Frees every held texture.
    func drain() {}

    /// Textures `texture` allocated.
    var allocationCount: Int { lock.withLock { allocations } }
    /// Bytes of textures held for reuse.
    var bytes: Int { 0 }
}
#endif
