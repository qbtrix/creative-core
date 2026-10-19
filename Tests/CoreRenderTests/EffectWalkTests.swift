// EffectWalkTests.swift: effects-engine FX-9's Journey step KJ-FX. A white
// 600 x 400 rounded rectangle on transparency, padded by 40 px (a 680 x 480
// layer), styled through a `RenderDispatcher` over a fake without `.effect`:
// drop shadow (dx 8, dy 8, blur 12, 50% black), a 4 px outside stroke in
// blue, a 16 px outer glow, then `clarity(amount: 30, radius: 30)` on the
// result. Every step falls back to the CPU and equals the direct CoreRaster
// call on the previous direct result, and the drop shadow sits 8 px right
// and down of the shape: its dark part past the shape's bottom and right
// edges ends at the shape's corner plus (8, 8), where it falls to half.
import CoreRaster
import CoreRender
import Testing

@Suite struct EffectWalkTests {
    static let pad = 40, shapeWidth = 600, shapeHeight = 400, cornerRadius = 24.0

    /// The shape's exclusive bottom-right corner: one past its last column and row.
    static var corner: (x: Int, y: Int) { (pad + shapeWidth, pad + shapeHeight) }

    /// The padded layer: the white rounded rectangle (8-bit sRGB coverage), its rounded corners
    /// anti-aliased by 4 x 4 supersampling, its straight edges on whole pixels.
    static func layer() throws -> PixelBuffer {
        let w = shapeWidth + 2 * pad, h = shapeHeight + 2 * pad, r = cornerRadius
        let x0 = Double(pad), y0 = Double(pad), x1 = Double(corner.x), y1 = Double(corner.y)
        /// Whether the point (px, py) is inside the rounded rectangle.
        func inside(_ px: Double, _ py: Double) -> Bool {
            guard px >= x0, px < x1, py >= y0, py < y1 else { return false }
            let cx = min(max(px, x0 + r), x1 - r), cy = min(max(py, y0 + r), y1 - r)
            return (px - cx) * (px - cx) + (py - cy) * (py - cy) <= r * r
        }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                var hits = 0
                for sy in 0..<4 {
                    for sx in 0..<4 where inside(Double(x) + (Double(sx) + 0.5) / 4, Double(y) + (Double(sy) + 0.5) / 4) {
                        hits += 1
                    }
                }
                guard hits > 0 else { continue }
                let v = UInt8((255 * hits + 8) / 16), o = (y * w + x) * 4
                for k in 0..<4 { bytes[o + k] = v }
            }
        }
        return try PixelBuffer(rgba8: bytes, width: w, height: h)
    }

    /// The journey's steps, in order.
    static let steps: [LayerEffect] = [
        .shadow(color: RGBA(r: 0, g: 0, b: 0, a: 0.5), dx: 8, dy: 8, blur: 12, inner: false),
        .stroke(color: RGBA(r: 0, g: 0, b: 1, a: 1), width: 4, position: .outside),
        .glow(color: RGBA(r: 1, g: 0.9, b: 0.4, a: 1), radius: 16, intensity: 0.75, inner: false),
        .clarity(amount: 30, radius: 30),
    ]

    @Test func walk() throws {
        let fake = FakeBackend(supports: Set(RenderOp.allCases).subtracting([.effect]))
        let dispatcher = RenderDispatcher(preferred: fake, fallback: CPUBackend())
        let start = try Self.layer()
        var expected = start, surface = try dispatcher.surface(start)
        var results: [PixelBuffer] = []
        for effect in Self.steps {
            surface = try dispatcher.applying(surface, effect)
            // The CoreRaster op the case names, not `applying` (CPUEffectTests' helper).
            expected = try CPUEffectTests().direct(expected, effect)
            let got = try dispatcher.read(surface)
            #expect(got == expected, "\(effect) through the dispatcher differs from the direct call")
            #expect(dispatcher.lastFallback?.op == .effect && dispatcher.lastFallback?.reason == RenderDispatcher.reasonUnsupported)
            results.append(got)
        }
        #expect(!fake.calls.contains { if case .applying = $0 { true } else { false } })
        #expect(results.count == Self.steps.count && zip(results, results.dropFirst()).allSatisfy { $0 != $1 })

        // The drop shadow alone shows past the shape's bottom and right edges,
        // at its full 50% just past them. Its blur is symmetric, so it falls
        // under half that darkness exactly where the offset shape ends: its
        // darkest part reaches 8 px right and 8 px down of the shape, so the
        // shadow's corner is the shape's corner plus (8, 8).
        let shadow = results[0], c = Self.corner, middle = (x: c.x - Self.shapeWidth / 2, y: c.y - Self.shapeHeight / 2)
        let full = try shadow.pixel(x: middle.x, y: c.y).a
        #expect(full > 0.45 && full <= 0.5, "shadow under the bottom edge is \(full), not about 50%")
        /// The first offset past the edge where the shadow falls under half its full darkness.
        func halfway(_ alpha: (Int) throws -> Float) throws -> Int? {
            try (0..<Self.pad).first { try alpha($0) < full / 2 }
        }
        let down = try halfway { try shadow.pixel(x: middle.x, y: c.y + $0).a }
        let right = try halfway { try shadow.pixel(x: c.x + $0, y: middle.y).a }
        #expect(down == 8 && right == 8, "shadow edge at (+\(String(describing: right)), +\(String(describing: down))) past the shape")
        // The shadow sits under the layer: the shape itself stays white.
        #expect(try shadow.pixel(x: middle.x, y: middle.y) == start.pixel(x: middle.x, y: middle.y))
    }
}
