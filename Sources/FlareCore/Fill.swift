// Fill.swift: how a shape's interior is painted. A solid color, or a linear
// or radial gradient through color stops.
//
// Invariants (checked by the format layer on load):
// - stop offsets are finite, in 0...1 and sorted ascending (equal is allowed)
// - a radial radius is finite and > 0
// - every color channel (solid or stop) is finite, so the document can be saved
//
// Encoding: `.solid` is written as the plain color object, exactly as v1 files
// stored `Shape.fill`, so old files stay byte-stable. Gradients are objects
// with a "type" key ("linear" or "radial").
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public struct GradientStop: Codable, Sendable, Hashable {
    /// Position along the gradient, 0...1.
    public var offset: Double
    public var color: Color

    public init(offset: Double, color: Color) {
        self.offset = offset
        self.color = color
    }
}

public enum Fill: Codable, Sendable, Hashable {
    case solid(Color)
    /// Colors run from `start` (offset 0) to `end` (offset 1), in shape space.
    case linear(stops: [GradientStop], start: Point, end: Point)
    /// Colors run from `center` (offset 0) out to `radius` (offset 1).
    case radial(stops: [GradientStop], center: Point, radius: Double)

    private enum CodingKeys: String, CodingKey {
        case type, stops, start, end, center, radius
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let type = try c.decodeIfPresent(String.self, forKey: .type) else {
            self = .solid(try Color(from: decoder))
            return
        }
        switch type {
        case "linear":
            self = .linear(stops: try c.decode([GradientStop].self, forKey: .stops),
                           start: try c.decode(Point.self, forKey: .start),
                           end: try c.decode(Point.self, forKey: .end))
        case "radial":
            self = .radial(stops: try c.decode([GradientStop].self, forKey: .stops),
                           center: try c.decode(Point.self, forKey: .center),
                           radius: try c.decode(Double.self, forKey: .radius))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown fill type \(type)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .solid(let color):
            try color.encode(to: encoder)
        case .linear(let stops, let start, let end):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode("linear", forKey: .type)
            try c.encode(stops, forKey: .stops)
            try c.encode(start, forKey: .start)
            try c.encode(end, forKey: .end)
        case .radial(let stops, let center, let radius):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode("radial", forKey: .type)
            try c.encode(stops, forKey: .stops)
            try c.encode(center, forKey: .center)
            try c.encode(radius, forKey: .radius)
        }
    }

    /// The stops of a gradient; empty for a solid fill.
    public var stops: [GradientStop] {
        switch self {
        case .solid: []
        case .linear(let stops, _, _), .radial(let stops, _, _): stops
        }
    }

    /// Throws `ModelError.invalidFill` if the fill breaks an invariant above.
    func validate() throws {
        let colors = if case .solid(let color) = self { [color] } else { stops.map(\.color) }
        for color in colors where !color.isFinite {
            throw ModelError.invalidFill("color channels must be finite")
        }
        var previous = 0.0
        for stop in stops {
            guard stop.offset.isFinite, (0...1).contains(stop.offset) else {
                throw ModelError.invalidFill("gradient stop offset \(stop.offset) outside 0...1")
            }
            guard stop.offset >= previous else { throw ModelError.invalidFill("gradient stops not sorted") }
            previous = stop.offset
        }
        if case .radial(_, _, let radius) = self, !(radius.isFinite && radius > 0) {
            throw ModelError.invalidFill("radial gradient radius must be finite and > 0")
        }
    }
}
