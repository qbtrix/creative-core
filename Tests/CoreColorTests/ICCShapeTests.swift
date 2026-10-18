// ICCShapeTests.swift: the ICC contract exists with its exact signatures, the
// unbuilt entry points throw `ColorError.invalid("not built: <task>")` instead
// of trapping, and the three built-in profiles hold the values ICC.1 needs.
import CoreColor
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Test func readStubThrowsNotBuilt() {
    let header = Data([0, 0, 0, 128] + [UInt8](repeating: 0, count: 124))
    #expect(throws: ColorError.invalid("not built: CP-3")) { try ColorProfile(iccData: header) }
    #expect(throws: ColorError.invalid("not built: CP-3")) { try ColorProfile(iccData: Data()) }
}

@Test func writeStubThrowsNotBuilt() {
    for profile in [ColorProfile.sRGB, .displayP3, .linearSRGB] {
        #expect(throws: ColorError.invalid("not built: CP-4")) { try profile.iccData() }
    }
}

@Test func transformStubThrowsNotBuilt() {
    #expect(throws: ColorError.invalid("not built: CP-5")) {
        try ProfileTransform(from: .sRGB, to: .displayP3)
    }
    #expect(throws: ColorError.invalid("not built: CP-5")) {
        try ProfileTransform(from: .sRGB, to: .sRGB)
    }
}

@Test func builtInsMapWhiteToTheD50PCS() {
    // ICC.1 7.2.16: the PCS illuminant is D50 (0.9642, 1.0, 0.8249).
    for profile in [ColorProfile.sRGB, .displayP3, .linearSRGB] {
        let m = profile.toXYZD50
        #expect(m.count == 9 && profile.curves.count == 3 && !profile.isGray)
        guard m.count == 9 else { continue }
        #expect(abs(m[0] + m[1] + m[2] - 0.9642) < 1e-9)
        #expect(abs(m[3] + m[4] + m[5] - 1.0) < 1e-9)
        #expect(abs(m[6] + m[7] + m[8] - 0.8249) < 1e-9)
    }
}

@Test func sRGBColourantsAreBradfordAdapted() {
    // The luminance row of sRGB adapted to D50 (D65 unadapted is 0.2126, 0.7152, 0.0722).
    let y = Array(ColorProfile.sRGB.toXYZD50[3..<6])
    #expect(abs(y[0] - 0.2225) < 1e-3 && abs(y[1] - 0.7169) < 1e-3 && abs(y[2] - 0.0606) < 1e-3)
    #expect(ColorProfile.sRGB.toXYZD50 != ColorProfile.displayP3.toXYZD50)
    #expect(ColorProfile.sRGB.toXYZD50 == ColorProfile.linearSRGB.toXYZD50)
}

@Test func builtInCurvesAndNames() {
    let srgbCurve = ProfileCurve.parametric(type: 3, params: [2.4, 1 / 1.055, 0.055 / 1.055, 1 / 12.92, 0.04045])
    #expect(ColorProfile.sRGB.curves == [srgbCurve, srgbCurve, srgbCurve])
    #expect(ColorProfile.displayP3.curves == ColorProfile.sRGB.curves)
    #expect(ColorProfile.linearSRGB.curves == [.gamma(1), .gamma(1), .gamma(1)])
    #expect(Set([ColorProfile.sRGB.name, ColorProfile.displayP3.name, ColorProfile.linearSRGB.name]).count == 3)
}

@Test func profilesAreValuesComparedByEveryField() {
    let gray = ColorProfile(name: "Gray 2.2", isGray: true, toXYZD50: [0.9642, 1.0, 0.8249],
                            curves: [.gamma(2.2)])
    #expect(gray.isGray && gray.curves == [.gamma(2.2)] && gray.toXYZD50.count == 3)
    var renamed = gray
    renamed.name = "Other"
    #expect(renamed != gray)
    var table = gray
    table.curves = [.table([0, 0.5, 1])]
    #expect(table != gray && Set([gray, table, renamed]).count == 3)
}
