// TextStyleCommandsTests.swift: the text style family's registry ids, registry samples and
// undo steps. A new text style command adds its id to `expectedIDs`, one sample to
// `registrySamples()` and its random steps to `undoSteps` here;
// CommandRegistryTests and UndoPropertyTests read all three, so neither shared
// test file changes. The paragraph and path cases are in TextParagraphCommandsTests.
@testable import FlareCore
import Testing

@Suite struct TextStyleCommandsTests {
    /// Every id in `TextStyleCommands.all`, in order, written out by hand.
    static let expectedIDs: [String] = [
        "text.applyStyle", "text.clearStyle", "text.editString", "text.setParagraph", "text.setOnPath",
    ]

    /// The ids whose commands are still stubs that throw "not built"; each
    /// leaves this set when its task builds it and adds a registry sample.
    static let notBuiltIDs: Set<String> = []

    /// One sample of every built text style command (not in `notBuiltIDs`), each valid on
    /// `CommandRegistryTests.sampleDocument()` (text "Hello" on the ball layer, "H" bold), in `expectedIDs` order.
    static func registrySamples() -> [any Command] {
        [ApplyTextStyle(owner: o, layerID: "ball", textIndex: 0, range: 1..<4, style: TextRunStyle(weight: 700, italic: true)),
         ClearTextStyle(owner: o, layerID: "ball", textIndex: 0, range: 0..<5),
         EditTextString(owner: o, layerID: "ball", textIndex: 0, replacing: 1..<3, with: "é👍🏽"),
         SetParagraphStyle(owner: o, layerID: "ball", textIndex: 0, paragraph: ParagraphStyle(alignment: .center, boxWidth: 120)),
         SetTextOnPath(owner: o, layerID: "ball", textIndex: 0,
                       onPath: TextOnPath(path: Path(polyline: [Point(x: 0, y: 0), Point(x: 100, y: 0)], closed: false)))]
    }

    /// Makes "H" of the registry sample document's scene text bold, so the clear
    /// sample has a style to remove (and "Hi", from the set-string sample, still holds it).
    static func addSampleRuns(_ doc: inout Document) {
        doc.scenes[0].layers[1].texts[0].runs = [bold(0, 1)]
    }

    /// A text index and a grapheme range on `layer`, sometimes out of bounds.
    static func anyRange(_ e: CommandEngine, _ layer: String, _ rng: inout SplitMix64) -> (Int, Range<Int>) {
        let index = TextCommandsTests.anyIndex(e, layer, &rng)
        let a = Int.random(in: -1...8, using: &rng), b = Int.random(in: -1...8, using: &rng)
        return (index, min(a, b)..<max(a, b))
    }

    /// Random text style steps, valid and invalid, for assertUndoRestoresDocument.
    static let undoSteps: [UndoStep] = [
        { e, rng, _ in
            let layer = UndoPropertyTests.anyLayer(e, &rng)
            let (index, range) = anyRange(e, layer, &rng)
            let style = TextRunStyle(fontSize: UndoPropertyTests.anyNumber(in: -1...48, &rng),
                                     weight: [nil, 400, 700, 1000].randomElement(using: &rng) ?? nil)
            try e.perform(ApplyTextStyle(owner: o, layerID: layer, textIndex: index, range: range, style: style))
        },
        { e, rng, _ in
            let layer = UndoPropertyTests.anyLayer(e, &rng)
            let (index, range) = anyRange(e, layer, &rng)
            try e.perform(ClearTextStyle(owner: o, layerID: layer, textIndex: index, range: range))
        },
        { e, rng, _ in
            let layer = UndoPropertyTests.anyLayer(e, &rng)
            let (index, range) = anyRange(e, layer, &rng)
            let with = ["", "x", "é👍🏽", "\u{301}"].randomElement(using: &rng) ?? ""
            try e.perform(EditTextString(owner: o, layerID: layer, textIndex: index, replacing: range, with: with))
        },
    ]

    @Test(arguments: 0..<100 as Range<UInt64>)
    func undoAllRestoresOriginal(seed: UInt64) throws {
        try assertUndoRestoresDocument(seed: seed, steps: TextCommandsTests.undoSteps + Self.undoSteps,
                                       start: TextFixtures.document(Self.boldMid))
    }

    /// A combining mark inserted after a letter would fuse two graphemes, so it
    /// is refused with a message naming the command, the mark, the grapheme
    /// offset of the edit and the grapheme it would join, even from `execute`.
    @Test func fusingInsertRefused() {
        let start = TextFixtures.document(TextFixtures.text("e"))
        var engine = CommandEngine(document: start)
        var message = ""
        do { try engine.perform(Self.edit(1..<1, "\u{301}")) } catch CommandError.invalidDocument(let text) { message = text } catch {}
        #expect(message.hasPrefix("Edit Text:") && message.contains("U+301") && message.contains("grapheme 1"))
        #expect(message.contains("before: \"e\""))
        #expect(engine.document == start && !engine.canUndo)
        var direct = Self.edit(1..<1, "\u{301}"), doc = start
        message = ""
        do { try direct.execute(&doc) } catch CommandError.invalidDocument(let text) { message = text } catch {}
        #expect(message.hasPrefix("Edit Text:") && doc == start)
        #expect(direct.replacement == "\u{301}")
    }

    /// Runs whose end overflows Int, or that lie outside the string, are refused
    /// with a CommandError before any arithmetic on them, leaving the document unchanged.
    @Test func malformedRunsThrow() {
        for runs in [[TextRun(start: Int.max, length: 1)], [TextRun(start: 1, length: Int.max)]] {
            let start = TextFixtures.document(TextFixtures.text("abc", runs: runs))
            for command in [Self.apply(0..<1), Self.clear(0..<1), Self.edit(0..<1, "x")] as [any Command] {
                var engine = CommandEngine(document: start)
                #expect(throws: CommandError.self) { try engine.perform(command) }
                #expect(engine.document == start && !engine.canUndo)
            }
        }
    }

    /// Seeded random runs, many with extreme starts and lengths, never crash a
    /// run command: it throws a CommandError and leaves the document, or succeeds with valid runs.
    @Test(arguments: 0..<50 as Range<UInt64>) func malformedRunsFuzz(seed: UInt64) throws {
        var rng = SplitMix64(seed: seed)
        let values = [Int.min, -1, 0, 1, 2, 3, 4, Int.max - 1, Int.max]
        for _ in 0..<10 {
            let runs = (0..<Int.random(in: 1...3, using: &rng)).map { _ in
                TextRun(start: values.randomElement(using: &rng) ?? 0, length: values.randomElement(using: &rng) ?? 0, weight: 700)
            }
            let start = TextFixtures.document(TextFixtures.text("abc", runs: runs))
            var engine = CommandEngine(document: start)
            let range = 0..<Int.random(in: 0...3, using: &rng)
            let command: any Command = [Self.apply(range), Self.clear(range), Self.edit(range, "xy")]
                .randomElement(using: &rng) ?? Self.clear(range)
            do { try engine.perform(command) } catch is CommandError { #expect(engine.document == start) }
            let text = try #require(TextFixtures.ballText(engine.document))
            #expect(engine.document == start
                    || text.runs.allSatisfy { $0.start >= 0 && $0.length > 0 && $0.start <= text.string.count - $0.length })
        }
    }

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

    @Test func boldInTheMiddleGivesThreeRuns() throws {
        let text = try Self.run([Self.apply(6..<11)])
        #expect(text?.runs == [Self.bold(6, 5)] && text?.resolvedRuns.map(\.weight) == [400, 700, 400])
    }
    @Test func equalNeighboursMerge() throws {
        #expect(try Self.run([Self.apply(6..<11), Self.apply(6..<8)])?.runs == [Self.bold(6, 5)])
        #expect(try Self.run([Self.apply(0..<3), Self.apply(3..<6)])?.runs == [Self.bold(0, 6)])
        #expect(try Self.run([Self.apply(6..<11), Self.apply(8..<9, TextRunStyle(italic: true))])?.runs == [
            Self.bold(6, 2), TextRun(start: 8, length: 1, weight: 700, italic: true), Self.bold(9, 2),
        ])
    }
    @Test func boldAllThenClearLeavesNoRuns() throws {
        #expect(try Self.run([Self.apply(0..<15), Self.clear(0..<15)])?.runs == [])
        #expect(try Self.run([Self.apply(0..<15, TextRunStyle(fontSize: 24))])?.runs == [])
        #expect(try Self.run([Self.apply(0..<15, TextRunStyle(fontFamily: "Inter", italic: false, fill: .solid(.black),
                                                              tracking: 0, baselineShift: 0))])?.runs == [])
    }
    @Test func editKeepsRunsOnTheirGraphemes() throws {
        #expect(try Self.run([Self.edit(0..<5, "Take")], on: Self.boldMid)?.runs == [Self.bold(5, 5)])
        #expect(try Self.run([Self.edit(7..<9, "IGH")], on: Self.boldMid)?.runs == [Self.bold(6, 6)])
        let across = try Self.run([Self.edit(9..<13, "")], on: Self.boldMid)
        #expect(across?.string == "Bring theht" && across?.runs == [Self.bold(6, 3)])
        #expect(try Self.run([Self.edit(6..<6, "warm ")], on: Self.boldMid)?.runs == [Self.bold(11, 5)])
    }
    /// Text inserted at a run's end takes the style before it, so the run grows.
    @Test func runAtEditPointGrows() throws {
        let grown = try Self.run([Self.edit(11..<11, "s")], on: Self.boldMid)
        #expect(grown?.string == "Bring the lsight" && grown?.runs == [Self.bold(6, 6)])
    }
    @Test func emojiAndCombiningMarksAreOneStep() throws {
        #expect(try Self.run([Self.apply(1..<2)], on: TextFixtures.text(TextFixtures.emoji))?.runs == [Self.bold(1, 1)])
        let marks = try Self.run([Self.edit(1..<2, "o")], on: TextFixtures.text(TextFixtures.combining))
        #expect(marks?.string == "e\u{301}on\u{303}" && marks?.string.count == 3)
    }
    @Test func rangePastEndRefused() throws {
        #expect(try Self.run([Self.apply(10..<15)])?.runs == [Self.bold(10, 5)])
        for command in [Self.apply(10..<16), Self.apply(-1..<2), Self.clear(14..<16), Self.edit(15..<16, "x")] as [any Command] {
            var engine = CommandEngine(document: TextFixtures.document())
            #expect(throws: CommandError.self) { try engine.perform(command) }
            #expect(engine.document == TextFixtures.document() && !engine.canUndo)
        }
    }
    /// A range past the string throws `invalidIndex` carrying the offending grapheme offset.
    @Test func rangePastEndNamesOffset() {
        let start = TextFixtures.document(TextFixtures.text("Bring"))
        var engine = CommandEngine(document: start)
        #expect(throws: CommandError.invalidIndex(9)) { try engine.perform(Self.apply(3..<9)) }
        #expect(throws: CommandError.invalidIndex(-1)) { try engine.perform(Self.apply(-1..<2)) }
        #expect(engine.document == start && !engine.canUndo)
    }
    /// Setting a field back to regular removes it: weight 400 over a bold range leaves no runs.
    @Test func unboldBySettingRegular() throws {
        #expect(try Self.run([Self.apply(6..<11), Self.apply(6..<11, TextRunStyle(weight: 400))])?.runs == [])
    }
    @Test func lockedLayerRefused() {
        var locked = TextFixtures.document()
        locked.scenes[0].layers[1].isLocked = true
        for command in [Self.apply(0..<1), Self.clear(0..<1), Self.edit(0..<1, "x")] as [any Command] {
            var engine = CommandEngine(document: locked)
            #expect(throws: CommandError.layerLocked("ball")) { try engine.perform(command) }
            #expect(engine.document == locked)
        }
    }
    /// A random style over a few values of every field, the shape's own and neutral ones included.
    static func anyStyle(_ rng: inout SplitMix64) -> TextRunStyle {
        func pick<T>(_ values: [T]) -> T? { Bool.random(using: &rng) ? values.randomElement(using: &rng) : nil }
        return TextRunStyle(fontFamily: pick(["Inter", "Serif"]), fontSize: pick([24, 30]), weight: pick([400, 700]),
                            italic: pick([false, true]), fill: pick([.solid(.black), .solid(.white)]),
                            tracking: pick([0, 2]), baselineShift: pick([0, -3]))
    }

    /// Seeded random styles, clears and edits either throw a CommandError or
    /// leave runs inside the string, sorted, never overlapping, with touching
    /// equal neighbours merged and no plain runs.
    @Test(arguments: 0..<50 as Range<UInt64>) func fuzz(seed: UInt64) throws {
        var rng = SplitMix64(seed: seed)
        var engine = CommandEngine(document: TextFixtures.document(Self.boldMid))
        for _ in 0..<20 {
            let a = Int.random(in: -2...18, using: &rng), b = Int.random(in: -2...18, using: &rng)
            let range = min(a, b)..<max(a, b)
            let command: any Command = switch Int.random(in: 0..<3, using: &rng) {
            case 0: Self.apply(range, Self.anyStyle(&rng))
            case 1: Self.clear(range)
            default: Self.edit(range, "é👍🏽")
            }
            do { try engine.perform(command) } catch is CommandError {}
            let text = try #require(TextFixtures.ballText(engine.document))
            #expect(text.runs.allSatisfy { $0.start >= 0 && $0.length > 0 && $0.start + $0.length <= text.string.count })
            #expect(zip(text.runs, text.runs.dropFirst()).allSatisfy {
                $0.start + $0.length <= $1.start && !($0.start + $0.length == $1.start && $0.over(0, 0) == $1.over(0, 0))
            })
            #expect(text.runs.allSatisfy { $0.over(0, 0) != .plain })
        }
    }
}
