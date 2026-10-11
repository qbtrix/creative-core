// StressBudgetTests.swift: the engine stays fast on big documents. The engine
// runs each command on a copy of the document; copy-on-write means that costs
// the arrays a command touches, not a deep copy. A deep copy per command would
// blow this budget by orders of magnitude.
import FlareCore
import Testing

@Suite struct StressBudgetTests {
    static let layerCount = 10_000
    static let commandCount = 1_000

    /// One scene with `layerCount` layers, each with a shape and a keyframe track.
    static func bigDocument(seed: UInt64) -> Document {
        var rng = SplitMix64(seed: seed)
        let layers = (0..<layerCount).map { i in
            let x = Double.random(in: -100...100, using: &rng)
            return Layer(
                id: "big\(i)", name: "Layer \(i)",
                shapes: [Shape(points: [Point(x: x, y: 0), Point(x: 1, y: 1)], closed: false)],
                tracks: ["x": [Keyframe(frame: 0, value: x), Keyframe(frame: 24, value: -x)]]
            )
        }
        return Document(scenes: [Scene(id: Fixtures.sceneID, name: "Main", fps: 24, durationFrames: 48,
                                       layers: layers)])
    }

    @Test func thousandCommandsOnTenThousandLayersStayInBudget() throws {
        let start = Self.bigDocument(seed: 40)
        var rng = SplitMix64(seed: 4040)
        var engine = CommandEngine(document: start, maxUndoDepth: Self.commandCount)
        var nextID = 0, performed = 0, undone = 0
        // Every layer-level family. Scene steps are left out: removing the only
        // scene early would make the rest of the run fail fast and prove nothing.
        let steps = UndoPropertyTests.coreSteps + KeyframeCommandsTests.undoSteps
            + LayerFlagsTests.undoSteps + ShapeCommandsTests.undoSteps

        let elapsed = try ContinuousClock().measure {
            for _ in 0..<Self.commandCount {
                guard let step = steps.randomElement(using: &rng) else { return }
                if (try? step(&engine, &rng, &nextID)) != nil { performed += 1 }
            }
            while engine.canUndo { try engine.undo(); undone += 1 }
        }

        #expect(performed > Self.commandCount / 2, "most random commands should succeed")
        #expect(undone == performed)
        #expect(engine.document == start)
        #expect(elapsed < .seconds(5), "1,000 commands + undo-all on 10,000 layers took \(elapsed)")
    }
}
