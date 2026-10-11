// KeyframeCommands.swift: keyframe edits beyond set/move/remove. Each command
// validates its params, throws a CommandError instead of crashing, and records
// just enough in execute() for undo() to restore the document exactly.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The keyframe commands in this file, registered in `CommandRegistry.builtIn`.
public enum KeyframeCommands {
    public static let all: [any Command.Type] = [SetKeyframeEasing.self, ShiftKeyframes.self]
}

/// Changes the easing of the keyframe at `frame`; its frame and value stay.
public struct SetKeyframeEasing: Command {
    public static let id = "keyframe.setEasing"
    public var label: String { "Set Keyframe Easing" }
    public var sceneID: String
    public var layerID: String
    public var property: String
    public var frame: Int
    public var easing: Easing
    var oldEasing: Easing?

    public init(sceneID: String, layerID: String, property: String, frame: Int, easing: Easing) {
        self.sceneID = sceneID
        self.layerID = layerID
        self.property = property
        self.frame = frame
        self.easing = easing
    }

    public mutating func execute(_ document: inout Document) throws {
        oldEasing = try Self.replace(&document, sceneID, layerID, property, frame, easing)
    }

    public func undo(_ document: inout Document) throws {
        guard let oldEasing else { throw CommandError.notExecuted }
        try Self.replace(&document, sceneID, layerID, property, frame, oldEasing)
    }

    /// Sets the easing in place and returns the one it replaced.
    @discardableResult
    private static func replace(
        _ document: inout Document, _ scene: String, _ layer: String, _ p: String, _ frame: Int, _ easing: Easing
    ) throws -> Easing {
        try document.withLayer(scene: scene, layer: layer) { layer in
            guard var k = layer.keyframe(at: frame, property: p) else {
                throw CommandError.keyframeNotFound(property: p, frame: frame)
            }
            let old = k.easing
            k.easing = easing
            layer.setKeyframe(k, property: p)
            return old
        }
    }
}

/// Moves every keyframe in `fromFrame...toFrame` (inclusive), on every track of
/// the layer, by `delta` frames. An empty range (`fromFrame > toFrame`) moves
/// nothing. Throws if a result is negative or lands on a keyframe outside the
/// range on the same track.
public struct ShiftKeyframes: Command {
    public static let id = "keyframe.shift"
    public var label: String { "Shift Keyframes" }
    public var sceneID: String
    public var layerID: String
    public var fromFrame: Int
    public var toFrame: Int
    public var delta: Int
    var oldTracks: [String: [Keyframe]]?

    public init(sceneID: String, layerID: String, fromFrame: Int, toFrame: Int, delta: Int) {
        self.sceneID = sceneID
        self.layerID = layerID
        self.fromFrame = fromFrame
        self.toFrame = toFrame
        self.delta = delta
    }

    public mutating func execute(_ document: inout Document) throws {
        let (from, to, delta) = (fromFrame, toFrame, self.delta)
        oldTracks = try document.withLayer(scene: sceneID, layer: layerID) { layer in
            var shifted: [String: [Keyframe]] = [:]
            for (property, track) in layer.tracks {
                let outside = Set(track.filter { $0.frame < from || $0.frame > to }.map(\.frame))
                var newTrack: [Keyframe] = []
                newTrack.reserveCapacity(track.count)
                for var k in track {
                    if k.frame >= from && k.frame <= to {
                        let (moved, overflow) = k.frame.addingReportingOverflow(delta)
                        guard !overflow, moved >= 0 else { throw CommandError.invalidFrame(overflow ? k.frame : moved) }
                        guard !outside.contains(moved) else {
                            throw CommandError.frameOccupied(property: property, frame: moved)
                        }
                        k.frame = moved
                    }
                    newTrack.append(k)
                }
                newTrack.sort { $0.frame < $1.frame }
                shifted[property] = newTrack
            }
            let old = layer.tracks
            layer.tracks = shifted
            return old
        }
    }

    public func undo(_ document: inout Document) throws {
        guard let oldTracks else { throw CommandError.notExecuted }
        try document.withLayer(scene: sceneID, layer: layerID) { $0.tracks = oldTracks }
    }
}
