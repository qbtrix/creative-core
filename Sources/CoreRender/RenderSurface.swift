// RenderSurface.swift: a handle to pixels a backend holds. The storage is the
// backend's: a CPU surface is a PixelBuffer, a Metal surface is a texture. The
// handle carries only what every caller may read: an identity, a size and the
// name of the backend that owns it.

import Foundation

/// A pixel surface owned by one backend. Two surfaces are equal when they are
/// the same surface, which is what the dispatcher uses to spot a surface that
/// belongs to the other backend.
public struct RenderSurface: Sendable, Equatable {
    public let id: UUID
    public let width: Int
    public let height: Int
    /// The `RenderBackend.name` of the backend that holds the pixels.
    public let backend: String

    public init(id: UUID, width: Int, height: Int, backend: String) {
        self.id = id
        self.width = width
        self.height = height
        self.backend = backend
    }
}
