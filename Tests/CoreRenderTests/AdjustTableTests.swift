// AdjustTableTests.swift: the Metal adjust kernel's data (MB-13) maps the parity samples as the CPU backend
// does within `.standard`, reads a straight curve exactly (table endpoint and square-root index) and extends
// it along its line, keeps exposure as its factor, and throws the CPU's errors and `unsupported` for MB-14.
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

    @Test func mapsTheParitySamplesAsTheCPUDoes() throws {
        let cpu = CPUBackend()
        for sample in try ParityHarness.sampleSet(for: .adjust) {
            for adjustment in Self.adjustments {
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
        #expect(table.values.count == AdjustTable.steps + 1 && table.scale == 1)
        for k in -50...150 {
            let v = Float(k) / 100 + 0.003
            #expect(abs(table.apply(v) - (0.1 + 0.8 * v)) < 1e-5, "v \(v): \(table.apply(v))")
        }
        #expect(table.map(RGBA(r: 0.5, g: 0.5, b: 0.5, a: 0)) == .clear, "alpha 0 gives zeros")
    }

    @Test func exposureKeepsItsFactor() throws {
        let table = try AdjustTable(.exposure(stops: 2))
        #expect(table.values.isEmpty && table.scale == 4 && table.apply(0.3) == 0.3 * 4)
        #expect(try AdjustTable(.exposure(stops: 0)).apply(0.7) == 0.7)
    }

    @Test func throwsTheCPUsErrorsAndUnsupportedForTheDevelopSliders() throws {
        for adjustment in [ToneAdjustment.whiteBalance(temperature: 10, tint: 0), .contrast(40),
                           .highlightsShadows(highlights: 10, shadows: 0)] {
            #expect(throws: RenderError.unsupported(.adjust)) { try AdjustTable(adjustment) }
        }
        let cpu = CPUBackend()
        let surface = try cpu.surface(PixelBuffer(width: 2, height: 2))
        for bad in [ToneAdjustment.exposure(stops: .nan), .levels(inBlack: 0.5, inWhite: 0.5, gamma: 1, outBlack: 0, outWhite: 1),
                    .curves(points: [CurvePoint(x: 0, y: 0)])] {
            do {
                _ = try cpu.adjusted(surface, bad)
                Issue.record("the CPU accepts \(bad)")
            } catch let expected as RenderError {
                #expect(throws: expected) { try AdjustTable(bad) }
            }
        }
    }
}
