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
    case layer(RenderLayer)
    /// A layer's shape, in its layer's space.
    case shape(index: Int, Shape)
    case text(index: Int, TextShape)
    /// An instance holding its symbol's layers at the symbol `frame`.
    case instance(index: Int, Instance, symbolID: String, frame: Double, children: [RenderNode])
    /// An instance whose symbol is missing, cyclic or nested too deep.
    case unresolved(index: Int, symbolID: String)
}

/// A visible layer: its sampled local transform and opacity, its own lock
/// flag, and what it draws in paint order.
public struct RenderLayer: Sendable, Hashable {
    public var id: String
    public var name: String
    public var transform: Transform
    public var opacity: Double
    public var isLocked: Bool
    public var children: [RenderNode]
}

public struct RenderItem: Sendable, Hashable {
    public var address: RenderAddress
    public var outline: Path             // in the item's local space; empty for text
    public var fill: Fill?               // nil for text
    public var stroke: Stroke?
    public var matrix: Matrix            // local -> scene space, y down
    public var opacity: Double           // product of every layer opacity on the way down
    public var isLocked: Bool            // the leaf layer or any host layer above it is locked
    public var isText: Bool
}

/// Where an item lives in the document.
public struct RenderAddress: Sendable, Hashable {
    public var owner: LayerOwner         // the layer list the walk started from
    public var hosts: [InstanceHost]     // from the top down; empty at top level
    public var layerID: String           // the leaf layer
    public var shapeIndex: Int?          // nil for text
    public var textIndex: Int?           // nil for shapes
}

/// One instance on the way down to an item: its layer and its index there.
public struct InstanceHost: Sendable, Hashable {
    public var layerID: String
    public var instanceIndex: Int
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
    /// Depth is bounded by `Instance.resolve` (`Instance.maxNestingDepth`).
    private struct Walker {
        let owner: LayerOwner
        let symbols: [Symbol]
        var items: [RenderItem] = []

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
                for (i, s) in layer.shapes.enumerated() {
                    children.append(.shape(index: i, s))
                    items.append(item(s.outline, s.fill, s.stroke, shape: i, text: nil))
                }
                for (i, x) in layer.texts.enumerated() {
                    children.append(.text(index: i, x))
                    items.append(item(Path(), nil, nil, shape: nil, text: i))
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
