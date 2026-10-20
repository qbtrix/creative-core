// Document.swift: the Flare document model. A Document holds Scenes; a Scene
// holds Layers; a Layer holds vector Shapes and keyframe tracks keyed by
// property name ("x", "opacity", ..., "strokeWidth.<i>"; see `Layer.tracks`).
//
// Invariants (checked by the format layer on load, kept by commands):
// - every public type here is a Codable, Sendable value type with no shared mutable
//   state; Layer keeps its fields behind a private copy-on-write box (LayerStorage),
//   so copying a big scene's layer array costs an id and a pointer per layer
// - Scene.rate has both parts > 0, Scene.durationFrames >= 0
// - Scene.width and Scene.height are finite and > 0
// - Scene label frames are in 0...durationFrames
// - Scene guide positions are finite
// - Scene background color channels are finite
// - layer ids are unique within a scene or symbol
// - symbol ids are unique, Symbol.durationFrames >= 0
// - every layer instance names a known symbol and has firstFrame >= 0
// - each track is sorted by frame, frames are unique and >= 0, and a track is
//   never stored empty (an empty track is removed, so undo restores equality)
// - keyframe values and shape points (including path points) are finite, and a
//   scaleX/scaleY value × 100 is finite too (Lottie writes scale as a percent)
// - text shapes have a finite font size > 0 and a finite position
// - swatch names are non-empty and unique, and swatch color channels are finite and in 0...1
// - masks, mattes, text styles and colour and shape tracks keep the rules in W1Model.swift
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public struct Document: Codable, Sendable, Hashable {
    public var scenes: [Scene]
    /// Reusable symbol definitions. Missing in older v1 files means empty.
    public var symbols: [Symbol]
    /// Title, author and generator. Missing in older v1 files means empty.
    public var metadata: Metadata
    /// Interactive state machines. Missing in older v1 files means empty.
    public var stateMachines: [StateMachine]
    /// The document's color palette, in display order. Missing in older v1
    /// files means empty.
    public var swatches: [Swatch]

    public init(
        scenes: [Scene] = [], symbols: [Symbol] = [], metadata: Metadata = Metadata(),
        stateMachines: [StateMachine] = [], swatches: [Swatch] = []
    ) {
        self.scenes = scenes
        self.symbols = symbols
        self.metadata = metadata
        self.stateMachines = stateMachines
        self.swatches = swatches
    }

    private enum CodingKeys: String, CodingKey {
        case scenes, symbols, metadata, stateMachines, swatches
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scenes = try container.decode([Scene].self, forKey: .scenes)
        symbols = try container.decodeIfPresent([Symbol].self, forKey: .symbols) ?? []
        metadata = try container.decodeIfPresent(Metadata.self, forKey: .metadata) ?? Metadata()
        stateMachines = try container.decodeIfPresent([StateMachine].self, forKey: .stateMachines) ?? []
        swatches = try container.decodeIfPresent([Swatch].self, forKey: .swatches) ?? []
    }

    /// Empty metadata, state machines and swatches are left out, so documents
    /// without them encode as before.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scenes, forKey: .scenes)
        try container.encode(symbols, forKey: .symbols)
        if !metadata.isEmpty { try container.encode(metadata, forKey: .metadata) }
        if !stateMachines.isEmpty { try container.encode(stateMachines, forKey: .stateMachines) }
        if !swatches.isEmpty { try container.encode(swatches, forKey: .swatches) }
    }
}

/// A named color in the document palette. The name is the swatch's key.
public struct Swatch: Codable, Sendable, Hashable {
    public var name: String
    public var color: Color

    public init(name: String, color: Color) {
        self.name = name
        self.color = color
    }
}

/// Descriptive document info. Every field is optional; nil fields are not encoded.
public struct Metadata: Codable, Sendable, Hashable {
    public var title: String?
    public var author: String?
    /// The app or tool that wrote the file, e.g. "Flare 1.0".
    public var generator: String?

    public init(title: String? = nil, author: String? = nil, generator: String? = nil) {
        self.title = title
        self.author = author
        self.generator = generator
    }

    public var isEmpty: Bool { title == nil && author == nil && generator == nil }
}

/// A reusable animation with its own timeline. Its layers follow the same
/// invariants as scene layers.
public struct Symbol: Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var durationFrames: Int
    public var layers: [Layer]

    public init(id: String, name: String, durationFrames: Int = 48, layers: [Layer] = []) {
        self.id = id
        self.name = name
        self.durationFrames = durationFrames
        self.layers = layers
    }
}

public struct Scene: Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    /// The exact frame rate. Files store it as `fps` when whole and add `frameRate` when not.
    public var rate: SceneRate
    /// The whole rate nearest `rate` (30 for 29.97); setting it makes the rate that whole number.
    public var fps: Int {
        get { rate.nominal }
        set { rate = SceneRate(whole: newValue) }
    }
    public var durationFrames: Int
    /// Canvas size in points.
    public var width: Double
    public var height: Double
    public var background: Color
    public var layers: [Layer]
    /// Named frames, label name to frame in `0...durationFrames`.
    public var labels: [String: Int]
    /// Ruler guides in scene coordinates, in the order they were added.
    public var guides: [Guide]

    public static let defaultWidth: Double = 550
    public static let defaultHeight: Double = 400

    public init(
        id: String, name: String, fps: Int = 24, durationFrames: Int = 48,
        width: Double = Scene.defaultWidth, height: Double = Scene.defaultHeight,
        background: Color = .white, layers: [Layer] = [], labels: [String: Int] = [:],
        guides: [Guide] = [], rate: SceneRate? = nil
    ) {
        self.id = id
        self.name = name
        self.rate = rate ?? SceneRate(whole: fps)
        self.durationFrames = durationFrames
        self.width = width
        self.height = height
        self.background = background
        self.layers = layers
        self.labels = labels
        self.guides = guides
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, fps, frameRate, durationFrames, width, height, background, layers, labels, guides
    }

    /// Files written before the canvas fields, labels, guides or `frameRate` existed decode with the defaults; a
    /// file without `frameRate` runs at its whole `fps`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        let whole = try c.decode(Int.self, forKey: .fps)
        rate = try c.decodeIfPresent(SceneRate.self, forKey: .frameRate) ?? SceneRate(whole: whole)
        durationFrames = try c.decode(Int.self, forKey: .durationFrames)
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? Scene.defaultWidth
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? Scene.defaultHeight
        background = try c.decodeIfPresent(Color.self, forKey: .background) ?? .white
        layers = try c.decode([Layer].self, forKey: .layers)
        labels = try c.decodeIfPresent([String: Int].self, forKey: .labels) ?? [:]
        guides = try c.decodeIfPresent([Guide].self, forKey: .guides) ?? []
    }

    /// `fps` always (the nominal rate, what older readers use) and `frameRate` only when the rate isn't whole, so
    /// a whole-rate scene writes the same bytes as before rates were fractions.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(rate.isWhole ? rate.numerator : rate.nominal, forKey: .fps)
        if !rate.isWhole { try c.encode(rate, forKey: .frameRate) }
        try c.encode(durationFrames, forKey: .durationFrames)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encode(background, forKey: .background)
        try c.encode(layers, forKey: .layers)
        try c.encode(labels, forKey: .labels)
        try c.encode(guides, forKey: .guides)
    }
}

/// A ruler guide: a horizontal line at y = `position` or a vertical line at
/// x = `position`, in scene coordinates. Guides are editing aids and never render.
public struct Guide: Codable, Sendable, Hashable {
    public enum Axis: String, Codable, Sendable, Hashable { case horizontal, vertical }

    public var axis: Axis
    /// Finite.
    public var position: Double

    public init(axis: Axis, position: Double) {
        self.axis = axis
        self.position = position
    }
}

/// The fields of a `Layer` other than its id; see `Layer` for each one.
struct LayerFields: Sendable, Hashable {
    var name: String
    var shapes: [Shape]
    var tracks: [String: [Keyframe]]
    var isVisible: Bool
    var isLocked: Bool
    var instances: [Instance]
    var texts: [TextShape]
    var w1: W1Box?
}

/// The copy-on-write box behind a `Layer`. Sendable because no box is written
/// while shared: `Layer` writes only through its `fields`, which first copies
/// a box it does not own alone, the way Array's own storage works.
final class LayerStorage: @unchecked Sendable {
    var fields: LayerFields
    init(_ fields: LayerFields) { self.fields = fields }
}

public struct Layer: Codable, Sendable, Hashable {
    /// Stored inline, so a scan for a layer by id reads the array, not each box.
    public var id: String
    public var name: String {
        get { storage.fields.name }
        _modify { yield &fields.name }
    }
    public var shapes: [Shape] {
        get { storage.fields.shapes }
        _modify { yield &fields.shapes }
    }
    /// Number keyframes keyed by property: "x", "y", "scaleX", "scaleY",
    /// "rotation" and "opacity" for the layer, "strokeWidth.<i>" for the
    /// stroke width of `shapes[i]` (build it with `trackKey(strokeWidthOf:)`),
    /// and "trimStart.<i>", "trimEnd.<i>" and "trimOffset.<i>" for its stroke's trim.
    /// Any other key is stored, but no drawing or export reads it.
    public var tracks: [String: [Keyframe]] {
        get { storage.fields.tracks }
        _modify { yield &fields.tracks }
    }
    /// Hidden layers are skipped when rendering; they stay editable.
    public var isVisible: Bool {
        get { storage.fields.isVisible }
        _modify { yield &fields.isVisible }
    }
    /// Locked layers reject commands that edit their shapes or keyframes.
    public var isLocked: Bool {
        get { storage.fields.isLocked }
        _modify { yield &fields.isLocked }
    }
    /// Symbol placements on this layer. Missing in older v1 files means empty.
    public var instances: [Instance] {
        get { storage.fields.instances }
        _modify { yield &fields.instances }
    }
    /// Text drawn above the shapes. Missing in older v1 files means empty.
    public var texts: [TextShape] {
        get { storage.fields.texts }
        _modify { yield &fields.texts }
    }
    /// Masks applied in order. Missing in older files means none.
    public var masks: [LayerMask] {
        get { w1Fields.masks }
        set { w1Fields.masks = newValue }
    }
    /// Another layer of the same list that limits where this one draws.
    public var matte: TrackMatte? {
        get { w1Fields.matte }
        set { w1Fields.matte = newValue }
    }
    /// Colour keyframes keyed "fill.<i>" or "stroke.<i>", `i` an index into
    /// `shapes`, or "text.<i>", `i` an index into `texts`; build keys with
    /// `colorTrackKey(fillOf:)`, `colorTrackKey(strokeOf:)` and `colorTrackKey(text:)`.
    public var colorTracks: [String: [ColorKeyframe]] {
        get { w1Fields.colorTracks }
        set { w1Fields.colorTracks = newValue }
    }
    /// Keyframed geometry, one track per animated shape.
    public var shapeTracks: [ShapeTrack] {
        get { w1Fields.shapeTracks }
        set { w1Fields.shapeTracks = newValue }
    }
    /// Another layer of the same list this one follows: its matrix is the parent's world matrix times its own.
    /// Opacity and visibility are not inherited. Nil (and missing in older files) means none.
    public var parentID: String? {
        get { w1Fields.parentID }
        set { w1Fields.parentID = newValue }
    }

    /// Every field but `id`, behind one copy-on-write reference, so copying a
    /// layer (and so a big scene's layer array, which every command and undo
    /// does) is two retains, not one per field.
    private var storage: LayerStorage
    /// `storage`'s fields for writing: the box is copied first unless this layer is its only owner.
    private var fields: LayerFields {
        get { storage.fields }
        _modify {
            if !isKnownUniquelyReferenced(&storage) { storage = LayerStorage(storage.fields) }
            yield &storage.fields
        }
    }
    /// False when masks, matte, colorTracks and shapeTracks are all empty: validation skips them.
    var hasW1Fields: Bool { storage.fields.w1 != nil }
    private var w1Fields: W1Fields {
        get {
            switch storage.fields.w1 {
            case .fields(let fields)?: fields
            case nil: W1Fields()
            }
        }
        set { fields.w1 = newValue.isEmpty ? nil : .fields(newValue) }
    }

    public init(
        id: String, name: String, shapes: [Shape] = [], tracks: [String: [Keyframe]] = [:],
        isVisible: Bool = true, isLocked: Bool = false, instances: [Instance] = [], texts: [TextShape] = [],
        masks: [LayerMask] = [], matte: TrackMatte? = nil, colorTracks: [String: [ColorKeyframe]] = [:],
        shapeTracks: [ShapeTrack] = [], parentID: String? = nil
    ) {
        self.id = id
        storage = LayerStorage(LayerFields(name: name, shapes: shapes, tracks: tracks, isVisible: isVisible,
                                           isLocked: isLocked, instances: instances, texts: texts))
        self.masks = masks
        self.matte = matte
        self.colorTracks = colorTracks
        self.shapeTracks = shapeTracks
        self.parentID = parentID
    }

    public static func == (a: Layer, b: Layer) -> Bool {
        a.id == b.id && (a.storage === b.storage || a.storage.fields == b.storage.fields)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(storage.fields)
    }

    /// The `tracks` key for the stroke width of `shapes[index]`.
    public static func trackKey(strokeWidthOf index: Int) -> String { "strokeWidth.\(index)" }
    /// The `colorTracks` key for the fill of `shapes[index]`.
    public static func colorTrackKey(fillOf index: Int) -> String { "fill.\(index)" }
    /// The `tracks` key for the trim start of `shapes[index]`'s stroke (a fraction, as `StrokeTrim.start`).
    public static func trackKey(trimStartOf index: Int) -> String { "trimStart.\(index)" }
    /// The `tracks` key for the trim end of `shapes[index]`'s stroke (a fraction, as `StrokeTrim.end`).
    public static func trackKey(trimEndOf index: Int) -> String { "trimEnd.\(index)" }
    /// The `tracks` key for the trim offset of `shapes[index]`'s stroke (in turns, as `StrokeTrim.offset`).
    public static func trackKey(trimOffsetOf index: Int) -> String { "trimOffset.\(index)" }
    /// The `colorTracks` key for the stroke of `shapes[index]`.
    public static func colorTrackKey(strokeOf index: Int) -> String { "stroke.\(index)" }
    /// The `colorTracks` key for the fill of `texts[index]`.
    public static func colorTrackKey(text index: Int) -> String { "text.\(index)" }

    private enum CodingKeys: String, CodingKey {
        case id, name, shapes, tracks, isVisible, isLocked, instances, texts, masks, matte, colorTracks, shapeTracks
        case parentID = "parent"
    }

    /// Files written before the flags existed decode as visible and unlocked,
    /// and files without instances or texts decode with none.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: c.decode(String.self, forKey: .id),
            name: c.decode(String.self, forKey: .name),
            shapes: c.decode([Shape].self, forKey: .shapes),
            tracks: c.decode([String: [Keyframe]].self, forKey: .tracks),
            isVisible: c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true,
            isLocked: c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false,
            instances: c.decodeIfPresent([Instance].self, forKey: .instances) ?? [],
            texts: c.decodeIfPresent([TextShape].self, forKey: .texts) ?? [],
            masks: c.decodeIfPresent([LayerMask].self, forKey: .masks) ?? [],
            matte: c.decodeIfPresent(TrackMatte.self, forKey: .matte),
            colorTracks: c.decodeIfPresent([String: [ColorKeyframe]].self, forKey: .colorTracks) ?? [:],
            shapeTracks: c.decodeIfPresent([ShapeTrack].self, forKey: .shapeTracks) ?? [],
            parentID: c.decodeIfPresent(String.self, forKey: .parentID)
        )
    }

    /// Empty texts, masks and tracks and a nil matte or parent are left out, so older layers encode as before.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(shapes, forKey: .shapes)
        try c.encode(tracks, forKey: .tracks)
        try c.encode(isVisible, forKey: .isVisible)
        try c.encode(isLocked, forKey: .isLocked)
        try c.encode(instances, forKey: .instances)
        if !texts.isEmpty { try c.encode(texts, forKey: .texts) }
        if !masks.isEmpty { try c.encode(masks, forKey: .masks) }
        try c.encodeIfPresent(matte, forKey: .matte)
        if !colorTracks.isEmpty { try c.encode(colorTracks, forKey: .colorTracks) }
        if !shapeTracks.isEmpty { try c.encode(shapeTracks, forKey: .shapeTracks) }
        try c.encodeIfPresent(parentID, forKey: .parentID)
    }

    /// Inserts or replaces the keyframe at `keyframe.frame`, keeping the track
    /// sorted. Returns the keyframe it replaced, if any.
    @discardableResult
    mutating func setKeyframe(_ keyframe: Keyframe, property: String) -> Keyframe? {
        var track = tracks[property] ?? []
        if let i = track.firstIndex(where: { $0.frame == keyframe.frame }) {
            let old = track[i]
            track[i] = keyframe
            tracks[property] = track
            return old
        }
        let insertAt = track.firstIndex(where: { $0.frame > keyframe.frame }) ?? track.count
        track.insert(keyframe, at: insertAt)
        tracks[property] = track
        return nil
    }

    /// Removes the keyframe at `frame`. Drops the track when it becomes empty.
    @discardableResult
    mutating func removeKeyframe(at frame: Int, property: String) -> Keyframe? {
        guard var track = tracks[property], let i = track.firstIndex(where: { $0.frame == frame }) else {
            return nil
        }
        let old = track.remove(at: i)
        tracks[property] = track.isEmpty ? nil : track
        return old
    }

    func keyframe(at frame: Int, property: String) -> Keyframe? {
        tracks[property]?.first(where: { $0.frame == frame })
    }
}

public struct Keyframe: Codable, Sendable, Hashable {
    public var frame: Int
    public var value: Double
    /// Easing applied from this keyframe to the next one.
    public var easing: Easing

    public init(frame: Int, value: Double, easing: Easing = .linear) {
        self.frame = frame
        self.value = value
        self.easing = easing
    }
}

public struct Point: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Both coordinates are finite, so the point can be saved.
    public var isFinite: Bool { x.isFinite && y.isFinite }
}

/// RGBA, each channel in 0...1.
public struct Color: Codable, Sendable, Hashable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// True if every channel is finite and in 0...1.
    public var isInRange: Bool { [r, g, b, a].allSatisfy { (0...1).contains($0) } }

    /// True if every channel is finite, so the color can be encoded and saved.
    public var isFinite: Bool { [r, g, b, a].allSatisfy(\.isFinite) }

    public static let black = Color(r: 0, g: 0, b: 0)
    public static let white = Color(r: 1, g: 1, b: 1)
}

/// Minimal vector shape: a polyline through `points`, optionally closed, with
/// a solid or gradient fill and an optional stroke. When `path` is set it wins
/// over `points` and `closed` (see `outline`).
public struct Shape: Codable, Sendable, Hashable {
    public var points: [Point]
    public var closed: Bool
    public var fill: Fill
    /// Curved geometry. Optional so v1 files without it still decode.
    public var path: Path?
    /// Outline style. Nil means no stroke; v1 files without it decode as nil.
    public var stroke: Stroke?

    public init(
        points: [Point], closed: Bool = true, fill: Fill = .solid(.black), path: Path? = nil, stroke: Stroke? = nil
    ) {
        self.points = points
        self.closed = closed
        self.fill = fill
        self.path = path
        self.stroke = stroke
    }
}

/// `string` set in `fontFamily` at `fontSize` points (finite, > 0), its baseline
/// origin at the finite `position`, painted with `fill`, restyled by `runs`, `paragraph` and `onPath`.
public struct TextShape: Codable, Sendable, Hashable {
    public var string: String
    public var fontFamily: String
    public var fontSize: Double
    public var position: Point
    public var fill: Fill
    /// Styles over grapheme ranges, sorted and not overlapping; graphemes outside every run keep the shape's style.
    public var runs: [TextRun] = []
    /// Line layout; nil means one unwrapped, leading-aligned line per paragraph.
    public var paragraph: ParagraphStyle?
    /// A path the text follows instead of a straight baseline at `position`; nil means none.
    public var onPath: TextOnPath?

    public init(
        string: String, fontFamily: String, fontSize: Double, position: Point, fill: Fill = .solid(.black),
        runs: [TextRun] = [], paragraph: ParagraphStyle? = nil, onPath: TextOnPath? = nil
    ) {
        self.string = string
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.position = position
        self.fill = fill
        self.runs = runs
        self.paragraph = paragraph
        self.onPath = onPath
    }

    private enum CodingKeys: String, CodingKey {
        case string, fontFamily, fontSize, position, fill, runs, paragraph, onPath
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        string = try c.decode(String.self, forKey: .string)
        fontFamily = try c.decode(String.self, forKey: .fontFamily)
        fontSize = try c.decode(Double.self, forKey: .fontSize)
        position = try c.decode(Point.self, forKey: .position)
        fill = try c.decode(Fill.self, forKey: .fill)
        runs = try c.decodeIfPresent([TextRun].self, forKey: .runs) ?? []
        paragraph = try c.decodeIfPresent(ParagraphStyle.self, forKey: .paragraph)
        onPath = try c.decodeIfPresent(TextOnPath.self, forKey: .onPath)
    }

    /// Empty runs and nil styles are left out, so plain text encodes as before.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(string, forKey: .string)
        try c.encode(fontFamily, forKey: .fontFamily)
        try c.encode(fontSize, forKey: .fontSize)
        try c.encode(position, forKey: .position)
        try c.encode(fill, forKey: .fill)
        if !runs.isEmpty { try c.encode(runs, forKey: .runs) }
        try c.encodeIfPresent(paragraph, forKey: .paragraph)
        try c.encodeIfPresent(onPath, forKey: .onPath)
    }

    /// Throws `ModelError.invalidText` or `invalidFill` if an invariant above breaks.
    func validate() throws {
        guard fontSize.isFinite, fontSize > 0 else { throw ModelError.invalidText("font size must be finite and > 0") }
        guard position.isFinite else { throw ModelError.invalidText("position not finite") }
        try fill.validate()
    }
}

/// How a shape's outline is drawn. `width` is in points, finite and >= 0, and
/// every color channel is finite. `dash` is empty (solid) or at most
/// `maxDashEntries` finite lengths >= 0 with a positive finite sum, `dashPhase`
/// is finite, and a `trim`'s start and end are in 0...1 with a finite offset
/// (all checked by `validate`, which the format layer runs on load). The stroke
/// paints `paintedPath`: the outline trimmed, then dashed.
public struct Stroke: Codable, Sendable, Hashable {
    public enum Join: String, Codable, Sendable, Hashable, CaseIterable {
        case miter, round, bevel
    }

    public enum Cap: String, Codable, Sendable, Hashable, CaseIterable {
        case butt, round, square
    }

    /// Most entries a dash pattern may hold (as `Path.dashed` allows).
    public static let maxDashEntries = 64

    public var color: Color
    public var width: Double
    public var join: Join
    public var cap: Cap
    /// Dash, gap, dash, ... lengths in points; an odd count repeats once (as
    /// SVG reads it). Empty draws a solid stroke. Old files decode as empty.
    public var dash: [Double]
    /// How far into the dash pattern the stroke starts, in points.
    public var dashPhase: Double
    /// The part of the outline the stroke draws; nil draws all of it.
    public var trim: StrokeTrim?

    public init(color: Color = .black, width: Double = 1, join: Join = .miter, cap: Cap = .butt,
                dash: [Double] = [], dashPhase: Double = 0, trim: StrokeTrim? = nil) {
        self.color = color
        self.width = width
        self.join = join
        self.cap = cap
        self.dash = dash
        self.dashPhase = dashPhase
        self.trim = trim
    }

    private enum CodingKeys: String, CodingKey { case color, width, join, cap, dash, dashPhase, trim }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = try c.decode(Color.self, forKey: .color)
        width = try c.decode(Double.self, forKey: .width)
        join = try c.decode(Join.self, forKey: .join)
        cap = try c.decode(Cap.self, forKey: .cap)
        dash = try c.decodeIfPresent([Double].self, forKey: .dash) ?? []
        dashPhase = try c.decodeIfPresent(Double.self, forKey: .dashPhase) ?? 0
        trim = try c.decodeIfPresent(StrokeTrim.self, forKey: .trim)
    }

    /// No dash, phase 0 and no trim are left out, so a plain stroke encodes as before.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(color, forKey: .color)
        try c.encode(width, forKey: .width)
        try c.encode(join, forKey: .join)
        try c.encode(cap, forKey: .cap)
        if !dash.isEmpty { try c.encode(dash, forKey: .dash) }
        if dashPhase != 0 { try c.encode(dashPhase, forKey: .dashPhase) }
        try c.encodeIfPresent(trim, forKey: .trim)
    }

    /// Throws `ModelError.invalidStroke` if an invariant above breaks.
    func validate() throws {
        guard width.isFinite, width >= 0 else { throw ModelError.invalidStroke("stroke width must be finite and >= 0") }
        guard color.isFinite else { throw ModelError.invalidStroke("color channels must be finite") }
        if !dash.isEmpty {
            let sum = dash.reduce(0, +)
            guard dash.count <= Self.maxDashEntries, dash.allSatisfy({ $0.isFinite && $0 >= 0 }), sum > 0, sum.isFinite else {
                throw ModelError.invalidStroke("dash must be at most \(Self.maxDashEntries) finite lengths >= 0 with a positive sum")
            }
        }
        guard dashPhase.isFinite else { throw ModelError.invalidStroke("dash phase must be finite") }
        if let trim {
            guard (0...1).contains(trim.start), (0...1).contains(trim.end), trim.offset.isFinite else {
                throw ModelError.invalidStroke("trim start and end must be in 0...1 and its offset finite")
            }
        }
    }
}

/// The part of a shape's outline its stroke draws, as `Path.trimmed` cuts it:
/// `start` and `end` are fractions of the length in 0...1, `offset` turns the
/// span along the path (1 is one full turn), and `mode` says whether the
/// fractions run over all contours together or each contour on its own.
public struct StrokeTrim: Codable, Sendable, Hashable {
    public var start: Double
    public var end: Double
    public var offset: Double
    public var mode: TrimMode

    public init(start: Double = 0, end: Double = 1, offset: Double = 0, mode: TrimMode = .together) {
        self.start = start
        self.end = end
        self.offset = offset
        self.mode = mode
    }

    /// Whether the trim keeps the whole outline (start 0, end 1, any offset).
    public var isWhole: Bool { start <= 0 && end >= 1 }
}

extension Document {
    func sceneIndex(_ id: String) throws -> Int {
        guard let i = scenes.firstIndex(where: { $0.id == id }) else {
            throw ModelError.sceneNotFound(id)
        }
        return i
    }

    func symbolIndex(_ id: String) throws -> Int {
        guard let i = symbols.firstIndex(where: { $0.id == id }) else {
            throw ModelError.symbolNotFound(id)
        }
        return i
    }

    /// The layer list of `owner`, or nil if it is missing.
    public func layers(of owner: LayerOwner) -> [Layer]? {
        switch owner {
        case .scene(let id): scenes.first { $0.id == id }?.layers
        case .symbol(let id): symbols.first { $0.id == id }?.layers
        }
    }

    /// Runs `body` on the layer list of `owner` in place. The one resolver:
    /// throws `sceneNotFound` or `symbolNotFound` if the owner is missing.
    @discardableResult
    mutating func withLayers<T>(_ owner: LayerOwner, _ body: (inout [Layer]) throws -> T) throws -> T {
        switch owner {
        case .scene(let id): return try body(&scenes[sceneIndex(id)].layers)
        case .symbol(let id): return try body(&symbols[symbolIndex(id)].layers)
        }
    }

    /// Runs `body` on the addressed layer in place, or throws if it is missing.
    @discardableResult
    mutating func withLayer<T>(_ owner: LayerOwner, layer: String, _ body: (inout Layer) throws -> T) throws -> T {
        try withLayers(owner) { layers in
            guard let l = layers.firstIndex(where: { $0.id == layer }) else {
                throw ModelError.layerNotFound(layer)
            }
            return try body(&layers[l])
        }
    }

    /// Like `withLayer`, but throws `layerLocked` if the layer is locked. Content
    /// edits (shapes, keyframes) use this in `execute`; `undo` uses `withLayer`
    /// so it always restores exactly.
    @discardableResult
    mutating func withEditableLayer<T>(_ owner: LayerOwner, layer: String, _ body: (inout Layer) throws -> T) throws -> T {
        try withLayer(owner, layer: layer) { l in
            guard !l.isLocked else { throw ModelError.layerLocked(l.id) }
            return try body(&l)
        }
    }
}
