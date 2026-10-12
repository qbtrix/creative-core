// LayerOwner.swift: names the layer list a layer lives in, a scene's or a
// symbol's. Scene ids and symbol ids are separate namespaces, so the kind is
// part of the address.
//
// Invariants:
// - the encoded form is flat: exactly one of the keys "sceneID" and "symbolID",
//   written into the encoder it is given, so a command can encode it beside its
//   own keys. Decoding both keys or neither throws; there is no default owner
// - `description` is the owner prefix of validation messages, e.g. "scene s1"
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public enum LayerOwner: Codable, Sendable, Hashable, CustomStringConvertible {
    case scene(String)
    case symbol(String)

    private enum CodingKeys: String, CodingKey {
        case sceneID, symbolID
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let scene = try c.decodeIfPresent(String.self, forKey: .sceneID)
        let symbol = try c.decodeIfPresent(String.self, forKey: .symbolID)
        switch (scene, symbol) {
        case (let id?, nil): self = .scene(id)
        case (nil, let id?): self = .symbol(id)
        default:
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath, debugDescription: "expected exactly one of sceneID, symbolID"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .scene(let id): try c.encode(id, forKey: .sceneID)
        case .symbol(let id): try c.encode(id, forKey: .symbolID)
        }
    }

    public var description: String {
        switch self {
        case .scene(let id): "scene \(id)"
        case .symbol(let id): "symbol \(id)"
        }
    }
}
