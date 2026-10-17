// ParityTests+Unsharp.swift: MB-12 enables `ParityTests/unsharp` (metal-backend) and owns this file. It will
// compare the unsharp mask over an amount, sigma, threshold grid within `.standard`.
#if canImport(Metal)
import CoreRenderMetal
import Testing

extension ParityTests {
    @Test(.disabled("waits on MB-12")) func unsharp() { #expect(Bool(false), "waits on MB-12") }
}
#endif
