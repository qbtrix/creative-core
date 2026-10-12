// LayerCommands.swift: layer state and order beyond add/remove/rename. Each
// command validates its params, throws a CommandError instead of crashing, and
// records just enough in execute() for undo() to restore the document exactly.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The layer flag and order commands.
public enum LayerCommands {
    public static let all: [any Command.Type] = [SetLayerFlags.self, ReorderLayer.self]
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
