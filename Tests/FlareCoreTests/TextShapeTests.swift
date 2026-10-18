// TextShapeTests.swift: the text-engine contract (TE-1): resolved runs tile the
// string in graphemes, metrics refuse bad values, and the stubs throw notBuilt.
import FlareCore
import Testing

@Suite struct TextShapeTests {
    static func text(_ string: String = "Bring the light", runs: [TextRun] = []) -> TextShape {
        TextShape(string: string, fontFamily: "Inter", fontSize: 24, position: Point(x: 0, y: 0), runs: runs)
    }

    /// The runs leave no gap and no overlap, and end at the string's grapheme count.
    static func expectTiles(_ runs: [ResolvedRun], _ count: Int) {
        var cursor = 0
        for run in runs {
            #expect(run.start == cursor && run.length > 0, "\(run)")
            cursor = run.start + run.length
        }
        #expect(cursor == count)
    }

    @Test func plainShapeIsOneRun() {
        #expect(Self.text().resolvedRuns == [ResolvedRun(start: 0, length: 15, fontFamily: "Inter", fontSize: 24, fill: .solid(.black))])
        #expect(Self.text("").resolvedRuns.isEmpty)
    }

    @Test func runsTileTheString() {
        let runs = Self.text(runs: [TextRun(start: 6, length: 5, weight: 700)]).resolvedRuns
        #expect(runs.map(\.weight) == [400, 700, 400])
        #expect(runs.map(\.start) == [0, 6, 11] && runs.map(\.length) == [6, 5, 4])
        #expect(runs.allSatisfy { $0.fontFamily == "Inter" && $0.fontSize == 24 })
        Self.expectTiles(runs, 15)
    }

    @Test func runFieldsOverrideTheShape() throws {
        let red = Fill.solid(Color(r: 1, g: 0, b: 0))
        let run = TextRun(start: 0, length: 2, fontFamily: "Mono", fontSize: 10, weight: 300,
                          italic: true, fill: red, tracking: 2, baselineShift: -3)
        #expect(Self.text(runs: [run]).resolvedRuns.first == ResolvedRun(
            start: 0, length: 2, fontFamily: "Mono", fontSize: 10, weight: 300, italic: true, fill: red, tracking: 2, baselineShift: -3))
    }

    /// Unsorted, overlapping or out-of-range runs still tile the string; nothing traps.
    @Test func malformedRunsStillTile() {
        let runs = [TextRun(start: 10, length: 99, weight: 700), TextRun(start: 2, length: 10, italic: true),
                    TextRun(start: -4, length: 1), TextRun(start: 3, length: Int.max)]
        Self.expectTiles(Self.text(runs: runs).resolvedRuns, 15)
    }

    @Test func emojiIsOneGrapheme() {
        let runs = Self.text("👍🏽é!", runs: [TextRun(start: 0, length: 1, weight: 700)]).resolvedRuns
        #expect(runs.map(\.length) == [1, 2])
        Self.expectTiles(runs, 3)
        #expect(FixedAdvances.measure(Self.text("👍🏽é!")).map(\.advances.count) == [3])
    }

    @Test func fixedAdvancesAreHalfAnEm() {
        let measured = FixedAdvances.measure(Self.text(runs: [TextRun(start: 6, length: 5, fontSize: 10)]))
        #expect(measured.map(\.advances) == [[Double](repeating: 12, count: 6), [Double](repeating: 5, count: 5),
                                             [Double](repeating: 12, count: 4)])
        let ems: [Double] = [24, 10, 24]
        #expect(measured.map(\.ascent) == ems.map { 0.8 * $0 } && measured.map(\.descent) == ems.map { 0.2 * $0 })
    }

    @Test(arguments: [Double.nan, -1, .infinity])
    func metricsRejectBadValues(_ bad: Double) throws {
        #expect(throws: ModelError.self) { try GlyphRunMetrics(advances: [1, bad], ascent: 1, descent: 1) }
        #expect(throws: ModelError.self) { try GlyphRunMetrics(advances: [1], ascent: bad, descent: 1) }
        #expect(throws: ModelError.self) { try GlyphRunMetrics(advances: [1], ascent: 1, descent: bad) }
        #expect(try GlyphRunMetrics(advances: [0, 3], ascent: 0, descent: 0).advances == [0, 3])
    }

    @Test func layoutStubsThrowNotBuilt() {
        let text = Self.text(), measured = FixedAdvances.measure(text)
        #expect(throws: CommandError.notBuilt("TextLayout.lay is not built yet (text-engine)")) {
            try TextLayout.lay(text, measured: measured)
        }
        #expect(throws: CommandError.notBuilt("TextLayout.onPath is not built yet (text-engine)")) {
            try TextLayout.onPath(text, measured: measured, tolerance: 0.1)
        }
        #expect(TextLayout.maxGraphemes == 100_000)
    }

    /// Each command stub registers, round-trips through the registry and
    /// throws notBuilt naming its id, leaving the document as it was.
    @Test func commandStubsThrowNotBuilt() throws {
        let o = LayerOwner.scene(Fixtures.sceneID)
        let commands: [any Command] = [
            ApplyTextStyle(owner: o, layerID: "ball", textIndex: 0, range: 0..<2, style: TextRunStyle(weight: 700)),
            ClearTextStyle(owner: o, layerID: "ball", textIndex: 0, range: 0..<2),
            EditTextString(owner: o, layerID: "ball", textIndex: 0, replacing: 1..<2, with: "x"),
            SetParagraphStyle(owner: o, layerID: "ball", textIndex: 0, paragraph: ParagraphStyle(boxWidth: 120)),
            SetTextOnPath(owner: o, layerID: "ball", textIndex: 0, onPath: nil),
        ]
        #expect(commands.map { type(of: $0).id } == TextStyleCommands.all.map { $0.id })
        for command in commands {
            let id = type(of: command).id, data = try CommandRegistry.builtIn.encode(command)
            #expect(try CommandRegistry.builtIn.encode(CommandRegistry.builtIn.decode(data)) == data)
            var engine = CommandEngine(document: TextCommandsTests.withText())
            let before = engine.document
            #expect(throws: CommandError.notBuilt("\(id) is not built yet (text-engine)")) { try engine.perform(command) }
            #expect(engine.document == before)
        }
    }
}
