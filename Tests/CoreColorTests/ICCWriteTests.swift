// ICCWriteTests.swift: CP-4's acceptance checks. A written profile reads back: exactly for 50 seeded ones on
// the fields' grids, within their rounding for the built-ins. Sizes are multiples of 4 matching the header,
// and `chad` adapts D65 to the D50 PCS. Disabled until CP-4.
import CoreColor
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite(.disabled("waits on CP-4"))
struct ICCWriteTests {
    static let builtIns = [ColorProfile.sRGB, .displayP3, .linearSRGB]

    static func seeded() -> [ColorProfile] {
        var rng = ICC.SplitMix64(state: 0xC010_5EED)
        return (0..<50).map { i in
            let m = (0..<9).map { _ in Double(rng.next() % 65536) / 65536 }
            let gamma = Double(256 + rng.next() % 512) / 256
            return ColorProfile(name: "Seeded \(i)", isGray: false, toXYZD50: m, curves: Array(repeating: .gamma(gamma), count: 3))
        }
    }

    @Test func roundTripsSeeded() throws { for p in Self.seeded() { #expect(try ColorProfile(iccData: p.iccData()) == p) } }

    @Test func roundTripsBuiltIns() throws {
        for profile in Self.builtIns {
            let read = try ColorProfile(iccData: profile.iccData())
            #expect(nearlyEqual(read, profile, 1e-5), "\(profile.name): \(read)")
        }
    }

    @Test func sizeMultipleOfFour() throws {
        for profile in Self.builtIns + Self.seeded() {
            let bytes = [UInt8](try profile.iccData())
            #expect(bytes.count % 4 == 0 && bytes.count >= 132 && ICC.read32(bytes, 0) == bytes.count, "\(profile.name)")
            guard bytes.count >= 132 else { continue }
            #expect(bytes[8] == 4 && Array(bytes[12..<24]) == ICC.sig("mntr") + ICC.sig("RGB ") + ICC.sig("XYZ "))
            #expect(Array(bytes[36..<40]) == ICC.sig("acsp"))
        }
    }

    @Test func roundTripsAdapted() throws {
        let bytes = [UInt8](try ColorProfile.sRGB.iccData())
        let chad = try #require(ICC.tags(bytes).first { $0.sig == "chad" })
        #expect(chad.size == 44 && Array(bytes[chad.offset..<chad.offset + 4]) == ICC.sig("sf32"))
        let m = (0..<9).map { Double(Int32(truncatingIfNeeded: ICC.read32(bytes, chad.offset + 8 + 4 * $0))) / 65536 }
        let d65 = try Color3(1, 1, 1).converted(from: .linearSRGB, to: .xyzD65)
        let mapped = [0, 3, 6].map { m[$0] * d65.c0 + m[$0 + 1] * d65.c1 + m[$0 + 2] * d65.c2 }
        #expect(zip(mapped, ICCFixture.d50).allSatisfy { abs($0 - $1) < 1e-4 }, "\(mapped)")
        #expect(nearlyEqual(try ColorProfile(iccData: Data(bytes)), .sRGB, 1e-5))
    }
}
