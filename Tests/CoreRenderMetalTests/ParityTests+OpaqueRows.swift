// ParityTests+OpaqueRows.swift: MB-6 enables `ParityTests/opaqueRows` (metal-backend) and owns this file.
// It will compare the `.composite` "opaque-rows" golden band (`ParityGolden.band`, cut at opacity 0.8)
// within that golden's own tolerance; render an opaque `.normal` row at opacity 1 on a live `CPUBackend`
// and compare it with `ParityHarness.compare(_:_:tolerance:)` at `ParityTolerance(bytes: 0, linear: 0)`;
// and show that a row with one 0.999 alpha pixel takes the kernel path.
#if canImport(Metal)
import CoreRenderMetal
import Testing

extension ParityTests {
    @Test(.disabled("waits on MB-6")) func opaqueRows() { #expect(Bool(false), "waits on MB-6") }
}
#endif
