// DevelopSpeedTests.swift: contrast and highlights/shadows on a 24-megapixel
// buffer (issue #255), and their outputs pinned to the values they gave
// before the loop was made fast, so the speed-up changed no result.
import CoreRaster
import Testing

#if DEBUG
private let isReleaseBuild = false
#else
private let isReleaseBuild = true
#endif

/// The shortest of `runs` timed calls of `body`, and the last result.
private func fastest(of runs: Int, _ body: () throws -> PixelBuffer) throws -> (Duration, PixelBuffer) {
    let clock = ContinuousClock()
    var best = Duration.seconds(Int64.max)
    var result: PixelBuffer?
    for _ in 0..<runs {
        var out: PixelBuffer?
        best = min(best, try clock.measure { out = try body() })
        result = out
    }
    return (best, try #require(result))
}

/// A 1-row opaque buffer holding `pixels`, premultiplied.
private func row(_ pixels: [RGBA]) throws -> PixelBuffer {
    var buffer = try PixelBuffer(width: pixels.count, height: 1)
    for (x, p) in pixels.enumerated() {
        try buffer.setPixel(x: x, y: 0, p.premultiplied())
    }
    return buffer
}

private func close(_ got: Float, _ want: Float) -> Bool {
    abs(got - want) <= 1e-6 * max(1, abs(want))
}

/// The 1 s target is for release builds; a debug build is many times slower,
/// so the 24-megapixel run is skipped there.
@Test(.enabled(if: isReleaseBuild, "the 1 s target is for release builds"))
func contrastAndHighlightsShadowsOn24MegapixelsMeetTheOneSecondTarget() throws {
    let width = 6000, height = 4000
    let fill = RGBA(r: 0.3, g: 0.4, b: 0.5, a: 1)
    let buffer = try PixelBuffer(width: width, height: height, fill: fill)
    let small = try PixelBuffer(width: 1, height: 1, fill: fill)
    let calls: [(String, (PixelBuffer) throws -> PixelBuffer)] = [
        ("whiteBalance", { try $0.whiteBalance(temperature: 30, tint: 10) }),
        ("contrast", { try $0.contrast(40) }),
        ("highlightsShadows", { try $0.highlightsShadows(highlights: -50, shadows: 50) }),
    ]
    var total = Duration.zero
    for (name, call) in calls {
        let (time, result) = try fastest(of: 3) { try call(buffer) }
        total += time
        print("\(name) on \(width)x\(height): \(time)")
        if name != "whiteBalance" {
            #expect(time < .seconds(1), "\(name) took \(time)")
        }
        let expected = try call(small).pixel(x: 0, y: 0)
        for (x, y) in [(0, 0), (width - 1, height - 1), (width / 2, height / 3)] {
            #expect(try result.pixel(x: x, y: y) == expected, "\(name) at (\(x), \(y))")
        }
    }
    print("develop sliders on \(width)x\(height): total \(total)")
}

@Test func contrastKeepsItsOutputs() throws {
    let values: [Float] = [-0.5, -0.01, 0, 0.001, 0.02, 0.05, 0.09, 0.12, 0.18, 0.25, 0.4, 0.59, 0.75, 0.9, 1, 1.5, 4]
    let expected: [Float: [Float]] = [
        -100: [-0.25, -0.005, 0, 0.0015054939, 0.031728394, 0.08117284, 0.135, 0.15666667, 0.18,
               0.21004462, 0.26264724, 0.385, 0.5952558, 0.84077924, 1, 1.25, 2.5],
        -40: [-0.4, -0.008, 0, 0.0012021976, 0.024691358, 0.06246914, 0.10800001, 0.13466667, 0.18,
              0.23401785, 0.3450589, 0.50799996, 0.6881023, 0.87631166, 1, 1.4, 3.4],
        40: [-0.6, -0.012, 0, 0.0007978025, 0.015308642, 0.037530866, 0.072000004, 0.10533333, 0.18,
             0.26598215, 0.45494112, 0.672, 0.8118977, 0.9236883, 1, 1.6, 4.6000004],
        100: [-0.75, -0.015, 0, 0.0004945062, 0.008271605, 0.01882716, 0.045, 0.08333333, 0.18,
              0.28995538, 0.53735274, 0.79499996, 0.9047442, 0.9592207, 1, 1.75, 5.5],
    ]
    let buffer = try row(values.map { RGBA(r: $0, g: $0, b: $0, a: 1) })
    for (amount, want) in expected {
        let out = try buffer.contrast(amount)
        for (x, w) in want.enumerated() {
            let p = try out.pixel(x: x, y: 0)
            #expect(close(p.r, w) && p.g == p.r && p.b == p.r, "contrast \(amount) at \(values[x]): \(p.r), want \(w)")
        }
    }
}

/// Inside 0...1 contrast is the monotone curve through its five points, so
/// it must agree with `curves` on those points at any value.
@Test func contrastMatchesItsCurveInsideZeroToOne() throws {
    var rng = SplitMix64(seed: 255)
    let values = (0..<200).map { _ in Float(rng.next() % 1_000_001) / 1_000_000 }
    let buffer = try row(values.map { RGBA(r: $0, g: $0, b: $0, a: 1) })
    for amount: Float in [-100, -63, -7.5, 12, 55, 100] {
        let push = amount / 200
        let curve = try buffer.curves(points: [
            CurvePoint(x: 0, y: 0),
            CurvePoint(x: 0.09, y: 0.09 * (1 - push)),
            CurvePoint(x: 0.18, y: 0.18),
            CurvePoint(x: 0.59, y: 0.59 + 0.41 * push),
            CurvePoint(x: 1, y: 1),
        ])
        let out = try buffer.contrast(amount)
        for x in values.indices {
            let got = try out.pixel(x: x, y: 0).r, want = try curve.pixel(x: x, y: 0).r
            #expect(close(got, want), "contrast \(amount) at \(values[x]): \(got), want \(want)")
        }
    }
}

@Test func highlightsShadowsKeepItsOutputs() throws {
    let pixels = [
        RGBA(r: 0.02, g: 0.03, b: 0.01, a: 1), RGBA(r: 0.1, g: 0.2, b: 0.05, a: 1),
        RGBA(r: 0.3, g: 0.4, b: 0.5, a: 1), RGBA(r: 0.7, g: 0.8, b: 0.6, a: 1),
        RGBA(r: 1.2, g: 0.9, b: 2, a: 1), RGBA(r: 0.2, g: 0.3, b: 0.4, a: 0.5),
    ]
    let expected: [(Float, Float, [RGBA])] = [
        (-50, 50, [
            RGBA(r: 0.028205106, g: 0.04230766, b: 0.014102553, a: 1),
            RGBA(r: 0.12911974, g: 0.25823948, b: 0.06455987, a: 1),
            RGBA(r: 0.29738748, g: 0.39651662, b: 0.49564576, a: 1),
            RGBA(r: 0.5305682, g: 0.60636365, b: 0.45477274, a: 1),
            RGBA(r: 0.84852815, g: 0.63639605, b: 1.4142135, a: 1),
            RGBA(r: 0.11278249, g: 0.16917375, b: 0.22556499, a: 0.5),
        ]),
        (100, -100, [
            RGBA(r: 0.010056213, g: 0.01508432, b: 0.0050281063, a: 1),
            RGBA(r: 0.059981145, g: 0.11996229, b: 0.029990572, a: 1),
            RGBA(r: 0.30529416, g: 0.40705886, b: 0.5088236, a: 1),
            RGBA(r: 1.2184612, g: 1.3925271, b: 1.0443953, a: 1),
            RGBA(r: 2.4, g: 1.8, b: 4, a: 1),
            RGBA(r: 0.07861703, g: 0.11792555, b: 0.15723406, a: 0.5),
        ]),
        (-100, 100, [
            RGBA(r: 0.039776403, g: 0.059664603, b: 0.019888202, a: 1),
            RGBA(r: 0.16671906, g: 0.33343813, b: 0.08335953, a: 1),
            RGBA(r: 0.29479766, g: 0.39306355, b: 0.49132943, a: 1),
            RGBA(r: 0.40214655, g: 0.45959607, b: 0.34469706, a: 1),
            RGBA(r: 0.6, g: 0.45, b: 1, a: 1),
            RGBA(r: 0.1271989, g: 0.19079836, b: 0.2543978, a: 0.5),
        ]),
    ]
    let buffer = try row(pixels)
    for (highlights, shadows, want) in expected {
        let out = try buffer.highlightsShadows(highlights: highlights, shadows: shadows)
        for (x, w) in want.enumerated() {
            let p = try out.pixel(x: x, y: 0)
            #expect(close(p.r, w.r) && close(p.g, w.g) && close(p.b, w.b) && p.a == w.a,
                    "highlights \(highlights) shadows \(shadows) at \(x): \(p), want \(w)")
        }
    }
}
