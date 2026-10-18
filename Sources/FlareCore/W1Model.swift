// W1Model.swift: layer masks, track mattes, text runs, paragraph and path-text
// styles, and colour and shape keyframe tracks. Their fields on `Layer` and
// `TextShape` decode from files that lack them and are left out at defaults.
//
// Invariants (`FlareFormat.validateW1` on load and after commands): Doubles are
// finite; feather >= 0, opacity in 0...1, at most `maxMasksPerLayer` masks; a
// matte names another layer of the same list, with no cycle; text runs are
// non-empty, inside the graphemes, sorted, not overlapping, fontSize > 0;
// lineHeight in 0.5...4, boxWidth > 0; tracks hold 1...`maxKeysPerTrack` keys,
// sorted, unique frames in 0...duration; shapeIndex >= 0 (readers bound it).
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A closed path that limits where its layer draws.
public struct LayerMask: Codable, Sendable, Hashable {
    public var path: Path
    public var mode: MaskMode
    /// Edge softness in points.
    public var feather: Double
    public var opacity: Double
    public var inverted: Bool
    public init(path: Path, mode: MaskMode = .add, feather: Double = 0, opacity: Double = 1, inverted: Bool = false) {
        (self.path, self.mode, self.feather, self.opacity, self.inverted) = (path, mode, feather, opacity, inverted)
    }
}

/// How a mask combines with the masks before it.
public enum MaskMode: String, Codable, Sendable, Hashable { case add, subtract, intersect, difference }

/// The layer draws only where `sourceLayerID`, in the same layer list, covers it.
public struct TrackMatte: Codable, Sendable, Hashable {
    public var sourceLayerID: String
    public var kind: MatteKind
    public init(sourceLayerID: String, kind: MatteKind = .alpha) { (self.sourceLayerID, self.kind) = (sourceLayerID, kind) }
}

public enum MatteKind: String, Codable, Sendable, Hashable { case alpha, alphaInverted, luma, lumaInverted }

/// A style over graphemes `start ..< start + length` of a text shape's string.
/// Nil fields inherit the text shape's own style.
public struct TextRun: Codable, Sendable, Hashable {
    public var start: Int
    public var length: Int
    public var fontFamily: String?
    public var fontSize: Double?
    public var weight: Int?
    public var italic: Bool?
    public var fill: Fill?
    public var tracking: Double?
    public var baselineShift: Double?
    public init(start: Int, length: Int, fontFamily: String? = nil, fontSize: Double? = nil, weight: Int? = nil,
                italic: Bool? = nil, fill: Fill? = nil, tracking: Double? = nil, baselineShift: Double? = nil) {
        (self.start, self.length, self.fontFamily, self.fontSize, self.weight) = (start, length, fontFamily, fontSize, weight)
        (self.italic, self.fill, self.tracking, self.baselineShift) = (italic, fill, tracking, baselineShift)
    }
}

/// Line layout of a text shape. `lineHeight` is a multiple of the font size;
/// a nil `boxWidth` means one line per paragraph, with no wrapping.
public struct ParagraphStyle: Codable, Sendable, Hashable {
    public var alignment: TextAlignment
    public var lineHeight: Double
    public var tracking: Double
    public var paragraphSpacing: Double
    public var boxWidth: Double?
    public init(alignment: TextAlignment = .leading, lineHeight: Double = 1.2, tracking: Double = 0,
                paragraphSpacing: Double = 0, boxWidth: Double? = nil) {
        (self.alignment, self.lineHeight, self.tracking) = (alignment, lineHeight, tracking)
        (self.paragraphSpacing, self.boxWidth) = (paragraphSpacing, boxWidth)
    }
}

public enum TextAlignment: String, Codable, Sendable, Hashable { case leading, center, trailing, justified }

/// Text set along `path`, starting `startOffset` points from its start.
public struct TextOnPath: Codable, Sendable, Hashable {
    public var path: Path
    public var startOffset: Double
    public var flipped: Bool
    public init(path: Path, startOffset: Double = 0, flipped: Bool = false) {
        (self.path, self.startOffset, self.flipped) = (path, startOffset, flipped)
    }
}

public struct ColorKeyframe: Codable, Sendable, Hashable {
    public var frame: Int
    public var value: Color
    /// Easing applied from this keyframe to the next one.
    public var easing: Easing
    public init(frame: Int, value: Color, easing: Easing = .linear) {
        (self.frame, self.value, self.easing) = (frame, value, easing)
    }
}

public struct PathKeyframe: Codable, Sendable, Hashable {
    public var frame: Int
    public var path: Path
    /// Easing applied from this keyframe to the next one.
    public var easing: Easing
    public init(frame: Int, path: Path, easing: Easing = .linear) {
        (self.frame, self.path, self.easing) = (frame, path, easing)
    }
}

/// Keyframed geometry for the layer's shape at `shapeIndex`.
public struct ShapeTrack: Codable, Sendable, Hashable {
    public var shapeIndex: Int
    public var keys: [PathKeyframe]
    public init(shapeIndex: Int, keys: [PathKeyframe]) { (self.shapeIndex, self.keys) = (shapeIndex, keys) }
}
