// SceneCommands.swift: commands that add, remove, retime and resize scenes. Same shape
// as Commands.swift: params first, undo state as optional vars last. Undo
// restores the document exactly, including scene order.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The scene commands, registered in `CommandRegistry.builtIn`.
public enum SceneCommands {
    public static let all: [any Command.Type] = [
        AddScene.self, RemoveScene.self, SetSceneTiming.self, SetSceneCanvas.self,
    ]
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
        guard scene.background.isFinite else {
            throw CommandError.invalidDocument("background color channels must be finite")
        }
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

    private enum CodingKeys: String, CodingKey { case sceneID }

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

    private enum CodingKeys: String, CodingKey { case sceneID, fps, durationFrames }

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

/// Sets a scene's canvas size and background color. A bad size throws the
/// message `FlareFormat.validate` gives; every check runs before any change.
public struct SetSceneCanvas: Command {
    public static let id = "scene.setCanvas"
    public var label: String { "Set Scene Canvas" }
    public var sceneID: String
    public var width: Double
    public var height: Double
    public var background: Color
    var oldWidth: Double?
    var oldHeight: Double?
    var oldBackground: Color?

    private enum CodingKeys: String, CodingKey { case sceneID, width, height, background }

    public init(sceneID: String, width: Double, height: Double, background: Color) {
        self.sceneID = sceneID
        self.width = width
        self.height = height
        self.background = background
    }

    public mutating func execute(_ document: inout Document) throws {
        let s = try document.sceneIndex(sceneID)
        guard width.isFinite, width > 0, height.isFinite, height > 0 else {
            throw CommandError.invalidDocument("scene \(sceneID): canvas size must be finite and > 0")
        }
        guard background.isFinite else { throw CommandError.invalidDocument("background color channels must be finite") }
        oldWidth = document.scenes[s].width
        oldHeight = document.scenes[s].height
        oldBackground = document.scenes[s].background
        document.scenes[s].width = width
        document.scenes[s].height = height
        document.scenes[s].background = background
    }

    public func undo(_ document: inout Document) throws {
        guard let oldWidth, let oldHeight, let oldBackground else { throw CommandError.notExecuted }
        let s = try document.sceneIndex(sceneID)
        document.scenes[s].width = oldWidth
        document.scenes[s].height = oldHeight
        document.scenes[s].background = oldBackground
    }
}
