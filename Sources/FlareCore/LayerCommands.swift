// LayerCommands.swift: layer state, order and duplication beyond add/remove/rename. Each
// command validates its params, throws a CommandError instead of crashing, and
// records just enough in execute() for undo() to restore the document exactly.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The layer flag, order and duplicate commands.
public enum LayerCommands {
    public static let all: [any Command.Type] = [SetLayerFlags.self, ReorderLayer.self, DuplicateLayer.self]
}

/// Sets a layer's visibility and lock flags. A nil flag is left unchanged.
/// Works on locked layers, so a layer can always be unlocked.
public struct SetLayerFlags: LayerCommand {
    public static let id = "layer.setFlags"
    public var label: String { "Set Layer Flags" }
    public var owner: LayerOwner
    public var layerID: String
    public var isVisible: Bool?
    public var isLocked: Bool?
    var oldVisible: Bool?
    var oldLocked: Bool?

    private enum CodingKeys: String, CodingKey { case isVisible, isLocked }

    public init(owner: LayerOwner, layerID: String, isVisible: Bool? = nil, isLocked: Bool? = nil) {
        self.owner = owner
        self.layerID = layerID
        self.isVisible = isVisible
        self.isLocked = isLocked
    }

    public init(from decoder: any Decoder) throws {
        (owner, layerID) = try Self.decodeAddress(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible)
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked)
    }

    public func encode(to encoder: any Encoder) throws {
        try encodeAddress(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(isVisible, forKey: .isVisible)
        try c.encodeIfPresent(isLocked, forKey: .isLocked)
    }

    public mutating func execute(_ document: inout Document) throws {
        let (visible, locked) = (isVisible, isLocked)
        (oldVisible, oldLocked) = try document.withLayer(owner, layer: layerID) { layer in
            defer {
                layer.isVisible = visible ?? layer.isVisible
                layer.isLocked = locked ?? layer.isLocked
            }
            return (layer.isVisible, layer.isLocked)
        }
    }

    public func undo(_ document: inout Document) throws {
        guard let oldVisible, let oldLocked else { throw CommandError.notExecuted }
        try document.withLayer(owner, layer: layerID) { layer in
            layer.isVisible = oldVisible
            layer.isLocked = oldLocked
        }
    }
}

/// Moves a layer to `toIndex` within its owner's list. `toIndex` is the
/// layer's position after the move, so it must be in `0..<layers.count`.
public struct ReorderLayer: LayerCommand {
    public static let id = "layer.reorder"
    public var label: String { "Reorder Layer" }
    public var owner: LayerOwner
    public var layerID: String
    public var toIndex: Int
    var fromIndex: Int?

    private enum CodingKeys: String, CodingKey { case toIndex }

    public init(owner: LayerOwner, layerID: String, toIndex: Int) {
        self.owner = owner
        self.layerID = layerID
        self.toIndex = toIndex
    }

    public init(from decoder: any Decoder) throws {
        (owner, layerID) = try Self.decodeAddress(from: decoder)
        toIndex = try decoder.container(keyedBy: CodingKeys.self).decode(Int.self, forKey: .toIndex)
    }

    public func encode(to encoder: any Encoder) throws {
        try encodeAddress(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(toIndex, forKey: .toIndex)
    }

    public mutating func execute(_ document: inout Document) throws {
        fromIndex = try Self.move(&document, owner, layerID, toIndex)
    }

    public func undo(_ document: inout Document) throws {
        guard let fromIndex else { throw CommandError.notExecuted }
        _ = try Self.move(&document, owner, layerID, fromIndex)
    }

    /// Moves the layer and returns its index before the move.
    private static func move(_ document: inout Document, _ owner: LayerOwner, _ layer: String, _ to: Int) throws -> Int {
        try document.withLayers(owner) { layers in
            guard let i = layers.firstIndex(where: { $0.id == layer }) else { throw CommandError.layerNotFound(layer) }
            guard layers.indices.contains(to) else { throw CommandError.invalidIndex(to) }
            layers.insert(layers.remove(at: i), at: to)
            return i
        }
    }
}

/// Inserts a copy of a layer just above it (at its index + 1). The copy equals
/// the layer except its id, the first of "<id>-copy", "<id>-copy-2", ... that no
/// layer of the owner uses, and its name, "<name> copy". Undo removes the copy
/// only if it still sits at index + 1: it throws `invalidDocument` when the copy
/// moved to another index, and `layerNotFound` when no layer has its id.
// A LayerCommand for `layerID`, though it inserts the copy: the engine's scoped
// check validates that layer, which the copy equals but for its fresh id, and
// checks the document limits because the layer list grew.
public struct DuplicateLayer: LayerCommand {
    public static let id = "layer.duplicate"
    public var label: String { "Duplicate Layer" }
    public var owner: LayerOwner
    public var layerID: String
    var inserted: (index: Int, id: String)?

    public init(owner: LayerOwner, layerID: String) {
        self.owner = owner
        self.layerID = layerID
    }

    public init(from decoder: any Decoder) throws { (owner, layerID) = try Self.decodeAddress(from: decoder) }
    public func encode(to encoder: any Encoder) throws { try encodeAddress(to: encoder) }

    public mutating func execute(_ document: inout Document) throws {
        let id = layerID
        inserted = try document.withLayers(owner) { layers in
            guard let i = layers.firstIndex(where: { $0.id == id }) else { throw CommandError.layerNotFound(id) }
            var copy = layers[i]
            copy.id = Self.freshID(for: id, in: layers)
            copy.name += " copy"
            layers.insert(copy, at: i + 1)
            return (i + 1, copy.id)
        }
    }

    public func undo(_ document: inout Document) throws {
        guard let inserted else { throw CommandError.notExecuted }
        try document.withLayers(owner) { layers in
            guard layers.indices.contains(inserted.index), layers[inserted.index].id == inserted.id else {
                guard layers.contains(where: { $0.id == inserted.id }) else {
                    throw CommandError.layerNotFound(inserted.id)
                }
                throw CommandError.invalidDocument(
                    "layer \(inserted.id): the duplicate is no longer at index \(inserted.index)")
            }
            layers.remove(at: inserted.index)
        }
    }

    /// "<id>-copy", then "<id>-copy-2", "-copy-3", ...: the first no layer uses.
    /// At most `layers.count + 1` candidates, so the suffix cannot overflow.
    static func freshID(for id: String, in layers: [Layer]) -> String {
        let used = Set(layers.map(\.id))
        var candidate = "\(id)-copy", n = 1
        while used.contains(candidate) {
            n += 1
            candidate = "\(id)-copy-\(n)"
        }
        return candidate
    }
}
