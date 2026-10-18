// FillFromSurroundings.swift: remove a spot or an object by building it from
// nearby texture, then healing the seam (retouch-heal RH-4). Declared here by
// RH-0 as a stub; RH-4 fills in the body and never changes the signature.

extension PixelBuffer {
    /// The buffer with the pixels `mask` covers rebuilt from patches of
    /// radius `patchRadius` (a `2r + 1` square) found outside the mask, then
    /// healed against the ring around it. The same `seed` gives the same
    /// pixels; an empty mask returns the input. Throws `RasterError.invalid`
    /// when the mask's size differs from the buffer's or `patchRadius` is
    /// below 1.
    public func filledFromSurroundings(_ mask: Mask, seed: UInt64, patchRadius: Int = 3) throws -> PixelBuffer {
        throw RasterError.invalid("filledFromSurroundings is not built yet (retouch-heal RH-4)")
    }
}
