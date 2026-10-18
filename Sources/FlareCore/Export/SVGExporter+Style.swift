// SVGExporter+Style.swift: the fill, stroke and gradient attributes SVGExporter writes on a path,
// and each shape as it draws at the exported frame: its layer's fill and stroke colour tracks,
// `Layer.trackKey(strokeWidthOf:)` track and shape track sampled there (an instance's symbol layers at the
// symbol frame). A value with no track stays static, so an unkeyed scene exports as before.
// A keyed fill track paints the shape a solid of its sampled colour, replacing a gradient as the
// Lottie export does; stroke tracks colour and widen an existing stroke only.

extension SVGExporter {
    /// `nodes` with each shape replaced by `styled(_:index:of:at:)`: shapes of
    /// `layers` (matched by layer id) sample at `frame`, and an instance's
    /// children sample its symbol's layers at the instance's symbol frame.
    static func sampled(_ nodes: [RenderNode], layers: [Layer], frame: Double, symbols: [Symbol]) -> [RenderNode] {
        var byID: [String: Layer] = [:]
        for layer in layers where byID[layer.id] == nil { byID[layer.id] = layer }
        return nodes.map { node in
            guard case .layer(var layer) = node else { return node }
            let model = byID[layer.id]
            layer.children = layer.children.map { child in
                switch child {
                case .shape(let index, let shape):
                    return .shape(index: index, model.map { styled(shape, index: index, of: $0, at: frame) } ?? shape)
                case .instance(let index, let instance, let symbolID, let local, let children):
                    let inner = symbols.first(where: { $0.id == symbolID })?.layers ?? []
                    return .instance(index: index, instance, symbolID: symbolID, frame: local,
                                     children: sampled(children, layers: inner, frame: local, symbols: symbols))
                case .text, .unresolved, .layer:
                    return child
                }
            }
            return .layer(layer)
        }
    }

    /// `shape`, which is `layer.shapes[index]`, with its fill colour, stroke
    /// colour, stroke width and path sampled from `layer`'s tracks at `frame`.
    /// A keyed fill colour replaces any fill, gradients included, with that solid.
    /// A sampled width below 0 draws as 0, the least a stroke may have.
    static func styled(_ shape: Shape, index: Int, of layer: Layer, at frame: Double) -> Shape {
        var out = shape
        if let color = layer.sampledColor(.fill(shape: index), at: frame) { out.fill = .solid(color) }
        if var stroke = shape.stroke {
            if let color = layer.sampledColor(.stroke(shape: index), at: frame) { stroke.color = color }
            if let keys = layer.tracks[Layer.trackKey(strokeWidthOf: index)], let width = Timeline.value(of: keys, at: frame) {
                stroke.width = max(width, 0)
            }
            out.stroke = stroke
        }
        if let path = layer.sampledPath(shape: index, at: frame) { out.path = path }
        return out
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
