// ParityTests+Composite.swift: MB-4 enables `ParityTests/compositeNormal` (metal-backend) and owns this file.
// It will compare `.normal` at opacities 0, 0.37, 1, sources off every edge and corner, wholly outside,
// and an alpha 1e-45 source, within `.standard`.
#if canImport(Metal)
import CoreRenderMetal
import Testing

extension ParityTests {
    @Test(.disabled("waits on MB-4")) func compositeNormal() { #expect(Bool(false), "waits on MB-4") }
}
#endif
