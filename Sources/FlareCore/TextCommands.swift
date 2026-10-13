// TextCommands.swift: add, edit and remove a layer's text shapes, addressed by
// owner, layer and text index. A bad index throws shapeNotFound, a locked layer
// layerLocked, and a text breaking a `TextShape` invariant is rejected before
// the document changes. Undo puts back the stored old text, so it is exact.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The text shape commands.
public enum TextCommands {
    public static let all: [any Command.Type] = [
        AddTextShape.self, RemoveTextShape.self, SetTextString.self, SetTextFont.self,
    ]
}

extension Layer {
    func checkTextIndex(_ index: Int) throws {
        guard texts.indices.contains(index) else { throw CommandError.shapeNotFound(index) }
    }
}

extension Document {
    /// Applies `edit` to text `index` of an editable layer, checks the result
    /// and stores it. Returns the old text, for undo.
    mutating func editText(_ owner: LayerOwner, layer: String, index: Int,
                           _ edit: (inout TextShape) -> Void) throws -> TextShape {
        try withEditableLayer(owner, layer: layer) { l in
            try l.checkTextIndex(index)
            var text = l.texts[index]
            edit(&text)
            try text.validate()
            defer { l.texts[index] = text }
            return l.texts[index]
        }
    }

    /// Puts `old` back at text `index`, undoing `editText`.
    mutating func restoreText(_ old: TextShape?, _ owner: LayerOwner, layer: String, index: Int) throws {
        guard let old else { throw CommandError.notExecuted }
        try withLayer(owner, layer: layer) { l in
            try l.checkTextIndex(index)
            l.texts[index] = old
        }
    }
}

/// Appends a text shape to a layer.
public struct AddTextShape: Command {
    public static let id = "text.add"
    public var label: String { "Add Text" }
    public var owner: LayerOwner
    public var layerID: String
    public var text: TextShape
    var insertedAt: Int?

    private struct Params: Codable { var text: TextShape }

    public init(owner: LayerOwner, layerID: String, text: TextShape) {
        self.owner = owner
        self.layerID = layerID
        self.text = text
    }

    public init(from decoder: any Decoder) throws {
        let (owner, layerID, p) = try Self.decodeAddress(from: decoder, params: Params.self)
        self.init(owner: owner, layerID: layerID, text: p.text)
    }
    public func encode(to encoder: any Encoder) throws { try encodeAddress(to: encoder, params: Params(text: text)) }

    public mutating func execute(_ document: inout Document) throws {
        try text.validate()
        insertedAt = try document.withEditableLayer(owner, layer: layerID) { [text] layer in
            layer.texts.append(text)
            return layer.texts.count - 1
        }
    }

    public func undo(_ document: inout Document) throws {
        guard let insertedAt else { throw CommandError.notExecuted }
        try document.withLayer(owner, layer: layerID) { layer in
            try layer.checkTextIndex(insertedAt)
            layer.texts.remove(at: insertedAt)
        }
    }
}

public struct RemoveTextShape: Command {
    public static let id = "text.remove"
    public var label: String { "Delete Text" }
    public var owner: LayerOwner
    public var layerID: String
    public var index: Int
    var removed: TextShape?

    private struct Params: Codable { var index: Int }

    public init(owner: LayerOwner, layerID: String, index: Int) {
        self.owner = owner
        self.layerID = layerID
        self.index = index
    }

    public init(from decoder: any Decoder) throws {
        let (owner, layerID, p) = try Self.decodeAddress(from: decoder, params: Params.self)
        self.init(owner: owner, layerID: layerID, index: p.index)
    }
    public func encode(to encoder: any Encoder) throws { try encodeAddress(to: encoder, params: Params(index: index)) }

    public mutating func execute(_ document: inout Document) throws {
        removed = try document.withEditableLayer(owner, layer: layerID) { [index] layer in
            try layer.checkTextIndex(index)
            return layer.texts.remove(at: index)
        }
    }

    public func undo(_ document: inout Document) throws {
        guard let removed else { throw CommandError.notExecuted }
        try document.withLayer(owner, layer: layerID) { [index] layer in
            guard index >= 0, index <= layer.texts.count else { throw CommandError.shapeNotFound(index) }
            layer.texts.insert(removed, at: index)
        }
    }
}

public struct SetTextString: Command {
    public static let id = "text.setString"
    public var label: String { "Edit Text" }
    public var owner: LayerOwner
    public var layerID: String
    public var index: Int
    public var string: String
    var oldText: TextShape?

    private struct Params: Codable { var index: Int; var string: String }

    public init(owner: LayerOwner, layerID: String, index: Int, string: String) {
        self.owner = owner
        self.layerID = layerID
        self.index = index
        self.string = string
    }

    public init(from decoder: any Decoder) throws {
        let (owner, layerID, p) = try Self.decodeAddress(from: decoder, params: Params.self)
        self.init(owner: owner, layerID: layerID, index: p.index, string: p.string)
    }
    public func encode(to encoder: any Encoder) throws { try encodeAddress(to: encoder, params: Params(index: index, string: string)) }

    public mutating func execute(_ document: inout Document) throws {
        let string = string
        oldText = try document.editText(owner, layer: layerID, index: index) { $0.string = string }
    }

    public func undo(_ document: inout Document) throws {
        try document.restoreText(oldText, owner, layer: layerID, index: index)
    }
}

/// Sets the font family and size of a text shape. The size must be finite and > 0.
public struct SetTextFont: Command {
    public static let id = "text.setFont"
    public var label: String { "Set Font" }
    public var owner: LayerOwner
    public var layerID: String
    public var index: Int
    public var family: String
    public var size: Double
    var oldText: TextShape?

    private struct Params: Codable { var index: Int; var family: String; var size: Double }

    public init(owner: LayerOwner, layerID: String, index: Int, family: String, size: Double) {
        self.owner = owner
        self.layerID = layerID
        self.index = index
        self.family = family
        self.size = size
    }

    public init(from decoder: any Decoder) throws {
        let (owner, layerID, p) = try Self.decodeAddress(from: decoder, params: Params.self)
        self.init(owner: owner, layerID: layerID, index: p.index, family: p.family, size: p.size)
    }
    public func encode(to encoder: any Encoder) throws { try encodeAddress(to: encoder, params: Params(index: index, family: family, size: size)) }

    public mutating func execute(_ document: inout Document) throws {
        let (family, size) = (family, size)
        oldText = try document.editText(owner, layer: layerID, index: index) { text in
            text.fontFamily = family
            text.fontSize = size
        }
    }

    public func undo(_ document: inout Document) throws {
        try document.restoreText(oldText, owner, layer: layerID, index: index)
    }
}
