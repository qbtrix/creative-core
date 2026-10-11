// SVGExporter.swift: one frame of a scene as an SVG document.
//
// Layers render bottom to top (the first layer is drawn first). Each visible
// layer is a <g> carrying its sampled transform as a matrix and its opacity;
// each shape is a <path> built from `Shape.outline`, so curves stay curves.
// Coordinates are written as-is: scene space maps straight to SVG user space.
// A gradient fill is written as a gradient element (in user space) just before
// its path, which refers to it by id ("g0", "g1", ... in document order).
// Numbers are rounded to 4 decimals; a non-finite value throws.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public enum SVGExportError: Error, Equatable, Sendable {
    case nonFiniteValue
}

public enum SVGExporter {
    public static func export(scene: Scene, frame: Double) throws -> String {
        let w = try number(scene.width)
        let h = try number(scene.height)
        var lines = [
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(w)\" height=\"\(h)\" viewBox=\"0 0 \(w) \(h)\">",
            "<rect width=\"\(w)\" height=\"\(h)\"\(try fill(scene.background))/>",
        ]
        var gradients = 0
        for layer in scene.layers where layer.isVisible {
            let s = layer.sample(at: frame)
            let transform = Transform(
                x: s["x"] ?? 0, y: s["y"] ?? 0,
                scaleX: s["scaleX"] ?? 1, scaleY: s["scaleY"] ?? 1,
                rotation: s["rotation"] ?? 0
            )
            let m = transform.matrix
            let values = try [m.a, m.b, m.c, m.d, m.tx, m.ty].map(number).joined(separator: " ")
            let opacity = s["opacity"] ?? 1
            let opacityAttr = opacity == 1 ? "" : " opacity=\"\(try number(opacity))\""
            lines.append("<g transform=\"matrix(\(values))\"\(opacityAttr)>")
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
                lines.append("<path d=\"\(d)\"\(attr)/>")
            }
            lines.append("</g>")
        }
        lines.append("</svg>")
        return lines.joined(separator: "\n") + "\n"
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
        return "\(rounded)"
    }
}
