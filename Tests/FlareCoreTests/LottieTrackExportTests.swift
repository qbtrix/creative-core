// LottieTrackExportTests.swift: Lottie writes Fixtures/tracks.flare's fill, stroke, width and path keys (AP-7)
// with `t`, `s` and `o`/`i`, hold as `h: 1`, colours in 0...1, relative tangents, and stable bytes.
import FlareCore
import Foundation
import Testing

@Suite(.disabled("AP-7 turns this on"))
struct LottieTrackExportTests {
    /// The keys of animated property `property` (`a` is 1) on the shape group's item of type `type`.
    static func keys(_ type: String, _ property: String) throws -> [[String: Any]] {
        let json = try #require(try JSONSerialization.jsonObject(with: LottieExporter.export(scene: TrackCommandsTests.fixtureScene())) as? [String: Any])
        let group = try #require(((json["layers"] as? [[String: Any]])?.first?["shapes"] as? [[String: Any]])?.first)
        let item = try #require((group["it"] as? [[String: Any]])?.first { $0["ty"] as? String == type })
        let animated = try #require(item[property] as? [String: Any])
        #expect(animated["a"] as? Int == 1)
        return try #require(animated["k"] as? [[String: Any]])
    }

    @Test func fillColourKeys() throws {
        let keys = try Self.keys("fl", "c")
        #expect(keys.map { $0["t"] as? Int } == [0, 24] && keys.map { $0["s"] as? [Double] } == [[1, 0, 0, 1], [0, 0, 1, 1]])
        let o = try #require(keys[0]["o"] as? [String: Any]), i = try #require(keys[0]["i"] as? [String: Any])
        #expect(o["x"] as? [Double] == [0.42] && o["y"] as? [Double] == [0] && i["x"] as? [Double] == [0.58] && i["y"] as? [Double] == [1])
    }

    @Test func colourUnitRange() throws {
        let values = try (Self.keys("fl", "c") + Self.keys("st", "c")).flatMap { $0["s"] as? [Double] ?? [] }
        #expect(values.count == 16 && values.allSatisfy { (0...1).contains($0) })
    }

    @Test func strokeHoldAndWidth() throws {
        let (colour, width) = (try Self.keys("st", "c"), try Self.keys("st", "w"))
        #expect(colour.map { $0["s"] as? [Double] } == [[0, 0, 0, 1], [1, 1, 1, 1]] && colour[0]["h"] as? Int == 1 && colour[0]["o"] == nil)
        #expect(width.map { $0["t"] as? Int } == [0, 24] && width.map { $0["s"] as? [Double] } == [[2], [8]])
    }

    @Test func tangentsRelative() throws {
        let keys = try Self.keys("sh", "ks")
        let first = try #require((keys.first?["s"] as? [[String: Any]])?.first)
        #expect(first["v"] as? [[Double]] == [[0, 0], [20, 0], [40, 0], [40, 20], [40, 40], [20, 40], [0, 40], [0, 20]])
        // Straight sides: each tangent is the zero offset from its vertex, not the vertex itself.
        #expect(first["i"] as? [[Double]] == Array(repeating: [0, 0], count: 8) && first["o"] as? [[Double]] == Array(repeating: [0, 0], count: 8))
        #expect(first["c"] as? Bool == true && keys.map { $0["t"] as? Int } == [0, 24])
    }

    @Test func byteStable() throws {
        let scene = try TrackCommandsTests.fixtureScene()
        #expect(try LottieExporter.export(scene: scene) == LottieExporter.export(scene: scene))
    }
}
