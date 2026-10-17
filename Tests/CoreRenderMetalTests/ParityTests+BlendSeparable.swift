// ParityTests+BlendSeparable.swift: MB-5 enables `ParityTests/blendSeparable` (metal-backend) and owns this
// file. It will compare the twelve separable modes at three opacities within `.standard`.
#if canImport(Metal)
import CoreRenderMetal
import Testing

extension ParityTests {
    @Test(.disabled("waits on MB-5")) func blendSeparable() { #expect(Bool(false), "waits on MB-5") }
}
#endif
