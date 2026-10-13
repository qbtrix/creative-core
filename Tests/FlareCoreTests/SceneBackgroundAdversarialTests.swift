// SceneBackgroundAdversarialTests.swift: tries to get a non-finite scene
// background past AddScene and load validation (#196) by other routes: JSON
// numbers that overflow to infinity, command envelopes, groups, direct
// execute, extreme finite values and a seeded fuzz.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@testable import FlareCore
import Testing

@Suite struct SceneBackgroundAdversarialTests {
    /// A saved document with scene 0's background red channel replaced by `literal`.
    static func file(red literal: String) throws -> Data {
        var doc = ShapeTextOwnerTests.start()
        doc.scenes[0].background = Color(r: 0.123456, g: 0, b: 0)
        let text = try #require(String(data: try FlareFormat.encode(doc), encoding: .utf8))
        #expect(text.contains("0.123456"))
        return Data(text.replacingOccurrences(of: "0.123456", with: literal).utf8)
    }

    @Test(arguments: ["1e999", "-1e999", "1e309"])
    func overflowingBackgroundInFileIsRejected(_ literal: String) throws {
        #expect(throws: (any Error).self) { try FlareFormat.decode(Self.file(red: literal)) }
    }

    @Test func extremeFiniteBackgroundRoundTrips() throws {
        let colors = [
            Color(r: .greatestFiniteMagnitude, g: -.greatestFiniteMagnitude, b: .leastNonzeroMagnitude, a: -0.0),
            Color(r: -1, g: 2, b: 1e300, a: .leastNormalMagnitude),
        ]
        for (i, color) in colors.enumerated() {
            var e = CommandEngine(document: ShapeTextOwnerTests.start())
            try e.perform(AddScene(scene: Scene(id: "x\(i)", name: "X", background: color)))
            let back = try FlareFormat.decode(FlareFormat.encode(e.document))
            #expect(back.scenes.last?.background == color)
            _ = try SVGExporter.export(scene: try #require(e.document.scenes.last), frame: 0)
        }
    }

    @Test func overflowingBackgroundInCommandEnvelopeNeverCommits() throws {
        let registry = CommandRegistry.builtIn
        let good = AddScene(scene: Scene(id: "s9", name: "S9", background: Color(r: 0.123456, g: 0, b: 0)))
        let text = try #require(String(data: try registry.encode(good), encoding: .utf8))
        let bad = Data(text.replacingOccurrences(of: "0.123456", with: "1e999").utf8)
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        let before = e.document
        // Either the envelope is refused, or the decoded command is.
        if let command = try? registry.decode(bad) {
            #expect(throws: (any Error).self) { try e.perform(command) }
        }
        #expect(e.document == before)
        #expect(e.undoStack.isEmpty)
        _ = try FlareFormat.encode(e.document)
    }

    @Test func nonFiniteBackgroundInGroupRollsBackEarlierSteps() throws {
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        let before = e.document
        #expect(throws: CommandError.invalidDocument("background color channels must be finite")) {
            try e.group("Two Scenes") { e in
                try e.perform(AddScene(scene: Scene(id: "ok", name: "OK")))
                try e.perform(AddScene(scene: Scene(id: "bad", name: "Bad", background: Color(r: .nan, g: 0, b: 0))))
            }
        }
        #expect(e.document == before)
        #expect(e.undoStack.isEmpty)
        _ = try FlareFormat.encode(e.document)
    }

    @Test func directExecuteRejectsSignalingNaN() throws {
        var doc = ShapeTextOwnerTests.start()
        let before = doc
        var add = AddScene(scene: Scene(id: "s9", name: "S9", background: Color(r: 0, g: 0, b: 0, a: .signalingNaN)))
        #expect(throws: CommandError.invalidDocument("background color channels must be finite")) {
            try add.execute(&doc)
        }
        #expect(doc == before)
    }

    @Test func duplicateIDIsReportedBeforeBackground() throws {
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        let id = Fixtures.sceneID
        #expect(throws: CommandError.duplicateID(id)) {
            try e.perform(AddScene(scene: Scene(id: id, name: "Dup", background: Color(r: .nan, g: 0, b: 0))))
        }
    }

    @Test func fuzzAddSceneCommitsOnlyFiniteBackgroundsAndAlwaysSaves() throws {
        var rng = SplitMix64(seed: 196)
        let specials: [Double] = [.nan, .infinity, -.infinity, .greatestFiniteMagnitude, -0.0, .leastNonzeroMagnitude, 0.5, 2]
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        for i in 0..<300 {
            func channel() -> Double {
                Int.random(in: 0..<3, using: &rng) == 0
                    ? specials[Int.random(in: 0..<specials.count, using: &rng)]
                    : Double.random(in: -2...2, using: &rng)
            }
            let color = Color(r: channel(), g: channel(), b: channel(), a: channel())
            let before = e.document
            let depth = e.undoStack.count
            do {
                try e.perform(AddScene(scene: Scene(id: "f\(i)", name: "F", background: color)))
                #expect(color.isFinite)
                #expect(e.undoStack.count == depth + 1)
            } catch {
                #expect(!color.isFinite)
                #expect(e.document == before)
                #expect(e.undoStack.count == depth)
            }
            _ = try FlareFormat.encode(e.document)
        }
        while e.canUndo { try e.undo() }
        #expect(e.document == ShapeTextOwnerTests.start())
    }
}
