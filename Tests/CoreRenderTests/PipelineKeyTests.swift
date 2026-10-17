// PipelineKeyTests.swift: the identity of one cached Metal pipeline. Equal op
// and variant hash to one entry; a different variant or op is a different
// key; `functionName` is the op's raw value with `_variant` when there is
// one; `validated` keeps identifier variants of at most 64 bytes and throws
// `RenderError.raster` for anything else; a Codable round trip is exact; and a seeded fuzz over
// random Unicode variants never crashes.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CoreRender
import Testing

@Suite struct PipelineKeyTests {
    @Test func sameOpAndVariantAreEqualAndHashToOneEntry() {
        let a = PipelineKey(op: .blendSeparable, variant: "multiply")
        let b = PipelineKey(op: .blendSeparable, variant: "multiply")
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        #expect(Set([a, b]).count == 1)
        #expect(PipelineKey(op: .display) == PipelineKey(op: .display, variant: ""), "the default variant is empty")
    }

    @Test func differentVariantOrOpIsADifferentKey() {
        let multiply = PipelineKey(op: .blendSeparable, variant: "multiply")
        let screen = PipelineKey(op: .blendSeparable, variant: "screen")
        let resample = PipelineKey(op: .resample, variant: "multiply")
        #expect(multiply != screen)
        #expect(multiply != resample)
        #expect(Set([multiply, screen, resample]).count == 3)
    }

    @Test func functionNameIsTheOpThenAnUnderscoreAndTheVariant() {
        #expect(PipelineKey(op: .composite, variant: "").functionName == "composite")
        #expect(PipelineKey(op: .composite, variant: "multiply").functionName == "composite_multiply")
        #expect(PipelineKey(op: .resample, variant: "lanczos3").functionName == "resample_lanczos3")
        #expect(PipelineKey(op: .blendNonSeparable).functionName == "blendNonSeparable")
    }

    @Test func validatedAcceptsIdentifierVariants() throws {
        let lanczos = try PipelineKey.validated(op: .resample, variant: "lanczos3")
        #expect(lanczos == PipelineKey(op: .resample, variant: "lanczos3"))
        let softLight = try PipelineKey.validated(op: .blendSeparable, variant: "soft_light")
        #expect(softLight.functionName == "blendSeparable_soft_light")
        let plain = try PipelineKey.validated(op: .display, variant: "")
        #expect(plain == PipelineKey(op: .display), "an empty variant is an identifier-free name")
    }

    @Test(arguments: ["soft light", "über", "a-b", "x.y", "ʼ", "a/b"])
    func validatedThrowsRasterForANonIdentifierVariant(variant: String) {
        #expect(throws: RenderError.raster("pipeline variant '\(variant)' must be [A-Za-z0-9_]")) {
            try PipelineKey.validated(op: .blendSeparable, variant: variant)
        }
    }

    @Test func validatedBoundsTheVariantAtSixtyFourBytes() throws {
        #expect(PipelineKey.maxVariantLength == 64)
        let empty = try PipelineKey.validated(op: .composite, variant: "")
        #expect(empty.functionName == "composite")
        let atLimit = String(repeating: "a", count: 64)
        let key = try PipelineKey.validated(op: .composite, variant: atLimit)
        #expect(key.variant == atLimit)
        #expect(throws: RenderError.raster("pipeline variant is 65 bytes, over 64")) {
            try PipelineKey.validated(op: .composite, variant: String(repeating: "a", count: 65))
        }
        // 22 two-byte scalars: 44 bytes, under the bound, so the identifier check rejects it.
        let accents = String(repeating: "é", count: 22)
        #expect(throws: RenderError.raster("pipeline variant '\(accents)' must be [A-Za-z0-9_]")) {
            try PipelineKey.validated(op: .composite, variant: accents)
        }
        // 33 two-byte scalars: 33 characters but 66 bytes, so the bound counts bytes.
        #expect(throws: RenderError.raster("pipeline variant is 66 bytes, over 64")) {
            try PipelineKey.validated(op: .composite, variant: String(repeating: "é", count: 33))
        }
    }

    @Test func codableRoundTripIsExact() throws {
        let key = PipelineKey(op: .adjust, variant: "curves")
        let data = try JSONEncoder().encode(key)
        let decoded = try JSONDecoder().decode(PipelineKey.self, from: data)
        #expect(decoded == key)
        #expect(decoded.functionName == "adjust_curves")
        let empty = try JSONDecoder().decode(PipelineKey.self, from: JSONEncoder().encode(PipelineKey(op: .blur)))
        #expect(empty == PipelineKey(op: .blur))
    }

    @Test func fuzzedVariantsAreValidatedOrRejectedAndNeverCrash() {
        var rng = SplitMix64(seed: 0x5EED_2A)
        let ops = RenderOp.allCases
        var accepted = 0
        var rejected = 0
        for _ in 0..<200 {
            let op = ops[Int(rng.next() % UInt64(ops.count))]
            let variant = randomVariant(&rng)
            do {
                let key = try PipelineKey.validated(op: op, variant: variant)
                accepted += 1
                #expect(key.op == op)
                #expect(key.variant == variant)
                #expect(isWellFormedFunctionName(key.functionName, op: op), "\(key.functionName)")
            } catch RenderError.raster(let message) {
                rejected += 1
                #expect(message.hasPrefix("pipeline variant '"))
                #expect(variant.unicodeScalars.contains { !isIdentifier($0) }, "rejected an identifier: \(variant)")
            } catch {
                Issue.record("validated threw a non-raster error: \(error)")
            }
        }
        #expect(accepted > 20, "the fuzz exercised the accept path")
        #expect(rejected > 20, "the fuzz exercised the reject path")
    }

    /// `op.rawValue`, then nothing, or `_` and one or more identifier scalars.
    private func isWellFormedFunctionName(_ name: String, op: RenderOp) -> Bool {
        guard name.hasPrefix(op.rawValue) else { return false }
        let tail = name.dropFirst(op.rawValue.count)
        if tail.isEmpty { return true }
        guard tail.first == "_", tail.count > 1 else { return false }
        return tail.dropFirst().unicodeScalars.allSatisfy(isIdentifier)
    }

    private func isIdentifier(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F: true
        default: false
        }
    }

    /// 0 to 11 scalars; half the strings draw from an identifier alphabet so
    /// the accept path is exercised, the rest from the whole scalar space
    /// (surrogates skipped, since they are not scalars).
    private func randomVariant(_ rng: inout SplitMix64) -> String {
        let identifierAlphabet = Array("ABCXYZabcxyz0189_")
        let length = Int(rng.next() % 12)
        var scalars = String.UnicodeScalarView()
        let safe = rng.next() % 2 == 0
        while scalars.count < length {
            if safe {
                scalars.append(contentsOf: identifierAlphabet[Int(rng.next() % UInt64(identifierAlphabet.count))].unicodeScalars)
            } else if let scalar = Unicode.Scalar(UInt32(rng.next() % 0x11_0000)) {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }
}
