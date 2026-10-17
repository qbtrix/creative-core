// ParityTolerance.swift: how far two backends' results may differ and still
// count as the same image. Goldens store the one they were cut with.

/// The largest difference `ParityHarness.compare` accepts between two results.
public struct ParityTolerance: Codable, Equatable, Hashable, Sendable {
    /// Largest per-channel difference of the 8-bit sRGB display bytes.
    public let bytes: UInt8
    /// Largest per-component difference of the linear premultiplied buffers,
    /// over pixels whose alpha is above 0.01 in either result.
    public let linear: Float

    /// A tolerance of `bytes` display levels and `linear` per component.
    public init(bytes: UInt8, linear: Float) { (self.bytes, self.linear) = (bytes, linear) }

    /// Separable ops: 2 display levels, 1e-3 linear.
    public static let standard = ParityTolerance(bytes: 2, linear: 1e-3)
    /// Non-separable blends, whose clip-to-gamut step amplifies rounding.
    public static let nonSeparable = ParityTolerance(bytes: 4, linear: 4e-3)
}
