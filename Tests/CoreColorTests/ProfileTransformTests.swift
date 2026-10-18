// ProfileTransformTests.swift: CP-5's acceptance checks. sRGB to itself is identity within 1e-9, to P3 matches
// CoreColor within 1e-6; a table inverts within 1e-5, outside 0...1 too; gray gives r == g == b. Disabled until CP-5.
import CoreColor
import Testing

@Suite(.disabled("waits on CP-5"))
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
        }
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
