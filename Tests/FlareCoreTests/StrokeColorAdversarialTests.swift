// StrokeColorAdversarialTests.swift: adversarial and fuzz tests for the finite
// stroke color check (#193). Random stroke channels and widths drawn from
// finite, huge, subnormal, signed-zero, NaN and infinite values: AddShape is
// accepted exactly when the stroke is valid, a rejected one leaves the engine
// untouched, and an accepted one saves, reloads and undoes exactly. Also covers
// strokes that arrive inside a whole layer, scene or symbol, groups, a file
// whose number overflows to infinity, and a direct execute without the engine.
@testable import FlareCore
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Testing

@Suite struct StrokeColorAdversarialTests {
    static let widths: [Double] = [0, -0.0, 1, 1e308, .leastNonzeroMagnitude, -1, -.leastNonzeroMagnitude,
                                   .nan, .infinity, -.infinity]
    static let nanStroke = Stroke(color: Color(r: 0, g: .nan, b: 0))

    static func stroke(_ rng: inout SplitMix64) -> (Stroke, Bool) {
        let color = FillColorAdversarialTests.color(&rng)
        let width = widths.randomElement(using: &rng) ?? 1
        let join = Stroke.Join.allCases.randomElement(using: &rng) ?? .miter
        let cap = Stroke.Cap.allCases.randomElement(using: &rng) ?? .butt
        let ok = color.isFinite && width.isFinite && width >= 0
        return (Stroke(color: color, width: width, join: join, cap: cap), ok)
    }

    @Test(arguments: [UInt64(1), 7, 193, 0xC0FF_EE00])
    func fuzzAcceptsExactlyValidStrokes(seed: UInt64) throws {
        var rng = SplitMix64(seed: seed)
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        var history = [e.document]
        for _ in 0..<300 {
            let (stroke, ok) = Self.stroke(&rng)
            let owners = FillColorAdversarialTests.owners
            let (owner, layer) = owners[Int.random(in: 0..<owners.count, using: &rng)]
            let add = AddShape(owner: owner, layerID: layer,
                               shape: Shape(points: [Point(x: 1, y: 2)], stroke: stroke))
            let (before, depth) = (e.document, e.undoStack.count)
            if ok {
                try e.perform(add)
                #expect(try FlareFormat.decode(FlareFormat.encode(e.document)) == e.document)
                history.append(e.document)
            } else {
                #expect(throws: CommandError.self, "\(stroke)") { try e.perform(add) }
                #expect(e.document == before)
                #expect(e.undoStack.count == depth)
                _ = try FlareFormat.encode(e.document)
            }
        }
        while e.canUndo {
            try e.undo()
            history.removeLast()
            #expect(e.document == history.last)
        }
    }

    @Test func colorCheckWinsOnlyWhenWidthIsValid() {
        let bad = Stroke(color: Color(r: .nan, g: 0, b: 0), width: -1)
        #expect(throws: ModelError.invalidStroke("stroke width must be finite and >= 0")) { try bad.validate() }
        #expect(throws: ModelError.invalidStroke("color channels must be finite")) {
            try Stroke(color: Color(r: 0, g: 0, b: 0, a: -.infinity), width: 0).validate()
        }
    }

    @Test func boundaryStrokesAreAccepted() throws {
        let strokes = [
            Stroke(color: Color(r: 1e308, g: -.greatestFiniteMagnitude, b: .leastNonzeroMagnitude, a: -0.0), width: 0),
            Stroke(color: .white, width: -0.0),
            Stroke(color: .black, width: .greatestFiniteMagnitude),
        ]
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        for stroke in strokes {
            try e.perform(AddShape(owner: .symbol("sym"), layerID: "wing",
                                   shape: Shape(points: [Point(x: 0, y: 0)], stroke: stroke)))
        }
        #expect(e.document.symbols[0].layers[0].shapes.suffix(3).map(\.stroke) == strokes)
        #expect(try FlareFormat.decode(FlareFormat.encode(e.document)) == e.document)
    }

    @Test func directExecuteRejectsBeforeMutating() {
        var doc = ShapeTextOwnerTests.start()
        var add = AddShape(owner: .scene(Fixtures.sceneID), layerID: "ball",
                           shape: Shape(points: [Point(x: 1, y: 2)], stroke: Self.nanStroke))
        #expect(throws: ModelError.invalidStroke("color channels must be finite")) { try add.execute(&doc) }
        #expect(doc == ShapeTextOwnerTests.start())
    }

    @Test func badStrokeOnMissingOrLockedLayerStillThrows() throws {
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        try e.perform(SetLayerFlags(owner: .scene(Fixtures.sceneID), layerID: "ball", isLocked: true))
        let before = (e.document, e.undoStack.count)
        let shape = Shape(points: [Point(x: 1, y: 2)], stroke: Self.nanStroke)
        for (owner, layer) in [(LayerOwner.scene(Fixtures.sceneID), "ball"), (.scene(Fixtures.sceneID), "nope"),
                               (.scene("nope"), "ball"), (.symbol("nope"), "wing")] {
            #expect(throws: CommandError.self) { try e.perform(AddShape(owner: owner, layerID: layer, shape: shape)) }
        }
        #expect(e.document == before.0)
        #expect(e.undoStack.count == before.1)
    }

    @Test func badStrokeInsideWholeLayerSceneOrSymbolIsRejected() throws {
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        let before = e.document
        let layer = Layer(id: "fresh", name: "Fresh", shapes: [Shape(points: [Point(x: 0, y: 0)], stroke: Self.nanStroke)])
        let commands: [any Command] = [
            AddLayer(owner: .scene(Fixtures.sceneID), layer: layer),
            AddLayer(owner: .symbol("sym"), layer: layer),
            AddScene(scene: Scene(id: "s9", name: "S9", layers: [layer])),
            AddSymbol(symbol: Symbol(id: "sym9", name: "Sym9", layers: [layer])),
        ]
        for command in commands {
            #expect(throws: CommandError.self, "\(command.label)") { try e.perform(command) }
            #expect(e.document == before)
            #expect(!e.canUndo)
        }
        _ = try FlareFormat.encode(e.document)
    }

    @Test func groupWithBadStrokeRollsBackEarlierSteps() throws {
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        let before = e.document
        #expect(throws: CommandError.self) {
            try e.group("Two shapes") { e in
                try e.perform(AddShape(owner: .scene(Fixtures.sceneID), layerID: "ball",
                                       shape: Shape(points: [Point(x: 0, y: 0)], stroke: Stroke())))
                try e.perform(AddShape(owner: .scene(Fixtures.sceneID), layerID: "ball",
                                       shape: Shape(points: [Point(x: 0, y: 0)], stroke: Self.nanStroke)))
            }
        }
        #expect(e.document == before)
        #expect(!e.canUndo)
        _ = try FlareFormat.encode(e.document)
    }

    @Test func fileWithOverflowingStrokeChannelFailsToLoad() throws {
        var doc = ShapeTextOwnerTests.start()
        doc.scenes[0].layers[1].shapes[0].stroke = Stroke(color: Color(r: 0.123456, g: 0, b: 0))
        let json = try #require(String(data: FlareFormat.encode(doc), encoding: .utf8))
        #expect(json.contains("0.123456"))
        let bad = Data(json.replacingOccurrences(of: "0.123456", with: "1e999").utf8)
        #expect(throws: FormatError.self) { try FlareFormat.decode(bad) }
    }

    @Test func strokeIsCheckedAfterFill() {
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        let shape = Shape(points: [Point(x: 1, y: 2)], fill: .solid(Color(r: .nan, g: 0, b: 0)), stroke: Self.nanStroke)
        #expect(throws: CommandError.invalidDocument("color channels must be finite")) {
            try e.perform(AddShape(owner: .scene(Fixtures.sceneID), layerID: "ball", shape: shape))
        }
        #expect(!e.canUndo)
    }
}
