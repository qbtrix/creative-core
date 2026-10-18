// TrackCommands+Shape.swift: the shape key commands, which key a shape's
// path for morphing. Stubs today (animate-properties AP-1): they decode,
// encode and register in `TrackCommands.all`, but execute and undo throw
// `CommandError.notBuilt("<id> is not built yet (animate-properties)")` until AP-4 gives them
// bodies, including the rule that makes a new key compatible with the track.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Sets the path key at `frame` on the shape track of `owner`'s layer's shape
/// `shape`, adding it or replacing the key there. The key is made compatible
/// with the track's other keys (same contours and anchor counts) without
/// changing how it draws. Stub: execute and undo throw `CommandError.notBuilt`.
public struct SetShapeKeyframe: LayerParamsCommand {
    public static let id = "shapeKey.set"
    public var label: String { "Set Shape Keyframe" }
    public var owner: LayerOwner
    public var layerID: String
    public var shape: Int
    public var frame: Int
    public var path: Path
    public var easing: Easing

    public init(owner: LayerOwner, layerID: String, shape: Int, frame: Int, path: Path, easing: Easing = .linear) {
        (self.owner, self.layerID, self.shape) = (owner, layerID, shape)
        (self.frame, self.path, self.easing) = (frame, path, easing)
    }

    struct Params: Codable { var shape: Int; var frame: Int; var path: Path; var easing: Easing }
    var params: Params { Params(shape: shape, frame: frame, path: path, easing: easing) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, shape: params.shape, frame: params.frame,
                  path: params.path, easing: params.easing)
    }

    public mutating func execute(_ document: inout Document) throws { throw TrackCommands.notBuilt(Self.id) }
    public func undo(_ document: inout Document) throws { throw TrackCommands.notBuilt(Self.id) }
}

/// Removes the path key at `frame` from the shape track of `owner`'s layer's
/// shape `shape`. Stub: execute and undo throw `CommandError.notBuilt`.
public struct RemoveShapeKeyframe: LayerParamsCommand {
    public static let id = "shapeKey.remove"
    public var label: String { "Remove Shape Keyframe" }
    public var owner: LayerOwner
    public var layerID: String
    public var shape: Int
    public var frame: Int

    public init(owner: LayerOwner, layerID: String, shape: Int, frame: Int) {
        (self.owner, self.layerID, self.shape, self.frame) = (owner, layerID, shape, frame)
    }

    struct Params: Codable { var shape: Int; var frame: Int }
    var params: Params { Params(shape: shape, frame: frame) }
    init(owner: LayerOwner, layerID: String, params: Params) {
        self.init(owner: owner, layerID: layerID, shape: params.shape, frame: params.frame)
    }

    public mutating func execute(_ document: inout Document) throws { throw TrackCommands.notBuilt(Self.id) }
    public func undo(_ document: inout Document) throws { throw TrackCommands.notBuilt(Self.id) }
}
