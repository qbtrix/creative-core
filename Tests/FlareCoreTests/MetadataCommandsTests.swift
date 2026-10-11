// MetadataCommandsTests.swift: Document.metadata and SetMetadata. Old files
// decode with empty metadata, the encoding round-trips byte for byte, and
// undo restores the previous metadata exactly.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import FlareCore
import Testing

@Suite struct MetadataCommandsTests {
    static let full = Metadata(title: "Bounce", author: "Ada", generator: "Flare 1.0")

    @Test func oldFileDecodesWithEmptyMetadata() throws {
        let v1 = """
        {"format":"flare","version":1,"document":{"scenes":[{"id":"s","name":"S","fps":24,"durationFrames":10,"layers":[]}]}}
        """
        let doc = try FlareFormat.decode(Data(v1.utf8))
        #expect(doc.metadata == Metadata())
        #expect(doc.metadata.isEmpty)
    }

    @Test func emptyMetadataIsNotEncoded() throws {
        let text = String(decoding: try FlareFormat.encode(Fixtures.document()), as: UTF8.self)
        #expect(!text.contains("metadata"))
    }

    @Test(arguments: [full, Metadata(title: "Only title"), Metadata(author: "A", generator: "g")])
    func roundTripIsByteStable(metadata: Metadata) throws {
        var doc = Fixtures.document()
        doc.metadata = metadata
        let first = try FlareFormat.encode(doc)
        let decoded = try FlareFormat.decode(first)
        #expect(decoded == doc)
        #expect(try FlareFormat.encode(decoded) == first)
    }

    @Test func setMetadataUndoAndRedo() throws {
        let start = Fixtures.document()
        var engine = CommandEngine(document: start)
        try engine.perform(SetMetadata(metadata: Self.full))
        #expect(engine.document.metadata == Self.full)
        try engine.perform(SetMetadata(metadata: Metadata(title: "Renamed")))
        #expect(engine.document.metadata == Metadata(title: "Renamed"))
        try engine.undo()
        #expect(engine.document.metadata == Self.full)
        try engine.undo()
        #expect(engine.document == start)
        try engine.redo()
        #expect(engine.document.metadata == Self.full)
    }

    @Test func undoBeforeExecuteThrows() {
        var doc = Fixtures.document()
        #expect(throws: CommandError.notExecuted) { try SetMetadata(metadata: Self.full).undo(&doc) }
    }

    /// One sample of each metadata command, for CommandRegistryTests.
    static func registrySamples() -> [any Command] {
        [SetMetadata(metadata: full)]
    }

    static func randomField(_ rng: inout SplitMix64) -> String? {
        Bool.random(using: &rng) ? nil : "v\(Int.random(in: 0..<5, using: &rng))"
    }

    /// Random metadata steps for assertUndoRestoresDocument.
    static let undoSteps: [UndoStep] = [
        { e, rng, _ in
            let metadata = Metadata(title: randomField(&rng), author: randomField(&rng),
                                    generator: randomField(&rng))
            try e.perform(SetMetadata(metadata: metadata))
        },
    ]

    @Test(arguments: 0..<100)
    func undoAllRestoresOriginal(seed: UInt64) throws {
        var start = Fixtures.document()
        start.metadata = Metadata(title: "Start")
        try assertUndoRestoresDocument(seed: seed, steps: Self.undoSteps, start: start)
    }
}
