// ProfileTransformTests.swift: CP-5's acceptance checks. sRGB to itself is identity within 1e-9, to P3 matches
// CoreColor within `grid` (the built-ins sit on the ICC s15Fixed16 grid, CoreColor does not); a table inverts within 1e-5, outside 0...1 too; gray gives r == g == b; singular
// colourants, a falling or dipping table and malformed curves throw; every para type round trips; the built-in P3 colourants are CoreColor's P3 primaries adapted to D50.
import CoreColor
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

@Suite
struct ProfileTransformTests {
    /// Comparing a built-in against CoreColor's unrounded matrices and curve: the built-ins' entries are each
    /// within 2^-17 of those values, and three s15Fixed16 steps bound what that moves a channel or cone response.
    static let grid = 3.0 / 65536

    static func colours(_ seed: UInt64, _ low: Double, _ high: Double) -> [Color3] {
        var rng = ICC.SplitMix64(state: seed)
        return (0..<200).map { _ in
            Color3(.random(in: low...high, using: &rng), .random(in: low...high, using: &rng), .random(in: low...high, using: &rng))
        }
    }

    static func near(_ a: Color3, _ b: Color3, _ tolerance: Double) -> Bool {
        abs(a.c0 - b.c0) <= tolerance && abs(a.c1 - b.c1) <= tolerance && abs(a.c2 - b.c2) <= tolerance
    }

    @Test func sRGBToSRGBIsIdentity() throws {
        let transform = try ProfileTransform(from: .sRGB, to: .sRGB)
        for c in Self.colours(1, -0.25, 1.25) { #expect(Self.near(transform.apply(c), c, 1e-9), "\(c)") }
    }

    @Test func sRGBToP3MatchesCoreColor() throws {
        let transform = try ProfileTransform(from: .sRGB, to: .displayP3)
        for c in Self.colours(2, 0, 1) {
            let want = try c.converted(from: .sRGB, to: .displayP3)
            // Encoded, a linear difference grows by up to the sRGB curve's steepest slope, 12.92.
            #expect(Self.near(transform.apply(c), want, 13 * Self.grid), "\(c)")
            // The matrix part alone: linear sRGB in, linear P3 out.
            let linearP3 = Color3(TransferCurve.decode(want.c0), TransferCurve.decode(want.c1), TransferCurve.decode(want.c2))
            #expect(Self.near(transform.applyLinear(try c.converted(from: .sRGB, to: .linearSRGB)), linearP3, Self.grid), "\(c)")
        }
    }

    @Test func displayP3ColourantsAreCoreColorsPrimaries() throws {
        // In Bradford cone space (ICC.1 Annex E) adaptation is a per-cone scale, so each D50 colourant's cone
        // response is CoreColor's D65 P3 primary's response scaled by D50 over D65; no matrix inverse needed.
        let bradford = [[0.8951, 0.2664, -0.1614], [-0.7502, 1.7135, 0.0367], [0.0389, -0.0685, 1.0296]]
        func cones(_ x: Double, _ y: Double, _ z: Double) -> [Double] { bradford.map { $0[0] * x + $0[1] * y + $0[2] * z } }
        let d65 = try Color3(1, 1, 1).converted(from: .linearSRGB, to: .xyzD65)
        let d50 = cones(0.9642, 1.0, 0.8249), white = cones(d65.c0, d65.c1, d65.c2)
        let m = ColorProfile.displayP3.toXYZD50
        try #require(m.count == 9)
        for (column, rgb) in [Color3(1, 0, 0), Color3(0, 1, 0), Color3(0, 0, 1)].enumerated() {
            let p = try rgb.converted(from: .displayP3, to: .xyzD65)
            let want = zip(cones(p.c0, p.c1, p.c2), zip(d50, white)).map { $0 * $1.0 / $1.1 }
            let got = cones(m[column], m[3 + column], m[6 + column])
            #expect(zip(got, want).allSatisfy { abs($0 - $1) < Self.grid }, "column \(column): \(got) vs \(want)")
        }
    }

    @Test func uninvertibleTargetsThrow() {
        let flat = ColorProfile(name: "Flat", isGray: false, toXYZD50: [Double](repeating: 0.5, count: 9),
                                curves: [.gamma(1), .gamma(1), .gamma(1)])
        #expect(throws: ColorError.self) { try ProfileTransform(from: .sRGB, to: flat) }
        let falling = ProfileCurve.table([1, 0.5, 0])
        let backwards = ColorProfile(name: "Falling", isGray: false, toXYZD50: ColorProfile.sRGB.toXYZD50,
                                     curves: [falling, falling, falling])
        #expect(throws: ColorError.self) { try ProfileTransform(from: .sRGB, to: backwards) }
        #expect(throws: ColorError.self) { try ProfileTransform(from: .sRGB, to: ColorProfile(name: "Short", isGray: false,
                                                                                           toXYZD50: [1, 0, 0], curves: [])) }
        // A zero gamma, and a para function type 3 whose linear segment falls (c < 0), cannot be inverted.
        // A para function type 1 with a zero slope a has no inverse either.
        let para = ProfileCurve.parametric(type: 3, params: [2.4, 1, 0, -0.5, 0.04])
        for curve in [ProfileCurve.gamma(0), para, .parametric(type: 1, params: [2.2, 0, 0.1])] {
            let target = ColorProfile(name: "\(curve)", isGray: false, toXYZD50: ColorProfile.sRGB.toXYZD50,
                                      curves: [curve, curve, curve])
            #expect(throws: ColorError.self, "\(curve)") { try ProfileTransform(from: .sRGB, to: target) }
        }
        // A table that dips in the middle, and one that never rises, cannot be inverted by binary search.
        for curve in [ProfileCurve.table([0, 0.8, 0.4, 1]), .table([0.5, 0.5])] {
            let target = ColorProfile(name: "\(curve)", isGray: false, toXYZD50: ColorProfile.sRGB.toXYZD50,
                                      curves: [curve, curve, curve])
            #expect(throws: ColorError.self, "\(curve)") { try ProfileTransform(from: .sRGB, to: target) }
        }
    }

    @Test func malformedCurvesThrow() {
        // A para type out of range, a para type with too few parameters, and an RGB profile with 2 curves: each
        // throws, where indexing the parameter counts, the parameters or the third curve would trap.
        let g = ProfileCurve.gamma(2.2), m = ColorProfile.sRGB.toXYZD50
        let targets = [
            ColorProfile(name: "para type 5", isGray: false, toXYZD50: m, curves: [g, .parametric(type: 5, params: [1]), g]),
            ColorProfile(name: "para short", isGray: false, toXYZD50: m, curves: [g, .parametric(type: 3, params: [2.4]), g]),
            ColorProfile(name: "two curves", isGray: false, toXYZD50: m, curves: [g, g]),
        ]
        for target in targets {
            #expect(throws: ColorError.self, "\(target.name)") { try ProfileTransform(from: .sRGB, to: target) }
        }
        // A curve's error names the profile and the channel that failed.
        #expect { try ProfileTransform(from: .sRGB, to: targets[0]) } throws: { error in
            guard case ColorError.invalid(let why) = error else { return false }
            return why.contains("para type 5") && why.contains("curve 1")
        }
    }

    @Test func everyParametricTypeRoundTrips() throws {
        // ICC.1 10.18's five function types, each with the linear value it gives encoded 0.5. sRGB's colourants
        // make the matrix part identity, and 0.1 and up is past every knee, where each curve is invertible.
        // Encoded 0.02 is below the knee d of types 1 to 4, so it gives the linear segment: 0 for type 1, f for
        // type 2, cX for type 3 and cX + f for type 4. `back` is what encoding that value gives: 0.02 where the
        // segment rises, and d where it is flat (types 1 and 2), the lowest input that reaches it.
        let low = 0.02, d = 0.1 / 1.1
        let cases: [(type: Int, params: [Double], half: Double, linear: Double, back: Double)] = [
            (0, [2.2], pow(0.5, 2.2), pow(low, 2.2), low),
            (1, [2.2, 1.1, -0.1], pow(1.1 * 0.5 - 0.1, 2.2), 0, d),
            (2, [2.2, 1.1, -0.1, 0.05], pow(1.1 * 0.5 - 0.1, 2.2) + 0.05, 0.05, d),
            (3, [2.4, 1 / 1.055, 0.055 / 1.055, 1 / 12.92, 0.04045], pow((0.5 + 0.055) / 1.055, 2.4), low / 12.92, low),
            // f below the knee's value, about 0.0131, so the linear segment stays under the curve and inverts.
            (4, [2.4, 0.947, 0.052, 0.077, 0.04, 0.01, 0.005], pow(0.947 * 0.5 + 0.052, 2.4) + 0.01, 0.077 * low + 0.005, low),
        ]
        for (type, params, half, linear, back) in cases {
            let curve = ProfileCurve.parametric(type: type, params: params)
            let profile = ColorProfile(name: "Type \(type)", isGray: false, toXYZD50: ColorProfile.sRGB.toXYZD50,
                                       curves: [curve, curve, curve])
            let decode = try ProfileTransform(from: profile, to: .linearSRGB)
            let encode = try ProfileTransform(from: .linearSRGB, to: profile)
            let mid = decode.apply(Color3(0.5, 0.5, 0.5))
            #expect(Self.near(mid, Color3(half, half, half), 1e-9), "type \(type): \(mid) vs \(half)")
            let below = decode.apply(Color3(low, low, low))
            #expect(Self.near(below, Color3(linear, linear, linear), 1e-9), "type \(type): \(below) vs \(linear)")
            let again = encode.apply(Color3(linear, linear, linear))
            // 1e-6, as below: at a flat segment's d the 1/g root magnifies the matrix part's grid-sized rounding.
            #expect(Self.near(again, Color3(back, back, back), 1e-6), "type \(type): \(again) vs \(back)")
            for c in Self.colours(6, 0.1, 1.25) {
                #expect(Self.near(encode.apply(decode.apply(c)), c, 1e-6), "type \(type): \(c)")
            }
        }
    }

    @Test func differentWhitesAdapt() throws {
        // sRGB's colourants left at their D65 white, not adapted to D50: Bradford must carry D65 to sRGB's D50.
        let c = try [Color3(1, 0, 0), Color3(0, 1, 0), Color3(0, 0, 1)].map { try $0.converted(from: .linearSRGB, to: .xyzD65) }
        let d65 = ColorProfile(name: "D65 sRGB", isGray: false,
                               toXYZD50: [c[0].c0, c[1].c0, c[2].c0, c[0].c1, c[1].c1, c[2].c1, c[0].c2, c[1].c2, c[2].c2],
                               curves: ColorProfile.sRGB.curves)
        let transform = try ProfileTransform(from: d65, to: .sRGB)
        let white = transform.apply(Color3(1, 1, 1)), grey = transform.apply(Color3(0.5, 0.5, 0.5))
        #expect(Self.near(white, Color3(1, 1, 1), 1e-4), "\(white)")
        #expect(Self.near(grey, Color3(0.5, 0.5, 0.5), 1e-4), "\(grey)")
    }

    @Test func tableInverts() throws {
        // Encoded x to linear x * x, as 257 entries; sRGB's colourants so the matrix part is identity.
        let squares = ProfileCurve.table((0...256).map { Double($0 * $0) / 65536 })
        let table = ColorProfile(name: "Squares", isGray: false, toXYZD50: ColorProfile.sRGB.toXYZD50,
                                 curves: [squares, squares, squares])
        let encode = try ProfileTransform(from: .linearSRGB, to: table), decode = try ProfileTransform(from: table, to: .linearSRGB)
        #expect(Self.near(encode.apply(Color3(0.25, 0.25, 0.25)), Color3(0.5, 0.5, 0.5), 1e-6))
        for c in Self.colours(4, -0.25, 1.25) { #expect(Self.near(decode.apply(encode.apply(c)), c, 1e-5), "\(c)") }
    }

    @Test func sRGBToGrayIsLuminance() throws {
        // Gray target: Y over the white's Y, written to all three channels, then the gamma-2 curve inverted.
        let gray = ColorProfile(name: "Gray 2", isGray: true, toXYZD50: [0.9642, 1.0, 0.8249], curves: [.gamma(2)])
        let transform = try ProfileTransform(from: .sRGB, to: gray)
        let toLinear = try ProfileTransform(from: .sRGB, to: .linearSRGB), row = ColorProfile.linearSRGB.toXYZD50
        for c in Self.colours(5, 0, 1) {
            let linear = toLinear.apply(c), y = row[3] * linear.c0 + row[4] * linear.c1 + row[5] * linear.c2
            let out = transform.apply(c)
            #expect(out.c0 == out.c1 && out.c1 == out.c2, "\(c): \(out)")
            #expect(abs(out.c1 - y.squareRoot()) < Self.grid, "\(c): \(out) vs \(y)")
        }
        // A gray white with Y <= 0 throws; a negative Y would otherwise build a finite, inverted transform.
        for y in [0.0, -1] {
            let dark = ColorProfile(name: "Y \(y)", isGray: true, toXYZD50: [0.9642, y, 0.8249], curves: [.gamma(2)])
            #expect(throws: ColorError.self, "Y \(y)") { try ProfileTransform(from: .sRGB, to: dark) }
        }
    }

    @Test func grayToSRGBIsNeutral() throws {
        let gray = ColorProfile(name: "Gray 2", isGray: true, toXYZD50: [0.9642, 1.0, 0.8249], curves: [.gamma(2)])
        let transform = try ProfileTransform(from: gray, to: .sRGB)
        for v in stride(from: 0.0, through: 1.0, by: 0.125) {
            let out = transform.apply(Color3(v, v, v))
            #expect(abs(out.c0 - out.c1) < 1e-9 && abs(out.c1 - out.c2) < 1e-9, "\(v): \(out)")
            #expect(abs(out.c1 - TransferCurve.encode(v * v)) < Self.grid, "\(v): \(out)")
        }
    }
}
