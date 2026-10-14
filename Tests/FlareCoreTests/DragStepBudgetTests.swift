// DragStepBudgetTests.swift: the drag-step budget QB-L7. One step of a drag goes
// through CommandEngine.perform, which executes the command, validates the
// result and merges it into the drag's undo entry. A drag sends one step per
// pointer move, so each step must cost well under a frame: the median of 100
// steps stays within 10 ms on a seeded scene of 200 layers. Three drags are
// timed: an instance move (SetInstanceTransform), a keyframe scrub
// (SetKeyframe) and a guide move (MoveGuide), each under one coalesce key, and
// each must end as one undo entry so the budget times the coalesced path. The
// budget is a debug-build CI gate on a shared machine: a few warm-up steps run
// first so the median reflects steady state, and the median (not the mean)
// keeps one slow step from failing the run.
@testable import FlareCore
import Testing

@Suite struct DragStepBudgetTests {
    static let layerCount = 200
    static let steps = 100
    static let warmUpSteps = 10
    static let budget: Duration = .milliseconds(10)
    static let scene = Fixtures.sceneID

    /// The fixture document with its scene holding `layerCount` seeded layers,
    /// every tenth placing symbol "spark", and two guides.
    static func document(seed: UInt64) -> Document {
        var rng = SplitMix64(seed: seed)
        var doc = Fixtures.document()
        doc.symbols = [Symbol(id: "spark", name: "Spark", durationFrames: 6)]
        var layers: [Layer] = []
        for i in 0..<layerCount {
            let x = Double.random(in: 0...500, using: &rng)
            let y = Double.random(in: 0...300, using: &rng)
            let shape = Shape(points: [Point(x: x, y: y), Point(x: x + 10, y: y), Point(x: x + 10, y: y + 10)],
                              fill: .solid(Color(r: Double.random(in: 0...1, using: &rng), g: 0.4, b: 0.6)))
            let tracks = ["x": [Keyframe(frame: 0, value: x), Keyframe(frame: 24, value: -x, easing: .easeInOut)]]
            let instances = i % 10 == 0 ? [Instance(symbolID: "spark", transform: Transform(x: x, y: y))] : []
            layers.append(Layer(id: "L\(i)", name: "Layer \(i)", shapes: [shape], tracks: tracks, instances: instances))
        }
        doc.scenes[0].layers = layers
        doc.scenes[0].guides = [Guide(axis: .vertical, position: 100), Guide(axis: .horizontal, position: 50)]
        return doc
    }

    /// Runs `warmUpSteps` untimed then `steps` timed calls of `step` on one
    /// engine, and returns the median step time and the engine.
    static func drag(seed: UInt64,
                     _ step: (inout CommandEngine, Int) throws -> Void) throws -> (Duration, CommandEngine) {
        var engine = CommandEngine(document: document(seed: seed))
        #expect(engine.document.scenes.first?.layers.count == layerCount)
        for i in 0..<warmUpSteps { try step(&engine, i) }
        let clock = ContinuousClock()
        var times: [Duration] = []
        for i in warmUpSteps..<(warmUpSteps + steps) {
            times.append(try clock.measure { try step(&engine, i) })
        }
        times.sort()
        return (times[times.count / 2], engine)
    }

    @Test func instanceDragStepWithinBudget() throws {
        let (median, engine) = try Self.drag(seed: 71) { engine, i in
            try engine.perform(SetInstanceTransform(owner: .scene(Self.scene), layerID: "L100", index: 0,
                                                    transform: Transform(x: Double(i), y: 0.5 * Double(i))),
                               coalesceKey: "instance-drag")
        }
        #expect(engine.undoStack.count == 1)
        #expect(engine.undoStack.first?.commands.count == 1)
        #expect(median <= Self.budget, "instance drag step median \(median) over \(Self.budget)")
    }

    @Test func scrubStepWithinBudget() throws {
        let (median, engine) = try Self.drag(seed: 72) { engine, i in
            try engine.perform(SetKeyframe(owner: .scene(Self.scene), layerID: "L100", property: "x",
                                           keyframe: Keyframe(frame: 12, value: Double(i))),
                               coalesceKey: "scrub")
        }
        #expect(engine.undoStack.count == 1)
        #expect(engine.undoStack.first?.commands.count == 1)
        #expect(median <= Self.budget, "scrub step median \(median) over \(Self.budget)")
    }

    @Test func guideDragStepWithinBudget() throws {
        let (median, engine) = try Self.drag(seed: 73) { engine, i in
            try engine.perform(MoveGuide(sceneID: Self.scene, index: 0, position: 100 + Double(i)),
                               coalesceKey: "guide-drag")
        }
        #expect(engine.undoStack.count == 1)
        #expect(engine.undoStack.first?.commands.count == 1)
        #expect(median <= Self.budget, "guide drag step median \(median) over \(Self.budget)")
    }
}
