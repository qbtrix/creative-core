// MetalStrokeBevelTests.swift: layer-style-engine LE-9a2. The Metal stroke and bevel layers match CoreRaster
// `styleLayers` on the style fixtures (within 2 levels, edge pixels within 8 on at most 0.5%), with its modes,
// opacities and placements: strokes at every position and several widths, in a colour and a gradient; bevels in every
// shape and technique, up and down, softened, lit from overhead and of size 0; the bevel reuses the cached field.
// Skipped without a device; compiled out on Linux.
#if canImport(Metal)
import CoreRaster
import CoreRender
import CoreRenderMetal
import Testing

@Suite struct MetalStrokeBevelTests {
    static let ink = MetalStyleTests.ink

    /// Strokes at every position, at widths 0, under a pixel, a few pixels and wide, one in a gradient.
    static let strokes: [StyleEntry] = {
        let ramp = StyleFill.gradient(stops: [RasterGradientStop(offset: 0, color: ink),
                                              RasterGradientStop(offset: 1, color: RGBA(r: 0.9, g: 0.5, b: 0, a: 1))],
                                      shape: .linear, from: Mask.Point(x: 0, y: 0), to: Mask.Point(x: 40, y: 30))
        var made: [StyleEntry] = []
        for position: StrokePosition in [.outside, .inside, .center] {
            for width in [0, 0.75, 2.5, 6] {
                made.append(StyleEntry(op: .stroke(fill: .color(ink), width: width, position: position), opacity: 0.8))
            }
            made.append(StyleEntry(op: .stroke(fill: ramp, width: 3, position: position), mode: .multiply))
        }
        return made
    }()

    /// Bevels in every shape and technique, plus down, softened, overhead and empty ones.
    static let bevels: [StyleEntry] = {
        var made: [StyleEntry] = []
        for shape: BevelShape in [.innerBevel, .outerBevel, .emboss, .pillowEmboss] {
            for technique: BevelTechnique in [.smooth, .chiselHard, .chiselSoft] {
                made.append(StyleEntry(op: .bevel(MetalStyleTests.bevel { $0.shape = shape; $0.technique = technique })))
            }
        }
        made.append(StyleEntry(op: .bevel(MetalStyleTests.bevel { $0.up = false; $0.depth = 2.5; $0.angle = -45 })))
        made.append(StyleEntry(op: .bevel(MetalStyleTests.bevel { $0.soften = 3; $0.size = 7 }), opacity: 0.6))
        made.append(StyleEntry(op: .bevel(MetalStyleTests.bevel { $0.altitude = 90 })))
        made.append(StyleEntry(op: .bevel(MetalStyleTests.bevel { $0.size = 0 })))
        return made
    }()

    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func strokeAndBevelLayersMatchTheCPU() throws {
        let metal = try MetalBackend.onDefaultDevice()
        let samples = try MetalDistanceTests.fixtures().filter { $0.0 != "seeded" }
        for (name, buffer) in samples {
            let source = try metal.surface(buffer)
            defer { metal.release(source) }
            let held = try metal.read(source)
            for entry in Self.strokes + Self.bevels {
                let got = try metal.styleLayers(source, entry), want = try held.styleLayers(entry)
                #expect(got.count == want.count, "\(name) \(entry.op): layer count")
                for (a, b) in zip(got, want) {
                    #expect(a.mode == b.mode && a.opacity == b.opacity && a.placement == b.placement, "\(name) \(entry.op)")
                    MetalStyleTests.expectClose(a.source, b.source, "\(name) \(entry.op)")
                }
            }
            #expect(try metal.read(source) == held, "\(name): the source is unchanged")
        }
        #expect(metal.isHealthy)
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func bevelReusesTheCachedField() throws {
        let metal = try MetalBackend.onDefaultDevice()
        let source = try metal.surface(try MetalDistanceTests.fixtures()[1].1)
        defer { metal.release(source) }
        let start = metal.styleFieldEncodeCount
        _ = try metal.styleLayers(source, StyleEntry(op: .bevel(MetalStyleTests.bevel)))
        _ = try metal.styleLayers(source, StyleEntry(op: .outerGlow(color: Self.ink, spread: 0.5, size: 3)))
        _ = try metal.styleLayers(source, StyleEntry(op: .stroke(fill: .color(Self.ink), width: 2, position: .center)))
        #expect(metal.styleFieldEncodeCount == start + 1, "one field for the bevel and the glow; the stroke needs none")
    }
}
#endif
