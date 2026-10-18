// ICCFuzzTests.swift: CP-3's never-crash checks. A tag past the end, every truncation and 1,000 seeded
// byte mutations of the fixtures each throw `ColorError` or read a well-formed profile.
import CoreColor
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

struct ICCFuzzTests {
    @Test func tagPastEndThrows() {
        #expect(throws: ColorError.self) { try ColorProfile(iccData: ICCFixture.damaged.data) }
    }

    @Test func everyTruncationThrows() {
        let bytes = ICCFixture.v4Parametric.bytes
        for n in 0..<bytes.count {
            #expect(throws: ColorError.self, "\(n) bytes") { try ColorProfile(iccData: Data(bytes[0..<n])) }
        }
    }

    @Test func seededMutationsThrowOrRead() {
        var rng = ICC.SplitMix64(state: 0x1CC_F022)
        let bases = ICCFixture.all.map { $0.bytes }
        var read = 0, threw = 0
        for _ in 0..<1000 {
            var bytes = bases[Int(rng.next() % UInt64(bases.count))]
            for _ in 0...Int(rng.next() % 8) {
                bytes[Int(rng.next() % UInt64(bytes.count))] = UInt8(truncatingIfNeeded: rng.next())
            }
            if rng.next() % 4 == 0 { bytes.removeLast(Int(rng.next() % UInt64(bytes.count))) }
            do {
                let profile = try ColorProfile(iccData: Data(bytes))
                read += 1
                #expect(profile.curves.count == (profile.isGray ? 1 : 3))
                #expect(profile.toXYZD50.count == (profile.isGray ? 3 : 9) && profile.toXYZD50.allSatisfy { $0.isFinite })
            } catch {
                threw += 1
            }
        }
        #expect(read + threw == 1000 && read > 0 && threw > 0)
    }
}
