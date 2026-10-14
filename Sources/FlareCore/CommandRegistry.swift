// CommandRegistry.swift: maps Command.id to a decoder, so a JSON envelope
// {"id": "keyframe.move", "params": {...}} decodes to `any Command`, and any
// registered command encodes to that envelope (journals, scripting, replay).
//
// Untrusted input never crashes: an unknown id throws
// CommandError.unknownCommand, anything else that fails to decode throws
// CommandError.malformedCommand.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public struct CommandRegistry: Sendable {
    typealias Decode = @Sendable (any Decoder) throws -> any Command

    fileprivate var decoders: [String: Decode] = [:]

    /// An empty registry. Most callers want `CommandRegistry.builtIn`.
    public init() {}

    /// Every built-in command family. Each family lists its own command types
    /// in its own file, so a new command touches only that file and a new
    /// family adds one line here.
    static let builtInFamilies: [[any Command.Type]] = [
        CoreCommands.all,
        LayerCommands.all,
        ShapeCommands.all,
        SceneCommands.all,
        KeyframeCommands.all,
        MetadataCommands.all,
        LabelCommands.all,
        GuideCommands.all,
        SymbolCommands.all,
        TextCommands.all,
        SwatchCommands.all,
        InstanceCommands.all,
    ]

    /// Every built-in command.
    public static let builtIn: CommandRegistry = {
        var r = CommandRegistry()
        for type in builtInFamilies.joined() { r.register(type) }
        return r
    }()

    /// Registers `type` under `type.id`. A later registration of the same id
    /// replaces the earlier one.
    public mutating func register<C: Command>(_ type: C.Type) {
        decoders[C.id] = { try C(from: $0) }
    }

    /// The registered ids, sorted.
    public var ids: [String] { decoders.keys.sorted() }

    public func contains(_ id: String) -> Bool { decoders[id] != nil }

    /// Decodes one envelope from `data`.
    public func decode(_ data: Data) throws -> any Command {
        do {
            guard let registryKey else { throw CommandError.malformedCommand("no registry key") }
            let decoder = JSONDecoder()
            decoder.userInfo[registryKey] = self
            return try decoder.decode(IncomingEnvelope.self, from: data).command
        } catch let error as CommandError {
            throw error
        } catch {
            throw CommandError.malformedCommand(String(describing: error))
        }
    }

    /// Encodes `command` as an envelope. Throws `unknownCommand` if its type is
    /// not registered, so every envelope this produces decodes back.
    public func encode(_ command: any Command) throws -> Data {
        let id = type(of: command).id
        guard contains(id) else { throw CommandError.unknownCommand(id) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            return try encoder.encode(OutgoingEnvelope(id: id, command: command))
        } catch {
            throw CommandError.malformedCommand(String(describing: error))
        }
    }
}

private enum EnvelopeKey: String, CodingKey {
    case id, params
}

/// Where `decode` hands the registry to `IncomingEnvelope`. The init is failable
/// in the standard library, so a nil key is handled as an error, never unwrapped.
private let registryKey = CodingUserInfoKey(rawValue: "flare.commandRegistry")

/// Reads the id, then decodes "params" with the decoder registered for it.
private struct IncomingEnvelope: Decodable {
    var command: any Command

    init(from decoder: any Decoder) throws {
        guard let registryKey, let registry = decoder.userInfo[registryKey] as? CommandRegistry else {
            throw CommandError.malformedCommand("no registry")
        }
        let c = try decoder.container(keyedBy: EnvelopeKey.self)
        let id = try c.decode(String.self, forKey: .id)
        guard let decode = registry.decoders[id] else { throw CommandError.unknownCommand(id) }
        command = try decode(c.superDecoder(forKey: .params))
    }
}

private struct OutgoingEnvelope: Encodable {
    var id: String
    var command: any Command

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: EnvelopeKey.self)
        try c.encode(id, forKey: .id)
        try command.encode(to: c.superEncoder(forKey: .params))
    }
}
