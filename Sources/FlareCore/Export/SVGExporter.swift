// SVGExporter.swift: one frame of a scene as an SVG document.
//
// Layers render bottom to top (the first layer is drawn first). Each visible
// layer is a <g> carrying its sampled transform as a matrix and its opacity;
// each shape is a <path> built from `Shape.outline`, so curves stay curves.
// Coordinates are written as-is: scene space maps straight to SVG user space.
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
                lines.append("<path d=\"\(d)\"\(try fill(shape.fill))/>")
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
        var hex = "#"
        for channel in [color.r, color.g, color.b] {
            guard channel.isFinite else { throw SVGExportError.nonFiniteValue }
            let byte = Int((min(max(channel, 0), 1) * 255).rounded())
            let digits = String(byte, radix: 16)
            hex += digits.count == 1 ? "0" + digits : digits
        }
        guard color.a.isFinite else { throw SVGExportError.nonFiniteValue }
        let alpha = min(max(color.a, 0), 1)
        let opacity = alpha == 1 ? "" : " fill-opacity=\"\(try number(alpha))\""
        return " fill=\"\(hex)\"\(opacity)"
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
