// MachineStateCommands.swift: commands that add, update and remove the states
// of a state machine. Each follows the one rule set of StateMachineCommands:
// edit a copy of the machine, throw its first error issue as `invalidMachine`
// before touching the document, record what undo needs, encode params only.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension StateMachine {
    /// The position of state `id`, or `stateNotFound`.
    func stateIndex(_ id: String) throws -> Int {
        guard let j = states.firstIndex(where: { $0.id == id }) else { throw CommandError.stateNotFound(id) }
        return j
    }
}

/// Appends `state` to machine `machineID`. Throws `stateMachineNotFound`, or
/// `invalidMachine` when the state breaks a rule (a used id, an unknown
/// scene, a frame range outside the scene).
public struct AddMachineState: Command {
    public static let id = "machine.addState"
    public var label: String { "Add State" }
    public var machineID: String
    /// The new state; its id is unique within the machine.
    public var state: MachineState
    var old: StateMachine?
    var index: Int?

    private enum CodingKeys: String, CodingKey { case machineID, state }

    public init(machineID: String, state: MachineState) {
        self.machineID = machineID
        self.state = state
    }

    public mutating func execute(_ document: inout Document) throws {
        let state = state
        (old, index) = try document.editStateMachine(machineID) { $0.states.append(state) }
    }

    public func undo(_ document: inout Document) throws {
        try document.restoreStateMachine(old, at: index)
    }
}

/// Replaces the name, scene and frame range of the state of machine
/// `machineID` whose id is `state.id`. Throws `stateMachineNotFound`,
/// `stateNotFound`, or `invalidMachine` when the new values break a rule.
public struct UpdateMachineState: Command {
    public static let id = "machine.updateState"
    public var label: String { "Edit State" }
    public var machineID: String
    /// The state's new values; `state.id` picks the state to change.
    public var state: MachineState
    var old: StateMachine?
    var index: Int?

    private enum CodingKeys: String, CodingKey { case machineID, state }

    public init(machineID: String, state: MachineState) {
        self.machineID = machineID
        self.state = state
    }

    public mutating func execute(_ document: inout Document) throws {
        let state = state
        (old, index) = try document.editStateMachine(machineID) { machine in
            machine.states[try machine.stateIndex(state.id)] = state
        }
    }

    public func undo(_ document: inout Document) throws {
        try document.restoreStateMachine(old, at: index)
    }
}

/// Removes state `stateID` from machine `machineID`; undo puts it back at its
/// index. Throws `stateMachineNotFound`, `stateNotFound`, or `invalidMachine`
/// when the state is the initial state or a transition still names it.
public struct RemoveMachineState: Command {
    public static let id = "machine.removeState"
    public var label: String { "Delete State" }
    public var machineID: String
    public var stateID: String
    var removed: MachineState?
    var removedIndex: Int?

    private enum CodingKeys: String, CodingKey { case machineID, stateID }

    public init(machineID: String, stateID: String) {
        self.machineID = machineID
        self.stateID = stateID
    }

    public mutating func execute(_ document: inout Document) throws {
        let stateID = stateID
        var state: MachineState?
        var j: Int?
        _ = try document.editStateMachine(machineID) { machine in
            let k = try machine.stateIndex(stateID)
            state = machine.states.remove(at: k)
            j = k
        }
        (removed, removedIndex) = (state, j)
    }

    public func undo(_ document: inout Document) throws {
        guard let removed, let removedIndex else { throw CommandError.notExecuted }
        let i = try document.stateMachineIndex(machineID)
        guard (0...document.stateMachines[i].states.count).contains(removedIndex) else {
            throw CommandError.invalidIndex(removedIndex)
        }
        document.stateMachines[i].states.insert(removed, at: removedIndex)
    }
}
