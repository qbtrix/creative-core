// SurfaceStore.swift: the pixels behind one backend's surfaces, keyed by
// RenderSurface id, and `Locked`, the one lock CoreRender's backends share, so the
// non-mutating Sendable protocol can hold PixelBuffers (the fake, the CPU backend).
// Invariants: a surface resolves only when its `backend` is this store's name, its id
// is live and its size matches; else `RenderError.surfaceMismatch`. `remove` ignores
// what it cannot find. The lock is a serial DispatchQueue: Dispatch ships with every
// Swift toolchain, NSLock is not in FoundationEssentials, and Mutex needs macOS 15.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CoreRaster
import Dispatch

/// A value shared by reference and changed only under a lock. Copies of a
/// struct that holds one share the value.
final class Locked<Value>: @unchecked Sendable {
    private let queue = DispatchQueue(label: "CoreRender.Locked")
    private var value: Value

    init(_ value: Value) { self.value = value }

    /// Runs `body` on the value with the lock held. Never call it from `body`.
    func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
        try queue.sync { try body(&value) }
    }
}

/// The PixelBuffers behind the surfaces of the backend named `backend`.
final class SurfaceStore: Sendable {
    /// The backend's name, written into every surface `insert` makes.
    let backend: String
    private let buffers = Locked<[UUID: PixelBuffer]>([:])

    init(backend: String) { self.backend = backend }

    /// Holds `buffer` under a new id and returns its surface.
    func insert(_ buffer: PixelBuffer) -> RenderSurface {
        let surface = RenderSurface(id: UUID(), width: buffer.width, height: buffer.height, backend: backend)
        buffers.withLock { $0[surface.id] = buffer }
        return surface
    }

    /// The pixels behind `surface`. Throws `RenderError.surfaceMismatch` for
    /// another backend's surface, a released or unknown id, or a wrong size.
    func buffer(for surface: RenderSurface) throws -> PixelBuffer {
        try buffers.withLock { try Self.resolve(surface, backend, in: $0) }
    }

    /// Replaces the pixels behind `surface` with `buffer` of the same size, as
    /// an in-place composite does. Throws `surfaceMismatch` as `buffer(for:)`
    /// does, and when `buffer`'s size differs from the surface's.
    func replace(_ surface: RenderSurface, with buffer: PixelBuffer) throws {
        guard buffer.width == surface.width, buffer.height == surface.height else {
            throw RenderError.surfaceMismatch
        }
        try buffers.withLock { stored in
            _ = try Self.resolve(surface, backend, in: stored)
            stored[surface.id] = buffer
        }
    }

    /// Frees the pixels behind `surface`; another backend's surface, or one
    /// already removed, is ignored.
    func remove(_ surface: RenderSurface) {
        guard surface.backend == backend else { return }
        buffers.withLock { _ = $0.removeValue(forKey: surface.id) }
    }

    private static func resolve(_ surface: RenderSurface, _ backend: String,
                                in stored: [UUID: PixelBuffer]) throws -> PixelBuffer {
        guard surface.backend == backend, let buffer = stored[surface.id],
              buffer.width == surface.width, buffer.height == surface.height else {
            throw RenderError.surfaceMismatch
        }
        return buffer
    }
}
