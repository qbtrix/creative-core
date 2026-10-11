// StrokeTests.swift: Shape.stroke round trips through the file format, old
// shapes without a stroke decode as nil, and bad widths fail validation.
import FlareCore
import Foundation
import Testing

@Suite struct StrokeTests {
    static func document(with stroke: Stroke?) -> Document {
        var doc = Fixtures.document()
        doc.scenes[0].layers[1].shapes[0].stroke = stroke
        return doc
    }

    @Test func everyJoinAndCapRoundTrips() throws {
        for join in Stroke.Join.allCases {
            for cap in Stroke.Cap.allCases {
                let stroke = Stroke(color: Color(r: 0.1, g: 0.2, b: 0.3, a: 0.5), width: 2.5, join: join, cap: cap)
                let doc = Self.document(with: stroke)
                let first = try FlareFormat.encode(doc)
                let decoded = try FlareFormat.decode(first)
                #expect(decoded == doc)
                #expect(decoded.scenes[0].layers[1].shapes[0].stroke == stroke)
                #expect(try FlareFormat.encode(decoded) == first)
            }
        }
    }

    @Test func zeroWidthIsValid() throws {
        try FlareFormat.validate(Self.document(with: Stroke(width: 0)))
    }

    @Test func v1ShapeWithoutStrokeDecodesAsNil() throws {
        let json = #"""
        {"format":"flare","version":1,"document":{"scenes":[{"id":"s","name":"S","fps":24,"durationFrames":1,
          "layers":[{"id":"l","name":"L","tracks":{},"shapes":[{"points":[{"x":0,"y":0},{"x":1,"y":2}],
            "closed":false,"fill":{"r":0,"g":0,"b":0,"a":1}}]}]}]}}
        """#
        let shape = try FlareFormat.decode(Data(json.utf8)).scenes[0].layers[0].shapes[0]
        #expect(shape.stroke == nil)
    }

    @Test func shapeWithoutStrokeEncodesNoStrokeKey() throws {
        let text = String(decoding: try FlareFormat.encode(Fixtures.document()), as: UTF8.self)
        #expect(!text.contains(#""stroke""#))
    }

    @Test(arguments: [-1.0, -0.001, Double.nan, Double.infinity, -Double.infinity])
    func badWidthThrows(width: Double) {
        #expect(throws: FormatError.self) {
            try FlareFormat.validate(Self.document(with: Stroke(width: width)))
        }
    }

    @Test func badWidthInSymbolThrows() {
        var doc = Fixtures.document()
        let shape = Shape(points: [Point(x: 0, y: 0)], stroke: Stroke(width: -1))
        doc.symbols = [Symbol(id: "sym", name: "Sym", layers: [Layer(id: "l", name: "L", shapes: [shape])])]
        #expect(throws: FormatError.self) { try FlareFormat.validate(doc) }
    }

    @Test func unknownJoinInFileThrows() {
        let json = #"""
        {"format":"flare","version":1,"document":{"scenes":[{"id":"s","name":"S","fps":24,"durationFrames":1,
          "layers":[{"id":"l","name":"L","tracks":{},"shapes":[{"points":[],"closed":true,
            "fill":{"r":0,"g":0,"b":0,"a":1},
            "stroke":{"color":{"r":0,"g":0,"b":0,"a":1},"width":1,"join":"wobbly","cap":"butt"}}]}]}]}}
        """#
        #expect(throws: FormatError.self) { try FlareFormat.decode(Data(json.utf8)) }
    }
}
