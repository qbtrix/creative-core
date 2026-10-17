// ParityTests+Adjust.swift: MB-13 enables `ParityTests/adjust` (metal-backend) and owns this file. It will
// compare exposure, levels and curves within `.standard`, in linear and sRGB encodings.
#if canImport(Metal)
import CoreRenderMetal
import Testing

extension ParityTests {
    @Test(.disabled("waits on MB-13")) func adjust() { #expect(Bool(false), "waits on MB-13") }
}
#endif
