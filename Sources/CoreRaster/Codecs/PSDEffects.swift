// PSDEffects.swift: a PSD layer's object-based effects (`lfx2`, version 0,
// descriptor version 16, from the published PSD file format specification)
// mapped onto a `LayerStyleStack`: drop and inner shadow, outer and inner
// glow, stroke, colour and gradient overlay, bevel and emboss, with the
// layer's fill opacity (`iOpa`) and the image's global light (resources 1037
// and 1049) for effects that use it.
// Invariants: this never throws. Every effect the stack cannot hold (satin,
// pattern overlay, a contour, a pattern stroke, a second instance of one
// effect, an unknown blend mode or effect) adds a "<layer>: <what> (not kept)"
// note; a block the descriptor reader refuses notes "unreadable" and the
// layer opens bare. `masterFXSwitch` off keeps every entry, disabled.
// Opacities are percent in the file and 0...1 in the stack; angles are
// degrees counterclockwise in the file, and a bevel's angle turns clockwise
// (y down) for `Bevel`.
import CoreColor
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// The image's global light angle (resource 1037) and altitude (1049), degrees; nil when absent.
struct PSDGlobalLight: Sendable {
    var angle: Double?, altitude: Double?

    init() {}

    /// The global light in an image resources section; other resources are passed over by length.
    init(resources: ByteReader) throws {
        var r = resources
        while !r.isAtEnd {
            let isBIM = try r.bytes(4) == Array("8BIM".utf8), id = try r.u16(), name = Int(try r.u8())
            try r.skip(name + (name + 1) % 2)
            let size = try r.length32()
            var data = try r.reader(size)
            try r.skip(min(size % 2, r.remaining))
            guard isBIM, size >= 4 else { continue }
            if id == 1037 { angle = Double(try data.i32()) } else if id == 1049 { altitude = Double(try data.i32()) }
        }
    }
}

enum PSDEffects {
    /// The style of a layer named `layer`, `width` x `height` px, and its notes, from its
    /// `lfx2` block (nil: none), its `iOpa` byte and whether it has the older `lrFX` block.
    /// The style is nil when the layer has no effects and a fill opacity of 1.
    static func style(_ block: ByteReader?, fill: UInt8, oldBlock: Bool, layer: String,
                      width: Int, height: Int, light: PSDGlobalLight) -> (LayerStyleStack?, [String]) {
        let bare = fill == 255 ? nil : LayerStyleStack(entries: [], fillOpacity: Float(fill) / 255)
        guard var block else { return (bare, oldBlock ? ["\(layer): layer effects in the older lrFX block (not kept)"] : []) }
        let fx: PSDDescriptor
        do {
            guard try block.u32() == 0, try block.u32() == 16 else { throw CodecError.unsupported("effects version") }
            fx = try PSDDescriptor(&block)
        } catch { return (bare, ["\(layer): layer effects (unreadable, not kept)"]) }
        var map = Mapper(layer: layer, width: Double(max(width, 1)), height: Double(max(height, 1)),
                         light: light, master: fx.bool("masterFXSwitch") ?? true)
        let listed = Set(fx.items.compactMap { multi[$0.key] })
        for (key, value) in fx.items {
            if let base = multi[key], case let .list(list) = value {
                for (index, item) in list.enumerated() {
                    guard index == 0 else { map.note("\(names[base] ?? base) \(index + 1)"); continue }
                    if case let .object(d) = item { map.add(base, d) }
                }
            } else if case let .object(d) = value, !listed.contains(key) {
                if names[key] != nil { map.add(key, d) } else { map.note(dropped[key] ?? "effect \(key)") }
            }
        }
        return (LayerStyleStack(entries: map.entries, fillOpacity: Float(fill) / 255), map.notes)
    }

    static let names = ["DrSh": "drop shadow", "IrSh": "inner shadow", "OrGl": "outer glow", "IrGl": "inner glow",
                        "FrFX": "stroke", "SoFi": "colour overlay", "GrFl": "gradient overlay", "ebbl": "bevel and emboss"]
    static let dropped = ["ChFX": "satin", "patternFill": "pattern overlay"]
    /// The lists that hold several instances of one effect, by the effect's own key.
    static let multi = ["dropShadowMulti": "DrSh", "innerShadowMulti": "IrSh", "solidFillMulti": "SoFi",
                        "gradientFillMulti": "GrFl", "frameFXMulti": "FrFX"]
    /// Descriptor blend mode values (`BlnM`) to modes.
    static let modes: [String: BlendMode] = [
        "Nrml": .normal, "Mltp": .multiply, "Scrn": .screen, "Ovrl": .overlay, "Drkn": .darken, "Lghn": .lighten,
        "CDdg": .colorDodge, "CBrn": .colorBurn, "HrdL": .hardLight, "SftL": .softLight, "Dfrn": .difference,
        "Xclu": .exclusion, "H   ": .hue, "Strt": .saturation, "Clr ": .color, "Lmns": .luminosity,
        // Descriptors spell these two as long IDs, not as the layer record's `lddg` and `lbrn`.
        "linearDodge": .linearDodge, "linearBurn": .linearBurn]
}

/// Maps one layer's effect descriptors to entries, collecting notes.
private struct Mapper {
    let layer: String, width: Double, height: Double, light: PSDGlobalLight, master: Bool
    var entries: [StyleEntry] = [], notes: [String] = []

    mutating func note(_ what: String) { notes.append("\(layer): \(what) (not kept)") }

    mutating func add(_ key: String, _ d: PSDDescriptor) {
        let name = PSDEffects.names[key] ?? key
        if (d.object("TrnS")?.list("Crv ")?.count ?? 0) > 2 { note("\(name) contour") }
        do {
            let op: StyleOp
            let color = try self.color(d, "Clr "), spread = unit((d.number("Ckmt") ?? 0) / 100), size = d.number("blur") ?? 0
            switch key {
            case "DrSh", "IrSh":
                let a = angle(d) * .pi / 180, distance = d.number("Dstn") ?? 0
                let (dx, dy) = (-cos(a) * distance, sin(a) * distance)
                op = key == "DrSh" ? .dropShadow(color: color, dx: dx, dy: dy, spread: spread, blur: size)
                    : .innerShadow(color: color, dx: dx, dy: dy, spread: spread, blur: size)
            case "OrGl": op = .outerGlow(color: color, spread: spread, size: size)
            case "IrGl": op = .innerGlow(color: color, spread: spread, size: size)
            case "FrFX":
                let position: StrokePosition = d.enumValue("Styl") == "InsF" ? .inside : d.enumValue("Styl") == "CtrF" ? .center : .outside
                let paint = d.enumValue("PntT") ?? "SClr"
                guard paint == "SClr" || paint == "GrFl" else { throw CodecError.unsupported("stroke paint \(paint)") }
                op = .stroke(fill: paint == "GrFl" ? try gradient(d) : .color(color), width: d.number("Sz  ") ?? 0, position: position)
            case "SoFi": op = .overlay(.color(color))
            case "GrFl": op = .overlay(try gradient(d))
            default: op = .bevel(try bevel(d))
            }
            entries.append(StyleEntry(op: op, mode: key == "ebbl" ? .normal : mode(d, "Md  ", name),
                                      opacity: key == "ebbl" ? 1 : opacity(d, "Opct"), isEnabled: master && (d.bool("enab") ?? true)))
        } catch { note("\(name) (unreadable)") }
    }

    /// The light's angle, degrees counterclockwise: the global one when the effect uses it.
    func angle(_ d: PSDDescriptor) -> Double { (d.bool("uglg") == true ? light.angle : nil) ?? d.number("lagl") ?? 0 }

    func unit(_ v: Double) -> Double { min(max(v, 0), 1) }

    func opacity(_ d: PSDDescriptor, _ key: String) -> Float { Float(unit((d.number(key) ?? 100) / 100)) }

    mutating func mode(_ d: PSDDescriptor, _ key: String, _ name: String) -> BlendMode {
        let value = d.enumValue(key) ?? "Nrml"
        guard let mode = PSDEffects.modes[value] else { note("\(name) blend mode \(value)"); return .normal }
        return mode
    }

    /// An `RGBC` colour object (0...255 sRGB) as opaque linear light.
    func color(_ d: PSDDescriptor, _ key: String) throws -> RGBA {
        guard let c = d.object(key), let r = c.number("Rd  "), let g = c.number("Grn "), let b = c.number("Bl  ") else {
            throw CodecError.unsupported("colour \(key)")
        }
        let linear = { (v: Double) in Float(TransferCurve.decode(unit(v / 255))) }
        return RGBA(r: linear(r), g: linear(g), b: linear(b), a: 1)
    }

    /// A gradient object (`Grad`: colour stops `Clrs` and opacity stops `Trns` at 0...4096)
    /// across the layer at `Angl`, scaled by `Scl ` and moved by `Ofst` percent of its size.
    func gradient(_ d: PSDDescriptor) throws -> StyleFill {
        guard let g = d.object("Grad"), let colors = g.list("Clrs"), (2...PixelBuffer.maxGradientStops).contains(colors.count) else {
            throw CodecError.unsupported("gradient")
        }
        let alphas = (g.list("Trns") ?? []).compactMap { v -> (Double, Double)? in
            if case let .object(t) = v { (unit((t.number("Lctn") ?? 0) / 4096), Double(opacity(t, "Opct"))) } else { nil }
        }.sorted { $0.0 < $1.0 }
        func alpha(_ t: Double) -> Double {
            var value = alphas.first?.1 ?? 1
            for (a, b) in zip(alphas, alphas.dropFirst()) where t >= a.0 { value = b.0 > a.0 ? a.1 + (b.1 - a.1) * unit((t - a.0) / (b.0 - a.0)) : b.1 }
            return value
        }
        let reversed = d.bool("Rvrs") == true
        let stops = try colors.map { v -> RasterGradientStop in
            guard case let .object(s) = v else { throw CodecError.unsupported("gradient stop") }
            let at = unit((s.number("Lctn") ?? 0) / 4096)
            var c = try color(s, "Clr ")
            c.a = Float(alpha(at))
            return RasterGradientStop(offset: Float(reversed ? 1 - at : at), color: c)
        }.sorted { $0.offset < $1.offset }
        let shapes: [String: RasterGradientShape] = ["Rdl ": .radial, "Angl": .angle, "Rflc": .reflected, "Dmnd": .diamond]
        let shape = shapes[d.enumValue("Type") ?? ""] ?? .linear
        let a = (d.number("Angl") ?? 90) * .pi / 180, scale = (d.number("Scl ") ?? 100) / 100
        let cx = width / 2 + (d.object("Ofst")?.number("Hrzn") ?? 0) / 100 * width
        let cy = height / 2 + (d.object("Ofst")?.number("Vrtc") ?? 0) / 100 * height
        let half = (abs(width * cos(a)) + abs(height * sin(a))) / 2 * scale, (vx, vy) = (cos(a) * half, -sin(a) * half)
        guard half > 0 else { throw CodecError.unsupported("gradient scale") }
        let back = shape == .linear ? 1.0 : 0
        return .gradient(stops: stops, shape: shape, from: Mask.Point(x: cx - vx * back, y: cy - vy * back),
                         to: Mask.Point(x: cx + vx, y: cy + vy))
    }

    mutating func bevel(_ d: PSDDescriptor) throws -> Bevel {
        let shapes: [String: BevelShape] = ["InrB": .innerBevel, "OtrB": .outerBevel, "Embs": .emboss, "PlEb": .pillowEmboss]
        guard let shape = shapes[d.enumValue("bvlS") ?? "InrB"] else { throw CodecError.unsupported("bevel style") }
        let techniques: [String: BevelTechnique] = ["PrBL": .chiselHard, "Slmt": .chiselSoft]
        let turned = (-angle(d)).truncatingRemainder(dividingBy: 360)
        return Bevel(shape: shape, technique: techniques[d.enumValue("bvlT") ?? ""] ?? .smooth,
                     depth: (d.number("srgR") ?? 100) / 100, up: d.enumValue("bvlD") != "Out ",
                     size: d.number("blur") ?? 0, soften: d.number("Sftn") ?? 0, angle: turned < 0 ? turned + 360 : turned,
                     altitude: (d.bool("uglg") == true ? light.altitude : nil) ?? d.number("Lald") ?? 30,
                     highlight: try color(d, "hglC"), highlightMode: mode(d, "hglM", "bevel highlight"), highlightOpacity: opacity(d, "hglO"),
                     shadow: try color(d, "sdwC"), shadowMode: mode(d, "sdwM", "bevel shadow"), shadowOpacity: opacity(d, "sdwO"))
    }
}
