// SVGStyle.swift: the SVG presentation properties the reader keeps, from
// presentation attributes and the `style` attribute, cascaded parent to child
// (W3C SVG 1.1 chapters 6 and 11, SVG 2 "Styling"). A `style` declaration
// beats the attribute of the same name. Values the reader cannot parse are
// ignored, so the inherited value stays, as the spec asks for invalid values.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A paint: `none`, a color, or a `url(#id)` reference to a gradient.
enum SVGPaint: Sendable, Hashable {
    case none, color(Color), url(String)
}

/// The inherited presentation properties at one element; nil means not set.
struct SVGStyle: Sendable, Hashable {
    var fill: SVGPaint?
    var stroke: SVGPaint?
    var strokeWidth: Double?
    var join: Stroke.Join?
    var cap: Stroke.Cap?
    var fillOpacity: Double?
    var strokeOpacity: Double?
    /// The product of `opacity` down the tree, folded into every alpha.
    var opacity = 1.0

    /// The properties declared on one element: its presentation attributes, then its `style`, which wins.
    static func declared(_ attributes: [String: String]) -> [String: String] {
        let inline = (attributes["style"] ?? "").split(separator: ";").compactMap { part -> (String, String)? in
            let pair = part.split(separator: ":", maxSplits: 1)
            return pair.count == 2 ? (trim(pair[0]), trim(pair[1])) : nil
        }
        return Dictionary(attributes.map { ($0.key, $0.value) } + inline) { $1 }
    }

    /// This style with the element's own declarations applied over it.
    func applying(_ attributes: [String: String]) -> SVGStyle {
        var s = self
        for (key, value) in Self.declared(attributes) {
            switch key {
            case "fill": s.fill = Self.paint(value) ?? s.fill
            case "stroke": s.stroke = Self.paint(value) ?? s.stroke
            case "stroke-width": s.strokeWidth = Self.length(value, of: 1).flatMap { $0 >= 0 ? $0 : nil } ?? s.strokeWidth
            case "stroke-linejoin": s.join = Stroke.Join(rawValue: value) ?? s.join
            case "stroke-linecap": s.cap = Stroke.Cap(rawValue: value) ?? s.cap
            case "fill-opacity": s.fillOpacity = Self.unit(value) ?? s.fillOpacity
            case "stroke-opacity": s.strokeOpacity = Self.unit(value) ?? s.strokeOpacity
            case "opacity": s.opacity *= Self.unit(value) ?? 1
            default: break
            }
        }
        return s
    }

    /// `value` without leading and trailing spaces, tabs, line breaks and `extra` characters.
    static func trim<S: StringProtocol>(_ value: S, extra: String = "") -> String {
        let drop = Set(" \t\n\r" + extra)
        return String(value.drop { drop.contains($0) }.reversed().drop { drop.contains($0) }.reversed())
    }

    /// A number in 0...1, or a percentage of 1, clamped; nil when it does not parse.
    static func unit(_ value: String) -> Double? { length(value, of: 1).map { min(max($0, 0), 1) } }

    /// A length in user units: a number with an optional unit, a percentage of `reference`; nil when it does not parse.
    static func length(_ value: String, of reference: Double) -> Double? {
        let units: [(String, Double)] = [("%", reference / 100), ("px", 1), ("pt", 4.0 / 3), ("pc", 16), ("mm", 96 / 25.4),
                                         ("cm", 96 / 2.54), ("in", 96), ("em", 16), ("", 1)]
        let text = trim(value)
        for (suffix, scale) in units where text.hasSuffix(suffix) {
            guard let n = Double(text.dropLast(suffix.count)), n.isFinite, (n * scale).isFinite else { return nil }
            return n * scale
        }
        return nil
    }

    /// A paint value; nil for one the reader does not know, such as `currentColor`.
    static func paint(_ value: String) -> SVGPaint? {
        let text = trim(value)
        if text == "none" { return SVGPaint.none }
        if text.hasPrefix("url(") { return .url(text) }
        return color(text).map(SVGPaint.color)
    }

    static let named: [String: UInt32] = [
        "black": 0x000000, "white": 0xFFFFFF, "red": 0xFF0000, "green": 0x008000, "blue": 0x0000FF, "yellow": 0xFFFF00,
        "cyan": 0x00FFFF, "aqua": 0x00FFFF, "magenta": 0xFF00FF, "fuchsia": 0xFF00FF, "gray": 0x808080, "grey": 0x808080,
        "silver": 0xC0C0C0, "maroon": 0x800000, "olive": 0x808000, "lime": 0x00FF00, "teal": 0x008080, "navy": 0x000080,
        "purple": 0x800080, "orange": 0xFFA500,
    ]

    /// A color: `#rgb`, `#rrggbb`, `rgb(r, g, b)` with numbers or percentages, a basic named color or `transparent`.
    static func color(_ value: String) -> Color? {
        let text = trim(value).lowercased()
        if text == "transparent" { return Color(r: 0, g: 0, b: 0, a: 0) }
        if text.hasPrefix("rgb(") && text.hasSuffix(")") {
            let parts = text.dropFirst(4).dropLast().split { $0 == "," || $0 == " " }
            let channels = parts.compactMap { part in
                part.hasSuffix("%") ? length(String(part), of: 1) : length(String(part), of: 1).map { $0 / 255 }
            }.map { min(max($0, 0), 1) }
            return channels.count == 3 && parts.count == 3 ? Color(r: channels[0], g: channels[1], b: channels[2]) : nil
        }
        var hex = text.hasPrefix("#") ? String(text.dropFirst()) : ""
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard let rgb = hex.count == 6 && hex.allSatisfy(\.isHexDigit) ? UInt32(hex, radix: 16) : named[text] else { return nil }
        return Color(r: Double(rgb >> 16 & 0xFF) / 255, g: Double(rgb >> 8 & 0xFF) / 255, b: Double(rgb & 0xFF) / 255)
    }
}

/// Paint: a style's fill and stroke for one element.
extension SVGReader {
    /// The fill: black when unset, clear for `none`, else a color, its alpha scaled by `fill-opacity` and `opacity`.
    mutating func fill(_ style: SVGStyle) -> Fill {
        let alpha = (style.fillOpacity ?? 1) * style.opacity
        switch style.fill ?? .color(.black) {
        case .none: return .solid(Self.clear)
        case .color(let c): return .solid(Color(r: c.r, g: c.g, b: c.b, a: c.a * alpha))
        case .url: count("gradient fill"); return .solid(Self.clear)
        }
    }

    /// The stroke, nil when unset, `none` or zero wide.
    mutating func stroke(_ style: SVGStyle, _ ctm: Matrix) -> Stroke? {
        let alpha = (style.strokeOpacity ?? 1) * style.opacity
        let width = (style.strokeWidth ?? 1) * abs(ctm.determinant).squareRoot()
        var color: Color
        switch style.stroke {
        case nil, .none?: return nil
        case .color(let c)?: color = c
        case .url?: count("gradient stroke"); color = Self.clear
        }
        color.a *= alpha
        return width > 0 ? Stroke(color: color, width: width, join: style.join ?? .miter, cap: style.cap ?? .butt) : nil
    }
}
