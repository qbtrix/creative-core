// Support.swift: shared test helpers. A seedable RNG (SplitMix64) so property
// and fuzz tests are reproducible, and a small sample document.
import FlareCore

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
            fill: Color(r: 1, g: 0.5, b: 0.25)
        )
        let ball = Layer(
            id: "ball", name: "Ball", shapes: [square],
            tracks: ["x": [Keyframe(frame: 0, value: 0, easing: .easeInOut), Keyframe(frame: 24, value: 100)]]
        )
        let bg = Layer(id: "bg", name: "Background")
        return Document(scenes: [Scene(id: sceneID, name: "Main", fps: 24, durationFrames: 48, layers: [bg, ball])])
    }
}
