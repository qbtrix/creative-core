// RenderList.swift: what one frame of a scene or symbol draws, built from one
// walk of its layers, so the stage, hit testing, bounds and the SVG exporter
// agree. `nodes` keeps the layer and instance tree (one node per visible
// layer, empty ones included); `items` are its leaves in paint order. Paint
// order is the SVG exporter's: layers in order; in a layer its shapes, then
// texts, then instances, each instance's symbol layers recursively.
//
// Invariants:
// - a hidden layer is absent from `nodes` and `items`, with all it holds
// - an item's opacity is the product of every layer opacity on its way down;
//   instances have no opacity of their own
// - an item is locked when its layer or any host layer above it is locked
// - an instance whose symbol is missing, cyclic or nested too deep is an
//   `.unresolved` node and adds no items; building never throws or traps
// - once the walk has built `RenderList.maxRenderItems` items and nodes, every
//   further instance is an `.unresolved` node and is not expanded, so a small
//   file whose symbols fan out (two instances per symbol, 40 deep) cannot
//   build 2^40 items; the layers being walked still list their own leaves
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// What one frame of a scene or symbol draws: its layer and instance tree
/// and the tree's leaves in paint order. Instance expansion stops once
/// `maxRenderItems` items and nodes are built; later instances are
/// `.unresolved`, which the SVG exporter rejects with `unresolvedSymbol`.
public struct RenderList: Sendable, Hashable {
    /// The budget of items plus nodes one walk builds before it stops
    /// expanding instances: far above a real scene, small enough that a file
    /// whose symbols fan out cannot exhaust memory.
    public static let maxRenderItems = 50_000

    /// The tree, for exporters that keep groups: one node per visible layer.
    public var nodes: [RenderNode]
    /// The leaves in paint order, matrices and opacity already multiplied
    /// down the tree: what the stage draws and hit testing reads.
    public var items: [RenderItem]
}

/// One node of a render list's tree. Each `index` is the position in the
/// owning layer's `shapes`, `texts` or `instances`.
public indirect enum RenderNode: Sendable, Hashable {
    /// A visible layer and what it draws.
    case layer(RenderLayer)
    /// A layer's shape, in its layer's space; `index` is its position in the
    /// layer's `shapes`.
    case shape(index: Int, Shape)
    /// A layer's text; `index` is its position in the layer's `texts`.
    case text(index: Int, TextShape)
    /// An instance holding its symbol's layers at the symbol `frame`; `index`
    /// is its position in the layer's `instances`.
    case instance(index: Int, Instance, symbolID: String, frame: Double, children: [RenderNode])
    /// An instance whose symbol is missing, cyclic or nested too deep, or that
    /// came after the walk spent `RenderList.maxRenderItems`; `index` is its
    /// position in the layer's `instances`.
    case unresolved(index: Int, symbolID: String)
}

/// A visible layer: its sampled local transform and opacity, its own lock
/// flag, and what it draws in paint order.
public struct RenderLayer: Sendable, Hashable {
    /// The layer's id.
    public var id: String
    /// The layer's name.
    public var name: String
    /// The layer's transform sampled at the frame, relative to its parent.
    public var transform: Transform
    /// The layer's own opacity sampled at the frame, not multiplied down.
    public var opacity: Double
    /// The layer's own lock flag, not inherited from host layers.
    public var isLocked: Bool
    /// What the layer draws: shapes, then texts, then instances.
    public var children: [RenderNode]
}

/// One leaf of a render list: a shape or text with everything above it
/// multiplied in.
public struct RenderItem: Sendable, Hashable {
    /// Where the item lives in the document.
    public var address: RenderAddress
    /// The outline in the item's local space; empty for text.
    public var outline: Path
    /// The fill; nil for text.
    public var fill: Fill?
    /// The stroke; nil for text.
    public var stroke: Stroke?
    /// Local to scene space, y down.
    public var matrix: Matrix
    /// The product of every layer opacity on the way down.
    public var opacity: Double
    /// Whether the leaf layer or any host layer above it is locked.
    public var isLocked: Bool
    /// Whether the item is a text, which has no outline, fill or stroke.
    public var isText: Bool
}

/// Where an item lives in the document.
public struct RenderAddress: Sendable, Hashable {
    /// The layer list the walk started from.
    public var owner: LayerOwner
    /// The instances on the way down, from the top; empty at top level.
    public var hosts: [InstanceHost]
    /// The leaf layer.
    public var layerID: String
    /// The position in the leaf layer's `shapes`; nil for text.
    public var shapeIndex: Int?
    /// The position in the leaf layer's `texts`; nil for shapes.
    public var textIndex: Int?

    /// An address built from a selection the caller holds, e.g. for
    /// `RenderList.worldBounds(of:)`.
    public init(owner: LayerOwner, hosts: [InstanceHost], layerID: String, shapeIndex: Int?, textIndex: Int?) {
        self.owner = owner
        self.hosts = hosts
        self.layerID = layerID
        self.shapeIndex = shapeIndex
        self.textIndex = textIndex
    }
}

/// One instance on the way down to an item: its layer and its index there.
public struct InstanceHost: Sendable, Hashable {
    /// The layer holding the instance.
    public var layerID: String
    /// The position in that layer's `instances`.
    public var instanceIndex: Int

    /// The instance at `instanceIndex` in layer `layerID`.
    public init(layerID: String, instanceIndex: Int) {
        self.layerID = layerID
        self.instanceIndex = instanceIndex
    }
}

extension Scene {
    /// The scene's render list at `frame`; `symbols` are the document's symbols.
    public func renderList(at frame: Double, symbols: [Symbol]) -> RenderList {
        RenderList(layers: layers, owner: .scene(id), frame: frame, symbols: symbols, path: [])
    }
}

extension Symbol {
    /// The symbol's own layers at `frame`, for editing it in place. An
    /// instance of this symbol inside it counts as a cycle.
    public func renderList(at frame: Double, symbols: [Symbol]) -> RenderList {
        RenderList(layers: layers, owner: .symbol(id), frame: frame, symbols: symbols, path: [id])
    }
}

extension RenderList {
    init(layers: [Layer], owner: LayerOwner, frame: Double, symbols: [Symbol], path: [String]) {
        var walker = Walker(owner: owner, symbols: symbols)
        nodes = walker.walk(layers, frame: frame, path: path, hosts: [], parent: .identity, opacity: 1, locked: false)
        items = walker.items
    }

    /// Collects `items` while it builds the tree, so both come from one walk.
    /// Depth is bounded by `Instance.resolve` (`Instance.maxNestingDepth`),
    /// total size by `maxRenderItems`: `built` counts items and nodes.
    private struct Walker {
        let owner: LayerOwner
        let symbols: [Symbol]
        var items: [RenderItem] = []
        var built = 0

        mutating func walk(
            _ layers: [Layer], frame: Double, path: [String], hosts: [InstanceHost],
            parent: Matrix, opacity: Double, locked: Bool
        ) -> [RenderNode] {
            var nodes: [RenderNode] = []
            let owner = self.owner
            for layer in layers where layer.isVisible {
                let (t, o) = layer.placement(at: frame)
                let m = parent * t.matrix
                let op = opacity * o
                let lk = locked || layer.isLocked
                func item(_ outline: Path, _ fill: Fill?, _ stroke: Stroke?, shape: Int?, text: Int?) -> RenderItem {
                    let address = RenderAddress(owner: owner, hosts: hosts, layerID: layer.id,
                                                shapeIndex: shape, textIndex: text)
                    return RenderItem(address: address, outline: outline, fill: fill, stroke: stroke,
                                      matrix: m, opacity: op, isLocked: lk, isText: text != nil)
                }
                var children: [RenderNode] = []
                built += 1 + 2 * (layer.shapes.count + layer.texts.count)
                for (i, s) in layer.shapes.enumerated() {
                    children.append(.shape(index: i, s))
                    items.append(item(s.outline, s.fill, s.stroke, shape: i, text: nil))
                }
                for (i, x) in layer.texts.enumerated() {
                    children.append(.text(index: i, x))
                    items.append(item(Path(), nil, nil, shape: nil, text: i))
                }
                for (i, inst) in layer.instances.enumerated() {
                    built += 1
                    guard built < RenderList.maxRenderItems,
                          let (symbol, local) = inst.resolve(in: symbols, frame: frame, path: path) else {
                        children.append(.unresolved(index: i, symbolID: inst.symbolID))
                        continue
                    }
                    let inner = walk(symbol.layers, frame: local, path: path + [symbol.id],
                                     hosts: hosts + [InstanceHost(layerID: layer.id, instanceIndex: i)],
                                     parent: m * inst.transform.matrix, opacity: op, locked: lk)
                    children.append(.instance(index: i, inst, symbolID: symbol.id, frame: local, children: inner))
                }
                nodes.append(.layer(RenderLayer(id: layer.id, name: layer.name, transform: t, opacity: o,
                                                isLocked: layer.isLocked, children: children)))
            }
            return nodes
        }
    }
}
