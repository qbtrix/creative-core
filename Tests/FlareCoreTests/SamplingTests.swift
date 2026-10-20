import Testing
@testable import FlareCore

struct SamplingTests {
    private func ball() throws -> Layer {
        let layers = Fixtures.document().scenes.first?.layers ?? []
        return try #require(layers.first(where: { $0.id == "ball" }))
    }

    @Test func fixtureBallAtFrames() throws {
        let layer = try ball()
        let expected = Easing.easeInOut.value(at: 0.5) * 100
        for (frame, x) in [(0.0, 0.0), (12.0, expected), (24.0, 100.0)] {
            let s = layer.sample(at: frame)
            #expect(abs((s["x"] ?? .nan) - x) < 1e-9)
            #expect(s["y"] == 0)
            #expect(s["scaleX"] == 1)
            #expect(s["scaleY"] == 1)
            #expect(s["rotation"] == 0)
            #expect(s["opacity"] == 1)
            #expect(s.count == 8)
        }
    }

    @Test func emptyLayerReturnsDefaults() {
        let s = Layer(id: "e", name: "Empty").sample(at: 5)
        #expect(s == ["x": 0, "y": 0, "scaleX": 1, "scaleY": 1, "rotation": 0, "opacity": 1, "anchorX": 0, "anchorY": 0])
    }

    @Test func opacityIsClamped() {
        let high = Layer(id: "o", name: "O", tracks: ["opacity": [Keyframe(frame: 0, value: 1.5)]])
        #expect(high.sample(at: 0)["opacity"] == 1)
        let low = Layer(id: "o", name: "O", tracks: ["opacity": [Keyframe(frame: 0, value: -0.5)]])
        #expect(low.sample(at: 0)["opacity"] == 0)
    }

    @Test func customTracksAreIncluded() {
        let layer = Layer(id: "c", name: "C", tracks: ["blur": [Keyframe(frame: 0, value: 0), Keyframe(frame: 10, value: 10)]])
        #expect(layer.sample(at: 5)["blur"] == 5)
    }

    @Test func nonFiniteFrameGivesDefaults() throws {
        #expect(try ball().sample(at: .nan) == Layer.standardDefaults)
    }
}
