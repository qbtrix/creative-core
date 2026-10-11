// EngineStressTests.swift: the engine stress budget. perform and undo copy the
// document and rely on copy-on-write, so a command on a big document should
// cost the arrays it touches, not a deep copy. 1,000 random commands from every
// family on a 10,000-layer document, then undo-all, must stay within budget and
// give back the original document.
import FlareCore
import Testing

@Suite struct EngineStressTests {
    static let layerCount = 10_000
    static let commandCount = 1_000
    static let budget: Duration = .seconds(5)
    /// Every family that edits the big scene. Scene steps are left out: one
    /// RemoveScene of the big scene would make every later command a no-op throw.
    static let steps: [UndoStep] = UndoPropertyTests.coreSteps
        + KeyframeCommandsTests.undoSteps
        + LayerFlagsTests.undoSteps
        + ShapeCommandsTests.undoSteps

    /// The fixture document with `layerCount` extra seeded layers in its first scene.
    static func bigDocument(seed: UInt64) -> Document {
        var rng = SplitMix64(seed: seed)
        var doc = Fixtures.document()
        guard var scene = doc.scenes.first else { return doc }
        for i in 0..<layerCount {
            let x = Double(Int.random(in: 0...100, using: &rng))
            let shape = Shape(points: [Point(x: x, y: 0), Point(x: x + 1, y: 1)], closed: false)
            let track = [Keyframe(frame: 0, value: x), Keyframe(frame: 24, value: -x, easing: .easeInOut)]
            scene.layers.append(Layer(id: "big\(i)", name: "Big \(i)", shapes: [shape], tracks: ["x": track]))
        }
        doc.scenes[0] = scene
        return doc
    }

    @Test func thousandCommandsOnTenThousandLayersStayInBudget() throws {
        let start = Self.bigDocument(seed: 40)
        #expect(start.scenes.first?.layers.count == Self.layerCount + 2)

        var rng = SplitMix64(seed: 40)
        var engine = CommandEngine(document: start, maxUndoDepth: Self.commandCount)
        var nextID = 0
        var performed = 0
        let clock = ContinuousClock()
        let elapsed = try clock.measure {
            for _ in 0..<Self.commandCount {
                guard let step = Self.steps.randomElement(using: &rng) else { continue }
                do {
                    try step(&engine, &rng, &nextID)
                    performed += 1
                } catch {
                    // Invalid params are part of the mix; the engine left the document as it was.
                }
            }
            while engine.canUndo { try engine.undo() }
        }

        #expect(performed > Self.commandCount / 2, "too few commands succeeded to exercise the engine")
        #expect(engine.document == start)
        #expect(elapsed < Self.budget, "1,000 commands + undo-all on 10,000 layers took \(elapsed)")
    }
}
