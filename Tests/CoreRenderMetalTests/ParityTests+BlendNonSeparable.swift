// ParityTests+BlendNonSeparable.swift: MB-9 enables `ParityTests/blendNonSeparable` (metal-backend) and owns
// this file. It will compare hue, saturation, color and luminosity within `.nonSeparable` on the seeded set.
#if canImport(Metal)
import CoreRenderMetal
import Testing

extension ParityTests {
    @Test(.disabled("waits on MB-9")) func blendNonSeparable() { #expect(Bool(false), "waits on MB-9") }
}
#endif
