// ToneProgramTests.swift: a ToneProgram maps the parity samples as the CPU backend's `adjusted` does with its
// adjustments one after another, within `.standard`, for single steps (hue/saturation included) and for the
// chains a live Photo slider runs (exposure, levels, curves and hue/saturation in that order, an adjustment
// layer's chain followed by the image's), vibrance included; vibrance matches the CPU on a skin-hue pixel (halved
// boost) and a near-gamut one (capped); it lays each step's table at its offset, throws the CPU's error for a bad
// hue or vibrance and `unsupported(.color)` for a colour case it has no step for, and is empty for no adjustments.
// A matrix operation maps each straight linear color through its rows, clamps at 0 and mixes by lightness,
// lays its ten values at its offset and refuses a malformed matrix; `CPUBackend.adjusted(_:tone:)` is the
// program's map over the surface.
import CoreRaster
import CoreRender
import Testing

@Suite struct ToneProgramTests {
    static let levels = ToneAdjustment.levels(inBlack: 0.05, inWhite: 0.8, gamma: 1.4, outBlack: 0, outWhite: 1, encoding: .sRGB)
    static let curves = ToneAdjustment.curves(
        points: [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.62), CurvePoint(x: 1, y: 1)], encoding: .sRGB)
    static let chains: [[ToneAdjustment]] = [
        [.hueSaturation(hue: 40, saturation: -30, lightness: 0)],
        [.hueSaturation(hue: -150, saturation: 60, lightness: 25)],
        [.hueSaturation(hue: 0, saturation: 100, lightness: -40)],
        [levels], [curves], [.exposure(stops: 0.7)],
        [.exposure(stops: -0.5), levels, curves, .hueSaturation(hue: 20, saturation: 35, lightness: -10)],
        [levels, .hueSaturation(hue: 0, saturation: -100, lightness: 0), .exposure(stops: 1), curves],
        [.vibrance(60)], [.vibrance(100)], [.vibrance(-40)],
        [.exposure(stops: 0.3), levels, .vibrance(45), .hueSaturation(hue: 10, saturation: -20, lightness: 0), curves],
    ]

    @Test func mapsTheParitySamplesAsTheCPUChainDoes() throws {
        let cpu = CPUBackend()
        for sample in try ParityHarness.sampleSet(for: .adjust) {
            for chain in Self.chains {
                let program = try ToneProgram(chain)
                let source = sample.source
                var got = try PixelBuffer(width: source.width, height: source.height)
                for y in 0..<source.height {
                    for x in 0..<source.width { try got.setPixel(x: x, y: y, program.map(try source.pixel(x: x, y: y))) }
                }
                var want = try cpu.surface(source)
                for adjustment in chain { want = try cpu.adjusted(want, adjustment) }
                let result = try ParityHarness.compare(got, try cpu.read(want), tolerance: .standard)
                #expect(result.passed, "\(sample.name) \(chain): \(result)")
            }
        }
    }

    /// A muted skin-hue pixel (encoded hue about 24 degrees, boost halved), a near-gamut one whose boost the cap
    /// trims, a saturated blue, a half-transparent green and a grey, through positive and negative vibrance.
    @Test func vibranceMatchesTheCPUOnSkinAndCappedPixels() throws {
        let cpu = CPUBackend()
        let pixels = [RGBA(r: 0.5, g: 0.3, b: 0.2, a: 1), RGBA(r: 0.98, g: 0.5, b: 0.45, a: 1), RGBA(r: 0.05, g: 0.1, b: 0.9, a: 1),
                      RGBA(r: 0.1, g: 0.3, b: 0.05, a: 0.5), RGBA(r: 0.4, g: 0.4, b: 0.4, a: 1)]
        var source = try PixelBuffer(width: pixels.count, height: 1)
        for (x, p) in pixels.enumerated() { try source.setPixel(x: x, y: 0, p) }
        for amount: Float in [100, 60, 25, -50, -100] {
            let program = try ToneProgram([.vibrance(amount)])
            #expect(program.steps.map(\.kind) == [ToneProgram.vibrance] && program.steps[0].values == SIMD3(amount, 0, 0))
            var got = try PixelBuffer(width: pixels.count, height: 1)
            for x in pixels.indices { try got.setPixel(x: x, y: 0, program.map(try source.pixel(x: x, y: 0))) }
            let want = try cpu.read(cpu.adjusted(cpu.surface(source), .vibrance(amount)))
            let result = try ParityHarness.compare(got, want, tolerance: .standard)
            #expect(result.passed, "vibrance \(amount): \(result)")
        }
    }

    @Test func laysEachTableAtItsOffset() throws {
        let program = try ToneProgram([.exposure(stops: 1), Self.levels, .hueSaturation(hue: 10, saturation: 0, lightness: 0), Self.curves])
        let (levels, curves) = (try AdjustTable(Self.levels), try AdjustTable(Self.curves))
        #expect(program.steps.map(\.kind) == [0, 1, ToneProgram.hueSaturation, 1])
        #expect(program.steps[0].values == SIMD3(repeating: 2) && program.steps[0].n == 0)
        #expect(program.steps[1].offset == 0 && program.steps[3].offset == UInt32(levels.values.count + 2 * levels.below.count))
        #expect(program.steps[3].n == UInt32(AdjustTable.steps) && program.steps[3].outer == UInt32(curves.above.count))
        #expect(program.steps[2].values == SIMD3(10, 0, 0))
        let vibrant = try ToneProgram([Self.levels, .vibrance(30), Self.curves])
        #expect(vibrant.steps.map(\.kind) == [1, ToneProgram.vibrance, 1] && vibrant.steps[1].n == 0)
        #expect(vibrant.steps[2].offset == UInt32(levels.values.count + 2 * levels.below.count), "vibrance adds no table")
        #expect(program.tables == levels.values + levels.below + levels.above + curves.values + curves.below + curves.above)
        #expect(program.map(RGBA(r: 0.5, g: 0.2, b: 0.1, a: 0)) == .clear, "alpha 0 gives zeros")
        #expect(try ToneProgram([]).isEmpty)
    }

    /// A hue-rotate-like matrix with negative entries, so some results clamp at 0.
    static let rows: [Float] = [0.6, 0.5, -0.1, -0.2, 1.1, 0.1, 0.3, -0.4, 1.1]

    @Test func aMatrixMapsTheStraightColorClampsAndMixes() throws {
        for lightness: Float in [0, 0.4, -0.3] {
            let program = try ToneProgram(operations: [.matrix(rows: Self.rows, lightness: lightness)])
            #expect(program.steps.map(\.kind) == [ToneProgram.matrix] && program.tables == Self.rows + [lightness])
            let p = RGBA(r: 0.2, g: 0.6, b: 0.1, a: 0.5)
            let got = program.map(p)
            let (r, g, b) = (p.r / p.a, p.g / p.a, p.b / p.a)
            func light(_ v: Float) -> Float { let c = max(v, 0); return lightness >= 0 ? c + (1 - c) * lightness : c * (1 + lightness) }
            let m = Self.rows
            let want = [light(m[0] * r + m[1] * g + m[2] * b), light(m[3] * r + m[4] * g + m[5] * b), light(m[6] * r + m[7] * g + m[8] * b)]
            #expect(abs(got.r - want[0] * p.a) < 1e-6 && abs(got.g - want[1] * p.a) < 1e-6 && abs(got.b - want[2] * p.a) < 1e-6)
            #expect(got.a == p.a)
        }
        let chained = try ToneProgram(operations: [.adjustment(Self.levels), .matrix(rows: Self.rows, lightness: 0.2), .adjustment(Self.curves)])
        #expect(chained.steps[1].offset == UInt32(try AdjustTable(Self.levels).values.count + 2 * AdjustTable(Self.levels).below.count))
        #expect(chained.steps[2].offset == chained.steps[1].offset + 10)
        for bad: ToneProgram.Operation in [.matrix(rows: [1, 0, 0], lightness: 0), .matrix(rows: Self.rows, lightness: 1.5),
                                           .matrix(rows: Self.rows.map { $0 * .nan }, lightness: 0)] {
            #expect(throws: RenderError.self) { try ToneProgram(operations: [bad]) }
        }
    }

    @Test func theCPUBackendAppliesAProgramAsItsMap() throws {
        let cpu = CPUBackend()
        let source = try ParityHarness.sampleSet(for: .adjust)[0].source
        let program = try ToneProgram(operations: [.adjustment(Self.levels), .matrix(rows: Self.rows, lightness: -0.2)])
        let s = try cpu.surface(source)
        let got = try cpu.read(cpu.adjusted(s, tone: program))
        for y in 0..<source.height {
            for x in 0..<source.width { #expect(try got.pixel(x: x, y: y) == program.map(try source.pixel(x: x, y: y))) }
        }
        #expect(try cpu.read(s) == source, "the source is unchanged")
    }

    @Test func throwsTheCPUErrorAndRefusesOtherColourCases() throws {
        let cpu = CPUBackend()
        for bad in [ToneAdjustment.hueSaturation(hue: 181, saturation: 0, lightness: 0), .vibrance(101), .vibrance(.nan)] {
            do {
                _ = try cpu.adjusted(cpu.surface(PixelBuffer(width: 1, height: 1)), bad)
                Issue.record("the CPU accepts \(bad)")
            } catch let expected as RenderError {
                #expect(throws: expected) { try ToneProgram([bad]) }
            }
        }
        #expect(throws: RenderError.unsupported(.color)) { try ToneProgram([.invert]) }
    }
}
