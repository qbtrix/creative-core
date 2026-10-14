// InstanceCommands.swift: add and remove symbol instances on a layer of a
// scene or a symbol, addressed by owner, layer and instance index.
//
// Invariants:
// - params are checked before any change: an unknown symbol throws
//   symbolNotFound, a non-finite transform invalidTransform, a negative first
//   frame invalidFrame, a bad index invalidIndex, a locked layer layerLocked.
//   An instance that would make a symbol contain itself passes here and fails
//   `perform`'s validation
// - undo restores exactly: AddInstance removes the instance it appended,
//   RemoveInstance puts the removed one back at its index
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The instance commands, registered in `CommandRegistry.builtIn`.
public enum InstanceCommands {
    public static let all: [any Command.Type] = [AddInstance.self, RemoveInstance.self]
}

/// Appends an instance to the end of the layer's instances.
public struct AddInstance: LayerParamsCommand {
    public static let id = "instance.add"
    public var label: String { "Add Instance" }
    public var owner: LayerOwner
    public var layerID: String
    public var instance: Instance
    var executed = false

    public init(owner: LayerOwner, layerID: String, instance: Instance) {
        self.owner = owner
        self.layerID = layerID
        self.instance = instance
    }

    struct Params: Codable { var instance: Instance }
    var params: Params { Params(instance: instance) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, instance: params.instance)
    }

    public mutating func execute(_ document: inout Document) throws {
        _ = try document.symbolIndex(instance.symbolID)
        guard instance.transform.isFinite else { throw CommandError.invalidTransform }
        guard instance.firstFrame >= 0 else { throw CommandError.invalidFrame(instance.firstFrame) }
        try document.withEditableLayer(owner, layer: layerID) { [instance] layer in
            layer.instances.append(instance)
        }
        executed = true
    }

    public func undo(_ document: inout Document) throws {
        guard executed else { throw CommandError.notExecuted }
        try document.withLayer(owner, layer: layerID) { layer in
            guard layer.instances.last == instance else {
                throw CommandError.invalidIndex(layer.instances.count - 1)
            }
            layer.instances.removeLast()
        }
    }
}

extension Layer {
    /// Removes and returns instance `index`, or throws invalidIndex.
    mutating func removeInstance(at index: Int) throws -> Instance {
        guard instances.indices.contains(index) else { throw CommandError.invalidIndex(index) }
        return instances.remove(at: index)
    }

    /// Puts `instance` back at `index` (at most the count), or throws invalidIndex.
    mutating func insertInstance(_ instance: Instance, at index: Int) throws {
        guard (0...instances.count).contains(index) else { throw CommandError.invalidIndex(index) }
        instances.insert(instance, at: index)
    }
}

/// Removes the instance at `index` of the layer's instances; undo puts it back there.
public struct RemoveInstance: LayerItemCommand {
    public static let id = "instance.remove"
    /// The instance `execute` removed, for undo.
    var removed: Instance?
    public var owner: LayerOwner
    public var layerID: String
    public var index: Int
    public var label: String { "Delete Instance" }

    public init(owner: LayerOwner, layerID: String, index: Int) {
        (self.owner, self.layerID, self.index) = (owner, layerID, index)
    }

    public mutating func execute(_ document: inout Document) throws {
        removed = try document.withEditableLayer(owner, layer: layerID) { [index] in try $0.removeInstance(at: index) }
    }

    public func undo(_ document: inout Document) throws {
        guard let removed else { throw CommandError.notExecuted }
        try document.withLayer(owner, layer: layerID) { [index] in try $0.insertInstance(removed, at: index) }
    }
}
