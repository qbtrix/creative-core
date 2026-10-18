// ICCReadTests.swift: CP-3's acceptance checks. Matrix-and-curve fixtures read colourants within 1e-6 and
// their curves; gray reads one curve; LUT, CMYK and Lab profiles throw naming themselves. Disabled until CP-3.
import CoreColor
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// True when reading `data` throws `.invalid` whose message names `word` (any case).
func readThrowsNaming(_ word: String, _ data: Data) -> Bool {
    do { _ = try ColorProfile(iccData: data) } catch { if case .invalid(let m) = error { return m.lowercased().contains(word.lowercased()) } }
    return false
}

@Suite(.disabled("waits on CP-3"))
struct ICCReadTests {
    @Test func colourantsExact() throws {
        for fixture in [ICCFixture.v2Gamma, .v4Parametric, .table] {
            let read = try ColorProfile(iccData: fixture.data).toXYZD50, want = fixture.expected?.toXYZD50 ?? []
            #expect(read.count == 9 && zip(read, want).allSatisfy { abs($0 - $1) < 1e-6 }, "\(fixture.name): \(read)")
        }
    }

    @Test func gammaCurve() throws {
        let read = try ColorProfile(iccData: ICCFixture.v2Gamma.data)
        #expect(read.curves == three(.gamma(563.0 / 256)) && read.name == "Fixture v2 gamma" && !read.isGray)
    }

    @Test func everyMatrixFixtureReads() throws {
        for fixture in ICCFixture.all {
            guard let want = fixture.expected else { continue }
            let read = try ColorProfile(iccData: fixture.data)
            #expect(nearlyEqual(read, want, 1e-6), "\(fixture.name): \(read)")
        }
    }

    @Test func grayReadsOneCurve() throws {
        let read = try ColorProfile(iccData: ICCFixture.gray.data)
        #expect(read.isGray && read.curves == [.gamma(ICC.q8(1.8))] && read.name == "Fixture gray")
        #expect(read.toXYZD50.count == 3 && zip(read.toXYZD50, ICCFixture.d50).allSatisfy { abs($0 - $1) < 1e-4 })
    }

    @Test func everyParametricTypeAndIdentity() throws {
        let params: [[Double]] = [[2.2], [2.2, 1.1, -0.1], [2.2, 1.1, -0.1, 0.05], ICCFixture.sRGBParams,
                                  [2.4, 0.947, 0.052, 0.077, 0.04, 0.01, 0.02]]
        let cases = params.enumerated().map { (ICC.para(UInt16($0), $1), ProfileCurve.parametric(type: $0, params: $1.map(ICC.q15))) }
        for (curve, want) in cases + [(ICC.type("curv") + ICC.u32(0), .gamma(1))] {  // a `curv` with count 0 is identity
            let bytes = ICC.profile(ICC.Header(), [("desc", ICC.mluc("Curve"))] + ICCFixture.rgbTags(ICCFixture.primariesB, three(curve)))
            let read = try ColorProfile(iccData: Data(bytes))
            #expect(nearlyEqual(read, ICCFixture.rgb("Curve", ICCFixture.primariesB, three(want)), 1e-6), "\(want)")
        }
    }

    @Test func unsupportedProfilesThrowNamingThemselves() {
        for (fixture, word) in [(ICCFixture.lutV2, "LUT"), (.lutV4, "LUT"), (.cmyk, "CMYK"), (.lab, "Lab")] {
            #expect(readThrowsNaming(word, fixture.data), "\(fixture.name)")
        }
        // An RGB matrix profile whose PCS is Lab, not XYZ.
        let labPCS = ICC.profile(ICC.Header(pcs: "Lab "), [("desc", ICC.mluc("Lab PCS"))]
            + ICCFixture.rgbTags(ICCFixture.primariesA, three(ICC.curv(gamma: 2.2))))
        #expect(readThrowsNaming("Lab", Data(labPCS)))
    }
}
