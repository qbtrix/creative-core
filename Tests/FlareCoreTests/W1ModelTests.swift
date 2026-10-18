// W1ModelTests.swift: older files load and save unchanged, every W1 field round
// trips, validate refuses each bad value, and a seeded fuzz never crashes.
import FlareCore
import Foundation
import Testing

@Suite struct W1ModelTests {
    static let newKeys = ["masks", "matte", "colorTracks", "shapeTracks", "runs", "paragraph", "onPath"]
    static let square = Path(polyline: [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10)], closed: true)

    /// The fixture with every W1 field set on "ball", matted by "bg".
    static func w1Document() -> Document {
        var doc = Fixtures.document()
        var text = TextShape(string: "Hello", fontFamily: "Inter", fontSize: 12, position: Point(x: 1, y: 2))
        text.runs = [TextRun(start: 0, length: 2, fontSize: 14, weight: 700, italic: true, fill: .solid(.white)),
                     TextRun(start: 2, length: 3, tracking: 0.5, baselineShift: -1)]
        text.paragraph = ParagraphStyle(alignment: .center, lineHeight: 1.5, boxWidth: 200)
        text.onPath = TextOnPath(path: square, startOffset: 3, flipped: true)
        var ball = doc.scenes[0].layers[1]
        ball.texts = [text]
        ball.masks = [LayerMask(path: square, mode: .subtract, feather: 2, opacity: 0.5, inverted: true)]
        ball.matte = TrackMatte(sourceLayerID: "bg", kind: .lumaInverted)
        ball.colorTracks = ["fill.0": [ColorKeyframe(frame: 0, value: .black), ColorKeyframe(frame: 10, value: .white)]]
        ball.shapeTracks = [ShapeTrack(shapeIndex: 0, keys: [PathKeyframe(frame: 0, path: square, easing: .hold)])]
        doc.scenes[0].layers[1] = ball
        doc.scenes[0].layers[0].matte = TrackMatte(sourceLayerID: "top")   // a chain ball -> bg -> top is fine
        doc.scenes[0].layers.append(Layer(id: "top", name: "Top"))
        return doc
    }

    static func refuses(_ edit: (inout Layer) -> Void, _ why: String = "", layers: Int = 1) {
        var doc = w1Document()
        edit(&doc.scenes[0].layers[layers])
        #expect(throws: FormatError.self, "\(why)") { try FlareFormat.validate(doc) }
    }

    @Test func v1RoundTripsByteForByte() throws {
        let v1 = #"""
        {"format":"flare","version":1,"document":{"scenes":[{"id":"s","name":"S","fps":24,"durationFrames":10,
          "layers":[{"id":"l","name":"L","shapes":[],"tracks":{},
            "texts":[{"string":"Hi","fontFamily":"Inter","fontSize":12,"position":{"x":0,"y":0},
              "fill":{"r":0,"g":0,"b":0,"a":1}}]}]}]}}
        """#
        let doc = try FlareFormat.decode(Data(v1.utf8))
        let layer = doc.scenes[0].layers[0]
        #expect(layer.masks.isEmpty && layer.matte == nil && layer.colorTracks.isEmpty && layer.shapeTracks.isEmpty)
        #expect(layer.texts[0].runs.isEmpty && layer.texts[0].paragraph == nil && layer.texts[0].onPath == nil)
        let bytes = try FlareFormat.encode(doc)
        let text = String(decoding: bytes, as: UTF8.self)
        for key in Self.newKeys { #expect(!text.contains("\"\(key)\""), "v1 file gained \(key)") }
        #expect(try FlareFormat.encode(FlareFormat.decode(bytes)) == bytes)
    }

    @Test func everyFieldRoundTrips() throws {
        try FlareFormat.validate(Self.w1Document())   // so each refusal below is the edit's doing
        let bytes = try FlareFormat.encode(Self.w1Document())
        #expect(try FlareFormat.decode(bytes) == Self.w1Document())
        let text = String(decoding: bytes, as: UTF8.self)
        for key in Self.newKeys { #expect(text.contains("\"\(key)\""), "\(key) not written") }
    }

    @Test func refusesBadValues() {
        Self.refuses({ $0.masks[0].feather = .nan }, "NaN feather")
        Self.refuses({ $0.masks[0].opacity = 1.5 }, "opacity 1.5")
        Self.refuses({ $0.masks = Array(repeating: $0.masks[0], count: 33) }, "33 masks")
        Self.refuses({ $0.matte = TrackMatte(sourceLayerID: "ball") }, "self matte")
        Self.refuses({ $0.matte = TrackMatte(sourceLayerID: "nope") }, "unknown matte source")
        Self.refuses({ $0.texts[0].runs[1].length = 4 }, "run past the string")
        Self.refuses({ $0.texts[0].runs[1].length = 0 }, "empty run")
        Self.refuses({ $0.texts[0].runs[0].fontSize = 0 }, "run font size 0")
        Self.refuses({ $0.texts[0].paragraph?.lineHeight = 5 }, "lineHeight 5")
        Self.refuses({ $0.texts[0].onPath?.startOffset = .infinity }, "infinite path offset")
        Self.refuses({ $0.colorTracks["fill.0"]?.reverse() }, "unsorted colour track")
        Self.refuses({ $0.colorTracks["fill.0"]?[1].frame = 49 }, "key past the duration")
        Self.refuses({ $0.colorTracks["fill.0"] = [] }, "empty colour track")
        Self.refuses({ $0.shapeTracks[0].shapeIndex = -1 }, "negative shape index")
        Self.refuses({ $0.shapeTracks[0].keys[0].path = Path(polyline: [Point(x: .nan, y: 0)], closed: false) }, "NaN path")
    }

    @Test func refusesMatteCycleTwoDeep() {
        Self.refuses({ $0.matte = TrackMatte(sourceLayerID: "ball") }, "bg <-> ball", layers: 0)
    }

    @Test func refusesTouchingRunsThatOverlap() {
        Self.refuses({ $0.texts[0].runs[1].start = 1; $0.texts[0].runs[1].length = 4 }, "runs share grapheme 1")
    }

    @Test func capsKeysAt4096() throws {
        var doc = Self.w1Document()
        doc.scenes[0].durationFrames = 5000
        let keys = (0..<4096).map { ColorKeyframe(frame: $0, value: .black) }
        doc.scenes[0].layers[1].colorTracks["fill.0"] = keys
        try FlareFormat.validate(doc)
        doc.scenes[0].layers[1].colorTracks["fill.0"] = keys + [ColorKeyframe(frame: 4096, value: .white)]
        #expect(throws: FormatError.self) { try FlareFormat.validate(doc) }
    }

    @Test func removingAMatteSourceIsRefused() {
        var engine = CommandEngine(document: Self.w1Document())
        #expect(throws: CommandError.self) { try engine.perform(RemoveLayer(owner: .scene(Fixtures.sceneID), layerID: "bg")) }
        #expect(engine.document == Self.w1Document())
    }

    @Test func fuzzNeverCrashes() throws {
        var rng = SplitMix64(seed: 61)
        let wild: [Double] = [.nan, .infinity, -1, 0, 0.5, 1.5, 5, 1e308]
        let ints = [Int.min, -1, 0, 1, 3, 5, 48, Int.max]
        let edits: [(inout Layer, Double, Int) -> Void] = [
            { l, d, _ in l.masks[0].feather = d }, { l, d, _ in l.masks[0].opacity = d },
            { l, d, _ in l.texts[0].paragraph?.lineHeight = d }, { l, d, _ in l.texts[0].runs[0].fontSize = d },
            { l, _, n in l.texts[0].runs[0].start = n }, { l, _, n in l.texts[0].runs[1].length = n },
            { l, _, n in l.colorTracks["fill.0"]?[0].frame = n }, { l, _, n in l.shapeTracks[0].keys[0].frame = n },
            { l, _, n in l.matte = TrackMatte(sourceLayerID: n % 2 == 0 ? "ball" : "bg") },
        ]
        for _ in 0..<200 {
            var doc = Self.w1Document()
            for _ in 0..<Int.random(in: 1...3, using: &rng) {
                let d = wild.randomElement(using: &rng) ?? 0, n = ints.randomElement(using: &rng) ?? 0
                edits.randomElement(using: &rng)?(&doc.scenes[0].layers[1], d, n)
            }
            do {
                try FlareFormat.validate(doc)
                #expect(try FlareFormat.decode(FlareFormat.encode(doc)) == doc)
            } catch is FormatError {}
        }
    }
}
