// SymbolTests.swift: symbol definitions in the document and the file format.
// Old files decode with no symbols, symbols round-trip byte-stable, and
// validate applies scene-style layer checks to symbols.
import FlareCore
import Foundation
import Testing

@Suite struct SymbolTests {
    static func documentWithSymbols() -> Document {
        var doc = Fixtures.document()
        let spin = Layer(
            id: "blade", name: "Blade",
            shapes: [Shape(points: [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 5, y: 3)])],
            tracks: ["rotation": [Keyframe(frame: 0, value: 0), Keyframe(frame: 11, value: 360)]]
        )
        doc.symbols = [
            Symbol(id: "fan", name: "Fan", durationFrames: 12, layers: [spin]),
            Symbol(id: "empty", name: "Empty", durationFrames: 0),
        ]
        return doc
    }

    @Test func oldFileDecodesWithNoSymbols() throws {
        let json = #"""
        {"format":"flare","version":1,"document":{"scenes":[{"id":"s","name":"S","fps":24,"durationFrames":10,"layers":[]}]}}
        """#
        let doc = try FlareFormat.decode(Data(json.utf8))
        #expect(doc.symbols.isEmpty)
        #expect(doc.scenes.count == 1)
    }

    @Test func symbolsRoundTripByteStable() throws {
        let original = Self.documentWithSymbols()
        let first = try FlareFormat.encode(original)
        let decoded = try FlareFormat.decode(first)
        #expect(decoded == original)
        #expect(try FlareFormat.encode(decoded) == first)
    }

    @Test func duplicateSymbolIDThrows() {
        var doc = Self.documentWithSymbols()
        doc.symbols.append(Symbol(id: "fan", name: "Fan 2"))
        #expect(throws: FormatError.invalid("duplicate symbol id fan")) { try FlareFormat.validate(doc) }
        #expect(throws: FormatError.self) { try FlareFormat.encode(doc) }
    }

    @Test func symbolLayerProblemsThrow() {
        var dupLayer = Self.documentWithSymbols()
        dupLayer.symbols[0].layers.append(Layer(id: "blade", name: "Again"))
        #expect(throws: FormatError.invalid("symbol fan: duplicate layer id blade")) { try FlareFormat.validate(dupLayer) }

        var unsorted = Self.documentWithSymbols()
        unsorted.symbols[0].layers[0].tracks["rotation"] = [Keyframe(frame: 5, value: 0), Keyframe(frame: 2, value: 0)]
        #expect(throws: FormatError.self) { try FlareFormat.validate(unsorted) }

        var emptyTrack = Self.documentWithSymbols()
        emptyTrack.symbols[0].layers[0].tracks["x"] = []
        #expect(throws: FormatError.self) { try FlareFormat.validate(emptyTrack) }

        var negative = Self.documentWithSymbols()
        negative.symbols[1].durationFrames = -1
        #expect(throws: FormatError.invalid("symbol empty: negative duration")) { try FlareFormat.validate(negative) }
    }

    @Test func symbolLayerIDsAreIndependentOfScenes() throws {
        var doc = Self.documentWithSymbols()
        let sceneLayerID = try #require(doc.scenes.first?.layers.first?.id)
        doc.symbols[0].layers.append(Layer(id: sceneLayerID, name: "Shared id"))
        try FlareFormat.validate(doc)
    }

    @Test func malformedSymbolsThrow() {
        let json = #"""
        {"format":"flare","version":1,"document":{"scenes":[],"symbols":[{"id":"a"}]}}
        """#
        #expect(throws: FormatError.self) { try FlareFormat.decode(Data(json.utf8)) }
    }
}
