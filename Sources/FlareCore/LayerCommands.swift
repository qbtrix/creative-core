// LayerCommands.swift: layer state beyond add/remove/rename. Each command
// validates its params, throws a CommandError instead of crashing, and records
// just enough in execute() for undo() to restore the document exactly.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Sets a layer's visibility and lock flags. A nil flag is left unchanged.
/// Works on locked layers, so a layer can always be unlocked.
public struct SetLayerFlags: Command {
    public static let id = "layer.setFlags"
    public var label: String { "Set Layer Flags" }
    public var sceneID: String
    public var layerID: String
    public var isVisible: Bool?
    public var isLocked: Bool?
    var oldVisible: Bool?
    var oldLocked: Bool?

    public init(sceneID: String, layerID: String, isVisible: Bool? = nil, isLocked: Bool? = nil) {
        self.sceneID = sceneID
        self.layerID = layerID
        self.isVisible = isVisible
        self.isLocked = isLocked
    }

    public mutating func execute(_ document: inout Document) throws {
        let (visible, locked) = (isVisible, isLocked)
        (oldVisible, oldLocked) = try document.withLayer(scene: sceneID, layer: layerID) { layer in
            defer {
                layer.isVisible = visible ?? layer.isVisible
                layer.isLocked = locked ?? layer.isLocked
            }
            return (layer.isVisible, layer.isLocked)
        }
    }

    public func undo(_ document: inout Document) throws {
        guard let oldVisible, let oldLocked else { throw CommandError.notExecuted }
        try document.withLayer(scene: sceneID, layer: layerID) { layer in
            layer.isVisible = oldVisible
            layer.isLocked = oldLocked
        }
    }
}
