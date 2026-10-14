// RenderListTests.swift: the render list of a nested scene lists the visible
// items in paint order with exact addresses, multiplies opacity and matrices
// down the tree, inherits locks from host layers, skips hidden layers and
// marks missing or cyclic symbols unresolved; Path.transformed keeps cubics;
// instance expansion stops at RenderList.maxExpandedPoints (fan-out and
// heavy fan-out) while large valid scenes and reused symbols expand fully;
// an instance node carries the symbol frame; a caller outside the module
// builds an address; 1,000 seeded broken scenes build a list,
// hit, marquee and bound without trapping. The import is not @testable, so
// the public inits are what these tests compile against.
import FlareCore
import Testing

/// The nested scene the stage-geometry tests share. Scene "s": "main" (two
/// shapes), "hidden" (hidden: a shape and an instance), "label" (one text),
/// "host" (locked, opacity 0.5, x 10: a shape, an instance of "outer" at x 5,
/// then one of the missing symbol "missing"). "outer" has "outerLayer"
/// (opacity 0.5, rotation 90: a shape, then an instance of "inner" at scale
/// 2); "inner" has "innerLayer" (opacity 0.8, y 3: a stroked cubic shape).
enum NestedScene {
    static let square = Shape(points: [
        Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10), Point(x: 0, y: 10),
    ])
    static let curve = Shape(points: [], fill: .solid(Color(r: 0, g: 0, b: 1)), path: Path(elements: [
        .move(to: Point(x: 0, y: 0)),
        .cubic(control1: Point(x: 1, y: 2), control2: Point(x: 3, y: 4), to: Point(x: 5, y: 0)), .close,
    ]), stroke: Stroke(width: 2))

    static func key(_ value: Double) -> [Keyframe] { [Keyframe(frame: 0, value: value)] }

    static let inner = Symbol(id: "inner", name: "Inner", layers: [
        Layer(id: "innerLayer", name: "Inner", shapes: [curve], tracks: ["opacity": key(0.8), "y": key(3)]),
    ])
    static let outer = Symbol(id: "outer", name: "Outer", layers: [
        Layer(id: "outerLayer", name: "Outer", shapes: [square], tracks: ["opacity": key(0.5), "rotation": key(90)],
              instances: [Instance(symbolID: "inner", transform: Transform(scaleX: 2, scaleY: 2))]),
    ])
    static let symbols = [outer, inner]

    static func scene(withText: Bool = true, withMissing: Bool = true) -> Scene {
        let main = Layer(id: "main", name: "Main", shapes: [square, curve])
        let hidden = Layer(id: "hidden", name: "Hidden", shapes: [square], isVisible: false,
                           instances: [Instance(symbolID: "outer")])
        let label = Layer(id: "label", name: "Label", texts: [
            TextShape(string: "Hi", fontFamily: "Serif", fontSize: 12, position: Point(x: 1, y: 2)),
        ])
        let instances = [Instance(symbolID: "outer", transform: Transform(x: 5))]
            + (withMissing ? [Instance(symbolID: "missing")] : [])
        let host = Layer(id: "host", name: "Host", shapes: [square], tracks: ["opacity": key(0.5), "x": key(10)],
                         isLocked: true, instances: instances)
        return Scene(id: "s", name: "Nested", width: 100, height: 100,
                     layers: withText ? [main, hidden, label, host] : [main, hidden, host])
    }

    static var list: RenderList { scene().renderList(at: 0, symbols: symbols) }
}

@Suite struct RenderListTests {
    /// "owner|host:0>outerLayer:0|leaf|s0" or "...|t0".
    static func key(_ a: RenderAddress) -> String {
        let hosts = a.hosts.map { "\($0.layerID):\($0.instanceIndex)" }.joined(separator: ">")
        let leaf = a.shapeIndex.map { "s\($0)" } ?? a.textIndex.map { "t\($0)" } ?? "-"
        return "\(a.owner)|\(hosts)|\(a.layerID)|\(leaf)"
    }

    @Test func itemsAreVisibleLeavesInPaintOrder() {
        let list = NestedScene.list
        #expect(list.items.map { Self.key($0.address) } == [
            "scene s||main|s0", "scene s||main|s1", "scene s||label|t0", "scene s||host|s0",
            "scene s|host:0|outerLayer|s0", "scene s|host:0>outerLayer:0|innerLayer|s0",
        ])
        #expect(list.items.map(\.isLocked) == [false, false, false, true, true, true])
        #expect(list.items.map(\.opacity) == [1, 1, 1, 0.5, 0.25, 0.2])
        let text = list.items[2]
        #expect(text.isText && text.outline.elements.isEmpty && text.fill == nil && text.stroke == nil)
        let shape = list.items[1]
        #expect(!shape.isText && shape.outline == NestedScene.curve.outline)
        #expect(shape.fill == NestedScene.curve.fill && shape.stroke == NestedScene.curve.stroke)
    }

    @Test func nestedLeafMultipliesOpacityAndMatrices() throws {
        let leaf = try #require(NestedScene.list.items.last)
        #expect(leaf.opacity == 0.5 * 0.5 * 0.8 && leaf.opacity == 0.2)
        let chain = Transform(x: 10).matrix * Transform(x: 5).matrix * Transform(rotation: 90).matrix
            * Transform(scaleX: 2, scaleY: 2).matrix * Transform(y: 3).matrix
        let m = leaf.matrix
        let diff = zip([m.a, m.b, m.c, m.d, m.tx, m.ty], [chain.a, chain.b, chain.c, chain.d, chain.tx, chain.ty])
        #expect(diff.allSatisfy { abs($0 - $1) <= 1e-12 })
        // (1, 0) -> y 3 -> scale 2 -> rotate 90 -> x 5 -> x 10.
        let p = m.apply(Point(x: 1, y: 0))
        #expect(abs(p.x - 9) <= 1e-12 && abs(p.y - 2) <= 1e-12)
    }

    @Test func treeKeepsLayersInstancesAndUnresolved() {
        let list = NestedScene.list
        let ids = list.nodes.map { node -> String in
            if case .layer(let l) = node { return l.id }
            return "?"
        }
        #expect(ids == ["main", "label", "host"])
        guard case .layer(let host)? = list.nodes.last, host.children.count == 3,
              case .instance(0, _, "outer", 0, let inner) = host.children[1] else {
            Issue.record("host node shape wrong"); return
        }
        #expect(host.isLocked && host.opacity == 0.5 && host.transform == Transform(x: 10) && inner.count == 1)
        #expect(host.children[2] == .unresolved(index: 1, symbolID: "missing"))
        // A nested layer keeps its own lock flag and opacity, not the host's.
        guard case .layer(let outerLayer)? = inner.first else { Issue.record("no outerLayer node"); return }
        #expect(outerLayer.id == "outerLayer" && !outerLayer.isLocked && outerLayer.opacity == 0.5)
        let noMissing = NestedScene.scene(withMissing: false).renderList(at: 0, symbols: NestedScene.symbols)
        #expect(noMissing.items == list.items)
        let empty = Scene(id: "e", name: "E", layers: [Layer(id: "empty", name: "Empty")]).renderList(at: 0, symbols: [])
        guard case .layer(let layer)? = empty.nodes.first else { Issue.record("no empty node"); return }
        #expect(layer.children.isEmpty && empty.nodes.count == 1 && empty.items.isEmpty)
    }

    @Test func symbolListsOnlyItsLayers() {
        let list = NestedScene.inner.renderList(at: 0, symbols: NestedScene.symbols)
        #expect(list.items.map { Self.key($0.address) } == ["symbol inner||innerLayer|s0"])
        #expect(list.items.first?.opacity == 0.8)
        var cyclic = NestedScene.inner
        cyclic.layers[0].instances = [Instance(symbolID: "inner")]
        let looped = cyclic.renderList(at: 0, symbols: [cyclic])
        guard case .layer(let layer)? = looped.nodes.first else { Issue.record("no node"); return }
        #expect(layer.children.last == .unresolved(index: 0, symbolID: "inner") && looped.items.count == 1)
    }

    @Test func transformedMapsEveryPoint() {
        let m = Transform(x: 3, y: -2, scaleX: 2, scaleY: 0.5, rotation: 30).matrix
        let p = (0..<6).map { Point(x: Double($0), y: Double($0 * $0 % 5)) }
        let path = Path(elements: [.move(to: p[0]), .line(to: p[1]), .quad(control: p[2], to: p[3]),
                                   .cubic(control1: p[4], control2: p[5], to: p[0]), .close])
        let q = p.map(m.apply)
        #expect(path.transformed(by: m).elements == [.move(to: q[0]), .line(to: q[1]), .quad(control: q[2], to: q[3]),
                                                     .cubic(control1: q[4], control2: q[5], to: q[0]), .close])
    }

    /// QB-V1: a cubic in a shape's outline is a cubic in its item's outline.
    @Test func cubicsKept() {
        let curved = NestedScene.list.items.filter { $0.outline == NestedScene.curve.outline }
        #expect(curved.count == 2)
        for item in curved {
            guard case .cubic = item.outline.transformed(by: item.matrix).elements[1] else {
                Issue.record("cubic lost"); continue
            }
        }
    }

    /// Every node in the tree, leaves included.
    static func nodeCount(_ nodes: [RenderNode]) -> Int {
        nodes.reduce(0) { sum, node in
            switch node {
            case .layer(let l): sum + 1 + nodeCount(l.children)
            case .instance(_, _, _, _, let children): sum + 1 + nodeCount(children)
            case .shape, .text, .unresolved: sum + 1
            }
        }
    }

    static func hasUnresolved(_ nodes: [RenderNode]) -> Bool {
        nodes.contains { node in
            switch node {
            case .layer(let l): hasUnresolved(l.children)
            case .instance(_, _, _, _, let children): hasUnresolved(children)
            case .unresolved: true
            case .shape, .text: false
            }
        }
    }

    /// Every outline element in the list's items.
    static func outlineElements(_ list: RenderList) -> Int {
        list.items.reduce(0) { $0 + $1.outline.elements.count }
    }

    /// `depth` symbols, each holding two instances of the next; the last
    /// holds `leaf`: 2^depth copies of it unbounded.
    static func fanOut(depth: Int, leaf: Shape) -> (Scene, [Symbol]) {
        let symbols = (0...depth).map { i in
            let layer = i == depth
                ? Layer(id: "l\(i)", name: "L", shapes: [leaf])
                : Layer(id: "l\(i)", name: "L", instances: [Instance(symbolID: "s\(i + 1)"), Instance(symbolID: "s\(i + 1)")])
            return Symbol(id: "s\(i)", name: "S", layers: [layer])
        }
        let scene = Scene(id: "fan", name: "Fan", layers: [Layer(id: "top", name: "Top", instances: [Instance(symbolID: "s0")])])
        return (scene, symbols)
    }

    /// 2^40 small leaves unbounded. The walk stops expanding at the budget
    /// and marks the list truncated; each leaf, 40 deep, costs about 250.
    @Test func fanOutIsBounded() throws {
        let rect = Shape(points: [], path: try PathBuilders.rectangle(in: Rect(minX: 0, minY: 0, maxX: 4, maxY: 4)))
        let (scene, symbols) = Self.fanOut(depth: 39, leaf: rect)
        let list = scene.renderList(at: 0, symbols: symbols)
        let (truncated, unresolved, count) = (list.isTruncated, Self.hasUnresolved(list.nodes), list.items.count)
        #expect(truncated && unresolved && count > 0)
        #expect(count < RenderList.maxExpandedPoints / 200)
    }

    /// 2^14 copies of a 200,000-point shape unbounded (billions of points):
    /// the budget counts points, so only about twenty copies expand.
    @Test func heavyFanOutIsBounded() {
        let heavy = Shape(points: (0..<200_000).map { Point(x: Double($0 % 7), y: Double($0 % 5)) })
        let (scene, symbols) = Self.fanOut(depth: 14, leaf: heavy)
        let list = scene.renderList(at: 0, symbols: symbols)
        let (truncated, count, elements) = (list.isTruncated, list.items.count, Self.outlineElements(list))
        #expect(truncated && count > 0)
        // At most one symbol's own content past the budget.
        #expect(elements <= RenderList.maxExpandedPoints + 200_001)
    }

    /// A valid v1-sized scene: one layer of 30,000 shapes, then an instance
    /// of a small symbol. The owner's own layers cost nothing, so the
    /// instance expands and the scene exports.
    @Test func largeValidSceneExpandsEveryInstance() throws {
        let square = NestedScene.square
        let big = Layer(id: "big", name: "Big", shapes: Array(repeating: square, count: 30_000))
        let host = Layer(id: "host", name: "Host", instances: [Instance(symbolID: "outer")])
        let scene = Scene(id: "s", name: "S", width: 100, height: 100, layers: [big, host])
        let list = scene.renderList(at: 0, symbols: NestedScene.symbols)
        let (truncated, unresolved, count) = (list.isTruncated, Self.hasUnresolved(list.nodes), list.items.count)
        #expect(!truncated && !unresolved && count == 30_002)
        let lastLayer = list.items.last?.address.layerID
        #expect(lastLayer == "innerLayer")
        _ = try SVGExporter.export(scene: scene, frame: 0, symbols: NestedScene.symbols)
    }

    /// The owner's own layers list fully however much they hold, and do not
    /// spend the budget: a layer with more points than the budget lists every
    /// shape and a later instance still expands.
    @Test func ownLayersAreNotCharged() {
        let path = Path(elements: Array(repeating: .line(to: Point(x: 1, y: 1)), count: 100_000))
        let shapes = Array(repeating: Shape(points: [], path: path), count: RenderList.maxExpandedPoints / 100_000 + 2)
        let heavy = Layer(id: "heavy", name: "Heavy", shapes: shapes)
        let host = Layer(id: "host", name: "Host", instances: [Instance(symbolID: "inner")])
        let list = Scene(id: "s", name: "S", layers: [heavy, host]).renderList(at: 0, symbols: NestedScene.symbols)
        let (truncated, count, elements) = (list.isTruncated, list.items.count, Self.outlineElements(list))
        #expect(elements > RenderList.maxExpandedPoints)
        #expect(!truncated && count == shapes.count + 1)
    }

    /// A 300-shape symbol placed 100 times expands every instance.
    @Test func repeatedSymbolExpandsFully() {
        let symbol = Symbol(id: "many", name: "Many", layers: [
            Layer(id: "m", name: "M", shapes: Array(repeating: NestedScene.square, count: 300)),
        ])
        let layer = Layer(id: "l", name: "L", instances: Array(repeating: Instance(symbolID: "many"), count: 100))
        let list = Scene(id: "s", name: "S", layers: [layer]).renderList(at: 0, symbols: [symbol])
        let (truncated, unresolved, count) = (list.isTruncated, Self.hasUnresolved(list.nodes), list.items.count)
        #expect(!truncated && !unresolved && count == 30_000)
    }

    /// The instance node carries the symbol frame, not the host frame: host
    /// frame 1.5 rounds down to 1, and playOnce from 1 gives symbol frame 2.
    @Test func renderListInstanceNodeCarriesSymbolFrame() {
        let inner = Layer(id: "in", name: "In", shapes: [NestedScene.square])
        let symbol = Symbol(id: "sym", name: "Sym", durationFrames: 4, layers: [inner])
        let host = Layer(id: "h", name: "H", instances: [Instance(symbolID: "sym", firstFrame: 1, loop: .playOnce)])
        let list = Scene(id: "s", name: "S", layers: [host]).renderList(at: 1.5, symbols: [symbol])
        guard case .layer(let layer)? = list.nodes.first, case .instance(0, _, "sym", 2, _)? = layer.children.first else {
            Issue.record("instance node frame wrong: \(list.nodes)"); return
        }
    }

    /// An address with both indices set matches nothing; with only the shape
    /// index it is the shape.
    @Test func addressNeedsExactlyOneIndex() {
        let both = RenderAddress(owner: .scene("s"), hosts: [], layerID: "main", shapeIndex: 0, textIndex: 0)
        #expect(NestedScene.list.worldBounds(of: [both]) == nil)
        var shape = both
        shape.textIndex = nil
        #expect(NestedScene.list.worldBounds(of: [shape]) == Rect(minX: 0, minY: 0, maxX: 10, maxY: 10))
    }

    /// A caller outside the module builds an address from a selection it holds.
    @Test func publicAddressInit() throws {
        let address = RenderAddress(owner: .scene("s"), hosts: [], layerID: "main", shapeIndex: 0, textIndex: nil)
        let box = try #require(NestedScene.list.worldBounds(of: [address]))
        #expect(box == Rect(minX: 0, minY: 0, maxX: 10, maxY: 10))
        let nested = RenderAddress(owner: .scene("s"), hosts: [InstanceHost(layerID: "host", instanceIndex: 0)],
                                   layerID: "outerLayer", shapeIndex: 0, textIndex: nil)
        #expect(NestedScene.list.items.contains { $0.address == nested })
    }

    /// Never crash: random NaN transforms, missing symbols and cycles, then
    /// every public query on the result.
    @Test func seededScenesNeverTrap() {
        var rng = SplitMix64(seed: 0x5E61)
        let weird: [Double] = [.nan, .infinity, -.infinity, 0, 1, -3, 0.5, 1e308]
        func value() -> Double { weird[Int(rng.next() % UInt64(weird.count))] }
        func count() -> Int { Int(rng.next() % 3) }
        func point() -> Point { Point(x: value(), y: value()) }
        func shape() -> Shape {
            switch rng.next() % 3 {
            case 0: Shape(points: [point()])
            case 1: Shape(points: (0..<4).map { _ in point() }, stroke: Stroke(width: value()))
            default:
                Shape(points: [], path: Path(elements: [
                    .move(to: point()), .cubic(control1: point(), control2: point(), to: point()), .close,
                ]), stroke: Stroke(width: value()))
            }
        }
        func query(_ list: RenderList) {
            let addresses = Set(list.items.map(\.address))
            for t in [0, 4, Double.nan, 1e300] {
                let hit = list.hit(point(), tolerance: t)
                #expect(hit.map(addresses.contains) ?? true)
            }
            let picked = list.marquee(Rect(minX: value(), minY: value(), maxX: value(), maxY: value()))
            #expect(picked.allSatisfy(addresses.contains))
            let all = list.worldBounds(of: Array(addresses))
            #expect(all.map { _ in !addresses.isEmpty } ?? true)
            for item in list.items {
                #expect(item.worldBounds.map { _ in !item.isText } ?? true)
            }
        }
        func layers(_ prefix: String) -> [Layer] {
            (0..<count()).map { i in
                var tracks: [String: [Keyframe]] = [:]
                for k in ["x", "y", "scaleX", "rotation", "opacity"] where rng.next() % 2 == 0 {
                    tracks[k] = [Keyframe(frame: 0, value: value())]
                }
                let shapes = (0..<count()).map { _ in shape() }
                let instances = (0..<count()).map { _ in
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
            let list = Scene(id: "s\(n)", name: "S", layers: layers("t")).renderList(at: value(), symbols: symbols)
            #expect(list.items.count == leaves(list.nodes))
            query(list)
            let own = symbols[n % 3].renderList(at: Double(n), symbols: symbols)
            #expect(own.items.count == leaves(own.nodes))
            query(own)
        }
    }
}
