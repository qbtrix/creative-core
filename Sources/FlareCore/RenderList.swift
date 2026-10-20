// RenderList.swift: what one frame of a scene or symbol draws, built from one
// walk of its layers, so the stage, hit testing, bounds, PNG frames and the SVG
// exporter agree. Every shape is drawn as `Layer.sampledShape` gives it at the
// frame (an instance's at its symbol frame): fill and stroke colour, stroke
// width, trim and path keys included, in both `nodes` and `items`. `nodes`
// keeps the layer and instance tree (one node per visible
// layer, empty ones included); `items` are its leaves in paint order. Paint
// order is the SVG exporter's: layers in order; in a layer its shapes, then
// texts, then instances, each instance's symbol layers recursively.
//
// Invariants:
// - a hidden layer is absent from `nodes` and `items`, with all it holds; one
//   a visible layer of its list uses as a track matte lists in `matteItems`
// - an item's `clips` are its layer's and every host layer's masks through
//   that layer's scene matrix, outermost first; its `matte` is the nearest
//   matted layer's on its way down, naming the source layer's items, which
//   are flagged `isMatteSource`
// - an item's opacity is the product of every layer opacity on its way down;
//   instances have no opacity of their own
// - a layer with a parent (`Layer.parentID`, same list) is placed by its
//   parent chain's matrices, hidden parents included, before its own; its
//   opacity, lock and visibility are its own
// - an item is locked when its layer or any host layer above it is locked
// - an instance whose symbol is missing, cyclic or nested too deep is an
//   `.unresolved` node and adds no items; building never throws or traps
// - the owner's own layers always list fully; only what instance expansion
//   builds is charged to `RenderList.maxExpandedPoints`: the outline points of
//   each expanded shape and the mask path points of each expanded layer, plus one more than its nesting depth per expanded
//   node and item (each carries its chain of hosts). Once it is spent,
//   every further instance is an `.unresolved` node, not expanded, and
//   `isTruncated` is true, so a small file whose symbols fan out (two
//   instances per symbol, 40 deep, or 14 deep over a huge shape) cannot build
//   2^40 items or billions of points; a symbol already being walked still
//   lists its own leaves
// - each symbol shape's outline is built once per walk and shared by every
//   item that expands it, except a shape with a shape track, whose outline
//   depends on the frame
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// What one frame of a scene or symbol draws: its layer and instance tree
/// and the tree's leaves in paint order. Instance expansion stops once it
/// has spent `maxExpandedPoints`; later instances are `.unresolved` and
/// `isTruncated` is true, which the SVG exporter rejects with `sceneTooLarge`.
public struct RenderList: Sendable, Hashable {
    /// The budget one walk spends on instance expansion before it stops
    /// expanding: the outline points of every shape and the mask path points
    /// of every layer built under an instance, plus, per node and item built there, one more than its nesting depth
    /// (the hosts its address carries). The owner's own layers are not
    /// charged, so this does not cap `items.count`: a layer with more shapes
    /// than this lists them all. Four times the file format's point cap (a
    /// test pins the ratio; evaluation does not read the format layer), so a
    /// file at that cap can still draw every stored point in four instances,
    /// while a file whose symbols fan out stops after a few million points
    /// (or about 16,000 leaves 40 deep) instead of billions.
    public static let maxExpandedPoints = 4_000_000

    /// The tree, for exporters that keep groups: one node per visible layer.
    public var nodes: [RenderNode]
    /// The leaves in paint order, matrices and opacity already multiplied
    /// down the tree: what the stage draws and hit testing reads.
    public var items: [RenderItem]
    /// The items of hidden layers that a visible layer uses as a track
    /// matte: read only through `MatteLink`, never drawn or hit. Mattes are
    /// one level deep, as in the exporters: a matte on a hidden matte source
    /// is not resolved, so its items here have `matte` nil (they render
    /// unmatted) and export refuses it as "nested matte".
    public var matteItems: [RenderItem] = []
    /// True when instance expansion stopped at `maxExpandedPoints`: the
    /// instances past the budget are `.unresolved` nodes with no items, even
    /// though their symbols exist.
    public var isTruncated = false
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
    /// came after the walk spent `RenderList.maxExpandedPoints` (then the
    /// list's `isTruncated` is true); `index` is its
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
    /// Its parent layers' matrices multiplied down to it (`Layer.parentID`); identity without a parent. The
    /// layer's matrix in its list is `parentMatrix * transform.matrix`.
    public var parentMatrix: Matrix = .identity
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
    /// The masks of its layer and every host layer above it, in scene
    /// space, outermost host first and each layer's masks in order.
    public var clips: [ClipMask] = []
    /// The track matte of its nearest matted layer (its own or a host's);
    /// always nil on an item in `matteItems`: one matte level only.
    public var matte: MatteLink?
    /// Whether some visible layer of its list uses its layer as a matte.
    public var isMatteSource = false

    /// The path the stroke paints in the item's local space: the outline
    /// trimmed, then dashed (`Stroke.paintedPath`); nil without a stroke.
    /// Throws as `Path.trimmed` and `Path.dashed` do.
    public func strokePath(tolerance: Double) throws -> Path? {
        try stroke?.paintedPath(outline, tolerance: tolerance)
    }
}

/// A layer mask carried into scene space that clips the item, one per mask
/// on the way down to it.
public struct ClipMask: Sendable, Hashable {
    /// The mask's path through its layer's scene matrix. An open subpath is
    /// implicitly closed.
    public var path: Path
    /// How it combines with the masks before it on the same layer.
    public var mode: MaskMode
    /// The feather radius in scene units: renderers blur with sigma =
    /// feather / 3, the same radius `Mask.feathered(radius:)` takes. It is the
    /// mask's own feather times the uniform scale of its layer's scene matrix,
    /// sqrt(|det|), the same matrix `path` went through, so a feather of 10
    /// under a 4x instance is 40; a feather of 0 stays 0 under any matrix.
    public var feather: Double
    /// Mask strength, 0...1.
    public var opacity: Double
    /// Whether it keeps what lies outside `path`.
    public var inverted: Bool
    /// The number of instances above the mask's layer; masks combine by
    /// mode only within one layer, and each layer's result intersects.
    public var depth: Int

    public init(path: Path, mode: MaskMode, feather: Double, opacity: Double, inverted: Bool, depth: Int) {
        (self.path, self.mode, self.feather, self.opacity, self.inverted, self.depth) =
            (path, mode, feather, opacity, inverted, depth)
    }
}

/// An item's track matte: its source layer's items and what to read from them.
/// One level only: a hidden source's own matte gets no link.
public struct MatteLink: Sendable, Hashable {
    /// The source layer's items: positions in `RenderList.matteItems` when
    /// `inMatteItems` (a hidden source), else in `RenderList.items`.
    public var sourceItems: Range<Int>
    /// Whether `sourceItems` index `matteItems` rather than `items`.
    public var inMatteItems: Bool
    /// Which of the source's values limits the item.
    public var kind: MatteKind

    public init(sourceItems: Range<Int>, inMatteItems: Bool, kind: MatteKind) {
        (self.sourceItems, self.inMatteItems, self.kind) = (sourceItems, inMatteItems, kind)
    }
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
    /// `RenderList.worldBounds(of:)`. Exactly one of `shapeIndex` and
    /// `textIndex` is non-nil, as in the addresses `hit` and `marquee`
    /// return; any other address matches no item.
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

extension Matrix {
    /// sqrt(|determinant|), the uniform scale of the linear part, without
    /// overflow or underflow for finite entries: they are divided by the
    /// largest first, so a 1e160 scale gives 1e160, not infinity.
    var uniformScale: Double {
        let k = Swift.max(abs(a), abs(b), abs(c), abs(d))
        guard k > 0, k.isFinite else { return k }
        return abs((a / k) * (d / k) - (b / k) * (c / k)).squareRoot() * k
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
        nodes = walker.walk(layers, symbol: nil, frame: frame, path: path, hosts: [],
                            parent: .identity, opacity: 1, locked: false, clips: [])
        items = walker.items
        matteItems = walker.matteItems
        isTruncated = walker.isTruncated
    }

    /// A shape's outline and the points it stores, built once per walk.
    private struct Outline {
        var path: Path
        var points: Int

        init(_ shape: Shape) {
            path = shape.outline
            points = path.elements.reduce(0) { $0 + $1.pointCount }
        }
    }

    /// Collects `items` while it builds the tree, so both come from one walk.
    /// Depth is bounded by `Instance.resolve` (`Instance.maxNestingDepth`),
    /// total size by `maxExpandedPoints`: `expanded` charges what is built
    /// under an instance (outline and mask points, plus `1 + nesting depth` per node
    /// and item).
    private struct Walker {
        let owner: LayerOwner
        let symbols: [Symbol]
        var items: [RenderItem] = [], matteItems: [RenderItem] = []
        /// True while walking a hidden matte source: its items go to `matteItems`.
        var matteOnly = false
        var expanded = 0
        var isTruncated = false
        /// Per symbol id, each layer's shape outlines.
        var outlines: [String: [[Outline]]] = [:]

        /// `symbol` is the id of the symbol whose layers these are, nil for
        /// the owner's own layers, which are not charged to the budget.
        mutating func walk(
            _ layers: [Layer], symbol: String?, frame: Double, path: [String], hosts: [InstanceHost],
            parent: Matrix, opacity: Double, locked: Bool, clips: [ClipMask]
        ) -> [RenderNode] {
            var nodes: [RenderNode] = []
            let owner = self.owner
            // What one node or item costs here: it carries its host chain.
            let weight = symbol == nil ? 0 : 1 + hosts.count
            var cached: [[Outline]]?
            if let symbol {
                cached = outlines[symbol] ?? layers.map { $0.shapes.map(Outline.init) }
                outlines[symbol] = cached
            }
            // Hidden layers a visible one uses as a matte are walked into `matteItems` only.
            let wanted = Set(layers.filter(\.isVisible).compactMap { $0.matte?.sourceLayerID })
            var spans: [String: (items: Range<Int>, inMatteItems: Bool)] = [:]
            // Parents name layers of this list; validation keeps the chains acyclic, and the hop bound holds anyway.
            let byID = layers.contains { $0.parentID != nil }
                ? Dictionary(layers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) : [:]
            func parentMatrix(of layer: Layer) -> Matrix {
                var m = Matrix.identity, next = layer.parentID, hops = 0
                while let id = next, let p = byID[id], hops < layers.count {
                    m = p.placement(at: frame).transform.matrix * m
                    (next, hops) = (p.parentID, hops + 1)
                }
                return m
            }
            for (li, layer) in layers.enumerated() where layer.isVisible || wanted.contains(layer.id) {
                let outer = matteOnly
                matteOnly = outer || !layer.isVisible
                defer { matteOnly = outer }
                let start = matteOnly ? matteItems.count : items.count
                let (t, o) = layer.placement(at: frame)
                let up = byID.isEmpty ? Matrix.identity : parentMatrix(of: layer)
                let m = byID.isEmpty ? parent * t.matrix : parent * up * t.matrix
                let op = opacity * o
                let lk = locked || layer.isLocked
                let scale = m.uniformScale
                // Each walk under an instance copies the layer's masks into scene space.
                if symbol != nil { expanded += layer.masks.reduce(0) { $0 + $1.path.elements.reduce(0) { $0 + $1.pointCount } } }
                let own = clips + layer.masks.map {
                    ClipMask(path: $0.path.transformed(by: m), mode: $0.mode, feather: $0.feather * scale,
                                opacity: $0.opacity, inverted: $0.inverted, depth: hosts.count)
                }
                func item(_ outline: Path, _ fill: Fill?, _ stroke: Stroke?, shape: Int?, text: Int?) -> RenderItem {
                    let address = RenderAddress(owner: owner, hosts: hosts, layerID: layer.id,
                                                shapeIndex: shape, textIndex: text)
                    var item = RenderItem(address: address, outline: outline, fill: fill, stroke: stroke,
                                          matrix: m, opacity: op, isLocked: lk, isText: text != nil)
                    item.clips = own
                    return item
                }
                var children: [RenderNode] = []
                let shared = cached?[li]
                expanded += weight * (1 + 2 * (layer.shapes.count + layer.texts.count))
                for i in layer.shapes.indices {
                    let s = layer.sampledShape(i, at: frame)
                    children.append(.shape(index: i, s))
                    if let cachedOutline = shared?[i] {
                        // A shape track changes the path with the frame, so its outline is never the shared one.
                        let outline = layer.shapeTracks.contains { $0.shapeIndex == i } ? Outline(s) : cachedOutline
                        expanded += outline.points
                        add(item(outline.path, s.fill, s.stroke, shape: i, text: nil))
                    } else {
                        add(item(s.outline, s.fill, s.stroke, shape: i, text: nil))
                    }
                }
                for (i, x) in layer.texts.enumerated() {
                    children.append(.text(index: i, x))
                    add(item(Path(), nil, nil, shape: nil, text: i))
                }
                for (i, inst) in layer.instances.enumerated() {
                    expanded += weight
                    guard let (target, local) = inst.resolve(in: symbols, frame: frame, path: path) else {
                        children.append(.unresolved(index: i, symbolID: inst.symbolID))
                        continue
                    }
                    guard expanded < RenderList.maxExpandedPoints else {
                        isTruncated = true
                        children.append(.unresolved(index: i, symbolID: inst.symbolID))
                        continue
                    }
                    let inner = walk(target.layers, symbol: target.id, frame: local, path: path + [target.id],
                                     hosts: hosts + [InstanceHost(layerID: layer.id, instanceIndex: i)],
                                     parent: m * inst.transform.matrix, opacity: op, locked: lk, clips: own)
                    children.append(.instance(index: i, inst, symbolID: target.id, frame: local, children: inner))
                }
                spans[layer.id] = (start..<(matteOnly ? matteItems.count : items.count), matteOnly)
                guard layer.isVisible else { continue }
                var node = RenderLayer(id: layer.id, name: layer.name, transform: t, opacity: o,
                                       isLocked: layer.isLocked, children: children)
                node.parentMatrix = up
                nodes.append(.layer(node))
            }
            // Inner walks linked their own mattes first, so a matte nearer the item wins.
            for layer in layers where layer.isVisible {
                guard let matte = layer.matte, let source = spans[matte.sourceLayerID], let span = spans[layer.id] else { continue }
                update(source.items, inMatteItems: source.inMatteItems) { $0.isMatteSource = true }
                let link = MatteLink(sourceItems: source.items, inMatteItems: source.inMatteItems, kind: matte.kind)
                update(span.items, inMatteItems: span.inMatteItems) { if $0.matte == nil { $0.matte = link } }
            }
            return nodes
        }

        private mutating func add(_ item: RenderItem) {
            if matteOnly { matteItems.append(item) } else { items.append(item) }
        }

        private mutating func update(_ range: Range<Int>, inMatteItems: Bool, _ change: (inout RenderItem) -> Void) {
            if inMatteItems {
                for i in range.clamped(to: matteItems.indices) { change(&matteItems[i]) }
            } else {
                for i in range.clamped(to: items.indices) { change(&items[i]) }
            }
        }
    }
}
