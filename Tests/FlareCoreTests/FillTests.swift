// FillTests.swift: solid, linear and radial fills. Old files with a plain
// color fill stay byte-stable, gradients round-trip, and bad stops or radius
// are rejected on load.
import FlareCore
import Foundation
import Testing

@Suite struct FillTests {
    static func file(fill: String) -> Data {
        Data(#"""
        {"format":"flare","version":1,
         "document":{"scenes":[{"id":"s","name":"S","fps":24,"durationFrames":10,"layers":[
           {"id":"l","name":"L","tracks":{},"shapes":[{"points":[],"closed":true,"fill":\#(fill)}]}]}]}}
        """#.utf8)
    }

    static func roundTrip(_ fill: Fill) throws -> Fill? {
        var doc = Fixtures.document()
        doc.scenes[0].layers[1].shapes[0].fill = fill
        return try FlareFormat.decode(FlareFormat.encode(doc)).scenes.first?.layers.last?.shapes.first?.fill
    }

    static let stops = [
        GradientStop(offset: 0, color: .black),
        GradientStop(offset: 0.5, color: Color(r: 1, g: 0, b: 0, a: 0.5)),
        GradientStop(offset: 1, color: .white),
    ]

    @Test func oldFileDecodesAsSolidAndReencodesByteForByte() throws {
        let doc = try FlareFormat.decode(Self.file(fill: #"{"r":1,"g":0.5,"b":0,"a":1}"#))
        #expect(doc.scenes.first?.layers.first?.shapes.first?.fill == .solid(Color(r: 1, g: 0.5, b: 0)))
        let first = try FlareFormat.encode(doc)
        #expect(try FlareFormat.encode(FlareFormat.decode(first)) == first)
        // The solid fill is written as the plain color object, as in v1.
        let json = try #require(String(data: first, encoding: .utf8))
        #expect(!json.contains("\"type\""))
        #expect(json.contains("\"fill\" : {\n"))
    }

    @Test func fixtureEncodingIsUnchanged() throws {
        let data = try FlareFormat.encode(Fixtures.document())
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"a\" : 1,\n"))
        #expect(!json.contains("solid"))
    }

    @Test func linearGradientRoundTrips() throws {
        let fill = Fill.linear(stops: Self.stops, start: Point(x: 0, y: 0), end: Point(x: 10, y: 5))
        #expect(try Self.roundTrip(fill) == fill)
    }

    @Test func radialGradientRoundTrips() throws {
        let fill = Fill.radial(stops: Self.stops, center: Point(x: 5, y: 5), radius: 7.5)
        #expect(try Self.roundTrip(fill) == fill)
    }

    @Test func gradientDecodesFromJSON() throws {
        let doc = try FlareFormat.decode(Self.file(fill: #"""
        {"type":"radial","center":{"x":1,"y":2},"radius":3,
         "stops":[{"offset":0,"color":{"r":0,"g":0,"b":0,"a":1}},{"offset":1,"color":{"r":1,"g":1,"b":1,"a":1}}]}
        """#))
        let expected = Fill.radial(stops: [GradientStop(offset: 0, color: .black), GradientStop(offset: 1, color: .white)],
                                   center: Point(x: 1, y: 2), radius: 3)
        #expect(doc.scenes.first?.layers.first?.shapes.first?.fill == expected)
    }

    @Test func unsortedStopsThrowInvalid() {
        let stops = [GradientStop(offset: 0.8, color: .black), GradientStop(offset: 0.2, color: .white)]
        let fill = Fill.linear(stops: stops, start: Point(x: 0, y: 0), end: Point(x: 1, y: 0))
        #expect { try Self.roundTrip(fill) } throws: { error in
            if case FormatError.invalid = error { return true }
            return false
        }
        let json = #"""
        {"type":"linear","start":{"x":0,"y":0},"end":{"x":1,"y":0},
         "stops":[{"offset":1,"color":{"r":0,"g":0,"b":0,"a":1}},{"offset":0,"color":{"r":1,"g":1,"b":1,"a":1}}]}
        """#
        #expect { try FlareFormat.decode(Self.file(fill: json)) } throws: { error in
            if case FormatError.invalid = error { return true }
            return false
        }
    }

    @Test(arguments: [-0.1, 1.5, Double.nan, Double.infinity])
    func offsetOutsideUnitRangeThrowsInvalid(offset: Double) {
        let fill = Fill.radial(stops: [GradientStop(offset: offset, color: .black)], center: Point(x: 0, y: 0), radius: 1)
        #expect { try Self.roundTrip(fill) } throws: { error in
            if case FormatError.invalid = error { return true }
            return false
        }
    }

    @Test(arguments: [0, -1, Double.nan, Double.infinity])
    func nonPositiveRadiusThrowsInvalid(radius: Double) {
        let fill = Fill.radial(stops: Self.stops, center: Point(x: 0, y: 0), radius: radius)
        #expect { try Self.roundTrip(fill) } throws: { error in
            if case FormatError.invalid = error { return true }
            return false
        }
    }

    @Test func equalOffsetsAreAllowed() throws {
        let stops = [GradientStop(offset: 0.5, color: .black), GradientStop(offset: 0.5, color: .white)]
        let fill = Fill.linear(stops: stops, start: Point(x: 0, y: 0), end: Point(x: 1, y: 0))
        #expect(try Self.roundTrip(fill) == fill)
    }

    @Test func unknownFillTypeThrowsMalformed() {
        #expect { try FlareFormat.decode(Self.file(fill: #"{"type":"conic","stops":[]}"#)) } throws: { error in
            if case FormatError.malformed = error { return true }
            return false
        }
    }

    @Test func svgWritesGradientElements() throws {
        let square = [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10)]
        let layer = Layer(id: "l", name: "L", shapes: [
            Shape(points: square, fill: .linear(stops: Self.stops, start: Point(x: 0, y: 0), end: Point(x: 10, y: 0))),
            Shape(points: square, fill: .radial(stops: Self.stops, center: Point(x: 5, y: 5), radius: 5)),
        ])
        let svg = try SVGExporter.export(scene: Scene(id: "s", name: "S", layers: [layer]), frame: 0)
        #expect(svg.contains(#"<linearGradient id="g0" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="10" y2="0">"#))
        #expect(svg.contains(##"<stop offset="0.5" stop-color="#ff0000" stop-opacity="0.5"/>"##))
        #expect(svg.contains(#"<radialGradient id="g1" gradientUnits="userSpaceOnUse" cx="5" cy="5" r="5">"#))
        #expect(svg.contains(##"fill="url(#g0)"/>"##))
        #expect(svg.contains(##"fill="url(#g1)"/>"##))
    }
}
