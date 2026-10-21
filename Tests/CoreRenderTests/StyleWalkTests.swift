// StyleWalkTests.swift: layer-style-engine LE-10, journey KJ-LE. A white 400 x 300 rounded-rect badge padded
// by its stack's `reach`, styled with drop shadow, outer glow, outside stroke, gradient overlay, inner shadow
// and an inner smooth bevel through a `RenderDispatcher` with Metal off, `==` the direct `styled` call (Metal on
// is MetalStyleWalkTests). The shadow ends 6 px right and down of the badge, the bevel lights the edges facing
// 120°, a disabled entry changes nothing, and a PSD written with the stack as `lfx2` reads it back (offsets and
// gradient ends to 1e-9 px).
import CoreColor
import CoreRaster
import CoreRender
import Foundation
import Testing

@Suite struct StyleWalkTests {
    static let shape = (width: 400, height: 300), radius = 24.0

    /// An sRGB colour given in bytes, as the PSD reader decodes it: opaque linear light.
    static func srgb(_ r: Double, _ g: Double, _ b: Double) -> RGBA {
        let f = { (v: Double) in Float(TransferCurve.decode(v / 255)) }
        return RGBA(r: f(r), g: f(g), b: f(b), a: 1)
    }
    static let black = srgb(0, 0, 0), white = srgb(255, 255, 255), glow = srgb(255, 230, 150)
    static let crimson = srgb(220, 20, 60), blue = srgb(0, 0, 255)
    static let bevel = Bevel(shape: .innerBevel, technique: .smooth, depth: 1, up: true, size: 8, soften: 0,
                             angle: 120, altitude: 30, highlight: white, highlightMode: .screen, highlightOpacity: 0.75,
                             shadow: black, shadowMode: .multiply, shadowOpacity: 0.75)

    /// The journey's stack for a `width` x `height` layer: its gradient runs from the top edge to the bottom.
    static func stack(width: Int, height: Int) -> LayerStyleStack {
        let ramp = [RasterGradientStop(offset: 0, color: blue), RasterGradientStop(offset: 1, color: white)]
        let x = Double(width) / 2
        return LayerStyleStack(entries: [
            StyleEntry(op: .dropShadow(color: black, dx: 6, dy: 6, spread: 0, blur: 12), mode: .multiply, opacity: 0.5),
            StyleEntry(op: .outerGlow(color: glow, spread: 0, size: 10), mode: .screen, opacity: 0.75),
            StyleEntry(op: .stroke(fill: .color(crimson), width: 4, position: .outside)),
            StyleEntry(op: .overlay(.gradient(stops: ramp, shape: .linear, from: Mask.Point(x: x, y: 0),
                                              to: Mask.Point(x: x, y: Double(height)))), opacity: 0.6),
            StyleEntry(op: .innerShadow(color: black, dx: 3, dy: 3, spread: 0, blur: 6), mode: .multiply, opacity: 0.5),
            StyleEntry(op: .bevel(bevel)),
        ])
    }

    /// The badge drawn `pad` px in from every side, its corners anti-aliased by 4 x 4 supersampling.
    static func badge(pad: Int) throws -> PixelBuffer {
        let (w, h) = (shape.width + 2 * pad, shape.height + 2 * pad)
        let (x0, y0) = (Double(pad), Double(pad)), (x1, y1) = (Double(pad + shape.width), Double(pad + shape.height))
        var buffer = try PixelBuffer(width: w, height: h)
        for y in 0..<h {
            for x in 0..<w {
                var hits = 0
                for s in 0..<16 {
                    let (px, py) = (Double(x) + (Double(s % 4) + 0.5) / 4, Double(y) + (Double(s / 4) + 0.5) / 4)
                    let cx = min(max(px, x0 + radius), x1 - radius), cy = min(max(py, y0 + radius), y1 - radius)
                    if px >= x0, px < x1, py >= y0, py < y1, (px - cx) * (px - cx) + (py - cy) * (py - cy) <= radius * radius { hits += 1 }
                }
                let k = Float(hits) / 16
                if k > 0 { try buffer.setPixel(x: x, y: y, RGBA(r: k, g: k, b: k, a: k)) }
            }
        }
        return buffer
    }

    /// `stack` on `layer` through `d`, read back.
    static func styled(_ d: RenderDispatcher, _ layer: PixelBuffer, _ stack: LayerStyleStack) throws -> PixelBuffer {
        let s = try d.surface(layer), out = try d.styled(s, stack)
        defer { d.release(s); d.release(out) }
        return try d.read(out)
    }

    @Test func walk() throws {
        let probe = Self.stack(width: 1, height: 1)
        #expect(probe.reach == 21, "hypot(6, 6) + 12, rounded up")
        let pad = probe.reach, badge = try Self.badge(pad: pad)
        let stack = Self.stack(width: badge.width, height: badge.height)
        let off = RenderDispatcher(preferred: nil, fallback: CPUBackend())
        let styled = try Self.styled(off, badge, stack)
        let same = styled == (try badge.styled(stack))  // a Bool, so a miss does not print both buffers
        #expect(same, "Metal off: the dispatcher's style differs from the direct call")

        // The shadow alone, the layer hidden (it still knocks the shadow out beneath it): at its 50% it falls
        // under half that darkness 6 px past the badge's right and bottom edges, where the offset shape ends.
        let shadow = try Self.styled(off, badge, LayerStyleStack(entries: [stack.entries[0]], fillOpacity: 0))
        let (right, bottom) = (pad + Self.shape.width, pad + Self.shape.height), mid = (x: badge.width / 2, y: badge.height / 2)
        let full: Float = 0.5
        let down = try (0..<pad).first { try shadow.pixel(x: mid.x, y: bottom + $0).a < full / 2 }
        let across = try (0..<pad).first { try shadow.pixel(x: right + $0, y: mid.y).a < full / 2 }
        #expect(down == 6 && across == 6, "shadow edge at +\(String(describing: across)), +\(String(describing: down))")

        // The bevel alone: its white Screen highlight leaves the white badge white on the edges facing 120°
        // (bottom, left), and its Multiply shadow darkens the edges facing 300° (top, right).
        let lit = try Self.styled(off, badge, LayerStyleStack(entries: [stack.entries[5]]))
        func band(_ points: [(Int, Int)]) throws -> Float {
            var sum: Float = 0
            for (x, y) in points { sum += try lit.pixel(x: x, y: y).r }
            return sum / Float(points.count)
        }
        let xs = (mid.x - 100)..<(mid.x + 100), ys = (mid.y - 75)..<(mid.y + 75)
        let top = try band(xs.map { ($0, pad + 2) }), low = try band(xs.map { ($0, bottom - 3) })
        let left = try band(ys.map { (pad + 2, $0) }), east = try band(ys.map { (right - 3, $0) })
        #expect(low > 0.99 && left > 0.99 && top < 0.9 && east < 0.9, "top \(top) bottom \(low) left \(left) right \(east)")

        // Each entry disabled draws as if it were not in the stack.
        for index in stack.entries.indices {
            var disabled = stack, removed = stack
            disabled.entries[index].isEnabled = false
            removed.entries.remove(at: index)
            let equal = try Self.styled(off, badge, disabled) == badge.styled(removed)
            #expect(equal, "entry \(index) disabled still draws")
        }

        // The badge in a PSD whose layer carries the stack as `lfx2`: read back within the file's precision.
        let image = LayeredImage(width: badge.width, height: badge.height, nodes: [.pixels(PixelLayer(name: "badge", pixels: badge))])
        let read = try PSD.read(Self.withEffects(try PSD.write(image), Self.lfx2(height: badge.height)))
        guard case let .pixels(layer)? = read.nodes.first, let got = layer.style else { Issue.record("no style read"); return }
        #expect(read.notes.isEmpty, "\(read.notes)")
        #expect(Self.rounded(got) == Self.rounded(stack), "\(got)")
    }
}

extension StyleWalkTests {
    /// `stack` with every offset and gradient end rounded to 1e-9 px, the precision the PSD's angles keep.
    static func rounded(_ stack: LayerStyleStack) -> LayerStyleStack {
        func r(_ v: Double) -> Double { (v * 1e9).rounded() / 1e9 }
        var out = stack
        for i in out.entries.indices {
            switch out.entries[i].op {
            case let .dropShadow(c, dx, dy, s, b): out.entries[i].op = .dropShadow(color: c, dx: r(dx), dy: r(dy), spread: s, blur: b)
            case let .innerShadow(c, dx, dy, s, b): out.entries[i].op = .innerShadow(color: c, dx: r(dx), dy: r(dy), spread: s, blur: b)
            case let .overlay(.gradient(stops, shape, a, b)):
                out.entries[i].op = .overlay(.gradient(stops: stops, shape: shape, from: Mask.Point(x: r(a.x), y: r(a.y)),
                                                       to: Mask.Point(x: r(b.x), y: r(b.y))))
            default: break
            }
        }
        return out
    }

    /// The PSD `data` (one layer, as `PSD.write` lays it out) with `block` appended to its layer's extra
    /// data, and the extra data, layer info and layer and mask section lengths grown to match.
    static func withEffects(_ data: Data, _ block: [UInt8]) throws -> Data {
        var bytes = [UInt8](data)
        func u32(_ at: Int) -> Int { bytes[at..<at + 4].reduce(0) { $0 << 8 | Int($1) } }
        func grow(_ at: Int) { let v = u32(at) + block.count; for k in 0..<4 { bytes[at + k] = UInt8(truncatingIfNeeded: v >> (24 - 8 * k)) } }
        let section = 30 + 4 + u32(30), record = section + 10
        let channels = Int(bytes[record + 16]) << 8 | Int(bytes[record + 17])
        let extra = record + 18 + 6 * channels + 12
        bytes.insert(contentsOf: block, at: extra + 4 + u32(extra))
        for at in [extra, section + 4, section] { grow(at) }
        return Data(bytes)
    }

    /// The walk's stack as an `lfx2` block for a layer `height` px tall, as the published spec lays it out.
    static func lfx2(height: Int) -> [UInt8] {
        func rgb(_ r: Double, _ g: Double, _ b: Double) -> Desc { .obj("RGBC", [("Rd  ", .doub(r)), ("Grn ", .doub(g)), ("Bl  ", .doub(b))]) }
        func shadow(_ distance: Double, _ blur: Double) -> [(String, Desc)] {
            [("Md  ", .enm("BlnM", "Mltp")), ("Clr ", rgb(0, 0, 0)), ("Opct", .untf("#Prc", 50)), ("uglg", .bool(false)),
             ("lagl", .untf("#Ang", 135)), ("Dstn", .untf("#Pxl", distance)), ("Ckmt", .untf("#Pxl", 0)), ("blur", .untf("#Pxl", blur))]
        }
        let stop = { (at: Double, c: Desc) in Desc.obj("Clrt", [("Clr ", c), ("Lctn", .long(Int(at)))]) }
        let opaque = { (at: Double) in Desc.obj("TrnS", [("Opct", .untf("#Prc", 100)), ("Lctn", .long(Int(at)))]) }
        let fx = Desc.obj("null", [
            ("masterFXSwitch", .bool(true)),
            ("DrSh", .obj("DrSh", shadow(6 * 2.0.squareRoot(), 12))),
            ("OrGl", .obj("OrGl", [("Md  ", .enm("BlnM", "Scrn")), ("Clr ", rgb(255, 230, 150)), ("Opct", .untf("#Prc", 75)),
                                   ("Ckmt", .untf("#Pxl", 0)), ("blur", .untf("#Pxl", 10))])),
            ("FrFX", .obj("FrFX", [("Styl", .enm("FStl", "OutF")), ("PntT", .enm("FrFl", "SClr")), ("Md  ", .enm("BlnM", "Nrml")),
                                   ("Opct", .untf("#Prc", 100)), ("Sz  ", .untf("#Pxl", 4)), ("Clr ", rgb(220, 20, 60))])),
            ("GrFl", .obj("GrFl", [("Md  ", .enm("BlnM", "Nrml")), ("Opct", .untf("#Prc", 60)), ("Angl", .untf("#Ang", -90)),
                                   ("Grad", .obj("Grdn", [("Clrs", .list([stop(0, rgb(0, 0, 255)), stop(4096, rgb(255, 255, 255))])),
                                                          ("Trns", .list([opaque(0), opaque(4096)]))]))])),
            ("IrSh", .obj("IrSh", shadow(3 * 2.0.squareRoot(), 6))),
            ("ebbl", .obj("ebbl", [("bvlS", .enm("BESl", "InrB")), ("bvlT", .enm("bvlT", "SfBL")), ("srgR", .untf("#Prc", 100)),
                                   ("bvlD", .enm("BESs", "In  ")), ("blur", .untf("#Pxl", 8)), ("Sftn", .untf("#Pxl", 0)),
                                   ("uglg", .bool(false)), ("lagl", .untf("#Ang", -120)), ("Lald", .untf("#Ang", 30)),
                                   ("hglM", .enm("BlnM", "Scrn")), ("hglC", rgb(255, 255, 255)), ("hglO", .untf("#Prc", 75)),
                                   ("sdwM", .enm("BlnM", "Mltp")), ("sdwC", rgb(0, 0, 0)), ("sdwO", .untf("#Prc", 75))])),
        ])
        var body: [UInt8] = []
        Desc.u32(&body, 0); Desc.u32(&body, 16); fx.write(&body)
        if body.count % 2 == 1 { body.append(0) }
        var out = Array("8BIMlfx2".utf8)
        Desc.u32(&out, body.count)
        return out + body
    }
}

/// A descriptor value as the published PSD spec stores it (CoreRasterTests' `Desc`, a target this one cannot import).
indirect enum Desc {
    case obj(String, [(String, Desc)]), doub(Double), untf(String, Double), long(Int), bool(Bool), enm(String, String), list([Desc])

    static func u32(_ w: inout [UInt8], _ v: Int) { for k in 0..<4 { w.append(UInt8(truncatingIfNeeded: v >> (24 - 8 * k))) } }

    func write(_ w: inout [UInt8]) {
        func id(_ s: String) { Desc.u32(&w, s.utf8.count == 4 ? 0 : s.utf8.count); w += Array(s.utf8) }
        switch self {
        case let .obj(cls, items):
            Desc.u32(&w, 1); w += [0, 0]; id(cls); Desc.u32(&w, items.count)
            for (key, value) in items { id(key); w += Array(value.type.utf8); value.write(&w) }
        case let .doub(v): Desc.u32(&w, Int(v.bitPattern >> 32)); Desc.u32(&w, Int(v.bitPattern & 0xFFFF_FFFF))
        case let .untf(unit, v): w += Array(unit.utf8); Desc.doub(v).write(&w)
        case let .long(v): Desc.u32(&w, v)
        case let .bool(v): w.append(v ? 1 : 0)
        case let .enm(type, value): id(type); id(value)
        case let .list(items): Desc.u32(&w, items.count); for item in items { w += Array(item.type.utf8); item.write(&w) }
        }
    }

    var type: String {
        switch self { case .obj: "Objc"; case .doub: "doub"; case .untf: "UntF"; case .long: "long"; case .bool: "bool"; case .enm: "enum"; case .list: "VlLs" }
    }
}
