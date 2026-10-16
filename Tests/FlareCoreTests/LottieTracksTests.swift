import Foundation
import Testing
@testable import FlareCore

/// Animated opacity and rotation tracks become animated `ks.o` and `ks.r`.
struct LottieTracksTests {
    private func exported(_ tracks: [String: [Keyframe]]) throws -> String {
        let layer = Layer(id: "a", name: "A", tracks: tracks)
        let scene = Scene(id: "s", name: "S", layers: [layer])
        return try #require(String(data: try LottieExporter.export(scene: scene), encoding: .utf8))
    }

    @Test func opacityKeysAnimateWithEasingTangents() throws {
        let text = try exported(["opacity": [
            Keyframe(frame: 0, value: 1, easing: .easeInOut), Keyframe(frame: 24, value: 0),
        ]])
        let golden = #""o":{"a":1,"k":[{"i":{"x":[0.58],"y":[1]},"o":{"x":[0.42],"y":[0]},"s":[100],"t":0},{"s":[0],"t":24}]}"#
        #expect(text.contains(golden))
    }

    @Test func rotationHoldKeyWritesH() throws {
        let text = try exported(["rotation": [
            Keyframe(frame: 0, value: 0), Keyframe(frame: 12, value: 45, easing: .hold),
            Keyframe(frame: 24, value: 90),
        ]])
        let golden = #""r":{"a":1,"k":[{"i":{"x":[1],"y":[1]},"o":{"x":[0],"y":[0]},"s":[0],"t":0},{"h":1,"s":[45],"t":12},{"s":[90],"t":24}]}"#
        #expect(text.contains(golden))
    }

    @Test func opacityKeysOutsideUnitRangeClamp() throws {
        let text = try exported(["opacity": [
            Keyframe(frame: 0, value: 1.5, easing: .hold), Keyframe(frame: 10, value: -0.5),
        ]])
        #expect(text.contains(#""o":{"a":1,"k":[{"h":1,"s":[100],"t":0},{"s":[0],"t":10}]}"#))
    }

    @Test func singleKeysStayStatic() throws {
        let text = try exported([
            "opacity": [Keyframe(frame: 5, value: 0.25)], "rotation": [Keyframe(frame: 5, value: 30)],
        ])
        #expect(text.contains(#""o":{"a":0,"k":25},"p":{"a":0,"k":[0,0]},"r":{"a":0,"k":30}"#))
    }

    @Test func nonFiniteKeysThrow() {
        for bad in [Double.nan, .infinity] {
            #expect(throws: LottieExportError.nonFiniteValue) {
                _ = try exported(["opacity": [Keyframe(frame: 0, value: 1), Keyframe(frame: 12, value: bad)]])
            }
            #expect(throws: LottieExportError.nonFiniteValue) {
                _ = try exported(["rotation": [Keyframe(frame: 0, value: bad), Keyframe(frame: 12, value: 0)]])
            }
        }
    }
}
