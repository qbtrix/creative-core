// TextStyleCommands.swift: the text run and style command family. Stubs today
// (TE-1): they decode, encode and register, but execute and undo throw
// `CommandError.notBuilt` until TE-3 (here) and TE-4 (+Paragraph) build them.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The text run and style commands, registered in `CommandRegistry.builtIn`.
public enum TextStyleCommands {
    /// Every text-style command type, in registration order.
    public static let all: [any Command.Type] = [
        ApplyTextStyle.self, ClearTextStyle.self, EditTextString.self, SetParagraphStyle.self, SetTextOnPath.self,
    ]
}

/// The style fields of a `TextRun`; nil leaves a field as it is.
public struct TextRunStyle: Codable, Sendable, Hashable {
    public var fontFamily: String?, fontSize: Double?, weight: Int?, italic: Bool?
    public var fill: Fill?, tracking: Double?, baselineShift: Double?
    public init(fontFamily: String? = nil, fontSize: Double? = nil, weight: Int? = nil, italic: Bool? = nil,
                fill: Fill? = nil, tracking: Double? = nil, baselineShift: Double? = nil) {
        (self.fontFamily, self.fontSize, self.weight, self.italic) = (fontFamily, fontSize, weight, italic)
        (self.fill, self.tracking, self.baselineShift) = (fill, tracking, baselineShift)
    }
}

/// Sets `style`'s non-nil fields on graphemes `range` of text `textIndex`,
/// splitting and merging runs so they never overlap.
/// Stub: execute and undo throw `CommandError.notBuilt`.
public struct ApplyTextStyle: LayerParamsCommand {
    public static let id = "text.applyStyle"
    public var label: String { "Apply Text Style" }
    public var owner: LayerOwner, layerID: String, textIndex: Int, range: Range<Int>, style: TextRunStyle
    public init(owner: LayerOwner, layerID: String, textIndex: Int, range: Range<Int>, style: TextRunStyle) {
        (self.owner, self.layerID, self.textIndex, self.range, self.style) = (owner, layerID, textIndex, range, style)
    }
    struct Params: Codable { var textIndex: Int; var range: Range<Int>; var style: TextRunStyle }
    var params: Params { Params(textIndex: textIndex, range: range, style: style) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, textIndex: params.textIndex, range: params.range, style: params.style)
    }
    public mutating func execute(_ document: inout Document) throws { throw TextLayout.notBuilt(Self.id) }
    public func undo(_ document: inout Document) throws { throw TextLayout.notBuilt(Self.id) }
}

/// Removes every run style from graphemes `range` of text `textIndex`, so
/// they take the shape's own style. Stub: execute and undo throw `CommandError.notBuilt`.
public struct ClearTextStyle: LayerParamsCommand {
    public static let id = "text.clearStyle"
    public var label: String { "Clear Text Style" }
    public var owner: LayerOwner, layerID: String, textIndex: Int, range: Range<Int>
    public init(owner: LayerOwner, layerID: String, textIndex: Int, range: Range<Int>) {
        (self.owner, self.layerID, self.textIndex, self.range) = (owner, layerID, textIndex, range)
    }
    struct Params: Codable { var textIndex: Int; var range: Range<Int> }
    var params: Params { Params(textIndex: textIndex, range: range) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, textIndex: params.textIndex, range: params.range)
    }
    public mutating func execute(_ document: inout Document) throws { throw TextLayout.notBuilt(Self.id) }
    public func undo(_ document: inout Document) throws { throw TextLayout.notBuilt(Self.id) }
}

/// Replaces graphemes `replacing` of text `textIndex` with `with`, keeping
/// every run on its graphemes. Stub: execute and undo throw `CommandError.notBuilt`.
public struct EditTextString: LayerParamsCommand {
    public static let id = "text.editString"
    public var label: String { "Edit Text" }
    public var owner: LayerOwner, layerID: String, textIndex: Int, replacing: Range<Int>, with: String
    public init(owner: LayerOwner, layerID: String, textIndex: Int, replacing: Range<Int>, with: String) {
        (self.owner, self.layerID, self.textIndex, self.replacing, self.with) = (owner, layerID, textIndex, replacing, with)
    }
    struct Params: Codable { var textIndex: Int; var replacing: Range<Int>; var with: String }
    var params: Params { Params(textIndex: textIndex, replacing: replacing, with: with) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, textIndex: params.textIndex, replacing: params.replacing, with: params.with)
    }
    public mutating func execute(_ document: inout Document) throws { throw TextLayout.notBuilt(Self.id) }
    public func undo(_ document: inout Document) throws { throw TextLayout.notBuilt(Self.id) }
}
