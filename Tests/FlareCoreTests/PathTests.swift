// PathTests.swift: Path elements round trip through Codable and the file
// format, old shapes without a path still decode, and path wins over points.
import FlareCore
import Foundation
import Testing

@Suite struct PathTests {
    static let everyKind = Path(elements: [
        .move(to: Point(x: 0, y: 0)),
        .line(to: Point(x: 10, y: 0)),
        .quad(control: Point(x: 15, y: 5), to: Point(x: 10, y: 10)),
        .cubic(control1: Point(x: 5, y: 15), control2: Point(x: -5, y: 15), to: Point(x: 0, y: 10)),
        .close,
    ])

    static func document(with path: Path?) -> Document {
        var doc = Fixtures.document()
        doc.scenes[0].layers[0].shapes.append(Shape(points: [], fill: .solid(Color(r: 1, g: 0, b: 0)), path: path))
        return doc
    }

    @Test func everyElementKindRoundTrips() throws {
        for element in Self.everyKind.elements {
            let data = try JSONEncoder().encode(element)
            #expect(try JSONDecoder().decode(PathElement.self, from: data) == element)
        }
        let data = try JSONEncoder().encode(Self.everyKind)
        #expect(try JSONDecoder().decode(Path.self, from: data) == Self.everyKind)
    }

    @Test func fileRoundTripIsByteStable() throws {
        let doc = Self.document(with: Self.everyKind)
        let first = try FlareFormat.encode(doc)
        let decoded = try FlareFormat.decode(first)
        #expect(decoded == doc)
        #expect(try FlareFormat.encode(decoded) == first)
    }

    @Test func v1ShapeWithOnlyPointsDecodes() throws {
        let json = #"""
        {"format":"flare","version":1,"document":{"scenes":[{"id":"s","name":"S","fps":24,"durationFrames":1,
          "layers":[{"id":"l","name":"L","tracks":{},"shapes":[{"points":[{"x":0,"y":0},{"x":1,"y":2}],
            "closed":false,"fill":{"r":0,"g":0,"b":0,"a":1}}]}]}]}}
        """#
        let shape = try FlareFormat.decode(Data(json.utf8)).scenes[0].layers[0].shapes[0]
        #expect(shape.path == nil)
        #expect(shape.points == [Point(x: 0, y: 0), Point(x: 1, y: 2)])
        #expect(shape.outline == Path(elements: [.move(to: Point(x: 0, y: 0)), .line(to: Point(x: 1, y: 2))]))
    }

    @Test func shapeWithoutPathEncodesNoPathKey() throws {
        let text = String(decoding: try FlareFormat.encode(Fixtures.document()), as: UTF8.self)
        #expect(!text.contains(#""path""#))
    }

    @Test func pathWinsOverPoints() {
        let square = Shape(points: [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 1, y: 1)], closed: true)
        #expect(square.outline == Path(polyline: square.points, closed: true))
        #expect(square.outline.elements.last == .close)
        var curved = square
        curved.path = Self.everyKind
        #expect(curved.outline == Self.everyKind)
    }

    @Test func emptyPolylineIsEmptyPath() {
        #expect(Path(polyline: [], closed: true).elements.isEmpty)
    }

    @Test(arguments: [
        #"{"elements":[{"bogus":{}}]}"#,
        #"{"elements":[{"move":{}}]}"#,
        #"{"elements":[{"cubic":{"control1":{"x":0,"y":0},"to":{"x":1,"y":1}}}]}"#,
        #"{"elements":[{"line":{"to":{"x":"a","y":0}}}]}"#,
        #"{"elements":{}}"#,
    ])
    func malformedPathThrows(_ json: String) {
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Path.self, from: Data(json.utf8)) }
    }

    @Test func fuzzedPathFilesThrowOrDecode() throws {
        let base = try FlareFormat.encode(Self.document(with: Self.everyKind))
        var rng = SplitMix64(seed: 20)
        for _ in 0..<300 {
            var bytes = [UInt8](base)
            for _ in 0..<3 {
                let i = Int(rng.next() % UInt64(bytes.count))
                bytes[i] = UInt8(truncatingIfNeeded: rng.next())
            }
            _ = try? FlareFormat.decode(Data(bytes))
        }
    }
}
