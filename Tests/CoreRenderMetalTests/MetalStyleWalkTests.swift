// MetalStyleWalkTests.swift: layer-style-engine LE-10, the KJ-LE walk with Metal on: the walk's badge and stack
// through a `RenderDispatcher` preferring Metal run on Metal within `MetalStyleTests.expectClose` of CoreRaster's
// `styled`; and the Metal budget (release, reported): a style step on a 2,000 x 2,000 layer, p95 ≤ 16 ms over
// thirty. The stack is StyleWalkTests' (not importable here). Skipped without a device; compiled out on Linux.
#if canImport(Metal)
import CoreRaster
import CoreRender
import CoreRenderMetal
import Testing

#if DEBUG
private let optimized = false
#else
private let optimized = true
#endif

@Suite(.serialized) struct MetalStyleWalkTests {
    static let black = RGBA(r: 0, g: 0, b: 0, a: 1), white = RGBA(r: 1, g: 1, b: 1, a: 1)

    /// The walk's stack for a `width` x `height` layer, its stroke in `stroke`.
    static func stack(width: Int, height: Int, stroke: RGBA = RGBA(r: 0.716, g: 0.007, b: 0.045, a: 1)) -> LayerStyleStack {
        let ramp = [RasterGradientStop(offset: 0, color: RGBA(r: 0, g: 0, b: 1, a: 1)), RasterGradientStop(offset: 1, color: white)]
        let bevel = Bevel(shape: .innerBevel, technique: .smooth, depth: 1, up: true, size: 8, soften: 0, angle: 120, altitude: 30,
                          highlight: white, highlightMode: .screen, highlightOpacity: 0.75,
                          shadow: black, shadowMode: .multiply, shadowOpacity: 0.75)
        let x = Double(width) / 2
        return LayerStyleStack(entries: [
            StyleEntry(op: .dropShadow(color: black, dx: 6, dy: 6, spread: 0, blur: 12), mode: .multiply, opacity: 0.5),
            StyleEntry(op: .outerGlow(color: RGBA(r: 1, g: 0.79, b: 0.3, a: 1), spread: 0, size: 10), mode: .screen, opacity: 0.75),
            StyleEntry(op: .stroke(fill: .color(stroke), width: 4, position: .outside)),
            StyleEntry(op: .overlay(.gradient(stops: ramp, shape: .linear, from: Mask.Point(x: x, y: 0),
                                              to: Mask.Point(x: x, y: Double(height)))), opacity: 0.6),
            StyleEntry(op: .innerShadow(color: black, dx: 3, dy: 3, spread: 0, blur: 6), mode: .multiply, opacity: 0.5),
            StyleEntry(op: .bevel(bevel)),
        ])
    }

    /// A white `w` x `h` rounded rectangle (radius 24) `pad` px in from every side, 4 x 4 supersampled.
    static func badge(w: Int, h: Int, pad: Int) throws -> PixelBuffer {
        var buffer = try PixelBuffer(width: w + 2 * pad, height: h + 2 * pad)
        let (x0, y0, x1, y1, r) = (Double(pad), Double(pad), Double(pad + w), Double(pad + h), 24.0)
        for y in 0..<buffer.height {
            for x in 0..<buffer.width {
                var hits = 0
                for s in 0..<16 {
                    let (px, py) = (Double(x) + (Double(s % 4) + 0.5) / 4, Double(y) + (Double(s / 4) + 0.5) / 4)
                    let cx = min(max(px, x0 + r), x1 - r), cy = min(max(py, y0 + r), y1 - r)
                    if px >= x0, px < x1, py >= y0, py < y1, (px - cx) * (px - cx) + (py - cy) * (py - cy) <= r * r { hits += 1 }
                }
                let k = Float(hits) / 16
                if k > 0 { try buffer.setPixel(x: x, y: y, RGBA(r: k, g: k, b: k, a: k)) }
            }
        }
        return buffer
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func walkWithMetalOn() throws {
        let metal = try MetalBackend.onDefaultDevice()
        let on = RenderDispatcher(preferred: metal, fallback: CPUBackend())
        let pad = Self.stack(width: 1, height: 1).reach, badge = try Self.badge(w: 400, h: 300, pad: pad)
        let stack = Self.stack(width: badge.width, height: badge.height)
        let source = try on.surface(badge), out = try on.styled(source, stack)
        defer { on.release(source); on.release(out) }
        #expect(out.backend == metal.name, "the style ran on \(out.backend): \(String(describing: on.lastFallback))")
        MetalStyleTests.expectClose(try on.read(out), try on.read(source).styled(stack), "walk")
        #expect(metal.isHealthy)
    }

    /// Thirty steps after a warm-up, each the stroke's colour moved (as a colour drag would), so the
    /// field stays cached; the 29th slowest of 30 is the p95.
    @Test(.enabled(if: MetalBackend.defaultDevice != nil && optimized, "a release budget: needs a device and an optimized build"))
    func styleStepP95Under16ms() throws {
        let metal = try MetalBackend.onDefaultDevice()
        let source = try metal.surface(try Self.badge(w: 1958, h: 1958, pad: 21))
        defer { metal.release(source) }
        metal.release(try metal.styled(source, Self.stack(width: 2000, height: 2000)))
        let times = try (0..<30).map { step in
            let stack = Self.stack(width: 2000, height: 2000, stroke: RGBA(r: Float(step) / 30, g: 0.1, b: 0.2, a: 1))
            return try ContinuousClock().measure { metal.release(try metal.styled(source, stack)) }
        }.sorted()
        let p95 = times[28]  // the 29th of 30: index 30 * 95 / 100 rounded down
        print("budget style step 2000x2000 Metal p95: \(p95) (budget 16 ms)")
        #expect(p95 <= .milliseconds(16), "style step p95 \(p95)")
    }
}
#endif
