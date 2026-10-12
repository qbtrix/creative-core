// InstanceCommands.swift: add, remove and move symbol instances on a layer of a
// scene or a symbol, addressed by owner, layer and instance index.
//
// Invariants:
// - params are checked before any change: an unknown symbol throws
//   symbolNotFound, a non-finite transform invalidTransform, a bad index
//   invalidIndex, a locked layer layerLocked. An instance that would make a
//   symbol contain itself passes here and fails `perform`'s validation
// - the owner encodes flat beside the other params (see LayerOwner.swift)
// - undo restores the stored old value, so it is exact
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The instance commands, registered in `CommandRegistry.builtIn`.
public enum InstanceCommands {
    public static let all: [any Command.Type] = [AddInstance.self, RemoveInstance.self, SetInstanceTransform.self]
}

extension Document {
    /// Runs `body` on the instances of the addressed layer, after checking that
    /// `index` names one of them. `editable` also refuses a locked layer.
    @discardableResult
    mutating func withInstance<T>(_ owner: LayerOwner, layer: String, index: Int, editable: Bool,
                                  _ body: (inout [Instance]) throws -> T) throws -> T {
        let run: (inout Layer) throws -> T = { layer in
            guard layer.instances.indices.contains(index) else { throw CommandError.invalidIndex(index) }
            return try body(&layer.instances)
        }
        return editable ? try withEditableLayer(owner, layer: layer, run) : try withLayer(owner, layer: layer, run)
    }
}

/// The param keys of the instance commands. The owner is encoded flat beside them.
private enum ParamKey: String, CodingKey { case layerID, index, instance, transform }

/// Decodes the owner and "layerID", and returns the container for the other params.
private func decodeParams(_ decoder: any Decoder) throws -> (LayerOwner, String, KeyedDecodingContainer<ParamKey>) {
    let c = try decoder.container(keyedBy: ParamKey.self)
    return (try LayerOwner(from: decoder), try c.decode(String.self, forKey: .layerID), c)
}

/// Encodes the owner flat, then `params` in order, beside it.
private func encodeParams(_ owner: LayerOwner, _ params: KeyValuePairs<ParamKey, any Encodable>,
                          to encoder: any Encoder) throws {
    try owner.encode(to: encoder)
    var c = encoder.container(keyedBy: ParamKey.self)
    for (key, value) in params { try c.encode(value, forKey: key) }
}

/// Appends an instance to the end of the layer's instances.
public struct AddInstance: Command {
    public static let id = "instance.add"
    public var label: String { "Add Instance" }
    public var owner: LayerOwner
    public var layerID: String
    public var instance: Instance
    var insertedAt: Int?

    public init(owner: LayerOwner, layerID: String, instance: Instance) {
        self.owner = owner
        self.layerID = layerID
        self.instance = instance
    }

    public init(from decoder: any Decoder) throws {
        let c: KeyedDecodingContainer<ParamKey>
        (owner, layerID, c) = try decodeParams(decoder)
        instance = try c.decode(Instance.self, forKey: .instance)
    }

    public func encode(to encoder: any Encoder) throws {
        try encodeParams(owner, [.layerID: layerID, .instance: instance], to: encoder)
    }

    public mutating func execute(_ document: inout Document) throws {
        let instance = instance
        _ = try document.symbolIndex(instance.symbolID)
        guard instance.firstFrame >= 0 else { throw CommandError.invalidFrame(instance.firstFrame) }
        guard instance.transform.isFinite else { throw CommandError.invalidTransform }
        insertedAt = try document.withEditableLayer(owner, layer: layerID) { layer in
            layer.instances.append(instance)
            return layer.instances.count - 1
        }
    }

    public func undo(_ document: inout Document) throws {
        guard let insertedAt else { throw CommandError.notExecuted }
        try document.withInstance(owner, layer: layerID, index: insertedAt, editable: false) {
            $0.remove(at: insertedAt)
        }
    }
}

public struct RemoveInstance: Command {
    public static let id = "instance.remove"
    public var label: String { "Delete Instance" }
    public var owner: LayerOwner
    public var layerID: String
    public var index: Int
    var removed: Instance?

    public init(owner: LayerOwner, layerID: String, index: Int) {
        self.owner = owner
        self.layerID = layerID
        self.index = index
    }

    public init(from decoder: any Decoder) throws {
        let c: KeyedDecodingContainer<ParamKey>
        (owner, layerID, c) = try decodeParams(decoder)
        index = try c.decode(Int.self, forKey: .index)
    }

    public func encode(to encoder: any Encoder) throws {
        try encodeParams(owner, [.layerID: layerID, .index: index], to: encoder)
    }

    public mutating func execute(_ document: inout Document) throws {
        let index = index
        removed = try document.withInstance(owner, layer: layerID, index: index, editable: true) {
            $0.remove(at: index)
        }
    }

    public func undo(_ document: inout Document) throws {
        guard let removed else { throw CommandError.notExecuted }
        let index = index
        try document.withLayer(owner, layer: layerID) { layer in
            guard index >= 0, index <= layer.instances.count else { throw CommandError.invalidIndex(index) }
            layer.instances.insert(removed, at: index)
        }
    }
}

/// Sets an instance's transform. Consecutive sets of the same instance merge
/// into one, as a drag does: the merged command keeps the first old transform
/// and the last new one.
public struct SetInstanceTransform: Command {
    public static let id = "instance.setTransform"
    public var label: String { "Move Instance" }
    public var owner: LayerOwner
    public var layerID: String
    public var index: Int
    public var transform: Transform
    var oldTransform: Transform?

    public init(owner: LayerOwner, layerID: String, index: Int, transform: Transform) {
        self.owner = owner
        self.layerID = layerID
        self.index = index
        self.transform = transform
    }

    public init(from decoder: any Decoder) throws {
        let c: KeyedDecodingContainer<ParamKey>
        (owner, layerID, c) = try decodeParams(decoder)
        index = try c.decode(Int.self, forKey: .index)
        transform = try c.decode(Transform.self, forKey: .transform)
    }

    public func encode(to encoder: any Encoder) throws {
        try encodeParams(owner, [.layerID: layerID, .index: index, .transform: transform], to: encoder)
    }

    public mutating func execute(_ document: inout Document) throws {
        let (index, transform) = (index, transform)
        guard transform.isFinite else { throw CommandError.invalidTransform }
        oldTransform = try document.withInstance(owner, layer: layerID, index: index, editable: true) { instances in
            defer { instances[index].transform = transform }
            return instances[index].transform
        }
    }

    public mutating func merge(_ next: SetInstanceTransform) -> Bool {
        guard oldTransform != nil, next.oldTransform == transform,
              (next.owner, next.layerID, next.index) == (owner, layerID, index) else { return false }
        transform = next.transform
        return true
    }

    public func undo(_ document: inout Document) throws {
        guard let oldTransform else { throw CommandError.notExecuted }
        let index = index
        try document.withInstance(owner, layer: layerID, index: index, editable: false) {
            $0[index].transform = oldTransform
        }
    }
}
