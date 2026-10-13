// FillRadialEdgeOffCenterTests.swift: a radial radius too small to move the
// edge off center.x (#235). center.x ± radius is a rounded sum, so a positive
// radius below half an ulp of center.x gives an edge equal to the center, and
// Lottie would write a zero-length gradient (e == s). Validation rejects that,
// on either side, and every radial fill that validates exports with e != s.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Testing
@testable import FlareCore

@Suite struct FillRadialEdgeOffCenterTests {
    static let message = "radial gradient radius too small to move its edge off center.x"

    static func doc(_ x: Double, _ r: Double) -> Document {
        FillRadialExtentAdversarialTests.doc(FillRadialExtentAdversarialTests.radial(x, 0, r))
    }

    /// Just enough of the Lottie document to read the gradient fill's points.
    /// JSONDecoder, because it parses doubles exactly.
    struct Lottie: Decodable {
        struct Layer: Decodable { let shapes: [Group] }
        struct Group: Decodable { let it: [Item] }
        struct Item: Decodable { let ty: String; let s: Value?; let e: Value? }
        struct Value: Decodable { let k: [Double] }
        let layers: [Layer]
    }

    /// The Lottie gradient fill's start and end points, as exported.
    static func lottieStartAndEnd(_ d: Document) throws -> (s: [Double], e: [Double]) {
        let lottie = try JSONDecoder().decode(Lottie.self, from: LottieExporter.export(scene: d.scenes[0]))
        let fill = try #require(lottie.layers.first?.shapes.first?.it.first { $0.ty == "gf" })
        return (try #require(fill.s?.k), try #require(fill.e?.k))
    }

    /// The issue's repro: center.x = 1e17 (ulp 16) with radius 1 is rejected,
    /// in the model and on load.
    @Test func issueReproIsRejected() {
        #expect(throws: FormatError.invalid(Self.message)) { try FlareFormat.validate(Self.doc(1e17, 1)) }
    }

    /// Both sides of the boundary: one ulp of center.x moves the edge, a
    /// quarter ulp does not. At x = ±1 the ulp toward zero is half the ulp away,
    /// so a radius of 0.75 · 2⁻⁵³ collapses only one edge; that is rejected too.
    @Test(arguments: [
        (1e17, 16, true), (1e17, 4, false), (-1e17, 16, true), (-1e17, 4, false),
        (1, 2 * 0x1p-53, true), (1, 0.75 * 0x1p-53, false), (-1, 0.75 * 0x1p-53, false),
        (0, Double.leastNonzeroMagnitude, true),
    ] as [(Double, Double, Bool)])
    func edgeMustDifferFromCenterOnBothSides(x: Double, r: Double, accepted: Bool) throws {
        let d = Self.doc(x, r)
        guard accepted else {
            #expect((x - r == x) || (x + r == x))
            #expect(throws: FormatError.invalid(Self.message)) { try FlareFormat.validate(d) }
            return
        }
        try FlareFormat.validate(d)
        let (s, e) = try Self.lottieStartAndEnd(d)
        #expect(s == [x, 0])
        #expect(e == [x + r, 0])
        #expect(e != s)
    }

    /// Seeded fuzz over magnitudes and radii near an ulp: validation accepts
    /// exactly when both edges are finite and differ from the center, and every
    /// accepted fill exports to Lottie with e != s.
    @Test(arguments: [UInt64(1), 235])
    func everyValidatedRadialExportsANonZeroLengthGradient(seed: UInt64) throws {
        var rng = SplitMix64(seed: seed)
        var (accepted, rejected) = (0, 0)
        for _ in 0..<400 {
            let x = (Bool.random(using: &rng) ? 1 : -1) * Double(sign: .plus, exponent: Int.random(in: -60...1000, using: &rng),
                                                                  significand: Double.random(in: 1..<2, using: &rng))
            let r = x.ulp * [0.25, 0.5, 0.75, 1, 1.5, 4][Int.random(in: 0...5, using: &rng)]
            let d = Self.doc(x, r)
            guard (x - r) < x, (x + r) > x else {
                rejected += 1
                #expect(throws: FormatError.invalid(Self.message), "\(x) \(r)") { try FlareFormat.validate(d) }
                continue
            }
            accepted += 1
            try FlareFormat.validate(d)
            let (s, e) = try Self.lottieStartAndEnd(d)
            #expect(e != s, "\(x) \(r)")
        }
        #expect(accepted > 100)
        #expect(rejected > 100)
    }
}
