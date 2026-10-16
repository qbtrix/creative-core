// LottieGradientAlphaTests.swift: a gradient's stop alpha is written as
// `[offset, alpha]` stops after the color stops, only when some stop is under
// 1. An opaque gradient keeps today's bytes (MT-4, #227).
import Foundation
import Testing
@testable import FlareCore

struct LottieGradientAlphaTests {
    private static let square = [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 1, y: 1)]

    /// A linear and a radial fill over `stops`.
    private static func fills(_ stops: [GradientStop]) -> [Fill] {
        [.linear(stops: stops, start: Point(x: 0, y: 0), end: Point(x: 4, y: 0)),
         .radial(stops: stops, center: Point(x: 2, y: 3), radius: 5)]
    }

    private func exported(_ fill: Fill) throws -> String {
        let layer = Layer(id: "a", name: "A", shapes: [Shape(points: Self.square, fill: fill)])
        let scene = Scene(id: "s", name: "S", layers: [layer])
        return try #require(String(data: try LottieExporter.export(scene: scene), encoding: .utf8))
    }

    /// The gradient `g` of a one-shape scene's fill, as `p` and the flat `k`.
    private func gradient(_ fill: Fill) throws -> (p: Int, k: [Double]) {
        let layer = Layer(id: "a", name: "A", shapes: [Shape(points: Self.square, fill: fill)])
        let data = try LottieExporter.export(scene: Scene(id: "s", name: "S", layers: [layer]))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let layers = try #require(json["layers"] as? [[String: Any]])
        let shapes = try #require(layers.first?["shapes"] as? [[String: Any]])
        let items = try #require(shapes.first?["it"] as? [[String: Any]])
        let g = try #require(items[1]["g"] as? [String: Any])
        return (try #require(g["p"] as? Int), try #require((g["k"] as? [String: Any])?["k"] as? [Double]))
    }

    private static let translucent = [
        GradientStop(offset: 0, color: .black),
        GradientStop(offset: 1, color: Color(r: 1, g: 1, b: 1, a: 0.25)),
    ]

    @Test func translucentStopWritesAlphaStopsAfterColors() throws {
        let golden = #""g":{"k":{"a":0,"k":[0,0,0,0,1,1,1,1,0,1,1,0.25]},"p":2}"#
        for fill in Self.fills(Self.translucent) {
            #expect(try exported(fill).contains(golden))
        }
    }

    @Test func opaqueGradientKeepsTodaysBytes() throws {
        let opaque = [GradientStop(offset: 0, color: .black), GradientStop(offset: 1, color: .white)]
        for fill in Self.fills(opaque) {
            #expect(try exported(fill).contains(#""g":{"k":{"a":0,"k":[0,0,0,0,1,1,1,1]},"p":2}"#))
        }
    }

    @Test func alphaAboveOneClampsAndStaysOpaque() throws {
        let stops = [GradientStop(offset: 0, color: .black),
                     GradientStop(offset: 1, color: Color(r: 1, g: 1, b: 1, a: 1.5))]
        for fill in Self.fills(stops) {
            #expect(try exported(fill).contains(#""g":{"k":{"a":0,"k":[0,0,0,0,1,1,1,1]},"p":2}"#))
        }
    }

    @Test func seededStopsWriteOneAlphaPairPerStop() throws {
        var rng = SplitMix64(seed: 0x4D54_34)
        for _ in 0..<50 {
            let count = Int.random(in: 2...6, using: &rng)
            let stops = (0..<count).map { index in
                GradientStop(offset: Double(index) / Double(count - 1), color: Color(
                    r: Double.random(in: 0...1, using: &rng), g: Double.random(in: 0...1, using: &rng),
                    b: Double.random(in: 0...1, using: &rng), a: Double.random(in: 0..<1, using: &rng)))
            }
            let (p, k) = try gradient(.linear(stops: stops, start: Point(x: 0, y: 0), end: Point(x: 1, y: 0)))
            #expect(p == count)
            #expect(k.count == 6 * count)
            guard k.count == 6 * count else { continue }
            // JSON parsing on Linux can differ from the source double by an ulp.
            for (index, stop) in stops.enumerated() {
                #expect(abs(k[4 * count + 2 * index] - stop.offset) < 1e-12)
                #expect(abs(k[4 * count + 2 * index + 1] - stop.color.a) < 1e-12)
            }
        }
    }

    @Test func nonFiniteAlphaThrows() {
        let stops = [GradientStop(offset: 0, color: .black),
                     GradientStop(offset: 1, color: Color(r: 1, g: 1, b: 1, a: .nan))]
        for fill in Self.fills(stops) {
            #expect(throws: LottieExportError.nonFiniteValue) { _ = try exported(fill) }
        }
    }
}
