// StrokeDashTrimTests.swift: a stroke's dash pattern, dash phase and trim. Old strokes decode with no dash and
// no trim and plain strokes encode as before; validation refuses a bad pattern, phase or trim; the painted path
// is the outline trimmed, then dashed, and render list items paint it; SVG writes stroke-dasharray and
// stroke-dashoffset and the trimmed geometry on a stroke-only path above the full fill; Lottie writes `st.d`
// and a `tm` that trims the stroke and not the fill; the trimStart/End/Offset.<i> tracks key the trim in both
// writers, and removing a shape moves them with their shapes.
import Foundation
import Testing
@testable import FlareCore

@Suite struct StrokeDashTrimTests {
    /// A 100 pt horizontal line, open.
    static let line = Path(polyline: [Point(x: 0, y: 0), Point(x: 100, y: 0)], closed: false)
    static let square = [Point(x: 0, y: 0), Point(x: 40, y: 0), Point(x: 40, y: 40), Point(x: 0, y: 40)]

    static func scene(_ stroke: Stroke?, tracks: [String: [Keyframe]] = [:]) -> Scene {
        let shape = Shape(points: Self.square, fill: .solid(Color(r: 1, g: 0, b: 0)), stroke: stroke)
        return Scene(id: "s", name: "S", layers: [Layer(id: "l", name: "L", shapes: [shape], tracks: tracks)])
    }

    static func paths(_ scene: Scene, frame: Double = 0) throws -> [String] {
        try SVGExporter.export(scene: scene, frame: frame).split(separator: "\n").filter { $0.hasPrefix("<path ") }.map(String.init)
    }

    /// The items of the first layer's first shape group.
    static func group(_ scene: Scene) throws -> [[String: Any]] {
        let json = try #require(try JSONSerialization.jsonObject(with: LottieExporter.export(scene: scene)) as? [String: Any])
        let group = try #require(((json["layers"] as? [[String: Any]])?.first?["shapes"] as? [[String: Any]])?.first)
        return try #require(group["it"] as? [[String: Any]])
    }

    @Test func oldStrokesDecodeWithNoDashOrTrimAndPlainStrokesEncodeAsBefore() throws {
        let plain = try JSONEncoder().encode(Stroke(color: .black, width: 2))
        let text = try #require(String(data: plain, encoding: .utf8))
        #expect(!text.contains("dash") && !text.contains("trim"))
        let old = try JSONDecoder().decode(Stroke.self, from: plain)
        #expect(old.dash.isEmpty && old.dashPhase == 0 && old.trim == nil && old.width == 2)
        let full = Stroke(width: 3, dash: [4, 2], dashPhase: 1.5, trim: StrokeTrim(start: 0.1, end: 0.7, offset: 0.25, mode: .eachContour))
        #expect(try JSONDecoder().decode(Stroke.self, from: JSONEncoder().encode(full)) == full)
    }

    @Test func validationRefusesBadPatternsPhasesAndTrims() throws {
        try Stroke(dash: [4, 2], dashPhase: -3, trim: StrokeTrim(start: 0, end: 1, offset: -2.5)).validate()
        try Stroke(dash: [0, 2]).validate()
        try Stroke(dash: Array(repeating: 1, count: Stroke.maxDashEntries)).validate()
        let bad = [
            Stroke(dash: Array(repeating: 1, count: Stroke.maxDashEntries + 1)), Stroke(dash: [4, -1]), Stroke(dash: [.nan, 2]),
            Stroke(dash: [0, 0]), Stroke(dash: [.infinity, 1]), Stroke(dash: [.greatestFiniteMagnitude, .greatestFiniteMagnitude]),
            Stroke(dashPhase: .nan), Stroke(trim: StrokeTrim(start: -0.1)), Stroke(trim: StrokeTrim(end: 1.5)),
            Stroke(trim: StrokeTrim(start: .nan)), Stroke(trim: StrokeTrim(offset: .infinity)),
        ]
        for stroke in bad {
            #expect(throws: ModelError.self, "\(stroke)") { try stroke.validate() }
        }
    }

    @Test func thePaintedPathIsTrimmedThenDashed() throws {
        func length(_ stroke: Stroke) throws -> Double { try stroke.paintedPath(Self.line, tolerance: 0.01).length(tolerance: 0.01) }
        #expect(try Stroke().paintedPath(Self.line, tolerance: 0.01) == Self.line)
        #expect(abs(try length(Stroke(trim: StrokeTrim(start: 0, end: 0.5))) - 50) < 1e-9)
        #expect(abs(try length(Stroke(dash: [10, 10])) - 50) < 1e-9)
        // Trimmed to 0...50, then dashed: 0-10, 20-30, 40-50. Dashed first, then trimmed, would keep 25.
        #expect(abs(try length(Stroke(dash: [10, 10], trim: StrokeTrim(start: 0, end: 0.5))) - 30) < 1e-9)
        // The phase shifts the pattern: 5 into [10, 10] leaves dashes 0-5, 15-25, ..., 95-100.
        #expect(abs(try length(Stroke(dash: [10, 10], dashPhase: 5)) - 50) < 1e-9)
        #expect(try Stroke(dash: [10, 10], dashPhase: 5).paintedPath(Self.line, tolerance: 0.01).elements.first == .move(to: Point(x: 0, y: 0)))
        #expect(try Stroke(dash: [10, 10], dashPhase: 5).paintedPath(Self.line, tolerance: 0.01).elements.dropFirst().first
                == .line(to: Point(x: 5, y: 0)))
    }

    @Test func renderListItemsPaintTheTrimmedDashedPath() throws {
        let stroke = Stroke(dash: [10, 5], trim: StrokeTrim(start: 0.25, end: 0.75))
        let list = Self.scene(stroke).renderList(at: 0, symbols: [])
        let item = try #require(list.items.first)
        #expect(try item.strokePath(tolerance: 0.01) == stroke.paintedPath(item.outline, tolerance: 0.01))
        #expect(try Self.scene(nil).renderList(at: 0, symbols: []).items.first?.strokePath(tolerance: 0.01) == nil)
    }

    @Test func svgWritesDashAttributes() throws {
        let line = try #require(try Self.paths(Self.scene(Stroke(width: 2, dash: [4, 2.5], dashPhase: 1))).first)
        #expect(line.contains(" stroke-dasharray=\"4 2.5\" stroke-dashoffset=\"1\""))
        #expect(!(try #require(try Self.paths(Self.scene(Stroke(width: 2))).first)).contains("dash"))
    }

    @Test func svgWritesTrimmedGeometryAboveTheFullFill() throws {
        let plain = try Self.paths(Self.scene(Stroke(width: 2)))
        let full = try Self.paths(Self.scene(Stroke(width: 2, trim: StrokeTrim(start: 0, end: 1, offset: 0.3))))
        #expect(plain.count == 1 && full == plain, "a trim that keeps everything writes the shape as before")
        let lines = try Self.paths(Self.scene(Stroke(width: 2, trim: StrokeTrim(start: 0, end: 0.25))))
        #expect(lines.count == 2)
        #expect(lines[0].contains("fill=\"#ff0000\"") && !lines[0].contains("stroke"))
        #expect(lines[1].contains("d=\"M0 0 L40 0\" fill=\"none\" stroke=\"#000000\" stroke-width=\"2\""))
    }

    @Test func trimTracksKeyTheSVGTrim() throws {
        let tracks = [Layer.trackKey(trimEndOf: 0): [Keyframe(frame: 0, value: 0.25), Keyframe(frame: 10, value: 0.75)],
                      Layer.trackKey(trimStartOf: 0): [Keyframe(frame: 0, value: 0)],
                      Layer.trackKey(trimOffsetOf: 0): [Keyframe(frame: 0, value: 0.25)]]
        // No trim on the stroke: the tracks start from the whole outline. Frame 5 samples end 0.5, offset a quarter.
        let lines = try Self.paths(Self.scene(Stroke(width: 2), tracks: tracks), frame: 5)
        #expect(lines.count == 2 && lines[1].contains("d=\"M40 0 L40 40 L0 40\" fill=\"none\""))
        #expect(try Self.paths(Self.scene(nil, tracks: tracks), frame: 5).count == 1, "trim tracks need a stroke")
    }

    @Test func lottieWritesDashesOnTheStroke() throws {
        let items = try Self.group(Self.scene(Stroke(width: 2, dash: [4, 2, 1], dashPhase: 3)))
        let st = try #require(items.first { $0["ty"] as? String == "st" })
        let d = try #require(st["d"] as? [[String: Any]])
        // An odd pattern repeats once, as SVG and `Path.dashed` read it, then the offset.
        #expect(d.map { $0["n"] as? String } == ["d", "g", "d", "g", "d", "g", "o"])
        #expect(d.map { ($0["v"] as? [String: Any])?["k"] as? Double } == [4, 2, 1, 4, 2, 1, 3])
        #expect(try Self.group(Self.scene(Stroke(width: 2))).first { $0["ty"] as? String == "st" }?["d"] == nil)
    }

    @Test func lottieTrimsTheStrokeAndNotTheFill() throws {
        let items = try Self.group(Self.scene(Stroke(width: 2, trim: StrokeTrim(start: 0.2, end: 0.8, offset: 0.25))))
        #expect(items.map { $0["ty"] as? String } == ["gr", "gr", "tr"])
        let stroke = try #require(items[0]["it"] as? [[String: Any]]), fill = try #require(items[1]["it"] as? [[String: Any]])
        #expect(stroke.map { $0["ty"] as? String } == ["sh", "tm", "st", "tr"])
        #expect(fill.map { $0["ty"] as? String } == ["sh", "fl", "tr"])
        let tm = stroke[1]
        #expect((tm["s"] as? [String: Any])?["k"] as? Double == 20 && (tm["e"] as? [String: Any])?["k"] as? Double == 80)
        #expect((tm["o"] as? [String: Any])?["k"] as? Double == 90 && tm["m"] as? Int == 2)
        let each = try Self.group(Self.scene(Stroke(trim: StrokeTrim(end: 0.5, mode: .eachContour))))
        #expect(((each[0]["it"] as? [[String: Any]])?[1])?["m"] as? Int == 1)
        #expect(try Self.group(Self.scene(Stroke(width: 2))).map { $0["ty"] as? String } == ["sh", "st", "fl", "tr"])
    }

    @Test func lottieAnimatesTrimTracks() throws {
        let tracks = [Layer.trackKey(trimEndOf: 0): [Keyframe(frame: 0, value: 0), Keyframe(frame: 24, value: 1)],
                      Layer.trackKey(trimOffsetOf: 0): [Keyframe(frame: 0, value: 0.5)]]
        let items = try Self.group(Self.scene(Stroke(width: 2), tracks: tracks))
        let tm = try #require((items.first?["it"] as? [[String: Any]])?.first { $0["ty"] as? String == "tm" })
        let e = try #require(tm["e"] as? [String: Any])
        #expect(e["a"] as? Int == 1 && (e["k"] as? [[String: Any]])?.map { $0["s"] as? [Double] } == [[0], [100]])
        #expect((tm["s"] as? [String: Any])?["k"] as? Double == 0 && (tm["o"] as? [String: Any])?["k"] as? Double == 180)
    }

    @Test func removingAShapeMovesItsTrimTracks() throws {
        var layer = Layer(id: "l", name: "L", tracks: [
            "trimStart.0": [Keyframe(frame: 0, value: 0.1)], "trimEnd.1": [Keyframe(frame: 0, value: 0.5)],
            "trimOffset.2": [Keyframe(frame: 0, value: 0.2)],
        ])
        layer.removeShapeTracks(at: 0)
        #expect(Set(layer.tracks.keys) == ["trimEnd.0", "trimOffset.1"])
    }
}
