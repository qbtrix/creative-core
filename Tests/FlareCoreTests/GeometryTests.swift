// GeometryTests.swift: known matrix values, composition order, and a seeded
// property test that m * m.inverted() is the identity.
@testable import FlareCore
import Foundation
import Testing

private func close(_ m: Matrix, _ n: Matrix, _ tol: Double) -> Bool {
    abs(m.a - n.a) < tol && abs(m.b - n.b) < tol && abs(m.c - n.c) < tol
        && abs(m.d - n.d) < tol && abs(m.tx - n.tx) < tol && abs(m.ty - n.ty) < tol
}

@Suite struct GeometryTests {
    @Test func rotate90MapsXAxisToYAxis() {
        let p = Transform(rotation: 90).matrix.apply(Point(x: 1, y: 0))
        #expect(abs(p.x - 0) < 1e-12)
        #expect(abs(p.y - 1) < 1e-12)
    }

    @Test func rotate45KnownValue() {
        let p = Matrix.rotation(degrees: 45).apply(Point(x: 1, y: 0))
        #expect(abs(p.x - 0.5.squareRoot()) < 1e-12)
        #expect(abs(p.y - 0.5.squareRoot()) < 1e-12)
    }

    @Test func identityLeavesPointsAlone() {
        #expect(Matrix.identity.apply(Point(x: 3, y: -4)) == Point(x: 3, y: -4))
        #expect(Transform.identity.matrix == .identity)
    }

    @Test func transformScalesThenRotatesThenTranslates() {
        // (1, 0) scaled by 2 -> (2, 0), rotated 90 -> (0, 2), moved -> (10, 22).
        let t = Transform(x: 10, y: 20, scaleX: 2, scaleY: 3, rotation: 90)
        let p = t.matrix.apply(Point(x: 1, y: 0))
        #expect(abs(p.x - 10) < 1e-12)
        #expect(abs(p.y - 22) < 1e-12)
    }

    @Test func multiplyAppliesRightOperandFirst() {
        let m = Matrix.translation(x: 5, y: 0)
        let n = Matrix.scale(x: 2, y: 2)
        let p = Point(x: 1, y: 1)
        #expect((m * n).apply(p) == m.apply(n.apply(p)))
        #expect((m * n).apply(p) == Point(x: 7, y: 2))
        #expect((n * m).apply(p) == Point(x: 12, y: 2))
    }

    @Test func inverseOfRandomTransformsIsIdentity() throws {
        var rng = SplitMix64(seed: 11)
        for _ in 0..<1000 {
            let sx = Double.random(in: 0.05...20, using: &rng) * (Bool.random(using: &rng) ? 1 : -1)
            let sy = Double.random(in: 0.05...20, using: &rng) * (Bool.random(using: &rng) ? 1 : -1)
            let t = Transform(
                x: Double.random(in: -1000...1000, using: &rng),
                y: Double.random(in: -1000...1000, using: &rng),
                scaleX: sx, scaleY: sy,
                rotation: Double.random(in: -720...720, using: &rng)
            )
            let m = t.matrix
            let inv = try m.inverted()
            #expect(close(m * inv, .identity, 1e-9))
            #expect(close(inv * m, .identity, 1e-9))
        }
    }

    @Test(arguments: [Transform(scaleX: 0), Transform(scaleY: 0), Transform(scaleX: 0, scaleY: 0)])
    func zeroScaleInversionThrows(_ t: Transform) {
        #expect(throws: GeometryError.singularMatrix) { try t.matrix.inverted() }
    }

    @Test func degenerateMatricesThrowInsteadOfReturningNonFinite() {
        let tiny = Matrix.scale(x: 1e-200, y: 1e-200)
        #expect(throws: GeometryError.singularMatrix) { try tiny.inverted() }
        let nan = Transform(rotation: .nan).matrix
        #expect(throws: GeometryError.singularMatrix) { try nan.inverted() }
        let inf = Matrix.scale(x: .infinity, y: 1)
        #expect(throws: GeometryError.singularMatrix) { try inf.inverted() }
    }

    @Test func roundTripsThroughJSON() throws {
        let t = Transform(x: 1, y: 2, scaleX: 3, scaleY: 4, rotation: 30)
        let data = try JSONEncoder().encode(t)
        #expect(try JSONDecoder().decode(Transform.self, from: data) == t)
    }
}
