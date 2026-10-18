// TextStyleCommands+Paragraph.swift: the paragraph and type-on-a-path text
// commands. Stubs (TE-1) that throw `CommandError.notBuilt` until TE-4.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Sets text `textIndex`'s paragraph style; nil clears it.
/// Stub: execute and undo throw `CommandError.notBuilt`.
public struct SetParagraphStyle: LayerParamsCommand {
    public static let id = "text.setParagraph"
    public var label: String { "Set Paragraph Style" }
    public var owner: LayerOwner, layerID: String, textIndex: Int, paragraph: ParagraphStyle?
    public init(owner: LayerOwner, layerID: String, textIndex: Int, paragraph: ParagraphStyle?) {
        (self.owner, self.layerID, self.textIndex, self.paragraph) = (owner, layerID, textIndex, paragraph)
    }
    struct Params: Codable { var textIndex: Int; var paragraph: ParagraphStyle? }
    var params: Params { Params(textIndex: textIndex, paragraph: paragraph) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, textIndex: params.textIndex, paragraph: params.paragraph)
    }
    public mutating func execute(_ document: inout Document) throws { throw TextLayout.notBuilt(Self.id) }
    public func undo(_ document: inout Document) throws { throw TextLayout.notBuilt(Self.id) }
}

/// Sets the path text `textIndex` follows; nil puts it back on a straight
/// baseline. Stub: execute and undo throw `CommandError.notBuilt`.
public struct SetTextOnPath: LayerParamsCommand {
    public static let id = "text.setOnPath"
    public var label: String { "Set Text on Path" }
    public var owner: LayerOwner, layerID: String, textIndex: Int, onPath: TextOnPath?
    public init(owner: LayerOwner, layerID: String, textIndex: Int, onPath: TextOnPath?) {
        (self.owner, self.layerID, self.textIndex, self.onPath) = (owner, layerID, textIndex, onPath)
    }
    struct Params: Codable { var textIndex: Int; var onPath: TextOnPath? }
    var params: Params { Params(textIndex: textIndex, onPath: onPath) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, textIndex: params.textIndex, onPath: params.onPath)
    }
    public mutating func execute(_ document: inout Document) throws { throw TextLayout.notBuilt(Self.id) }
    public func undo(_ document: inout Document) throws { throw TextLayout.notBuilt(Self.id) }
}
