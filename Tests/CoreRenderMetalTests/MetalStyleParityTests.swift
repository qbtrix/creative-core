// MetalStyleParityTests.swift: layer-style-engine LE-9b. Metal claims `.style`: `styled` matches CoreRaster's
// `styled` (within 2 levels, edge pixels within 8 on at most 0.5%) on the parity samples, rendered from their
// Float32 sources (the CPU reproduces the checked-in goldens exactly, CPUGoldenTests), and on the style
// fixtures with every light, stroke and bevel entry, mixed modes and placements, out of paint order, at a fill
// opacity under 1 and with nothing active; a bad stack throws the CPU's error and the backend stays healthy; a
// second `styled` reuses the cached field; the source is unchanged. Skipped without a device; compiled out on Linux.
#if canImport(Metal)
import CoreRaster
import CoreRender
import CoreRenderMetal
import Testing

@Suite struct MetalStyleParityTests {
    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func samplesMatchTheCPU() throws {
        let metal = try MetalBackend.onDefaultDevice()
        #expect(metal.supports.contains(.style), "LE-9b enables .style")
        let cpu = CPUBackend()
        for sample in try ParityHarness.sampleSet(for: .style) {
            let got = try ParityHarness.render(sample, on: metal), want = try ParityHarness.render(sample, on: cpu)
            MetalStyleTests.expectClose(got, want, "style/\(sample.name)")
        }
        #expect(metal.isHealthy)
    }

    /// Stacks over every entry kind: each entry alone at its own mode, a mixed stack out of paint order with
    /// a clipped overlay, and the same at fill opacity 0.4; a stack of disabled entries at fill opacity 1.
    static let stacks: [LayerStyleStack] = {
        let ink = MetalStyleTests.ink
        let ramp = StyleFill.gradient(stops: [RasterGradientStop(offset: 0, color: ink),
                                              RasterGradientStop(offset: 1, color: RGBA(r: 1, g: 1, b: 1, a: 1))],
                                      shape: .radial, from: Mask.Point(x: 20, y: 16), to: Mask.Point(x: 40, y: 16))
        let mixed = [
            StyleEntry(op: .overlay(ramp), mode: .overlay, opacity: 0.7),
            StyleEntry(op: .dropShadow(color: ink, dx: 2, dy: 3, spread: 0.2, blur: 3), mode: .multiply, opacity: 0.8),
            StyleEntry(op: .stroke(fill: .color(ink), width: 2, position: .outside), mode: .difference),
            StyleEntry(op: .bevel(MetalStyleTests.bevel), opacity: 0.9),
            StyleEntry(op: .innerGlow(color: RGBA(r: 0.9, g: 0.6, b: 0.1, a: 1), spread: 0, size: 3), mode: .hue),
            StyleEntry(op: .outerGlow(color: ink, spread: 0.4, size: 4), mode: .luminosity),
            StyleEntry(op: .overlay(.color(ink)), mode: .colorBurn, opacity: 0, isEnabled: true),
        ]
        let singles = (MetalStyleTests.lights + MetalStrokeBevelTests.strokes + MetalStrokeBevelTests.bevels)
            .map { LayerStyleStack(entries: [$0]) }
        let modes = BlendMode.allCases.map {
            LayerStyleStack(entries: [StyleEntry(op: .overlay(ramp), mode: $0, opacity: 0.6),
                                      StyleEntry(op: .outerGlow(color: ink, spread: 0, size: 3), mode: $0)])
        }
        let off = LayerStyleStack(entries: mixed.map { var e = $0; e.isEnabled = false; return e })
        return singles + modes + [LayerStyleStack(entries: mixed), LayerStyleStack(entries: mixed, fillOpacity: 0.4),
                                  LayerStyleStack(entries: [], fillOpacity: 0.25), off]
    }()

    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func stacksMatchTheCPU() throws {
        let metal = try MetalBackend.onDefaultDevice()
        for (name, buffer) in try MetalDistanceTests.fixtures().filter({ $0.0 != "seeded" }) {
            let source = try metal.surface(buffer)
            defer { metal.release(source) }
            let held = try metal.read(source)
            for (index, stack) in Self.stacks.enumerated() {
                let got = try metal.styled(source, stack)
                defer { metal.release(got) }
                #expect(got.id != source.id, "\(name) stack \(index): a new surface")
                MetalStyleTests.expectClose(try metal.read(got), try held.styled(stack), "\(name) stack \(index)")
            }
            #expect(try metal.read(source) == held, "\(name): the source is unchanged")
        }
        #expect(metal.isHealthy)
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func badStacksThrowTheCPUError() throws {
        let metal = try MetalBackend.onDefaultDevice()
        let buffer = try PixelBuffer.seeded(width: 6, height: 4, seed: 0x5F)
        let source = try metal.surface(buffer)
        defer { metal.release(source) }
        let glow = StyleOp.outerGlow(color: MetalStyleTests.ink, spread: 0, size: 2)
        let bad = [
            LayerStyleStack(entries: [], fillOpacity: .nan),
            LayerStyleStack(entries: [StyleEntry(op: glow)], fillOpacity: 1.5),
            LayerStyleStack(entries: [StyleEntry(op: glow, opacity: 1.5)]),
            LayerStyleStack(entries: [StyleEntry(op: glow, opacity: -0.1, isEnabled: false)]),
            LayerStyleStack(entries: [StyleEntry(op: .outerGlow(color: MetalStyleTests.ink, spread: 0, size: 1_001))]),
            LayerStyleStack(entries: [StyleEntry(op: .bevel(MetalStyleTests.bevel { $0.depth = 0 }))]),
        ]
        for stack in bad {
            do {
                _ = try buffer.styled(stack)
                Issue.record("the CPU accepts \(stack)")
            } catch let expected as RasterError {
                #expect(throws: RenderError(expected)) { try metal.styled(source, stack) }
            }
        }
        #expect(metal.isHealthy, "a bad stack does not fail the backend")
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func styledReusesTheCachedField() throws {
        let metal = try MetalBackend.onDefaultDevice()
        let source = try metal.surface(try MetalDistanceTests.fixtures()[1].1)
        defer { metal.release(source) }
        let stack = LayerStyleStack(entries: [StyleEntry(op: .bevel(MetalStyleTests.bevel)),
                                              StyleEntry(op: .outerGlow(color: MetalStyleTests.ink, spread: 0.5, size: 3))])
        let start = metal.styleFieldEncodeCount
        metal.release(try metal.styled(source, stack))
        metal.release(try metal.styled(source, stack))
        #expect(metal.styleFieldEncodeCount == start + 1, "one field for both calls")
    }
}
#endif
