// ParityTests.swift: the parity suite scaffold (metal-backend MB-2): one disabled test per op
// family, each in its own `ParityTests+<Family>.swift` owned by the slice that lands the family
// (MB-3 to MB-15). Recipe, all in Sources/CoreRender/Parity; a family file imports CoreRender
// (and Foundation, for `URL`) besides CoreRenderMetal and Testing:
//   op: the family's `RenderOp`, the same name except `compositeNormal` -> `.composite` and
//       `opaqueRows` -> sample "opaque-rows" of `.composite` only; `unsharp` has no golden yet
//       (`.blur`'s samples call `gaussianBlur` only).
//   root: Tests/CoreRenderTests/Golden, from #filePath (`deletingLastPathComponent()` twice,
//         then "CoreRenderTests/Golden"); the goldens are packs of samples (ParityPack.swift).
//   for sample in try ParityHarness.sampleSet(for: op):
//     read and slice: let golden = try ParityGolden.band(from: root, op: op, sample: sample.name)
//     render:         let result = try ParityHarness.render(sample, on: backend)
//     compare:        #expect(try ParityHarness.compare(golden: golden, result).passed)
// The compare is in bytes in the golden's colour space, within the golden's tolerance. Goldens
// cover only `sampleSet(for:)`, one fixed set of calls per op; any wider grid a family header promises (other
// opacities, modes, sigmas, sizes) renders on a live `CPUBackend` too and compares the two with
// `ParityHarness.compare(_:_:tolerance:)`.
// Until its slice lands each body fails on purpose, so a
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
