// SwatchCommands.swift: commands that edit Document.swatches, the document's
// color palette. Same shape as SymbolCommands.swift: params first, undo state
// as optional vars last. Undo restores the palette exactly, including order.
//
// A swatch is keyed by its name, so names stay unique and non-empty, and every
// swatch color has channels finite and in 0...1 (all checked by
// FlareFormat.validate too).
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The swatch commands, registered in `CommandRegistry.builtIn`.
public enum SwatchCommands {
    public static let all: [any Command.Type] = [
        AddSwatch.self, RenameSwatch.self, SetSwatchColor.self, RemoveSwatch.self,
    ]
}

extension Document {
    func swatchIndex(_ name: String) throws -> Int {
        guard let i = swatches.firstIndex(where: { $0.name == name }) else { throw CommandError.swatchNotFound(name) }
        return i
    }
}

/// Appends a swatch to the palette.
public struct AddSwatch: Command {
    public static let id = "swatch.add"
    public var label: String { "Add Swatch" }
    public var name: String
    public var color: Color

    public init(name: String, color: Color) {
        self.name = name
        self.color = color
    }

    public mutating func execute(_ document: inout Document) throws {
        guard !name.isEmpty else { throw CommandError.emptySwatchName }
        guard !document.swatches.contains(where: { $0.name == name }) else { throw CommandError.duplicateID(name) }
        guard color.isInRange else { throw CommandError.invalidColor(color) }
        document.swatches.append(Swatch(name: name, color: color))
    }

    public func undo(_ document: inout Document) throws {
        let i = try document.swatchIndex(name)
        document.swatches.remove(at: i)
    }
}

/// Renames the swatch `name` to `newName`, which no other swatch may have.
public struct RenameSwatch: Command {
    public static let id = "swatch.rename"
    public var label: String { "Rename Swatch" }
    public var name: String
    public var newName: String

    public init(name: String, newName: String) {
        self.name = name
        self.newName = newName
    }

    public mutating func execute(_ document: inout Document) throws {
        let i = try document.swatchIndex(name)
        guard !newName.isEmpty else { throw CommandError.emptySwatchName }
        guard newName == name || !document.swatches.contains(where: { $0.name == newName }) else {
            throw CommandError.duplicateID(newName)
        }
        document.swatches[i].name = newName
    }

    public func undo(_ document: inout Document) throws {
        let i = try document.swatchIndex(newName)
        document.swatches[i].name = name
    }
}

/// Replaces the color of the swatch `name`.
public struct SetSwatchColor: Command {
    public static let id = "swatch.setColor"
    public var label: String { "Set Swatch Color" }
    public var name: String
    public var color: Color
    var oldColor: Color?

    private enum CodingKeys: String, CodingKey { case name, color }

    public init(name: String, color: Color) {
        self.name = name
        self.color = color
    }

    public mutating func execute(_ document: inout Document) throws {
        let i = try document.swatchIndex(name)
        guard color.isInRange else { throw CommandError.invalidColor(color) }
        oldColor = document.swatches[i].color
        document.swatches[i].color = color
    }

    public func undo(_ document: inout Document) throws {
        guard let oldColor else { throw CommandError.notExecuted }
        let i = try document.swatchIndex(name)
        document.swatches[i].color = oldColor
    }
}

/// Removes the swatch `name` from the palette.
public struct RemoveSwatch: Command {
    public static let id = "swatch.remove"
    public var label: String { "Delete Swatch" }
    public var name: String
    var removed: Swatch?
    var removedIndex: Int?

    private enum CodingKeys: String, CodingKey { case name }

    public init(name: String) {
        self.name = name
    }

    public mutating func execute(_ document: inout Document) throws {
        let i = try document.swatchIndex(name)
        removed = document.swatches.remove(at: i)
        removedIndex = i
    }

    public func undo(_ document: inout Document) throws {
        guard let removed, let removedIndex else { throw CommandError.notExecuted }
        guard (0...document.swatches.count).contains(removedIndex) else {
            throw CommandError.invalidIndex(removedIndex)
        }
        document.swatches.insert(removed, at: removedIndex)
    }
}
