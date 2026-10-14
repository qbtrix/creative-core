// HitQueryTests.swift: RenderList.hit picks the topmost unlocked, non-text
// item under a point, adds the tolerance once, keeps the instance chain in
// the address, refuses bad tolerances, and at tolerance 0 agrees with
// Layer.hits on 200 seeded points. Stroke reach scales by the larger axis and
// the fill rule is forwarded. The world-bounds prefilter never changes
// the answer of a brute-force scan of the exact per-item test.
import FlareCore
import Testing

@Suite struct HitQueryTests {
    static func square(at x: Double) -> Shape {
        Shape(points: [Point(x: x, y: 0), Point(x: x + 10, y: 0), Point(x: x + 10, y: 10), Point(x: x, y: 10)])
    }

    static func list(_ layers: [Layer]) -> RenderList {
        Scene(id: "s", name: "S", layers: layers).renderList(at: 0, symbols: [])
    }

    static func scaled(_ s: Double) -> [String: [Keyframe]] {
        ["scaleX": [Keyframe(frame: 0, value: s)], "scaleY": [Keyframe(frame: 0, value: s)]]
    }

    @Test func toleranceAddsOnceToAZeroWidthStroke() {
        let line = Shape(points: [Point(x: 0, y: 0), Point(x: 100, y: 0)], closed: false, stroke: Stroke(width: 0))
        let list = Self.list([Layer(id: "l", name: "L", shapes: [line])])
        let hit = list.hit(Point(x: 50, y: 4), tolerance: 4)
        #expect(hit?.layerID == "l" && hit?.shapeIndex == 0)
        #expect(list.hit(Point(x: 50, y: 4), tolerance: 3.9) == nil)
        #expect(list.hit(Point(x: 50, y: 4)) == nil)
        // A 2-wide stroke under scale 2 reaches 2 more: 6 is in, 6.1 is out.
        let wide = Shape(points: line.points, closed: false, stroke: Stroke(width: 2))
        let scaled = Self.list([Layer(id: "w", name: "W", shapes: [wide], tracks: Self.scaled(2))])
        #expect(scaled.hit(Point(x: 50, y: 6), tolerance: 4)?.layerID == "w")
        #expect(scaled.hit(Point(x: 50, y: 6.1), tolerance: 4) == nil)
    }

    @Test func nonUniformScaleWidensStrokeByLargerAxis() {
        // A 2-wide stroke under scaleY 3 is 3 deep each side; tolerance 1 makes the reach 4.
        let line = Shape(points: [Point(x: 0, y: 0), Point(x: 100, y: 0)], closed: false, stroke: Stroke(width: 2))
        let tracks = ["scaleX": [Keyframe(frame: 0, value: 1)], "scaleY": [Keyframe(frame: 0, value: 3)]]
        let list = Self.list([Layer(id: "l", name: "L", shapes: [line], tracks: tracks)])
        #expect(list.hit(Point(x: 50, y: 3.9), tolerance: 1)?.layerID == "l")
        #expect(list.hit(Point(x: 50, y: 4.1), tolerance: 1) == nil)
    }

    @Test func evenOddRuleIsForwarded() {
        let star = Self.list([Layer(id: "star", name: "Star", shapes: [HitTestTests.star])])
        let centre = Point(x: 0, y: 0)
        #expect(star.hit(centre)?.layerID == "star")
        #expect(star.hit(centre, rule: .evenOdd) == nil)
    }

    @Test func laterOfTwoOverlappingSquaresWins() {
        let list = Self.list([Layer(id: "a", name: "A", shapes: [Self.square(at: 0)]),
                              Layer(id: "b", name: "B", shapes: [Self.square(at: 5)])])
        #expect(list.hit(Point(x: 7, y: 5))?.layerID == "b")
        #expect(list.hit(Point(x: 2, y: 5))?.layerID == "a")
        #expect(list.hit(Point(x: 20, y: 5)) == nil)
    }

    @Test func lockedTextAndHiddenAreSkipped() {
        let base = Layer(id: "base", name: "Base", shapes: [Self.square(at: 0)])
        let locked = Layer(id: "locked", name: "Locked", shapes: [Self.square(at: 0)], isLocked: true)
        let hidden = Layer(id: "hidden", name: "Hidden", shapes: [Self.square(at: 0)], isVisible: false)
        let text = Layer(id: "text", name: "Text", texts: [
            TextShape(string: "Hi", fontFamily: "Serif", fontSize: 12, position: Point(x: 5, y: 5)),
        ])
        #expect(Self.list([base, locked, hidden, text]).hit(Point(x: 5, y: 5), tolerance: 1)?.layerID == "base")
        #expect(Self.list([base, text, locked]).hit(Point(x: 5, y: 5))?.layerID == "base")
        #expect(Self.list([hidden]).hit(Point(x: 5, y: 5), tolerance: 1) == nil)
        #expect(Self.list([locked, text]).hit(Point(x: 5, y: 5), tolerance: 1) == nil)
    }

    @Test func nestedHitKeepsTheHostsChain() throws {
        var scene = NestedScene.scene()
        scene.layers[3].isLocked = false
        let list = scene.renderList(at: 0, symbols: NestedScene.symbols)
        // Inner (2.5, 1) maps to (7, 5): y 3, scale 2, rotate 90, x 5, x 10; over the outer square.
        let hit = try #require(list.hit(Point(x: 7, y: 5)))
        #expect(hit.owner == .scene("s") && hit.layerID == "innerLayer" && hit.shapeIndex == 0)
        #expect(RenderListTests.key(hit) == "scene s|host:0>outerLayer:0|innerLayer|s0")
        // With the host locked, as built, the same point falls through to "main" below.
        #expect(NestedScene.list.hit(Point(x: 7, y: 5))?.layerID == "main")
    }

    @Test func badToleranceIsNil() {
        let list = Self.list([Layer(id: "a", name: "A", shapes: [Self.square(at: 0)])])
        for tolerance in [-1, -0.001, .nan, .infinity] {
            #expect(list.hit(Point(x: 5, y: 5), tolerance: tolerance) == nil)
        }
        #expect(list.hit(Point(x: 5, y: 5), tolerance: 0) != nil)
    }

    @Test func zeroScaleItemIsSkipped() {
        let flat = Layer(id: "flat", name: "Flat", shapes: [Self.square(at: 0)], tracks: Self.scaled(0))
        let list = Self.list([Layer(id: "a", name: "A", shapes: [Self.square(at: 0)]), flat])
        #expect(list.hit(Point(x: 0, y: 0), tolerance: 2)?.layerID == "a")
    }

    @Test func agreesWithLayerHitsAtToleranceZero() {
        var scene = NestedScene.scene()
        scene.layers[3].isLocked = false
        let symbols = NestedScene.symbols
        let list = scene.renderList(at: 0, symbols: symbols)
        var rng = SplitMix64(seed: 0x5347_3300)
        var hits = 0
        for _ in 0..<200 {
            let p = Point(x: Double.random(in: -5...25, using: &rng), y: Double.random(in: -5...25, using: &rng))
            let expected = scene.layers.contains { $0.hits(p, at: 0, symbols: symbols, rule: .nonZero) }
            #expect((list.hit(p) != nil) == expected, "\(p)")
            if expected { hits += 1 }
        }
        #expect(hits > 20 && hits < 180)
    }

    /// The exact per-item test of `RenderList.hit`, without the bounds prefilter.
    static func bruteForceHit(_ list: RenderList, _ p: Point, tolerance: Double) -> RenderAddress? {
        for item in list.items.reversed() where !item.isLocked && !item.isText {
            guard let inverse = try? item.matrix.inverted() else { continue }
            if Shape(points: [], path: item.outline, stroke: item.stroke).hits(inverse.apply(p), rule: .nonZero) {
                return item.address
            }
            guard tolerance > 0 else { continue }
            let m = item.matrix
            let scale = max(m.a * m.a + m.b * m.b, m.c * m.c + m.d * m.d).squareRoot()
            let width = item.stroke?.width ?? 0
            let reach = tolerance + (width.isFinite && width > 0 ? width / 2 * scale : 0)
            guard let lines = try? item.outline.transformed(by: m).flattened(tolerance: max(tolerance / 8, 1e-3)) else {
                continue
            }
            for line in lines {
                for (a, b) in zip(line, line.dropFirst()) where segmentDistance(p, a, b) <= reach { return item.address }
            }
        }
        return nil
    }

    static func segmentDistance(_ p: Point, _ a: Point, _ b: Point) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        let t = lengthSquared > 0 ? min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared, 0), 1) : 0
        let ex = p.x - (a.x + t * dx), ey = p.y - (a.y + t * dy)
        return (ex * ex + ey * ey).squareRoot()
    }

    @Test(arguments: [0.0, 4.0]) func prefilteredHitEqualsBruteForce(tolerance: Double) throws {
        let (scene, symbols) = try StageBudgetTests.scene(seed: 2026)
        let list = scene.renderList(at: StageBudgetTests.frame, symbols: symbols)
        var rng = SplitMix64(seed: 0x5347_3301)
        var hits = 0
        for i in 0..<120 {
            let p: Point
            if i.isMultiple(of: 2) {
                p = Point(x: Double.random(in: -20...570, using: &rng), y: Double.random(in: -20...420, using: &rng))
            } else {
                // Just outside a random item's box, where only the tolerance can reach.
                let item = list.items[Int.random(in: 0..<list.items.count, using: &rng)]
                let box = try #require(item.worldBounds)
                p = Point(x: box.maxX + Double.random(in: 0...5, using: &rng),
                          y: Double.random(in: box.minY...box.maxY, using: &rng))
            }
            let expected = Self.bruteForceHit(list, p, tolerance: tolerance)
            #expect(list.hit(p, tolerance: tolerance) == expected, "\(p)")
            if expected != nil { hits += 1 }
        }
        #expect(hits > 10 && hits < 110)
    }
}
