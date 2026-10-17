// ParityTests.swift: the parity suite scaffold (metal-backend MB-2): one disabled test per op
// family, each turned on by the slice that lands the family (MB-3 to MB-15). `ParityHarness`
// (render-backend RB-6: sample sets, `compare` within a `ParityTolerance`, golden read and
// write) and the CPU goldens (RB-7) plug in here when they exist; until then each body fails
// on purpose, so a family enabled by mistake fails loudly instead of passing empty. Every real
// parity test is also `.enabled(if: MetalBackend.defaultDevice != nil)`: a runner without a
// GPU skips it. Compiled out on Linux.
#if canImport(Metal)
import CoreRenderMetal
import Testing

@Suite struct ParityTests {
    /// Every family the suite covers, one test each, in the order the slices land.
    static let families = [
        "display", "compositeNormal", "blendSeparable", "opaqueRows", "transform", "resample",
        "blendNonSeparable", "blur", "unsharp", "adjust", "retouch",
    ]

    @Test func scaffoldListsEveryFamily() {
        #expect(Self.families.count == 11)
        #expect(Set(Self.families).count == Self.families.count, "no family is listed twice")
    }

    @Test(.disabled("waits on MB-3")) func display() { #expect(Bool(false), "waits on MB-3") }
    @Test(.disabled("waits on MB-4")) func compositeNormal() { #expect(Bool(false), "waits on MB-4") }
    @Test(.disabled("waits on MB-5")) func blendSeparable() { #expect(Bool(false), "waits on MB-5") }
    @Test(.disabled("waits on MB-6")) func opaqueRows() { #expect(Bool(false), "waits on MB-6") }
    @Test(.disabled("waits on MB-7")) func transform() { #expect(Bool(false), "waits on MB-7") }
    @Test(.disabled("waits on MB-8")) func resample() { #expect(Bool(false), "waits on MB-8") }
    @Test(.disabled("waits on MB-9")) func blendNonSeparable() { #expect(Bool(false), "waits on MB-9") }
    @Test(.disabled("waits on MB-11")) func blur() { #expect(Bool(false), "waits on MB-11") }
    @Test(.disabled("waits on MB-12")) func unsharp() { #expect(Bool(false), "waits on MB-12") }
    @Test(.disabled("waits on MB-13")) func adjust() { #expect(Bool(false), "waits on MB-13") }
    @Test(.disabled("waits on MB-15")) func retouch() { #expect(Bool(false), "waits on MB-15") }
}
#endif
