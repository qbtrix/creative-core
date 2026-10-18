// CPUBackend+MaskedComposite.swift: the CPU backend's `.maskedComposite`
// family, a composite whose coverage is scaled by a mask. A stub until the
// masks-mattes feature fills this file: it checks the backdrop, then `s`
// under the family's gate (`notBuilt`), and throws
// `RenderError.unsupported(.maskedComposite)`.
// Invariants: `b` is left unchanged; a surface this backend cannot resolve
// throws `surfaceMismatch` first.
import CoreRaster

extension CPUBackend {
    public func composite(_ s: RenderSurface, onto b: inout RenderSurface, x: Int, y: Int, mode: BlendMode,
                          opacity: Float, mask: Mask, maskX: Int, maskY: Int) throws {
        _ = try read(b)
        _ = try notBuilt(s, .maskedComposite)
    }
}
