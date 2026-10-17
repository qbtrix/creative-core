// ParityTests+Resample.swift: MB-8 enables `ParityTests/resample` (metal-backend) and owns this file. It will
// compare both filters up and down at 5 sizes within `.standard`, and show that a constant image stays constant.
#if canImport(Metal)
import CoreRenderMetal
import Testing

extension ParityTests {
    @Test(.disabled("waits on MB-8")) func resample() { #expect(Bool(false), "waits on MB-8") }
}
#endif
