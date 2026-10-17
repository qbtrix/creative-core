// CPUSurface.swift: where the CPU backend keeps its pixels. A RenderSurface
// handle holds no pixels; the store maps its id to one PixelBuffer. A lock
// guards every access, so one backend can be shared across threads.

import CoreRaster
import Foundation

/// The CPU backend's pixel storage, keyed by surface id.
final class CPUSurfaceStore: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [UUID: PixelBuffer] = [:]

    func insert(_ buffer: PixelBuffer, id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        buffers[id] = buffer
    }

    func buffer(for surface: RenderSurface) throws -> PixelBuffer {
        lock.lock()
        defer { lock.unlock() }
        return try fetch(surface)
    }

    func release(_ surface: RenderSurface) {
        lock.lock()
        defer { lock.unlock() }
        buffers[surface.id] = nil
    }

    /// Composites `source` onto `backdrop` in place. The backdrop is taken out
    /// of the store while it is written, so its storage is not copied.
    func composite(_ source: RenderSurface, onto backdrop: RenderSurface,
                   x: Int, y: Int, mode: BlendMode, opacity: Float) throws {
        lock.lock()
        defer { lock.unlock() }
        let top = try fetch(source)
        guard backdrop.backend == CPUBackend.backendName,
              var target = buffers.removeValue(forKey: backdrop.id) else {
            throw RenderError.surfaceMismatch
        }
        defer { buffers[backdrop.id] = target }
        try raster { try target.composite(top, x: x, y: y, mode: mode, opacity: opacity) }
    }

    /// Looks a surface up. The caller holds `lock`.
    private func fetch(_ surface: RenderSurface) throws -> PixelBuffer {
        guard surface.backend == CPUBackend.backendName, let buffer = buffers[surface.id] else {
            throw RenderError.surfaceMismatch
        }
        return buffer
    }
}

/// Runs a CoreRaster call and turns its error into `RenderError.raster`, so no
/// CoreRaster error type crosses the backend boundary.
func raster<T>(_ body: () throws -> T) throws -> T {
    do {
        return try body()
    } catch let RasterError.invalid(message) {
        throw RenderError.raster(message)
    }
}
