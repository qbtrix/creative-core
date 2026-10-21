// MetalBackend+BlendSeparable.swift: the separable blend modes (MB-5) as variants of the in-place composite
// (MetalBackend+Composite.swift): the same checks, CompositeMap pieces, tile restores and encode, with the
// kernel picked by mode. Invariants: `.normal` keeps `composite_normal`; a non-separable mode runs its
// `blendNonSeparable_<mode>` kernel (MB-9, Shaders/BlendNonSeparableShader.swift); the family gate is `supported`,
// and `MetalBackend.init` enables `.blendSeparable` (MB-6) and `.blendNonSeparable` (MB-10) only on a read-write
// tier 2 device, beside `.composite`; elsewhere, and while unhealthy, `composite` throws `unsupported(<family>)`.
#if canImport(Metal)
import CoreRaster
import CoreRender
import Metal

extension MetalBackend {
    /// The in-place kernel's key and MSL for `mode`: `composite_normal` for `.normal`, `blendSeparable_<mode>`
    /// for the other separable modes (linear dodge and burn among them, LE-7), `blendNonSeparable_<mode>` for hue,
    /// saturation, color and luminosity. A mode whose family has no kernel for it throws `unsupported`.
    static func compositeKernel(for mode: BlendMode) throws -> (key: PipelineKey, source: String) {
        switch RenderOp(compositing: mode) {
        case .composite: return (CompositeShader.key, CompositeShader.source)
        case .blendSeparable where BlendSeparableShader.modes.contains(mode):
            return (BlendSeparableShader.key(mode), BlendSeparableShader.source)
        case .blendNonSeparable: return (BlendNonSeparableShader.key(mode), BlendNonSeparableShader.source)
        default: throw RenderError.unsupported(RenderOp(compositing: mode))
        }
    }
}
#endif
