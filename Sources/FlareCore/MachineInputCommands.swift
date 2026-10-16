// MachineInputCommands.swift: commands that add, update and remove the inputs
// of a state machine. Each follows the one rule set of StateMachineCommands:
// edit a copy of the machine, throw its first error issue as `invalidMachine`
// before touching the document, record what undo needs (via
// `MachineEditRecord`), encode params only. Only the update's type rule
// (`inputTypeChange`) is a command rule with no format twin.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension StateMachine {
    /// The position of input `name`, or `inputNotFound`.
    func inputIndex(_ name: String) throws -> Int {
        guard let j = inputs.firstIndex(where: { $0.name == name }) else { throw CommandError.inputNotFound(name) }
        return j
    }
}

/// Appends `input` to machine `machineID`. Throws `stateMachineNotFound`, or
/// `invalidMachine` when the input breaks a rule (a used name, a default
/// that is not finite).
public struct AddMachineInput: Command {
    public static let id = "machine.addInput"
    public var label: String { "Add Input" }
    /// The id of the state machine to edit.
    public var machineID: String
    /// The new input; its name is unique within the machine.
    public var input: MachineInput
    var record = MachineEditRecord()

    private enum CodingKeys: String, CodingKey { case machineID, input }

    public init(machineID: String, input: MachineInput) {
        self.machineID = machineID
        self.input = input
    }

    public mutating func execute(_ document: inout Document) throws {
        let input = input
        try record.edit(&document, machineID) { $0.inputs.append(input) }
    }

    public func undo(_ document: inout Document) throws {
        try record.undo(&document)
    }
}

/// Sets the default of the input of machine `machineID` named `input.name`.
/// The input keeps its type. Throws `stateMachineNotFound`, `inputNotFound`,
/// `inputTypeChange` when the new default has another type, or
/// `invalidMachine` when it is not finite.
public struct UpdateMachineInput: Command {
    public static let id = "machine.updateInput"
    public var label: String { "Edit Input" }
    /// The id of the state machine to edit.
    public var machineID: String
    /// The input's new values; `input.name` picks the input to change.
    public var input: MachineInput
    var record = MachineEditRecord()

    private enum CodingKeys: String, CodingKey { case machineID, input }

    public mutating func execute(_ document: inout Document) throws {
        let input = input
        try record.edit(&document, machineID) { machine in
            let j = try machine.inputIndex(input.name)
            guard machine.inputs[j].defaultValue.sameType(as: input.defaultValue) else {
                throw CommandError.inputTypeChange(input.name)
            }
            machine.inputs[j] = input
        }
    }

    public func undo(_ document: inout Document) throws {
        try record.undo(&document)
    }

    public init(machineID: String, input: MachineInput) {
        self.machineID = machineID
        self.input = input
    }
}

/// Removes input `name` from machine `machineID`; undo puts the machine back
/// as it was, so the input returns at its index. Throws
/// `stateMachineNotFound`, `inputNotFound`, or `invalidMachine` naming the
/// first transition whose condition still uses the input (issue "condition
/// names unknown input <name>", with `transitionIndex` set).
public struct RemoveMachineInput: Command {
    public static let id = "machine.removeInput"
    public var label: String { "Delete Input" }
    /// The id of the state machine to edit.
    public var machineID: String
    /// The name of the input to remove; no condition may still use it.
    public var name: String
    var record = MachineEditRecord()

    private enum CodingKeys: String, CodingKey { case machineID, name }

    public mutating func execute(_ document: inout Document) throws {
        let name = name
        try record.edit(&document, machineID) { machine in
            machine.inputs.remove(at: try machine.inputIndex(name))
        }
    }

    public func undo(_ document: inout Document) throws {
        try record.undo(&document)
    }

    public init(machineID: String, name: String) {
        self.machineID = machineID
        self.name = name
    }
}
