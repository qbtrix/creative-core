// MaskCommands.swift: the commands that edit a layer's masks and track matte.
// Each names its layer by owner and layerID, refuses a locked layer
// (`layerLocked`) and a mask index outside the list (`invalidIndex`), and
// saves what it replaced, so undo is exact. A drag of one mask (SetLayerMask
// under one coalesce key) merges into one step; a step on another mask starts
// a new command. SetTrackMatte refuses a source missing from the owner's list
// (`layerNotFound`) and a source whose chain of mattes leads back to the layer
// at any depth, the layer itself included (`invalidDocument`), before it
// changes anything; `FlareFormat.checkMattes` stays the backstop on perform.
// Through `CommandEngine.perform` the format check also refuses bad mask
// values (a non-finite point or feather, opacity outside 0...1, more than
// `FlareFormat.maxMasksPerLayer` masks); calling `execute` directly checks none.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The mask and track-matte commands, registered in `CommandRegistry.builtIn`.
public enum MaskCommands {
    /// Every mask and track-matte command type, in registration order.
    public static let all: [any Command.Type] = [
        AddLayerMask.self, SetLayerMask.self, RemoveLayerMask.self, MoveLayerMask.self, SetTrackMatte.self,
    ]
}

extension [LayerMask] {
    /// Throws `invalidIndex(index)` unless `index` is a position in the list, or one past it when `end` is true.
    func checkMaskIndex(_ index: Int, end: Bool = false) throws {
        guard index >= 0, index < count + (end ? 1 : 0) else { throw CommandError.invalidIndex(index) }
    }
}

/// Inserts `mask` into a layer's masks at `index`, or appends it when `index`
/// is nil. An index outside 0...masks.count throws `invalidIndex`.
public struct AddLayerMask: LayerParamsCommand {
    public static let id = "mask.add"
    public var label: String { "Add Mask" }
    public var owner: LayerOwner, layerID: String, mask: LayerMask, index: Int?
    var insertedAt: Int?
    public init(owner: LayerOwner, layerID: String, mask: LayerMask, index: Int? = nil) {
        (self.owner, self.layerID, self.mask, self.index) = (owner, layerID, mask, index)
    }
    struct Params: Codable { var mask: LayerMask; var index: Int? }
    var params: Params { Params(mask: mask, index: index) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, mask: params.mask, index: params.index)
    }
    public mutating func execute(_ document: inout Document) throws {
        let (mask, index) = (mask, index)
        insertedAt = try document.withEditableLayer(owner, layer: layerID) { l in
            let at = index ?? l.masks.count
            try l.masks.checkMaskIndex(at, end: true)
            l.masks.insert(mask, at: at)
            return at
        }
    }
    public func undo(_ document: inout Document) throws {
        guard let insertedAt else { throw CommandError.notExecuted }
        try document.withLayer(owner, layer: layerID) { l in
            try l.masks.checkMaskIndex(insertedAt)
            l.masks.remove(at: insertedAt)
        }
    }
}

/// Replaces the mask at `index`. Steps of a drag on the same mask, performed
/// with one coalesce key, merge into one undo step.
public struct SetLayerMask: LayerParamsCommand {
    public static let id = "mask.set"
    public var label: String { "Set Mask" }
    public var owner: LayerOwner, layerID: String, index: Int, mask: LayerMask
    var oldMask: LayerMask?
    public init(owner: LayerOwner, layerID: String, index: Int, mask: LayerMask) {
        (self.owner, self.layerID, self.index, self.mask) = (owner, layerID, index, mask)
    }
    struct Params: Codable { var index: Int; var mask: LayerMask }
    var params: Params { Params(index: index, mask: mask) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, index: params.index, mask: params.mask)
    }
    public mutating func execute(_ document: inout Document) throws {
        let (index, mask) = (index, mask)
        oldMask = try document.withEditableLayer(owner, layer: layerID) { l in
            try l.masks.checkMaskIndex(index)
            defer { l.masks[index] = mask }
            return l.masks[index]
        }
    }
    public func undo(_ document: inout Document) throws {
        guard let oldMask else { throw CommandError.notExecuted }
        try document.withLayer(owner, layer: layerID) { l in
            try l.masks.checkMaskIndex(index)
            l.masks[index] = oldMask
        }
    }
    /// Folds in `next` when it set the same mask of the same layer; the old
    /// mask is kept, so undo goes back to before the drag.
    public mutating func merge(_ next: SetLayerMask) -> Bool {
        guard oldMask != nil, next.oldMask != nil,
              (next.owner, next.layerID, next.index) == (owner, layerID, index) else { return false }
        mask = next.mask
        return true
    }
}

/// Removes the mask at `index`.
public struct RemoveLayerMask: LayerParamsCommand {
    public static let id = "mask.remove"
    public var label: String { "Remove Mask" }
    public var owner: LayerOwner, layerID: String, index: Int
    var removed: LayerMask?
    public init(owner: LayerOwner, layerID: String, index: Int) {
        (self.owner, self.layerID, self.index) = (owner, layerID, index)
    }
    struct Params: Codable { var index: Int }
    var params: Params { Params(index: index) }
    init(owner: LayerOwner, layerID: String, params: Params) { self.init(owner: owner, layerID: layerID, index: params.index) }
    public mutating func execute(_ document: inout Document) throws {
        let index = index
        removed = try document.withEditableLayer(owner, layer: layerID) { l in
            try l.masks.checkMaskIndex(index)
            return l.masks.remove(at: index)
        }
    }
    public func undo(_ document: inout Document) throws {
        guard let removed else { throw CommandError.notExecuted }
        try document.withLayer(owner, layer: layerID) { l in
            try l.masks.checkMaskIndex(index, end: true)
            l.masks.insert(removed, at: index)
        }
    }
}

/// Moves the mask at `from` to position `to`, which changes how it combines
/// with the masks before it. Both must be positions in the list.
public struct MoveLayerMask: LayerParamsCommand {
    public static let id = "mask.move"
    public var label: String { "Move Mask" }
    public var owner: LayerOwner, layerID: String, from: Int, to: Int
    var moved = false
    public init(owner: LayerOwner, layerID: String, from: Int, to: Int) {
        (self.owner, self.layerID, self.from, self.to) = (owner, layerID, from, to)
    }
    struct Params: Codable { var from: Int; var to: Int }
    var params: Params { Params(from: from, to: to) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, from: params.from, to: params.to)
    }
    public mutating func execute(_ document: inout Document) throws {
        let (from, to) = (from, to)
        try document.withEditableLayer(owner, layer: layerID) { l in
            try l.masks.checkMaskIndex(from)
            try l.masks.checkMaskIndex(to)
            l.masks.insert(l.masks.remove(at: from), at: to)
        }
        moved = true
    }
    public func undo(_ document: inout Document) throws {
        guard moved else { throw CommandError.notExecuted }
        try document.withLayer(owner, layer: layerID) { l in
            try l.masks.checkMaskIndex(to)
            try l.masks.checkMaskIndex(from)
            l.masks.insert(l.masks.remove(at: to), at: from)
        }
    }
}

/// Sets the layer's track matte; nil clears it. The source must be another
/// layer of the same list whose own chain of mattes never reaches this layer.
public struct SetTrackMatte: LayerParamsCommand {
    public static let id = "mask.setMatte"
    public var label: String { "Set Track Matte" }
    public var owner: LayerOwner, layerID: String, matte: TrackMatte?
    var oldMatte: TrackMatte?
    var executed = false
    public init(owner: LayerOwner, layerID: String, matte: TrackMatte?) {
        (self.owner, self.layerID, self.matte) = (owner, layerID, matte)
    }
    struct Params: Codable { var matte: TrackMatte? }
    var params: Params { Params(matte: matte) }
    init(owner: LayerOwner, layerID: String, params: Params) { self.init(owner: owner, layerID: layerID, matte: params.matte) }
    public mutating func execute(_ document: inout Document) throws {
        let matte = matte
        if let matte, let layers = document.layers(of: owner) {
            try Self.checkSource(matte.sourceLayerID, of: layerID, in: layers)
        }
        oldMatte = try document.withEditableLayer(owner, layer: layerID) { l in
            defer { l.matte = matte }
            return l.matte
        }
        executed = true
    }
    public func undo(_ document: inout Document) throws {
        guard executed else { throw CommandError.notExecuted }
        let oldMatte = oldMatte
        try document.withLayer(owner, layer: layerID) { $0.matte = oldMatte }
    }
    /// Throws `layerNotFound(source)` unless `source` is in `layers`, and
    /// `invalidDocument` when the chain of mattes from `source` reaches
    /// `layerID` (a self matte is the chain of length 0).
    static func checkSource(_ source: String, of layerID: String, in layers: [Layer]) throws {
        guard layers.contains(where: { $0.id == source }) else { throw CommandError.layerNotFound(source) }
        var next: String? = source, hops = 0
        // Bounded: a chain longer than the list repeats a layer, so it never reaches `layerID` after that.
        while let id = next, hops <= layers.count {
            guard id != layerID else {
                throw CommandError.invalidDocument("layer \(layerID) matte source \(source) leads back to \(layerID)")
            }
            next = layers.first { $0.id == id }?.matte?.sourceLayerID
            hops += 1
        }
    }
}
