// RenderList.swift: what one frame of a scene (or a symbol) draws, built from
// one walk of its layers. The stage, hit testing, bounds and the SVG exporter
// all read it, so they agree on paint order and on what is visible.
//
// `nodes` keeps the layer and instance structure (one node per visible layer,
// empty ones included) for exporters that write groups; `items` is the flat
// list of leaves in paint order, with matrices and opacity multiplied down.
//
// Paint order is the SVG exporter's: layers in array order; inside a layer,
// its shapes, then its texts, then its instances, each instance's symbol
// layers recursively. Later items paint on top.
//
// Invariants:
// - a hidden layer is absent from both `nodes` and `items`, with everything
//   on it (instances included)
// - an item's opacity is the product of every layer opacity on its way down;
//   instances have no opacity of their own
// - an item is locked when its layer or any host layer above it is locked
// - an instance whose symbol is missing, cyclic or nested too deep is an
//   `.unresolved` node and adds no items; building never throws or traps
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public struct RenderList: Sendable, Hashable {
    /// The tree, for exporters that keep groups: one node per visible layer.
    public var nodes: [RenderNode]
    /// The leaves in paint order, matrices and opacity already multiplied
    /// down the tree: what the stage draws and hit testing reads.
    public var items: [RenderItem]
}

public indirect enum RenderNode: Sendable, Hashable {
    /// A visible layer and what it draws, in paint order.
    case layer(RenderLayer)
    /// A layer's shape, in its layer's space.
    case shape(index: Int, Shape)
    case text(index: Int, TextShape)
    /// An instance holding its symbol's layers at the symbol `frame`.
    case instance(index: Int, Instance, symbolID: String, frame: Double, children: [RenderNode])
    /// An instance whose symbol is missing, cyclic or nested too deep.
    case unresolved(index: Int, symbolID: String)
}

/// A visible layer with its sampled local transform and opacity at the frame.
public struct RenderLayer: Sendable, Hashable {
    public var id: String
    public var name: String
    public var transform: Transform
    public var opacity: Double
    /// The layer's own flag; `RenderItem.isLocked` adds the host layers'.
    public var isLocked: Bool
    public var children: [RenderNode]
}

public struct RenderItem: Sendable, Hashable {
    public var address: RenderAddress
    /// In the item's local space; empty for text.
    public var outline: Path
    /// Nil for text.
    public var fill: Fill?
    public var stroke: Stroke?
    /// Local -> scene space, y down.
    public var matrix: Matrix
    /// Product of every layer opacity on the way down.
    public var opacity: Double
    /// The leaf layer or any host layer above it is locked.
    public var isLocked: Bool
    public var isText: Bool
}

/// Where an item lives in the document.
public struct RenderAddress: Sendable, Hashable {
    /// The layer list the walk started from.
    public var owner: LayerOwner
    /// (layerID, instanceIndex) from the top down; empty at top level.
    public var hosts: [InstanceHost]
    /// The leaf layer.
    public var layerID: String
    /// Nil for text.
    public var shapeIndex: Int?
    /// Nil for shapes.
    public var textIndex: Int?

    public init(owner: LayerOwner, hosts: [InstanceHost] = [], layerID: String,
                shapeIndex: Int? = nil, textIndex: Int? = nil) {
        self.owner = owner
        self.hosts = hosts
        self.layerID = layerID
        self.shapeIndex = shapeIndex
        self.textIndex = textIndex
    }
}

/// One instance on the way down to an item: its layer and its index there.
public struct InstanceHost: Sendable, Hashable {
    public var layerID: String
    public var instanceIndex: Int

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
        nodes = walker.walk(layers, frame: frame, path: path, hosts: [],
                            parent: .identity, opacity: 1, locked: false)
        items = walker.items
    }

    /// Collects `items` while it builds the tree, so both come from one walk.
    private struct Walker {
        let owner: LayerOwner
        let symbols: [Symbol]
        var items: [RenderItem] = []

        /// Depth is bounded by `Instance.resolve`, which refuses paths
        /// `Instance.maxNestingDepth` deep.
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
                func item(_ outline: Path, _ fill: Fill?, _ stroke: Stroke?,
                          shape: Int? = nil, text: Int? = nil) -> RenderItem {
                    let address = RenderAddress(owner: owner, hosts: hosts, layerID: layer.id,
                                                shapeIndex: shape, textIndex: text)
                    return RenderItem(address: address, outline: outline, fill: fill, stroke: stroke,
                                      matrix: m, opacity: op, isLocked: lk, isText: text != nil)
                }
                var children: [RenderNode] = []
                for (i, s) in layer.shapes.enumerated() {
                    children.append(.shape(index: i, s))
                    items.append(item(s.outline, s.fill, s.stroke, shape: i))
                }
                for (i, x) in layer.texts.enumerated() {
                    children.append(.text(index: i, x))
                    items.append(item(Path(), nil, nil, text: i))
                }
                for (i, inst) in layer.instances.enumerated() {
                    guard let (symbol, local) = inst.resolve(in: symbols, frame: frame, path: path) else {
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
