// ParityTests+OpaqueRows.swift: MB-6 enables `ParityTests/opaqueRows` (metal-backend) and owns this file.
// It will compare an opaque `.normal` row at opacity 1 to the golden with zero delta, and show that a row
// with one 0.999 alpha pixel takes the kernel path.
#if canImport(Metal)
import CoreRenderMetal
import Testing

extension ParityTests {
    @Test(.disabled("waits on MB-6")) func opaqueRows() { #expect(Bool(false), "waits on MB-6") }
}
#endif
