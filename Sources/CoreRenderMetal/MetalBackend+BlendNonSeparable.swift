// MetalBackend+BlendNonSeparable.swift: the non-separable blend modes (MB-9) as variants of the in-place
// composite (MetalBackend+Composite.swift), routed by `compositeKernel(for:)` (MetalBackend+BlendSeparable.swift)
// to one `blendNonSeparable_<mode>` kernel each (Shaders/BlendNonSeparableShader.swift). Invariants: the family
// gate is `supported`, and `.blendNonSeparable` is not enabled at init (MB-10 enables it after the clip-colour
// edge cases), so until then only the parity hook turns it on, and only on a read-write tier 2 device; the
// public `composite` still throws `unsupported(.blendNonSeparable)` for these modes.
#if canImport(Metal)
import CoreRaster
import CoreRender
import Metal

extension MetalBackend {
    /// The in-place kernel's key and MSL for a non-separable `mode`: `blendNonSeparable_<mode>`.
    static func nonSeparableKernel(for mode: BlendMode) -> (key: PipelineKey, source: String) {
        (BlendNonSeparableShader.key(mode), BlendNonSeparableShader.source)
    }

    /// Turns `.blendNonSeparable` on for the parity suite before MB-10 enables it at init; false (and nothing
    /// changes) on a device without read-write texture tier 2, where the kernels cannot write in place.
    package func enableNonSeparableBlendsForParity() -> Bool {
        guard Self.compositesInPlace(on: device) else { return false }
        withCapabilities { $0.enable(.blendNonSeparable) }
        return true
    }
}
#endif
