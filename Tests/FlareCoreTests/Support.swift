// Support.swift: shared test helpers. A seedable RNG (SplitMix64) so property
// and fuzz tests are reproducible, and a small sample document.
import FlareCore
import Testing

/// SplitMix64: tiny, fast, seedable. Same seed, same sequence, on every platform.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum Fixtures {
    static let sceneID = "s1"

    static func document() -> Document {
        let square = Shape(
            points: [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10), Point(x: 0, y: 10)],
            fill: .solid(Color(r: 1, g: 0.5, b: 0.25))
        )
        let ball = Layer(
            id: "ball", name: "Ball", shapes: [square],
            tracks: ["x": [Keyframe(frame: 0, value: 0, easing: .easeInOut), Keyframe(frame: 24, value: 100)]]
        )
        let bg = Layer(id: "bg", name: "Background")
        return Document(scenes: [Scene(id: sceneID, name: "Main", fps: 24, durationFrames: 48, layers: [bg, ball],
                                      labels: ["start": 0])])
    }
}

/// One random command step for `assertUndoRestoresDocument`: performs one
/// command on the engine, with valid or invalid params. `nextID` makes fresh ids.
typealias UndoStep = @Sendable (inout CommandEngine, inout SplitMix64, inout Int) throws -> Void

/// Runs `length` random steps (some grouped, some invalid) from `start`, then
/// checks that a failed step left the document untouched, every step left a
/// valid document, undo-all gives back `start` and redo-all gives back the
/// final document. Each command family's
/// test file calls this with its own steps; UndoPropertyTests mixes them all.
func assertUndoRestoresDocument(seed: UInt64, steps: [UndoStep], start: Document = Fixtures.document(),
                                length: Int = 40) throws {
    var rng = SplitMix64(seed: seed)
    var engine = CommandEngine(document: start)
    var nextID = 0
    func step(_ e: inout CommandEngine) throws {
        guard let s = steps.randomElement(using: &rng) else { return }
        try s(&e, &rng, &nextID)
    }

    for _ in 0..<length {
        if Int.random(in: 0..<8, using: &rng) == 0 {
            // A group of 2-4 commands; a failure inside rolls the group back.
            try? engine.group("Batch") { e in
                for _ in 0..<Int.random(in: 2...4, using: &rng) { try step(&e) }
            }
        } else {
            let before = engine.document
            do {
                try step(&engine)
            } catch {
                #expect(engine.document == before, "failed command mutated the document")
            }
        }
        // perform validates (scoped for a LayerCommand); the full check must agree.
        #expect(throws: Never.self) { try FlareFormat.validate(engine.document) }
    }

    let final = engine.document
    var undos = 0
    while engine.canUndo { try engine.undo(); undos += 1 }
    #expect(engine.document == start)
    for _ in 0..<undos { try engine.redo() }
    #expect(engine.document == final)
}
