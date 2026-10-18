// TrackCommands.swift: the family for commands that edit W1 colour and shape
// tracks, and the colour key commands (set, remove, move). Invariants: each
// colour command checks its params and the layer's lock before it changes
// anything, keeps a track's keys sorted by frame, one per frame and in
// 0...the owner's duration, drops a track left empty, and records the whole
// track it replaced so undo restores it exactly. A move is all or nothing.
// Stroke width keys need no command here: they use the existing Double tracks
// under "strokeWidth.<shape>" and the existing keyframe commands.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The colour and shape track commands, registered in `CommandRegistry.builtIn`.
public enum TrackCommands {
    /// Every colour and shape track command type, in registration order.
    public static let all: [any Command.Type] = [
        SetColorKeyframe.self, RemoveColorKeyframe.self, MoveColorKeyframes.self,
        SetShapeKeyframe.self, RemoveShapeKeyframe.self,
    ]

    /// What a stub command with id `id` throws until its feature builds it,
    /// e.g. "shapeKey.set is not built yet (animate-properties)".
    static func notBuilt(_ id: String) -> CommandError { .notBuilt("\(id) is not built yet (animate-properties)") }

    /// Replaces `target`'s colour track on the editable layer with what `edit`
    /// makes of it (given the track, empty if none, and the owner's duration);
    /// an empty result removes the track. Returns the track it replaced.
    /// A missing shape throws shapeNotFound, a missing text invalidIndex.
    static func editColorTrack(
        _ document: inout Document, _ owner: LayerOwner, _ layerID: String, _ target: TrackTarget,
        _ edit: ([ColorKeyframe], Int) throws -> [ColorKeyframe]
    ) throws -> [ColorKeyframe]? {
        let duration = switch owner {
        case .scene(let id): try document.scenes[document.sceneIndex(id)].durationFrames
        case .symbol(let id): try document.symbols[document.symbolIndex(id)].durationFrames
        }
        return try document.withEditableLayer(owner, layer: layerID) { layer in
            guard target.exists(in: layer) else {
                if case .text(let index) = target { throw CommandError.invalidIndex(index) }
                throw CommandError.shapeNotFound(target.index)
            }
            let old = layer.colorTracks[target.key]
            let new = try edit(old ?? [], duration)
            layer.colorTracks[target.key] = new.isEmpty ? nil : new
            return old
        }
    }

    /// Puts `track` back as `target`'s colour track (nil removes it): every colour undo.
    static func restoreColorTrack(
        _ document: inout Document, _ owner: LayerOwner, _ layerID: String, _ target: TrackTarget,
        _ track: [ColorKeyframe]?
    ) throws {
        try document.withLayer(owner, layer: layerID) { $0.colorTracks[target.key] = track }
    }
}

/// Colour tracks only: stroke width uses `Layer.trackKey(strokeWidthOf:)` and
/// paths use `shape:`. Which colour a colour track animates: a shape's fill or
/// stroke, or a text's fill. Its `key` is the track's key in `Layer.colorTracks`
/// (on `Layer.tracks` it finds nothing).
public enum TrackTarget: Hashable, Codable, Sendable {
    case fill(shape: Int)
    case stroke(shape: Int)
    case text(index: Int)

    /// "fill.<shape>", "stroke.<shape>" or "text.<index>".
    public var key: String {
        switch self {
        case .fill(let shape): Layer.colorTrackKey(fillOf: shape)
        case .stroke(let shape): Layer.colorTrackKey(strokeOf: shape)
        case .text(let index): Layer.colorTrackKey(text: index)
        }
    }

    /// The shape or text index this target colours.
    var index: Int {
        switch self {
        case .fill(let i), .stroke(let i), .text(let i): i
        }
    }

    /// Whether `layer` has the shape or text this target colours.
    func exists(in layer: Layer) -> Bool {
        switch self {
        case .fill, .stroke: layer.shapes.indices.contains(index)
        case .text: layer.texts.indices.contains(index)
        }
    }
}

/// Sets the colour key at `frame` on `target`'s track of `owner`'s layer,
/// adding it or replacing the key there. Throws invalidColor unless every
/// channel is in 0...1, invalidFrame outside 0...the owner's duration,
/// shapeNotFound(i) for a missing fill or stroke shape and invalidIndex(i) for
/// a missing text. Performed repeatedly with the same `coalesceKey`, steps on
/// one key (same owner, layer, target and frame) merge into one undo step.
public struct SetColorKeyframe: LayerParamsCommand {
    public static let id = "colorKey.set"
    public var label: String { "Set Color Keyframe" }
    public var owner: LayerOwner
    public var layerID: String
    public var target: TrackTarget
    public var frame: Int
    public var value: Color
    public var easing: Easing
    /// Undo state: the track before the first execute (nil: there was none).
    var previous: [ColorKeyframe]?
    var executed = false

    public init(owner: LayerOwner, layerID: String, target: TrackTarget, frame: Int, value: Color,
                easing: Easing = .linear) {
        (self.owner, self.layerID, self.target) = (owner, layerID, target)
        (self.frame, self.value, self.easing) = (frame, value, easing)
    }

    struct Params: Codable { var target: TrackTarget; var frame: Int; var value: Color; var easing: Easing }
    var params: Params { Params(target: target, frame: frame, value: value, easing: easing) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, target: params.target, frame: params.frame,
                  value: params.value, easing: params.easing)
    }

    public mutating func execute(_ document: inout Document) throws {
        guard value.isInRange else { throw CommandError.invalidColor(value) }
        let key = ColorKeyframe(frame: frame, value: value, easing: easing)
        previous = try TrackCommands.editColorTrack(&document, owner, layerID, target) { track, duration in
            guard key.frame >= 0, key.frame <= duration else { throw CommandError.invalidFrame(key.frame) }
            var track = track
            if let i = track.firstIndex(where: { $0.frame >= key.frame }) {
                if track[i].frame == key.frame { track[i] = key } else { track.insert(key, at: i) }
            } else {
                track.append(key)
            }
            return track
        }
        executed = true
    }

    public func undo(_ document: inout Document) throws {
        guard executed else { throw CommandError.notExecuted }
        try TrackCommands.restoreColorTrack(&document, owner, layerID, target, previous)
    }

    /// A step on the same key, performed with the same non-nil `coalesceKey`
    /// (`CommandEngine.perform(_:coalesceKey:)`): the merged command keeps the
    /// track from before the first step and takes the last step's value and
    /// easing, so one undo restores it. Another owner, layer, target or frame
    /// never merges.
    public mutating func merge(_ next: SetColorKeyframe) -> Bool {
        guard (next.owner, next.layerID, next.target, next.frame) == (owner, layerID, target, frame) else { return false }
        (value, easing) = (next.value, next.easing)
        return true
    }
}

/// Removes the colour key at `frame` from `target`'s track of `owner`'s
/// layer, and the track with its last key; throws keyframeNotFound if there
/// is no key there, shapeNotFound(i) for a missing fill or stroke shape and
/// invalidIndex(i) for a missing text.
public struct RemoveColorKeyframe: LayerParamsCommand {
    public static let id = "colorKey.remove"
    public var label: String { "Remove Color Keyframe" }
    public var owner: LayerOwner
    public var layerID: String
    public var target: TrackTarget
    public var frame: Int
    /// Undo state: the track before execute.
    var previous: [ColorKeyframe]?

    public init(owner: LayerOwner, layerID: String, target: TrackTarget, frame: Int) {
        (self.owner, self.layerID, self.target, self.frame) = (owner, layerID, target, frame)
    }

    struct Params: Codable { var target: TrackTarget; var frame: Int }
    var params: Params { Params(target: target, frame: frame) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, target: params.target, frame: params.frame)
    }

    public mutating func execute(_ document: inout Document) throws {
        let (frame, key) = (frame, target.key)
        previous = try TrackCommands.editColorTrack(&document, owner, layerID, target) { track, _ in
            guard let i = track.firstIndex(where: { $0.frame == frame }) else {
                throw CommandError.keyframeNotFound(property: key, frame: frame)
            }
            var track = track
            track.remove(at: i)
            return track
        }
    }

    public func undo(_ document: inout Document) throws {
        guard let previous else { throw CommandError.notExecuted }
        try TrackCommands.restoreColorTrack(&document, owner, layerID, target, previous)
    }
}

/// Shifts the colour keys at `frames` on `target`'s track of `owner`'s layer
/// by `by` frames, all or nothing: throws keyframeNotFound if a frame has no
/// key, invalidFrame(the key's frame) if a key would leave 0...the owner's
/// duration (the number names the key that could not move, not where it
/// would land), frameOccupied if one would land on a key that is not moving,
/// shapeNotFound(i) for a missing fill or stroke shape and invalidIndex(i) for
/// a missing text.
public struct MoveColorKeyframes: LayerParamsCommand {
    public static let id = "colorKey.move"
    public var label: String { "Move Color Keyframes" }
    public var owner: LayerOwner
    public var layerID: String
    public var target: TrackTarget
    public var frames: [Int]
    public var by: Int
    /// Undo state: the track before execute (nil: there was none, as when an
    /// empty `frames` moves nothing on a target with no track).
    var previous: [ColorKeyframe]?
    var executed = false

    public init(owner: LayerOwner, layerID: String, target: TrackTarget, frames: [Int], by: Int) {
        (self.owner, self.layerID, self.target, self.frames, self.by) = (owner, layerID, target, frames, by)
    }

    struct Params: Codable { var target: TrackTarget; var frames: [Int]; var by: Int }
    var params: Params { Params(target: target, frames: frames, by: by) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, target: params.target, frames: params.frames, by: params.by)
    }

    public mutating func execute(_ document: inout Document) throws {
        let (picked, by, key) = (Set(frames), by, target.key)
        previous = try TrackCommands.editColorTrack(&document, owner, layerID, target) { track, duration in
            if let missing = picked.subtracting(track.map(\.frame)).min() {
                throw CommandError.keyframeNotFound(property: key, frame: missing)
            }
            var kept: [ColorKeyframe] = [], moved: [ColorKeyframe] = []
            for var k in track {
                guard picked.contains(k.frame) else { kept.append(k); continue }
                let (to, overflow) = k.frame.addingReportingOverflow(by)
                guard !overflow, to >= 0, to <= duration else { throw CommandError.invalidFrame(k.frame) }
                k.frame = to
                moved.append(k)
            }
            let still = Set(kept.map(\.frame))
            if let clash = moved.first(where: { still.contains($0.frame) }) {
                throw CommandError.frameOccupied(property: key, frame: clash.frame)
            }
            return (kept + moved).sorted { $0.frame < $1.frame }
        }
        executed = true
    }

    public func undo(_ document: inout Document) throws {
        guard executed else { throw CommandError.notExecuted }
        try TrackCommands.restoreColorTrack(&document, owner, layerID, target, previous)
    }
}
