// LabelCommands.swift: commands that name scene frames. A label maps a name to
// a frame in 0...durationFrames. Each command records the scene's old labels
// in execute() so undo() restores them exactly.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The frame label commands, registered in `CommandRegistry.builtIn`.
public enum LabelCommands {
    public static let all: [any Command.Type] = [SetFrameLabel.self, RemoveFrameLabel.self]
}

/// Adds the label `name` at `frame`, or moves it there if it already exists.
public struct SetFrameLabel: Command {
    public static let id = "label.set"
    public var label: String { "Set Frame Label" }
    public var sceneID: String
    public var name: String
    public var frame: Int
    var oldLabels: [String: Int]?

    public init(sceneID: String, name: String, frame: Int) {
        self.sceneID = sceneID
        self.name = name
        self.frame = frame
    }

    public mutating func execute(_ document: inout Document) throws {
        let s = try document.sceneIndex(sceneID)
        guard frame >= 0, frame <= document.scenes[s].durationFrames else { throw CommandError.invalidFrame(frame) }
        oldLabels = document.scenes[s].labels
        document.scenes[s].labels[name] = frame
    }

    public func undo(_ document: inout Document) throws {
        guard let oldLabels else { throw CommandError.notExecuted }
        let s = try document.sceneIndex(sceneID)
        document.scenes[s].labels = oldLabels
    }
}

/// Removes the label `name`; throws `labelNotFound` if the scene has none.
public struct RemoveFrameLabel: Command {
    public static let id = "label.remove"
    public var label: String { "Remove Frame Label" }
    public var sceneID: String
    public var name: String
    var oldLabels: [String: Int]?

    public init(sceneID: String, name: String) {
        self.sceneID = sceneID
        self.name = name
    }

    public mutating func execute(_ document: inout Document) throws {
        let s = try document.sceneIndex(sceneID)
        guard document.scenes[s].labels[name] != nil else { throw CommandError.labelNotFound(name) }
        oldLabels = document.scenes[s].labels
        document.scenes[s].labels[name] = nil
    }

    public func undo(_ document: inout Document) throws {
        guard let oldLabels else { throw CommandError.notExecuted }
        let s = try document.sceneIndex(sceneID)
        document.scenes[s].labels = oldLabels
    }
}
