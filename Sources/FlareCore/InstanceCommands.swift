// InstanceCommands.swift: add, remove, move and retime symbol instances on a
// layer of a scene or a symbol, addressed by owner, layer and instance index.
//
// Invariants:
// - params are checked before any change: an unknown symbol throws
//   symbolNotFound, a non-finite transform invalidTransform, a negative first
//   frame invalidFrame, a bad index invalidIndex, a locked layer layerLocked.
//   An instance that would make a symbol contain itself passes here and fails
//   `perform`'s validation
// - undo restores exactly: AddInstance removes the instance it appended,
//   RemoveInstance puts the removed one back at its index, SetInstanceTransform
//   and SetInstancePlayback put back the old transform or (firstFrame, loop)
// - a SetInstanceTransform drag merges only steps on the same owner, layer and
//   index, keeping the first old transform, so a drag undoes in one step
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The instance commands, registered in `CommandRegistry.builtIn`.
public enum InstanceCommands {
    public static let all: [any Command.Type] = [
        AddInstance.self, RemoveInstance.self, SetInstanceTransform.self, SetInstancePlayback.self,
    ]
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

    /// Runs `body` on instance `index`, or throws invalidIndex.
    mutating func updateInstance<T>(at index: Int, _ body: (inout Instance) throws -> T) throws -> T {
        guard instances.indices.contains(index) else { throw CommandError.invalidIndex(index) }
        return try body(&instances[index])
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

/// Sets the transform of the instance at `index`. Steps of one drag merge.
public struct SetInstanceTransform: LayerParamsCommand {
    public static let id = "instance.setTransform"
    public var label: String { "Move Instance" }
    public var owner: LayerOwner
    public var layerID: String
    public var index: Int
    public var transform: Transform
    /// The transform before the first step of the drag, for undo.
    var oldTransform: Transform?

    public init(owner: LayerOwner, layerID: String, index: Int, transform: Transform) {
        (self.owner, self.layerID, self.index, self.transform) = (owner, layerID, index, transform)
    }

    struct Params: Codable { var index: Int; var transform: Transform }
    var params: Params { Params(index: index, transform: transform) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, index: params.index, transform: params.transform)
    }

    public mutating func execute(_ document: inout Document) throws {
        guard transform.isFinite else { throw CommandError.invalidTransform }
        oldTransform = try document.withEditableLayer(owner, layer: layerID) { [index, transform] layer in
            try layer.updateInstance(at: index) { instance in
                defer { instance.transform = transform }
                return instance.transform
            }
        }
    }

    /// A later step of a drag of the same instance: keeps this step's old
    /// transform and takes `next.transform`. Decides on params only.
    public mutating func merge(_ next: SetInstanceTransform) -> Bool {
        guard (next.owner, next.layerID, next.index) == (owner, layerID, index) else { return false }
        transform = next.transform
        return true
    }

    public func undo(_ document: inout Document) throws {
        guard let oldTransform else { throw CommandError.notExecuted }
        try document.withLayer(owner, layer: layerID) { [index] layer in
            try layer.updateInstance(at: index) { $0.transform = oldTransform }
        }
    }
}

/// Sets where the instance at `index` starts in its symbol and how it plays.
public struct SetInstancePlayback: LayerParamsCommand {
    public static let id = "instance.setPlayback"
    public var label: String { "Set Instance Playback" }
    public var owner: LayerOwner
    public var layerID: String
    public var index: Int
    public var firstFrame: Int
    public var loop: Instance.LoopMode
    /// The (firstFrame, loop) `execute` replaced, for undo.
    var old: Params?

    public init(owner: LayerOwner, layerID: String, index: Int, firstFrame: Int, loop: Instance.LoopMode) {
        (self.owner, self.layerID, self.index) = (owner, layerID, index)
        (self.firstFrame, self.loop) = (firstFrame, loop)
    }

    struct Params: Codable { var index: Int; var firstFrame: Int; var loop: Instance.LoopMode }
    var params: Params { Params(index: index, firstFrame: firstFrame, loop: loop) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, index: params.index, firstFrame: params.firstFrame, loop: params.loop)
    }

    public mutating func execute(_ document: inout Document) throws {
        guard firstFrame >= 0 else { throw CommandError.invalidFrame(firstFrame) }
        old = try document.withEditableLayer(owner, layer: layerID) { [params] layer in
            try layer.updateInstance(at: params.index) { instance in
                defer { (instance.firstFrame, instance.loop) = (params.firstFrame, params.loop) }
                return Params(index: params.index, firstFrame: instance.firstFrame, loop: instance.loop)
            }
        }
    }

    public func undo(_ document: inout Document) throws {
        guard let old else { throw CommandError.notExecuted }
        try document.withLayer(owner, layer: layerID) { layer in
            try layer.updateInstance(at: old.index) { ($0.firstFrame, $0.loop) = (old.firstFrame, old.loop) }
        }
    }
}
