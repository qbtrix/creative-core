// SVGExporter.swift: one frame of a scene as an SVG document.
//
// The exporter walks the scene's render list (`Scene.renderList`), so it draws
// what the stage draws. Layers render bottom to top (the first layer is drawn
// first). Each visible layer is a <g> carrying its sampled transform as a
// matrix and its opacity; each shape is a <path> built from `Shape.outline`, so curves stay curves,
// with its stroke as stroke attributes, its colour, width, trim and shape tracks sampled
// at the frame first (SVGExporter+Style). A stroke whose trim cuts the outline is a second
// <path> above it with fill="none" and the trimmed geometry (flattened at `strokeTolerance`),
// the first <path> keeping the whole fill; a trim that keeps everything writes one <path>. After its shapes, each instance on a
// layer is a nested <g> with the instance transform holding the symbol's
// layers sampled at the symbol frame.
// Coordinates are written as-is: scene space maps straight to SVG user space.
// A gradient fill is written as a gradient element (in user space) just before
// its path, which refers to it by id ("g0", "g1", ... in document order).
// Each layer's <g> carries its id and name, XML-escaped. Numbers are rounded
// to 4 decimals and never use exponent notation; a non-finite value throws.
// Each text shape is one <text> element (SVGExporter+Text), laid out over the
// metrics `export`'s `measure` gives (0.5 em per grapheme by default); type on
// a path is a <textPath> naming its path in <defs> (SVGExporter+TextPath).
// A render list that stopped expanding instances at its budget throws
// `sceneTooLarge` before anything is written. Masks: SVGExporter+Masks.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public enum SVGExportError: Error, Equatable, Sendable {
    case nonFiniteValue
    /// An instance names a symbol that is missing, contains itself, or is
    /// nested deeper than `Instance.maxNestingDepth`.
    case unresolvedSymbol(String)
    /// The scene's instances expand past `RenderList.maxExpandedPoints`
    /// (its render list `isTruncated`), e.g. symbols that nest two or more
    /// instances of each other many levels deep. Every symbol exists; place
    /// fewer instances or flatten the nesting.
    case sceneTooLarge
    /// The scene draws something this exporter cannot write yet, e.g. "matte source".
    case unsupported(String)
}

public enum SVGExporter {
    /// How far, in the shape's own units, a trimmed stroke's flattened geometry may stray from its curve.
    public static let strokeTolerance = 0.01

    /// The scene at `frame` as an SVG document. `symbols` are the document's
    /// symbols, which the scene's instances name.
    ///
    /// Each text shape is laid out with `TextLayout.lay` over the metrics
    /// `measure` gives it (one `GlyphRunMetrics` per `resolvedRuns`, in
    /// order); its line breaks, baselines and justified per-grapheme `x`
    /// lists come from that layout. The default, `FixedAdvances.measure`,
    /// gives every grapheme 0.5 em, not the platform's font metrics: pass the
    /// app's measured advances so the SVG wraps and justifies as the screen does.
    ///
    /// Throws `SVGExportError` (`nonFiniteValue`, `unresolvedSymbol`,
    /// `sceneTooLarge`, or `unsupported` with one of these reasons:
    /// "matte source"
    /// for a track matte whose source is not in the same layer list, "nested matte" for a matte source that has
    /// a matte of its own), or `ModelError.invalidText` when the layout refuses a
    /// text shape: a paragraph value out of range, metrics that do not match
    /// its runs, or more than `TextLayout.maxGraphemes` graphemes.
    public static func export(scene: Scene, frame: Double, symbols: [Symbol] = [],
                              measure: (TextShape) -> [GlyphRunMetrics] = FixedAdvances.measure) throws -> String {
        let w = try number(scene.width)
        let h = try number(scene.height)
        var lines = [
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(w)\" height=\"\(h)\" viewBox=\"0 0 \(w) \(h)\">",
            "<rect width=\"\(w)\" height=\"\(h)\"\(try fill(scene.background))/>",
        ]
        var gradients = 0
        let list = scene.renderList(at: frame, symbols: symbols)
        if list.isTruncated { throw SVGExportError.sceneTooLarge }
        let scope = Scope(layers: scene.layers, frame: frame, symbols: symbols)
        for node in list.nodes {
            try emit(node, in: scope, into: &lines, gradients: &gradients, measure: measure)
        }
        lines.append("</svg>")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Appends one render node: a layer as a <g> holding its children, a shape
    /// as a <path>, an instance as a nested <g> with the instance transform.
    /// `scope` is the model the node came from; only scene layers get an id.
    static func emit(_ node: RenderNode, in scope: Scope, into lines: inout [String], gradients: inout Int,
                     measure: (TextShape) -> [GlyphRunMetrics]) throws {
        switch node {
        case .layer(let layer):
            let opacityAttr = layer.opacity == 1 ? "" : " opacity=\"\(try number(layer.opacity))\""
            let idName = scope.writesIDs ? "id" : "data-id"
            let ids = " \(idName)=\"\(escape(layer.id))\" data-name=\"\(escape(layer.name))\""
            let (masks, matte) = try maskDefs(for: layer.id, in: scope, into: &lines, ids: &gradients, measure: measure)
            if let matte { lines.append("<g mask=\"url(#\(matte))\">") }
            lines.append("<g\(ids)\(try matrix(layer.transform))\(opacityAttr)\(masks)>")
            for child in layer.children {
                try emit(child, in: scope, into: &lines, gradients: &gradients, measure: measure)
            }
            lines.append(matte == nil ? "</g>" : "</g>\n</g>")
        case .shape(_, let shape):
            let d = try pathData(shape.outline)
            if d.isEmpty { return }
            let attr: String
            if case .solid(let color) = shape.fill {
                attr = try fill(color)
            } else {
                let id = "g\(gradients)"
                gradients += 1
                lines.append(try gradient(shape.fill, id: id))
                attr = " fill=\"url(#\(id))\""
            }
            guard let trim = shape.stroke?.trim, !trim.isWhole else {
                lines.append("<path d=\"\(d)\"\(attr)\(try stroke(shape.stroke))/>")
                return
            }
            lines.append("<path d=\"\(d)\"\(attr)/>")
            let cut = try shape.outline.trimmed(start: trim.start, end: trim.end, offset: trim.offset, mode: trim.mode,
                                                tolerance: strokeTolerance)
            let t = try pathData(cut)
            if !t.isEmpty { lines.append("<path d=\"\(t)\" fill=\"none\"\(try stroke(shape.stroke))/>") }
        case .text(_, let text) where text.onPath != nil:
            lines.append(contentsOf: try textPathElement(text, ids: &gradients, measure: measure))
        case .text(_, let text):
            lines.append(contentsOf: try textElement(text, gradients: &gradients, measure: measure))
        case .instance(_, let instance, let symbolID, let local, let children):
            lines.append("<g data-symbol=\"\(escape(symbolID))\"\(try matrix(instance.transform))>")
            let inner = Scope(layers: scope.symbols.first { $0.id == symbolID }?.layers ?? [], frame: local,
                              symbols: scope.symbols, path: scope.path + [symbolID], writesIDs: false)
            for child in children {
                try emit(child, in: inner, into: &lines, gradients: &gradients, measure: measure)
            }
            lines.append("</g>")
        case .unresolved(_, let symbolID):
            throw SVGExportError.unresolvedSymbol(symbolID)
        }
    }

    /// ` transform="matrix(a b c d tx ty)"`.
    static func matrix(_ transform: Transform) throws -> String {
        let m = transform.matrix
        return " transform=\"matrix(\(try [m.a, m.b, m.c, m.d, m.tx, m.ty].map(number).joined(separator: " ")))\""
    }

    /// SVG path data (the `d` attribute) for `path`: M, L, Q, C and Z commands
    /// with absolute coordinates, numbers written as `export` writes them.
    /// Throws `SVGExportError.nonFiniteValue` for a NaN or infinite coordinate.
    public static func pathData(_ path: Path) throws -> String {
        func pt(_ p: Point) throws -> String { "\(try number(p.x)) \(try number(p.y))" }
        var parts: [String] = []
        for element in path.elements {
            switch element {
            case .move(let to): parts.append("M\(try pt(to))")
            case .line(let to): parts.append("L\(try pt(to))")
            case .quad(let c, let to): parts.append("Q\(try pt(c)) \(try pt(to))")
            case .cubic(let c1, let c2, let to): parts.append("C\(try pt(c1)) \(try pt(c2)) \(try pt(to))")
            case .close: parts.append("Z")
            }
        }
        return parts.joined(separator: " ")
    }

    /// A finite number rounded to 4 decimals, without a trailing ".0".
    static func number(_ value: Double) throws -> String {
        guard value.isFinite else { throw SVGExportError.nonFiniteValue }
        // Huge values have no fractional part to round, and scaling could overflow.
        let rounded = abs(value) >= 1e15 ? value : (value * 10_000).rounded() / 10_000
        if rounded == 0 { return "0" }
        if rounded == rounded.rounded(), abs(rounded) < 1e15 {
            return String(Int(rounded))
        }
        return plainDecimal("\(rounded)")
    }

    /// Rewrites a number like "1.5e+20" or "-2.5e-05" as a plain decimal,
    /// without trailing fractional zeros.
    static func plainDecimal(_ text: String) -> String {
        var mantissa = Substring(text)
        var exponent = 0
        if let e = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            guard let value = Int(text[text.index(after: e)...]) else { return text }
            mantissa = text[..<e]
            exponent = value
        }
        let sign = mantissa.hasPrefix("-") ? "-" : ""
        if !sign.isEmpty { mantissa = mantissa.dropFirst() }
        let parts = mantissa.split(separator: ".", omittingEmptySubsequences: false)
        let whole = parts.first.map(String.init) ?? ""
        let digits = whole + (parts.count > 1 ? String(parts[1]) : "")
        let point = whole.count + exponent
        var result: String
        if point <= 0 {
            result = "0." + String(repeating: "0", count: -point) + digits
        } else if point >= digits.count {
            result = digits + String(repeating: "0", count: point - digits.count)
        } else {
            result = String(digits.prefix(point)) + "." + String(digits.dropFirst(point))
        }
        if result.contains(".") {
            while result.hasSuffix("0") { result.removeLast() }
            if result.hasSuffix(".") { result.removeLast() }
        }
        return sign + result
    }

    /// Text safe inside an XML attribute value.
    static func escape(_ text: String) -> String {
        var out = ""
        for ch in text {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(ch)
            }
        }
        return out
    }
}
