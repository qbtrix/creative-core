// W1ModelInitTests.swift: the W1 fields can be set through `Layer.init` and
// `TextShape.init`, and the colour-track key helpers build the documented keys.
import FlareCore
import Foundation
import Testing

@Suite struct W1ModelInitTests {
    static let square = Path(polyline: [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10)], closed: true)

    @Test func layerInitTakesW1Fields() throws {
        let keys = [ColorKeyframe(frame: 0, value: .black)]
        let shapeKeys = [PathKeyframe(frame: 0, path: Self.square)]
        let layer = Layer(id: "a", name: "a", masks: [LayerMask(path: Self.square)],
                          matte: TrackMatte(sourceLayerID: "b"), colorTracks: [Layer.colorTrackKey(fillOf: 0): keys],
                          shapeTracks: [ShapeTrack(shapeIndex: 0, keys: shapeKeys)])
        #expect(layer.masks == [LayerMask(path: Self.square)])
        #expect(layer.matte == TrackMatte(sourceLayerID: "b"))
        #expect(layer.colorTracks == ["fill.0": keys])
        #expect(layer.shapeTracks == [ShapeTrack(shapeIndex: 0, keys: shapeKeys)])
        let data = try JSONEncoder().encode(layer)
        #expect(try JSONDecoder().decode(Layer.self, from: data) == layer)
    }

    @Test func layerInitDefaultsLeaveW1FieldsEmpty() {
        let layer = Layer(id: "a", name: "a")
        #expect(layer.masks.isEmpty && layer.matte == nil && layer.colorTracks.isEmpty && layer.shapeTracks.isEmpty)
    }

    @Test func textShapeInitTakesW1Fields() throws {
        let runs = [TextRun(start: 0, length: 1)]
        let paragraph = ParagraphStyle(alignment: .center, boxWidth: 100)
        let onPath = TextOnPath(path: Self.square, startOffset: 0.25, flipped: true)
        let text = TextShape(string: "hi", fontFamily: "F", fontSize: 12, position: Point(x: 0, y: 0),
                             runs: runs, paragraph: paragraph, onPath: onPath)
        #expect(text.runs == runs && text.paragraph == paragraph && text.onPath == onPath)
        let data = try JSONEncoder().encode(text)
        #expect(try JSONDecoder().decode(TextShape.self, from: data) == text)
        let plain = TextShape(string: "hi", fontFamily: "F", fontSize: 12, position: Point(x: 0, y: 0))
        #expect(plain.runs.isEmpty && plain.paragraph == nil && plain.onPath == nil)
    }

    @Test func colorTrackKeysMatchTheDocumentedForms() {
        #expect(Layer.colorTrackKey(fillOf: 0) == "fill.0")
        #expect(Layer.colorTrackKey(strokeOf: 3) == "stroke.3")
        #expect(Layer.colorTrackKey(text: 12) == "text.12")
    }
}
