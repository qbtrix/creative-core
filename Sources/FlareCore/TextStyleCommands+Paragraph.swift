// TextStyleCommands+Paragraph.swift: the paragraph and type-on-a-path text
// commands. Each replaces one whole setting of one text shape (nil clears it)
// and saves the old shape, so undo is exact. The engine's FlareFormat check
// refuses a bad value (lineHeight outside 0.5...4, startOffset outside 0...1).
// A drag of one paragraph field, performed with one coalesce key, merges into
// one step; a step that changes another field starts a new command.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Sets text `textIndex`'s paragraph style; nil clears it.
public struct SetParagraphStyle: LayerParamsCommand {
    public static let id = "text.setParagraph"
    public var label: String { "Set Paragraph Style" }
    public var owner: LayerOwner, layerID: String, textIndex: Int, paragraph: ParagraphStyle?
    var oldText: TextShape?
    public init(owner: LayerOwner, layerID: String, textIndex: Int, paragraph: ParagraphStyle?) {
        (self.owner, self.layerID, self.textIndex, self.paragraph) = (owner, layerID, textIndex, paragraph)
    }
    struct Params: Codable { var textIndex: Int; var paragraph: ParagraphStyle? }
    var params: Params { Params(textIndex: textIndex, paragraph: paragraph) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, textIndex: params.textIndex, paragraph: params.paragraph)
    }
    public mutating func execute(_ document: inout Document) throws {
        let paragraph = paragraph
        oldText = try document.editText(owner, layer: layerID, index: textIndex) { $0.paragraph = paragraph }
    }
    public func undo(_ document: inout Document) throws {
        try document.restoreText(oldText, owner, layer: layerID, index: textIndex)
    }
    /// Folds in `next` when it sets the same text and changes at most the one
    /// field this command changed (a drag of that field); it keeps the old text,
    /// so undo still goes back to before the drag.
    public mutating func merge(_ next: SetParagraphStyle) -> Bool {
        guard let oldText, next.oldText != nil, let set = next.paragraph,
              (next.owner, next.layerID, next.textIndex) == (owner, layerID, textIndex) else { return false }
        let mine = Self.changedFields(oldText.paragraph, paragraph)
        guard mine.count == 1, Self.changedFields(paragraph, set).isSubset(of: mine) else { return false }
        paragraph = set
        return true
    }
    /// The indices of the fields that differ between `a` and `b`, a missing style counting as the default.
    static func changedFields(_ a: ParagraphStyle?, _ b: ParagraphStyle?) -> Set<Int> {
        let (a, b) = (a ?? ParagraphStyle(), b ?? ParagraphStyle())
        let same = [a.alignment == b.alignment, a.lineHeight == b.lineHeight, a.tracking == b.tracking,
                    a.paragraphSpacing == b.paragraphSpacing, a.boxWidth == b.boxWidth]
        return Set(same.indices.filter { !same[$0] })
    }
}

/// Sets the path text `textIndex` follows; nil puts it back on a straight baseline.
public struct SetTextOnPath: LayerParamsCommand {
    public static let id = "text.setOnPath"
    public var label: String { "Set Text on Path" }
    public var owner: LayerOwner, layerID: String, textIndex: Int, onPath: TextOnPath?
    var oldText: TextShape?
    public init(owner: LayerOwner, layerID: String, textIndex: Int, onPath: TextOnPath?) {
        (self.owner, self.layerID, self.textIndex, self.onPath) = (owner, layerID, textIndex, onPath)
    }
    struct Params: Codable { var textIndex: Int; var onPath: TextOnPath? }
    var params: Params { Params(textIndex: textIndex, onPath: onPath) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, textIndex: params.textIndex, onPath: params.onPath)
    }
    public mutating func execute(_ document: inout Document) throws {
        let onPath = onPath
        oldText = try document.editText(owner, layer: layerID, index: textIndex) { $0.onPath = onPath }
    }
    public func undo(_ document: inout Document) throws {
        try document.restoreText(oldText, owner, layer: layerID, index: textIndex)
    }
}
