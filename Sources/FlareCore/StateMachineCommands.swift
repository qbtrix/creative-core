// StateMachineCommands.swift: commands that add, rename and remove state
// machines and set a machine's initial state; params encoded, undo state not.
// One rule set: a command edits a copy of the machine, runs `issues(in:)` (the
// rules FlareFormat.validate checks) and throws the first error as
// `CommandError.invalidMachine` before it touches the document. Later machine
// commands reuse `editStateMachine` and `restoreStateMachine`.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The state machine commands, registered in `CommandRegistry.builtIn`.
public enum StateMachineCommands {
    public static let all: [any Command.Type] = [
        AddStateMachine.self, RenameStateMachine.self, RemoveStateMachine.self, SetInitialState.self,
    ]
}

extension StateMachine {
    /// Throws the first error issue of this machine as `invalidMachine`;
    /// warnings (an unreachable state) pass.
    func requireNoErrors(in document: Document) throws {
        if let issue = issues(in: document).first(where: { $0.severity == .error }) {
            throw CommandError.invalidMachine(issue)
        }
    }
}

extension Document {
    /// The position of state machine `id`, or `stateMachineNotFound`.
    func stateMachineIndex(_ id: String) throws -> Int {
        guard let i = stateMachines.firstIndex(where: { $0.id == id }) else {
            throw CommandError.stateMachineNotFound(id)
        }
        return i
    }

    /// Applies `edit` to a copy of machine `id`, checks the copy's rules and
    /// only then stores it. Returns the machine as it was and its index, which
    /// is what `restoreStateMachine` needs for undo.
    mutating func editStateMachine(_ id: String, _ edit: (inout StateMachine) throws -> Void) throws
        -> (old: StateMachine, index: Int) {
        let i = try stateMachineIndex(id)
        var machine = stateMachines[i]
        try edit(&machine)
        try machine.requireNoErrors(in: self)
        let old = stateMachines[i]
        stateMachines[i] = machine
        return (old, i)
    }

    /// Puts `old` back at `index`, undoing an `editStateMachine`. Throws
    /// `notExecuted` when nothing was recorded.
    mutating func restoreStateMachine(_ old: StateMachine?, at index: Int?) throws {
        guard let old, let index else { throw CommandError.notExecuted }
        guard stateMachines.indices.contains(index), stateMachines[index].id == old.id else {
            throw CommandError.stateMachineNotFound(old.id)
        }
        stateMachines[index] = old
    }
}

/// Appends a new state machine with one state, `firstState`, which becomes its
/// initial state. Throws `duplicateID` if a machine already has `id`,
/// `emptyName` for an empty name, and `invalidMachine` if `firstState` breaks
/// a rule (an unknown scene, a frame range outside it).
public struct AddStateMachine: Command {
    public static let id = "machine.add"
    public var label: String { "Add State Machine" }
    /// The new machine's id; unique among the document's machines.
    public var id: String
    /// The new machine's name; not empty.
    public var name: String
    /// The machine's only state, and its initial state.
    public var firstState: MachineState

    public init(id: String, name: String, firstState: MachineState) {
        self.id = id
        self.name = name
        self.firstState = firstState
    }

    public mutating func execute(_ document: inout Document) throws {
        guard !document.stateMachines.contains(where: { $0.id == id }) else { throw CommandError.duplicateID(id) }
        guard !name.isEmpty else { throw CommandError.emptyName }
        let machine = StateMachine(id: id, name: name, states: [firstState], initialState: firstState.id)
        try machine.requireNoErrors(in: document)
        document.stateMachines.append(machine)
    }

    public func undo(_ document: inout Document) throws {
        let i = try document.stateMachineIndex(id)
        document.stateMachines.remove(at: i)
    }
}

/// Renames state machine `machineID`. Throws `stateMachineNotFound` or
/// `emptyName`.
public struct RenameStateMachine: Command {
    public static let id = "machine.rename"
    public var label: String { "Rename State Machine" }
    public var machineID: String
    /// The new name; not empty.
    public var name: String
    var old: StateMachine?
    var index: Int?

    private enum CodingKeys: String, CodingKey { case machineID, name }

    public init(machineID: String, name: String) {
        self.machineID = machineID
        self.name = name
    }

    public mutating func execute(_ document: inout Document) throws {
        let name = name
        (old, index) = try document.editStateMachine(machineID) { machine in
            guard !name.isEmpty else { throw CommandError.emptyName }
            machine.name = name
        }
    }

    public func undo(_ document: inout Document) throws {
        try document.restoreStateMachine(old, at: index)
    }
}

/// Removes state machine `machineID`; undo puts it back at its index. Throws
/// `stateMachineNotFound`.
public struct RemoveStateMachine: Command {
    public static let id = "machine.remove"
    public var label: String { "Delete State Machine" }
    public var machineID: String
    var removed: StateMachine?
    var removedIndex: Int?

    private enum CodingKeys: String, CodingKey { case machineID }

    public init(machineID: String) {
        self.machineID = machineID
    }

    public mutating func execute(_ document: inout Document) throws {
        let i = try document.stateMachineIndex(machineID)
        removed = document.stateMachines.remove(at: i)
        removedIndex = i
    }

    public func undo(_ document: inout Document) throws {
        guard let removed, let removedIndex else { throw CommandError.notExecuted }
        guard (0...document.stateMachines.count).contains(removedIndex) else {
            throw CommandError.invalidIndex(removedIndex)
        }
        document.stateMachines.insert(removed, at: removedIndex)
    }
}

/// Makes `stateID` the initial state of machine `machineID`. Throws
/// `stateMachineNotFound`, or `invalidMachine` when no state has `stateID`.
public struct SetInitialState: Command {
    public static let id = "machine.setInitial"
    public var label: String { "Set Initial State" }
    public var machineID: String
    /// The state the machine starts in; one of its states.
    public var stateID: String
    var old: StateMachine?
    var index: Int?

    private enum CodingKeys: String, CodingKey { case machineID, stateID }

    public init(machineID: String, stateID: String) {
        self.machineID = machineID
        self.stateID = stateID
    }

    public mutating func execute(_ document: inout Document) throws {
        let stateID = stateID
        (old, index) = try document.editStateMachine(machineID) { $0.initialState = stateID }
    }

    public func undo(_ document: inout Document) throws {
        try document.restoreStateMachine(old, at: index)
    }
}
