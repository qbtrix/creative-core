// Smudge.swift: the smudge brush's state, a carried colour dragged along
// successive dabs that fades by strength (retouch-heal RH-6). Declared here
// by RH-0 as a stub; RH-6 fills in the body and never changes the signature.

/// A smudge stroke in progress: the patch each dab carries to the next.
public struct SmudgeState: Sendable {
    private let strength: Float

    /// A new stroke. `strength` is in 0...1: how much of the carried colour
    /// each dab lays down; 0 changes nothing.
    public init(strength: Float) {
        self.strength = strength
    }

    /// Blends the carried patch onto `buffer` under `dab` (its top-left at
    /// `x`, `y`) by strength times coverage, then picks up what is now under
    /// the dab. The first dab of a stroke only picks up. Throws
    /// `RasterError.invalid` for a strength outside 0...1 or NaN.
    public mutating func dab(_ dab: Mask, x: Int, y: Int, on buffer: inout PixelBuffer) throws {
        throw RasterError.invalid("dab is not built yet (retouch-heal RH-6)")
    }
}
