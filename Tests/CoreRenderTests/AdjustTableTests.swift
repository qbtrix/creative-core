// AdjustTableTests.swift: the Metal adjust kernel's data (MB-13, MB-14) maps the parity samples as the CPU
// backend does within `.standard` for every case (develop sliders included), reads a straight curve exactly
// (table endpoint and square-root index) and extends it along its line, keeps exposure and white balance as
// their factors, matches every case outside 0...1 (levels with a gamma, sRGB levels and curves through the
// octave tables), builds tables for extreme valid parameters the CPU accepts on 0...1, and throws the CPU's
// errors.
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
        // The octave edges: under 2^octaveMin (only below 0; 0...1 is the main table) the line from f(0), past
        // 2^octaveMax the last interval's line.
        for v: Float in [-1e-9, 0x1p41, -0x1p41] {
            #expect(abs(table.apply(v) - (0.1 + 0.8 * v)) <= 1e-5 * max(1, abs(v)), "v \(v): \(table.apply(v))")
        }
        // Between -2^-24 and 0, through the origin so the step is not lost under f(0)'s rounding: the line from
        // f(0) to the entry at -2^-24, which moves with v instead of holding f(0).
        let origin = try AdjustTable(.curves(points: [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 0.8)]))
        let (zero, edge) = (origin.apply(0), origin.apply(-0x1p-24))
        #expect(abs(edge - zero) > 0x1p-26, "the entry at -2^-24 differs from f(0)")
        for v: Float in [-1e-9, -3e-10, -0x1p-30] {
            let line = zero + (edge - zero) * (-v / 0x1p-24)
            #expect(abs(origin.apply(v) - line) <= 1e-2 * abs(line - zero), "v \(v): \(origin.apply(v)) vs \(line)")
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
    /// matches the CPU on far values, for both.
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
        #expect(shadows.kind == .luma && shadows.below.isEmpty && shadows.above.isEmpty)
        #expect(abs(shadows.apply(0) - 2) < 1e-6 && abs(shadows.apply(1) - 1) < 1e-6, "shadows lift the dark end only")
    }

    /// Levels and curves outside 0...1, bent maps included (a gamma other than 1, a black point below 0,
    /// sRGB-encoded parameters): the octave tables give the CPU's values within 1e-3.
    @Test func levelsAndCurvesMatchTheCPUOutsideZeroToOne() throws {
        let cpu = CPUBackend()
        let values: [Float] = [-300, -16, -3, -0.5, -0.01, -1e-3, -1e-6, 1.000_01, 1.5, 4, 16, 300, 60_000]
        var probe = try PixelBuffer(width: values.count, height: 1)
        for (i, v) in values.enumerated() { try probe.setPixel(x: i, y: 0, RGBA(r: v, g: v, b: v, a: 1)) }
        let rows = Self.adjustments.filter { if case .exposure = $0 { false } else { true } } + [
            .levels(inBlack: -0.3, inWhite: 0.7, gamma: 2.2, outBlack: 0.1, outWhite: 0.6),
            .levels(inBlack: 0.2, inWhite: 0.6, gamma: 1, outBlack: 0.9, outWhite: 0.2, encoding: .sRGB),
            .curves(points: [CurvePoint(x: 0.1, y: 0.2), CurvePoint(x: 0.6, y: 0.5)], encoding: .sRGB),
        ]
        for adjustment in rows {
            let table = try AdjustTable(adjustment)
            let want = try cpu.read(cpu.adjusted(cpu.surface(probe), adjustment))
            for i in values.indices {
                let (got, w) = (table.map(try probe.pixel(x: i, y: 0)).r, try want.pixel(x: i, y: 0).r)
                #expect(abs(got - w) <= 1e-3 * max(1, abs(w) / 100), "\(adjustment) at \(values[i]): \(got) vs \(w)")
            }
        }
    }

    /// Exposure near the Float limit and a gamma whose power overflows past 1 are valid on 0...1, where the
    /// CPU succeeds: the table builds without the CPU's overflow error and matches it there; an octave that
    /// overflows holds the largest finite Float in the map's direction.
    @Test func extremeParametersTheCPUAcceptsBuildATable() throws {
        let cpu = CPUBackend()
        let grey = try PixelBuffer(width: 1, height: 1, fill: RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1))
        for adjustment in [ToneAdjustment.exposure(stops: 127.5),
                           .levels(inBlack: 0, inWhite: 1, gamma: 0.004, outBlack: 0, outWhite: 1),
                           .levels(inBlack: 0, inWhite: 1, gamma: 0.004, outBlack: 1, outWhite: 0)] {
            let want = try cpu.read(cpu.adjusted(cpu.surface(grey), adjustment)).pixel(x: 0, y: 0)
            let table = try AdjustTable(adjustment)
            let got = table.map(try grey.pixel(x: 0, y: 0))
            #expect(abs(got.r - want.r) <= 1e-6 * max(1, abs(want.r)), "\(adjustment): \(got) vs \(want)")
        }
        let rising = try AdjustTable(.levels(inBlack: 0, inWhite: 1, gamma: 0.004, outBlack: 0, outWhite: 1))
        let falling = try AdjustTable(.levels(inBlack: 0, inWhite: 1, gamma: 0.004, outBlack: 1, outWhite: 0))
        #expect(rising.above.count == AdjustTable.octaveCount && rising.above.last == .greatestFiniteMagnitude)
        #expect(falling.above.last == -.greatestFiniteMagnitude && falling.apply(1e6) < -1e30)
        #expect(rising.below.allSatisfy { $0 == 0 }, "below inBlack levels give outBlack")
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
