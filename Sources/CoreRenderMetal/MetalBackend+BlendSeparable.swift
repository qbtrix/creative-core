// MetalBackend+BlendSeparable.swift: the separable blend modes (MB-5) as variants of the in-place composite
// (MetalBackend+Composite.swift): the same checks, CompositeMap pieces, tile restores and encode, with the
// kernel picked by mode. Invariants: `.normal` keeps `composite_normal`; a non-separable mode runs its
// `blendNonSeparable_<mode>` kernel (MB-9, MetalBackend+BlendNonSeparable.swift); the family gate is `supported`, and `.blendSeparable`
// is not enabled at init (MB-6 enables it after the opaque-row path), so until then only the parity hook
// turns it on, and only on a read-write tier 2 device.
#if canImport(Metal)
import CoreRaster
import CoreRender
import Metal

extension MetalBackend {
    /// The in-place kernel's key and MSL for `mode`: `composite_normal` for `.normal`, `blendSeparable_<mode>`
    /// for the other separable modes, `blendNonSeparable_<mode>` for hue, saturation, color and luminosity.
    static func compositeKernel(for mode: BlendMode) throws -> (key: PipelineKey, source: String) {
        switch RenderOp(compositing: mode) {
        case .composite: return (CompositeShader.key, CompositeShader.source)
        case .blendSeparable: return (BlendSeparableShader.key(mode), BlendSeparableShader.source)
        case .blendNonSeparable: return (BlendNonSeparableShader.key(mode), BlendNonSeparableShader.source)
        default: throw RenderError.unsupported(RenderOp(compositing: mode))
        }
    }

    /// Turns `.blendSeparable` on for the parity suite before MB-6 enables it at init; false (and nothing
    /// changes) on a device without read-write texture tier 2, where the kernels cannot write in place.
    package func enableSeparableBlendsForParity() -> Bool {
        guard Self.compositesInPlace(on: device) else { return false }
        withCapabilities { $0.enable(.blendSeparable) }
        return true
    }
}
#endif
