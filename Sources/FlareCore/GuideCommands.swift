// GuideCommands.swift: commands that add, move and remove a scene's ruler
// guides. Guides are addressed by their index in `Scene.guides`; AddGuide
// appends. Positions must be finite. Each command records what it replaced in
// execute() so undo() restores the guide list exactly, order included. The
// MoveGuide steps of one drag merge, keeping the first old position.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The guide commands, registered in `CommandRegistry.builtIn`.
public enum GuideCommands {
    public static let all: [any Command.Type] = [AddGuide.self, MoveGuide.self, RemoveGuide.self]
}

/// Appends a guide on `axis` at `position`.
public struct AddGuide: Command {
    public static let id = "guide.add"
    public var label: String { "Add Guide" }
    public var sceneID: String
    public var axis: Guide.Axis
    public var position: Double
    var addedIndex: Int?

    private enum CodingKeys: String, CodingKey { case sceneID, axis, position }

    public init(sceneID: String, axis: Guide.Axis, position: Double) {
        self.sceneID = sceneID
        self.axis = axis
        self.position = position
    }

    public mutating func execute(_ document: inout Document) throws {
        guard position.isFinite else { throw CommandError.invalidGuidePosition }
        let s = try document.sceneIndex(sceneID)
        addedIndex = document.scenes[s].guides.count
        document.scenes[s].guides.append(Guide(axis: axis, position: position))
    }

    public func undo(_ document: inout Document) throws {
        guard let addedIndex else { throw CommandError.notExecuted }
        let s = try document.sceneIndex(sceneID)
        guard document.scenes[s].guides.indices.contains(addedIndex) else { throw CommandError.invalidIndex(addedIndex) }
        document.scenes[s].guides.remove(at: addedIndex)
    }
}

/// Moves the guide at `index` to `position`; its axis stays.
public struct MoveGuide: Command {
    public static let id = "guide.move"
    public var label: String { "Move Guide" }
    public var sceneID: String
    public var index: Int
    public var position: Double
    var oldPosition: Double?

    private enum CodingKeys: String, CodingKey { case sceneID, index, position }

    public init(sceneID: String, index: Int, position: Double) {
        self.sceneID = sceneID
        self.index = index
        self.position = position
    }

    public mutating func execute(_ document: inout Document) throws {
        guard position.isFinite else { throw CommandError.invalidGuidePosition }
        let s = try document.sceneIndex(sceneID)
        guard document.scenes[s].guides.indices.contains(index) else { throw CommandError.invalidIndex(index) }
        oldPosition = document.scenes[s].guides[index].position
        document.scenes[s].guides[index].position = position
    }

    public func undo(_ document: inout Document) throws {
        guard let oldPosition else { throw CommandError.notExecuted }
        let s = try document.sceneIndex(sceneID)
        guard document.scenes[s].guides.indices.contains(index) else { throw CommandError.invalidIndex(index) }
        document.scenes[s].guides[index].position = oldPosition
    }
}

extension MoveGuide {
    /// A drag step on the same guide: the merged command keeps the first
    /// recorded old position and takes `next.position`, so one undo puts the
    /// guide back where the drag began. Decides on params only.
    public mutating func merge(_ next: MoveGuide) -> Bool {
        guard (next.sceneID, next.index) == (sceneID, index) else { return false }
        position = next.position
        return true
    }
}

/// Removes the guide at `index`.
public struct RemoveGuide: Command {
    public static let id = "guide.remove"
    public var label: String { "Remove Guide" }
    public var sceneID: String
    public var index: Int
    var removed: Guide?

    private enum CodingKeys: String, CodingKey { case sceneID, index }

    public init(sceneID: String, index: Int) {
        self.sceneID = sceneID
        self.index = index
    }

    public mutating func execute(_ document: inout Document) throws {
        let s = try document.sceneIndex(sceneID)
        guard document.scenes[s].guides.indices.contains(index) else { throw CommandError.invalidIndex(index) }
        removed = document.scenes[s].guides.remove(at: index)
    }

    public func undo(_ document: inout Document) throws {
        guard let removed else { throw CommandError.notExecuted }
        let s = try document.sceneIndex(sceneID)
        guard index >= 0, index <= document.scenes[s].guides.count else { throw CommandError.invalidIndex(index) }
        document.scenes[s].guides.insert(removed, at: index)
    }
}
