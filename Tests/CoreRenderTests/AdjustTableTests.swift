// AdjustTableTests.swift: the Metal adjust kernel's data (MB-13, MB-14) maps the parity samples as the CPU
// backend does within `.standard` for every case (develop sliders included), reads a straight curve exactly
// (table endpoint and square-root index) and extends it along its line, keeps exposure and white balance as
// their factors, matches contrast and highlights/shadows outside 0...1, and throws the CPU's errors.
import CoreRaster
import CoreRender
import Testing

@Suite struct AdjustTableTests {
    /// The MB-13 rows: exposure at -2, 0, +2 EV, levels with black, white and gamma points, curves through
    /// 3 and 5 points, in linear and sRGB encodings.
    static let adjustments: [ToneAdjustment] = [
        .exposure(stops: -2), .exposure(stops: 0), .exposure(stops: 2),
        .levels(inBlack: 0.1, inWhite: 0.9, gamma: 1.6, outBlack: 0.05, outWhite: 0.95),
        .levels(inBlack: 0.05, inWhite: 0.8, gamma: 0.7, outBlack: 0, outWhite: 1, encoding: .sRGB),
        .curves(points: [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.4, y: 0.6), CurvePoint(x: 1, y: 1)]),
        .curves(points: [CurvePoint(x: 0, y: 0.05), CurvePoint(x: 0.25, y: 0.2), CurvePoint(x: 0.5, y: 0.55),
                         CurvePoint(x: 0.75, y: 0.8), CurvePoint(x: 1, y: 0.95)], encoding: .sRGB),
    ]

    /// The MB-14 rows: white balance warm, cool and tinted, contrast at the slider's ends and 0, and a
    /// highlights/shadows grid over the slider's ends and 0.
    static let develop: [ToneAdjustment] = [
        .whiteBalance(temperature: 60, tint: 0), .whiteBalance(temperature: -60, tint: 0),
        .whiteBalance(temperature: 0, tint: 45), .whiteBalance(temperature: -100, tint: -100),
        .contrast(-100), .contrast(0), .contrast(100),
    ] + [-100, 0, 100].flatMap { h in [-100, 0, 100].map { ToneAdjustment.highlightsShadows(highlights: Float(h), shadows: Float($0)) } }

    @Test func mapsTheParitySamplesAsTheCPUDoes() throws {
        let cpu = CPUBackend()
        for sample in try ParityHarness.sampleSet(for: .adjust) {
            for adjustment in Self.adjustments + Self.develop {
                let table = try AdjustTable(adjustment)
                let source = sample.source
                var got = try PixelBuffer(width: source.width, height: source.height)
                for y in 0..<source.height {
                    for x in 0..<source.width { try got.setPixel(x: x, y: y, table.map(try source.pixel(x: x, y: y))) }
                }
                let want = try cpu.read(cpu.adjusted(cpu.surface(source), adjustment))
                let result = try ParityHarness.compare(got, want, tolerance: .standard)
                #expect(result.passed, "\(sample.name) \(adjustment): \(result)")
            }
        }
    }

    @Test func aStraightCurveIsExactAndExtendsAlongItsLine() throws {
        let table = try AdjustTable(.curves(points: [CurvePoint(x: 0, y: 0.1), CurvePoint(x: 1, y: 0.9)]))
        #expect(table.values.count == AdjustTable.steps + 1 && table.kind == .channel && table.gains == SIMD3(repeating: 1))
        for k in -50...150 {
            let v = Float(k) / 100 + 0.003
            #expect(abs(table.apply(v) - (0.1 + 0.8 * v)) < 1e-5, "v \(v): \(table.apply(v))")
        }
        #expect(table.map(RGBA(r: 0.5, g: 0.5, b: 0.5, a: 0)) == .clear, "alpha 0 gives zeros")
    }

    @Test func exposureKeepsItsFactor() throws {
        let table = try AdjustTable(.exposure(stops: 2))
        #expect(table.values.isEmpty && table.kind == .gains && table.gains == SIMD3(repeating: 4))
        #expect(table.map(RGBA(r: 0.3, g: 0.1, b: 0.2, a: 1)) == RGBA(r: 0.3 * 4, g: 0.1 * 4, b: 0.2 * 4, a: 1))
        #expect(try AdjustTable(.exposure(stops: 0)).map(RGBA(r: 0.7, g: 0.2, b: 0.1, a: 0.5)) == RGBA(r: 0.7, g: 0.2, b: 0.1, a: 0.5))
    }

    /// Warm raises red over blue, cool the reverse, magenta tint lowers green; the factors are the CPU's own.
    @Test func whiteBalanceKeepsTheCPUsGainsWithTheirSigns() throws {
        let cpu = CPUBackend()
        for (temperature, tint) in [(Float(60), Float(0)), (-60, 0), (0, 45), (-100, -100)] {
            let table = try AdjustTable(.whiteBalance(temperature: temperature, tint: tint))
            let white = try cpu.read(cpu.adjusted(cpu.surface(PixelBuffer(width: 1, height: 1, fill: RGBA(r: 1, g: 1, b: 1, a: 1))),
                                                  .whiteBalance(temperature: temperature, tint: tint))).pixel(x: 0, y: 0)
            #expect(table.kind == .gains && table.values.isEmpty && table.gains == SIMD3(white.r, white.g, white.b))
            #expect(temperature == 0 || (table.gains.x > table.gains.z) == (temperature > 0), "\(temperature): \(table.gains)")
            #expect(tint <= 0 || table.gains.y < table.gains.x, "\(tint): \(table.gains)")
            #expect(table.map(RGBA(r: 2, g: -0.5, b: 3, a: 1)).r == 2 * table.gains.x, "unclipped values scale too")
        }
    }

    /// Contrast is a line from 0 and 1 outside 0...1, and highlights/shadows a constant gain there: the table
    /// matches the CPU on far values, so the secant is exact for both (the MB-13 gap does not reach MB-14).
    @Test func developSlidersMatchTheCPUOutsideZeroToOne() throws {
        let cpu = CPUBackend()
        let values: [Float] = [-40, -3, -1, -0.25, -1e-3, 1.001, 1.5, 2, 7, 300]
        var probe = try PixelBuffer(width: values.count, height: 1)
        for (i, v) in values.enumerated() { try probe.setPixel(x: i, y: 0, RGBA(r: v, g: v * 0.5, b: -v, a: 1)) }
        for adjustment in [ToneAdjustment.contrast(-100), .contrast(55), .contrast(100),
                           .highlightsShadows(highlights: -100, shadows: 100), .highlightsShadows(highlights: 70, shadows: -30)] {
            let table = try AdjustTable(adjustment)
            let want = try cpu.read(cpu.adjusted(cpu.surface(probe), adjustment))
            for i in values.indices {
                let (got, w) = (table.map(try probe.pixel(x: i, y: 0)), try want.pixel(x: i, y: 0))
                for (a, b) in [(got.r, w.r), (got.g, w.g), (got.b, w.b)] {
                    #expect(abs(a - b) <= 1e-5 * max(1, abs(b)), "\(adjustment) at \(values[i]): \(got) vs \(w)")
                }
            }
        }
        let shadows = try AdjustTable(.highlightsShadows(highlights: 0, shadows: 100))
        #expect(shadows.kind == .luma && shadows.below == 0 && shadows.above == 0)
        #expect(abs(shadows.apply(0) - 2) < 1e-6 && abs(shadows.apply(1) - 1) < 1e-6, "shadows lift the dark end only")
    }

    @Test func throwsTheCPUsErrors() throws {
        let cpu = CPUBackend()
        let surface = try cpu.surface(PixelBuffer(width: 2, height: 2))
        for bad in [ToneAdjustment.exposure(stops: .nan), .levels(inBlack: 0.5, inWhite: 0.5, gamma: 1, outBlack: 0, outWhite: 1),
                    .curves(points: [CurvePoint(x: 0, y: 0)]), .whiteBalance(temperature: 101, tint: 0),
                    .contrast(.nan), .highlightsShadows(highlights: 0, shadows: -100.5)] {
            do {
                _ = try cpu.adjusted(surface, bad)
                Issue.record("the CPU accepts \(bad)")
            } catch let expected as RenderError {
                #expect(throws: expected) { try AdjustTable(bad) }
            }
        }
    }
}
