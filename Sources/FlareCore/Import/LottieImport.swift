// LottieImport.swift: the Lottie reader's shapes, solids, styles and static transform.
//
// From the public Lottie format docs; docs/blueprints/core/features/vector-import.md
// gives the rules. Layers and shape items are listed top first, so both are
// reversed; each group (`gr`) becomes one shape. Keys, masks, mattes: LottieImport+Animation.swift.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension LottieImport {
    /// The frames `ip`, `op` and keyframe `t` may name; a layer's `st` may also be as negative.
    static let frames = 0...1_000_000

    static func read(_ data: Data) throws -> (Document, ImportReport) {
        guard data.count <= maxBytes else { throw ImportError.tooLarge("file is \(data.count) bytes, limit \(maxBytes)") }
        let space: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]
        guard data.first(where: { !space.contains($0) }) == UInt8(ascii: "{") else { throw ImportError.notThisFormat }
        try checkNesting(data, limit: 2 * maxDepth + 12)  // 512, Foundation's decoder cap that the parser keeps
        let root = try LottieJSON.parse(data)
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

/// Any JSON value, read by `parse` (nesting is capped by `LottieImport.checkNesting` first).
/// Equatable but not Hashable: a synthesized `==` or `hash(into:)` recurses once per nesting level.
enum LottieJSON: Sendable, Equatable {
    case null, bool(Bool), number(Double), string(String), array([LottieJSON]), object([String: LottieJSON])

    /// Compares with an explicit stack of pairs, so a deep value needs no more call stack than a flat one.
    static func == (lhs: LottieJSON, rhs: LottieJSON) -> Bool {
        var pending = [(lhs, rhs)]
        while let pair = pending.popLast() {
            switch pair {
            case (.null, .null): continue
            case (.bool(let a), .bool(let b)) where a == b: continue
            case (.number(let a), .number(let b)) where a == b: continue
            case (.string(let a), .string(let b)) where a == b: continue
            case (.array(let a), .array(let b)) where a.count == b.count: pending += zip(a, b)
            case (.object(let a), .object(let b)) where a.count == b.count:
                for (key, value) in a {
                    guard let other = b[key] else { return false }
                    pending.append((value, other))
                }
            default: return false
            }
        }
        return true
    }

    /// Parses JSON (RFC 8259) with an explicit stack of open containers: Foundation's decoder
    /// recurses per nesting level, which overflows the 512 KB stack of a secondary thread on macOS.
    /// A repeated key keeps its first value and a trailing comma is taken, as Foundation's decoder
    /// does. Throws `damaged("not valid JSON")` for anything else, including invalid UTF-8, a lone
    /// surrogate escape and a number past `Double`'s range.
    static func parse(_ data: Data) throws -> LottieJSON {
        let bad = ImportError.damaged("not valid JSON"), b = [UInt8](data)
        var i = 0
        func at(_ c: Unicode.Scalar) -> Bool { i < b.count && b[i] == UInt8(ascii: c) }
        func space() { while i < b.count, b[i] == 0x20 || b[i] == 0x09 || b[i] == 0x0A || b[i] == 0x0D { i += 1 } }
        func expect(_ c: Unicode.Scalar) throws { space(); guard at(c) else { throw bad }; i += 1 }
        func hex() throws -> UInt32 {
            guard i + 4 <= b.count, let v = UInt32(String(decoding: b[i..<(i + 4)], as: UTF8.self), radix: 16),
                  b[i..<(i + 4)].allSatisfy({ $0 != UInt8(ascii: "+") && $0 != UInt8(ascii: "-") }) else { throw bad }
            i += 4
            return v
        }
        func string() throws -> String {
            try expect("\"")
            var bytes: [UInt8] = []
            while true {
                guard i < b.count, b[i] >= 0x20 else { throw bad }
                let c = b[i]; i += 1
                if c == UInt8(ascii: "\"") { break }
                guard c == UInt8(ascii: "\\") else { bytes.append(c); continue }
                guard i < b.count else { throw bad }
                let e = b[i]; i += 1
                let simple: [UInt8: UInt8] = [0x22: 0x22, 0x5C: 0x5C, 0x2F: 0x2F, 0x62: 0x08, 0x66: 0x0C, 0x6E: 0x0A, 0x72: 0x0D, 0x74: 0x09]
                if let s = simple[e] { bytes.append(s); continue }
                guard e == UInt8(ascii: "u") else { throw bad }
                var v = try hex()
                if (0xD800..<0xDC00).contains(v) {
                    guard at("\\"), i + 1 < b.count, b[i + 1] == UInt8(ascii: "u") else { throw bad }
                    i += 2
                    let low = try hex()
                    guard (0xDC00..<0xE000).contains(low) else { throw bad }
                    v = 0x10000 + (v - 0xD800) << 10 + (low - 0xDC00)
                }
                guard let scalar = Unicode.Scalar(v) else { throw bad }
                bytes += Array(String(scalar).utf8)
            }
            var text = String.UnicodeScalarView(), it = bytes.makeIterator(), utf8 = UTF8()
            while true {
                switch utf8.decode(&it) {
                case .scalarValue(let s): text.append(s)
                case .emptyInput: return String(text)
                case .error: throw bad
                }
            }
        }
        func number() throws -> Double {
            let start = i
            func digits() -> Int { let s = i; while i < b.count, (0x30...0x39).contains(b[i]) { i += 1 }; return i - s }
            if at("-") { i += 1 }
            if at("0") { i += 1 } else { guard digits() > 0 else { throw bad } }
            if at(".") { i += 1; guard digits() > 0 else { throw bad } }
            if at("e") || at("E") { i += 1; if at("+") || at("-") { i += 1 }; guard digits() > 0 else { throw bad } }
            guard let v = Double(String(decoding: b[start..<i], as: UTF8.self)), v.isFinite else { throw bad }
            return v
        }
        func key() throws -> String { let k = try string(); try expect(":"); return k }
        // Each open container: an array's items, or an object's members and the key its next value goes under.
        // Containers are filled in place, so appending never copies them.
        var open: [(isObject: Bool, items: [LottieJSON], members: [String: LottieJSON], key: String)] = []
        scan: while true {
            space()
            var value: LottieJSON
            if at("{") {
                i += 1; space()
                guard at("}") else { open.append((true, [], [:], try key())); continue }
                i += 1; value = .object([:])
            } else if at("[") {
                i += 1; space()
                guard at("]") else { open.append((false, [], [:], "")); continue }
                i += 1; value = .array([])
            } else if at("\"") { value = .string(try string())
            } else if let (word, v) = [("true", LottieJSON.bool(true)), ("false", .bool(false)), ("null", .null)]
                .first(where: { b[i...].starts(with: $0.0.utf8) }) { i += word.utf8.count; value = v
            } else { value = .number(try number()) }
            // Hand the value to its container, closing each container it completes.
            while let top = open.indices.last {
                let k = open[top].key
                if !open[top].isObject { open[top].items.append(value) } else if open[top].members[k] == nil { open[top].members[k] = value }
                let close: Unicode.Scalar = open[top].isObject ? "}" : "]"
                space()
                if at(",") {
                    i += 1; space()
                    // A comma before the close is taken, as Foundation's decoder takes it.
                    if !at(close) {
                        if open[top].isObject { open[top].key = try key() }
                        continue scan
                    }
                }
                try expect(close)
                let done = open.removeLast()
                value = done.isObject ? .object(done.members) : .array(done.items)
            }
            space()
            guard i == b.count else { throw bad }
            return value
        }
    }

    subscript(key: String) -> LottieJSON? { if case .object(let o) = self { o[key] } else { nil } }
    var array: [LottieJSON]? { if case .array(let a) = self { a } else { nil } }
    var string: String? { if case .string(let s) = self { s } else { nil } }
    /// `true`, or the number 1 that some decoders hand back for it.
    var isTrue: Bool { self == .bool(true) || self == .number(1) }
}

/// A fill and stroke that geometry is painted with.
struct LottieStyles {
    var fill: Fill?, stroke: Stroke?, keys = LottieStyleKeys()
    func over(_ other: LottieStyles) -> LottieStyles {
        LottieStyles(fill: fill ?? other.fill, stroke: stroke ?? other.stroke, keys: keys.over(other.keys, fill: fill != nil, stroke: stroke != nil))
    }

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
        result.keys = keys.faded(opacity)
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
    var animatedKind: String? = "animated property"
    var clock = LottieClock()

    var report: ImportReport { ImportReport(skipped: counts.keys.sorted().map { "\($0) (\(counts[$0] ?? 0))" }) }
    mutating func skip(_ kind: String, _ count: Int = 1) { counts[kind, default: 0] += count }

    mutating func scene(_ root: LottieJSON, layers json: LottieJSON) throws -> Scene {
        guard let layers = json.array else { throw ImportError.damaged("layers is not an array") }
        guard layers.count <= LottieImport.maxLayers else { throw ImportError.tooLarge("\(layers.count) layers, limit \(LottieImport.maxLayers)") }
        let fps = try frame(root["fr"], "fr", 30, 1...240)
        let ip = try frame(root["ip"], "ip", 0, LottieImport.frames), op = try frame(root["op"], "op", 60, LottieImport.frames)
        let w = try number(root["w"], "w", 0), h = try number(root["h"], "h", 0)
        guard w > 0 else { throw ImportError.damaged("w \(w) is not positive") }
        guard h > 0 else { throw ImportError.damaged("h \(h) is not positive") }
        guard op >= ip else { throw ImportError.damaged("ip/op \(ip)...\(op) out of order") }
        var out: [Layer] = [], built: [Int: Int] = [:]
        clock = LottieClock(ip: ip, duration: op - ip)
        for (index, json) in layers.enumerated().reversed() {
            if let layer = try layer(json, id: "layer-\(out.count + 1)", range: Double(ip)...Double(op)) { built[index] = out.count; out.append(layer) }
        }
        linkMattes(&out, layers, built: built)
        return Scene(id: "scene-1", name: root["nm"]?.string ?? "Scene 1", fps: fps, durationFrames: op - ip, width: w, height: h, layers: out)
    }
    mutating func layer(_ json: LottieJSON, id: String, range: ClosedRange<Double>) throws -> Layer? {
        let kinds: [Double: String] = [0: "precomp", 2: "image", 3: "null", 5: "text"]
        let ty = try number(json["ty"], "layer ty", -1)
        guard ty == 1 || ty == 4 else { skip(kinds[ty] ?? "layer type"); return nil }
        clock.start = try frame(json["st"], "st", 0, -LottieImport.frames.upperBound...LottieImport.frames.upperBound)
        let (transform, anchor, opacity) = try placement(json["ks"])
        let root = Matrix.translation(x: -anchor.x, y: -anchor.y)
        var shapes = try group(json["shapes"]?.array ?? [], matrix: root, opacity: 1, inherited: LottieStyles(), depth: 0)
        if ty == 1 {
            let rect = Rect(minX: 0, minY: 0, maxX: try number(json["sw"], "solid width", 0), maxY: try number(json["sh"], "solid height", 0))
            shapes = [LottieShape(shape: Shape(points: [], fill: .solid(try hexColor(json["sc"])), path: try PathBuilders.rectangle(in: rect).transformed(by: root)))]
        }
        let values = ["x": transform.x, "y": transform.y, "scaleX": transform.scaleX, "scaleY": transform.scaleY,
                      "rotation": transform.rotation, "opacity": opacity]
        var layer = Layer(id: id, name: json["nm"]?.string ?? "Layer")
        layer.tracks = values.filter { Layer.standardDefaults[$0.key] != $0.value }.mapValues { [Keyframe(frame: 0, value: $0)] }
        layer.tracks.merge(try transformTracks(json["ks"])) { $1 }
        place(shapes.reversed(), on: &layer)
        layer.isVisible = !(json["hd"]?.isTrue ?? false) && !(json["td"]?.isTrue ?? false)
        layer.masks = try masks(json["masksProperties"]?.array ?? [], root: root)
        if json["parent"] != nil { skip("parent") }
        let inPoint = try number(json["ip"], "layer ip", range.lowerBound), outPoint = try number(json["op"], "layer op", range.upperBound)
        if inPoint > range.lowerBound || outPoint < range.upperBound { skip("layer in/out") }
        return layer
    }
    /// The shapes of one group's items, top first. Nested groups are walked with an explicit stack:
    /// recursing `maxDepth` deep overflows the 512 KB stack of a secondary thread on macOS.
    mutating func group(_ items: [LottieJSON], matrix: Matrix, opacity: Double,
                        inherited: LottieStyles, depth: Int) throws -> [LottieShape] {
        var open = [try groupFrame(items, matrix: matrix, opacity: opacity, inherited: inherited, depth: depth)]
        while let top = open.indices.last {
            guard open[top].next < open[top].items.count else {
                var done = open.removeLast()
                if !done.placed { done.shapes.append(done.shape) }
                guard top > 0 else { return done.shapes }
                open[top - 1].shapes += done.shapes
                continue
            }
            let item = open[top].items[open[top].next]
            open[top].next += 1
            switch item["ty"]?.string {
            case "gr":
                let f = open[top]
                open.append(try groupFrame(item["it"]?.array ?? [], matrix: f.matrix, opacity: f.opacity, inherited: f.styles, depth: f.depth + 1))
            case "fl", "gf", "st": if !open[top].placed { open[top].shapes.append(open[top].shape) }; open[top].placed = true
            default: break
            }
        }
        return []
    }
    /// One group being walked: its visible items and the next to place, what they inherit, and
    /// its own shape, which goes in at its first fill or stroke (at the end when none).
    struct GroupFrame {
        var items: [LottieJSON], next = 0, matrix: Matrix, opacity: Double, styles: LottieStyles, depth: Int
        var shape: LottieShape, placed: Bool, shapes: [LottieShape] = []
    }
    /// A group's frame: its transform and styles applied and its geometry built into one shape.
    mutating func groupFrame(_ items: [LottieJSON], matrix outer: Matrix, opacity outerOpacity: Double,
                             inherited outerStyles: LottieStyles, depth: Int) throws -> GroupFrame {
        // `depth` 0 is the layer's own shapes, so exactly `maxDepth` nested groups read.
        guard depth <= LottieImport.maxDepth else { throw ImportError.tooLarge("groups nest deeper than \(LottieImport.maxDepth)") }
        var matrix = outer, opacity = outerOpacity, inherited = outerStyles
        if let tr = items.first(where: { $0["ty"]?.string == "tr" }) {
            let (t, anchor, o) = try placement(tr, group: true)
            matrix = outer * t.matrix * Matrix.translation(x: -anchor.x, y: -anchor.y)
            (opacity, inherited) = (opacity * o, inherited.faded(o))
        }
        let visible = items.filter { !($0["hd"]?.isTrue ?? false) }
        if visible.count < items.count { skip("hidden item", items.count - visible.count) }
        var own = LottieStyles(), geometry: [PathElement] = [], keyed: [LottieKeyedPart] = []
        for item in visible {
            switch item["ty"]?.string {
            case "sh": try outline(item["ks"], matrix: matrix, into: &geometry, keyed: &keyed)
            case "rc":
                let radius = try scalar(item["r"], "rect roundness", 0)
                geometry += try PathBuilders.rectangle(in: box(item), cornerRadius: radius).transformed(by: matrix).elements
            case "el": geometry += try PathBuilders.ellipse(in: box(item)).transformed(by: matrix).elements
            case "fl": if own.fill == nil { let c = try color(item, opacity); own.fill = .solid(c); own.keys.fill = try colorKeys(item["c"], alpha: c.a) }
            case "gf": if own.fill == nil { own.fill = try gradient(item, matrix: matrix, opacity: opacity) }
            case "st" where own.stroke == nil:  // keyed colour and width become tracks, the width scaled like the stroke
                let s = try stroke(item, matrix: matrix, opacity: opacity), scale = abs(matrix.determinant).squareRoot()
                (own.stroke, own.keys.stroke, own.keys.width) = (s, try colorKeys(item["c"], alpha: s.color.a), try track(item["w"], 0) { max($0, 0) * scale })
            case "gr", "tr", "st": break
            case let other?: skip("shape item \(other)")
            case nil: skip("shape item without a type")
            }
        }
        let styles = own.over(inherited)
        let shape = LottieShape(shape: Shape(points: [], fill: styles.fill ?? .solid(Color(r: 0, g: 0, b: 0, a: 0)),
                                             path: Path(elements: geometry), stroke: styles.stroke),
                                keys: styles.keys, path: pathKeys(geometry, keyed))
        let drawn = !geometry.isEmpty && (styles.fill != nil || styles.stroke != nil)
        if !geometry.isEmpty && !drawn { skip("unstyled path") }
        return GroupFrame(items: visible, matrix: matrix, opacity: opacity, styles: styles, depth: depth, shape: shape, placed: !drawn)
    }
    /// An `rc` or `el` item's box: `s` wide and tall around `p`.
    mutating func box(_ item: LottieJSON) throws -> Rect {
        let c = try point(item["p"], "shape position"), s = try point(item["s"], "shape size")
        return Rect(minX: c.x - s.x / 2, minY: c.y - s.y / 2, maxX: c.x + s.x / 2, maxY: c.y + s.y / 2)
    }
    /// An `sh` bezier as a path: its static `k`, or its first key's.
    func bezier(_ property: LottieJSON?) throws -> Path {
        var value = property?["k"]
        if property?["a"]?.isTrue ?? false { value = try firstKey(value).map { $0.array?.first ?? $0 } }
        guard let value else { throw ImportError.damaged("path has no value") }
        return try path(value)
    }
    /// One bezier value, `{"c", "v", "i", "o"}`, as a path.
    func path(_ value: LottieJSON) throws -> Path {
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
        if !group { animatedKind = nil }  // keyed p, s, r and o become tracks in `transformTracks`
        let p = json?["p"]?["s"]?.isTrue ?? false
            ? Point(x: try scalar(json?["p"]?["x"], "position x", 0), y: try scalar(json?["p"]?["y"], "position y", 0))
            : try point(json?["p"], "position")
        let s = try values(json?["s"], "scale", [100, 100])
        guard s.count >= 2 else { throw ImportError.damaged("scale needs two values") }
        if try scalar(json?["sk"], "skew", 0) != 0 { skip("skew") }
        let transform = Transform(x: p.x, y: p.y, scaleX: s[0] / 100, scaleY: s[1] / 100, rotation: try scalar(json?["r"], "rotation", 0))
        return (transform, anchor, min(max(try scalar(json?["o"], "opacity", 100) / 100, 0), 1))
    }
    mutating func color(_ item: LottieJSON, _ opacity: Double) throws -> Color {
        let c = try values(item["c"], "color", [0, 0, 0], tracked: true)  // keys become a colour track
        return try Self.rgb(c, a: min(max(try scalar(item["o"], "opacity", 100) / 100, 0), 1) * opacity)
    }
    mutating func stroke(_ item: LottieJSON, matrix: Matrix, opacity: Double) throws -> Stroke {
        if item["d"] != nil { skip("dash") }
        let width = max(try scalar(item["w"], "stroke width", 1, tracked: true), 0) * abs(matrix.determinant).squareRoot()
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
    mutating func values(_ property: LottieJSON?, _ what: String, _ fallback: [Double], tracked: Bool = false) throws -> [Double] {
        guard let property else { return fallback }
        if property["x"] != nil { skip("expression") }
        var k = property["k"]
        if property["a"]?.isTrue ?? false {
            if let animatedKind, !tracked { skip(animatedKind) }
            k = try firstKey(k)
            if k == nil { return fallback }
        }
        switch k {
        case .number?: return [try number(k, what, 0)]
        case .array(let list)?: return try list.map { try number($0, what, 0) }
        default: throw ImportError.damaged("\(what) has no value")
        }
    }
    mutating func scalar(_ property: LottieJSON?, _ what: String, _ fallback: Double, tracked: Bool = false) throws -> Double {
        try values(property, what, [fallback], tracked: tracked).first ?? fallback
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
