// SVGImport.swift: the SVG document reader, from the W3C SVG 1.1 and SVG 2
// specs only. The bounded tokenizer gives the element tree; each top-level
// drawable child of the root becomes one layer, with every transform baked
// into its geometry. Basic shapes and paths become shapes, and solid paint in
// presentation attributes and `style` become fills and strokes. Every other
// element is skipped with its subtree and counted in the report by name, as
// is anything else the model cannot hold, such as a `clip-path` or a gradient.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension SVGImport {
    static func read(_ data: Data, name: String) throws -> (Scene, ImportReport) {
        guard data.count <= maxBytes else { throw ImportError.tooLarge("file is \(data.count) bytes, limit \(maxBytes)") }
        let space: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D, 0xEF, 0xBB, 0xBF]
        guard data.first(where: { !space.contains($0) }) == UInt8(ascii: "<") else { throw ImportError.notThisFormat }
        var reader = try SVGReader(try XMLTokens.tokens(data))
        let scene = try reader.scene(name: name)
        do { try FlareFormat.validate(Document(scenes: [scene])) } catch FormatError.tooLarge(let message) {
            throw ImportError.tooLarge(message)
        } catch { throw ImportError.damaged("imported scene does not validate: \(error)") }
        return (scene, ImportReport(skipped: reader.counts.keys.sorted().map { "\($0) (\(reader.counts[$0] ?? 0))" }))
    }
}

/// One element, its attributes by name (`xlink:href` keeps its prefix), or a run of text named `#text`.
struct SVGNode: Sendable {
    var name: String
    var attributes: [String: String] = [:]
    var children: [Int] = []
    var text = ""
}

/// The element tree and the walk that turns it into layers.
struct SVGReader {
    var nodes: [SVGNode] = []
    var ids: [String: Int] = [:]
    var counts: [String: Int] = [:]
    var size = (width: 1000.0, height: 1000.0)
    static let clear = Color(r: 0, g: 0, b: 0, a: 0)

    /// The tree of `tokens`; throws `notThisFormat` when the root element is not `svg`.
    init(_ tokens: [XMLToken]) throws {
        var open: [Int] = []
        for token in tokens {
            switch token {
            case .start(let tag, let attributes, let selfClosing):
                let local = String(tag.split(separator: ":").last ?? Substring(tag))
                let node = SVGNode(name: local, attributes: Dictionary(attributes.map { ($0.name, $0.value) }) { $1 })
                if let parent = open.last { nodes[parent].children.append(nodes.count) } else if !nodes.isEmpty { continue }
                if let id = node.attributes["id"], ids[id] == nil { ids[id] = nodes.count }
                if !selfClosing { open.append(nodes.count) }
                nodes.append(node)
            case .end: _ = open.popLast()
            case .text(let text):
                guard let parent = open.last else { continue }
                nodes[parent].children.append(nodes.count)
                nodes.append(SVGNode(name: "#text", text: text))
            }
        }
        guard nodes.first?.name == "svg" else { throw ImportError.notThisFormat }
    }

    mutating func count(_ kind: String) { counts[kind, default: 0] += 1 }

    mutating func scene(name: String) throws -> Scene {
        guard let root = nodes.first else { throw ImportError.notThisFormat }
        let a = root.attributes
        var base = Matrix.identity
        if let box = try? numbers(a["viewBox"] ?? ""), box.count == 4, box[2] > 0, box[3] > 0 {
            size = (box[2], box[3])
            base = .translation(x: -box[0], y: -box[1])
        } else {
            size = (positive(a["width"]) ?? 1000, positive(a["height"]) ?? 1000)
        }
        let style = SVGStyle().applying(a)
        var layers: [Layer] = []
        for child in root.children {
            let (shapes, texts) = try draw(child, base, style)
            guard !shapes.isEmpty || !texts.isEmpty else { continue }
            let node = nodes[child]
            layers.append(Layer(id: "layer-\(layers.count + 1)", name: node.attributes["id"] ?? node.name, shapes: shapes, texts: texts))
        }
        return Scene(id: "scene-1", name: name, width: size.width, height: size.height, layers: layers)
    }

    func positive(_ value: String?) -> Double? { value.flatMap { SVGStyle.length($0, of: 0) }.flatMap { $0 > 0 ? $0 : nil } }

    /// The shapes and texts of node `i` and its subtree, placed by `parent` times its own transform.
    /// Groups are walked depth first with an explicit stack: recursing `maxDepth` deep overflows
    /// the 512 KB stack of a secondary thread on macOS.
    mutating func draw(_ i: Int, _ parent: Matrix, _ inherited: SVGStyle) throws -> ([Shape], [TextShape]) {
        let silent: Set = ["#text", "title", "desc", "metadata", "linearGradient", "radialGradient", "clipPath", "stop"]
        // Each open group: its node, transform and style, its next child, and what its children drew.
        var open: [(node: Int, ctm: Matrix, style: SVGStyle, next: Int, out: ([Shape], [TextShape]))] = []
        var pending: (i: Int, parent: Matrix, inherited: SVGStyle)? = (i, parent, inherited)
        while true {
            var drawn: ([Shape], [TextShape]) = ([], [])
            if let (i, parent, inherited) = pending {
                pending = nil
                let node = nodes[i]
                if !silent.contains(node.name) {
                    let ctm = parent * (try transform(node.attributes["transform"]))
                    let style = inherited.applying(node.attributes)
                    if node.attributes["clip-path"] != nil { count("clip-path") }
                    switch node.name {
                    case "g", "a", "svg", "defs": open.append((i, ctm, style, 0, ([], []))); continue
                    default:
                        if let local = try outline(node) {
                            if !local.elements.isEmpty {
                                drawn.0 = [Shape(points: [], fill: fill(style), path: local.transformed(by: ctm), stroke: stroke(style, ctm))]
                            }
                        } else { count(node.name) }
                    }
                }
            } else if let top = open.indices.last {
                let children = nodes[open[top].node].children
                if open[top].next < children.count {
                    pending = (children[open[top].next], open[top].ctm, open[top].style)
                    open[top].next += 1
                    continue
                }
                let done = open.removeLast()
                if nodes[done.node].name != "defs" { drawn = done.out }
            }
            guard let top = open.indices.last else { return drawn }
            open[top].out.0 += drawn.0
            open[top].out.1 += drawn.1
        }
    }

    /// The node's outline in its own coordinates, empty when it draws nothing; nil when it is not a shape element.
    func outline(_ node: SVGNode) throws -> Path? {
        let (w, h) = size
        func len(_ key: String, _ reference: Double) -> Double { node.attributes[key].flatMap { SVGStyle.length($0, of: reference) } ?? 0 }
        let diagonal = ((w * w + h * h) / 2).squareRoot()
        switch node.name {
        case "path": return try SVGPathData.path(node.attributes["d"] ?? "")
        case "polyline", "polygon":
            return try SVGPathData.path("M" + (node.attributes["points"] ?? "") + (node.name == "polygon" ? "z" : ""))
        case "line":
            return Path(polyline: [Point(x: len("x1", w), y: len("y1", h)), Point(x: len("x2", w), y: len("y2", h))], closed: false)
        case "circle", "ellipse":
            let r = len("r", diagonal)
            let (rx, ry) = node.name == "circle" ? (r, r) : (len("rx", w), len("ry", h))
            let (cx, cy) = (len("cx", w), len("cy", h))
            guard rx > 0, ry > 0 else { return Path() }
            return try PathBuilders.ellipse(in: Rect(minX: cx - rx, minY: cy - ry, maxX: cx + rx, maxY: cy + ry))
        case "rect":
            let (x, y, width, height) = (len("x", w), len("y", h), len("width", w), len("height", h))
            guard width > 0, height > 0 else { return Path() }
            let given = { (key: String, reference: Double) in node.attributes[key].flatMap { SVGStyle.length($0, of: reference) }.flatMap { $0 >= 0 ? $0 : nil } }
            let rx = min(given("rx", w) ?? given("ry", h) ?? 0, width / 2), ry = min(given("ry", h) ?? given("rx", w) ?? 0, height / 2)
            guard rx > 0, ry > 0 else { return try PathBuilders.rectangle(in: Rect(minX: x, minY: y, maxX: x + width, maxY: y + height)) }
            let squash = rx / ry
            let round = try PathBuilders.rectangle(in: Rect(minX: x, minY: y * squash, maxX: x + width, maxY: (y + height) * squash), cornerRadius: rx)
            return round.transformed(by: .scale(x: 1, y: 1 / squash))
        default: return nil
        }
    }

    /// The numbers of an SVG number list, read with the path-data number grammar.
    func numbers(_ list: String) throws -> [Double] {
        try SVGPathData.path("M0 0H" + list).elements.dropFirst().compactMap { if case .line(let to) = $0 { to.x } else { nil } }
    }

    /// The matrix of a transform list; the leftmost entry is outermost. Throws `damaged` on a malformed or non-finite one.
    func transform(_ list: String?) throws -> Matrix {
        guard var rest = list?[...] else { return .identity }
        var m = Matrix.identity
        while let open = rest.firstIndex(of: "(") {
            let name = SVGStyle.trim(rest[..<open], extra: ",")
            guard let close = rest[open...].firstIndex(of: ")") else { throw ImportError.damaged("transform: no closing parenthesis") }
            let v = try numbers(String(rest[rest.index(after: open)..<close]))
            rest = rest[rest.index(after: close)...]
            let skew = v.first.map { Matrix.rotation(degrees: $0) }.map { $0.b / $0.a } ?? 0
            switch (name, v.count) {
            case ("matrix", 6): m = m * Matrix(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
            case ("translate", 1...2): m = m * .translation(x: v[0], y: v.count == 2 ? v[1] : 0)
            case ("scale", 1...2): m = m * .scale(x: v[0], y: v.count == 2 ? v[1] : v[0])
            case ("rotate", 1): m = m * .rotation(degrees: v[0])
            case ("rotate", 3): m = m * .translation(x: v[1], y: v[2]) * .rotation(degrees: v[0]) * .translation(x: -v[1], y: -v[2])
            case ("skewX", 1): m = m * Matrix(a: 1, b: 0, c: skew, d: 1, tx: 0, ty: 0)
            case ("skewY", 1): m = m * Matrix(a: 1, b: skew, c: 0, d: 1, tx: 0, ty: 0)
            default: throw ImportError.damaged("transform: bad \(name) with \(v.count) numbers")
            }
        }
        guard SVGStyle.trim(rest).isEmpty, [m.a, m.b, m.c, m.d, m.tx, m.ty].allSatisfy(\.isFinite) else {
            throw ImportError.damaged("transform: coordinate out of range or trailing text")
        }
        return m
    }
}
