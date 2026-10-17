// MetalBackend+BlendNonSeparable.swift: the non-separable blend modes (MB-9, MB-10) as variants of the in-place
// composite (MetalBackend+Composite.swift), routed by `compositeKernel(for:)` (MetalBackend+BlendSeparable.swift)
// to one `blendNonSeparable_<mode>` kernel each (Shaders/BlendNonSeparableShader.swift). Invariants: the family
// gate is `supported`, and `MetalBackend.init` enables `.blendNonSeparable` (MB-10, after the clip-colour edge
// cases) only on a read-write tier 2 device, beside `.composite` and `.blendSeparable`; elsewhere, and while
// unhealthy, `composite` throws `unsupported(.blendNonSeparable)` for hue, saturation, color and luminosity.
// The MB-9 parity hook is retired: the family needs no code beyond the shared composite path.
#if canImport(Metal)
#endif
