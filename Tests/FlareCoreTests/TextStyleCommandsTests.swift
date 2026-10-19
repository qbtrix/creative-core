// TextStyleCommandsTests.swift: the text style family's registry ids, registry samples and
// undo steps. A new text style command adds its id to `expectedIDs`, one sample to
// `registrySamples()` and its random steps to `undoSteps` here;
// CommandRegistryTests and UndoPropertyTests read all three, so neither shared
// test file changes. The acceptance cases below wait, disabled by name, on the
// task that builds their command (TE-3 runs and string, TE-4 paragraph and path).
@testable import FlareCore
import Testing

@Suite struct TextStyleCommandsTests {
    /// Every id in `TextStyleCommands.all`, in order, written out by hand.
    static let expectedIDs: [String] = [
        "text.applyStyle", "text.clearStyle", "text.editString", "text.setParagraph", "text.setOnPath",
    ]

    /// The ids whose commands are still stubs that throw "not built"; each
    /// leaves this set when its task builds it and adds a registry sample.
    static let notBuiltIDs: Set<String> = Set(expectedIDs)

    /// One sample of every built text style command (not in `notBuiltIDs`), each valid on
    /// `CommandRegistryTests.sampleDocument()`, in `expectedIDs` order.
    static func registrySamples() -> [any Command] { [] }

    /// Random text style steps, valid and invalid, for assertUndoRestoresDocument.
    static let undoSteps: [UndoStep] = []

    @Test func familyListsExactlyItsIDs() {
        #expect(TextStyleCommands.all.map { $0.id } == Self.expectedIDs)
    }

    @Test func samplesListExactlyItsIDs() {
        #expect(Self.registrySamples().map { type(of: $0).id } == Self.expectedIDs.filter { !Self.notBuiltIDs.contains($0) })
    }

    static let o = LayerOwner.scene(Fixtures.sceneID)

    /// Performs `commands` on `start`, checks that undoing each restores `start`, and returns the text they left.
    static func run(_ commands: [any Command], on start: TextShape = TextFixtures.text()) throws -> TextShape? {
        var engine = CommandEngine(document: TextFixtures.document(start))
        for command in commands { try engine.perform(command) }
        let after = TextFixtures.ballText(engine.document)
        for _ in commands { try engine.undo() }
        #expect(engine.document == TextFixtures.document(start) && !engine.canUndo)
        return after
    }

    static func apply(_ range: Range<Int>, _ style: TextRunStyle = TextRunStyle(weight: 700)) -> ApplyTextStyle {
        ApplyTextStyle(owner: o, layerID: "ball", textIndex: 0, range: range, style: style)
    }
    static func clear(_ range: Range<Int>) -> ClearTextStyle { ClearTextStyle(owner: o, layerID: "ball", textIndex: 0, range: range) }
    static func edit(_ range: Range<Int>, _ with: String) -> EditTextString {
        EditTextString(owner: o, layerID: "ball", textIndex: 0, replacing: range, with: with)
    }
    static func bold(_ start: Int, _ length: Int) -> TextRun { TextRun(start: start, length: length, weight: 700) }

    /// "Bring the light" with graphemes 6..<11 ("the l") bold.
    static let boldMid = TextFixtures.text(runs: [bold(6, 5)])

    @Test(.disabled("waits on TE-3")) func boldInTheMiddleGivesThreeRuns() throws {
        let text = try Self.run([Self.apply(6..<11)])
        #expect(text?.runs == [Self.bold(6, 5)] && text?.resolvedRuns.map(\.weight) == [400, 700, 400])
    }
    @Test(.disabled("waits on TE-3")) func equalNeighboursMerge() throws {
        #expect(try Self.run([Self.apply(6..<11), Self.apply(6..<8)])?.runs == [Self.bold(6, 5)])
        #expect(try Self.run([Self.apply(0..<3), Self.apply(3..<6)])?.runs == [Self.bold(0, 6)])
        #expect(try Self.run([Self.apply(6..<11), Self.apply(8..<9, TextRunStyle(italic: true))])?.runs == [
            Self.bold(6, 2), TextRun(start: 8, length: 1, weight: 700, italic: true), Self.bold(9, 2),
        ])
    }
    @Test(.disabled("waits on TE-3")) func boldAllThenClearLeavesNoRuns() throws {
        #expect(try Self.run([Self.apply(0..<15), Self.clear(0..<15)])?.runs == [])
        #expect(try Self.run([Self.apply(0..<15, TextRunStyle(fontSize: 24))])?.runs == [])
    }
    @Test(.disabled("waits on TE-3")) func editKeepsRunsOnTheirGraphemes() throws {
        #expect(try Self.run([Self.edit(0..<5, "Take")], on: Self.boldMid)?.runs == [Self.bold(5, 5)])
        #expect(try Self.run([Self.edit(7..<9, "IGH")], on: Self.boldMid)?.runs == [Self.bold(6, 6)])
        let across = try Self.run([Self.edit(9..<13, "")], on: Self.boldMid)
        #expect(across?.string == "Bring theht" && across?.runs == [Self.bold(6, 3)])
        #expect(try Self.run([Self.edit(6..<6, "warm ")], on: Self.boldMid)?.runs == [Self.bold(11, 5)])
    }
    /// Text inserted at a run's end takes the style before it, so the run grows.
    @Test(.disabled("waits on TE-3")) func runAtEditPointGrows() throws {
        let grown = try Self.run([Self.edit(11..<11, "s")], on: Self.boldMid)
        #expect(grown?.string == "Bring the lsight" && grown?.runs == [Self.bold(6, 6)])
    }
    @Test(.disabled("waits on TE-3")) func emojiAndCombiningMarksAreOneStep() throws {
        #expect(try Self.run([Self.apply(1..<2)], on: TextFixtures.text(TextFixtures.emoji))?.runs == [Self.bold(1, 1)])
        let marks = try Self.run([Self.edit(1..<2, "o")], on: TextFixtures.text(TextFixtures.combining))
        #expect(marks?.string == "e\u{301}on\u{303}" && marks?.string.count == 3)
    }
    @Test(.disabled("waits on TE-3")) func rangePastEndRefused() throws {
        #expect(try Self.run([Self.apply(10..<15)])?.runs == [Self.bold(10, 5)])
        for command in [Self.apply(10..<16), Self.clear(14..<16), Self.edit(15..<16, "x")] as [any Command] {
            var engine = CommandEngine(document: TextFixtures.document())
            #expect(throws: CommandError.self) { try engine.perform(command) }
            #expect(engine.document == TextFixtures.document() && !engine.canUndo)
        }
    }
    @Test(.disabled("waits on TE-3")) func lockedLayerRefused() {
        var locked = TextFixtures.document()
        locked.scenes[0].layers[1].isLocked = true
        for command in [Self.apply(0..<1), Self.clear(0..<1), Self.edit(0..<1, "x")] as [any Command] {
            var engine = CommandEngine(document: locked)
            #expect(throws: CommandError.layerLocked("ball")) { try engine.perform(command) }
            #expect(engine.document == locked)
        }
    }
    /// Seeded random styles and edits either throw a CommandError or leave runs inside the string.
    @Test(.disabled("waits on TE-3"), arguments: 0..<50 as Range<UInt64>) func fuzz(seed: UInt64) throws {
        var rng = SplitMix64(seed: seed)
        var engine = CommandEngine(document: TextFixtures.document(Self.boldMid))
        for _ in 0..<20 {
            let a = Int.random(in: -2...18, using: &rng), b = Int.random(in: -2...18, using: &rng)
            let range = min(a, b)..<max(a, b)
            let command: any Command = Bool.random(using: &rng) ? Self.apply(range) : Self.edit(range, "é👍🏽")
            do { try engine.perform(command) } catch is CommandError {}
            let text = try #require(TextFixtures.ballText(engine.document))
            #expect(text.runs.allSatisfy { $0.start >= 0 && $0.length > 0 && $0.start + $0.length <= text.string.count })
        }
    }
}

/// TE-4's paragraph and type-on-a-path command checks; TE-4 turns them on.
@Suite struct TextParagraphCommandChecks {
    static func paragraph(_ value: ParagraphStyle?) -> SetParagraphStyle {
        SetParagraphStyle(owner: TextStyleCommandsTests.o, layerID: "ball", textIndex: 0, paragraph: value)
    }
    static func onPath(_ value: TextOnPath?) -> SetTextOnPath {
        SetTextOnPath(owner: TextStyleCommandsTests.o, layerID: "ball", textIndex: 0, onPath: value)
    }
    @Test(.disabled("waits on TE-4")) func setChangeAndClearUndoExactly() throws {
        let circle = TextOnPath(path: try PathBuilders.ellipse(in: Rect(minX: 0, minY: 0, maxX: 100, maxY: 100)), startOffset: 0.25)
        let steps: [any Command] = [Self.paragraph(ParagraphStyle(boxWidth: 120)),
                                    Self.paragraph(ParagraphStyle(alignment: .justified, boxWidth: 120)), Self.onPath(circle)]
        let set = try TextStyleCommandsTests.run(steps)
        #expect(set?.paragraph == ParagraphStyle(alignment: .justified, boxWidth: 120) && set?.onPath == circle)
        let cleared = try TextStyleCommandsTests.run(steps + [Self.paragraph(nil), Self.onPath(nil)])
        #expect(cleared?.paragraph == nil && cleared?.onPath == nil)
    }
    /// A drag of `lineHeight` folds into one command; a different field starts another.
    @Test(.disabled("waits on TE-4")) func mergeOnlySameField() throws {
        var engine = CommandEngine(document: TextFixtures.document())
        for height in [1.3, 1.4, 1.5] {
            try engine.perform(Self.paragraph(ParagraphStyle(lineHeight: height)), coalesceKey: "drag")
        }
        #expect(engine.undoStack.count == 1 && engine.undoStack.last?.commands.count == 1)
        try engine.perform(Self.paragraph(ParagraphStyle(lineHeight: 1.5, tracking: 2)), coalesceKey: "drag")
        #expect(engine.undoStack.last?.commands.count == 2)
        try engine.undo()
        #expect(engine.document == TextFixtures.document() && !engine.canUndo)
    }
    @Test(.disabled("waits on TE-4")) func lineHeightFiveRefused() {
        var engine = CommandEngine(document: TextFixtures.document())
        #expect(throws: CommandError.self) { try engine.perform(Self.paragraph(ParagraphStyle(lineHeight: 5))) }
        #expect(engine.document == TextFixtures.document() && !engine.canUndo)
    }
}
