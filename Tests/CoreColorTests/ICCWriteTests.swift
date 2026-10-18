// ICCWriteTests.swift: CP-4's acceptance checks. A written profile reads back exactly: 50 seeded ones on
// the fields' grids and the built-ins, which are on the s15Fixed16 grid too. Sizes are multiples of 4 matching the header,
// and `chad` adapts D65 to the D50 PCS. Gray, table and parametric curves read back too, and a value that does
// not fit its field throws instead of writing bytes that read back different.
import CoreColor
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

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
            #expect(read == profile, "\(profile.name): \(read)")
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
        #expect(try ColorProfile(iccData: Data(bytes)) == .sRGB)
    }

    @Test func equalTagsShareOneCopy() throws {
        // sRGB's three curves are equal, so rTRC, gTRC and bTRC point at one copy (ICC.1 7.3.1).
        let tags = ICC.tags([UInt8](try ColorProfile.sRGB.iccData()))
        let offsets = ["rTRC", "gTRC", "bTRC"].map { name in tags.first { $0.sig == name }?.offset }
        #expect(offsets[0] != nil && offsets[0] == offsets[1] && offsets[1] == offsets[2], "\(offsets)")
    }

    @Test func roundTripsGrayTableAndParametric() throws {
        let gray = ColorProfile(name: "Gray ✓", isGray: true, toXYZD50: ICCFixture.d50.map(ICC.q15), curves: [.gamma(ICC.q8(1.8))])
        let table = ColorProfile(name: "Table", isGray: false, toXYZD50: ICCFixture.primariesB.map(ICC.q15),
                                 curves: ICCFixture.tables.map { .table($0.map(ICC.q16)) })
        let para = ColorProfile(name: "Para", isGray: false, toXYZD50: ICCFixture.primariesA.map(ICC.q15),
                                curves: [.parametric(type: 0, params: [2.5]), .parametric(type: 2, params: [2, 1, 0.5, 0.25]),
                                         .parametric(type: 4, params: [2.4, 0.9, 0.1, 0.0625, 0.04, 0.01, 0.02].map(ICC.q15))])
        for p in [gray, table, para] { #expect(try ColorProfile(iccData: p.iccData()) == p) }
        let grayBytes = [UInt8](try gray.iccData())
        #expect(Array(grayBytes[16..<20]) == ICC.sig("GRAY") && !ICC.tags(grayBytes).contains { $0.sig == "chad" })
    }

    @Test func valuesThatDoNotFitThrow() {
        let m = ColorProfile.sRGB.toXYZD50, g = ProfileCurve.gamma(2.2)
        let bad = [
            ColorProfile(name: "short matrix", isGray: false, toXYZD50: [1, 0, 0], curves: [g, g, g]),
            ColorProfile(name: "two curves", isGray: false, toXYZD50: m, curves: [g, g]),
            ColorProfile(name: "gray of nine", isGray: true, toXYZD50: m, curves: [g]),
            ColorProfile(name: "huge colourant", isGray: false, toXYZD50: [40_000] + m.dropFirst(), curves: [g, g, g]),
            ColorProfile(name: "NaN", isGray: false, toXYZD50: [.nan] + m.dropFirst(), curves: [g, g, g]),
            ColorProfile(name: "gamma 300", isGray: false, toXYZD50: m, curves: [.gamma(300), g, g]),
            ColorProfile(name: "negative gamma", isGray: false, toXYZD50: m, curves: [.gamma(-1), g, g]),
            ColorProfile(name: "one-entry table", isGray: false, toXYZD50: m, curves: [.table([0.5]), g, g]),
            ColorProfile(name: "table above 1", isGray: false, toXYZD50: m, curves: [.table([0, 1.5]), g, g]),
            // Just outside 0...1: these round onto the UInt16 grid's ends, so only the range check rejects them.
            ColorProfile(name: "table just above 1", isGray: false, toXYZD50: m, curves: [.table([0, 1.000001]), g, g]),
            ColorProfile(name: "table just below 0", isGray: false, toXYZD50: m, curves: [.table([-0.000001, 1]), g, g]),
            ColorProfile(name: "para type 5", isGray: false, toXYZD50: m, curves: [.parametric(type: 5, params: [1]), g, g]),
            ColorProfile(name: "para type -1", isGray: false, toXYZD50: m, curves: [.parametric(type: -1, params: [1]), g, g]),
            ColorProfile(name: "para short", isGray: false, toXYZD50: m, curves: [.parametric(type: 3, params: [2.4]), g, g]),
        ]
        for p in bad { #expect(throws: ColorError.self, "\(p.name)") { try p.iccData() } }
    }

    @Test func errorsSayWhatIsNeeded() {
        let g = ProfileCurve.gamma(1)
        let cases: [(ColorProfile, String)] = [
            (ColorProfile(name: "x", isGray: false, toXYZD50: Array(repeating: 0.1, count: 8), curves: [g, g, g]), "needs 9"),
            (ColorProfile(name: "x", isGray: false, toXYZD50: ColorProfile.sRGB.toXYZD50, curves: [.table([0.5]), g, g]), "needs 2 or more"),
            (ColorProfile(name: "x", isGray: false, toXYZD50: ColorProfile.sRGB.toXYZD50,
                          curves: [.parametric(type: 5, params: [1, 2, 3]), g, g]), "0 to 4 with 1/3/4/5/7"),
        ]
        for (profile, words) in cases {
            #expect { try profile.iccData() } throws: { error in
                guard case ColorError.invalid(let why) = error else { return false }
                return why.contains(words)
            }
        }
    }
}
