// ColorSpaceTests.swift: Color3 conversions against published reference values,
// seeded round trips through every space, and rejection of non-finite input.
import CoreColor
import Foundation
import Testing

/// Seeded generator; the same algorithm as FlareCoreTests' `SplitMix64`, which
/// this test target cannot import.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private func close(_ a: Color3, _ b: Color3, _ tolerance: Double) -> Bool {
    abs(a.c0 - b.c0) <= tolerance && abs(a.c1 - b.c1) <= tolerance && abs(a.c2 - b.c2) <= tolerance
}

@Test func randomSRGBColorsRoundTripThroughEverySpace() throws {
    var rng = SplitMix64(seed: 111)
    for _ in 0..<500 {
        let c = Color3(.random(in: 0...1, using: &rng), .random(in: 0...1, using: &rng), .random(in: 0...1, using: &rng))
        for space in ColorSpace.allCases {
            let there = try c.converted(from: .sRGB, to: space)
            let back = try there.converted(from: space, to: .sRGB)
            #expect(close(back, c, 1e-6), "sRGB \(c) via \(space) came back as \(back)")
        }
    }
}

@Test func outOfRangeValuesRoundTripUnclamped() throws {
    let wide = Color3(-0.2, 0.5, 1.3)
    for space in ColorSpace.allCases {
        let back = try wide.converted(from: .sRGB, to: space).converted(from: space, to: .sRGB)
        #expect(close(back, wide, 1e-6), "via \(space): \(back)")
    }
}

@Test func negativeLMSRoundTripsThroughOKLab() throws {
    // Linear sRGB (1, -0.5, -0.5) has a negative M response, so OKLab's cube root must keep the sign.
    let c = Color3(1, -0.5, -0.5)
    let back = try c.converted(from: .linearSRGB, to: .oklab).converted(from: .oklab, to: .linearSRGB)
    #expect(close(back, c, 1e-9), "\(back)")
}

@Test func sRGBWhiteIsD65InXYZ() throws {
    let xyz = try Color3(1, 1, 1).converted(from: .sRGB, to: .xyzD65)
    #expect(close(xyz, Color3(0.95047, 1.0, 1.08883), 1e-4), "\(xyz)")
}

@Test func sRGBRedInOKLab() throws {
    let lab = try Color3(1, 0, 0).converted(from: .sRGB, to: .oklab)
    #expect(close(lab, Color3(0.62796, 0.22486, 0.12585), 1e-4), "\(lab)")
}

@Test func sRGBWhiteInOKLabHasLightnessOne() throws {
    let lab = try Color3(1, 1, 1).converted(from: .sRGB, to: .oklab)
    #expect(close(lab, Color3(1, 0, 0), 1e-4), "\(lab)")
}

@Test func sRGBHalfDecodesToLinear() throws {
    let linear = try Color3(0.5, 0.5, 0.5).converted(from: .sRGB, to: .linearSRGB)
    #expect(close(linear, Color3(0.21404, 0.21404, 0.21404), 1e-5), "\(linear)")
    let toe = try Color3(0.02, 0, -0.02).converted(from: .sRGB, to: .linearSRGB)
    #expect(close(toe, Color3(0.02 / 12.92, 0, -0.02 / 12.92), 1e-12), "\(toe)")
}

@Test func sRGBRedInDisplayP3() throws {
    let p3 = try Color3(1, 0, 0).converted(from: .sRGB, to: .displayP3)
    #expect(close(p3, Color3(0.9175, 0.2003, 0.1386), 1e-3), "\(p3)")
    let white = try Color3(1, 1, 1).converted(from: .sRGB, to: .displayP3)
    #expect(close(white, Color3(1, 1, 1), 1e-9), "\(white)")
}

@Test func nonFiniteComponentsThrow() {
    let bad = [Color3(.nan, 0, 0), Color3(0, .infinity, 0), Color3(0, 0, -.infinity)]
    for c in bad {
        for space in ColorSpace.allCases {
            #expect(throws: ColorError.self) { try c.converted(from: space, to: .oklab) }
            #expect(throws: ColorError.self) { try c.converted(from: space, to: space) }
        }
    }
}

@Test func overflowingResultThrows() {
    #expect(throws: ColorError.self) { try Color3(1e308, 0, 0).converted(from: .sRGB, to: .linearSRGB) }
}

@Test func clampedToUnitClampsEachComponent() {
    #expect(Color3(-0.5, 0.25, 1.5).clampedToUnit() == Color3(0, 0.25, 1))
}

@Test func colorEncodesAndDecodes() throws {
    let c = Color3(0.1, -0.2, 1.3)
    let data = try JSONEncoder().encode(c)
    #expect(try JSONDecoder().decode(Color3.self, from: data) == c)
}
