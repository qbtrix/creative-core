// TransitionCommands.swift: commands that add, update and remove the
// transitions of a state machine. Each follows the one rule set of
// StateMachineCommands: edit a copy of the machine, throw its first error
// issue as `invalidMachine` before touching the document, record what undo
// needs (via `MachineEditRecord`), encode params only.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension StateMachine {
    /// Checks that `index` is a transition position, or throws `invalidIndex`.
    func requireTransitionIndex(_ index: Int) throws {
        guard transitions.indices.contains(index) else { throw CommandError.invalidIndex(index) }
    }
}

/// Inserts `transition` into machine `machineID` at `index` (nil appends;
/// out-of-range values are clamped). Throws `stateMachineNotFound`, or
/// `invalidMachine` when the transition breaks a rule (an unknown state, a
/// condition on an unknown input or of the wrong type).
public struct AddTransition: Command {
    public static let id = "machine.addTransition"
    public var label: String { "Add Transition" }
    /// The id of the state machine to edit.
    public var machineID: String
    /// The transition to insert; its states and inputs must exist.
    public var transition: Transition
    /// Insert position; nil appends. Out-of-range values are clamped.
    public var index: Int?
    var record = MachineEditRecord()

    private enum CodingKeys: String, CodingKey { case machineID, transition, index }

    public init(machineID: String, transition: Transition, index: Int? = nil) {
        self.machineID = machineID
        self.transition = transition
        self.index = index
    }

    public mutating func execute(_ document: inout Document) throws {
        let transition = transition, index = index
        try record.edit(&document, machineID) { machine in
            machine.transitions.insert(transition, at: machine.transitions.clampedInsertIndex(index))
        }
    }

    public func undo(_ document: inout Document) throws {
        try record.undo(&document)
    }
}

/// Replaces transition `index` of machine `machineID` with `transition`.
/// Throws `stateMachineNotFound`, `invalidIndex` for an index outside the
/// transitions, or `invalidMachine` when the new transition breaks a rule.
public struct UpdateTransition: Command {
    public static let id = "machine.updateTransition"
    public var label: String { "Edit Transition" }
    /// The id of the state machine to edit.
    public var machineID: String
    /// The position in `transitions`; must be in range, or `invalidIndex`.
    public var index: Int
    /// The transition's new values.
    public var transition: Transition
    var record = MachineEditRecord()

    private enum CodingKeys: String, CodingKey { case machineID, index, transition }

    public init(machineID: String, index: Int, transition: Transition) {
        self.machineID = machineID
        self.index = index
        self.transition = transition
    }

    public mutating func execute(_ document: inout Document) throws {
        let transition = transition, index = index
        try record.edit(&document, machineID) { machine in
            try machine.requireTransitionIndex(index)
            machine.transitions[index] = transition
        }
    }

    public func undo(_ document: inout Document) throws {
        try record.undo(&document)
    }
}

/// Removes transition `index` from machine `machineID`; undo puts the
/// machine back as it was, so the transition returns at its index. Throws
/// `stateMachineNotFound` or `invalidIndex`.
public struct RemoveTransition: Command {
    public static let id = "machine.removeTransition"
    public var label: String { "Delete Transition" }
    /// The id of the state machine to edit.
    public var machineID: String
    /// The position in `transitions`; must be in range, or `invalidIndex`.
    public var index: Int
    var record = MachineEditRecord()

    private enum CodingKeys: String, CodingKey { case machineID, index }

    public init(machineID: String, index: Int) {
        self.machineID = machineID
        self.index = index
    }

    public mutating func execute(_ document: inout Document) throws {
        let index = index
        try record.edit(&document, machineID) { machine in
            try machine.requireTransitionIndex(index)
            machine.transitions.remove(at: index)
        }
    }

    public func undo(_ document: inout Document) throws {
        try record.undo(&document)
    }
}
