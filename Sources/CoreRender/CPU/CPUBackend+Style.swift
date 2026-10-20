// CPUBackend+Style.swift: the CPU backend's `.style` family, a
// `LayerStyleStack` drawn on a layer. A stub until layer-style-engine LE-5
// fills this file: it checks `s` under the family's gate (`notBuilt`) and
// throws `RenderError.unsupported(.style)`.
// Invariants: `s` is left unchanged; a surface this backend cannot resolve
// throws `surfaceMismatch` first.
import CoreRaster

extension CPUBackend {
    public func styled(_ s: RenderSurface, _ stack: LayerStyleStack) throws -> RenderSurface {
        try notBuilt(s, .style)
    }
}
