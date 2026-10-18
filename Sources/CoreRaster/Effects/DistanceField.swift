// DistanceField.swift: the exact Euclidean distance, in pixels, from each
// pixel to the alpha >= level set (outside) and to its complement (inside).
// A stub until effects-engine task FX-5 fills it: the initializer throws
// `RasterError.invalid("not built")` and both lookups return 0.

/// Distances from a buffer's alpha edge, in pixels. Not built yet.
public struct DistanceField: Sendable {
    public let width: Int, height: Int

    /// The field of `buffer`'s alpha at `level`. Not built yet: throws.
    public init(alpha buffer: PixelBuffer, level: Float = 0.5) throws {
        throw RasterError.invalid("not built")
    }

    /// Distance from (x, y) to the nearest pixel inside the shape. Not built yet: 0.
    public func outside(x: Int, y: Int) -> Float { 0 }

    /// Distance from (x, y) to the nearest pixel outside the shape. Not built yet: 0.
    public func inside(x: Int, y: Int) -> Float { 0 }
}
