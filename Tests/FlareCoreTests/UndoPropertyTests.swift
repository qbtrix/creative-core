// UndoPropertyTests.swift: random command sequences (some invalid, some
// grouped), then undo everything, must give back the original document; redo
// everything must give back the final one. Seeded, so failures reproduce.
import FlareCore
import Testing

@Suite struct UndoPropertyTests {
    static let props = ["x", "y", "opacity"]

    @Test(arguments: 0..<200)
    func undoAllRestoresOriginal(seed: UInt64) throws {
        var rng = SplitMix64(seed: seed)
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        var nextID = 0

        for _ in 0..<40 {
            if Int.random(in: 0..<8, using: &rng) == 0 {
                // A group of 2-4 commands; a failure inside rolls the group back.
                try? engine.group("Batch") { e in
                    for _ in 0..<Int.random(in: 2...4, using: &rng) {
                        try Self.randomStep(&e, &rng, &nextID)
                    }
                }
            } else {
                let before = engine.document
                do {
                    try Self.randomStep(&engine, &rng, &nextID)
                } catch {
                    #expect(engine.document == before, "failed command mutated the document")
                }
            }
        }

        let final = engine.document
        var undos = 0
        while engine.canUndo { try engine.undo(); undos += 1 }
        #expect(engine.document == original)
        for _ in 0..<undos { try engine.redo() }
        #expect(engine.document == final)
    }

    /// One random command, chosen to hit both valid and invalid params.
    static func randomStep(_ e: inout CommandEngine, _ rng: inout SplitMix64, _ nextID: inout Int) throws {
        let s = Fixtures.sceneID
        let layers = e.document.scenes.first?.layers.map(\.id) ?? []
        let layer = (layers + ["missing"]).randomElement(using: &rng) ?? "missing"
        let prop = props.randomElement(using: &rng) ?? "x"
        let frame = Int.random(in: -1...30, using: &rng)
        let scene = (e.document.scenes.map(\.id) + ["missing"]).randomElement(using: &rng) ?? "missing"
        switch Int.random(in: 0..<11, using: &rng) {
        case 0:
            nextID += 1
            let index = Int.random(in: -2...5, using: &rng)
            try e.perform(AddLayer(sceneID: s, layer: Layer(id: "L\(nextID)", name: "Layer \(nextID)"), index: index))
        case 1:
            try e.perform(RemoveLayer(sceneID: s, layerID: layer))
        case 2:
            try e.perform(RenameLayer(sceneID: s, layerID: layer, name: "n\(frame)"))
        case 3:
            let easing: Easing = Bool.random(using: &rng) ? .linear : .easeInOut
            let k = Keyframe(frame: frame, value: Double.random(in: -100...100, using: &rng), easing: easing)
            try e.perform(SetKeyframe(sceneID: s, layerID: layer, property: prop, keyframe: k))
        case 4:
            try e.perform(MoveKeyframe(sceneID: s, layerID: layer, property: prop,
                                       from: frame, to: Int.random(in: -1...30, using: &rng)))
        case 5:
            try e.perform(RemoveKeyframe(sceneID: s, layerID: layer, property: prop, frame: frame))
        case 7:
            nextID += 1
            let id = Bool.random(using: &rng) ? scene : "S\(nextID)"
            let fps = Int.random(in: -1...60, using: &rng)
            try e.perform(AddScene(scene: Scene(id: id, name: "Scene \(nextID)", fps: fps, durationFrames: frame),
                                   index: Int.random(in: -2...5, using: &rng)))
        case 8:
            try e.perform(RemoveScene(sceneID: scene))
        case 9:
            try e.perform(SetSceneTiming(sceneID: scene, fps: Int.random(in: -1...60, using: &rng),
                                         durationFrames: frame))
        case 10:
            let easing: Easing = Bool.random(using: &rng) ? .easeIn : .linear
            try e.perform(SetKeyframeEasing(sceneID: s, layerID: layer, property: prop, frame: frame, easing: easing))
        default:
            let shape = Shape(points: [Point(x: Double(frame), y: 0), Point(x: 1, y: 1)], closed: false)
            try e.perform(AddShape(sceneID: s, layerID: layer, shape: shape))
        }
    }
}
