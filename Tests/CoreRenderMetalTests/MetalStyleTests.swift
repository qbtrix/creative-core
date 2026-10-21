// MetalStyleTests.swift: layer-style-engine LE-9a. The Metal shadow and glow layers match CoreRaster `styleLayers`
// on the style fixtures (within 2 levels, edge pixels within 8 on at most 0.5%), with its modes, opacities and
// placements; an overlay is the CPU's fill exactly; the distance field is encoded once per surface alpha (a second
// call reuses it, a new upload re-encodes, release drops it); a bad entry throws CoreRaster's error; a stroke or bevel
// throws `unsupported(.style)`; the backend stays healthy. Skipped without a device; compiled out on Linux.
#if canImport(Metal)
import CoreRaster
import CoreRender
import CoreRenderMetal
import Testing

@Suite struct MetalStyleTests {
    static let ink = RGBA(r: 0.1, g: 0.2, b: 0.6, a: 0.8)

    /// The shadow and glow entries under test, at sizes that spread, blur, offset and do neither.
    static let lights: [StyleEntry] = [
        StyleEntry(op: .dropShadow(color: ink, dx: 3, dy: 2.5, spread: 0, blur: 4), mode: .multiply, opacity: 0.75),
        StyleEntry(op: .dropShadow(color: ink, dx: -1.5, dy: 0, spread: 0.5, blur: 6)),
        StyleEntry(op: .innerShadow(color: ink, dx: 2, dy: 2, spread: 0.25, blur: 3)),
        StyleEntry(op: .outerGlow(color: ink, spread: 0.3, size: 5), mode: .screen),
        StyleEntry(op: .outerGlow(color: ink, spread: 1, size: 3)),
        StyleEntry(op: .innerGlow(color: ink, spread: 0, size: 4)),
        StyleEntry(op: .innerGlow(color: ink, spread: 0, size: 0)),
    ]

    /// Fails unless every component of `got` is within 2 levels of `want`, or within 8 on at most 0.5% of pixels.
    static func expectClose(_ got: PixelBuffer, _ want: PixelBuffer, _ label: String) {
        #expect(got.width == want.width && got.height == want.height, "\(label): size")
        let (g, w) = (got.components, want.components)
        guard g.count == w.count else { return }
        var worst: Float = 0, loose = 0
        for pixel in 0..<(g.count / 4) {
            let delta = (0..<4).map { abs(g[pixel * 4 + $0] - w[pixel * 4 + $0]) * 255 }.max() ?? 0
            worst = max(worst, delta)
            if delta > 2 { loose += 1 }
        }
        #expect(worst <= 8, "\(label): worst \(worst) levels")
        #expect(Double(loose) <= 0.005 * Double(g.count / 4), "\(label): \(loose) pixels past 2 levels")
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func lightLayersMatchTheCPU() throws {
        let metal = try MetalBackend.onDefaultDevice()
        let samples = try MetalDistanceTests.fixtures().filter { $0.0 != "seeded" }
        for (name, buffer) in samples {
            let source = try metal.surface(buffer)
            defer { metal.release(source) }
            let held = try metal.read(source)
            for entry in Self.lights {
                let got = try metal.styleLayers(source, entry), want = try held.styleLayers(entry)
                #expect(got.count == want.count, "\(name) \(entry.op): layer count")
                for (a, b) in zip(got, want) {
                    #expect(a.mode == b.mode && a.opacity == b.opacity && a.placement == b.placement, "\(name) \(entry.op)")
                    Self.expectClose(a.source, b.source, "\(name) \(entry.op)")
                }
            }
            #expect(try metal.read(source) == held, "\(name): the source is unchanged")
        }
        #expect(metal.isHealthy)
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func overlayIsTheCPUFill() throws {
        let metal = try MetalBackend.onDefaultDevice()
        let source = try metal.surface(try PixelBuffer.seeded(width: 24, height: 16, seed: 0x0E))
        defer { metal.release(source) }
        let held = try metal.read(source)
        let entry = StyleEntry(op: .overlay(.color(Self.ink)), mode: .overlay, opacity: 0.5)
        let got = try metal.styleLayers(source, entry), want = try held.styleLayers(entry)
        #expect(got.map(\.source) == want.map(\.source) && got.map(\.placement) == want.map(\.placement))
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func fieldIsCachedPerSurfaceAlpha() throws {
        let metal = try MetalBackend.onDefaultDevice()
        let buffer = try MetalDistanceTests.fixtures()[0].1
        let spread = StyleEntry(op: .outerGlow(color: Self.ink, spread: 0.5, size: 4))
        let first = try metal.surface(buffer)
        let start = metal.styleFieldEncodeCount
        _ = try metal.styleLayers(first, spread)
        #expect(metal.styleFieldEncodeCount == start + 1, "the first spread encodes the field")
        _ = try metal.styleLayers(first, StyleEntry(op: .innerShadow(color: Self.ink, dx: 1, dy: 1, spread: 0.5, blur: 2)))
        #expect(metal.styleFieldEncodeCount == start + 1, "the same alpha reuses it")
        _ = try metal.styleLayers(first, StyleEntry(op: .outerGlow(color: Self.ink, spread: 0, size: 4)))
        #expect(metal.styleFieldEncodeCount == start + 1, "no spread needs no field")
        let other = try metal.surface(try PixelBuffer.seeded(width: buffer.width, height: buffer.height, seed: 0xCA))
        defer { metal.release(other) }
        _ = try metal.styleLayers(other, spread)
        #expect(metal.styleFieldEncodeCount == start + 2, "new alpha encodes again")
        #expect(metal.cachedStyleFieldCount == 2)
        metal.release(first)
        #expect(metal.cachedStyleFieldCount == 1, "release drops the surface's field")
        #expect(throws: RenderError.surfaceMismatch) { try metal.styleLayers(first, spread) }
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func badEntriesThrowTheCPUError() throws {
        let metal = try MetalBackend.onDefaultDevice()
        let buffer = try PixelBuffer.seeded(width: 6, height: 4, seed: 0x5E)
        let source = try metal.surface(buffer)
        defer { metal.release(source) }
        let bad: [StyleOp] = [
            .dropShadow(color: Self.ink, dx: .nan, dy: 0, spread: 0, blur: 1),
            .innerShadow(color: Self.ink, dx: 0, dy: 0, spread: 1.5, blur: 1),
            .outerGlow(color: Self.ink, spread: 0, size: 1_001),
            .innerGlow(color: RGBA(r: .infinity, g: 0, b: 0, a: 1), spread: 0, size: 1),
            .overlay(.color(RGBA(r: .nan, g: 0, b: 0, a: 1))),
            .stroke(fill: .color(Self.ink), width: -1, position: .outside),
        ]
        for op in bad {
            do {
                _ = try buffer.styleLayers(StyleEntry(op: op))
                Issue.record("the CPU accepts \(op)")
            } catch let expected as RasterError {
                #expect(throws: RenderError(expected)) { try metal.styleLayers(source, StyleEntry(op: op)) }
            }
        }
        for op: StyleOp in [.stroke(fill: .color(Self.ink), width: 2, position: .center), .bevel(Self.bevel)] {
            #expect(throws: RenderError.unsupported(.style)) { try metal.styleLayers(source, StyleEntry(op: op)) }
        }
        #expect(metal.isHealthy, "a bad entry does not fail the backend")
    }

    static let bevel = Bevel(shape: .innerBevel, technique: .smooth, depth: 1, up: true, size: 4, soften: 0, angle: 120,
                             altitude: 30, highlight: RGBA(r: 1, g: 1, b: 1, a: 1), highlightMode: .screen,
                             highlightOpacity: 0.75, shadow: RGBA(r: 0, g: 0, b: 0, a: 1), shadowMode: .multiply,
                             shadowOpacity: 0.75)
}
#endif
