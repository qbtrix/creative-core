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
        text.onPath = TextOnPath(path: square, startOffset: 0.25, flipped: true)
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

    static let nanPath = Path(polyline: [Point(x: .nan, y: 0)], closed: false)

    static func refuses(_ edit: (inout Layer) -> Void, _ why: String = "", layers: Int = 1) {
        var doc = w1Document()
        edit(&doc.scenes[0].layers[layers])
        #expect(throws: FormatError.self, "\(why)") { try FlareFormat.validate(doc) }
    }

    /// The `FormatError.invalid` message validate gives after `edit` to "ball".
    static func message(_ edit: (inout Layer) -> Void) -> String {
        var doc = w1Document()
        edit(&doc.scenes[0].layers[1])
        do { try FlareFormat.validate(doc) } catch FormatError.invalid(let message) { return message } catch {}
        return "no invalid error"
    }

    /// A new layer "m" with `edit` applied.
    static func layer(_ edit: (inout Layer) -> Void) -> Layer {
        var layer = Layer(id: "m", name: "M")
        edit(&layer)
        return layer
    }

    /// A path of more than `maxTotalPoints` points, as cubics so it builds fast.
    static func hugePath() -> Path {
        let cubic = PathElement.cubic(control1: Point(x: 0, y: 0), control2: Point(x: 1, y: 1), to: Point(x: 2, y: 0))
        return Path(elements: Array(repeating: cubic, count: FlareFormat.maxTotalPoints / 3 + 1))
    }

    /// What the encoder wrote for this text layer before the W1 fields existed.
    static let preW1Golden = """
    {
      "document" : {
        "scenes" : [
          {
            "background" : {
              "a" : 1,
              "b" : 1,
              "g" : 1,
              "r" : 1
            },
            "durationFrames" : 10,
            "fps" : 24,
            "guides" : [

            ],
            "height" : 400,
            "id" : "s",
            "labels" : {

            },
            "layers" : [
              {
                "id" : "l",
                "instances" : [

                ],
                "isLocked" : false,
                "isVisible" : true,
                "name" : "L",
                "shapes" : [

                ],
                "texts" : [
                  {
                    "fill" : {
                      "a" : 1,
                      "b" : 0,
                      "g" : 0,
                      "r" : 0
                    },
                    "fontFamily" : "Inter",
                    "fontSize" : 12,
                    "position" : {
                      "x" : 0,
                      "y" : 0
                    },
                    "string" : "Hi"
                  }
                ],
                "tracks" : {

                }
              }
            ],
            "name" : "S",
            "width" : 550
          }
        ],
        "symbols" : [

        ]
      },
      "format" : "flare",
      "version" : 1
    }
    """

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
        #expect(String(decoding: try FlareFormat.encode(doc), as: UTF8.self) == Self.preW1Golden)
        #expect(try FlareFormat.encode(FlareFormat.decode(Data(Self.preW1Golden.utf8))) == Data(Self.preW1Golden.utf8))
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
        Self.refuses({ $0.texts[0].onPath?.startOffset = 40 }, "path offset 40, points not a fraction")
        Self.refuses({ $0.texts[0].onPath?.startOffset = -0.1 }, "negative path offset")
        Self.refuses({ $0.colorTracks["fill.0"]?[1].frame = 0 }, "two keys on one frame")
        Self.refuses({ $0.colorTracks["fill.0"]?.reverse() }, "unsorted colour track")
        Self.refuses({ $0.colorTracks["fill.0"]?[1].frame = 49 }, "key past the duration")
        Self.refuses({ $0.colorTracks["fill.0"] = [] }, "empty colour track")
        Self.refuses({ $0.shapeTracks[0].shapeIndex = -1 }, "negative shape index")
        Self.refuses({ $0.shapeTracks[0].keys[0].path = Self.nanPath }, "NaN path")
        Self.refuses({ $0.shapeTracks[0].shapeIndex = $0.shapes.count }, "shape index past the shapes")
        Self.refuses({ $0.shapeTracks.append($0.shapeTracks[0]) }, "two tracks for one shape")
        Self.refuses({ $0.colorTracks["fill.99"] = $0.colorTracks["fill.0"] }, "colour track for a missing shape")
        Self.refuses({ $0.colorTracks["text.1"] = $0.colorTracks["fill.0"] }, "colour track for a missing text")
        Self.refuses({ $0.colorTracks["fill.0x"] = $0.colorTracks["fill.0"] }, "colour track key not an index")
        Self.refuses({ $0.colorTracks["fill.00"] = $0.colorTracks["fill.0"] }, "colour track key fill.00, a twin of fill.0")
        Self.refuses({ $0.colorTracks["fill.+0"] = $0.colorTracks["fill.0"] }, "colour track key fill.+0, a twin of fill.0")
        Self.refuses({ $0.texts[0].runs[0].start = -1; $0.texts[0].runs[0].length = 1 }, "negative run start")
        Self.refuses({ $0.masks[0].path = Self.nanPath }, "NaN mask path")
        Self.refuses({ $0.texts[0].onPath?.path = Self.nanPath }, "NaN text path")
        Self.refuses({ $0.texts[0].runs[1].tracking = .nan }, "NaN run tracking")
        Self.refuses({ $0.texts[0].runs[1].baselineShift = .infinity }, "infinite baseline shift")
        Self.refuses({ $0.texts[0].runs[0].fill = .solid(Color(r: .nan, g: 0, b: 0)) }, "NaN run fill")
        Self.refuses({ $0.texts[0].paragraph?.lineHeight = 0.4 }, "lineHeight 0.4")
        Self.refuses({ $0.texts[0].paragraph?.boxWidth = 0 }, "boxWidth 0")
        Self.refuses({ $0.texts[0].paragraph?.tracking = .nan }, "NaN paragraph tracking")
        Self.refuses({ $0.texts[0].paragraph?.paragraphSpacing = .infinity }, "infinite paragraph spacing")
        Self.refuses({ $0.colorTracks["fill.0"]?[0].value = Color(r: .nan, g: 0, b: 0, a: 1) }, "NaN colour key")
        Self.refuses({ $0.colorTracks["fill.0"]?[0].frame = -1 }, "negative key frame")
        Self.refuses({ l in   // with colour track fill.0, one track over the limit
            l.shapes = Array(repeating: l.shapes[0], count: FlareFormat.maxTracksPerLayer)
            l.shapeTracks = l.shapes.indices.map { ShapeTrack(shapeIndex: $0, keys: l.shapeTracks[0].keys) }
        }, "too many tracks")
    }

    /// Values exactly at each limit validate, so an off-by-one in a guard fails here.
    @Test func acceptsBoundaries() throws {
        var doc = Self.w1Document()
        let ball = doc.scenes[0].layers[1]
        #expect(ball.texts[0].runs.last.map { $0.start + $0.length } == ball.texts[0].string.count) // last run ends at the end
        try FlareFormat.validate(doc)
        doc.scenes[0].layers[1].masks = Array(repeating: ball.masks[0], count: FlareFormat.maxMasksPerLayer)
        try FlareFormat.validate(doc)
        for offset in [0.0, 1.0] {
            doc.scenes[0].layers[1].texts[0].onPath?.startOffset = offset
            try FlareFormat.validate(doc)
        }
    }

    @Test func messagesNameTheItemAndValue() {
        let mask = Self.message { $0.masks.append($0.masks[0]); $0.masks[1].opacity = 1.5 }
        #expect(mask.contains("mask 1") && mask.contains("1.5"), "\(mask)")
        let lineHeight = Self.message { $0.texts[0].paragraph?.lineHeight = 5 }
        #expect(lineHeight.contains("0.5...4"), "\(lineHeight)")
        let font = Self.message { $0.texts[0].runs[0].fontSize = 0 }
        #expect(font.contains("fontSize") && font.contains("text 0 run 0"), "\(font)")
        let key = Self.message { $0.colorTracks["fil.0"] = $0.colorTracks["fill.0"] }
        #expect(key.contains("fil.0") && key.contains("fill.<i>") && key.contains("text.<i>"), "\(key)")
        let offset = Self.message { $0.texts[0].onPath?.startOffset = 40 }
        #expect(offset == "layer ball: text 0: onPath startOffset 40.0 is a fraction of the path length, 0...1", "\(offset)")
    }

    @Test func w1GeometryCountsTowardThePointLimit() {
        let huge = Self.hugePath()
        let layers = [Self.layer { $0.masks = [LayerMask(path: huge)] },
                      Self.layer { $0.texts = [TextShape(string: "a", fontFamily: "Inter", fontSize: 9, position: Point(x: 0, y: 0))]
                                   $0.texts[0].onPath = TextOnPath(path: huge) },
                      Self.layer { $0.shapes = [Shape(points: [])]
                                   $0.shapeTracks = [ShapeTrack(shapeIndex: 0, keys: [PathKeyframe(frame: 0, path: huge)])] }]
        for layer in layers {
            var doc = Self.w1Document()
            doc.scenes[0].layers.append(layer)
            #expect(throws: FormatError.tooLarge("more than \(FlareFormat.maxTotalPoints) points")) {
                try FlareFormat.validate(doc)
            }
            var engine = CommandEngine(document: Self.w1Document())
            #expect(throws: CommandError.self) {
                do { try engine.perform(AddLayer(owner: .scene(Fixtures.sceneID), layer: layer)) } catch let error {
                    #expect("\(error)".contains("tooLarge"), "\(error)")
                    throw error
                }
            }
            #expect(engine.document == Self.w1Document())
        }
    }

    @Test func addLayerRefusesBadW1Layer() {
        let bad = [Self.layer { $0.masks = [LayerMask(path: Self.square, feather: .nan)] },
                   Self.layer { $0.matte = TrackMatte(sourceLayerID: "m") },
                   Self.layer { $0.matte = TrackMatte(sourceLayerID: "nope") }]
        for layer in bad {
            var engine = CommandEngine(document: Self.w1Document())
            #expect(throws: CommandError.self) { try engine.perform(AddLayer(owner: .scene(Fixtures.sceneID), layer: layer)) }
            #expect(engine.document == Self.w1Document())
        }
    }

    @Test func refusesMatteCycleTwoDeep() {
        Self.refuses({ $0.matte = TrackMatte(sourceLayerID: "ball") }, "bg <-> ball", layers: 0)
        var doc = Self.w1Document()
        doc.scenes[0].layers[0].matte = TrackMatte(sourceLayerID: "ball")
        var message = "no invalid error"
        do { try FlareFormat.validate(doc) } catch FormatError.invalid(let m) { message = m } catch {}
        #expect(message.contains("ball -> bg -> ball") || message.contains("bg -> ball -> bg"), "\(message)")
        #expect(message.contains("cycle") && message.contains("remove one layer's matte"), "\(message)")
    }

    @Test func refusesColourKeyOutOfRange() {
        Self.refuses({ $0.colorTracks["fill.0"]?[0].value = Color(r: 2, g: 0, b: 0) }, "colour key red 2")
        Self.refuses({ $0.colorTracks["fill.0"]?[1].value = Color(r: 0, g: 0, b: 0, a: -0.1) }, "colour key alpha -0.1")
        let message = Self.message { $0.colorTracks["fill.0"]?[0].value = Color(r: 2, g: 0, b: 0) }
        #expect(message.contains("fill.0") && message.contains("0...1"), "\(message)")
    }

    @Test func refusesRunWeightOutOfRange() throws {
        Self.refuses({ $0.texts[0].runs[0].weight = 5000 }, "weight 5000")
        Self.refuses({ $0.texts[0].runs[0].weight = 99 }, "weight 99")
        let message = Self.message { $0.texts[0].runs[0].weight = 5000 }
        #expect(message.contains("5000") && message.contains("100...900"), "\(message)")
        for weight in [100, 900] {
            var doc = Self.w1Document()
            doc.scenes[0].layers[1].texts[0].runs[0].weight = weight
            try FlareFormat.validate(doc)
        }
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
            { l, _, n in l.masks = Array(repeating: l.masks.first ?? LayerMask(path: Self.square), count: min(max(n, 1), 40)) },
            { l, d, _ in l.masks = l.masks.map { LayerMask(path: Path(polyline: [Point(x: d, y: 0)], closed: true), opacity: $0.opacity) } },
            { l, d, _ in l.texts[0].paragraph?.tracking = d }, { l, d, _ in l.texts[0].paragraph?.paragraphSpacing = d },
            { l, d, _ in l.texts[0].paragraph?.boxWidth = d }, { l, d, _ in l.texts[0].onPath?.startOffset = d },
            { l, d, _ in l.texts[0].onPath?.path = Path(polyline: [Point(x: 0, y: d)], closed: false) },
            { l, d, _ in l.colorTracks["fill.0"]?[0].value = Color(r: d, g: 0, b: 0) },
            { l, _, n in l.colorTracks["fill.\(n)"] = [ColorKeyframe(frame: 0, value: .white)] },
            { l, _, n in l.shapeTracks[0].shapeIndex = n },
            { l, d, _ in l.texts[0].runs[1].tracking = d }, { l, d, _ in l.texts[0].runs[1].baselineShift = d },
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

    @Test func fuzzBytesNeverCrash() throws {
        var rng = SplitMix64(seed: 62)
        let clean = Array(try FlareFormat.encode(Self.w1Document()))
        let text = String(decoding: clean, as: UTF8.self)
        let starts = Self.newKeys.compactMap { text.range(of: "\"\($0)\"").map { text.utf8.distance(from: text.startIndex, to: $0.lowerBound) } }
        let junk = Array("0-9e.[]{}\",: ntf".utf8)
        for _ in 0..<200 {
            var bytes = clean
            for _ in 0..<Int.random(in: 1...4, using: &rng) {
                let start = starts.randomElement(using: &rng) ?? 0
                let at = min(bytes.count - 1, start + Int.random(in: 0..<300, using: &rng))
                switch Int.random(in: 0..<3, using: &rng) {
                case 0: bytes[at] = junk.randomElement(using: &rng) ?? 0
                case 1: bytes.remove(at: at)
                default: bytes.removeSubrange(at...)
                }
                if bytes.isEmpty { break }
            }
            do {
                let doc = try FlareFormat.decode(Data(bytes))
                try FlareFormat.validate(doc)
            } catch is FormatError {}
        }
    }
}
