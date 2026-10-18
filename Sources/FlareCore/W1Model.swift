// W1Model.swift: layer masks, track mattes, text runs, paragraph and path-text
// styles, and colour and shape keyframe tracks. Their fields on `Layer` and
// `TextShape` decode from files that lack them and are left out at defaults.
//
// Invariants (`FlareFormat.validateW1` on load and after commands): Doubles are
// finite; feather >= 0, opacity in 0...1, at most `maxMasksPerLayer` masks; a
// matte names another layer of the same list, with no cycle; text runs are
// non-empty, inside the graphemes, sorted, not overlapping, fontSize > 0,
// weight in 100...900; lineHeight in 0.5...4, boxWidth > 0; onPath
// startOffset in 0...1; colour key
// channels in 0...1; tracks hold 1...`maxKeysPerTrack` keys, sorted, unique
// frames in 0...duration; at most `maxTracksPerLayer` tracks; a
// shape track's shapeIndex is a distinct index into `shapes`; a colour track key
// is fill.<i> or stroke.<i> (i indexes `shapes`) or text.<i> (i indexes `texts`);
// mask, path-text and shape-key points count toward `maxTotalPoints`.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A closed path that limits where its layer draws.
public struct LayerMask: Codable, Sendable, Hashable {
    /// The closed outline, in layer coordinates; points finite.
    public var path: Path
    /// How this mask combines with the masks before it.
    public var mode: MaskMode
    /// Edge softness in points.
    public var feather: Double
    /// Mask strength, 0...1: 1 limits fully, 0 leaves the layer unmasked.
    public var opacity: Double
    /// When true the mask keeps what lies outside `path` instead of inside it.
    public var inverted: Bool
    public init(path: Path, mode: MaskMode = .add, feather: Double = 0, opacity: Double = 1, inverted: Bool = false) {
        (self.path, self.mode, self.feather, self.opacity, self.inverted) = (path, mode, feather, opacity, inverted)
    }
}

/// How a mask combines with the masks before it.
public enum MaskMode: String, Codable, Sendable, Hashable { case add, subtract, intersect, difference }

/// The layer draws only where `sourceLayerID`, in the same layer list, covers it.
public struct TrackMatte: Codable, Sendable, Hashable {
    /// The id of another layer in the same list; mattes may not form a cycle.
    public var sourceLayerID: String
    /// Which of the source's values limits this layer.
    public var kind: MatteKind
    public init(sourceLayerID: String, kind: MatteKind = .alpha) { (self.sourceLayerID, self.kind) = (sourceLayerID, kind) }
}

/// What a track matte reads from its source layer: its alpha or its luminance
/// (each 0...1), or one minus that value for the inverted kinds.
public enum MatteKind: String, Codable, Sendable, Hashable { case alpha, alphaInverted, luma, lumaInverted }

/// A style over graphemes `start ..< start + length` of a text shape's string.
/// Nil fields inherit the text shape's own style.
public struct TextRun: Codable, Sendable, Hashable {
    /// First grapheme of the run, an offset into the string's graphemes.
    public var start: Int
    /// Number of graphemes the run covers, > 0.
    public var length: Int
    /// Font family name.
    public var fontFamily: String?
    /// Font size in points, > 0.
    public var fontSize: Double?
    /// CSS-style font weight, 100...900: 400 is regular, 700 bold.
    public var weight: Int?
    /// True sets the run in the family's italic face.
    public var italic: Bool?
    /// Paint for the run's glyphs.
    public var fill: Fill?
    /// Extra space after each grapheme, in points; added to the paragraph's.
    public var tracking: Double?
    /// Points the run's baseline is raised; negative lowers it.
    public var baselineShift: Double?
    public init(start: Int, length: Int, fontFamily: String? = nil, fontSize: Double? = nil, weight: Int? = nil,
                italic: Bool? = nil, fill: Fill? = nil, tracking: Double? = nil, baselineShift: Double? = nil) {
        (self.start, self.length, self.fontFamily, self.fontSize, self.weight) = (start, length, fontFamily, fontSize, weight)
        (self.italic, self.fill, self.tracking, self.baselineShift) = (italic, fill, tracking, baselineShift)
    }
}

/// Line layout of a text shape. `lineHeight` is the baseline-to-baseline
/// distance as a multiple of the font size;
/// a nil `boxWidth` means one line per paragraph, with no wrapping.
public struct ParagraphStyle: Codable, Sendable, Hashable {
    /// How each line sits in the box.
    public var alignment: TextAlignment
    /// Baseline-to-baseline distance as a multiple of the font size, 0.5...4;
    /// 1 sets lines one font size apart.
    public var lineHeight: Double
    /// Extra space after each grapheme, in points, for the whole shape.
    public var tracking: Double
    /// Extra space in points added after each paragraph (at each newline).
    public var paragraphSpacing: Double
    /// Wrap width in points, > 0; nil means no wrapping.
    public var boxWidth: Double?
    public init(alignment: TextAlignment = .leading, lineHeight: Double = 1.2, tracking: Double = 0,
                paragraphSpacing: Double = 0, boxWidth: Double? = nil) {
        (self.alignment, self.lineHeight, self.tracking) = (alignment, lineHeight, tracking)
        (self.paragraphSpacing, self.boxWidth) = (paragraphSpacing, boxWidth)
    }
}

/// Where a line sits in the box: against its start, centred, against its
/// end, or justified (spaces stretched to fill every line but a paragraph's last).
public enum TextAlignment: String, Codable, Sendable, Hashable { case leading, center, trailing, justified }

/// Text set along `path`, starting `startOffset` along it.
public struct TextOnPath: Codable, Sendable, Hashable {
    /// The path the baseline follows.
    public var path: Path
    /// Where the text starts, as a fraction of the path's length, 0...1: 0 is its start, 0.5 its middle.
    public var startOffset: Double
    /// Reverses the path, so the text reads the other way and sits on its other side.
    public var flipped: Bool
    public init(path: Path, startOffset: Double = 0, flipped: Bool = false) {
        (self.path, self.startOffset, self.flipped) = (path, startOffset, flipped)
    }
}

/// A colour value at a frame of one of a layer's `colorTracks`.
public struct ColorKeyframe: Codable, Sendable, Hashable {
    /// Frame in 0...the owning scene's or symbol's duration.
    public var frame: Int
    /// The colour, each channel 0...1.
    public var value: Color
    /// Easing applied from this keyframe to the next one.
    public var easing: Easing
    public init(frame: Int, value: Color, easing: Easing = .linear) {
        (self.frame, self.value, self.easing) = (frame, value, easing)
    }
}

/// A shape's geometry at a frame of a `ShapeTrack`.
public struct PathKeyframe: Codable, Sendable, Hashable {
    /// Frame in 0...the owning scene's or symbol's duration.
    public var frame: Int
    /// The shape's path at this frame.
    public var path: Path
    /// Easing applied from this keyframe to the next one.
    public var easing: Easing
    public init(frame: Int, path: Path, easing: Easing = .linear) {
        (self.frame, self.path, self.easing) = (frame, path, easing)
    }
}

/// Keyframed geometry for the layer's shape at `shapeIndex`.
public struct ShapeTrack: Codable, Sendable, Hashable {
    /// Index into the layer's `shapes`; no two tracks share one.
    public var shapeIndex: Int
    /// Path keys sorted by frame, 1...FlareFormat.maxKeysPerTrack, frames unique and in 0...duration.
    public var keys: [PathKeyframe]
    public init(shapeIndex: Int, keys: [PathKeyframe]) { (self.shapeIndex, self.keys) = (shapeIndex, keys) }
}

/// The W1 fields of a `Layer`, stored together so the layer holds them behind one box.
struct W1Fields: Sendable, Hashable {
    var masks: [LayerMask] = []
    var matte: TrackMatte?
    var colorTracks: [String: [ColorKeyframe]] = [:]
    var shapeTracks: [ShapeTrack] = []
    var isEmpty: Bool { masks.isEmpty && matte == nil && colorTracks.isEmpty && shapeTracks.isEmpty }
}

/// A heap box for `W1Fields`, nil in `LayerFields` while they are empty, so a
/// plain layer skips the W1 checks and copies no W1 arrays.
indirect enum W1Box: Sendable, Hashable {
    case fields(W1Fields)
}
