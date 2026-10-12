// UndoPropertyTests.swift: the cross-family undo property. Random command
// sequences drawn from every family (some invalid, some grouped), then undo
// everything, must give back the original document; redo everything must give
// back the final one. Every perform, undo and redo must leave a document that
// passes FlareFormat.validate. Numeric params are sometimes NaN or +-infinity
// (anyNumber): such a step must either be rejected with the document unchanged
// or keep the document valid and undo exactly. Seeded, so failures reproduce. Each family's own test
// file runs the same property with only its steps (see Support.swift).
import FlareCore
import Testing

@Suite struct UndoPropertyTests {
    /// Every family's steps. A new family adds one line here.
    static let allSteps: [UndoStep] = coreSteps
        + SceneCommandTests.undoSteps
        + KeyframeCommandsTests.undoSteps
        + LayerFlagsTests.undoSteps
        + ShapeCommandsTests.undoSteps
        + SymbolCommandsTests.undoSteps
        + LabelCommandsTests.undoSteps
        + MetadataCommandsTests.undoSteps

    @Test(arguments: 0..<200)
    func undoAllRestoresOriginal(seed: UInt64) throws {
        try assertUndoRestoresDocument(seed: seed, steps: Self.allSteps)
    }

    @Test(arguments: 0..<200)
    func coreUndoAllRestoresOriginal(seed: UInt64) throws {
        try assertUndoRestoresDocument(seed: seed, steps: Self.coreSteps)
    }

    static let props = ["x", "y", "scale", "rotation", "opacity"]

    /// A number in `range`, or about one time in six NaN, +infinity or -infinity,
    /// so steps also send non-finite params.
    static func anyNumber(in range: ClosedRange<Double>, _ rng: inout SplitMix64) -> Double {
        guard Int.random(in: 0..<6, using: &rng) == 0 else { return Double.random(in: range, using: &rng) }
        return [Double.nan, .infinity, -.infinity].randomElement(using: &rng) ?? .nan
    }

    /// A layer of the first scene, or "missing", so steps hit both valid and invalid params.
    static func anyLayer(_ e: CommandEngine, _ rng: inout SplitMix64) -> String {
        // Index instead of mapping ids: O(1), so EngineStressTests' big scene stays cheap.
        let layers = e.document.scenes.first?.layers ?? []
        let i = Int.random(in: 0..<(layers.count + 1), using: &rng)
        return layers.indices.contains(i) ? layers[i].id : "missing"
    }

    static func anyProp(_ rng: inout SplitMix64) -> String { props.randomElement(using: &rng) ?? "x" }

    /// Layer, keyframe and shape commands (Commands.swift).
    static let coreSteps: [UndoStep] = [
        { e, rng, nextID in
            nextID += 1
            let index = Int.random(in: -2...5, using: &rng)
            try e.perform(AddLayer(sceneID: Fixtures.sceneID,
                                   layer: Layer(id: "L\(nextID)", name: "Layer \(nextID)"), index: index))
        },
        { e, rng, _ in
            try e.perform(RemoveLayer(sceneID: Fixtures.sceneID, layerID: anyLayer(e, &rng)))
        },
        { e, rng, _ in
            let layer = anyLayer(e, &rng)
            try e.perform(RenameLayer(sceneID: Fixtures.sceneID, layerID: layer,
                                      name: "n\(Int.random(in: -1...30, using: &rng))"))
        },
        { e, rng, _ in
            let layer = anyLayer(e, &rng), prop = anyProp(&rng)
            let easing: Easing = Bool.random(using: &rng) ? .linear : .easeInOut
            let k = Keyframe(frame: Int.random(in: -1...30, using: &rng),
                             value: anyNumber(in: -100...100, &rng), easing: easing)
            try e.perform(SetKeyframe(sceneID: Fixtures.sceneID, layerID: layer, property: prop, keyframe: k))
        },
        { e, rng, _ in
            let layer = anyLayer(e, &rng), prop = anyProp(&rng)
            try e.perform(MoveKeyframe(sceneID: Fixtures.sceneID, layerID: layer, property: prop,
                                       from: Int.random(in: -1...30, using: &rng),
                                       to: Int.random(in: -1...30, using: &rng)),
                          coalesceKey: Bool.random(using: &rng) ? "drag" : nil)
        },
        { e, rng, _ in
            let layer = anyLayer(e, &rng), prop = anyProp(&rng)
            try e.perform(RemoveKeyframe(sceneID: Fixtures.sceneID, layerID: layer, property: prop,
                                         frame: Int.random(in: -1...30, using: &rng)))
        },
        { e, rng, _ in
            let layer = anyLayer(e, &rng)
            let shape = Shape(points: [Point(x: anyNumber(in: -1...30, &rng), y: 0), Point(x: 1, y: 1)], closed: false)
            try e.perform(AddShape(sceneID: Fixtures.sceneID, layerID: layer, shape: shape))
        },
        { e, rng, _ in
            let layer = anyLayer(e, &rng)
            let count = e.document.scenes.first?.layers.count ?? 0
            let to = Int.random(in: -1...count, using: &rng)
            try e.perform(ReorderLayer(sceneID: Fixtures.sceneID, layerID: layer, toIndex: to))
        },
    ]
}
