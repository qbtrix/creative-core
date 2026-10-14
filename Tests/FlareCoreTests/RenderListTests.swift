// RenderListTests.swift: the render list of a nested scene lists the visible
// items in paint order with exact addresses, multiplies opacity and matrices
// down the tree, inherits locks from host layers, skips hidden layers and
// marks missing or cyclic symbols unresolved; Path.transformed keeps cubics;
// 1,000 seeded broken scenes build a list without trapping.
import FlareCore
import Testing

/// The nested scene the stage-geometry tests share. Scene "s" has layers
/// "main" (two shapes), "hidden" (hidden: a shape and an instance), "label"
/// (one text) and "host" (locked, opacity 0.5, x 10: one shape, an instance
/// of "outer" at x 5, then an instance of the missing symbol "missing").
/// "outer" has layer "outerLayer" (opacity 0.5, rotation 90: one shape, then
/// an instance of "inner" at scale 2); "inner" has layer "innerLayer"
/// (opacity 0.8, y 3: one shape with a cubic). Copy it, don't change it.
enum NestedScene {
    static let square = Shape(points: [
        Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10), Point(x: 0, y: 10),
    ])
    static let curve = Shape(points: [], fill: .solid(Color(r: 0, g: 0, b: 1)), path: Path(elements: [
        .move(to: Point(x: 0, y: 0)),
        .cubic(control1: Point(x: 1, y: 2), control2: Point(x: 3, y: 4), to: Point(x: 5, y: 0)),
        .close,
    ]), stroke: Stroke(width: 2))

    static func key(_ value: Double) -> [Keyframe] { [Keyframe(frame: 0, value: value)] }

    static let inner = Symbol(id: "inner", name: "Inner", layers: [
        Layer(id: "innerLayer", name: "Inner", shapes: [curve], tracks: ["opacity": key(0.8), "y": key(3)]),
    ])
    static let outer = Symbol(id: "outer", name: "Outer", layers: [
        Layer(id: "outerLayer", name: "Outer", shapes: [square], tracks: ["opacity": key(0.5), "rotation": key(90)],
              instances: [Instance(symbolID: "inner", transform: Transform(scaleX: 2, scaleY: 2))]),
    ])
    static var symbols: [Symbol] { [outer, inner] }

    static func scene(withText: Bool = true, withMissing: Bool = true) -> Scene {
        let main = Layer(id: "main", name: "Main", shapes: [square, curve])
        let hidden = Layer(id: "hidden", name: "Hidden", shapes: [square], isVisible: false,
                           instances: [Instance(symbolID: "outer")])
        let label = Layer(id: "label", name: "Label", texts: [
            TextShape(string: "Hi", fontFamily: "Serif", fontSize: 12, position: Point(x: 1, y: 2)),
        ])
        var instances = [Instance(symbolID: "outer", transform: Transform(x: 5))]
        if withMissing { instances.append(Instance(symbolID: "missing")) }
        let host = Layer(id: "host", name: "Host", shapes: [square], tracks: ["opacity": key(0.5), "x": key(10)],
                         isLocked: true, instances: instances)
        return Scene(id: "s", name: "Nested", width: 100, height: 100,
                     layers: withText ? [main, hidden, label, host] : [main, hidden, host])
    }
}

@Suite struct RenderListTests {
    static func address(_ layer: String, hosts: [(String, Int)] = [], shape: Int? = nil, text: Int? = nil,
                        owner: LayerOwner = .scene("s")) -> RenderAddress {
        RenderAddress(owner: owner, hosts: hosts.map { InstanceHost(layerID: $0.0, instanceIndex: $0.1) },
                      layerID: layer, shapeIndex: shape, textIndex: text)
    }

    static func close(_ m: Matrix, _ n: Matrix) -> Bool {
        zip([m.a, m.b, m.c, m.d, m.tx, m.ty], [n.a, n.b, n.c, n.d, n.tx, n.ty]).allSatisfy { abs($0 - $1) <= 1e-12 }
    }

    @Test func itemsAreVisibleLeavesInPaintOrder() {
        let list = NestedScene.scene().renderList(at: 0, symbols: NestedScene.symbols)
        #expect(list.items.map(\.address) == [
            Self.address("main", shape: 0),
            Self.address("main", shape: 1),
            Self.address("label", text: 0),
            Self.address("host", shape: 0),
            Self.address("outerLayer", hosts: [("host", 0)], shape: 0),
            Self.address("innerLayer", hosts: [("host", 0), ("outerLayer", 0)], shape: 0),
        ])
        #expect(!list.items.contains { $0.address.layerID == "hidden" })
        #expect(list.items.map(\.isLocked) == [false, false, false, true, true, true])
        #expect(list.items.map(\.opacity) == [1, 1, 1, 0.5, 0.25, 0.2])
    }

    @Test func textItemHasEmptyOutlineAndNoPaint() throws {
        let list = NestedScene.scene().renderList(at: 0, symbols: NestedScene.symbols)
        let text = try #require(list.items.first { $0.isText })
        #expect(text.address.textIndex == 0 && text.address.shapeIndex == nil)
        #expect(text.outline.elements.isEmpty && text.fill == nil && text.stroke == nil)
        let shape = list.items[1]
        #expect(!shape.isText && shape.outline == NestedScene.curve.outline)
        #expect(shape.fill == NestedScene.curve.fill && shape.stroke == NestedScene.curve.stroke)
    }

    @Test func nestedLeafMultipliesOpacityAndMatrices() throws {
        let list = NestedScene.scene().renderList(at: 0, symbols: NestedScene.symbols)
        let leaf = try #require(list.items.last)
        #expect(leaf.opacity == 0.5 * 0.5 * 0.8)
        #expect(leaf.opacity == 0.2)
        let chain = Transform(x: 10).matrix * Transform(x: 5).matrix * Transform(rotation: 90).matrix
            * Transform(scaleX: 2, scaleY: 2).matrix * Transform(y: 3).matrix
        #expect(Self.close(leaf.matrix, chain))
        // (1, 0) -> y 3 -> scale 2 -> rotate 90 -> x 5 -> x 10.
        let p = leaf.matrix.apply(Point(x: 1, y: 0))
        #expect(abs(p.x - 9) <= 1e-12 && abs(p.y - 2) <= 1e-12)
        #expect(leaf.isLocked)
    }

    @Test func treeKeepsLayersInstancesAndUnresolved() throws {
        let list = NestedScene.scene().renderList(at: 0, symbols: NestedScene.symbols)
        let ids = list.nodes.compactMap { node -> String? in
            if case .layer(let l) = node { return l.id }
            return nil
        }
        #expect(ids == ["main", "label", "host"])
        guard case .layer(let host)? = list.nodes.last else { Issue.record("no host node"); return }
        #expect(host.isLocked && host.opacity == 0.5 && host.transform == Transform(x: 10))
        #expect(host.children.count == 3)
        guard case .instance(0, _, "outer", 0, let inner) = host.children[1] else {
            Issue.record("instance node missing"); return
        }
        #expect(inner.count == 1)
        #expect(host.children[2] == .unresolved(index: 1, symbolID: "missing"))
        let withoutMissing = NestedScene.scene(withMissing: false).renderList(at: 0, symbols: NestedScene.symbols)
        #expect(withoutMissing.items == list.items)
    }

    @Test func emptyLayerIsANodeWithNoItems() {
        let scene = Scene(id: "e", name: "E", layers: [Layer(id: "empty", name: "Empty")])
        let list = scene.renderList(at: 0, symbols: [])
        #expect(list.items.isEmpty)
        guard case .layer(let layer)? = list.nodes.first else { Issue.record("no node"); return }
        #expect(layer.id == "empty" && layer.children.isEmpty && list.nodes.count == 1)
        let none = Scene(id: "n", name: "N").renderList(at: 0, symbols: [])
        #expect(none.nodes.isEmpty && none.items.isEmpty)
    }

    @Test func symbolListsOnlyItsLayers() {
        let list = NestedScene.inner.renderList(at: 0, symbols: NestedScene.symbols)
        #expect(list.items.map(\.address) == [Self.address("innerLayer", shape: 0, owner: .symbol("inner"))])
        #expect(list.items.first?.opacity == 0.8)
        var cyclic = NestedScene.inner
        cyclic.layers[0].instances = [Instance(symbolID: "inner")]
        let looped = cyclic.renderList(at: 0, symbols: [cyclic])
        guard case .layer(let layer)? = looped.nodes.first else { Issue.record("no node"); return }
        #expect(layer.children.last == .unresolved(index: 0, symbolID: "inner"))
        #expect(looped.items.count == 1)
    }

    @Test func transformedMapsEveryCubicPoint() {
        let m = Transform(x: 3, y: -2, scaleX: 2, scaleY: 0.5, rotation: 30).matrix
        let path = Path(elements: [
            .move(to: Point(x: 1, y: 1)), .line(to: Point(x: 2, y: 0)),
            .quad(control: Point(x: 3, y: 3), to: Point(x: 4, y: 0)),
            .cubic(control1: Point(x: 1, y: 2), control2: Point(x: 3, y: 4), to: Point(x: 5, y: 0)), .close,
        ])
        #expect(path.transformed(by: m).elements == [
            .move(to: m.apply(Point(x: 1, y: 1))), .line(to: m.apply(Point(x: 2, y: 0))),
            .quad(control: m.apply(Point(x: 3, y: 3)), to: m.apply(Point(x: 4, y: 0))),
            .cubic(control1: m.apply(Point(x: 1, y: 2)), control2: m.apply(Point(x: 3, y: 4)),
                   to: m.apply(Point(x: 5, y: 0))), .close,
        ])
    }

    /// QB-V1: a cubic in a shape's outline is a cubic in its item's outline.
    @Test func cubicsKept() {
        let list = NestedScene.scene().renderList(at: 0, symbols: NestedScene.symbols)
        for item in list.items where item.address.layerID == "innerLayer" || item.address.shapeIndex == 1 {
            #expect(item.outline == NestedScene.curve.outline)
            let world = item.outline.transformed(by: item.matrix).elements
            #expect(world.count == 3)
            guard case .cubic = world[1] else { Issue.record("cubic lost"); continue }
        }
    }

    /// Never crash: random NaN transforms, missing symbols and cycles.
    @Test func seededScenesNeverTrap() {
        var rng = SplitMix64(seed: 0x5E61)
        let weird: [Double] = [.nan, .infinity, -.infinity, 0, 1, -3, 0.5, 1e308]
        func value() -> Double { weird[Int(rng.next() % UInt64(weird.count))] }
        func layers(_ prefix: String) -> [Layer] {
            (0..<Int(rng.next() % 3)).map { i in
                let keys = ["x", "y", "scaleX", "scaleY", "rotation", "opacity"]
                var tracks: [String: [Keyframe]] = [:]
                for k in keys where rng.next() % 2 == 0 { tracks[k] = [Keyframe(frame: 0, value: value())] }
                let shapes = (0..<Int(rng.next() % 3)).map { _ in
                    Shape(points: [Point(x: value(), y: value()), Point(x: value(), y: 1)])
                }
                let instances = (0..<Int(rng.next() % 3)).map { _ in
                    Instance(symbolID: ["a", "b", "c", "zz"][Int(rng.next() % 4)],
                             transform: Transform(x: value(), scaleX: value(), rotation: value()))
                }
                return Layer(id: "\(prefix)\(i)", name: "L", shapes: shapes, tracks: tracks,
                             isVisible: rng.next() % 4 != 0, isLocked: rng.next() % 4 == 0, instances: instances)
            }
        }
        func leaves(_ nodes: [RenderNode]) -> Int {
            nodes.reduce(0) { sum, node in
                switch node {
                case .layer(let l): sum + leaves(l.children)
                case .instance(_, _, _, _, let children): sum + leaves(children)
                case .shape, .text: sum + 1
                case .unresolved: sum
                }
            }
        }
        for n in 0..<1000 {
            let symbols = ["a", "b", "c"].map { Symbol(id: $0, name: $0, durationFrames: 4, layers: layers($0)) }
            let scene = Scene(id: "s\(n)", name: "S", layers: layers("t"))
            let list = scene.renderList(at: value(), symbols: symbols)
            #expect(list.items.count == leaves(list.nodes))
            for symbol in symbols {
                let own = symbol.renderList(at: Double(n), symbols: symbols)
                #expect(own.items.count == leaves(own.nodes))
            }
        }
    }
}
