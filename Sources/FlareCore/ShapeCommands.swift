// ShapeCommands.swift: edits to existing shapes, addressed by owner, layer and
// shape index. A bad index throws shapeNotFound; a locked layer throws
// layerLocked. Undo restores the stored old value, so it is exact even where
// floating-point arithmetic would not round-trip.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The shape edit commands.
public enum ShapeCommands {
    public static let all: [any Command.Type] = [
        RemoveShape.self, SetShapeFill.self, SetShapeStroke.self, SetShapePath.self, TranslateShape.self,
    ]
}

extension Layer {
    func checkShapeIndex(_ index: Int) throws {
        guard shapes.indices.contains(index) else { throw CommandError.shapeNotFound(index) }
    }
}

public struct RemoveShape: LayerItemCommand {
    public static let id = "shape.remove"
    public var label: String { "Delete Shape" }
    public var owner: LayerOwner
    public var layerID: String
    public var index: Int
    var removed: Shape?

    public init(owner: LayerOwner, layerID: String, index: Int) {
        self.owner = owner
        self.layerID = layerID
        self.index = index
    }

    public mutating func execute(_ document: inout Document) throws {
        let index = index
        removed = try document.withEditableLayer(owner, layer: layerID) { layer in
            try layer.checkShapeIndex(index)
            return layer.shapes.remove(at: index)
        }
    }

    public func undo(_ document: inout Document) throws {
        guard let removed else { throw CommandError.notExecuted }
        let index = index
        try document.withLayer(owner, layer: layerID) { layer in
            guard index >= 0, index <= layer.shapes.count else { throw CommandError.shapeNotFound(index) }
            layer.shapes.insert(removed, at: index)
        }
    }
}

public struct SetShapeFill: LayerParamsCommand {
    public static let id = "shape.setFill"
    public var label: String { "Set Fill" }
    public var owner: LayerOwner
    public var layerID: String
    public var index: Int
    public var fill: Fill
    var oldFill: Fill?

    public init(owner: LayerOwner, layerID: String, index: Int, fill: Fill) {
        self.owner = owner
        self.layerID = layerID
        self.index = index
        self.fill = fill
    }

    struct Params: Codable { var index: Int; var fill: Fill }
    var params: Params { Params(index: index, fill: fill) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, index: params.index, fill: params.fill)
    }

    public mutating func execute(_ document: inout Document) throws {
        try fill.validate()
        let (index, fill) = (index, fill)
        oldFill = try document.withEditableLayer(owner, layer: layerID) { layer in
            try layer.checkShapeIndex(index)
            defer { layer.shapes[index].fill = fill }
            return layer.shapes[index].fill
        }
    }

    public func undo(_ document: inout Document) throws {
        guard let oldFill else { throw CommandError.notExecuted }
        let index = index
        try document.withLayer(owner, layer: layerID) { layer in
            try layer.checkShapeIndex(index)
            layer.shapes[index].fill = oldFill
        }
    }
}

/// Sets or, with nil, removes a shape's stroke. A negative or non-finite
/// width or a non-finite color throws before anything changes.
public struct SetShapeStroke: LayerParamsCommand {
    public static let id = "shape.setStroke"
    public var label: String { "Set Stroke" }
    public var owner: LayerOwner
    public var layerID: String
    public var index: Int
    public var stroke: Stroke?
    /// The stroke before execute; the outer optional is nil until it runs.
    var oldStroke: Stroke??

    public init(owner: LayerOwner, layerID: String, index: Int, stroke: Stroke?) {
        self.owner = owner
        self.layerID = layerID
        self.index = index
        self.stroke = stroke
    }

    struct Params: Codable { var index: Int; var stroke: Stroke? }
    var params: Params { Params(index: index, stroke: stroke) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, index: params.index, stroke: params.stroke)
    }

    public mutating func execute(_ document: inout Document) throws {
        try stroke?.validate()
        let (index, stroke) = (index, stroke)
        oldStroke = try document.withEditableLayer(owner, layer: layerID) { layer in
            try layer.checkShapeIndex(index)
            defer { layer.shapes[index].stroke = stroke }
            return .some(layer.shapes[index].stroke)
        }
    }

    public func undo(_ document: inout Document) throws {
        guard let oldStroke else { throw CommandError.notExecuted }
        let index = index
        try document.withLayer(owner, layer: layerID) { layer in
            try layer.checkShapeIndex(index)
            layer.shapes[index].stroke = oldStroke
        }
    }
}

/// Replaces a shape's curved path and its points together. A non-finite
/// point in either throws invalidDocument before anything changes.
public struct SetShapePath: LayerParamsCommand {
    public static let id = "shape.setPath"
    public var label: String { "Edit Path" }
    public var owner: LayerOwner
    public var layerID: String
    public var index: Int
    public var path: Path?
    public var points: [Point]
    var old: (path: Path?, points: [Point])?

    public init(owner: LayerOwner, layerID: String, index: Int, path: Path?, points: [Point]) {
        self.owner = owner
        self.layerID = layerID
        self.index = index
        self.path = path
        self.points = points
    }

    struct Params: Codable { var index: Int; var path: Path?; var points: [Point] }
    var params: Params { Params(index: index, path: path, points: points) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, index: params.index, path: params.path, points: params.points)
    }

    public mutating func execute(_ document: inout Document) throws {
        let all = points + (path?.elements.flatMap(\.points) ?? [])
        guard all.allSatisfy(\.isFinite) else { throw CommandError.invalidDocument("shape has a non-finite point") }
        let (index, path, points) = (index, path, points)
        old = try document.withEditableLayer(owner, layer: layerID) { layer in
            try layer.checkShapeIndex(index)
            let shape = layer.shapes[index]
            layer.shapes[index].path = path
            layer.shapes[index].points = points
            return (shape.path, shape.points)
        }
    }

    public func undo(_ document: inout Document) throws {
        guard let old else { throw CommandError.notExecuted }
        let index = index
        try document.withLayer(owner, layer: layerID) { layer in
            try layer.checkShapeIndex(index)
            layer.shapes[index].path = old.path
            layer.shapes[index].points = old.points
        }
    }
}

/// Moves every point of a shape, including its path and its gradient's start,
/// end or center, by (dx, dy). Consecutive
/// moves of the same shape merge: dx and dy add up, and the merged command keeps
/// the first old shape and the last new one, so redo gives back the exact
/// dragged shape rather than one translation by the rounded sum.
public struct TranslateShape: LayerParamsCommand {
    public static let id = "shape.translate"
    public var label: String { "Move Shape" }
    public var owner: LayerOwner
    public var layerID: String
    public var index: Int
    public var dx: Double
    public var dy: Double
    var oldShape: Shape?
    var newShape: Shape?

    public init(owner: LayerOwner, layerID: String, index: Int, dx: Double, dy: Double) {
        self.owner = owner
        self.layerID = layerID
        self.index = index
        self.dx = dx
        self.dy = dy
    }

    struct Params: Codable { var index: Int; var dx: Double; var dy: Double }
    var params: Params { Params(index: index, dx: dx, dy: dy) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, index: params.index, dx: params.dx, dy: params.dy)
    }

    public mutating func execute(_ document: inout Document) throws {
        let (index, dx, dy, recordedOld, recordedNew) = (index, dx, dy, oldShape, newShape)
        (oldShape, newShape) = try document.withEditableLayer(owner, layer: layerID) { layer in
            try layer.checkShapeIndex(index)
            let old = layer.shapes[index]
            // Redo from the recorded start replays the recorded result exactly.
            let new = old == recordedOld ? recordedNew ?? old.translated(dx: dx, dy: dy)
                : old.translated(dx: dx, dy: dy)
            layer.shapes[index] = new
            return (old, new)
        }
    }

    public mutating func merge(_ next: TranslateShape) -> Bool {
        guard oldShape != nil, next.oldShape == newShape, next.newShape != nil,
              (next.owner, next.layerID, next.index) == (owner, layerID, index) else { return false }
        dx += next.dx
        dy += next.dy
        newShape = next.newShape
        return true
    }

    public func undo(_ document: inout Document) throws {
        guard let oldShape else { throw CommandError.notExecuted }
        let index = index
        try document.withLayer(owner, layer: layerID) { layer in
            try layer.checkShapeIndex(index)
            layer.shapes[index] = oldShape
        }
    }
}

extension Point {
    func translated(dx: Double, dy: Double) -> Point { Point(x: x + dx, y: y + dy) }
}

extension Fill {
    /// This fill moved by (dx, dy): a gradient's start, end or center, which
    /// are in shape space. A solid fill has no geometry and comes back as is.
    func translated(dx: Double, dy: Double) -> Fill {
        switch self {
        case .solid: self
        case .linear(let stops, let start, let end):
            .linear(stops: stops, start: start.translated(dx: dx, dy: dy), end: end.translated(dx: dx, dy: dy))
        case .radial(let stops, let center, let radius):
            .radial(stops: stops, center: center.translated(dx: dx, dy: dy), radius: radius)
        }
    }
}

extension Shape {
    /// This shape moved by (dx, dy): its points, every point of its path and
    /// its gradient's geometry, so the fill moves with the shape.
    public func translated(dx: Double, dy: Double) -> Shape {
        var s = self
        s.points = points.map { $0.translated(dx: dx, dy: dy) }
        s.fill = fill.translated(dx: dx, dy: dy)
        s.path = path.map { p in
            Path(elements: p.elements.map { e in
                switch e {
                case .move(let to): .move(to: to.translated(dx: dx, dy: dy))
                case .line(let to): .line(to: to.translated(dx: dx, dy: dy))
                case .quad(let c, let to):
                    .quad(control: c.translated(dx: dx, dy: dy), to: to.translated(dx: dx, dy: dy))
                case .cubic(let c1, let c2, let to):
                    .cubic(control1: c1.translated(dx: dx, dy: dy), control2: c2.translated(dx: dx, dy: dy),
                           to: to.translated(dx: dx, dy: dy))
                case .close: .close
                }
            })
        }
        return s
    }
}
