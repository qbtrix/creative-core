// LayerCommand.swift: the built-in commands that change only one layer, so
// CommandEngine validates their result scoped to that layer. A command that
// conforms must never touch another layer, a scene or symbol field, or a
// machine. Each names its layer by `owner` (a scene or a symbol) and
// `layerID`, encoded flat beside its own keys by the helpers below.

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
}

/// A layer command whose own params are one synthesized-Codable `Params`,
/// written flat beside its owner and "layerID". Its Codable comes from here.
protocol LayerParamsCommand: LayerCommand {
    associatedtype Params: Codable
    var params: Params { get }
    init(owner: LayerOwner, layerID: String, params: Params)
}

extension LayerParamsCommand {
    public init(from decoder: any Decoder) throws {
        let (owner, layerID) = try Self.decodeAddress(from: decoder)
        try self.init(owner: owner, layerID: layerID, params: Params(from: decoder))
    }

    public func encode(to encoder: any Encoder) throws {
        try encodeAddress(to: encoder)
        try params.encode(to: encoder)
    }
}

/// The params of a command that edits one item (a shape or a text) of a layer.
struct ItemIndex: Codable { var index: Int }

/// A layer command whose only own param is an item index.
protocol LayerItemCommand: LayerParamsCommand where Params == ItemIndex {
    var index: Int { get }
    init(owner: LayerOwner, layerID: String, index: Int)
}

extension LayerItemCommand {
    var params: ItemIndex { ItemIndex(index: index) }

    init(owner: LayerOwner, layerID: String, params: ItemIndex) {
        self.init(owner: owner, layerID: layerID, index: params.index)
    }
}
