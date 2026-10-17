// ParityTests.swift: the parity suite scaffold (metal-backend MB-2): one disabled test per op
// family, each in its own `ParityTests+<Family>.swift` owned by the slice that lands the family
// (MB-3 to MB-15). Each family's test takes `ParityHarness.sampleSet(for:)`, renders each sample
// on this backend with `ParityHarness.render` and checks it against the RB-7 CPU goldens
// (`ParityGolden.read`) with `ParityHarness.compare(golden:_:)`, in bytes within the golden's
// tolerance (CPUGoldenTests says where each sample sits in a pack); all of it is in
// Sources/CoreRender/Parity, ready to call. Until its slice lands each body fails on purpose, so a
// family enabled by mistake fails loudly instead of passing empty. Every real parity test is also
// `.enabled(if: MetalBackend.defaultDevice != nil)`: a runner without a GPU skips it. Compiled
// out on Linux.
#if canImport(Metal)
import CoreRenderMetal
import Testing

@Suite struct ParityTests {
    /// Every family the suite covers, one test each, in the order the slices land.
    static let families = [
        "display", "compositeNormal", "blendSeparable", "opaqueRows", "transform", "resample",
        "blendNonSeparable", "blur", "unsharp", "adjust", "retouch",
    ]

    /// The same families bound to their test methods. `families` alone is a list of strings
    /// that nothing checks against the code: a family file could be renamed, dropped or
    /// misspelled and the list would still count 11. Each entry here is an unapplied method
    /// reference, so a family whose method is missing is a compile error, and
    /// `familiesAreBoundToTests` holds the two in the same order.
    static let tests: [(name: String, run: @Sendable (ParityTests) -> () -> Void)] = [
        ("display", { $0.display }),
        ("compositeNormal", { $0.compositeNormal }),
        ("blendSeparable", { $0.blendSeparable }),
        ("opaqueRows", { $0.opaqueRows }),
        ("transform", { $0.transform }),
        ("resample", { $0.resample }),
        ("blendNonSeparable", { $0.blendNonSeparable }),
        ("blur", { $0.blur }),
        ("unsharp", { $0.unsharp }),
        ("adjust", { $0.adjust }),
        ("retouch", { $0.retouch }),
    ]

    @Test func familiesAreBoundToTests() {
        #expect(Self.families.count == 11)
        #expect(Set(Self.families).count == Self.families.count, "no family is listed twice")
        #expect(Self.tests.map(\.name) == Self.families, "the bound table names every family, in order")
    }
}
#endif
