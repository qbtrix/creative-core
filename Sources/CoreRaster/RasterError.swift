// RasterError.swift: the one error type of CoreRaster, the shared raster
// module (pixel buffers, compositing, image operations). CoreRaster is
// Linux-safe, Foundation only, and depends only on CoreColor. Every throwing
// API in this module throws this.
public enum RasterError: Error, Equatable, Sendable {
    /// A size, index or parameter is out of range, or a buffer is too large.
    case invalid(String)
}
