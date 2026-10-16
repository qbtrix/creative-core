// Command.swift: the Command protocol and CommandEngine. Every document change
// goes through a Command: a named, Codable value with execute and undo. The
// engine owns the document and the undo/redo stacks.
//
// Invariants:
// - a command that throws leaves the document untouched (engine runs it on a copy)
// - perform commits only a result that passes FlareFormat.validate; otherwise it
//   throws CommandError.invalidDocument and changes nothing. A LayerCommand gets
//   the same check scoped to its layer, so a drag on a big scene stays cheap
// - a group is atomic: if its body throws, the document rolls back to the
//   state before the group and nothing is pushed
// - perform, undo and redo throw CommandError, never ModelError (mapped here)
// - one undo-stack entry per perform() outside a group, one per outermost group
// - performing anything new clears the redo stack
// - consecutive top-level performs with the same non-nil coalesce key share one
//   entry; a different or nil key, an undo, a redo or a group ends coalescing.
//   Inside that entry a command first tries to merge into the last one, so a
//   drag holds one command, not one per step
// - the undo stack holds at most maxUndoDepth entries; the oldest is dropped
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A document change. Its encoded form holds only its params (journals,
/// scripting, replay), so a decoded command is always a fresh, unexecuted one.
///
/// `execute` may record what it needs for `undo` in its own properties, which
/// is why it is `mutating`. Those properties stay out of `CodingKeys`. `undo`
/// must restore the document exactly.
public protocol Command: Codable, Sendable {
    /// Stable machine name, e.g. "keyframe.move". Never reuse a retired id.
    static var id: String { get }
    /// Human name for menus, e.g. "Move Keyframe".
    var label: String { get }
    mutating func execute(_ document: inout Document) throws
    func undo(_ document: inout Document) throws
    /// Folds `next`, which has just executed on the document this command left,
    /// into this executed command, so that undo and redo of the result equal
    /// undo and redo of both. Returns false, changing nothing, when they don't
    /// merge. Used for coalesced steps; the default never merges.
    mutating func merge(_ next: Self) -> Bool
}

extension Command {
    public mutating func merge(_ next: Self) -> Bool { false }
}

/// A command whose `execute` changes one layer of one scene or symbol and
/// nothing else: it edits, inserts, removes or moves that layer. CommandEngine
/// then checks only that layer, plus the document-wide rules that do not scan
/// layers.
public protocol LayerCommand: Command {
    /// The scene or symbol whose layer list holds the layer.
    var owner: LayerOwner { get }
    /// The one layer `execute` may change.
    var layerID: String { get }
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
    /// A guide position that is NaN or infinite.
    case invalidGuidePosition
    /// An instance transform with a NaN or infinite component.
    case invalidTransform
    /// The document palette has no swatch with this name.
    case swatchNotFound(String)
    /// A swatch name is empty; swatch names are the palette's keys.
    case emptySwatchName
    /// A name is empty where one is required, e.g. a scene name.
    case emptyName
    /// The document has no state machine with this id.
    case stateMachineNotFound(String)
    /// The edit would break a state machine rule; the issue names the rule and
    /// the state or transition it is about (see `StateMachine.issues(in:)`).
    /// Its `message` keeps the file format's wording, so it describes the
    /// machine as the edit would leave it: removing initial state idle reads
    /// "unknown initial state idle", removing input down reads "condition
    /// names unknown input down". To tell the user what to fix, word the
    /// refusal from `issue.stateID` and `issue.transitionIndex` instead, e.g.
    /// "idle is the initial state" or "transition 2 still uses hover". An
    /// issue about an input (a duplicate name, a non-finite default) has both
    /// nil and names the input only in `message`, so for AddMachineInput and
    /// UpdateMachineInput word the refusal from the input you sent.
    case invalidMachine(MachineIssue)
    /// The state machine has no state with this id (UpdateMachineState,
    /// RemoveMachineState).
    case stateNotFound(String)
    /// The state machine has no input with this name (UpdateMachineInput,
    /// RemoveMachineInput).
    case inputNotFound(String)
    /// An update would give the input with this name another type
    /// (UpdateMachineInput); an input keeps the type of its default.
    case inputTypeChange(String)
    /// A color channel is not finite or not in 0...1.
    case invalidColor(Color)
    /// An index outside the valid range. The number is one of: a layer
    /// position (ReorderLayer), a scene position (ReorderScene), an instance
    /// index within a layer (RemoveInstance, SetInstanceTransform,
    /// SetInstancePlayback, and RemoveInstance undo), a guide index
    /// (MoveGuide, RemoveGuide, AddGuide undo), a swatch position
    /// (RemoveSwatch undo), a transition index (UpdateTransition,
    /// RemoveTransition), a state machine position (RemoveStateMachine undo),
    /// or 0 for an empty layer list (ConvertToSymbol). A shape index missing
    /// from a layer throws `shapeNotFound` instead.
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
    /// The command would leave a document that fails `FlareFormat.validate`.
    case invalidDocument(String)
}

extension CommandError {
    /// The command-layer form of a model error, so engine callers see only
    /// CommandError.
    init(_ error: ModelError) {
        switch error {
        case .sceneNotFound(let id): self = .sceneNotFound(id)
        case .symbolNotFound(let id): self = .symbolNotFound(id)
        case .layerNotFound(let id): self = .layerNotFound(id)
        case .layerLocked(let id): self = .layerLocked(id)
        case .invalidFill(let message), .invalidText(let message), .invalidStroke(let message): self = .invalidDocument(message)
        }
    }
}

/// Runs `body`, rethrowing a ModelError as the matching CommandError.
private func mappingModelErrors(_ body: () throws -> Void) throws {
    do { try body() } catch let error as ModelError { throw CommandError(error) }
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
    private(set) var undoStack: [Entry] = []
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
        try mappingModelErrors { try cmd.execute(&doc) }
        do {
            if let scoped = cmd as? any LayerCommand {
                try FlareFormat.validate(doc, layer: scoped.layerID, owner: scoped.owner, since: document)
            } else {
                try FlareFormat.validate(doc)
            }
        } catch {
            throw CommandError.invalidDocument("\(cmd.label): \(error)")
        }
        document = doc
        if pending != nil {
            pending?.commands.append(cmd)
        } else if let key, key == coalesceKey, let last = undoStack.indices.last {
            if let i = undoStack[last].commands.indices.last,
               let merged = undoStack[last].commands[i].merged(with: cmd) {
                undoStack[last].commands[i] = merged
            } else {
                undoStack[last].commands.append(cmd)
            }
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
            try mappingModelErrors { try cmd.undo(&doc) }
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
            try mappingModelErrors { try entry.commands[i].execute(&doc) }
        }
        document = doc
        redoStack.removeLast()
        undoStack.append(entry)
        coalesceKey = nil
    }

    /// `last` with `next` merged into it, or nil when `next` is another type or
    /// `last.merge` declines.
    private mutating func push(_ entry: Entry) {
        undoStack.append(entry)
        if undoStack.count > maxUndoDepth {
            undoStack.removeFirst(undoStack.count - maxUndoDepth)
        }
        redoStack.removeAll()
    }
}

extension Command {
    /// `self` with `next` folded in, or nil if `next` is another type or
    /// refuses to merge. A method so the existential opens on any Swift 6.
    fileprivate func merged(with next: any Command) -> (any Command)? {
        guard let next = next as? Self else { return nil }
        var last = self
        return last.merge(next) ? last : nil
    }
}
