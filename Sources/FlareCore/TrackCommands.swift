// TrackCommands.swift: the family for commands that edit W1 colour and shape
// tracks, and the colour key commands. The colour commands are stubs today
// (animate-properties AP-1): they decode, encode and register, but execute
// and undo throw `CommandError.invalidDocument("not built: AP-3")` until AP-3
// gives them bodies. Their signatures are the packet's contract and do not
// change. Stroke width keys need no command here: they use the existing
// Double tracks under "strokeWidth.<shape>" and the existing keyframe commands.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The colour and shape track commands, registered in `CommandRegistry.builtIn`.
public enum TrackCommands {
    public static let all: [any Command.Type] = [
        SetColorKeyframe.self, RemoveColorKeyframe.self, MoveColorKeyframes.self,
        SetShapeKeyframe.self, RemoveShapeKeyframe.self,
    ]

    /// What a stub command throws until the task that builds it merges.
    static func notBuilt(_ task: String) -> CommandError { .invalidDocument("not built: \(task)") }
}

/// Which colour a colour track animates: a shape's fill or stroke, or a text's
/// fill. Its `key` is the track's key in `Layer.colorTracks`.
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
}

/// Sets the colour key at `frame` on `target`'s track of `owner`'s layer,
/// adding it or replacing the key there. A drag on one key merges into one
/// undo step. Stub: execute and undo throw "not built: AP-3".
public struct SetColorKeyframe: LayerParamsCommand {
    public static let id = "colorKey.set"
    public var label: String { "Set Color Keyframe" }
    public var owner: LayerOwner
    public var layerID: String
    public var target: TrackTarget
    public var frame: Int
    public var value: Color
    public var easing: Easing

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

    public mutating func execute(_ document: inout Document) throws { throw TrackCommands.notBuilt("AP-3") }
    public func undo(_ document: inout Document) throws { throw TrackCommands.notBuilt("AP-3") }
}

/// Removes the colour key at `frame` from `target`'s track of `owner`'s
/// layer. Stub: execute and undo throw "not built: AP-3".
public struct RemoveColorKeyframe: LayerParamsCommand {
    public static let id = "colorKey.remove"
    public var label: String { "Remove Color Keyframe" }
    public var owner: LayerOwner
    public var layerID: String
    public var target: TrackTarget
    public var frame: Int

    public init(owner: LayerOwner, layerID: String, target: TrackTarget, frame: Int) {
        (self.owner, self.layerID, self.target, self.frame) = (owner, layerID, target, frame)
    }

    struct Params: Codable { var target: TrackTarget; var frame: Int }
    var params: Params { Params(target: target, frame: frame) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, target: params.target, frame: params.frame)
    }

    public mutating func execute(_ document: inout Document) throws { throw TrackCommands.notBuilt("AP-3") }
    public func undo(_ document: inout Document) throws { throw TrackCommands.notBuilt("AP-3") }
}

/// Shifts the colour keys at `frames` on `target`'s track of `owner`'s layer
/// by `by` frames, all or nothing. Stub: execute and undo throw
/// "not built: AP-3".
public struct MoveColorKeyframes: LayerParamsCommand {
    public static let id = "colorKey.move"
    public var label: String { "Move Color Keyframes" }
    public var owner: LayerOwner
    public var layerID: String
    public var target: TrackTarget
    public var frames: [Int]
    public var by: Int

    public init(owner: LayerOwner, layerID: String, target: TrackTarget, frames: [Int], by: Int) {
        (self.owner, self.layerID, self.target, self.frames, self.by) = (owner, layerID, target, frames, by)
    }

    struct Params: Codable { var target: TrackTarget; var frames: [Int]; var by: Int }
    var params: Params { Params(target: target, frames: frames, by: by) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, target: params.target, frames: params.frames, by: params.by)
    }

    public mutating func execute(_ document: inout Document) throws { throw TrackCommands.notBuilt("AP-3") }
    public func undo(_ document: inout Document) throws { throw TrackCommands.notBuilt("AP-3") }
}
