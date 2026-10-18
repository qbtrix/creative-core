// MorphSamplingTests.swift: shape tracks morph anchor by anchor (AP-6): a key's frame draws that key exactly,
// anchors and handles move by the eased progress, and a line's missing handles lerp as its points.
import FlareCore
import Testing

struct MorphSamplingTests {
    static func p(_ x: Double, _ y: Double) -> Point { Point(x: x, y: y) }
    static func near(_ a: Point, _ b: Point) -> Bool { abs(a.x - b.x) <= 1e-12 && abs(a.y - b.y) <= 1e-12 }

    static func layer(_ keys: [PathKeyframe]) -> Layer { Layer(id: "l", name: "L", shapeTracks: [ShapeTrack(shapeIndex: 0, keys: keys)]) }

    @Test func keyFrameIsExact() {
        // Coordinates that are not dyadic, so a blend at a key frame shows.
        let paths = [0.1, 0.7, 1.3].map { s in Path(polyline: [Self.p(s, 0.3), Self.p(10.1 * s, 0.7), Self.p(3.3, 9.9 * s)], closed: true) }
        let layer = Self.layer(zip([0, 7, 24], paths).map { PathKeyframe(frame: $0, path: $1, easing: .easeInOut) })
        #expect(zip([0.0, 7, 24], paths).allSatisfy { layer.sampledPath(shape: 0, at: $0) == $1 })
    }

    @Test func midpointHalfway() throws {
        let layer = try #require(try TrackCommandsTests.fixtureScene().layers.first)
        let (a, b) = try #require(layer.shapeTracks.first.map { ($0.keys[0].path, $0.keys[1].path) })
        let mid = try #require(layer.sampledPath(shape: 0, at: 12))
        let anchors = { (path: Path) in path.elements.compactMap { if case .move(let q) = $0 { q } else if case .line(let q) = $0 { q } else { nil } } }
        // Every anchor is halfway: the corners move in to (7.5, 7.5) and the edge midpoints stay put.
        #expect(mid.elements.count == 9 && anchors(mid) == zip(anchors(a), anchors(b)).map { Self.p(($0.x + $1.x) / 2, ($0.y + $1.y) / 2) })
        #expect(mid.elements.prefix(2) == [.move(to: Self.p(7.5, 7.5)), .line(to: Self.p(20, 0))])
    }

    @Test func handlesLerp() throws {
        let arch = Path(elements: [.move(to: Self.p(0, 0)), .cubic(control1: Self.p(0, 10), control2: Self.p(10, 10), to: Self.p(10, 0))])
        let flat = Path(elements: [.move(to: Self.p(0, 0)), .cubic(control1: Self.p(4, 2), control2: Self.p(6, 2), to: Self.p(10, 0))])
        let cubic = Self.layer([PathKeyframe(frame: 0, path: arch), PathKeyframe(frame: 10, path: flat)])
        #expect(cubic.sampledPath(shape: 0, at: 5)?.elements.last == .cubic(control1: Self.p(2, 6), control2: Self.p(8, 6), to: Self.p(10, 0)))
        // A line has no handles: they count as the points it joins, (0, 0) and (10, 0).
        let line = Path(elements: [.move(to: Self.p(0, 0)), .line(to: Self.p(10, 0))])
        let mid = Self.layer([PathKeyframe(frame: 0, path: line), PathKeyframe(frame: 10, path: arch)]).sampledPath(shape: 0, at: 5)
        guard case .cubic(let c1, let c2, let to) = mid?.elements.last else { Issue.record("not a cubic: \(String(describing: mid))"); return }
        #expect(Self.near(c1, Self.p(0, 5)) && Self.near(c2, Self.p(10, 5)) && Self.near(to, Self.p(10, 0)))
    }

    @Test func emptyIsNil() { #expect(Self.layer([]).sampledPath(shape: 0, at: 0) == nil && Layer(id: "l", name: "L").sampledPath(shape: 0, at: 0) == nil) }
}
