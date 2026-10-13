// ShapeTextOwnerAdversarialTests.swift: edge cases and fuzz for the shape and
// text commands on symbol owners (Q5d): missing owners, shared scene and symbol
// ids, non-finite and huge values, extreme indices, the point limit, undo past
// a lock, hand-written symbol envelopes, and a seeded fuzz of their bytes.
@testable import FlareCore
import Foundation
import Testing

@Suite struct ShapeTextOwnerAdversarialTests {
    private static let registry = CommandRegistry.builtIn
    private static let sym = LayerOwner.symbol("sym")

    /// The Q5d acceptance start: a shape and a text on the symbol's "wing".
    private static func start() -> Document { ShapeTextOwnerTests.start() }

    @Test func missingOwnersAndLayersThrowAndChangeNothing() {
        let start = Self.start()
        let cases: [(LayerOwner, String, CommandError)] = [
            (.symbol("ghost"), "wing", .symbolNotFound("ghost")),
            (.symbol(""), "wing", .symbolNotFound("")),
            (.scene("sym"), "wing", .sceneNotFound("sym")),
            (.symbol(Fixtures.sceneID), "ball", .symbolNotFound(Fixtures.sceneID)),
            (Self.sym, "ball", .layerNotFound("ball")),
            (Self.sym, "", .layerNotFound("")),
        ]
        for (owner, layer, error) in cases {
            for command in ShapeTextOwnerTests.edits(owner, layerID: layer) {
                var e = CommandEngine(document: start)
                #expect(throws: error, "\(command.label) on \(owner)/\(layer)") { try e.perform(command) }
                #expect(e.document == start)
                #expect(!e.canUndo)
            }
        }
    }

    @Test func sharedSceneAndSymbolIDsStayApart() throws {
        // The symbol and its layer take the scene's ids, so only the owner kind differs.
        var start = Self.start()
        (start.symbols[0].id, start.symbols[0].layers[0].id) = (Fixtures.sceneID, "ball")
        start.scenes[0].layers[1].texts = [TextCommandsTests.hello]
        for owner in [LayerOwner.symbol(Fixtures.sceneID), .scene(Fixtures.sceneID)] {
            for command in ShapeTextOwnerTests.edits(owner, layerID: "ball") {
                var e = CommandEngine(document: start)
                try e.perform(command)
                if case .symbol = owner {
                    #expect(e.document.scenes == start.scenes, "\(command.label) touched the scene")
                } else {
                    #expect(e.document.symbols == start.symbols, "\(command.label) touched the symbol")
                }
                try e.undo()
                #expect(e.document == start)
            }
        }
    }

    @Test func extremeIndicesThrowShapeNotFound() {
        let start = Self.start()
        for index in [-1, 1, 2, Int.max, Int.min] {
            let commands: [any Command] = [
                RemoveShape(owner: Self.sym, layerID: "wing", index: index),
                SetShapeFill(owner: Self.sym, layerID: "wing", index: index, fill: .solid(.white)),
                TranslateShape(owner: Self.sym, layerID: "wing", index: index, dx: 1, dy: 1),
                RemoveTextShape(owner: Self.sym, layerID: "wing", index: index),
                SetTextString(owner: Self.sym, layerID: "wing", index: index, string: "x"),
                SetTextFont(owner: Self.sym, layerID: "wing", index: index, family: "A", size: 1),
            ]
            for command in commands {
                var e = CommandEngine(document: start)
                #expect(throws: CommandError.shapeNotFound(index), "\(command.label) \(index)") { try e.perform(command) }
                #expect(e.document == start)
            }
        }
    }

    @Test func nonFiniteAndOverflowingMovesAreRejected() throws {
        let start = Self.start()
        let bad: [(Double, Double)] = [
            (.nan, 0), (0, .nan), (.infinity, 0), (0, -.infinity), (.greatestFiniteMagnitude, 0),
        ]
        for (dx, dy) in bad {
            var e = CommandEngine(document: start)
            let first = TranslateShape(owner: Self.sym, layerID: "wing", index: 0, dx: dx, dy: dy)
            // A greatestFiniteMagnitude step is finite once; twice it overflows to infinity.
            if dx.isFinite && dy.isFinite {
                try e.perform(first, coalesceKey: "drag")
                let after = e.document
                #expect(throws: CommandError.self) { try e.perform(first, coalesceKey: "drag") }
                #expect(e.document == after)
                try e.undo()
            } else {
                #expect(throws: CommandError.self) { try e.perform(first, coalesceKey: "drag") }
            }
            #expect(e.document == start)
        }
    }

    @Test func badTextValuesInSymbolAreRejected() {
        let start = Self.start()
        var nanText = TextCommandsTests.hello
        nanText.position = Point(x: .nan, y: 0)
        let commands: [any Command] = [
            SetTextFont(owner: Self.sym, layerID: "wing", index: 0, family: "A", size: .nan),
            SetTextFont(owner: Self.sym, layerID: "wing", index: 0, family: "A", size: 0),
            SetTextFont(owner: Self.sym, layerID: "wing", index: 0, family: "A", size: -1),
            SetTextFont(owner: Self.sym, layerID: "wing", index: 0, family: "A", size: .infinity),
            AddTextShape(owner: Self.sym, layerID: "wing", text: nanText),
            AddShape(owner: Self.sym, layerID: "wing", shape: Shape(points: [Point(x: .nan, y: 0)])),
        ]
        for command in commands {
            var e = CommandEngine(document: start)
            #expect(throws: (any Error).self, "\(command.label)") { try e.perform(command) }
            #expect(e.document == start, "\(command.label)")
        }
    }

    @Test func pointLimitCountsSymbolLayers() {
        // The scene already holds its points, so a symbol shape that brings the
        // total over the limit must be refused.
        var start = Self.start()
        let scenePoints = FlareFormat.pointCount(start.scenes.flatMap { $0.layers.flatMap(\.shapes) })
            + FlareFormat.pointCount(start.symbols.flatMap { $0.layers.flatMap(\.shapes) })
        let room = FlareFormat.maxTotalPoints - scenePoints
        start.scenes[0].layers[1].shapes.append(Shape(points: Array(repeating: Point(x: 0, y: 0), count: room)))
        var e = CommandEngine(document: start)
        #expect(throws: CommandError.self) {
            try e.perform(AddShape(owner: Self.sym, layerID: "wing", shape: Shape(points: [Point(x: 1, y: 1)])))
        }
        #expect(e.document == start)
    }

    @Test func undoWorksAfterTheSymbolLayerIsLocked() throws {
        let start = Self.start()
        var e = CommandEngine(document: start)
        for command in ShapeTextOwnerTests.edits(Self.sym, layerID: "wing") { try e.perform(command) }
        let edited = e.document
        try e.perform(SetLayerFlags(owner: Self.sym, layerID: "wing", isLocked: true))
        // Undo goes past the lock in one group, then every edit undoes exactly.
        while e.canUndo { try e.undo() }
        #expect(e.document == start)
        while e.canRedo { try e.redo() }
        #expect(e.document.symbols[0].layers[0].isLocked)
        var unlocked = e.document
        unlocked.symbols[0].layers[0].isLocked = edited.symbols[0].layers[0].isLocked
        #expect(unlocked == edited)
    }

    @Test func handWrittenSymbolEnvelopes() throws {
        let good = #"{"id":"shape.translate","params":{"symbolID":"sym","layerID":"wing","index":0,"dx":2,"dy":3}}"#
        let command = try Self.registry.decode(Data(good.utf8))
        var e = CommandEngine(document: Self.start())
        try e.perform(command)
        #expect(e.document.symbols[0].layers[0].shapes[0]
            == Self.start().symbols[0].layers[0].shapes[0].translated(dx: 2, dy: 3))
        let bad = [
            #"{"id":"shape.translate","params":{"sceneID":"s1","symbolID":"sym","layerID":"wing","index":0,"dx":2,"dy":3}}"#,
            #"{"id":"shape.translate","params":{"layerID":"wing","index":0,"dx":2,"dy":3}}"#,
            #"{"id":"shape.translate","params":{"symbolID":5,"layerID":"wing","index":0,"dx":2,"dy":3}}"#,
            #"{"id":"shape.translate","params":{"symbolID":"sym","index":0,"dx":2,"dy":3}}"#,
            #"{"id":"shape.translate","params":{"symbolID":"sym","layerID":"wing","index":1e30,"dx":2,"dy":3}}"#,
            #"{"id":"shape.translate","params":{"symbolID":"sym","layerID":"wing","index":0.5,"dx":2,"dy":3}}"#,
            #"{"id":"text.setFont","params":{"symbolID":"sym","layerID":"wing","index":0,"family":"A"}}"#,
            #"{"id":"shape.add","params":{"symbolID":"sym","layerID":"wing"}}"#,
            #"{"id":"text.remove","params":{"symbolID":"sym","layerID":"wing","index":"0"}}"#,
        ]
        for json in bad {
            #expect(throws: CommandError.self, "\(json)") { try Self.registry.decode(Data(json.utf8)) }
        }
    }

    @Test func fuzzedSymbolEnvelopesNeverCrash() throws {
        let start = Self.start()
        let seeds = try ShapeTextOwnerTests.edits(Self.sym, layerID: "wing").map { try Self.registry.encode($0) }
        var rng = SplitMix64(seed: 0x5d_0bad)
        for _ in 0..<600 {
            guard var bytes = seeds.randomElement(using: &rng).map(Array.init) else { continue }
            for _ in 0..<Int.random(in: 1...4, using: &rng) where !bytes.isEmpty {
                let i = Int.random(in: 0..<bytes.count, using: &rng)
                switch Int.random(in: 0..<3, using: &rng) {
                case 0: bytes[i] = UInt8.random(in: 0...255, using: &rng)
                case 1: bytes.remove(at: i)
                default: bytes.insert(Array(#"{}[],:"-019eE.\"#.utf8).randomElement(using: &rng) ?? 0, at: i)
                }
            }
            let command: any Command
            do { command = try Self.registry.decode(Data(bytes)) } catch is CommandError { continue }
            var e = CommandEngine(document: start)
            do { try e.perform(command) } catch is CommandError { continue }
            try FlareFormat.validate(e.document)
            try e.undo()
            #expect(e.document == start)
        }
    }
}
