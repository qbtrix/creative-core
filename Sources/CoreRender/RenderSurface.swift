// RenderSurface.swift: the handle a RenderBackend hands out for an image it
// holds. The pixels live in the backend (a PixelBuffer on the CPU, textures on
// the GPU); the handle carries only the id, the size and the backend's name,
// so it is a small Sendable value any module can pass around.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A backend's handle for one image. Storage lives in the backend; `release`
/// frees it. Two handles with the same fields name the same image.
public struct RenderSurface: Sendable, Equatable, Hashable {
    /// Unique per surface the backend creates.
    public let id: UUID
    /// Pixels across.
    public let width: Int
    /// Pixels down.
    public let height: Int
    /// The `name` of the backend that made it, so a backend can tell its own
    /// surfaces from another's and throw `RenderError.surfaceMismatch`.
    public let backend: String

    /// A handle for the surface `backend` holds under `id`, `width` x
    /// `height` pixels. Backends construct it; callers only pass it on.
    public init(id: UUID, width: Int, height: Int, backend: String) {
        self.id = id
        self.width = width
        self.height = height
        self.backend = backend
    }
}
