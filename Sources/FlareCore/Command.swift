// Command.swift: the Command protocol and CommandEngine. Every document change
// goes through a Command: a named, Codable value with execute and undo. The
// engine owns the document and the undo/redo stacks.
//
// Invariants:
// - a command that throws leaves the document untouched (engine runs it on a copy)
// - a group is atomic: if its body throws, the document rolls back to the
//   state before the group and nothing is pushed
// - one undo-stack entry per perform() outside a group, one per outermost group
// - performing anything new clears the redo stack
// - consecutive top-level performs with the same non-nil coalesce key share one
//   entry; a different or nil key, an undo, a redo or a group ends coalescing
// - the undo stack holds at most maxUndoDepth entries; the oldest is dropped
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A document change. Stored properties are the command's params, so a
/// command encodes to JSON as-is (journals, scripting, replay).
///
/// `execute` may record what it needs for `undo` in its own properties, which
/// is why it is `mutating`. `undo` must restore the document exactly.
public protocol Command: Codable, Sendable {
    /// Stable machine name, e.g. "keyframe.move". Never reuse a retired id.
    static var id: String { get }
    /// Human name for menus, e.g. "Move Keyframe".
    var label: String { get }
    mutating func execute(_ document: inout Document) throws
    func undo(_ document: inout Document) throws
}

public enum CommandError: Error, Equatable, Sendable {
    case sceneNotFound(String)
    case layerNotFound(String)
    case duplicateID(String)
    case keyframeNotFound(property: String, frame: Int)
    case frameOccupied(property: String, frame: Int)
    case invalidFrame(Int)
    /// The scene has no frame label with this name.
    case labelNotFound(String)
    /// Scene fps must be > 0.
    case invalidFPS(Int)
    /// Scene duration must be >= 0 frames.
    case invalidDuration(Int)
    case shapeNotFound(Int)
    /// The layer is locked, so its shapes and keyframes cannot be edited.
    case layerLocked(String)
    case symbolNotFound(String)
    /// The symbol cannot be removed because an instance still uses it.
    case symbolInUse(String)
    /// An index outside the valid range, e.g. a layer position.
    case invalidIndex(Int)
    /// `undo` was called on a command that never executed.
    case notExecuted
    case nothingToUndo
    case nothingToRedo
    /// undo/redo was called from inside a group body.
    case groupInProgress
    /// No command with this id is registered.
    case unknownCommand(String)
    /// A command envelope or its params could not be decoded or encoded.
    case malformedCommand(String)
}

public struct CommandEngine: Sendable {
    /// One undoable step: a single command or a named group of them.
    struct Entry: Sendable {
        var label: String
        var commands: [any Command]
    }

    public private(set) var document: Document
    /// Most undo steps kept. When full, the oldest entry is dropped.
    public let maxUndoDepth: Int
    private var undoStack: [Entry] = []
    private var redoStack: [Entry] = []
    private var pending: Entry?
    /// Key of the last top-level perform, while it may still absorb more.
    private var coalesceKey: String?

    /// `maxUndoDepth` below 0 is treated as 0 (no undo history).
    public init(document: Document, maxUndoDepth: Int = 500) {
        self.document = document
        self.maxUndoDepth = max(0, maxUndoDepth)
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    /// "Undo Move Keyframe", or nil when there is nothing to undo.
    public var undoActionName: String? { undoStack.last.map { "Undo \($0.label)" } }
    public var redoActionName: String? { redoStack.last.map { "Redo \($0.label)" } }

    /// Runs `command` as one undo step. Consecutive calls with the same non-nil
    /// `coalesceKey` merge into a single step (a drag undoes in one go). Inside
    /// a group the key is ignored: the group is already one step.
    public mutating func perform(_ command: some Command, coalesceKey key: String? = nil) throws {
        var cmd: any Command = command
        var doc = document
        try cmd.execute(&doc)
        document = doc
        if pending != nil {
            pending?.commands.append(cmd)
        } else if let key, key == coalesceKey, let last = undoStack.indices.last {
            undoStack[last].commands.append(cmd)
            redoStack.removeAll()
        } else {
            push(Entry(label: cmd.label, commands: [cmd]))
            coalesceKey = key
        }
    }

    /// Runs `body` as one undo step named `label`. Nested groups fold into the
    /// outermost one. If `body` throws, every change it made is rolled back.
    public mutating func group(_ label: String, _ body: (inout CommandEngine) throws -> Void) throws {
        let outer = pending
        let before = document
        coalesceKey = nil
        pending = Entry(label: label, commands: [])
        do {
            try body(&self)
        } catch {
            document = before
            pending = outer
            throw error
        }
        let done = pending ?? Entry(label: label, commands: [])
        pending = outer
        guard !done.commands.isEmpty else { return }
        if pending != nil {
            pending?.commands += done.commands
        } else {
            push(done)
        }
    }

    public mutating func undo() throws {
        guard pending == nil else { throw CommandError.groupInProgress }
        guard let entry = undoStack.last else { throw CommandError.nothingToUndo }
        var doc = document
        for cmd in entry.commands.reversed() {
            try cmd.undo(&doc)
        }
        document = doc
        undoStack.removeLast()
        redoStack.append(entry)
        coalesceKey = nil
    }

    public mutating func redo() throws {
        guard pending == nil else { throw CommandError.groupInProgress }
        guard var entry = redoStack.last else { throw CommandError.nothingToRedo }
        var doc = document
        for i in entry.commands.indices {
            try entry.commands[i].execute(&doc)
        }
        document = doc
        redoStack.removeLast()
        undoStack.append(entry)
        coalesceKey = nil
    }

    private mutating func push(_ entry: Entry) {
        undoStack.append(entry)
        if undoStack.count > maxUndoDepth {
            undoStack.removeFirst(undoStack.count - maxUndoDepth)
        }
        redoStack.removeAll()
    }
}
