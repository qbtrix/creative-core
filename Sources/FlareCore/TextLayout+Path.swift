// TextLayout+Path.swift: type on a path (TE-1 contract). `onPath` places each
// grapheme of a text shape along its `TextOnPath`; a stub until TE-6.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// One grapheme set on a path: its index in the string, its baseline point
/// and its rotation in degrees (the path's tangent there).
public struct PlacedGlyph: Sendable, Hashable {
    public var index: Int, position: Point, degrees: Double
}

extension TextLayout {
    /// Places `text`'s graphemes along `text.onPath`, flattening the path to
    /// `tolerance`; graphemes past the end of an open path are left out.
    /// Stub: throws `CommandError.notBuilt` until TE-6 gives it a body.
    public static func onPath(_ text: TextShape, measured: [GlyphRunMetrics], tolerance: Double) throws -> [PlacedGlyph] {
        throw notBuilt("TextLayout.onPath")
    }
}
