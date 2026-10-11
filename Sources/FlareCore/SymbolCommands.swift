// SymbolCommands.swift: commands that add and remove symbol definitions. Same
// shape as SceneCommands.swift: params first, undo state as optional vars
// last. Undo restores the document exactly, including symbol order.
//
// A symbol that an instance still uses cannot be removed, so instances never
// name a missing symbol.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The symbol commands, registered in `CommandRegistry.builtIn`.
public enum SymbolCommands {
    public static let all: [any Command.Type] = [AddSymbol.self, RemoveSymbol.self]
}

extension Document {
    func symbolIndex(_ id: String) throws -> Int {
        guard let i = symbols.firstIndex(where: { $0.id == id }) else { throw CommandError.symbolNotFound(id) }
        return i
    }

    /// True if an instance on any scene layer, or on the layers of a symbol
    /// other than `symbolID` itself, names `symbolID`.
    func symbolIsUsed(_ symbolID: String) -> Bool {
        let uses: ([Layer]) -> Bool = { layers in
            layers.contains { layer in layer.instances.contains { $0.symbolID == symbolID } }
        }
        return scenes.contains { uses($0.layers) }
            || symbols.contains { $0.id != symbolID && uses($0.layers) }
    }
}

public struct AddSymbol: Command {
    public static let id = "symbol.add"
    public var label: String { "Add Symbol" }
    public var symbol: Symbol
    /// Insert position; nil appends. Out-of-range values are clamped.
    public var index: Int?

    public init(symbol: Symbol, index: Int? = nil) {
        self.symbol = symbol
        self.index = index
    }

    public mutating func execute(_ document: inout Document) throws {
        guard !document.symbols.contains(where: { $0.id == symbol.id }) else {
            throw CommandError.duplicateID(symbol.id)
        }
        guard symbol.durationFrames >= 0 else { throw CommandError.invalidDuration(symbol.durationFrames) }
        let known = Set(document.symbols.map(\.id))
        for layer in symbol.layers {
            for instance in layer.instances where !known.contains(instance.symbolID) {
                throw CommandError.symbolNotFound(instance.symbolID)
            }
        }
        let count = document.symbols.count
        let at = min(max(index ?? count, 0), count)
        document.symbols.insert(symbol, at: at)
    }

    public func undo(_ document: inout Document) throws {
        let i = try document.symbolIndex(symbol.id)
        document.symbols.remove(at: i)
    }
}

public struct RemoveSymbol: Command {
    public static let id = "symbol.remove"
    public var label: String { "Delete Symbol" }
    public var symbolID: String
    var removed: Symbol?
    var removedIndex: Int?

    public init(symbolID: String) {
        self.symbolID = symbolID
    }

    public mutating func execute(_ document: inout Document) throws {
        let i = try document.symbolIndex(symbolID)
        guard !document.symbolIsUsed(symbolID) else { throw CommandError.symbolInUse(symbolID) }
        removed = document.symbols.remove(at: i)
        removedIndex = i
    }

    public func undo(_ document: inout Document) throws {
        guard let removed, let removedIndex else { throw CommandError.notExecuted }
        let at = min(max(removedIndex, 0), document.symbols.count)
        document.symbols.insert(removed, at: at)
    }
}
