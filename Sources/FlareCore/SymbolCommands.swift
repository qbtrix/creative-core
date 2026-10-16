// SymbolCommands.swift: commands that add, remove, rename and create symbol
// definitions. Same
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
    public static let all: [any Command.Type] = [
        AddSymbol.self, RemoveSymbol.self, RenameSymbol.self, ConvertToSymbol.self,
    ]
}

extension Document {
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

    private enum CodingKeys: String, CodingKey { case symbolID }

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

/// Renames a symbol definition. A missing symbol throws `symbolNotFound` and
/// an empty name throws `emptyName`, both before any change.
public struct RenameSymbol: Command {
    public static let id = "symbol.rename"
    public var label: String { "Rename Symbol" }
    public var symbolID: String
    public var name: String
    var oldName: String?

    private enum CodingKeys: String, CodingKey { case symbolID, name }

    public init(symbolID: String, name: String) {
        self.symbolID = symbolID
        self.name = name
    }

    public mutating func execute(_ document: inout Document) throws {
        let i = try document.symbolIndex(symbolID)
        guard !name.isEmpty else { throw CommandError.emptyName }
        oldName = document.symbols[i].name
        document.symbols[i].name = name
    }

    public func undo(_ document: inout Document) throws {
        guard let oldName else { throw CommandError.notExecuted }
        let i = try document.symbolIndex(symbolID)
        document.symbols[i].name = oldName
    }
}

/// Moves layers of a scene into a new symbol and puts one layer holding an
/// instance of it where the topmost moved layer was. The symbol keeps the
/// layers in scene order and takes the scene's duration. The new layer takes
/// the first moved layer's id, so layer ids stay unique.
public struct ConvertToSymbol: Command {
    public static let id = "symbol.convert"
    public var label: String { "Convert to Symbol" }
    public var sceneID: String
    /// Must be non-empty, without repeats, and every id in the scene.
    public var layerIDs: [String]
    public var symbolID: String
    public var name: String
    var oldLayers: [Layer]?

    private enum CodingKeys: String, CodingKey { case sceneID, layerIDs, symbolID, name }

    public init(sceneID: String, layerIDs: [String], symbolID: String, name: String) {
        self.sceneID = sceneID
        self.layerIDs = layerIDs
        self.symbolID = symbolID
        self.name = name
    }

    public mutating func execute(_ document: inout Document) throws {
        let si = try document.sceneIndex(sceneID)
        let scene = document.scenes[si]
        guard !layerIDs.isEmpty else { throw CommandError.invalidIndex(0) }
        var seen = Set<String>()
        for id in layerIDs {
            guard seen.insert(id).inserted, scene.layers.contains(where: { $0.id == id }) else {
                throw CommandError.layerNotFound(id)
            }
        }
        guard !document.symbols.contains(where: { $0.id == symbolID }) else {
            throw CommandError.duplicateID(symbolID)
        }
        let moved = scene.layers.filter { seen.contains($0.id) }
        guard let at = scene.layers.firstIndex(where: { seen.contains($0.id) }), let first = moved.first else {
            throw CommandError.invalidIndex(0)
        }
        let host = Layer(id: first.id, name: name, instances: [Instance(symbolID: symbolID)])
        var layers = scene.layers.filter { !seen.contains($0.id) }
        layers.insert(host, at: min(at, layers.count))
        document.symbols.append(Symbol(id: symbolID, name: name, durationFrames: scene.durationFrames, layers: moved))
        document.scenes[si].layers = layers
        oldLayers = scene.layers
    }

    public func undo(_ document: inout Document) throws {
        guard let oldLayers else { throw CommandError.notExecuted }
        let si = try document.sceneIndex(sceneID)
        let i = try document.symbolIndex(symbolID)
        document.symbols.remove(at: i)
        document.scenes[si].layers = oldLayers
    }
}
