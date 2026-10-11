// Document.swift: the Flare document model. A Document holds Scenes; a Scene
// holds Layers; a Layer holds vector Shapes and keyframe tracks keyed by
// property name ("x", "opacity", ...).
//
// Invariants (checked by FlareFormat.validate on load, kept by commands):
// - every type here is a Codable, Sendable value type; no classes, no shared state
// - Scene.fps > 0, Scene.durationFrames >= 0
// - layer ids are unique within a scene
// - each track is sorted by frame, frames are unique and >= 0, and a track is
//   never stored empty (an empty track is removed, so undo restores equality)
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public struct Document: Codable, Sendable, Hashable {
    public var scenes: [Scene]

    public init(scenes: [Scene] = []) {
        self.scenes = scenes
    }
}

public struct Scene: Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var fps: Int
    public var durationFrames: Int
    public var layers: [Layer]

    public init(id: String, name: String, fps: Int = 24, durationFrames: Int = 48, layers: [Layer] = []) {
        self.id = id
        self.name = name
        self.fps = fps
        self.durationFrames = durationFrames
        self.layers = layers
    }
}

public struct Layer: Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var shapes: [Shape]
    public var tracks: [String: [Keyframe]]

    public init(id: String, name: String, shapes: [Shape] = [], tracks: [String: [Keyframe]] = [:]) {
        self.id = id
        self.name = name
        self.shapes = shapes
        self.tracks = tracks
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

    public static let black = Color(r: 0, g: 0, b: 0)
}

/// Minimal vector shape: a polyline through `points`, optionally closed, with
/// a solid fill. Curves, strokes and gradients come later (see docs/gaps.md).
public struct Shape: Codable, Sendable, Hashable {
    public var points: [Point]
    public var closed: Bool
    public var fill: Color

    public init(points: [Point], closed: Bool = true, fill: Color = .black) {
        self.points = points
        self.closed = closed
        self.fill = fill
    }
}

extension Document {
    func sceneIndex(_ id: String) throws -> Int {
        guard let i = scenes.firstIndex(where: { $0.id == id }) else {
            throw CommandError.sceneNotFound(id)
        }
        return i
    }

    /// Runs `body` on the addressed layer in place, or throws if it is missing.
    @discardableResult
    mutating func withLayer<T>(scene: String, layer: String, _ body: (inout Layer) throws -> T) throws -> T {
        let s = try sceneIndex(scene)
        guard let l = scenes[s].layers.firstIndex(where: { $0.id == layer }) else {
            throw CommandError.layerNotFound(layer)
        }
        return try body(&scenes[s].layers[l])
    }
}
