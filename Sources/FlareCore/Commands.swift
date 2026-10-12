// Commands.swift: the built-in document commands. Each one validates its
// params, throws a CommandError instead of crashing, and records just enough
// in execute() for undo() to restore the document exactly. New commands follow
// the same shape: params first, undo state as optional vars last, and
// CodingKeys that list only the params, so undo state is never encoded.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The layer, keyframe and shape commands, registered in `CommandRegistry.builtIn`.
public enum CoreCommands {
    public static let all: [any Command.Type] = [
        AddLayer.self, RemoveLayer.self, RenameLayer.self,
        SetKeyframe.self, MoveKeyframe.self, RemoveKeyframe.self,
        AddShape.self,
    ]
}

public struct AddLayer: LayerCommand {
    public static let id = "layer.add"
    public var label: String { "Add Layer" }
    public var owner: LayerOwner
    public var layer: Layer
    /// Insert position; nil appends.
    public var index: Int?
    public var layerID: String { layer.id }

    private enum CodingKeys: String, CodingKey { case layer, index }

    public init(owner: LayerOwner, layer: Layer, index: Int? = nil) {
        self.owner = owner
        self.layer = layer
        self.index = index
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(owner: LayerOwner(from: decoder), layer: c.decode(Layer.self, forKey: .layer),
                      index: c.decodeIfPresent(Int.self, forKey: .index))
    }

    public func encode(to encoder: any Encoder) throws {
        try owner.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(layer, forKey: .layer)
        try c.encodeIfPresent(index, forKey: .index)
    }

    public mutating func execute(_ document: inout Document) throws {
        try document.withLayers(owner) { layers in
            guard !layers.contains(where: { $0.id == layer.id }) else { throw CommandError.duplicateID(layer.id) }
            layers.insert(layer, at: min(max(index ?? layers.count, 0), layers.count))
        }
    }

    public func undo(_ document: inout Document) throws {
        var remove = RemoveLayer(owner: owner, layerID: layer.id)
        try remove.execute(&document)
    }
}

public struct RemoveLayer: LayerCommand {
    public static let id = "layer.remove"
    public var label: String { "Delete Layer" }
    public var owner: LayerOwner
    public var layerID: String
    var removed: Layer?
    var removedIndex: Int?

    public init(owner: LayerOwner, layerID: String) {
        self.owner = owner
        self.layerID = layerID
    }

    public init(from decoder: any Decoder) throws { (owner, layerID) = try Self.decodeAddress(from: decoder) }
    public func encode(to encoder: any Encoder) throws { try encodeAddress(to: encoder) }

    public mutating func execute(_ document: inout Document) throws {
        let id = layerID
        (removed, removedIndex) = try document.withLayers(owner) { layers in
            guard let i = layers.firstIndex(where: { $0.id == id }) else { throw CommandError.layerNotFound(id) }
            return (layers.remove(at: i), i)
        }
    }

    public func undo(_ document: inout Document) throws {
        guard let removed, let removedIndex else { throw CommandError.notExecuted }
        try document.withLayers(owner) { layers in
            layers.insert(removed, at: min(removedIndex, layers.count))
        }
    }
}

public struct RenameLayer: LayerCommand {
    public static let id = "layer.rename"
    public var label: String { "Rename Layer" }
    public var owner: LayerOwner
    public var layerID: String
    public var name: String
    var oldName: String?

    private enum CodingKeys: String, CodingKey { case name }

    public init(owner: LayerOwner, layerID: String, name: String) {
        self.owner = owner
        self.layerID = layerID
        self.name = name
    }

    public init(from decoder: any Decoder) throws {
        (owner, layerID) = try Self.decodeAddress(from: decoder)
        name = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .name)
    }

    public func encode(to encoder: any Encoder) throws {
        try encodeAddress(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
    }

    public mutating func execute(_ document: inout Document) throws {
        let newName = name
        oldName = try document.withLayer(owner, layer: layerID) { layer in
            defer { layer.name = newName }
            return layer.name
        }
    }

    public func undo(_ document: inout Document) throws {
        guard let oldName else { throw CommandError.notExecuted }
        try document.withLayer(owner, layer: layerID) { $0.name = oldName }
    }
}

public struct SetKeyframe: Command {
    public static let id = "keyframe.set"
    public var label: String { "Set Keyframe" }
    public var sceneID: String
    public var layerID: String
    public var property: String
    public var keyframe: Keyframe
    var previous: Keyframe?
    var executed: Bool?

    private enum CodingKeys: String, CodingKey { case sceneID, layerID, property, keyframe }

    public init(sceneID: String, layerID: String, property: String, keyframe: Keyframe) {
        self.sceneID = sceneID
        self.layerID = layerID
        self.property = property
        self.keyframe = keyframe
    }

    public mutating func execute(_ document: inout Document) throws {
        guard keyframe.frame >= 0 else { throw CommandError.invalidFrame(keyframe.frame) }
        let (k, p) = (keyframe, property)
        previous = try document.withEditableLayer(scene: sceneID, layer: layerID) { $0.setKeyframe(k, property: p) }
        executed = true
    }

    public func undo(_ document: inout Document) throws {
        guard executed == true else { throw CommandError.notExecuted }
        let (frame, p, previous) = (keyframe.frame, property, previous)
        try document.withLayer(scene: sceneID, layer: layerID) { layer in
            if let previous {
                layer.setKeyframe(previous, property: p)
            } else {
                layer.removeKeyframe(at: frame, property: p)
            }
        }
    }
}

public struct MoveKeyframe: Command {
    public static let id = "keyframe.move"
    public var label: String { "Move Keyframe" }
    public var sceneID: String
    public var layerID: String
    public var property: String
    public var from: Int
    public var to: Int

    public init(sceneID: String, layerID: String, property: String, from: Int, to: Int) {
        self.sceneID = sceneID
        self.layerID = layerID
        self.property = property
        self.from = from
        self.to = to
    }

    public mutating func execute(_ document: inout Document) throws {
        try Self.move(&document, sceneID, layerID, property, from, to, checkLock: true)
    }

    public func undo(_ document: inout Document) throws {
        try Self.move(&document, sceneID, layerID, property, to, from, checkLock: false)
    }

    /// A drag step that picks the keyframe up where this one put it down: the
    /// merged command moves it straight from `from` to `next.to`. Exact, because
    /// the steps between only moved this keyframe.
    public mutating func merge(_ next: MoveKeyframe) -> Bool {
        guard (next.sceneID, next.layerID, next.property, next.from) == (sceneID, layerID, property, to)
        else { return false }
        to = next.to
        return true
    }

    private static func move(
        _ document: inout Document, _ scene: String, _ layer: String, _ p: String, _ from: Int, _ to: Int,
        checkLock: Bool
    ) throws {
        guard to >= 0 else { throw CommandError.invalidFrame(to) }
        try document.withLayer(scene: scene, layer: layer) { layer in
            guard !checkLock || !layer.isLocked else { throw CommandError.layerLocked(layer.id) }
            guard var k = layer.keyframe(at: from, property: p) else {
                throw CommandError.keyframeNotFound(property: p, frame: from)
            }
            if from == to { return }
            guard layer.keyframe(at: to, property: p) == nil else {
                throw CommandError.frameOccupied(property: p, frame: to)
            }
            layer.removeKeyframe(at: from, property: p)
            k.frame = to
            layer.setKeyframe(k, property: p)
        }
    }
}

public struct RemoveKeyframe: Command {
    public static let id = "keyframe.remove"
    public var label: String { "Delete Keyframe" }
    public var sceneID: String
    public var layerID: String
    public var property: String
    public var frame: Int
    var removed: Keyframe?

    private enum CodingKeys: String, CodingKey { case sceneID, layerID, property, frame }

    public init(sceneID: String, layerID: String, property: String, frame: Int) {
        self.sceneID = sceneID
        self.layerID = layerID
        self.property = property
        self.frame = frame
    }

    public mutating func execute(_ document: inout Document) throws {
        let (f, p) = (frame, property)
        removed = try document.withEditableLayer(scene: sceneID, layer: layerID) { layer in
            guard let k = layer.removeKeyframe(at: f, property: p) else {
                throw CommandError.keyframeNotFound(property: p, frame: f)
            }
            return k
        }
    }

    public func undo(_ document: inout Document) throws {
        guard let removed else { throw CommandError.notExecuted }
        let p = property
        try document.withLayer(scene: sceneID, layer: layerID) { $0.setKeyframe(removed, property: p) }
    }
}

public struct AddShape: Command {
    public static let id = "shape.add"
    public var label: String { "Add Shape" }
    public var sceneID: String
    public var layerID: String
    public var shape: Shape
    var insertedAt: Int?

    private enum CodingKeys: String, CodingKey { case sceneID, layerID, shape }

    public init(sceneID: String, layerID: String, shape: Shape) {
        self.sceneID = sceneID
        self.layerID = layerID
        self.shape = shape
    }

    public mutating func execute(_ document: inout Document) throws {
        let shape = shape
        insertedAt = try document.withEditableLayer(scene: sceneID, layer: layerID) { layer in
            layer.shapes.append(shape)
            return layer.shapes.count - 1
        }
    }

    public func undo(_ document: inout Document) throws {
        guard let insertedAt else { throw CommandError.notExecuted }
        try document.withLayer(scene: sceneID, layer: layerID) { layer in
            guard layer.shapes.indices.contains(insertedAt) else { throw CommandError.shapeNotFound(insertedAt) }
            layer.shapes.remove(at: insertedAt)
        }
    }
}
