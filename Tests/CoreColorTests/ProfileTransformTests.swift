// ProfileTransformTests.swift: CP-5's acceptance checks. sRGB to itself is identity within 1e-9, to P3 matches
// CoreColor within 1e-6; a table inverts within 1e-5, outside 0...1 too; gray gives r == g == b; singular
// colourants and a falling table throw; the built-in P3 colourants are CoreColor's P3 primaries adapted to D50.
import CoreColor
import Testing

@Suite
struct ProfileTransformTests {
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
            #expect(Self.near(transform.apply(c), want, 1e-6), "\(c)")
            // The matrix part alone: linear sRGB in, linear P3 out.
            let linearP3 = Color3(TransferCurve.decode(want.c0), TransferCurve.decode(want.c1), TransferCurve.decode(want.c2))
            #expect(Self.near(transform.applyLinear(try c.converted(from: .sRGB, to: .linearSRGB)), linearP3, 1e-9), "\(c)")
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
            #expect(zip(got, want).allSatisfy { abs($0 - $1) < 1e-9 }, "column \(column): \(got) vs \(want)")
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
        let para = ProfileCurve.parametric(type: 3, params: [2.4, 1, 0, -0.5, 0.04])
        for curve in [ProfileCurve.gamma(0), para] {
            let target = ColorProfile(name: "\(curve)", isGray: false, toXYZD50: ColorProfile.sRGB.toXYZD50,
                                      curves: [curve, curve, curve])
            #expect(throws: ColorError.self, "\(curve)") { try ProfileTransform(from: .sRGB, to: target) }
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

    @Test func grayToSRGBIsNeutral() throws {
        let gray = ColorProfile(name: "Gray 2", isGray: true, toXYZD50: [0.9642, 1.0, 0.8249], curves: [.gamma(2)])
        let transform = try ProfileTransform(from: gray, to: .sRGB)
        for v in stride(from: 0.0, through: 1.0, by: 0.125) {
            let out = transform.apply(Color3(v, v, v))
            #expect(abs(out.c0 - out.c1) < 1e-9 && abs(out.c1 - out.c2) < 1e-9, "\(v): \(out)")
            #expect(abs(out.c1 - TransferCurve.encode(v * v)) < 1e-6, "\(v): \(out)")
        }
    }
}
