// SVGExporter+TextPath.swift: a text shape set on a path (TE-8) as a
// `<defs>` holding the path and one `<text>` whose `<textPath>` names it.
//
// The path is written in the layer's space, as `TextLayout.onPath` places
// glyphs (the shape's position does not move it); a flipped path is written
// reversed (`reversed`), so a renderer walks it from its end the way `onPath`
// does. `startOffset` is the fraction of the path's length as a percentage.
// Inside the `<textPath>` each resolved run is a `<tspan>` with the same
// attributes as SVGExporter+Text writes; there are no lines or anchors, since
// `onPath` sets the string as one line from the offset. The whole element is
// one output line, so `xml:space="preserve"` draws no stray space. Ids are
// "tp<n>" from the counter gradients and masks share, so they never collide.
// The text is laid out first, so a text the layout refuses throws its
// `ModelError.invalidText`; a non-finite offset or path point throws
// `nonFiniteValue`.
//
// Invariants:
// - `reversed` walks every contour backwards, last contour first; a closed
//   contour keeps its start point and walks its closing edge first, so a
//   point `d` along the reversed path is `length - d` along the original
// - the offset is `startOffset * 100` percent, never a length

extension SVGExporter {
    /// The `<defs>` and `<text>` lines for `text` on its path, gradient elements first.
    static func textPathElement(_ text: TextShape, ids: inout Int,
                                measure: (TextShape) -> [GlyphRunMetrics]) throws -> [String] {
        guard let spec = text.onPath else { return try textElement(text, gradients: &ids, measure: measure) }
        let style = text.paragraph ?? ParagraphStyle()
        let runs = text.resolvedRuns
        let (elements, attributes) = try runAttributeList(runs, style: style, gradients: &ids)
        var out = elements
        _ = try TextLayout.lay(text, measured: measure(text))
        let d = try pathData(spec.flipped ? reversed(spec.path) : spec.path)
        let offset = try number(spec.startOffset * 100)
        let id = nextID("tp", &ids)
        let chars = Array(text.string)
        var spans = ""
        for (run, attrs) in zip(runs, attributes) {
            let lower = max(run.start, 0), upper = min(run.start + run.length, chars.count)
            guard lower < upper else { continue }
            spans += "<tspan\(attrs)>\(escape(String(chars[lower..<upper])))</tspan>"
        }
        out.append("<defs><path id=\"\(id)\" d=\"\(d)\"/></defs>")
        out.append("<text xml:space=\"preserve\"><textPath href=\"#\(id)\" startOffset=\"\(offset)%\">\(spans)</textPath></text>")
        return out
    }

    /// `path` walked backwards: its contours last first, each from its end to
    /// its start, curves with their controls swapped. A closed contour starts
    /// at its own start point, walks its closing edge back to its last point
    /// (left out when the two coincide), then the rest, and closes. A drawing
    /// element with no current point starts a contour at its end, as the
    /// path measure reads it.
    static func reversed(_ path: Path) -> Path {
        /// One contour: its start, each drawing element with the point it leaves from, and whether it closes.
        struct Contour { var start: Point, segments: [(from: Point, element: PathElement)] = [], closed = false }
        var contours: [Contour] = [], current: Contour?, subpathStart: Point?
        for element in path.elements {
            switch element {
            case .move(let to):
                if let c = current { contours.append(c) }
                current = Contour(start: to)
                subpathStart = to
            case .close:
                guard var c = current else { continue }
                c.closed = true
                contours.append(c)
                current = nil
            case .line(let to), .quad(_, let to), .cubic(_, _, let to):
                if current == nil, let start = subpathStart { current = Contour(start: start) }
                guard var c = current else {
                    current = Contour(start: to)
                    subpathStart = to
                    continue
                }
                c.segments.append((c.segments.last?.element.endPoint ?? c.start, element))
                current = c
            }
        }
        if let c = current { contours.append(c) }
        var out: [PathElement] = []
        for c in contours.reversed() {
            let last = c.segments.last?.element.endPoint ?? c.start
            if c.closed {
                out.append(.move(to: c.start))
                if last != c.start { out.append(.line(to: last)) }
            } else {
                out.append(.move(to: last))
            }
            for (from, element) in c.segments.reversed() {
                switch element {
                case .quad(let control, _): out.append(.quad(control: control, to: from))
                case .cubic(let c1, let c2, _): out.append(.cubic(control1: c2, control2: c1, to: from))
                default: out.append(.line(to: from))
                }
            }
            if c.closed { out.append(.close) }
        }
        return Path(elements: out)
    }
}
