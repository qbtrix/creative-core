// StyleFixtures.swift: reference images and values for the layer-style suites
// (layer-style-engine LE-1): a white anti-aliased rounded-rect badge on
// transparency, the effects fixtures' disc (reused, not copied; their 1 px
// line and glyph serve as they are), a default inner smooth bevel and a small stack with one entry of
// each op. Buffers are linear, premultiplied, like PixelBuffer.
import CoreRaster
import Testing

enum StyleFixtures {
    static let white = EffectFixtures.white
    static let black = RGBA(r: 0, g: 0, b: 0, a: 1)

    /// A `width` x `height` buffer with a white rounded rect inset by `pad`,
    /// corner radius `radius`, anti-aliased by 4 x 4 supersampling.
    static func badge(width: Int = 48, height: Int = 32, pad: Double = 8, radius: Double = 4) throws -> PixelBuffer {
        var buffer = try PixelBuffer(width: width, height: height)
        let (x0, y0, x1, y1) = (pad, pad, Double(width) - pad, Double(height) - pad)
        func inside(_ px: Double, _ py: Double) -> Bool {
            guard px >= x0, px <= x1, py >= y0, py <= y1 else { return false }
            let cx = min(max(px, x0 + radius), x1 - radius), cy = min(max(py, y0 + radius), y1 - radius)
            return (px - cx) * (px - cx) + (py - cy) * (py - cy) <= radius * radius
        }
        for y in 0..<height {
            for x in 0..<width {
                var hits = 0
                for sy in 0..<4 {
                    for sx in 0..<4 where inside(Double(x) + (Double(sx) + 0.5) / 4, Double(y) + (Double(sy) + 0.5) / 4) {
                        hits += 1
                    }
                }
                let k = Float(hits) / 16
                guard k > 0 else { continue }
                try buffer.setPixel(x: x, y: y, RGBA(r: k, g: k, b: k, a: k))
            }
        }
        return buffer
    }

    static func disc(size: Int = 64, radius: Double = 16) throws -> PixelBuffer {
        try EffectFixtures.disc(size: size, radius: radius)
    }

    /// An inner smooth bevel lit from 120° at 30° altitude: white Screen over black Multiply.
    static func bevel(shape: BevelShape = .innerBevel, size: Double = 5, angle: Double = 120,
                      altitude: Double = 30, up: Bool = true, soften: Double = 0) -> Bevel {
        Bevel(shape: shape, technique: .smooth, depth: 1, up: up, size: size, soften: soften,
              angle: angle, altitude: altitude, highlight: white, highlightMode: .screen, highlightOpacity: 0.75,
              shadow: black, shadowMode: .multiply, shadowOpacity: 0.75)
    }

    /// One entry of each of the seven ops, in an order that is not the paint order.
    static func everyOp() -> LayerStyleStack {
        let grey = RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1)
        return LayerStyleStack(entries: [
            StyleEntry(op: .bevel(bevel())),
            StyleEntry(op: .overlay(.color(grey)), mode: .multiply),
            StyleEntry(op: .stroke(fill: .color(black), width: 2, position: .outside)),
            StyleEntry(op: .innerGlow(color: white, spread: 0, size: 3), mode: .screen),
            StyleEntry(op: .outerGlow(color: white, spread: 0, size: 4), mode: .screen),
            StyleEntry(op: .innerShadow(color: black, dx: 2, dy: 2, spread: 0, blur: 3), mode: .multiply),
            StyleEntry(op: .dropShadow(color: black, dx: 6, dy: 6, spread: 0, blur: 12), mode: .multiply, opacity: 0.75),
        ])
    }
}
