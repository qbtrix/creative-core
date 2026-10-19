// RasterGradientTests.swift: fill-tools FT-5's acceptance, written first (FT-1);
// enabled by FT-5. A black-to-white ramp in linear light,
// dither off, makes each pixel's red its `t` (FT-6 checks dither on its own).
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

    @Test
    func shapesMatchAnalyticT() throws {
        for c in FillFixtures.gradientCases {
            let got = try t(try render(c.shape), c.x, c.y)
            #expect(abs(got - c.t) < 1e-6, "\(c.shape) at (\(c.x), \(c.y)): \(got), want \(c.t)")
        }
        for shape in [RasterGradientShape.linear, .radial, .angle, .reflected, .diamond] {
            let image = try render(shape), again = try render(shape)
            #expect(image.width == 32 && image.height == 24 && image == again)  // deterministic
            for y in 0..<24 {
                for x in 0..<32 {
                    let p = Mask.Point(x: Double(x) + 0.5, y: Double(y) + 0.5)
                    let want = FillFixtures.analyticT(shape, at: p, from: FillFixtures.gradientA, to: FillFixtures.gradientB)
                    #expect(abs(try t(image, x, y) - want) < 1e-5, "\(shape) at (\(x), \(y))")
                }
            }
        }
    }

    @Test
    func reflectedMirrors() throws {
        let image = try render(.reflected)
        for k in 1...9 {
            #expect(try t(image, 10 - k, 10) == t(image, 10 + k, 10), "k = \(k)")
            #expect(abs(try t(image, 10 - k, 10) - Double(k) / 10) < 1e-6, "k = \(k)")
        }
        #expect(try t(image, 10, 10) == 0)
    }

    /// With `b` straight below `a`, angle 0 points down, not along +x.
    @Test
    func angleStartsAtB() throws {
        let a = FillFixtures.gradientA, b = Mask.Point(x: 10.5, y: 20.5)
        let image = try render(.angle, from: a, to: b)
        for (x, y, want) in [(10, 15, 0.0), (5, 10, 0.25), (10, 5, 0.5), (15, 10, 0.75), (5, 15, 0.125)] {
            #expect(abs(try t(image, x, y) - want) < 1e-6, "(\(x), \(y))")
            let p = Mask.Point(x: Double(x) + 0.5, y: Double(y) + 0.5)
            #expect(abs(FillFixtures.analyticT(.angle, at: p, from: a, to: b) - want) < 1e-9)
        }
    }

    @Test
    func clampsPastEnd() throws {
        let linear = try render(.linear)
        for x in 20..<32 { #expect(try t(linear, x, 3) == 1, "x = \(x)") }
        for x in 0...10 { #expect(try t(linear, x, 20) == 0, "x = \(x)") }
        let radial = try render(.radial)
        #expect(try t(radial, 31, 23) == 1)
        #expect(try t(try render(.diamond), 0, 0) == 1)
    }

    /// Red to green at `t` = 0.5 (pixel (15, 10)): linear light gives the
    /// plain mean; perceptual gives the OKLab midpoint, which CoreColor states.
    @Test
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
        #expect(want.c0 - 0.5 > 0.1 && want.c1 - 0.5 < -0.1)  // about +0.13 red, -0.11 green off the linear mid
    }

    /// Three stops with a hard edge at 0.5 and a fading alpha: each segment
    /// mixes only its own two stops, the edge takes the later stop, and the
    /// output is premultiplied.
    @Test
    func stopsSegmentAndPremultiply() throws {
        let stops = [RasterGradientStop(offset: 0.2, color: RGBA(r: 1, g: 0, b: 0, a: 1)),
                     RasterGradientStop(offset: 0.5, color: RGBA(r: 0, g: 1, b: 0, a: 1)),
                     RasterGradientStop(offset: 0.5, color: RGBA(r: 0, g: 0, b: 1, a: 1)),
                     RasterGradientStop(offset: 1, color: RGBA(r: 0, g: 0, b: 1, a: 0))]
        let image = try PixelBuffer.gradient(width: 32, height: 24, shape: .linear, from: FillFixtures.gradientA,
                                             to: FillFixtures.gradientB, stops: stops, space: .linear, dither: false)
        let cases: [(Int, RGBA)] = [(10, RGBA(r: 1, g: 0, b: 0, a: 1)), (11, RGBA(r: 1, g: 0, b: 0, a: 1)),
                                    (13, RGBA(r: 2.0 / 3, g: 1.0 / 3, b: 0, a: 1)), (15, RGBA(r: 0, g: 0, b: 1, a: 1)),
                                    (18, RGBA(r: 0, g: 0, b: 0.4, a: 0.4)), (25, .clear)]
        for (x, want) in cases {
            let got = try image.pixel(x: x, y: 10)
            #expect(abs(got.r - want.r) < 1e-6 && abs(got.g - want.g) < 1e-6 && abs(got.b - want.b) < 1e-6
                        && abs(got.a - want.a) < 1e-6, "x = \(x): \(got), want \(want)")
        }
    }

    /// The eyedropper flow: `sampledColor` is premultiplied, a stop is
    /// straight alpha, so `.unpremultiplied()` round-trips a 50%-alpha colour.
    /// Passing the sampled value directly premultiplies twice: darker.
    @Test
    func sampledStopRoundTrips() throws {
        let source = try PixelBuffer(width: 4, height: 4, fill: RGBA(r: 0.3, g: 0.2, b: 0.1, a: 0.5))
        let sampled = try source.sampledColor(at: (x: 1, y: 1), radius: 1)
        func render(_ color: RGBA) throws -> PixelBuffer {
            try PixelBuffer.gradient(width: 8, height: 8, shape: .linear, from: Mask.Point(x: 0, y: 0),
                                     to: Mask.Point(x: 8, y: 0), stops: [RasterGradientStop(offset: 0, color: color),
                                     RasterGradientStop(offset: 1, color: color)], space: .linear, dither: false)
        }
        let image = try render(sampled.unpremultiplied())
        for y in 0..<8 {
            for x in 0..<8 {
                let got = try image.pixel(x: x, y: y)
                #expect(abs(got.r - sampled.r) < 1e-6 && abs(got.g - sampled.g) < 1e-6 && abs(got.b - sampled.b) < 1e-6
                            && abs(got.a - sampled.a) < 1e-6, "(\(x), \(y)): \(got), want \(sampled)")
            }
        }
        let doubled = try render(sampled).pixel(x: 3, y: 3)
        #expect(abs(doubled.r - sampled.r / 2) < 1e-6 && doubled.a == sampled.a)  // premultiplied twice
    }

    /// The stop limit is inclusive: 64 stops render, 65 throw.
    @Test
    func sixtyFourStopsAccepted() throws {
        let stops = (0..<64).map { RasterGradientStop(offset: Float($0) / 63, color: Self.white) }
        let image = try PixelBuffer.gradient(width: 8, height: 8, shape: .linear, from: FillFixtures.gradientA,
                                             to: FillFixtures.gradientB, stops: stops)
        #expect(image.width == 8 && image.height == 8)
    }

    @Test
    func badStopsPointsOrSizeThrow() {
        let (a, b) = (FillFixtures.gradientA, FillFixtures.gradientB)
        let red = RGBA(r: 1, g: 0, b: 0, a: 1)
        func stop(_ offset: Float, _ color: RGBA = red) -> RasterGradientStop { RasterGradientStop(offset: offset, color: color) }
        let badStops: [[RasterGradientStop]] = [
            [], [stop(0)], [stop(0.8), stop(0.2)], [stop(-0.1), stop(1)], [stop(0), stop(1.1)],
            [stop(0), stop(.nan)], [stop(0), stop(1, RGBA(r: .infinity, g: 0, b: 0, a: 1))],
            (0...64).map { stop(Float($0) / 64) },
        ]
        let nan = Mask.Point(x: .nan, y: 0), inf = Mask.Point(x: 1, y: .infinity)
        let cases = badStops.map { (8, 8, a, b, $0) } + [(8, 8, a, a, Self.ramp), (8, 8, nan, b, Self.ramp),
            (8, 8, a, inf, Self.ramp), (0, 8, a, b, Self.ramp), (8, 0, a, b, Self.ramp), (-1, 4, a, b, Self.ramp),
            (Int.max, 2, a, b, Self.ramp)]
        for (w, h, p, q, stops) in cases {
            #expect(throws: RasterError.self) {
                try PixelBuffer.gradient(width: w, height: h, shape: .radial, from: p, to: q, stops: stops)
            }
        }
    }
}
