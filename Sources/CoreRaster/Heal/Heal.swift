// Heal.swift: the true heal behind Photo's heal, spot heal and patch tools
// (retouch-heal RH-3, Photo blueprint CR-7). Texture from the buffer shifted
// by an offset is cloned through a mask and its colour solved so it meets the
// destination's edge with no seam (gradient-domain editing). Declared here by
// RH-0 as a stub; RH-3 fills in the body and never changes the signature.

extension PixelBuffer {
    /// The most pixels a heal's mask may cover; a mask covering more throws.
    public static let maxHealPixels = 4_000_000

    /// The buffer with the source (itself shifted by `offset`) cloned through
    /// `mask` and its colour solved to match the destination along the mask's
    /// edge. Only pixels inside the mask's bounds change. The mask must match
    /// the buffer's size and cover at most `maxHealPixels`; otherwise, or for
    /// an offset whose source lies off the buffer, it throws
    /// `RasterError.invalid`.
    public func healed(offset: (dx: Int, dy: Int), through mask: Mask) throws -> PixelBuffer {
        throw RasterError.invalid("healed is not built yet (retouch-heal RH-3)")
    }
}
