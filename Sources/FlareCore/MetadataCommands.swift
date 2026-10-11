// MetadataCommands.swift: commands that edit Document.metadata. Same shape as
// Commands.swift: params first, undo state as optional vars last.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The metadata commands, registered in `CommandRegistry.builtIn`.
public enum MetadataCommands {
    public static let all: [any Command.Type] = [SetMetadata.self]
}

/// Replaces the document's metadata; undo restores the previous value.
public struct SetMetadata: Command {
    public static let id = "document.metadata"
    public var label: String { "Set Document Info" }
    public var metadata: Metadata
    var old: Metadata?

    private enum CodingKeys: String, CodingKey { case metadata }

    public init(metadata: Metadata) {
        self.metadata = metadata
    }

    public mutating func execute(_ document: inout Document) throws {
        old = document.metadata
        document.metadata = metadata
    }

    public func undo(_ document: inout Document) throws {
        guard let old else { throw CommandError.notExecuted }
        document.metadata = old
    }
}
