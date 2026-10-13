// Document.swift: the Flare document model. A Document holds Scenes; a Scene
// holds Layers; a Layer holds vector Shapes and keyframe tracks keyed by
// property name ("x", "opacity", ...).
//
// Invariants (checked by the format layer on load, kept by commands):
// - every type here is a Codable, Sendable value type; no classes, no shared state
// - Scene.fps > 0, Scene.durationFrames >= 0
// - Scene.width and Scene.height are finite and > 0
// - Scene label frames are in 0...durationFrames
// - Scene guide positions are finite
// - layer ids are unique within a scene or symbol
// - symbol ids are unique, Symbol.durationFrames >= 0
// - every layer instance names a known symbol and has firstFrame >= 0
// - each track is sorted by frame, frames are unique and >= 0, and a track is
//   never stored empty (an empty track is removed, so undo restores equality)
// - keyframe values and shape points (including path points) are finite
// - text shapes have a finite font size > 0 and a finite position
// - swatch names are unique and swatch color channels are finite and in 0...1
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
    public var fps: Int
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
        guides: [Guide] = []
    ) {
        self.id = id
        self.name = name
        self.fps = fps
        self.durationFrames = durationFrames
        self.width = width
        self.height = height
        self.background = background
        self.layers = layers
        self.labels = labels
        self.guides = guides
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, fps, durationFrames, width, height, background, layers, labels, guides
    }

    /// Files written before the canvas fields, labels or guides existed decode with the defaults.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        fps = try c.decode(Int.self, forKey: .fps)
        durationFrames = try c.decode(Int.self, forKey: .durationFrames)
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? Scene.defaultWidth
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? Scene.defaultHeight
        background = try c.decodeIfPresent(Color.self, forKey: .background) ?? .white
        layers = try c.decode([Layer].self, forKey: .layers)
        labels = try c.decodeIfPresent([String: Int].self, forKey: .labels) ?? [:]
        guides = try c.decodeIfPresent([Guide].self, forKey: .guides) ?? []
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

public struct Layer: Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var shapes: [Shape]
    public var tracks: [String: [Keyframe]]
    /// Hidden layers are skipped when rendering; they stay editable.
    public var isVisible: Bool
    /// Locked layers reject commands that edit their shapes or keyframes.
    public var isLocked: Bool
    /// Symbol placements on this layer. Missing in older v1 files means empty.
    public var instances: [Instance]
    /// Text drawn above the shapes. Missing in older v1 files means empty.
    public var texts: [TextShape]

    public init(
        id: String, name: String, shapes: [Shape] = [], tracks: [String: [Keyframe]] = [:],
        isVisible: Bool = true, isLocked: Bool = false, instances: [Instance] = [], texts: [TextShape] = []
    ) {
        self.id = id
        self.name = name
        self.shapes = shapes
        self.tracks = tracks
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.instances = instances
        self.texts = texts
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, shapes, tracks, isVisible, isLocked, instances, texts
    }

    /// Files written before the flags existed decode as visible and unlocked,
    /// and files without instances or texts decode with none.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        shapes = try c.decode([Shape].self, forKey: .shapes)
        tracks = try c.decode([String: [Keyframe]].self, forKey: .tracks)
        isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        instances = try c.decodeIfPresent([Instance].self, forKey: .instances) ?? []
        texts = try c.decodeIfPresent([TextShape].self, forKey: .texts) ?? []
    }

    /// Empty texts are left out, so layers without text encode as before.
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
/// origin at the finite `position`, painted with `fill`.
public struct TextShape: Codable, Sendable, Hashable {
    public var string: String
    public var fontFamily: String
    public var fontSize: Double
    public var position: Point
    public var fill: Fill

    public init(string: String, fontFamily: String, fontSize: Double, position: Point, fill: Fill = .solid(.black)) {
        self.string = string
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.position = position
        self.fill = fill
    }

    /// Throws `ModelError.invalidText` or `invalidFill` if an invariant above breaks.
    func validate() throws {
        guard fontSize.isFinite, fontSize > 0 else { throw ModelError.invalidText("font size must be finite and > 0") }
        guard position.x.isFinite, position.y.isFinite else { throw ModelError.invalidText("position not finite") }
        try fill.validate()
    }
}

/// How a shape's outline is drawn. `width` is in points, finite and >= 0, and
/// every color channel is finite (checked by `validate`, which the format layer
/// runs on load).
public struct Stroke: Codable, Sendable, Hashable {
    public enum Join: String, Codable, Sendable, Hashable, CaseIterable {
        case miter, round, bevel
    }

    public enum Cap: String, Codable, Sendable, Hashable, CaseIterable {
        case butt, round, square
    }

    public var color: Color
    public var width: Double
    public var join: Join
    public var cap: Cap

    public init(color: Color = .black, width: Double = 1, join: Join = .miter, cap: Cap = .butt) {
        self.color = color
        self.width = width
        self.join = join
        self.cap = cap
    }

    /// Throws `ModelError.invalidStroke` if an invariant above breaks.
    func validate() throws {
        guard width.isFinite, width >= 0 else { throw ModelError.invalidStroke("stroke width must be finite and >= 0") }
        guard color.isFinite else { throw ModelError.invalidStroke("color channels must be finite") }
    }
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

    // Scene-only forms, kept until the keyframe family takes an owner (Q5c).
    @discardableResult
    mutating func withLayer<T>(scene: String, layer: String, _ body: (inout Layer) throws -> T) throws -> T {
        try withLayer(.scene(scene), layer: layer, body)
    }

    @discardableResult
    mutating func withEditableLayer<T>(scene: String, layer: String, _ body: (inout Layer) throws -> T) throws -> T {
        try withEditableLayer(.scene(scene), layer: layer, body)
    }
}
