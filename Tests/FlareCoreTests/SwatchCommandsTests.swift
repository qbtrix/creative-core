// SwatchCommandsTests.swift: Document.swatches and the swatch commands. Each
// command undoes exactly, bad params throw and leave the document unchanged,
// old files decode with an empty palette, and validate rejects duplicate
// names and out-of-range colors.
import FlareCore
import Foundation
import Testing

@Suite struct SwatchCommandsTests {
    static let red = Color(r: 1, g: 0, b: 0)
    static let blue = Color(r: 0, g: 0, b: 1, a: 0.5)

    static func palette() -> Document {
        var doc = Fixtures.document()
        doc.swatches = [Swatch(name: "Red", color: red), Swatch(name: "Blue", color: blue)]
        return doc
    }

    @Test func addSwatchAppendsAndUndoes() throws {
        let green = Color(r: 0, g: 1, b: 0)
        try SceneCommandTests.roundTrip(AddSwatch(name: "Green", color: green), on: Self.palette()) {
            #expect($0.swatches.map(\.name) == ["Red", "Blue", "Green"])
            #expect($0.swatches.last?.color == green)
        }
    }

    @Test func renameSwatchUndoes() throws {
        try SceneCommandTests.roundTrip(RenameSwatch(name: "Red", newName: "Crimson"), on: Self.palette()) {
            #expect($0.swatches.map(\.name) == ["Crimson", "Blue"])
            #expect($0.swatches.first?.color == Self.red)
        }
    }

    @Test func setSwatchColorUndoes() throws {
        try SceneCommandTests.roundTrip(SetSwatchColor(name: "Blue", color: .black), on: Self.palette()) {
            #expect($0.swatches == [Swatch(name: "Red", color: Self.red), Swatch(name: "Blue", color: .black)])
        }
    }

    @Test func removeSwatchUndoesInPlace() throws {
        try SceneCommandTests.roundTrip(RemoveSwatch(name: "Red"), on: Self.palette()) {
            #expect($0.swatches == [Swatch(name: "Blue", color: Self.blue)])
        }
    }

    @Test func invalidParamsThrowWithoutChanges() {
        let start = Self.palette()
        let bad = Color(r: 1.5, g: 0, b: 0)
        SceneCommandTests.rejects(AddSwatch(name: "Red", color: .black), on: start, .duplicateID("Red"))
        SceneCommandTests.rejects(AddSwatch(name: "Hot", color: bad), on: start, .invalidColor(bad))
        SceneCommandTests.rejects(AddSwatch(name: "", color: .black), on: start, .emptySwatchName)
        SceneCommandTests.rejects(RenameSwatch(name: "Red", newName: "Blue"), on: start, .duplicateID("Blue"))
        SceneCommandTests.rejects(RenameSwatch(name: "Red", newName: ""), on: start, .emptySwatchName)
        SceneCommandTests.rejects(RenameSwatch(name: "Nope", newName: "X"), on: start, .swatchNotFound("Nope"))
        SceneCommandTests.rejects(SetSwatchColor(name: "Red", color: bad), on: start, .invalidColor(bad))
        SceneCommandTests.rejects(SetSwatchColor(name: "Nope", color: .black), on: start, .swatchNotFound("Nope"))
        SceneCommandTests.rejects(RemoveSwatch(name: "Nope"), on: start, .swatchNotFound("Nope"))
        var engine = CommandEngine(document: start)
        #expect(throws: (any Error).self) { try engine.perform(AddSwatch(name: "N", color: Color(r: .nan, g: 0, b: 0))) }
        #expect(engine.document == start)
    }

    @Test func undoBeforeExecuteThrows() {
        var doc = Self.palette()
        #expect(throws: CommandError.notExecuted) { try SetSwatchColor(name: "Red", color: .black).undo(&doc) }
        #expect(throws: CommandError.notExecuted) { try RemoveSwatch(name: "Red").undo(&doc) }
    }

    @Test func oldFileDecodesWithNoSwatches() throws {
        let json = #"""
        {"format":"flare","version":1,
         "document":{"scenes":[{"id":"s","name":"S","fps":24,"durationFrames":10,"layers":[]}]}}
        """#
        #expect(try FlareFormat.decode(Data(json.utf8)).swatches.isEmpty)
        let text = String(decoding: try FlareFormat.encode(Fixtures.document()), as: UTF8.self)
        #expect(!text.contains("swatches"))
    }

    @Test func swatchesRoundTripByteStable() throws {
        let doc = Self.palette()
        let first = try FlareFormat.encode(doc)
        #expect(try FlareFormat.decode(first) == doc)
        #expect(try FlareFormat.encode(FlareFormat.decode(first)) == first)
    }

    @Test(arguments: [
        #"[{"name":"A","color":{"r":0,"g":0,"b":0,"a":1}},{"name":"A","color":{"r":1,"g":1,"b":1,"a":1}}]"#,
        #"[{"name":"A","color":{"r":0,"g":-0.1,"b":0,"a":1}}]"#,
        #"[{"name":"A","color":{"r":0,"g":0,"b":0,"a":2}}]"#,
        #"[{"name":"","color":{"r":0,"g":0,"b":0,"a":1}}]"#,
    ])
    func validateRejectsBadPalette(swatches: String) {
        let json = #"""
        {"format":"flare","version":1,
         "document":{"scenes":[],"swatches":\#(swatches)}}
        """#
        #expect {
            try FlareFormat.decode(Data(json.utf8))
        } throws: { error in
            guard case FormatError.invalid = error else { return false }
            return true
        }
    }

    /// One sample of each swatch command for CommandRegistryTests, valid on
    /// its sample document (which holds the swatch "Ink").
    static func registrySamples() -> [any Command] {
        [
            AddSwatch(name: "Sky", color: Color(r: 0.4, g: 0.7, b: 1)),
            RenameSwatch(name: "Ink", newName: "Night"),
            SetSwatchColor(name: "Ink", color: red),
            RemoveSwatch(name: "Ink"),
        ]
    }

    static func anyName(_ rng: inout SplitMix64) -> String { ["A", "B", "C", ""].randomElement(using: &rng) ?? "A" }

    static func anyColor(_ rng: inout SplitMix64) -> Color {
        Color(r: UndoPropertyTests.anyNumber(in: -0.2...1.2, &rng), g: 0.5, b: 0.5)
    }

    /// Random swatch steps, valid and invalid, for assertUndoRestoresDocument.
    static let undoSteps: [UndoStep] = [
        { e, rng, _ in try e.perform(AddSwatch(name: anyName(&rng), color: anyColor(&rng))) },
        { e, rng, _ in try e.perform(RenameSwatch(name: anyName(&rng), newName: anyName(&rng))) },
        { e, rng, _ in try e.perform(SetSwatchColor(name: anyName(&rng), color: anyColor(&rng))) },
        { e, rng, _ in try e.perform(RemoveSwatch(name: anyName(&rng))) },
    ]

    @Test(arguments: 0..<100)
    func undoAllRestoresOriginal(seed: UInt64) throws {
        try assertUndoRestoresDocument(seed: seed, steps: Self.undoSteps, start: Self.palette())
    }
}
