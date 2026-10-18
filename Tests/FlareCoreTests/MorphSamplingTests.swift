// MorphSamplingTests.swift: shape tracks morph anchor by anchor (AP-6): a key's frame draws that key exactly,
// anchors and handles move by the eased progress, and a line's missing handles lerp as its points.
import FlareCore
import Testing

struct MorphSamplingTests {
    static func p(_ x: Double, _ y: Double) -> Point { Point(x: x, y: y) }
    static func near(_ a: Point, _ b: Point) -> Bool { abs(a.x - b.x) <= 1e-12 && abs(a.y - b.y) <= 1e-12 }

    static func layer(_ keys: [PathKeyframe]) -> Layer { Layer(id: "l", name: "L", shapeTracks: [ShapeTrack(shapeIndex: 0, keys: keys)]) }

    @Test func keyFrameIsExact() {
        // Coordinates that are not dyadic and shrink from the first key to the second, so a + (b - a) * 1
        // rounds away from b: the previous segment's end at frame 7 is not key 7 bit for bit.
        let paths = [1.3, 0.1, 0.7].map { s in Path(polyline: [Self.p(s, 0.3), Self.p(10.1 * s, 0.7), Self.p(3.3, 9.9 * s)], closed: true) }
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

    @Test func easingShapesTheMorph() throws {
        let a = Path(polyline: [Self.p(0, 0), Self.p(10, 0), Self.p(10, 10)], closed: true)
        let b = Path(polyline: [Self.p(4, 8), Self.p(30, 2), Self.p(20, 40)], closed: true)
        let layer = Self.layer([PathKeyframe(frame: 0, path: a, easing: .easeInOut), PathKeyframe(frame: 24, path: b)])
        let t = Easing.easeInOut.value(at: 0.25)
        let mid = try #require(layer.sampledPath(shape: 0, at: 6))
        #expect(t != 0.25 && mid.elements.count == a.elements.count)
        for (m, (ea, eb)) in zip(mid.elements, zip(a.elements, b.elements)) {
            switch (m, ea, eb) {
            case (.move(let q), .move(let pa), .move(let pb)), (.line(let q), .line(let pa), .line(let pb)):
                #expect(Self.near(q, Self.p(pa.x + (pb.x - pa.x) * t, pa.y + (pb.y - pa.y) * t)), "\(q)")
            case (.close, .close, .close): break
            default: Issue.record("unpaired \(m)")
            }
        }
    }

    @Test func quadElevatesToCubic() {
        // Two quads morph as quads, so pair the quad with the cubic that draws it: the quad is elevated to
        // handles p + 2/3(c - p) and to + 2/3(c - to), (2, 4) and (4, 4), so every frame between draws those.
        let quad = Path(elements: [.move(to: Self.p(0, 0)), .quad(control: Self.p(3, 6), to: Self.p(6, 0))])
        let cubic = Path(elements: [.move(to: Self.p(0, 0)), .cubic(control1: Self.p(2, 4), control2: Self.p(4, 4), to: Self.p(6, 0))])
        let mid = Self.layer([PathKeyframe(frame: 0, path: quad), PathKeyframe(frame: 10, path: cubic)]).sampledPath(shape: 0, at: 5)
        guard case .cubic(let c1, let c2, let to) = mid?.elements.last else { Issue.record("not a cubic: \(String(describing: mid))"); return }
        #expect(Self.near(c1, Self.p(2, 4)) && Self.near(c2, Self.p(4, 4)) && Self.near(to, Self.p(6, 0)))
    }

    @Test func quadsLerpAsQuads() {
        // Two quads stay a quad: the control and the end both move by t, so the midpoint control is (5, 5).
        let a = Path(elements: [.move(to: Self.p(0, 0)), .quad(control: Self.p(0, 10), to: Self.p(10, 0))])
        let b = Path(elements: [.move(to: Self.p(0, 0)), .quad(control: Self.p(10, 0), to: Self.p(10, 0))])
        let layer = Self.layer([PathKeyframe(frame: 0, path: a), PathKeyframe(frame: 10, path: b)])
        #expect(layer.sampledPath(shape: 0, at: 5)?.elements.last == .quad(control: Self.p(5, 5), to: Self.p(10, 0)))
    }

    @Test func unpairedKeysHoldTheLeftKey() {
        // A file can hold keys AP-4 never made compatible: a different count, or a close against a line.
        let tri = Path(polyline: [Self.p(0, 0), Self.p(4, 0), Self.p(0, 4)], closed: true)
        let open = Path(polyline: [Self.p(0, 0), Self.p(4, 0), Self.p(0, 4), Self.p(2, 2)], closed: false)
        let quad = Path(polyline: [Self.p(0, 0), Self.p(8, 0), Self.p(8, 8), Self.p(0, 8)], closed: true)
        #expect([open, quad].allSatisfy { Self.layer([PathKeyframe(frame: 0, path: tri), PathKeyframe(frame: 10, path: $0)]).sampledPath(shape: 0, at: 5) == tri })
        #expect(Self.layer([PathKeyframe(frame: 0, path: tri)]).sampledPath(shape: 0, at: .nan) == nil)
    }

    @Test func emptyIsNil() { #expect(Self.layer([]).sampledPath(shape: 0, at: 0) == nil && Layer(id: "l", name: "L").sampledPath(shape: 0, at: 0) == nil) }
}
