// MetalTexturePool.swift: freed tile textures kept for reuse, so a frame that copies, clears and tones its
// regions stops allocating and freeing hundreds of tile textures. `MetalBackend.release` puts a surface's
// resident tiles here; surfaces the GPU fills whole (blank, copy, tone, crop, rotate) take them back by size
// and pixel format. Invariants: a tile is reused only by those no-fill surfaces, never by a CPU upload, so
// no CPU write races GPU work still queued on it, and since every reuser writes every pixel on the GPU no old
// pixel shows; the GPU orders that write after earlier work on the tile because both run on the backend's one
// queue (a caller releases a surface only once no call on it is in flight). The pool holds at most `capBytes`
// and only room the backend's budget leaves (`room`); the backend drains it before evicting resident tiles.
#if canImport(Metal)
import CoreRender
import Foundation
import Metal

/// Freed tile textures by size and pixel format, for no-fill surfaces. Its own lock: callers hold the
/// backend's lock or not.
final class TexturePool: @unchecked Sendable {
    /// The most texture bytes the pool holds, whatever the budget leaves: a 24 MP frame's regions fit twice.
    static let capBytes = 512 << 20

    private struct Key: Hashable {
        let width: Int, height: Int, format: MTLPixelFormat
    }

    private let lock = NSLock()
    private var free: [Key: [any MTLTexture]] = [:]
    private var held = 0
    private var allocations = 0

    /// A `width` x `height` rgba16Float tile texture: a pooled one when one of that size is held, else new.
    /// Its pixels are undefined. Throws `RenderError.deviceLost` when the device gives none.
    func texture(width: Int, height: Int, device: any MTLDevice) throws -> any MTLTexture {
        let reused = lock.withLock { () -> (any MTLTexture)? in
            guard let texture = free[Key(width: width, height: height, format: .rgba16Float)]?.popLast() else { return nil }
            held -= Self.bytes(texture)
            return texture
        }
        if let reused { return reused }
        let texture = try MetalSurface.makeTexture(width: width, height: height, device: device)
        lock.withLock { allocations += 1 }
        return texture
    }

    /// Keeps each of a freed surface's tiles while the pool stays within `capBytes` and `room`, the bytes the
    /// backend's budget leaves free; the rest are dropped (freed).
    func put(_ textures: [any MTLTexture], room: Int) {
        lock.withLock {
            for texture in textures where held + Self.bytes(texture) <= min(Self.capBytes, room) {
                free[Key(width: texture.width, height: texture.height, format: texture.pixelFormat), default: []].append(texture)
                held += Self.bytes(texture)
            }
        }
    }

    /// Frees every held texture.
    func drain() { lock.withLock { (free, held) = ([:], 0) } }

    /// Textures `texture` allocated new.
    var allocationCount: Int { lock.withLock { allocations } }
    /// Bytes of textures held for reuse.
    var bytes: Int { lock.withLock { held } }

    private static func bytes(_ texture: any MTLTexture) -> Int { texture.width * texture.height * MetalSurface.bytesPerPixel }
}
#endif
