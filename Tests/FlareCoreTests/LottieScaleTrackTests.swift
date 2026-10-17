import Foundation
import Testing
@testable import FlareCore

/// Animated `scaleX` / `scaleY` tracks become one animated 2-D `ks.s`.
struct LottieScaleTrackTests {
    private func exported(_ tracks: [String: [Keyframe]], frames: Int = 48) throws -> String {
        let layer = Layer(id: "a", name: "A", tracks: tracks)
        let scene = Scene(id: "s", name: "S", durationFrames: frames, layers: [layer])
        return try #require(String(data: try LottieExporter.export(scene: scene), encoding: .utf8))
    }

    /// The decoded `ks.s` of the only layer.
    private func scale(_ tracks: [String: [Keyframe]], frames: Int = 48) throws -> [String: Any] {
        let data = try #require(try exported(tracks, frames: frames).data(using: .utf8))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let layer = try #require((root["layers"] as? [[String: Any]])?.first)
        return try #require((layer["ks"] as? [String: Any])?["s"] as? [String: Any])
    }

    private func keys(_ property: [String: Any]) throws -> [[String: Any]] {
        #expect(property["a"] as? Int == 1)
        return try #require(property["k"] as? [[String: Any]])
    }

    @Test func scaleXKeysOnlyFillYWithItsConstant() throws {
        let k = try keys(scale([
            "scaleX": [Keyframe(frame: 0, value: 1), Keyframe(frame: 10, value: 3, easing: .hold),
                       Keyframe(frame: 20, value: 2)],
            "scaleY": [Keyframe(frame: 7, value: 0.5)],
        ]))
        #expect(k.map { $0["t"] as? Int } == [0, 10, 20])
        #expect(k.map { $0["s"] as? [Double] } == [[100, 50], [300, 50], [200, 50]])
        #expect(k[1]["h"] as? Int == 1)
    }

    @Test func scaleYKeysOnlyFillXWithDefault() throws {
        let k = try keys(scale(["scaleY": [Keyframe(frame: 0, value: 1), Keyframe(frame: 10, value: 2)]]))
        #expect(k.map { $0["s"] as? [Double] } == [[100, 100], [100, 200]])
    }

    @Test func sharedFramesAndEasingShareKeys() throws {
        let track = [Keyframe(frame: 0, value: 1, easing: .easeInOut), Keyframe(frame: 24, value: 2)]
        let text = try exported(["scaleX": track, "scaleY": track])
        let golden = #""s":{"a":1,"k":[{"i":{"x":[0.58],"y":[1]},"o":{"x":[0.42],"y":[0]},"s":[100,100],"t":0},{"s":[200,200],"t":24}]}"#
        #expect(text.contains(golden))
    }

    @Test func differentEasingBakesEveryFrame() throws {
        let k = try keys(scale([
            "scaleX": [Keyframe(frame: 0, value: 1, easing: .easeIn), Keyframe(frame: 4, value: 2)],
            "scaleY": [Keyframe(frame: 0, value: 1), Keyframe(frame: 4, value: 2)],
        ]))
        #expect(k.map { $0["t"] as? Int } == [0, 1, 2, 3, 4])
    }

    @Test func differentFramesBakeOneLinearKeyPerFrame() throws {
        let tracks: [String: [Keyframe]] = [
            "scaleX": [Keyframe(frame: 2, value: 1, easing: .easeOut), Keyframe(frame: 12, value: 3)],
            "scaleY": [Keyframe(frame: 5, value: 0.5), Keyframe(frame: 9, value: 2, easing: .hold),
                       Keyframe(frame: 15, value: 1)],
        ]
        let layer = Layer(id: "a", name: "A", tracks: tracks)
        let k = try keys(scale(tracks))
        #expect(k.map { $0["t"] as? Int } == Array(2...15))
        for key in k {
            let t = try #require(key["t"] as? Int)
            let s = layer.sample(at: Double(t))
            let want = [try #require(s["scaleX"]) * 100, try #require(s["scaleY"]) * 100]
            // JSONSerialization may round the last digit; the encoder writes the exact Double.
            let got = try #require(key["s"] as? [Double])
            #expect(got.count == 2 && zip(got, want).allSatisfy { abs($0 - $1) < 1e-9 })
            if t < 15 {
                #expect((key["o"] as? [String: Any])?["x"] as? [Double] == [0])
                #expect((key["i"] as? [String: Any])?["x"] as? [Double] == [1])
                #expect(key["h"] == nil)
            } else {
                #expect(key["o"] == nil)
            }
        }
    }

    @Test func bakeClampsToSceneRange() throws {
        let k = try keys(scale([
            "scaleX": [Keyframe(frame: -5, value: 1), Keyframe(frame: 100, value: 2)],
            "scaleY": [Keyframe(frame: -2, value: 1), Keyframe(frame: 90, value: 2)],
        ], frames: 10))
        #expect(k.map { $0["t"] as? Int } == Array(0...9))
    }

    @Test func bakeOverMaxBakedKeysThrows() {
        let n = LottieExporter.maxBakedKeys
        #expect(throws: LottieExportError.unsupported("scale track")) {
            _ = try exported([
                "scaleX": [Keyframe(frame: 0, value: 1), Keyframe(frame: n, value: 2)],
                "scaleY": [Keyframe(frame: 1, value: 1), Keyframe(frame: n, value: 2)],
            ], frames: n + 1)
        }
    }

    @Test func bakeOfExactlyMaxBakedKeysIsWritten() throws {
        let n = LottieExporter.maxBakedKeys
        let k = try keys(scale([
            "scaleX": [Keyframe(frame: 0, value: 1), Keyframe(frame: n - 1, value: 2)],
            "scaleY": [Keyframe(frame: 1, value: 1), Keyframe(frame: n - 1, value: 2)],
        ], frames: n))
        #expect(k.count == n)
    }

    @Test func keysPastTheEndOrEmptySceneStayStatic() throws {
        let tracks: [String: [Keyframe]] = [
            "scaleX": [Keyframe(frame: 50, value: 2), Keyframe(frame: 60, value: 3)],
            "scaleY": [Keyframe(frame: 55, value: 4), Keyframe(frame: 60, value: 5)],
        ]
        for frames in [10, 0] {
            let s = try scale(tracks, frames: frames)
            #expect(s["a"] as? Int == 0)
            #expect(s["k"] as? [Double] == [200, 400])
        }
    }

    @Test func extremeFramesDoNotTrap() throws {
        let tracks: [String: [Keyframe]] = [
            "scaleX": [Keyframe(frame: Int.min, value: 1), Keyframe(frame: Int.max, value: 2)],
            "scaleY": [Keyframe(frame: Int.min + 1, value: 1), Keyframe(frame: Int.max, value: 2)],
        ]
        #expect(throws: LottieExportError.unsupported("scale track")) {
            _ = try exported(tracks, frames: Int.max)
        }
        #expect(try keys(scale(tracks, frames: 3)).map { $0["t"] as? Int } == [0, 1, 2])
        let late: [String: [Keyframe]] = [
            "scaleX": [Keyframe(frame: Int.max - 1, value: 1), Keyframe(frame: Int.max, value: 2)],
            "scaleY": [Keyframe(frame: Int.max - 2, value: 1), Keyframe(frame: Int.max, value: 2)],
        ]
        #expect(try scale(late, frames: Int.max)["a"] as? Int == 1)
    }

    @Test func staticScaleKeepsTodaysBytes() throws {
        let text = try exported(["scaleX": [Keyframe(frame: 3, value: 2)]])
        #expect(text.contains(#""s":{"a":0,"k":[200,100]}"#))
    }

    @Test func nonFiniteScaleKeysThrow() {
        for bad in [Double.nan, .infinity] {
            #expect(throws: LottieExportError.nonFiniteValue) {
                _ = try exported(["scaleX": [Keyframe(frame: 0, value: 1), Keyframe(frame: 12, value: bad)]])
            }
            #expect(throws: LottieExportError.nonFiniteValue) {
                _ = try exported([
                    "scaleX": [Keyframe(frame: 0, value: 1), Keyframe(frame: 12, value: 2)],
                    "scaleY": [Keyframe(frame: 3, value: bad), Keyframe(frame: 12, value: 2)],
                ])
            }
        }
    }

    /// A finite scale that overflows when written as a percent throws the
    /// typed error, not the encoder's, on every path: static, one track,
    /// shared keys and the bake.
    @Test func scaleOverflowingTimes100Throws() {
        let big = 1e307
        let ramp = [Keyframe(frame: 0, value: 1), Keyframe(frame: 9, value: 2)]
        let cases: [[String: [Keyframe]]] = [
            ["scaleX": [Keyframe(frame: 0, value: big)]],
            ["scaleY": [Keyframe(frame: 0, value: big)], "scaleX": ramp],
            ["scaleX": [Keyframe(frame: 0, value: 1), Keyframe(frame: 9, value: big)]],
            ["scaleX": [Keyframe(frame: 0, value: 1), Keyframe(frame: 9, value: big)], "scaleY": ramp],
            ["scaleX": [Keyframe(frame: 0, value: 1, easing: .easeIn), Keyframe(frame: 9, value: big)], "scaleY": ramp],
        ]
        for tracks in cases {
            #expect(throws: LottieExportError.nonFiniteValue) { _ = try exported(tracks) }
        }
    }
}
