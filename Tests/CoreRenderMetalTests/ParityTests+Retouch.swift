// ParityTests+Retouch.swift: MB-15 enables `ParityTests/retouch` (metal-backend) and owns this file. It will
// compare clone with offsets off the edge through rect, ellipse and polygon masks within `.standard`.
#if canImport(Metal)
import CoreRenderMetal
import Testing

extension ParityTests {
    @Test(.disabled("waits on MB-15")) func retouch() { #expect(Bool(false), "waits on MB-15") }
}
#endif
