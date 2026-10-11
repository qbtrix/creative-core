// SVGExporter.swift: one frame of a scene as an SVG document.
//
// Layers render bottom to top (the first layer is drawn first). Each visible
// layer is a <g> carrying its sampled transform as a matrix and its opacity;
// each shape is a <path> built from `Shape.outline`, so curves stay curves,
// with its stroke as stroke attributes. After its shapes, each instance on a
// layer is a nested <g> with the instance transform holding the symbol's
// layers sampled at the symbol frame (`Instance.resolve`).
// Coordinates are written as-is: scene space maps straight to SVG user space.
// A gradient fill is written as a gradient element (in user space) just before
// its path, which refers to it by id ("g0", "g1", ... in document order).
// Each layer's <g> carries its id and name, XML-escaped. Numbers are rounded
// to 4 decimals and never use exponent notation; a non-finite value throws.
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
}

public enum SVGExporter {
    /// `symbols` are the document's symbols, which the scene's instances name.
    public static func export(scene: Scene, frame: Double, symbols: [Symbol] = []) throws -> String {
        let w = try number(scene.width)
        let h = try number(scene.height)
        var lines = [
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(w)\" height=\"\(h)\" viewBox=\"0 0 \(w) \(h)\">",
            "<rect width=\"\(w)\" height=\"\(h)\"\(try fill(scene.background))/>",
        ]
        var gradients = 0
        for layer in scene.layers {
            try render(layer, frame: frame, symbols: symbols, path: [], into: &lines, gradients: &gradients)
        }
        lines.append("</svg>")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Appends a visible layer as a <g> holding its shapes, then one nested
    /// <g> per instance holding the symbol's layers at the symbol frame.
    /// `path` is the ids of the symbols being drawn around this layer.
    static func render(
        _ layer: Layer, frame: Double, symbols: [Symbol], path: [String],
        into lines: inout [String], gradients: inout Int
    ) throws {
        guard layer.isVisible else { return }
        let (transform, opacity) = layer.placement(at: frame)
        let opacityAttr = opacity == 1 ? "" : " opacity=\"\(try number(opacity))\""
        // Symbol layers repeat once per instance, so only scene layers get an id.
        let idName = path.isEmpty ? "id" : "data-id"
        let ids = " \(idName)=\"\(escape(layer.id))\" data-name=\"\(escape(layer.name))\""
        lines.append("<g\(ids)\(try matrix(transform))\(opacityAttr)>")
        for shape in layer.shapes {
            let d = try pathData(shape.outline)
            if d.isEmpty { continue }
            let attr: String
            if case .solid(let color) = shape.fill {
                attr = try fill(color)
            } else {
                let id = "g\(gradients)"
                gradients += 1
                lines.append(try gradient(shape.fill, id: id))
                attr = " fill=\"url(#\(id))\""
            }
            lines.append("<path d=\"\(d)\"\(attr)\(try stroke(shape.stroke))/>")
        }
        for instance in layer.instances {
            guard let (symbol, local) = instance.resolve(in: symbols, frame: frame, path: path) else {
                throw SVGExportError.unresolvedSymbol(instance.symbolID)
            }
            lines.append("<g data-symbol=\"\(escape(symbol.id))\"\(try matrix(instance.transform))>")
            for inner in symbol.layers {
                try render(inner, frame: local, symbols: symbols, path: path + [symbol.id],
                           into: &lines, gradients: &gradients)
            }
            lines.append("</g>")
        }
        lines.append("</g>")
    }

    /// ` transform="matrix(a b c d tx ty)"`.
    static func matrix(_ transform: Transform) throws -> String {
        let m = transform.matrix
        return " transform=\"matrix(\(try [m.a, m.b, m.c, m.d, m.tx, m.ty].map(number).joined(separator: " ")))\""
    }

    /// SVG path data: M, L, Q, C and Z commands with absolute coordinates.
    static func pathData(_ path: Path) throws -> String {
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

    /// ` stroke`, ` stroke-opacity` (when translucent), width, join and cap;
    /// empty when there is no stroke.
    static func stroke(_ stroke: Stroke?) throws -> String {
        guard let stroke else { return "" }
        let (hex, alpha) = try paint(stroke.color)
        let opacity = alpha.map { " stroke-opacity=\"\($0)\"" } ?? ""
        return " stroke=\"\(hex)\"\(opacity) stroke-width=\"\(try number(stroke.width))\""
            + " stroke-linejoin=\"\(stroke.join.rawValue)\" stroke-linecap=\"\(stroke.cap.rawValue)\""
    }

    /// ` fill="#rrggbb"`, plus ` fill-opacity` when the color is translucent.
    static func fill(_ color: Color) throws -> String {
        let (hex, alpha) = try paint(color)
        let opacity = alpha.map { " fill-opacity=\"\($0)\"" } ?? ""
        return " fill=\"\(hex)\"\(opacity)"
    }

    /// "#rrggbb" and the alpha as a number, or nil when the color is opaque.
    static func paint(_ color: Color) throws -> (hex: String, alpha: String?) {
        var hex = "#"
        for channel in [color.r, color.g, color.b] {
            guard channel.isFinite else { throw SVGExportError.nonFiniteValue }
            let byte = Int((min(max(channel, 0), 1) * 255).rounded())
            let digits = String(byte, radix: 16)
            hex += digits.count == 1 ? "0" + digits : digits
        }
        guard color.a.isFinite else { throw SVGExportError.nonFiniteValue }
        let alpha = min(max(color.a, 0), 1)
        return (hex, alpha == 1 ? nil : try number(alpha))
    }

    /// A gradient element with its stops, in user-space coordinates.
    static func gradient(_ fill: Fill, id: String) throws -> String {
        let (open, close): (String, String)
        switch fill {
        case .solid:
            return ""
        case .linear(_, let start, let end):
            open = "<linearGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\" "
                + "x1=\"\(try number(start.x))\" y1=\"\(try number(start.y))\" "
                + "x2=\"\(try number(end.x))\" y2=\"\(try number(end.y))\">"
            close = "</linearGradient>"
        case .radial(_, let center, let radius):
            open = "<radialGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\" "
                + "cx=\"\(try number(center.x))\" cy=\"\(try number(center.y))\" r=\"\(try number(radius))\">"
            close = "</radialGradient>"
        }
        let stops = try fill.stops.map { stop in
            let (hex, alpha) = try paint(stop.color)
            let opacity = alpha.map { " stop-opacity=\"\($0)\"" } ?? ""
            return "<stop offset=\"\(try number(stop.offset))\" stop-color=\"\(hex)\"\(opacity)/>"
        }
        return ([open] + stops + [close]).joined()
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
