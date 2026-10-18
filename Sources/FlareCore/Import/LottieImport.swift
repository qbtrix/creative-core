// LottieImport.swift: the Lottie reader's shapes, solids, styles and static transform.
//
// From the public Lottie format docs; docs/blueprints/core/features/vector-import.md
// gives the rules. Layers and shape items are listed top first, so both are
// reversed; each group (`gr`) becomes one shape. Not read yet (VI-7): keyframes
// (the first key is used), masks, mattes and parents, each counted in the report.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension LottieImport {
    /// The frames `ip`, `op`, `st` and keyframe `t` may name.
    static let frames = 0...1_000_000

    static func read(_ data: Data) throws -> (Document, ImportReport) {
        guard data.count <= maxBytes else { throw ImportError.tooLarge("file is \(data.count) bytes, limit \(maxBytes)") }
        let space: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]
        guard data.first(where: { !space.contains($0) }) == UInt8(ascii: "{") else { throw ImportError.notThisFormat }
        try checkNesting(data, limit: 2 * maxDepth + 8)
        guard let root = try? JSONDecoder().decode(LottieJSON.self, from: data) else { throw ImportError.damaged("not valid JSON") }
        guard let layers = root["layers"] else { throw ImportError.notThisFormat }
        var reader = LottieReader()
        do {
            let document = Document(scenes: [try reader.scene(root, layers: layers)])
            try FlareFormat.validate(document)
            return (document, reader.report)
        } catch let error as ImportError { throw error } catch FormatError.tooLarge(let message) {
            throw ImportError.tooLarge(message)
        } catch { throw ImportError.damaged("\(error)") }
    }

    /// Throws `tooLarge` when objects and arrays nest past `limit`, before the decoder recurses.
    static func checkNesting(_ data: Data, limit: Int) throws {
        var depth = 0, inString = false, escaped = false
        for byte in data {
            if inString {
                if escaped { escaped = false } else if byte == 0x5C { escaped = true } else if byte == 0x22 { inString = false }
                continue
            }
            if byte == 0x22 { inString = true } else if byte == 0x7D || byte == 0x5D { depth -= 1 }
            guard byte == 0x7B || byte == 0x5B else { continue }
            depth += 1
            guard depth <= limit else { throw ImportError.tooLarge("JSON nests deeper than \(limit)") }
        }
    }
}

/// Any JSON value, decoded with Foundation's JSON decoder (which caps nesting).
enum LottieJSON: Decodable, Sendable, Hashable {
    case null, bool(Bool), number(Double), string(String), array([LottieJSON]), object([String: LottieJSON])

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null } else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: LottieJSON].self) { self = .object(v) }
        else if let v = try? c.decode([LottieJSON].self) { self = .array(v) } else { self = .bool(try c.decode(Bool.self)) }
    }

    subscript(key: String) -> LottieJSON? { if case .object(let o) = self { o[key] } else { nil } }
    var array: [LottieJSON]? { if case .array(let a) = self { a } else { nil } }
    var string: String? { if case .string(let s) = self { s } else { nil } }
    /// `true`, or the number 1 that some decoders hand back for it.
    var isTrue: Bool { self == .bool(true) || self == .number(1) }
}

/// A fill and stroke that geometry is painted with.
struct LottieStyles {
    var fill: Fill?, stroke: Stroke?
    func over(_ other: LottieStyles) -> LottieStyles { LottieStyles(fill: fill ?? other.fill, stroke: stroke ?? other.stroke) }

    /// The styles with every alpha times `opacity`.
    func faded(_ opacity: Double) -> LottieStyles {
        func fade(_ c: Color) -> Color { Color(r: c.r, g: c.g, b: c.b, a: c.a * opacity) }
        func fade(_ s: [GradientStop]) -> [GradientStop] { s.map { GradientStop(offset: $0.offset, color: fade($0.color)) } }
        var result = self
        switch fill {
        case .solid(let c)?: result.fill = .solid(fade(c))
        case .linear(let stops, let start, let end)?: result.fill = .linear(stops: fade(stops), start: start, end: end)
        case .radial(let stops, let center, let radius)?: result.fill = .radial(stops: fade(stops), center: center, radius: radius)
        case nil: break
        }
        if let stroke { result.stroke?.color = fade(stroke.color) }
        return result
    }
}

/// A path vertex with its tangents, which are relative to it.
struct LottieKnot {
    var vertex, tangentIn, tangentOut: Point
    /// The segment from `a` to `b`: a line when both tangents are zero.
    static func segment(_ a: LottieKnot, _ b: LottieKnot) -> PathElement {
        let zero = Point(x: 0, y: 0)
        guard a.tangentOut != zero || b.tangentIn != zero else { return .line(to: b.vertex) }
        let c1 = Point(x: a.vertex.x + a.tangentOut.x, y: a.vertex.y + a.tangentOut.y)
        let c2 = Point(x: b.vertex.x + b.tangentIn.x, y: b.vertex.y + b.tangentIn.y)
        return .cubic(control1: c1, control2: c2, to: b.vertex)
    }
}

/// One import's walk over the file, counting what it skips.
struct LottieReader {
    private var counts: [String: Int] = [:]
    /// The report kind a keyframed property counts as.
    private var animatedKind = "animated property"

    var report: ImportReport { ImportReport(skipped: counts.keys.sorted().map { "\($0) (\(counts[$0] ?? 0))" }) }
    mutating func skip(_ kind: String, _ count: Int = 1) { counts[kind, default: 0] += count }

    mutating func scene(_ root: LottieJSON, layers json: LottieJSON) throws -> Scene {
        guard let layers = json.array else { throw ImportError.damaged("layers is not an array") }
        guard layers.count <= LottieImport.maxLayers else { throw ImportError.tooLarge("\(layers.count) layers, limit \(LottieImport.maxLayers)") }
        let fps = try frame(root["fr"], "fr", 30, 1...240)
        let ip = try frame(root["ip"], "ip", 0, LottieImport.frames), op = try frame(root["op"], "op", 60, LottieImport.frames)
        let w = try number(root["w"], "w", 0), h = try number(root["h"], "h", 0)
        guard w > 0, h > 0, op >= ip else { throw ImportError.damaged("canvas size or frame range \(ip)...\(op) out of order") }
        var out: [Layer] = []
        for json in layers.reversed() {
            if let layer = try layer(json, id: "layer-\(out.count + 1)", range: Double(ip)...Double(op)) { out.append(layer) }
        }
        return Scene(id: "scene-1", name: root["nm"]?.string ?? "Scene 1", fps: fps, durationFrames: op - ip, width: w, height: h, layers: out)
    }
    mutating func layer(_ json: LottieJSON, id: String, range: ClosedRange<Double>) throws -> Layer? {
        let kinds: [Double: String] = [0: "precomp", 2: "image", 3: "null", 5: "text"]
        let ty = try number(json["ty"], "layer ty", -1)
        guard ty == 1 || ty == 4 else { skip(kinds[ty] ?? "layer type"); return nil }
        let (transform, anchor, opacity) = try placement(json["ks"])
        let root = Matrix.translation(x: -anchor.x, y: -anchor.y)
        var shapes = try group(json["shapes"]?.array ?? [], matrix: root, opacity: 1, inherited: LottieStyles(), depth: 0)
        if ty == 1 {
            let rect = Rect(minX: 0, minY: 0, maxX: try number(json["sw"], "solid width", 0), maxY: try number(json["sh"], "solid height", 0))
            shapes = [Shape(points: [], fill: .solid(try hexColor(json["sc"])), path: try PathBuilders.rectangle(in: rect).transformed(by: root))]
        }
        let values = ["x": transform.x, "y": transform.y, "scaleX": transform.scaleX, "scaleY": transform.scaleY,
                      "rotation": transform.rotation, "opacity": min(max(opacity, 0), 1)]
        var layer = Layer(id: id, name: json["nm"]?.string ?? "Layer", shapes: shapes.reversed())
        layer.tracks = values.filter { Layer.standardDefaults[$0.key] != $0.value }.mapValues { [Keyframe(frame: 0, value: $0)] }
        layer.isVisible = !(json["hd"]?.isTrue ?? false) && !(json["td"]?.isTrue ?? false)
        // VI-7: masks become `LayerMask`s, `tt` a `TrackMatte`, in and out points and parents are read.
        if let masks = json["masksProperties"]?.array, !masks.isEmpty { skip("mask", masks.count) }
        if json["tt"] != nil { skip("matte") }
        if json["parent"] != nil { skip("parent") }
        let inPoint = try number(json["ip"], "layer ip", range.lowerBound), outPoint = try number(json["op"], "layer op", range.upperBound)
        if inPoint > range.lowerBound || outPoint < range.upperBound { skip("layer in/out") }
        _ = try frame(json["st"], "st", 0, LottieImport.frames)
        return layer
    }
    /// The shapes of one group's items, top first.
    mutating func group(_ items: [LottieJSON], matrix outer: Matrix, opacity outerOpacity: Double,
                        inherited outerStyles: LottieStyles, depth: Int) throws -> [Shape] {
        guard depth < LottieImport.maxDepth else { throw ImportError.tooLarge("groups nest deeper than \(LottieImport.maxDepth)") }
        var matrix = outer, opacity = outerOpacity, inherited = outerStyles
        if let tr = items.first(where: { $0["ty"]?.string == "tr" }) {
            let (t, anchor, o) = try placement(tr, group: true)
            matrix = outer * t.matrix * Matrix.translation(x: -anchor.x, y: -anchor.y)
            (opacity, inherited) = (opacity * o, inherited.faded(o))
        }
        let visible = items.filter { !($0["hd"]?.isTrue ?? false) }
        if visible.count < items.count { skip("hidden item", items.count - visible.count) }
        var own = LottieStyles(), geometry: [PathElement] = []
        for item in visible {
            switch item["ty"]?.string {
            case "sh": geometry += try bezier(item["ks"]).transformed(by: matrix).elements
            case "rc":
                let radius = try scalar(item["r"], "rect roundness", 0)
                geometry += try PathBuilders.rectangle(in: box(item), cornerRadius: radius).transformed(by: matrix).elements
            case "el": geometry += try PathBuilders.ellipse(in: box(item)).transformed(by: matrix).elements
            case "fl": if own.fill == nil { own.fill = .solid(try color(item, opacity)) }
            case "gf": if own.fill == nil { own.fill = try gradient(item, matrix: matrix, opacity: opacity) }
            case "st": if own.stroke == nil { own.stroke = try stroke(item, matrix: matrix, opacity: opacity) }
            case "gr", "tr": break
            case let other: skip("shape item \(other ?? "?")")
            }
        }
        let styles = own.over(inherited)
        let shape = Shape(points: [], fill: styles.fill ?? .solid(Color(r: 0, g: 0, b: 0, a: 0)),
                          path: Path(elements: geometry), stroke: styles.stroke)
        let drawn = !geometry.isEmpty && (styles.fill != nil || styles.stroke != nil)
        if !geometry.isEmpty && !drawn { skip("unstyled path") }
        var shapes: [Shape] = [], placed = !drawn
        for item in visible {
            switch item["ty"]?.string {
            case "gr":
                shapes += try group(item["it"]?.array ?? [], matrix: matrix, opacity: opacity, inherited: styles, depth: depth + 1)
            case "fl", "gf", "st": if !placed { shapes.append(shape) }; placed = true
            default: break
            }
        }
        if !placed { shapes.append(shape) }
        return shapes
    }
    /// An `rc` or `el` item's box: `s` wide and tall around `p`.
    mutating func box(_ item: LottieJSON) throws -> Rect {
        let c = try point(item["p"], "shape position"), s = try point(item["s"], "shape size")
        return Rect(minX: c.x - s.x / 2, minY: c.y - s.y / 2, maxX: c.x + s.x / 2, maxY: c.y + s.y / 2)
    }
    /// An `sh` bezier as a path.
    mutating func bezier(_ property: LottieJSON?) throws -> Path {
        var value = property?["k"]
        if property?["a"]?.isTrue ?? false {
            skip("animated property")  // VI-7: a `ShapeTrack`
            value = try firstKey(value)?.array?.first
        }
        guard let value else { throw ImportError.damaged("path has no value") }
        let v = try points(value["v"], "path vertices"), i = try points(value["i"], "path in tangents")
        let o = try points(value["o"], "path out tangents")
        guard i.count == v.count, o.count == v.count else { throw ImportError.damaged("path tangents do not match its vertices") }
        let knots = zip(v, zip(i, o)).map { LottieKnot(vertex: $0, tangentIn: $1.0, tangentOut: $1.1) }
        guard let first = knots.first, let last = knots.last else { return Path() }
        var elements: [PathElement] = [.move(to: first.vertex)]
        for (a, b) in zip(knots, knots.dropFirst()) { elements.append(LottieKnot.segment(a, b)) }
        if value["c"]?.isTrue ?? false { elements += [LottieKnot.segment(last, first), .close] }
        return Path(elements: elements)
    }
    /// A `ks` or `tr` transform: position, scale, rotation, its anchor and opacity in 0...1.
    mutating func placement(_ json: LottieJSON?, group: Bool = false) throws -> (Transform, anchor: Point, opacity: Double) {
        defer { animatedKind = "animated property" }
        animatedKind = group ? "group animation" : "anchor animation"
        let anchor = try point(json?["a"], "anchor")
        if !group { animatedKind = "animated property" }
        var p = try point(json?["p"], "position")
        if json?["p"]?["s"]?.isTrue ?? false {
            p = Point(x: try scalar(json?["p"]?["x"], "position x", 0), y: try scalar(json?["p"]?["y"], "position y", 0))
        }
        let s = try values(json?["s"], "scale", [100, 100])
        guard s.count >= 2 else { throw ImportError.damaged("scale needs two values") }
        if try scalar(json?["sk"], "skew", 0) != 0 { skip("skew") }
        let transform = Transform(x: p.x, y: p.y, scaleX: s[0] / 100, scaleY: s[1] / 100, rotation: try scalar(json?["r"], "rotation", 0))
        return (transform, anchor, try scalar(json?["o"], "opacity", 100) / 100)
    }
    mutating func color(_ item: LottieJSON, _ opacity: Double) throws -> Color {
        let c = try values(item["c"], "color", [0, 0, 0])
        guard c.count >= 3 else { throw ImportError.damaged("color needs three channels") }
        let a = min(max(try scalar(item["o"], "opacity", 100) / 100, 0), 1) * opacity
        return Color(r: min(max(c[0], 0), 1), g: min(max(c[1], 0), 1), b: min(max(c[2], 0), 1), a: a)
    }
    mutating func stroke(_ item: LottieJSON, matrix: Matrix, opacity: Double) throws -> Stroke {
        if item["d"] != nil { skip("dash") }
        let width = max(try scalar(item["w"], "stroke width", 1), 0) * abs(matrix.determinant).squareRoot()
        let caps: [Double: Stroke.Cap] = [2: .round, 3: .square], joins: [Double: Stroke.Join] = [2: .round, 3: .bevel]
        return Stroke(color: try color(item, opacity), width: width,
                      join: joins[try number(item["lj"], "line join", 1)] ?? .miter, cap: caps[try number(item["lc"], "line cap", 1)] ?? .butt)
    }
    /// A `gf` gradient: `g.p` stops of offset, r, g, b, then optionally offset, alpha for each.
    mutating func gradient(_ item: LottieJSON, matrix: Matrix, opacity: Double) throws -> Fill {
        let start = matrix.apply(try point(item["s"], "gradient start")), end = matrix.apply(try point(item["e"], "gradient end"))
        let count = try number(item["g"]?["p"], "gradient stop count", 0)
        let flat = try values(item["g"]?["k"], "gradient stops", [])
        guard count >= 1, count == count.rounded(), count * 4 <= Double(flat.count) else { throw ImportError.damaged("gradient stops do not match") }
        let n = Int(count), alphas = Array(flat.dropFirst(4 * n))
        let fade = min(max(try scalar(item["o"], "opacity", 100) / 100, 0), 1) * opacity
        let stops = (0..<n).map { k in
            let alpha = alphas.count >= 2 * n ? min(max(alphas[2 * k + 1], 0), 1) : 1
            let rgb = flat[(4 * k + 1)...(4 * k + 3)].map { min(max($0, 0), 1) }
            return GradientStop(offset: min(max(flat[4 * k], 0), 1), color: Color(r: rgb[0], g: rgb[1], b: rgb[2], a: alpha * fade))
        }.sorted { $0.offset < $1.offset }
        guard try number(item["t"], "gradient type", 1) == 2 else { return .linear(stops: stops, start: start, end: end) }
        let radius = norm(end.x - start.x, end.y - start.y)
        guard radius > 0, radius.isFinite, start.x + radius != start.x else { return .solid(stops.last?.color ?? .black) }
        return .radial(stops: stops, center: start, radius: radius)
    }
    /// A solid's `sc`, "#rrggbb".
    func hexColor(_ json: LottieJSON?) throws -> Color {
        let hex = (json?.string ?? "").drop { $0 == "#" }
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit), let v = UInt32(hex, radix: 16) else { throw ImportError.damaged("solid color is not #rrggbb") }
        return Color(r: Double(v >> 16 & 0xFF) / 255, g: Double(v >> 8 & 0xFF) / 255, b: Double(v & 0xFF) / 255)
    }
    func number(_ json: LottieJSON?, _ what: String, _ fallback: Double) throws -> Double {
        guard let json else { return fallback }
        guard case .number(let v) = json, v.isFinite else { throw ImportError.damaged("\(what) is not a finite number") }
        return v
    }
    /// A frame field, rounded and converted with `Int(exactly:)`, in `range`.
    func frame(_ json: LottieJSON?, _ field: String, _ fallback: Double, _ range: ClosedRange<Int>) throws -> Int {
        let v = try number(json, field, fallback).rounded()
        guard let n = Int(exactly: v), range.contains(n) else { throw ImportError.damaged("\(field) \(v) is outside \(range)") }
        return n
    }
    /// Keyframes `k`'s first value, once every key's `t` is in range.
    func firstKey(_ k: LottieJSON?) throws -> LottieJSON? {
        for key in k?.array ?? [] { _ = try frame(key["t"], "keyframe t", 0, LottieImport.frames) }
        return k?.array?.first?["s"]
    }
    /// A property's numbers: its static `k`, or the first key's value when animated.
    mutating func values(_ property: LottieJSON?, _ what: String, _ fallback: [Double]) throws -> [Double] {
        guard let property else { return fallback }
        if property["x"] != nil { skip("expression") }
        var k = property["k"]
        if property["a"]?.isTrue ?? false {
            skip(animatedKind)  // VI-7: keyframes become tracks
            k = try firstKey(k)
            if k == nil { return fallback }
        }
        switch k {
        case .number?: return [try number(k, what, 0)]
        case .array(let list)?: return try list.map { try number($0, what, 0) }
        default: throw ImportError.damaged("\(what) has no value")
        }
    }
    mutating func scalar(_ property: LottieJSON?, _ what: String, _ fallback: Double) throws -> Double {
        try values(property, what, [fallback]).first ?? fallback
    }
    mutating func point(_ property: LottieJSON?, _ what: String) throws -> Point {
        let v = try values(property, what, [0, 0])
        guard v.count >= 2 else { throw ImportError.damaged("\(what) needs two values") }
        return Point(x: v[0], y: v[1])
    }
    func points(_ json: LottieJSON?, _ what: String) throws -> [Point] {
        guard let list = json?.array else { throw ImportError.damaged("\(what) is not an array") }
        return try list.map { pair in
            guard let xy = pair.array, xy.count >= 2 else { throw ImportError.damaged("\(what) needs pairs") }
            return Point(x: try number(xy[0], what, 0), y: try number(xy[1], what, 0))
        }
    }
}
