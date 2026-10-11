// SceneCommands.swift: commands that add, remove and retime scenes. Same shape
// as Commands.swift: params first, undo state as optional vars last. Undo
// restores the document exactly, including scene order.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The scene commands, registered in `CommandRegistry.builtIn`.
public enum SceneCommands {
    public static let all: [any Command.Type] = [AddScene.self, RemoveScene.self, SetSceneTiming.self]
}

public struct AddScene: Command {
    public static let id = "scene.add"
    public var label: String { "Add Scene" }
    public var scene: Scene
    /// Insert position; nil appends. Out-of-range values are clamped.
    public var index: Int?

    public init(scene: Scene, index: Int? = nil) {
        self.scene = scene
        self.index = index
    }

    public mutating func execute(_ document: inout Document) throws {
        guard !document.scenes.contains(where: { $0.id == scene.id }) else {
            throw CommandError.duplicateID(scene.id)
        }
        guard scene.fps > 0 else { throw CommandError.invalidFPS(scene.fps) }
        guard scene.durationFrames >= 0 else { throw CommandError.invalidDuration(scene.durationFrames) }
        let count = document.scenes.count
        let at = min(max(index ?? count, 0), count)
        document.scenes.insert(scene, at: at)
    }

    public func undo(_ document: inout Document) throws {
        let i = try document.sceneIndex(scene.id)
        document.scenes.remove(at: i)
    }
}

public struct RemoveScene: Command {
    public static let id = "scene.remove"
    public var label: String { "Delete Scene" }
    public var sceneID: String
    var removed: Scene?
    var removedIndex: Int?

    public init(sceneID: String) {
        self.sceneID = sceneID
    }

    public mutating func execute(_ document: inout Document) throws {
        let i = try document.sceneIndex(sceneID)
        removed = document.scenes.remove(at: i)
        removedIndex = i
    }

    public func undo(_ document: inout Document) throws {
        guard let removed, let removedIndex else { throw CommandError.notExecuted }
        let at = min(max(removedIndex, 0), document.scenes.count)
        document.scenes.insert(removed, at: at)
    }
}

public struct SetSceneTiming: Command {
    public static let id = "scene.timing"
    public var label: String { "Set Scene Timing" }
    public var sceneID: String
    public var fps: Int
    public var durationFrames: Int
    var oldFPS: Int?
    var oldDurationFrames: Int?

    public init(sceneID: String, fps: Int, durationFrames: Int) {
        self.sceneID = sceneID
        self.fps = fps
        self.durationFrames = durationFrames
    }

    public mutating func execute(_ document: inout Document) throws {
        guard fps > 0 else { throw CommandError.invalidFPS(fps) }
        guard durationFrames >= 0 else { throw CommandError.invalidDuration(durationFrames) }
        let s = try document.sceneIndex(sceneID)
        oldFPS = document.scenes[s].fps
        oldDurationFrames = document.scenes[s].durationFrames
        document.scenes[s].fps = fps
        document.scenes[s].durationFrames = durationFrames
    }

    public func undo(_ document: inout Document) throws {
        guard let oldFPS, let oldDurationFrames else { throw CommandError.notExecuted }
        let s = try document.sceneIndex(sceneID)
        document.scenes[s].fps = oldFPS
        document.scenes[s].durationFrames = oldDurationFrames
    }
}
