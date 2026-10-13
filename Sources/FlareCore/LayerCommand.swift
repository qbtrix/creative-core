// LayerCommand.swift: the built-in commands that change only one layer, so
// CommandEngine validates their result scoped to that layer. A command listed
// here must never touch another layer, a scene field, a symbol or a machine.
//
// Until the keyframe family takes an owner param (Q5c), it names a scene layer:
// `SceneLayerCommand` computes `owner` from `sceneID` for it.

extension SetKeyframe: SceneLayerCommand {}
extension MoveKeyframe: SceneLayerCommand {}
extension RemoveKeyframe: SceneLayerCommand {}
extension SetKeyframeEasing: SceneLayerCommand {}
extension ShiftKeyframes: SceneLayerCommand {}
extension AddShape: LayerCommand {}
extension RemoveShape: LayerCommand {}
extension SetShapeFill: LayerCommand {}
extension TranslateShape: LayerCommand {}
extension AddTextShape: LayerCommand {}
extension RemoveTextShape: LayerCommand {}
extension SetTextString: LayerCommand {}
extension SetTextFont: LayerCommand {}

/// The listed commands that still address a layer by scene id.
protocol SceneLayerCommand: LayerCommand {
    var sceneID: String { get }
}

extension SceneLayerCommand {
    public var owner: LayerOwner { .scene(sceneID) }
}

/// The key a command writes its `layerID` under, beside its owner's key.
private enum LayerAddressKey: String, CodingKey { case layerID }

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

    /// Reads the owner, "layerID" and the command's other params `P`, all flat.
    static func decodeAddress<P: Decodable>(from decoder: any Decoder, params: P.Type) throws -> (LayerOwner, String, P) {
        let (owner, layer) = try decodeAddress(from: decoder)
        return try (owner, layer, P(from: decoder))
    }

    /// Writes the owner, "layerID" and `params`, all flat.
    func encodeAddress(to encoder: any Encoder, params: some Encodable) throws {
        try encodeAddress(to: encoder)
        try params.encode(to: encoder)
    }
}
