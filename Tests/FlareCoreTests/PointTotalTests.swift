// PointTotalTests.swift: CommandEngine's running point total. perform keeps
// FlareFormat's point count of the document per command, so the scoped check
// adds one layer's delta instead of recounting every layer. Random command
// sequences (groups, failures, undo, redo) must leave the total equal to a full
// recount whenever it is known, and a known total must reject exactly what a
// recount rejects, with the same error.
@testable import FlareCore
import Testing

@Suite struct PointTotalTests {
    @Test(arguments: 0..<40)
    func runningTotalEqualsAFullRecount(seed: UInt64) throws {
        var rng = SplitMix64(seed: seed)
        var engine = CommandEngine(document: Fixtures.withSymbol())
        var nextID = 0
        var known = 0
        let steps = UndoPropertyTests.allSteps
        func step(_ e: inout CommandEngine) throws {
            guard let s = steps.randomElement(using: &rng) else { return }
            try s(&e, &rng, &nextID)
        }
        let rounds = 120
        for _ in 0..<rounds {
            switch Int.random(in: 0..<16, using: &rng) {
            case 0, 1: try? engine.group("Batch") { e in
                for _ in 0..<Int.random(in: 2...4, using: &rng) { try step(&e) }
            }
            case 2: try? engine.undo()
            case 3: try? engine.redo()
            default: try? step(&engine)
            }
            if let total = engine.pointTotal {
                known += 1
                #expect(total == (try FlareFormat.checkLimits(engine.document)))
            }
        }
        #expect(known >= rounds / 8, "the total was known for only \(known) of \(rounds) rounds")
    }

    /// A known total rejects the same growth a recount does, with the same error,
    /// and a rejected command leaves the document and the total as they were.
    @Test func knownTotalRejectsWhatARecountRejects() throws {
        let full = FormatLimitsTests.document(points: FlareFormat.maxTotalPoints)
        let onePoint = Layer(id: "extra", name: "E", shapes: [Shape(points: [Point(x: 0, y: 0)])])
        let filler = (1..<FlareFormat.maxLayersPerScene).map { Layer(id: "f\($0)", name: "F") }
        var crowded = FormatLimitsTests.document(points: 10)
        crowded.scenes[0].layers += filler
        for (start, command) in [(full, AddLayer(owner: .scene("s"), layer: onePoint)),
                                 (crowded, AddLayer(owner: .scene("s"), layer: Layer(id: "x", name: "X")))] {
            var recount = CommandEngine(document: start)
            #expect(recount.pointTotal == nil)
            // A full validate (any non-layer command) sets the total.
            var running = CommandEngine(document: start)
            try running.perform(RenameScene(sceneID: "s", name: "Named"))
            let total = try #require(running.pointTotal)
            #expect(total == (try FlareFormat.checkLimits(start)))
            let document = running.document

            let viaRecount = #expect(throws: CommandError.self) { try recount.perform(command) }
            let viaTotal = #expect(throws: CommandError.self) { try running.perform(command) }
            #expect(viaTotal == viaRecount)
            #expect(running.document == document)
            #expect(running.pointTotal == total)
        }
    }

    /// Removing a layer takes its points off the total, so a layer of the same
    /// size fits again at the limit.
    @Test func removalFreesItsPoints() throws {
        var engine = CommandEngine(document: FormatLimitsTests.document(points: FlareFormat.maxTotalPoints))
        try engine.perform(RenameScene(sceneID: "s", name: "Named"))
        let layer = try #require(engine.document.scenes[0].layers.first)
        try engine.perform(RemoveLayer(owner: .scene("s"), layerID: "l"))
        #expect(engine.pointTotal == 0)
        try engine.perform(AddLayer(owner: .scene("s"), layer: layer))
        #expect(engine.pointTotal == FlareFormat.maxTotalPoints)
    }
}
