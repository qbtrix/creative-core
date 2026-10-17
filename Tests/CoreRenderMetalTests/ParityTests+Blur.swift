// ParityTests+Blur.swift: MB-11 enables `ParityTests/blur` (metal-backend) and owns this file. It will
// compare gaussian blur at sigma 0, 0.5, 3, 20 within `.standard`, with clamp-to-edge at the borders.
#if canImport(Metal)
import CoreRenderMetal
import Testing

extension ParityTests {
    @Test(.disabled("waits on MB-11")) func blur() { #expect(Bool(false), "waits on MB-11") }
}
#endif
