// GuideCommandsTests.swift: AddGuide, MoveGuide and RemoveGuide. Guides keep
// their order and undo restores it exactly; non-finite positions and bad
// indices throw and leave the document unchanged; old files decode with no
// guides; validate rejects non-finite guides in a file.
import FlareCore
import Foundation
import Testing

@Suite struct GuideCommandsTests {
    /// The fixture with a vertical guide at x = 100 and a horizontal one at y = 50.
    static func guided() -> Document {
        var doc = Fixtures.document()
        doc.scenes[0].guides = [Guide(axis: .vertical, position: 100), Guide(axis: .horizontal, position: 50)]
        return doc
    }

    @Test func addGuideAppendsAndUndoes() throws {
        try SceneCommandTests.roundTrip(AddGuide(sceneID: Fixtures.sceneID, axis: .horizontal, position: -12.5),
                                        on: Self.guided()) {
            #expect($0.scenes.first?.guides == [Guide(axis: .vertical, position: 100),
                                                Guide(axis: .horizontal, position: 50),
                                                Guide(axis: .horizontal, position: -12.5)])
        }
    }

    @Test func moveGuideKeepsAxisAndUndoes() throws {
        try SceneCommandTests.roundTrip(MoveGuide(sceneID: Fixtures.sceneID, index: 0, position: 320),
                                        on: Self.guided()) {
            #expect($0.scenes.first?.guides == [Guide(axis: .vertical, position: 320),
                                                Guide(axis: .horizontal, position: 50)])
        }
    }

    @Test func removeGuideUndoesAtTheSameIndex() throws {
        try SceneCommandTests.roundTrip(RemoveGuide(sceneID: Fixtures.sceneID, index: 0), on: Self.guided()) {
            #expect($0.scenes.first?.guides == [Guide(axis: .horizontal, position: 50)])
        }
    }

    @Test func addMoveRemoveThenEachUndoRestoresTheScene() throws {
        let start = Fixtures.document()
        var engine = CommandEngine(document: start)
        var states = [engine.document]
        try engine.perform(AddGuide(sceneID: Fixtures.sceneID, axis: .horizontal, position: 40))
        states.append(engine.document)
        try engine.perform(AddGuide(sceneID: Fixtures.sceneID, axis: .vertical, position: 200))
        states.append(engine.document)
        try engine.perform(MoveGuide(sceneID: Fixtures.sceneID, index: 0, position: 60))
        states.append(engine.document)
        try engine.perform(RemoveGuide(sceneID: Fixtures.sceneID, index: 1))
        #expect(engine.document.scenes.first?.guides == [Guide(axis: .horizontal, position: 60)])
        for expected in states.reversed() {
            try engine.undo()
            #expect(engine.document == expected)
        }
        #expect(engine.document == start)
    }

    @Test func invalidParamsThrowWithoutChanges() {
        let start = Self.guided()
        for bad in [Double.nan, .infinity, -.infinity] {
            SceneCommandTests.rejects(AddGuide(sceneID: Fixtures.sceneID, axis: .vertical, position: bad), on: start,
                                      .invalidGuidePosition)
            SceneCommandTests.rejects(MoveGuide(sceneID: Fixtures.sceneID, index: 0, position: bad), on: start,
                                      .invalidGuidePosition)
        }
        SceneCommandTests.rejects(MoveGuide(sceneID: Fixtures.sceneID, index: 2, position: 1), on: start,
                                  .invalidIndex(2))
        SceneCommandTests.rejects(RemoveGuide(sceneID: Fixtures.sceneID, index: -1), on: start, .invalidIndex(-1))
        SceneCommandTests.rejects(AddGuide(sceneID: "missing", axis: .vertical, position: 1), on: start,
                                  .sceneNotFound("missing"))
    }

    @Test func oldFileDecodesWithNoGuides() throws {
        let json = #"""
        {"format":"flare","version":1,
         "document":{"scenes":[{"id":"s","name":"S","fps":24,"durationFrames":10,"layers":[]}]}}
        """#
        let doc = try FlareFormat.decode(Data(json.utf8))
        #expect(doc.scenes.first?.guides == [])
        let encoded = try FlareFormat.encode(doc)
        #expect(try FlareFormat.encode(FlareFormat.decode(encoded)) == encoded)
    }

    @Test func guidesRoundTripByteStable() throws {
        let doc = Self.guided()
        let first = try FlareFormat.encode(doc)
        #expect(try FlareFormat.decode(first) == doc)
        #expect(try FlareFormat.encode(FlareFormat.decode(first)) == first)
    }

    @Test func validateRejectsNonFiniteGuide() {
        var doc = Self.guided()
        doc.scenes[0].guides[1].position = .infinity
        #expect {
            try FlareFormat.validate(doc)
        } throws: { error in
            guard case FormatError.invalid = error else { return false }
            return true
        }
    }

    /// One sample of each guide command for CommandRegistryTests, valid on its sample document.
    static func registrySamples() -> [any Command] {
        [
            AddGuide(sceneID: Fixtures.sceneID, axis: .vertical, position: 10),
            MoveGuide(sceneID: Fixtures.sceneID, index: 1, position: 75),
            RemoveGuide(sceneID: Fixtures.sceneID, index: 0),
        ]
    }

    /// Random guide steps, valid and invalid, for assertUndoRestoresDocument.
    static let undoSteps: [UndoStep] = [
        { e, rng, _ in
            let axis: Guide.Axis = Bool.random(using: &rng) ? .horizontal : .vertical
            try e.perform(AddGuide(sceneID: Fixtures.sceneID, axis: axis,
                                   position: UndoPropertyTests.anyNumber(in: -500...500, &rng)))
        },
        { e, rng, _ in
            try e.perform(MoveGuide(sceneID: Fixtures.sceneID, index: Int.random(in: -1...4, using: &rng),
                                    position: UndoPropertyTests.anyNumber(in: -500...500, &rng)),
                          coalesceKey: Bool.random(using: &rng) ? "drag" : nil)
        },
        { e, rng, _ in
            // A drag: 2-4 coalesced MoveGuide steps on one guide, so MoveGuide.merge
            // runs. A rejected step partway leaves the run as it was.
            let count = e.document.scenes.first { $0.id == Fixtures.sceneID }?.guides.count ?? 0
            let index = Int.random(in: -1...count, using: &rng)
            func drag(_ e: inout CommandEngine, _ rng: inout SplitMix64) throws {
                try e.perform(MoveGuide(sceneID: Fixtures.sceneID, index: index,
                                        position: UndoPropertyTests.anyNumber(in: -500...500, &rng)),
                              coalesceKey: "drag")
            }
            try drag(&e, &rng)
            for _ in 1..<Int.random(in: 2...4, using: &rng) { try? drag(&e, &rng) }
        },
        { e, rng, _ in
            try e.perform(RemoveGuide(sceneID: Fixtures.sceneID, index: Int.random(in: -1...4, using: &rng)))
        },
    ]

    @Test(arguments: 0..<200)
    func undoAllRestoresOriginal(seed: UInt64) throws {
        try assertUndoRestoresDocument(seed: seed, steps: UndoPropertyTests.coreSteps + Self.undoSteps,
                                       start: Self.guided())
    }
}
