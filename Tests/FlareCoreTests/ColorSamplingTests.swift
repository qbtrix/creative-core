// ColorSamplingTests.swift: colour tracks sample (AP-5) in encoded sRGB with the left key's easing; hold
// keeps the left key; the ends hold outside the keys; an empty or missing track is nil.
import FlareCore
import Testing

@Suite(.disabled("AP-5 turns this on"))
struct ColorSamplingTests {
    static let (red, blue) = (Color(r: 1, g: 0, b: 0), Color(r: 0, g: 0, b: 1))

    /// fill.0 of a layer: red at `from` (under `easing`) to blue at `to`.
    static func sample(_ easing: Easing, at frame: Double, from: Int = 0, to: Int = 24) -> Color? {
        let keys = [ColorKeyframe(frame: from, value: red, easing: easing), ColorKeyframe(frame: to, value: blue)]
        return Layer(id: "l", name: "L", colorTracks: ["fill.0": keys]).sampledColor(.fill(shape: 0), at: frame)
    }

    static func close(_ a: Color?, _ b: Color) -> Bool {
        a.map { a in [a.r - b.r, a.g - b.g, a.b - b.b, a.a - b.a].allSatisfy { abs($0) <= 1e-12 } } ?? false
    }

    @Test func encodedComponents() {
        // Encoded sRGB: the midpoint is (0.5, 0, 0.5), not a linear-light blend.
        #expect(Self.close(Self.sample(.linear, at: 12), Color(r: 0.5, g: 0, b: 0.5)))
        #expect(Self.sample(.easeInOut, at: 0) == Self.red && Self.sample(.easeInOut, at: 24) == Self.blue)
    }

    @Test func easingApplies() {
        let t = Easing.easeInOut.value(at: 0.25)
        #expect(Self.close(Self.sample(.easeInOut, at: 6), Color(r: 1 - t, g: 0, b: t)))
        #expect(!Self.close(Self.sample(.easeInOut, at: 6), Color(r: 0.75, g: 0, b: 0.25)))
    }

    @Test func holdKeepsLeft() {
        #expect([0.0, 1, 12, 23.5].allSatisfy { Self.sample(.hold, at: $0) == Self.red })
        #expect(Self.sample(.hold, at: 24) == Self.blue)
    }

    @Test func endsHold() {
        #expect([-3.0, 0, 6].allSatisfy { Self.sample(.linear, at: $0, from: 6, to: 18) == Self.red })
        #expect([18.0, 24, 1000].allSatisfy { Self.sample(.linear, at: $0, from: 6, to: 18) == Self.blue })
    }

    @Test func emptyIsNil() throws {
        var layer = try #require(try TrackCommandsTests.fixtureScene().layers.first)
        #expect(layer.sampledColor(.stroke(shape: 0), at: 12) == Color(r: 0, g: 0, b: 0))
        #expect(layer.sampledColor(.fill(shape: 1), at: 12) == nil && layer.sampledColor(.text(index: 0), at: 12) == nil)
        layer.colorTracks["fill.0"] = []
        #expect(layer.sampledColor(.fill(shape: 0), at: 12) == nil)
    }
}
