// TextParagraphCommandsTests.swift: SetParagraphStyle and SetTextOnPath. Set,
// change and clear undo exactly; a drag of one paragraph field merges into one
// step and a different field starts another; bad values, a bad index and a
// locked layer are refused with the document unchanged. `undoSteps` feeds
// UndoPropertyTests, some of them coalesced like a drag.
@testable import FlareCore
import Testing

@Suite struct TextParagraphCommandsTests {
    static let o = TextStyleCommandsTests.o
    static func paragraph(_ value: ParagraphStyle?, index: Int = 0) -> SetParagraphStyle {
        SetParagraphStyle(owner: o, layerID: "ball", textIndex: index, paragraph: value)
    }
    static func onPath(_ value: TextOnPath?) -> SetTextOnPath {
        SetTextOnPath(owner: o, layerID: "ball", textIndex: 0, onPath: value)
    }
    static let line = Path(polyline: [Point(x: 0, y: 0), Point(x: 100, y: 0)], closed: false)

    @Test func setChangeAndClearUndoExactly() throws {
        let circle = TextOnPath(path: try PathBuilders.ellipse(in: Rect(minX: 0, minY: 0, maxX: 100, maxY: 100)), startOffset: 0.25)
        let steps: [any Command] = [Self.paragraph(ParagraphStyle(boxWidth: 120)),
                                    Self.paragraph(ParagraphStyle(alignment: .justified, boxWidth: 120)), Self.onPath(circle)]
        let set = try TextStyleCommandsTests.run(steps)
        #expect(set?.paragraph == ParagraphStyle(alignment: .justified, boxWidth: 120) && set?.onPath == circle)
        let cleared = try TextStyleCommandsTests.run(steps + [Self.paragraph(nil), Self.onPath(nil)])
        #expect(cleared?.paragraph == nil && cleared?.onPath == nil)
    }

    /// A drag of `lineHeight` folds into one command; a different field starts another.
    @Test func mergeOnlySameField() throws {
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

    /// The merged command redoes to the drag's last value, and a drag on another text does not merge.
    @Test func dragRedoesToLastValue() throws {
        var two = TextFixtures.document()
        two.scenes[0].layers[1].texts.append(TextFixtures.text("second"))
        var engine = CommandEngine(document: two)
        for height in [1.3, 1.4, 1.5] {
            try engine.perform(Self.paragraph(ParagraphStyle(lineHeight: height)), coalesceKey: "drag")
        }
        let dragged = engine.document
        try engine.undo()
        try engine.redo()
        #expect(engine.document == dragged && engine.document.scenes[0].layers[1].texts[0].paragraph?.lineHeight == 1.5)
        try engine.perform(Self.paragraph(ParagraphStyle(lineHeight: 1.6)), coalesceKey: "other")
        try engine.perform(Self.paragraph(ParagraphStyle(lineHeight: 1.7), index: 1), coalesceKey: "other")
        #expect(engine.undoStack.last?.commands.count == 2)
    }

    @Test func lineHeightFiveRefused() {
        var engine = CommandEngine(document: TextFixtures.document())
        #expect(throws: CommandError.self) { try engine.perform(Self.paragraph(ParagraphStyle(lineHeight: 5))) }
        #expect(engine.document == TextFixtures.document() && !engine.canUndo)
    }

    @Test func badValuesIndexAndLockRefused() {
        var locked = TextFixtures.document()
        locked.scenes[0].layers[1].isLocked = true
        let cases: [(Document, any Command)] = [
            (TextFixtures.document(), Self.onPath(TextOnPath(path: Self.line, startOffset: 2))),
            (TextFixtures.document(), Self.paragraph(ParagraphStyle(boxWidth: 0))),
            (TextFixtures.document(), Self.paragraph(ParagraphStyle(), index: 1)),
            (locked, Self.paragraph(ParagraphStyle())), (locked, Self.onPath(nil)),
        ]
        for (start, command) in cases {
            var engine = CommandEngine(document: start)
            #expect(throws: CommandError.self) { try engine.perform(command) }
            #expect(engine.document == start && !engine.canUndo)
        }
    }

    /// One random step, a paragraph or a path setting, valid or invalid, the paragraph sometimes coalesced as a drag.
    static let undoSteps: [UndoStep] = [{ e, rng, _ in
        let layer = UndoPropertyTests.anyLayer(e, &rng)
        let index = TextCommandsTests.anyIndex(e, layer, &rng), clear = Int.random(in: 0..<6, using: &rng) == 0
        if !Bool.random(using: &rng) {
            let on = TextOnPath(path: line, startOffset: UndoPropertyTests.anyNumber(in: -0.5...1.5, &rng), flipped: Bool.random(using: &rng))
            return try e.perform(SetTextOnPath(owner: o, layerID: layer, textIndex: index, onPath: clear ? nil : on))
        }
        let style = ParagraphStyle(alignment: [.leading, .center, .justified].randomElement(using: &rng) ?? .leading,
                                   lineHeight: UndoPropertyTests.anyNumber(in: 0...5, &rng),
                                   tracking: Double(Int.random(in: 0...2, using: &rng)))
        try e.perform(SetParagraphStyle(owner: o, layerID: layer, textIndex: index, paragraph: clear ? nil : style),
                      coalesceKey: Bool.random(using: &rng) ? "paragraph-drag" : nil)
    }]

    @Test(arguments: 0..<100 as Range<UInt64>)
    func undoAllRestoresOriginal(seed: UInt64) throws {
        try assertUndoRestoresDocument(seed: seed, steps: TextCommandsTests.undoSteps + Self.undoSteps,
                                       start: TextFixtures.document())
    }
}
