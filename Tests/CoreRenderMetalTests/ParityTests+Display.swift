// ParityTests+Display.swift: MB-3 enables `ParityTests/display` (metal-backend) and owns this file. It will
// compare the display golden set in sRGB and P3 within 2/255; every byte value per channel round-trips.
#if canImport(Metal)
import CoreRenderMetal
import Testing

extension ParityTests {
    @Test(.disabled("waits on MB-3")) func display() { #expect(Bool(false), "waits on MB-3") }
}
#endif
