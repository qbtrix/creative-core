// ParityTests+Transform.swift: MB-7 enables `ParityTests/transform` (metal-backend) and owns this file.
// It will compare crop at every corner and the three quarter turns with zero delta (exact copies).
#if canImport(Metal)
import CoreRenderMetal
import Testing

extension ParityTests {
    @Test(.disabled("waits on MB-7")) func transform() { #expect(Bool(false), "waits on MB-7") }
}
#endif
