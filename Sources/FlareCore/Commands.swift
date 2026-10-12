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

public struct AddLayer: Command {
    public static let id = "layer.add"
    public var label: String { "Add Layer" }
    public var sceneID: String
    public var layer: Layer
    /// Insert position; nil appends.
    public var index: Int?

    public init(sceneID: String, layer: Layer, index: Int? = nil) {
        self.sceneID = sceneID
        self.layer = layer
        self.index = index
    }

    public mutating func execute(_ document: inout Document) throws {
        let s = try document.sceneIndex(sceneID)
        var layers = document.scenes[s].layers
        guard !layers.contains(where: { $0.id == layer.id }) else { throw CommandError.duplicateID(layer.id) }
        let at = min(max(index ?? layers.count, 0), layers.count)
        layers.insert(layer, at: at)
        document.scenes[s].layers = layers
    }

    public func undo(_ document: inout Document) throws {
        let s = try document.sceneIndex(sceneID)
        guard let i = document.scenes[s].layers.firstIndex(where: { $0.id == layer.id }) else {
            throw CommandError.layerNotFound(layer.id)
        }
        document.scenes[s].layers.remove(at: i)
    }
}

public struct RemoveLayer: Command {
    public static let id = "layer.remove"
    public var label: String { "Delete Layer" }
    public var sceneID: String
    public var layerID: String
    var removed: Layer?
    var removedIndex: Int?

    private enum CodingKeys: String, CodingKey { case sceneID, layerID }

    public init(sceneID: String, layerID: String) {
        self.sceneID = sceneID
        self.layerID = layerID
    }

    public mutating func execute(_ document: inout Document) throws {
        let s = try document.sceneIndex(sceneID)
        guard let i = document.scenes[s].layers.firstIndex(where: { $0.id == layerID }) else {
            throw CommandError.layerNotFound(layerID)
        }
        removed = document.scenes[s].layers.remove(at: i)
        removedIndex = i
    }

    public func undo(_ document: inout Document) throws {
        guard let removed, let removedIndex else { throw CommandError.notExecuted }
        let s = try document.sceneIndex(sceneID)
        let at = min(removedIndex, document.scenes[s].layers.count)
        document.scenes[s].layers.insert(removed, at: at)
    }
}

public struct RenameLayer: Command {
    public static let id = "layer.rename"
    public var label: String { "Rename Layer" }
    public var sceneID: String
    public var layerID: String
    public var name: String
    var oldName: String?

    private enum CodingKeys: String, CodingKey { case sceneID, layerID, name }

    public init(sceneID: String, layerID: String, name: String) {
        self.sceneID = sceneID
        self.layerID = layerID
        self.name = name
    }

    public mutating func execute(_ document: inout Document) throws {
        let newName = name
        oldName = try document.withLayer(scene: sceneID, layer: layerID) { layer in
            defer { layer.name = newName }
            return layer.name
        }
    }

    public func undo(_ document: inout Document) throws {
        guard let oldName else { throw CommandError.notExecuted }
        try document.withLayer(scene: sceneID, layer: layerID) { $0.name = oldName }
    }
}

public struct SetKeyframe: Command {
    public static let id = "keyframe.set"
    public var label: String { "Set Keyframe" }
    public var owner: LayerOwner
    public var layerID: String
    public var property: String
    public var keyframe: Keyframe
    var previous: Keyframe?
    var executed: Bool?

    public init(owner: LayerOwner, layerID: String, property: String, keyframe: Keyframe) {
        self.owner = owner
        self.layerID = layerID
        self.property = property
        self.keyframe = keyframe
    }

    /// Every param but the owner, which encodes flat beside them.
    private struct Params: Codable { var layerID: String; var property: String; var keyframe: Keyframe }

    public init(from decoder: any Decoder) throws {
        let p = try Params(from: decoder)
        self.init(owner: try LayerOwner(from: decoder), layerID: p.layerID, property: p.property, keyframe: p.keyframe)
    }

    public func encode(to encoder: any Encoder) throws {
        try owner.encode(to: encoder)
        try Params(layerID: layerID, property: property, keyframe: keyframe).encode(to: encoder)
    }

    public mutating func execute(_ document: inout Document) throws {
        guard keyframe.frame >= 0 else { throw CommandError.invalidFrame(keyframe.frame) }
        let (k, p) = (keyframe, property)
        previous = try document.withEditableLayer(owner, layer: layerID) { $0.setKeyframe(k, property: p) }
        executed = true
    }

    public func undo(_ document: inout Document) throws {
        guard executed == true else { throw CommandError.notExecuted }
        let (frame, p, previous) = (keyframe.frame, property, previous)
        try document.withLayer(owner, layer: layerID) { layer in
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
    public var owner: LayerOwner
    public var layerID: String
    public var property: String
    public var from: Int
    public var to: Int

    public init(owner: LayerOwner, layerID: String, property: String, from: Int, to: Int) {
        self.owner = owner
        self.layerID = layerID
        self.property = property
        self.from = from
        self.to = to
    }

    /// Every param but the owner, which encodes flat beside them.
    private struct Params: Codable { var layerID: String; var property: String; var from: Int; var to: Int }

    public init(from decoder: any Decoder) throws {
        let p = try Params(from: decoder)
        self.init(owner: try LayerOwner(from: decoder), layerID: p.layerID,
                  property: p.property, from: p.from, to: p.to)
    }

    public func encode(to encoder: any Encoder) throws {
        try owner.encode(to: encoder)
        try Params(layerID: layerID, property: property, from: from, to: to).encode(to: encoder)
    }

    public mutating func execute(_ document: inout Document) throws {
        try Self.move(&document, owner, layerID, property, from, to, checkLock: true)
    }

    public func undo(_ document: inout Document) throws {
        try Self.move(&document, owner, layerID, property, to, from, checkLock: false)
    }

    /// A drag step that picks the keyframe up where this one put it down: the
    /// merged command moves it straight from `from` to `next.to`. Exact, because
    /// the steps between only moved this keyframe. Drags on different owners
    /// never merge, even when the layer ids match.
    public mutating func merge(_ next: MoveKeyframe) -> Bool {
        guard next.owner == owner, (next.layerID, next.property, next.from) == (layerID, property, to)
        else { return false }
        to = next.to
        return true
    }

    private static func move(
        _ document: inout Document, _ owner: LayerOwner, _ layer: String, _ p: String, _ from: Int, _ to: Int,
        checkLock: Bool
    ) throws {
        guard to >= 0 else { throw CommandError.invalidFrame(to) }
        try document.withLayer(owner, layer: layer) { layer in
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
    public var owner: LayerOwner
    public var layerID: String
    public var property: String
    public var frame: Int
    var removed: Keyframe?

    public init(owner: LayerOwner, layerID: String, property: String, frame: Int) {
        self.owner = owner
        self.layerID = layerID
        self.property = property
        self.frame = frame
    }

    /// Every param but the owner, which encodes flat beside them.
    private struct Params: Codable { var layerID: String; var property: String; var frame: Int }

    public init(from decoder: any Decoder) throws {
        let p = try Params(from: decoder)
        self.init(owner: try LayerOwner(from: decoder), layerID: p.layerID, property: p.property, frame: p.frame)
    }

    public func encode(to encoder: any Encoder) throws {
        try owner.encode(to: encoder)
        try Params(layerID: layerID, property: property, frame: frame).encode(to: encoder)
    }

    public mutating func execute(_ document: inout Document) throws {
        let (f, p) = (frame, property)
        removed = try document.withEditableLayer(owner, layer: layerID) { layer in
            guard let k = layer.removeKeyframe(at: f, property: p) else {
                throw CommandError.keyframeNotFound(property: p, frame: f)
            }
            return k
        }
    }

    public func undo(_ document: inout Document) throws {
        guard let removed else { throw CommandError.notExecuted }
        let p = property
        try document.withLayer(owner, layer: layerID) { $0.setKeyframe(removed, property: p) }
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
