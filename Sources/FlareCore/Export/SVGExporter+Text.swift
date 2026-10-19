// SVGExporter+Text.swift: a text shape as one SVG <text> element.
//
// The shape is laid out with `TextLayout.lay` over `FixedAdvances` (the
// platform-free measurer), so the lines, baselines and justified positions
// are the layout's, offset by the shape's position. Each line is a
// `<tspan x y>` at its baseline; inside it each resolved run is a `<tspan>`
// with its font-family, font-size, fill and, when not the default,
// font-weight, font-style, letter-spacing (the run's tracking plus the
// paragraph's) and baseline-shift. Centre and trailing alignment write
// `text-anchor` middle and end, with x at the line's centre or end; a
// justified shape writes every line's per-grapheme x list. A line's trailing
// whitespace is not written, and the <text> keeps spaces with
// `xml:space="preserve"`. A gradient run fill is a gradient element before the
// <text>, like a path's. Numbers use `SVGExporter.number`, so a non-finite
// value throws `nonFiniteValue`; a text the layout refuses throws its
// `ModelError.invalidText`. Type on a path is not written here yet.

extension SVGExporter {
    /// The lines of one `<text>` element for `text`, gradient elements first.
    static func textElement(_ text: TextShape, gradients: inout Int) throws -> [String] {
        let style = text.paragraph ?? ParagraphStyle()
        let runs = text.resolvedRuns
        var out: [String] = [], attributes: [String] = []
        // Every run's attributes are formatted before layout, so a non-finite
        // run value throws `nonFiniteValue` rather than the layout's error.
        for run in runs {
            let (paint, element) = try runFill(run.fill, gradients: &gradients)
            if let element { out.append(element) }
            attributes.append(try runAttributes(run, paint: paint, paragraphTracking: style.tracking))
        }
        let origin = text.position
        let layout = try TextLayout.lay(text, measured: FixedAdvances.measure(text))
        let anchor = style.alignment == .center ? " text-anchor=\"middle\""
            : style.alignment == .trailing ? " text-anchor=\"end\"" : ""
        out.append("<text xml:space=\"preserve\"\(anchor)>")
        let chars = Array(text.string)
        for line in layout.lines {
            let lead = line.x.first ?? 0
            let x: String
            switch style.alignment {
            case .justified: x = try line.x.map { try number(origin.x + $0) }.joined(separator: " ")
            case .center: x = try number(origin.x + lead + line.width / 2)
            case .trailing: x = try number(origin.x + lead + line.width)
            case .leading: x = try number(origin.x + lead)
            }
            var end = line.graphemes.upperBound
            while end > line.graphemes.lowerBound, chars[end - 1].isWhitespace { end -= 1 }
            var spans = ""
            for (run, attrs) in zip(runs, attributes) {
                let lower = max(run.start, line.graphemes.lowerBound), upper = min(run.start + run.length, end)
                guard lower < upper else { continue }
                spans += "<tspan\(attrs)>\(escape(String(chars[lower..<upper])))</tspan>"
            }
            out.append("<tspan x=\"\(x)\" y=\"\(try number(origin.y + line.baseline))\">\(spans)</tspan>")
        }
        out.append("</text>")
        return out
    }

    /// One run's attributes, each with a leading space: family, size and
    /// `paint`, then weight, italic, letter-spacing and baseline-shift when
    /// they are not 400, upright, 0 and 0.
    static func runAttributes(_ run: ResolvedRun, paint: String, paragraphTracking: Double) throws -> String {
        var attrs = " font-family=\"\(escape(run.fontFamily))\" font-size=\"\(try number(run.fontSize))\"\(paint)"
        if run.weight != 400 { attrs += " font-weight=\"\(run.weight)\"" }
        if run.italic { attrs += " font-style=\"italic\"" }
        let tracking = try number(run.tracking + paragraphTracking)
        if tracking != "0" { attrs += " letter-spacing=\"\(tracking)\"" }
        let shift = try number(run.baselineShift)
        if shift != "0" { attrs += " baseline-shift=\"\(shift)\"" }
        return attrs
    }

    /// A run's fill attributes and, for a gradient, the gradient element it names.
    static func runFill(_ fill: Fill, gradients: inout Int) throws -> (attributes: String, element: String?) {
        if case .solid(let color) = fill { return (try self.fill(color), nil) }
        let id = "g\(gradients)"
        gradients += 1
        return (" fill=\"url(#\(id))\"", try gradient(fill, id: id))
    }
}
