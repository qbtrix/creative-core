// EasingTests.swift: known values, exact endpoints, monotonicity, hostile
// input, and a seeded property test of the cubic-bezier solver.
@testable import FlareCore
import Foundation
import Testing

@Suite struct EasingTests {
    @Test func easeInOutIsSymmetricAtHalf() {
        #expect(abs(Easing.easeInOut.value(at: 0.5) - 0.5) < 1e-9)
    }

    @Test func cssEaseKnownValue() {
        // CSS `ease` at 50% progress is ~0.8024 (as rendered by browsers).
        #expect(abs(Easing.ease.value(at: 0.5) - 0.8024) < 1e-3)
    }

    @Test(arguments: [Easing.linear, .ease, .easeIn, .easeOut, .easeInOut,
                      .cubicBezier(x1: 0, y1: 1.5, x2: 1, y2: -0.5)])
    func endpointsAreExact(_ easing: Easing) {
        #expect(easing.value(at: 0) == 0)
        #expect(easing.value(at: 1) == 1)
        #expect(easing.value(at: -3) == 0)
        #expect(easing.value(at: 7) == 1)
    }

    @Test(arguments: [Easing.linear, .ease, .easeIn, .easeOut, .easeInOut,
                      .cubicBezier(x1: 1, y1: 0, x2: 0, y2: 1)])
    func monotonicWhenControlPointsStayInUnitBox(_ easing: Easing) {
        var previous = -Double.infinity
        for i in 0...1000 {
            let v = easing.value(at: Double(i) / 1000)
            #expect(v >= previous - 1e-12, "dropped at \(i)")
            previous = v
        }
    }

    @Test func hostileInputNeverCrashesOrEscapes() {
        #expect(Easing.easeInOut.value(at: .nan) == 0)
        #expect(Easing.easeInOut.value(at: .infinity) == 1)
        #expect(Easing.easeInOut.value(at: -.infinity) == 0)
        // Out-of-range x control points are clamped; non-finite ones fall back to linear.
        let wild = Easing.cubicBezier(x1: -5, y1: 0, x2: 9, y2: 1).value(at: 0.3)
        #expect(wild.isFinite)
        #expect(Easing.cubicBezier(x1: .nan, y1: 0, x2: 1, y2: 1).value(at: 0.3) == 0.3)
    }

    @Test func solverFindsParameterForRandomCurves() {
        var rng = SplitMix64(seed: 42)
        for _ in 0..<2000 {
            let curve = CubicBezier(
                x1: .random(in: 0...1, using: &rng), y1: .random(in: -1...2, using: &rng),
                x2: .random(in: 0...1, using: &rng), y2: .random(in: -1...2, using: &rng))
            guard let curve else { Issue.record("finite control points rejected"); return }
            let x = Double.random(in: 0...1, using: &rng)
            let s = curve.parameter(forX: x)
            #expect(s >= 0 && s <= 1)
            #expect(abs(curve.x(s) - x) < 1e-9)
        }
    }

    @Test func easingRoundTripsThroughCodable() throws {
        for e in [Easing.linear, .easeInOut] {
            let data = try JSONEncoder().encode(e)
            #expect(try JSONDecoder().decode(Easing.self, from: data) == e)
        }
    }
}
