// RasterGradientTests.swift: fill-tools FT-5's acceptance, written first
// (FT-1 of docs/blueprints/core/features/fill-tools.md). Every case waits on
// FT-5, which removes the `.disabled` traits when `PixelBuffer.gradient` is
// built. A black-to-white ramp in linear light makes each pixel's red its `t`;
// dither is off so values are exact (FT-6 checks dither in its own suite).
import CoreColor
import CoreRaster
import Testing

@Suite struct RasterGradientTests {
    private static let black = RGBA(r: 0, g: 0, b: 0, a: 1)
    private static let white = RGBA(r: 1, g: 1, b: 1, a: 1)
    private static let ramp = [RasterGradientStop(offset: 0, color: black), RasterGradientStop(offset: 1, color: white)]

    /// A 32 x 24 ramp of `shape`, so each pixel's red is its `t`.
    private func render(_ shape: RasterGradientShape, from a: Mask.Point = FillFixtures.gradientA,
                        to b: Mask.Point = FillFixtures.gradientB) throws -> PixelBuffer {
        try PixelBuffer.gradient(width: 32, height: 24, shape: shape, from: a, to: b, stops: Self.ramp,
                                 space: .linear, dither: false)
    }

    private func t(_ image: PixelBuffer, _ x: Int, _ y: Int) throws -> Double { Double(try image.pixel(x: x, y: y).r) }

    @Test(.disabled("waits on FT-5"))
    func shapesMatchAnalyticT() throws {
        for c in FillFixtures.gradientCases {
            let got = try t(try render(c.shape), c.x, c.y)
            #expect(abs(got - c.t) < 1e-6, "\(c.shape) at (\(c.x), \(c.y)): \(got), want \(c.t)")
        }
        for shape in [RasterGradientShape.linear, .radial, .angle, .reflected, .diamond] {
            let image = try render(shape)
            #expect(image.width == 32 && image.height == 24)
            for y in 0..<24 {
                for x in 0..<32 {
                    let p = Mask.Point(x: Double(x) + 0.5, y: Double(y) + 0.5)
                    let want = FillFixtures.analyticT(shape, at: p, from: FillFixtures.gradientA, to: FillFixtures.gradientB)
                    #expect(abs(try t(image, x, y) - want) < 1e-5, "\(shape) at (\(x), \(y))")
                }
            }
        }
    }

    @Test(.disabled("waits on FT-5"))
    func reflectedMirrors() throws {
        let image = try render(.reflected)
        for k in 1...9 {
            #expect(try t(image, 10 - k, 10) == t(image, 10 + k, 10), "k = \(k)")
            #expect(abs(try t(image, 10 - k, 10) - Double(k) / 10) < 1e-6, "k = \(k)")
        }
        #expect(try t(image, 10, 10) == 0)
    }

    /// With `b` straight below `a`, angle 0 points down, not along +x.
    @Test(.disabled("waits on FT-5"))
    func angleStartsAtB() throws {
        let a = FillFixtures.gradientA, b = Mask.Point(x: 10.5, y: 20.5)
        let image = try render(.angle, from: a, to: b)
        for (x, y, want) in [(10, 15, 0.0), (5, 10, 0.25), (10, 5, 0.5), (15, 10, 0.75), (5, 15, 0.125)] {
            #expect(abs(try t(image, x, y) - want) < 1e-6, "(\(x), \(y))")
            let p = Mask.Point(x: Double(x) + 0.5, y: Double(y) + 0.5)
            #expect(abs(FillFixtures.analyticT(.angle, at: p, from: a, to: b) - want) < 1e-9)
        }
    }

    @Test(.disabled("waits on FT-5"))
    func clampsPastEnd() throws {
        let linear = try render(.linear)
        for x in 20..<32 { #expect(try t(linear, x, 3) == 1, "x = \(x)") }
        for x in 0...10 { #expect(try t(linear, x, 20) == 0, "x = \(x)") }
        let radial = try render(.radial)
        #expect(try t(radial, 31, 23) == 1)
        let diamond = try render(.diamond)
        #expect(try t(diamond, 0, 0) == 1)
        for shape in [RasterGradientShape.linear, .radial, .angle, .reflected, .diamond] {
            let image = try render(shape)
            for y in 0..<24 {
                for x in 0..<32 { #expect((0...1).contains(try image.pixel(x: x, y: y).r), "\(shape) (\(x), \(y))") }
            }
        }
    }

    /// Red to green at `t` = 0.5 (pixel (15, 10)): linear light gives the
    /// plain mean; perceptual gives the OKLab midpoint, which CoreColor states.
    @Test(.disabled("waits on FT-5"))
    func stopsInterpolateInOKLab() throws {
        let red = RGBA(r: 1, g: 0, b: 0, a: 1), green = RGBA(r: 0, g: 1, b: 0, a: 1)
        let stops = [RasterGradientStop(offset: 0, color: red), RasterGradientStop(offset: 1, color: green)]
        func mid(_ space: GradientSpace) throws -> RGBA {
            try PixelBuffer.gradient(width: 32, height: 24, shape: .linear, from: FillFixtures.gradientA,
                                     to: FillFixtures.gradientB, stops: stops, space: space, dither: false).pixel(x: 15, y: 10)
        }
        let lr = try Color3(1, 0, 0).converted(from: .linearSRGB, to: .oklab)
        let lg = try Color3(0, 1, 0).converted(from: .linearSRGB, to: .oklab)
        let want = try Color3((lr.c0 + lg.c0) / 2, (lr.c1 + lg.c1) / 2, (lr.c2 + lg.c2) / 2)
            .converted(from: .oklab, to: .linearSRGB)
        let linear = try mid(.linear), perceptual = try mid(.perceptual)
        #expect(abs(linear.r - 0.5) < 1e-6 && abs(linear.g - 0.5) < 1e-6 && abs(linear.b) < 1e-6)
        for (got, w) in [(perceptual.r, want.c0), (perceptual.g, want.c1), (perceptual.b, want.c2)] {
            #expect(abs(Double(got) - w) < 1e-4, "perceptual mid \(perceptual), want \(want)")
        }
        // About +0.13 red and -0.11 green against the linear midpoint.
        #expect(abs(Double(perceptual.r - linear.r) - (want.c0 - 0.5)) < 1e-4)
        #expect(abs(Double(perceptual.g - linear.g) - (want.c1 - 0.5)) < 1e-4)
        #expect(want.c0 - 0.5 > 0.1 && want.c1 - 0.5 < -0.1)
    }

    @Test(.disabled("waits on FT-5"))
    func badStopsPointsOrSizeThrow() {
        let (a, b) = (FillFixtures.gradientA, FillFixtures.gradientB)
        let red = RGBA(r: 1, g: 0, b: 0, a: 1)
        func stop(_ offset: Float, _ color: RGBA = red) -> RasterGradientStop { RasterGradientStop(offset: offset, color: color) }
        let badStops: [[RasterGradientStop]] = [
            [], [stop(0)], [stop(0.8), stop(0.2)], [stop(-0.1), stop(1)], [stop(0), stop(1.1)],
            [stop(0), stop(.nan)], [stop(0), stop(1, RGBA(r: .infinity, g: 0, b: 0, a: 1))],
            (0...64).map { stop(Float($0) / 64) },
        ]
        for stops in badStops {
            #expect(throws: RasterError.self) {
                try PixelBuffer.gradient(width: 8, height: 8, shape: .linear, from: a, to: b, stops: stops)
            }
        }
        let points = [(a, a), (Mask.Point(x: .nan, y: 0), b), (a, Mask.Point(x: 1, y: .infinity))]
        for (p, q) in points {
            #expect(throws: RasterError.self) {
                try PixelBuffer.gradient(width: 8, height: 8, shape: .radial, from: p, to: q, stops: Self.ramp)
            }
        }
        for (w, h) in [(0, 8), (8, 0), (-1, 4), (Int.max, 2)] {
            #expect(throws: RasterError.self) {
                try PixelBuffer.gradient(width: w, height: h, shape: .diamond, from: a, to: b, stops: Self.ramp)
            }
        }
    }

    @Test(.disabled("waits on FT-5"))
    func deterministicAcrossRuns() throws {
        for shape in [RasterGradientShape.linear, .radial, .angle, .reflected, .diamond] {
            #expect(try render(shape) == render(shape))
        }
    }
}
