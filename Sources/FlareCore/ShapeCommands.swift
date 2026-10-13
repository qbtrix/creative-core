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
    public static let all: [any Command.Type] = [RemoveShape.self, SetShapeFill.self, TranslateShape.self]
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

/// Moves every point of a shape, including its path, by (dx, dy). Consecutive
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

extension Shape {
    /// This shape moved by (dx, dy): its points and every point of its path.
    public func translated(dx: Double, dy: Double) -> Shape {
        var s = self
        s.points = points.map { $0.translated(dx: dx, dy: dy) }
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
