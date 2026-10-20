// MatteRenderListTests.swift: the MM-7 acceptance cases for the render list's
// `clips` and `matte` on Fixtures/masks.flare and on a masked symbol inside a
// masked, moved instance: clip paths in scene space through the layer's and
// every instance's matrices, masks in order, a matte naming its source's
// items, the source flagged, a hidden source listed only in `matteItems`, and
// a hidden matted layer giving no item.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import FlareCore
import Testing

@Suite struct MatteRenderListTests {
    static func fixture() throws -> Document {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/masks.flare")
        return try FlareFormat.decode(Data(contentsOf: url))
    }

    static func list(_ doc: Document) -> RenderList {
        doc.scenes[0].renderList(at: 0, symbols: doc.symbols)
    }

    static func square(_ a: Double, _ b: Double) -> Path {
        Path(polyline: [Point(x: a, y: a), Point(x: b, y: a), Point(x: b, y: b), Point(x: a, y: b)], closed: true)
    }

    /// card (two masks), photo (luma-matted by lumen), lumen (hidden): lumen is listed only in `matteItems`.
    @Test func matteNamesItsSourceItems() throws {
        let list = Self.list(try Self.fixture())
        #expect(list.items.map(\.address.layerID) == ["card", "photo"] && list.nodes.count == 2)
        #expect(list.items.map(\.matte) == [nil, MatteLink(sourceItems: 0..<1, inMatteItems: true, kind: .luma)])
        #expect(list.items.map(\.isMatteSource) == [false, false])
        #expect(list.matteItems.map(\.address.layerID) == ["lumen"] && list.matteItems.map(\.isMatteSource) == [true])
        #expect(list.matteItems.first?.outline == Self.square(20, 80))
    }

    /// A visible matte source is drawn in its own right as well as flagged.
    @Test func visibleSourceIsDrawnToo() throws {
        var doc = try Self.fixture()
        doc.scenes[0].layers[2].isVisible = true
        let list = Self.list(doc)
        #expect(list.items.map(\.isMatteSource) == [false, false, true] && list.matteItems.isEmpty)
        #expect(list.items.map(\.matte) == [nil, MatteLink(sourceItems: 2..<3, inMatteItems: false, kind: .luma), nil])
        #expect(list.nodes.count == 3)
    }

    /// Hiding the matted layer leaves no item for it, and its hidden source is not listed either.
    @Test func hiddenMattedLayerGivesNoItem() throws {
        var doc = try Self.fixture()
        doc.scenes[0].layers[1].isVisible = false
        let list = Self.list(doc)
        #expect(list.items.map(\.address.layerID) == ["card"] && list.matteItems.isEmpty && list.nodes.count == 1)
    }

    @Test func masksKeepOrder() throws {
        let doc = try Self.fixture()
        let card = try #require(Self.list(doc).items.first)
        let masks = doc.scenes[0].layers[0].masks
        #expect(card.clips.map(\.mode) == [.add, .subtract])
        #expect(card.clips.map(\.path) == masks.map(\.path))
        #expect(card.clips.map(\.feather) == [0, 8] && card.clips.map(\.opacity) == [1, 0.75])
        #expect(card.clips.allSatisfy { !$0.inverted && $0.depth == 0 })
        #expect(Self.list(doc).items.dropFirst().allSatisfy { $0.clips.isEmpty })
    }

    /// A masked symbol layer inside a moved instance on a moved, masked host:
    /// the host's mask goes through the host's matrix, the symbol layer's
    /// through the host's, the instance's and its own, host first.
    @Test func clipInWorldSpace() {
        let face = Layer(id: "face", name: "Face", shapes: [Shape(points: [Point(x: 0, y: 0), Point(x: 4, y: 0)])],
                         tracks: ["y": [Keyframe(frame: 0, value: 3)]],
                         masks: [LayerMask(path: Self.square(0, 4), inverted: true)])
        let badge = Symbol(id: "badge", name: "Badge", layers: [face])
        let inst = Transform(x: 5, y: 7, scaleX: 2, scaleY: 2)
        let host = Layer(id: "host", name: "Host", tracks: ["x": [Keyframe(frame: 0, value: 10)]],
                         instances: [Instance(symbolID: "badge", transform: inst)],
                         masks: [LayerMask(path: Self.square(0, 50), mode: .intersect)])
        let list = Scene(id: "s", name: "S", layers: [host]).renderList(at: 0, symbols: [badge])
        let hostM = Transform(x: 10).matrix, faceM = hostM * inst.matrix * Transform(y: 3).matrix
        #expect(list.items.count == 1 && list.items.first?.matrix == faceM)
        #expect(list.items.first?.clips == [
            ClipMask(path: Self.square(0, 50).transformed(by: hostM), mode: .intersect, feather: 0, opacity: 1,
                        inverted: false, depth: 0),
            ClipMask(path: Self.square(0, 4).transformed(by: faceM), mode: .add, feather: 0, opacity: 1,
                        inverted: true, depth: 1),
        ])
    }

    /// A symbol layer's feather goes through the same matrix as its path: 10 under a 4x instance is 40.
    @Test func featherScalesWithMatrix() {
        let face = Layer(id: "face", name: "Face", shapes: [Shape(points: [Point(x: 0, y: 0), Point(x: 4, y: 0)])],
                         masks: [LayerMask(path: Self.square(0, 4), feather: 10)])
        let host = Layer(id: "host", name: "Host",
                         instances: [Instance(symbolID: "badge", transform: Transform(scaleX: 4, scaleY: 4))])
        let list = Scene(id: "s", name: "S", layers: [host]).renderList(at: 0, symbols: [Symbol(id: "badge", name: "Badge", layers: [face])])
        #expect(list.items.first?.clips.map(\.feather) == [40])
    }

    /// A 1e160 scale overflows the determinant; the feather still scales by it, and a zero feather stays 0.
    @Test func featherSurvivesHugeScale() {
        let face = Layer(id: "face", name: "Face", shapes: [Shape(points: [Point(x: 0, y: 0), Point(x: 4, y: 0)])],
                         masks: [LayerMask(path: Self.square(0, 4)), LayerMask(path: Self.square(0, 4), feather: 1)])
        let host = Layer(id: "host", name: "Host",
                         instances: [Instance(symbolID: "badge", transform: Transform(scaleX: 1e160, scaleY: 1e160))])
        let list = Scene(id: "s", name: "S", layers: [host]).renderList(at: 0, symbols: [Symbol(id: "badge", name: "Badge", layers: [face])])
        #expect(list.items.first?.clips.map(\.feather) == [0, 1e160])
    }

    /// One matte level, as the exporters: a hidden matte source's own matte is not resolved, so the source's
    /// items carry no matte and the layer behind it is not walked.
    @Test func matteOnHiddenSourceIsNotResolved() throws {
        var doc = try Self.fixture()
        doc.scenes[0].layers[2].matte = TrackMatte(sourceLayerID: "deep")
        doc.scenes[0].layers.append(Layer(id: "deep", name: "Deep", shapes: doc.scenes[0].layers[2].shapes, isVisible: false))
        let list = Self.list(doc)
        #expect(list.matteItems.map(\.address.layerID) == ["lumen"] && list.matteItems.map(\.matte) == [nil])
        #expect(list.items.map(\.matte) == [nil, MatteLink(sourceItems: 0..<1, inMatteItems: true, kind: .luma)])
    }

    /// A matte on a host layer reaches the items its instances expand; a matte nearer the item wins.
    @Test func hostMatteReachesInstanceItems() {
        let shape = Shape(points: [Point(x: 0, y: 0), Point(x: 1, y: 1)])
        let dot = Symbol(id: "dot", name: "Dot", layers: [
            Layer(id: "d", name: "D", shapes: [shape]),
            Layer(id: "e", name: "E", shapes: [shape], matte: TrackMatte(sourceLayerID: "f")),
            Layer(id: "f", name: "F", shapes: [shape]),
        ])
        let source = Layer(id: "src", name: "Src", shapes: [shape, shape], isVisible: false)
        let host = Layer(id: "host", name: "Host", shapes: [shape], instances: [Instance(symbolID: "dot")],
                         matte: TrackMatte(sourceLayerID: "src", kind: .alphaInverted))
        let list = Scene(id: "s", name: "S", layers: [host, source]).renderList(at: 0, symbols: [dot])
        #expect(list.items.map(\.address.layerID) == ["host", "d", "e", "f"])
        let link = MatteLink(sourceItems: 0..<2, inMatteItems: true, kind: .alphaInverted)
        let inner = MatteLink(sourceItems: 3..<4, inMatteItems: false, kind: .alpha)
        #expect(list.items.map(\.matte) == [link, link, inner, link])
        #expect(list.items.map(\.isMatteSource) == [false, false, false, true] && list.matteItems.count == 2)
    }
}
