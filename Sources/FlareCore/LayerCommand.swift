// LayerCommand.swift: the built-in commands that change only one layer, so
// CommandEngine validates their result scoped to that layer. A command listed
// here must never touch another layer, a scene field, a symbol or a machine.
//
// The layer list, shape and text families declare `LayerCommand` themselves.
// Until the keyframe family takes an owner param (Q5c), it names a scene layer:
// the extension below computes `owner` from `sceneID` for it.

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

/// The key a command writes its `layerID` under, beside its owner's key.
private enum LayerAddressKey: String, CodingKey { case layerID }

/// The key a shape or text command writes its item index under.
private enum ItemIndexKey: String, CodingKey { case index }

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

    /// Reads the owner, "layerID" and "index" of a command that names one
    /// shape or text of a layer.
    static func decodeItemAddress(from decoder: any Decoder) throws -> (LayerOwner, String, Int) {
        let (owner, layer) = try decodeAddress(from: decoder)
        return try (owner, layer, decoder.container(keyedBy: ItemIndexKey.self).decode(Int.self, forKey: .index))
    }

    /// Writes the owner, "layerID" and `index`, flat beside the command's own keys.
    func encodeItemAddress(index: Int, to encoder: any Encoder) throws {
        try encodeAddress(to: encoder)
        var c = encoder.container(keyedBy: ItemIndexKey.self)
        try c.encode(index, forKey: .index)
    }
}
