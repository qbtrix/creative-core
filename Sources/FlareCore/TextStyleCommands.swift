// TextStyleCommands.swift: the text run and style command family: style a
// grapheme range, clear it, and edit the string with its runs kept on their
// graphemes. Offsets count graphemes (`Character`s), never UTF-16 units. After
// each command the runs are sorted, never overlap, stay inside the string,
// touching equal neighbours are merged, and a run in the shape's own style is
// dropped. A range outside the string throws `invalidIndex` with the document
// untouched; undo puts back the old text, so it is exact. The paragraph and
// path commands live in TextStyleCommands+Paragraph.swift (TE-4).
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

/// The style fields of a `TextRun`; nil leaves a field as it is. Fields mean
/// what `TextRun`'s do: font family name, size in points, CSS weight
/// (100...900), italic, fill, tracking and baseline shift in points.
///
/// To remove one field from a range, set it to the shape's own value (its
/// font family, size or fill), or to weight 400, italic false, tracking 0 or
/// baseline shift 0; the run drops it. `ClearTextStyle` removes every field.
public struct TextRunStyle: Codable, Sendable, Hashable {
    /// The font family name; the shape's own family removes it.
    public var fontFamily: String?
    /// The font size in points; the shape's own size removes it.
    public var fontSize: Double?
    /// The CSS font weight, 100...900; 400 removes it.
    public var weight: Int?
    /// Whether the graphemes are italic; false removes it.
    public var italic: Bool?
    /// The fill; the shape's own fill removes it.
    public var fill: Fill?
    /// Extra space after each grapheme, in points, added to the paragraph's; 0 removes it.
    public var tracking: Double?
    /// Points the baseline is raised, negative lowers; 0 removes it.
    public var baselineShift: Double?
    /// A style with the given fields set; every field left nil is unchanged when applied.
    public init(fontFamily: String? = nil, fontSize: Double? = nil, weight: Int? = nil, italic: Bool? = nil,
                fill: Fill? = nil, tracking: Double? = nil, baselineShift: Double? = nil) {
        (self.fontFamily, self.fontSize, self.weight, self.italic) = (fontFamily, fontSize, weight, italic)
        (self.fill, self.tracking, self.baselineShift) = (fill, tracking, baselineShift)
    }
}

/// Sets `style`'s non-nil fields on graphemes `range` of text `textIndex`,
/// splitting and merging runs so they never overlap. A field set to the
/// shape's own value (or weight 400, italic false, tracking/baselineShift 0)
/// is removed from the range; see `TextRunStyle`. Throws `invalidIndex` when
/// `range` is outside the string's graphemes (offsets count graphemes, not
/// UTF-16 units), with the out-of-range bound as its number, and
/// `invalidDocument` when an existing run lies outside the string. Through
/// `CommandEngine.perform`, a value outside the format's range (fontSize > 0,
/// weight 100...900) throws `CommandError.invalidDocument` naming the field; a
/// locked layer throws `layerLocked` and a missing text `shapeNotFound`.
public struct ApplyTextStyle: LayerParamsCommand {
    public static let id = "text.applyStyle"
    public var label: String { "Apply Text Style" }
    public var owner: LayerOwner, layerID: String, textIndex: Int, range: Range<Int>, style: TextRunStyle
    var oldText: TextShape?
    public init(owner: LayerOwner, layerID: String, textIndex: Int, range: Range<Int>, style: TextRunStyle) {
        (self.owner, self.layerID, self.textIndex, self.range, self.style) = (owner, layerID, textIndex, range, style)
    }
    struct Params: Codable { var textIndex: Int; var range: Range<Int>; var style: TextRunStyle }
    var params: Params { Params(textIndex: textIndex, range: range, style: style) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, textIndex: params.textIndex, range: params.range, style: params.style)
    }
    public mutating func execute(_ document: inout Document) throws {
        let (range, style) = (range, style)
        oldText = try document.editTextRuns(owner, layer: layerID, index: textIndex) { try $0.restyle(range) { $0.applying(style) } }
    }
    public func undo(_ document: inout Document) throws {
        try document.restoreText(oldText, owner, layer: layerID, index: textIndex)
    }
}

/// Removes every run style from graphemes `range` of text `textIndex`, so
/// they take the shape's own style. To remove only one field, use
/// `ApplyTextStyle` with that field set to the shape's own value. Throws
/// `invalidIndex` when `range` is outside the string's graphemes, with the
/// out-of-range bound as its number, and `invalidDocument` when an existing
/// run lies outside the string.
public struct ClearTextStyle: LayerParamsCommand {
    public static let id = "text.clearStyle"
    public var label: String { "Clear Text Style" }
    public var owner: LayerOwner, layerID: String, textIndex: Int, range: Range<Int>
    var oldText: TextShape?
    public init(owner: LayerOwner, layerID: String, textIndex: Int, range: Range<Int>) {
        (self.owner, self.layerID, self.textIndex, self.range) = (owner, layerID, textIndex, range)
    }
    struct Params: Codable { var textIndex: Int; var range: Range<Int> }
    var params: Params { Params(textIndex: textIndex, range: range) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, textIndex: params.textIndex, range: params.range)
    }
    public mutating func execute(_ document: inout Document) throws {
        let range = range
        oldText = try document.editTextRuns(owner, layer: layerID, index: textIndex) { try $0.restyle(range) { _ in .plain } }
    }
    public func undo(_ document: inout Document) throws {
        try document.restoreText(oldText, owner, layer: layerID, index: textIndex)
    }
}

/// Replaces graphemes `replacing` of text `textIndex` with `replacement`,
/// keeping every run on its graphemes: runs after the edit shift, a run the
/// edit cuts shrinks, and inserted text takes the style of the grapheme before it.
/// Throws `invalidIndex` when `replacing` is outside the string's graphemes,
/// with the out-of-range bound as its number, and `invalidDocument` when an
/// existing run lies outside the string. Throws `invalidDocument`, with a
/// message starting "Edit Text:" that names the inserted scalars, the edit's
/// grapheme offset and the neighbouring graphemes, when `replacement` starts
/// or ends with a mark that would join the grapheme beside the edit (a
/// combining mark, a joiner); widen `replacing` to include that grapheme.
public struct EditTextString: LayerParamsCommand {
    public static let id = "text.editString"
    public var label: String { "Edit Text" }
    public var owner: LayerOwner, layerID: String, textIndex: Int, replacing: Range<Int>
    /// The text put in place of graphemes `replacing`; empty deletes them.
    public var replacement: String
    var oldText: TextShape?
    public init(owner: LayerOwner, layerID: String, textIndex: Int, replacing: Range<Int>, with replacement: String) {
        (self.owner, self.layerID, self.textIndex, self.replacing) = (owner, layerID, textIndex, replacing)
        self.replacement = replacement
    }
    struct Params: Codable { var textIndex: Int; var replacing: Range<Int>; var with: String }
    var params: Params { Params(textIndex: textIndex, replacing: replacing, with: replacement) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, textIndex: params.textIndex, replacing: params.replacing, with: params.with)
    }
    public mutating func execute(_ document: inout Document) throws {
        let (range, replacement) = (replacing, replacement)
        oldText = try document.editTextRuns(owner, layer: layerID, index: textIndex) { try $0.replace(range, with: replacement) }
    }
    public func undo(_ document: inout Document) throws {
        try document.restoreText(oldText, owner, layer: layerID, index: textIndex)
    }
}

extension Document {
    /// `editText` with an `edit` that may throw; a refused edit puts the text
    /// back, so the document is left as it was.
    mutating func editTextRuns(_ owner: LayerOwner, layer: String, index: Int,
                               _ edit: (inout TextShape) throws -> Void) throws -> TextShape {
        var failure: (any Error)?
        let old = try editText(owner, layer: layer, index: index) { text in
            let saved = text
            do { try edit(&text) } catch { (failure, text) = (error, saved) }
        }
        if let failure { throw failure }
        return old
    }
}

extension TextRun {
    /// A run with no style of its own: every field nil.
    static let plain = TextRun(start: 0, length: 0)

    /// This run's style with `style`'s non-nil fields set over it.
    func applying(_ style: TextRunStyle) -> TextRun {
        TextRun(start: start, length: length, fontFamily: style.fontFamily ?? fontFamily, fontSize: style.fontSize ?? fontSize,
                weight: style.weight ?? weight, italic: style.italic ?? italic, fill: style.fill ?? fill,
                tracking: style.tracking ?? tracking, baselineShift: style.baselineShift ?? baselineShift)
    }

    /// This run's style over graphemes `start ..< end`.
    func over(_ start: Int, _ end: Int) -> TextRun {
        var run = self
        (run.start, run.length) = (start, end - start)
        return run
    }
}

extension TextShape {
    /// Throws `invalidIndex` unless `range` lies inside the string's graphemes,
    /// and `invalidDocument` unless every run does, the way FlareFormat checks
    /// them: runs come from the document, so their ends must not overflow.
    func checkGraphemes(_ range: Range<Int>) throws {
        let count = string.count
        if range.lowerBound < 0 { throw CommandError.invalidIndex(range.lowerBound) }
        if count < range.upperBound { throw CommandError.invalidIndex(range.upperBound) }
        for run in runs where run.start < 0 || run.length <= 0 || run.start > count - run.length {
            throw CommandError.invalidDocument("text run at \(run.start), length \(run.length), is outside the \(count) graphemes")
        }
    }

    /// Restyles graphemes `range`: each piece inside it (part of a run, or a gap
    /// in the shape's own style) takes `transform` of its style; outside, runs keep theirs.
    mutating func restyle(_ range: Range<Int>, _ transform: (TextRun) -> TextRun) throws {
        try checkGraphemes(range)
        let (lo, hi) = (range.lowerBound, range.upperBound)
        var out: [TextRun] = []
        var cursor = lo
        for run in runs.sorted(by: { $0.start < $1.start }) {
            let end = run.start + run.length
            if run.start < lo { out.append(run.over(run.start, min(end, lo))) }
            if end > hi { out.append(run.over(max(run.start, hi), end)) }
            let (s, e) = (max(run.start, cursor), min(end, hi))
            guard s < e else { continue }
            if cursor < s { out.append(transform(.plain).over(cursor, s)) }
            out.append(transform(run).over(s, e))
            cursor = e
        }
        if cursor < hi { out.append(transform(.plain).over(cursor, hi)) }
        runs = normalized(out)
    }

    /// Replaces graphemes `range` with `with`. A run starting before the edit
    /// keeps its start, else it moves past the inserted text; a run ending before
    /// the edit keeps its end, else the end moves with the string, so a run
    /// ending at the edit point takes the inserted text. Throws
    /// `invalidDocument`, naming the inserted scalars, the edit's grapheme
    /// offset and its neighbours, when `with` would fuse with one of them.
    mutating func replace(_ range: Range<Int>, with: String) throws {
        try checkGraphemes(range)
        let (lo, hi, count) = (range.lowerBound, range.upperBound, string.count)
        let from = string.index(string.startIndex, offsetBy: lo), to = string.index(from, offsetBy: hi - lo)
        let edited = String(string[..<from]) + with + String(string[to...])
        let delta = with.count - (hi - lo)
        guard edited.count == count + delta else {
            let scalars = with.unicodeScalars.map { "U+" + String($0.value, radix: 16, uppercase: true) }.joined(separator: " ")
            let before = lo > 0 ? "\"\(string[string.index(before: from)])\"" : "none"
            let after = hi < count ? "\"\(string[to])\"" : "none"
            throw CommandError.invalidDocument("Edit Text: \(scalars) inserted at grapheme \(lo) joins the grapheme beside it"
                + " (before: \(before), after: \(after)); include that grapheme in `replacing`")
        }
        string = edited
        runs = normalized(runs.map { run in
            let end = run.start + run.length
            let start = run.start < lo ? run.start : max(run.start, hi) + delta
            return run.over(start, lo > end ? end : max(end, hi) + delta)
        })
    }

    /// `runs` sorted, with fields equal to the shape's own cleared, empty and
    /// plain runs dropped, and touching equal neighbours merged.
    func normalized(_ runs: [TextRun]) -> [TextRun] {
        var out: [TextRun] = []
        for var run in runs.sorted(by: { $0.start < $1.start }) where run.length > 0 {
            if run.fontFamily == fontFamily { run.fontFamily = nil }
            if run.fontSize == fontSize { run.fontSize = nil }
            if run.weight == 400 { run.weight = nil }
            if run.italic == false { run.italic = nil }
            if run.fill == fill { run.fill = nil }
            if run.tracking == 0 { run.tracking = nil }
            if run.baselineShift == 0 { run.baselineShift = nil }
            let style = run.over(0, 0)
            guard style != .plain else { continue }
            if let last = out.last, last.start + last.length == run.start, last.over(0, 0) == style {
                out[out.count - 1].length += run.length
            } else {
                out.append(run)
            }
        }
        return out
    }
}
