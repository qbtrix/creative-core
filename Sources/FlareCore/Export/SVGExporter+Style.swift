// SVGExporter+Style.swift: the fill, stroke and gradient attributes SVGExporter writes on a path. The shapes
// arrive already sampled at the exported frame by the render list (`Layer.sampledShape`), so the SVG draws
// what the stage draws. A dash writes stroke-dasharray and stroke-dashoffset.

extension SVGExporter {
    /// ` stroke`, ` stroke-opacity` (when translucent), width, join and cap,
    /// then ` stroke-dasharray` and ` stroke-dashoffset` when dashed; empty
    /// when there is no stroke.
    static func stroke(_ stroke: Stroke?) throws -> String {
        guard let stroke else { return "" }
        let (hex, alpha) = try paint(stroke.color)
        let opacity = alpha.map { " stroke-opacity=\"\($0)\"" } ?? ""
        let dash = stroke.dash.isEmpty ? ""
            : " stroke-dasharray=\"\(try stroke.dash.map(number).joined(separator: " "))\" stroke-dashoffset=\"\(try number(stroke.dashPhase))\""
        return " stroke=\"\(hex)\"\(opacity) stroke-width=\"\(try number(stroke.width))\""
            + " stroke-linejoin=\"\(stroke.join.rawValue)\" stroke-linecap=\"\(stroke.cap.rawValue)\"\(dash)"
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
            // A valid radius below the rounding step would round to r="0", which
            // disables the gradient, so write it unrounded instead.
            let rounded = try number(radius)
            let r = rounded == "0" && radius > 0 ? plainDecimal("\(radius)") : rounded
            open = "<radialGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\" "
                + "cx=\"\(try number(center.x))\" cy=\"\(try number(center.y))\" r=\"\(r)\">"
            close = "</radialGradient>"
        }
        let stops = try fill.stops.map { stop in
            let (hex, alpha) = try paint(stop.color)
            let opacity = alpha.map { " stop-opacity=\"\($0)\"" } ?? ""
            return "<stop offset=\"\(try number(stop.offset))\" stop-color=\"\(hex)\"\(opacity)/>"
        }
        return ([open] + stops + [close]).joined()
    }
}
