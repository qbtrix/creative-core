// CPUBackend+Style.swift: the CPU backend's `.style` family, a
// `LayerStyleStack` drawn on a layer: CoreRaster's `styled(_:)` on `s`'s
// pixels, the whole stack (entries, modes, opacities and fill opacity) passed
// through, so the result equals the direct call with `==`. No style is
// computed here.
// Invariants: `s` is read under the `.style` gate and left unchanged
// (`derived`); a surface this backend cannot resolve throws
// `surfaceMismatch`; a CoreRaster error comes back as `RenderError.raster`.
import CoreRaster

extension CPUBackend {
    public func styled(_ s: RenderSurface, _ stack: LayerStyleStack) throws -> RenderSurface {
        try derived(s, .style) { try $0.styled(stack) }
    }
}
