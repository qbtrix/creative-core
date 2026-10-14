// MarqueeTests.swift: RenderList.marquee returns the unlocked, non-text items
// whose stroke-inclusive world bounds meet a rect, in paint order, each once;
// a zero-area or non-finite rect picks nothing.
import FlareCore
import Testing

@Suite struct MarqueeTests {
    static func square(at x: Double, stroke: Stroke? = nil) -> Shape {
        Shape(points: [Point(x: x, y: 0), Point(x: x + 10, y: 0), Point(x: x + 10, y: 10), Point(x: x, y: 10)],
              stroke: stroke)
    }

    static func list(_ layers: [Layer]) -> RenderList {
        Scene(id: "s", name: "S", layers: layers).renderList(at: 0, symbols: [])
    }

    static func ids(_ addresses: [RenderAddress]) -> [String] {
        addresses.map { "\($0.layerID):\($0.shapeIndex ?? -1)" }
    }

    static let everything = Rect(minX: -100, minY: -100, maxX: 100, maxY: 100)

    @Test func rectAroundTwoOfThreeReturnsThemInPaintOrder() {
        let list = Self.list([
            Layer(id: "c", name: "C", shapes: [Self.square(at: 40)]),
            Layer(id: "a", name: "A", shapes: [Self.square(at: 0)]),
            Layer(id: "b", name: "B", shapes: [Self.square(at: 20)]),
        ])
        // Covers b fully and a partly; misses c.
        #expect(Self.ids(list.marquee(Rect(minX: 5, minY: -1, maxX: 31, maxY: 11))) == ["a:0", "b:0"])
        // Drawn backwards (min past max) it is the same rect.
        #expect(Self.ids(list.marquee(Rect(minX: 31, minY: 11, maxX: 5, maxY: -1))) == ["a:0", "b:0"])
        // Paint order, not x order: c paints first.
        #expect(Self.ids(list.marquee(Self.everything)) == ["c:0", "a:0", "b:0"])
        // Touching an edge counts; a rect beside everything picks nothing.
        #expect(Self.ids(list.marquee(Rect(minX: 50, minY: 0, maxX: 60, maxY: 5))) == ["c:0"])
        #expect(Self.ids(list.marquee(Rect(minX: 32, minY: 0, maxX: 40, maxY: 5))) == ["c:0"])
        #expect(list.marquee(Rect(minX: 60.5, minY: 0, maxX: 70, maxY: 5)).isEmpty)
    }

    @Test func lockedTextAndHiddenAreNeverPicked() {
        let locked = Layer(id: "locked", name: "Locked", shapes: [Self.square(at: 0)], isLocked: true)
        let hidden = Layer(id: "hidden", name: "Hidden", shapes: [Self.square(at: 0)], isVisible: false)
        let text = Layer(id: "text", name: "Text", texts: [
            TextShape(string: "Hi", fontFamily: "Serif", fontSize: 12, position: Point(x: 5, y: 5)),
        ])
        #expect(Self.list([locked]).marquee(Self.everything).isEmpty)
        #expect(Self.list([locked, hidden, text]).marquee(Self.everything).isEmpty)
        let base = Layer(id: "base", name: "Base", shapes: [Self.square(at: 0)])
        #expect(Self.ids(Self.list([locked, base, hidden, text]).marquee(Self.everything)) == ["base:0"])
    }

    @Test func strokeOuterHalfIsPicked() {
        // Outline 0...10, stroke 10 wide: it paints out to 15.
        let list = Self.list([Layer(id: "s", name: "S", shapes: [Self.square(at: 0, stroke: Stroke(width: 10))])])
        #expect(Self.ids(list.marquee(Rect(minX: 12, minY: 2, maxX: 14, maxY: 8))) == ["s:0"])
        #expect(list.marquee(Rect(minX: 15.5, minY: 2, maxX: 20, maxY: 8)).isEmpty)
        let bare = Self.list([Layer(id: "s", name: "S", shapes: [Self.square(at: 0)])])
        #expect(bare.marquee(Rect(minX: 12, minY: 2, maxX: 14, maxY: 8)).isEmpty)
    }

    @Test func overflowingStrokeIsPicked() {
        // 1e308 * 2 / 2 overflows: no finite box, but the stroke paints everywhere.
        let tracks = ["scaleX": [Keyframe(frame: 0, value: 2)], "scaleY": [Keyframe(frame: 0, value: 2)]]
        let big = Layer(id: "big", name: "Big", shapes: [Self.square(at: 0, stroke: Stroke(width: 1e308))],
                        tracks: tracks)
        let list = Self.list([big, Layer(id: "a", name: "A", shapes: [Self.square(at: 0)])])
        #expect(list.items.first?.worldBounds == nil)
        #expect(Self.ids(list.marquee(Rect(minX: 2, minY: 2, maxX: 4, maxY: 4))) == ["big:0", "a:0"])
        #expect(Self.ids(list.marquee(Rect(minX: 500, minY: 500, maxX: 600, maxY: 600))) == ["big:0"])
        // An empty outline still has nothing to pick, and a bad rect still picks nothing.
        let empty = Layer(id: "e", name: "E", shapes: [Shape(points: [], stroke: Stroke(width: 1e308))], tracks: tracks)
        #expect(Self.list([empty]).marquee(Self.everything).isEmpty)
        #expect(list.marquee(Rect(minX: 5, minY: 0, maxX: 5, maxY: 10)).isEmpty)
    }

    @Test func zeroAreaOrNonFiniteRectIsEmpty() {
        let list = Self.list([Layer(id: "a", name: "A", shapes: [Self.square(at: 0)])])
        #expect(!list.marquee(Rect(minX: 0, minY: 0, maxX: 10, maxY: 10)).isEmpty)
        let bad = [
            Rect(minX: 5, minY: 0, maxX: 5, maxY: 10), Rect(minX: 0, minY: 5, maxX: 10, maxY: 5),
            Rect(minX: .nan, minY: 0, maxX: 10, maxY: 10), Rect(minX: 0, minY: 0, maxX: 10, maxY: .nan),
            Rect(minX: -.infinity, minY: 0, maxX: 10, maxY: 10), Rect(minX: 0, minY: 0, maxX: 10, maxY: .infinity),
        ]
        for rect in bad { #expect(list.marquee(rect).isEmpty) }
    }

    @Test func nestedItemKeepsTheHostsChain() {
        var scene = NestedScene.scene()
        scene.layers[3].isLocked = false
        let picked = scene.renderList(at: 0, symbols: NestedScene.symbols).marquee(Self.everything)
        #expect(picked.map(RenderListTests.key) == [
            "scene s||main|s0", "scene s||main|s1", "scene s||host|s0",
            "scene s|host:0|outerLayer|s0", "scene s|host:0>outerLayer:0|innerLayer|s0",
        ])
        // Built locked, the host and everything under it drop out.
        #expect(NestedScene.list.marquee(Self.everything).map(RenderListTests.key)
            == ["scene s||main|s0", "scene s||main|s1"])
    }
}
