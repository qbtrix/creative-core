// ParametricCurveCountTests.swift: `ProfileCurve.parametric(type:params:)`
// takes exactly the documented count of parameters per type (0: 1, 1: 3,
// 2: 4, 3: 5, 4: 7); one more or one fewer throws, and type 3 with the
// sRGB-shaped five values builds a transform.
import CoreColor
import Testing

@Suite struct ParametricCurveCountTests {
    private static let counts = [1, 3, 4, 5, 7]
    private static let values = [2.4, 1.0 / 1.055, 0.055 / 1.055, 1.0 / 12.92, 0.04045, 0, 0]

    private static func profile(_ type: Int, _ params: [Double]) -> ColorProfile {
        ColorProfile(name: "para \(type)", isGray: false, toXYZD50: ColorProfile.sRGB.toXYZD50,
                     curves: Array(repeating: .parametric(type: type, params: params), count: 3))
    }

    @Test(arguments: 0..<5) func exactCountBuilds(type: Int) throws {
        let params = Array(Self.values.prefix(Self.counts[type]))
        _ = try ProfileTransform(from: Self.profile(type, params), to: .sRGB)
    }

    @Test(arguments: 0..<5) func otherCountsThrow(type: Int) {
        for n in [Self.counts[type] - 1, Self.counts[type] + 1] {
            let params = Array(repeating: 1.0, count: n)
            #expect(throws: ColorError.self) { try ProfileTransform(from: Self.profile(type, params), to: .sRGB) }
        }
    }

    @Test func typeThreeTakesFiveNotSeven() throws {
        _ = try ProfileTransform(from: Self.profile(3, Array(Self.values.prefix(5))), to: .sRGB)
        #expect(throws: ColorError.self) { try ProfileTransform(from: Self.profile(3, Self.values), to: .sRGB) }
    }
}
