// LayerCommand.swift: the built-in commands that change only one layer, so
// CommandEngine validates their result scoped to that layer. A command listed
// here must never touch another layer, a scene field, a symbol or a machine.
//
// Every family but the keyframe one takes an owner param and conforms where it
// is declared. Until the keyframe family does (Q5c), it names a scene layer:
// `SceneLayerCommand` computes `owner` from `sceneID` for it.

extension SetKeyframe: SceneLayerCommand {}
extension MoveKeyframe: SceneLayerCommand {}
extension RemoveKeyframe: SceneLayerCommand {}
extension SetKeyframeEasing: SceneLayerCommand {}
extension ShiftKeyframes: SceneLayerCommand {}

/// The listed commands that still address a layer by scene id.
protocol SceneLayerCommand: LayerCommand {
    var sceneID: String { get }
}

extension SceneLayerCommand {
    public var owner: LayerOwner { .scene(sceneID) }
}

/// The keys a command writes its `layerID` (and item `index`) under, beside its owner's key.
private enum LayerAddressKey: String, CodingKey { case layerID, index }

extension LayerCommand {
    /// Reads the owner and "layerID", flat beside the command's own keys.
    static func decodeAddress(from decoder: any Decoder) throws -> (LayerOwner, String) {
        let c = try decoder.container(keyedBy: LayerAddressKey.self)
        return try (LayerOwner(from: decoder), c.decode(String.self, forKey: .layerID))
    }

    /// Writes the owner and "layerID", flat beside the command's own keys.
    func encodeAddress(to encoder: any Encoder) throws {
        try owner.encode(to: encoder)
        var c = encoder.container(keyedBy: LayerAddressKey.self)
        try c.encode(layerID, forKey: .layerID)
    }

    /// Reads the owner, "layerID" and "index" of a command that edits one item
    /// (a shape or a text) of a layer.
    static func decodeItemAddress(from decoder: any Decoder) throws -> (LayerOwner, String, Int) {
        let (owner, layerID) = try decodeAddress(from: decoder)
        let c = try decoder.container(keyedBy: LayerAddressKey.self)
        return try (owner, layerID, c.decode(Int.self, forKey: .index))
    }

    /// Writes the owner, "layerID" and "index", flat beside the command's own keys.
    func encodeItemAddress(to encoder: any Encoder, index: Int) throws {
        try encodeAddress(to: encoder)
        var c = encoder.container(keyedBy: LayerAddressKey.self)
        try c.encode(index, forKey: .index)
    }
}

/// A layer command whose params are exactly its owner, layer and item index,
/// so its Codable is the item address alone.
protocol LayerItemCommand: LayerCommand {
    var index: Int { get }
    init(owner: LayerOwner, layerID: String, index: Int)
}

extension LayerItemCommand {
    public init(from decoder: any Decoder) throws {
        let (owner, layerID, index) = try Self.decodeItemAddress(from: decoder)
        self.init(owner: owner, layerID: layerID, index: index)
    }

    public func encode(to encoder: any Encoder) throws { try encodeItemAddress(to: encoder, index: index) }
}
