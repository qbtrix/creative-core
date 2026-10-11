// ShapeCommands.swift: edits to existing shapes, addressed by scene, layer and
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

public struct RemoveShape: Command {
    public static let id = "shape.remove"
    public var label: String { "Delete Shape" }
    public var sceneID: String
    public var layerID: String
    public var index: Int
    var removed: Shape?

    private enum CodingKeys: String, CodingKey { case sceneID, layerID, index }

    public init(sceneID: String, layerID: String, index: Int) {
        self.sceneID = sceneID
        self.layerID = layerID
        self.index = index
    }

    public mutating func execute(_ document: inout Document) throws {
        let index = index
        removed = try document.withEditableLayer(scene: sceneID, layer: layerID) { layer in
            try layer.checkShapeIndex(index)
            return layer.shapes.remove(at: index)
        }
    }

    public func undo(_ document: inout Document) throws {
        guard let removed else { throw CommandError.notExecuted }
        let index = index
        try document.withLayer(scene: sceneID, layer: layerID) { layer in
            guard index >= 0, index <= layer.shapes.count else { throw CommandError.shapeNotFound(index) }
            layer.shapes.insert(removed, at: index)
        }
    }
}

public struct SetShapeFill: Command {
    public static let id = "shape.setFill"
    public var label: String { "Set Fill" }
    public var sceneID: String
    public var layerID: String
    public var index: Int
    public var fill: Fill
    var oldFill: Fill?

    private enum CodingKeys: String, CodingKey { case sceneID, layerID, index, fill }

    public init(sceneID: String, layerID: String, index: Int, fill: Fill) {
        self.sceneID = sceneID
        self.layerID = layerID
        self.index = index
        self.fill = fill
    }

    public mutating func execute(_ document: inout Document) throws {
        let (index, fill) = (index, fill)
        oldFill = try document.withEditableLayer(scene: sceneID, layer: layerID) { layer in
            try layer.checkShapeIndex(index)
            defer { layer.shapes[index].fill = fill }
            return layer.shapes[index].fill
        }
    }

    public func undo(_ document: inout Document) throws {
        guard let oldFill else { throw CommandError.notExecuted }
        let index = index
        try document.withLayer(scene: sceneID, layer: layerID) { layer in
            try layer.checkShapeIndex(index)
            layer.shapes[index].fill = oldFill
        }
    }
}

/// Moves every point of a shape, including its path, by (dx, dy).
public struct TranslateShape: Command {
    public static let id = "shape.translate"
    public var label: String { "Move Shape" }
    public var sceneID: String
    public var layerID: String
    public var index: Int
    public var dx: Double
    public var dy: Double
    var oldShape: Shape?

    private enum CodingKeys: String, CodingKey { case sceneID, layerID, index, dx, dy }

    public init(sceneID: String, layerID: String, index: Int, dx: Double, dy: Double) {
        self.sceneID = sceneID
        self.layerID = layerID
        self.index = index
        self.dx = dx
        self.dy = dy
    }

    public mutating func execute(_ document: inout Document) throws {
        let (index, dx, dy) = (index, dx, dy)
        oldShape = try document.withEditableLayer(scene: sceneID, layer: layerID) { layer in
            try layer.checkShapeIndex(index)
            let old = layer.shapes[index]
            layer.shapes[index] = old.translated(dx: dx, dy: dy)
            return old
        }
    }

    public func undo(_ document: inout Document) throws {
        guard let oldShape else { throw CommandError.notExecuted }
        let index = index
        try document.withLayer(scene: sceneID, layer: layerID) { layer in
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
