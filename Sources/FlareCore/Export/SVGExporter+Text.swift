// SVGExporter+Text.swift: a text shape as one SVG <text> element.
//
// The shape is laid out with `TextLayout.lay` over the metrics `measure`
// gives (`FixedAdvances`, the platform-free measurer, unless the caller of
// `export` passes measured ones), so the lines, baselines and justified
// positions are the layout's, offset by the shape's position. Each line is a
// `<tspan x y>` at its baseline; inside it each resolved run is a `<tspan>`
// with its font-family, font-size, fill and, when not the default,
// font-weight, font-style, letter-spacing (the run's tracking plus the
// paragraph's) and baseline-shift. Centre and trailing alignment write
// `text-anchor` middle and end, with x at the line's centre or end; a
// justified shape writes every line's x list, one value per Unicode scalar
// (SVG counts characters, not graphemes): each grapheme's x, repeated for its
// further scalars. A line's trailing whitespace is not written, and the
// <text> keeps spaces with `xml:space="preserve"`, so the whole element is
// one output line: a newline between line spans would draw as a space. A gradient run fill is a gradient element before the
// <text>, like a path's. Numbers use `SVGExporter.number`, so a non-finite
// value throws `nonFiniteValue`; a text the layout refuses throws its
// `ModelError.invalidText`. Lines and runs both tile the string in order, so
// one run cursor walks them together and the work is linear in lines plus
// runs. Type on a path is SVGExporter+TextPath.

extension SVGExporter {
    /// The lines of one `<text>` element for `text`, laid out over
    /// `measure(text)`, gradient elements first.
    static func textElement(_ text: TextShape, gradients: inout Int,
                            measure: (TextShape) -> [GlyphRunMetrics]) throws -> [String] {
        let style = text.paragraph ?? ParagraphStyle()
        let runs = text.resolvedRuns
        let (elements, attributes) = try runAttributeList(runs, style: style, gradients: &gradients)
        var out = elements
        let origin = text.position
        let layout = try TextLayout.lay(text, measured: measure(text))
        let anchor = style.alignment == .center ? " text-anchor=\"middle\""
            : style.alignment == .trailing ? " text-anchor=\"end\"" : ""
        var element = "<text xml:space=\"preserve\"\(anchor)>"
        let chars = Array(text.string)
        var first = 0
        for line in layout.lines {
            var end = line.graphemes.upperBound
            while end > line.graphemes.lowerBound, chars[end - 1].isWhitespace { end -= 1 }
            let lead = line.x.first ?? 0
            let x: String
            switch style.alignment {
            case .justified:
                // One x per scalar: a grapheme's x, then again for each further scalar in it.
                var xs: [String] = []
                for (i, px) in zip(line.graphemes.lowerBound..<end, line.x) {
                    xs += Array(repeating: try number(origin.x + px), count: chars[i].unicodeScalars.count)
                }
                x = xs.joined(separator: " ")
            case .center: x = try number(origin.x + lead + line.width / 2)
            case .trailing: x = try number(origin.x + lead + line.width)
            case .leading: x = try number(origin.x + lead)
            }
            var spans = ""
            // Skip the runs that end before this line, so no line restarts from run 0.
            while first < runs.count, runs[first].start + runs[first].length <= line.graphemes.lowerBound { first += 1 }
            for (run, attrs) in zip(runs[first...], attributes[first...]) {
                if run.start >= end { break }
                let lower = max(run.start, line.graphemes.lowerBound), upper = min(run.start + run.length, end)
                guard lower < upper else { continue }
                spans += "<tspan\(attrs)>\(escape(String(chars[lower..<upper])))</tspan>"
            }
            element += "<tspan x=\"\(x)\" y=\"\(try number(origin.y + line.baseline))\">\(spans)</tspan>"
        }
        out.append(element + "</text>")
        return out
    }

    /// The gradient elements and the attributes of each of `runs`. Every
    /// run's attributes are formatted before layout, so a non-finite run
    /// value throws `nonFiniteValue` rather than the layout's error.
    static func runAttributeList(_ runs: [ResolvedRun], style: ParagraphStyle,
                                 gradients: inout Int) throws -> (elements: [String], attributes: [String]) {
        var out: [String] = [], attributes: [String] = []
        for run in runs {
            let (paint, element) = try runFill(run.fill, gradients: &gradients)
            if let element { out.append(element) }
            attributes.append(try runAttributes(run, paint: paint, paragraphTracking: style.tracking))
        }
        return (out, attributes)
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
