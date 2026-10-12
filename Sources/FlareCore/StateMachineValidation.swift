// StateMachineValidation.swift: the format layer's check of the state machine
// invariants listed at the top of StateMachine.swift. FlareFormat.validate
// calls validateStateMachines; it throws FormatError.invalid on the first
// broken rule.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension FlareFormat {
    /// Checks the invariants listed at the top of StateMachine.swift.
    static func validateStateMachines(_ document: Document) throws {
        var durations: [String: Int] = [:]
        for scene in document.scenes { durations[scene.id] = scene.durationFrames }
        var machineIDs = Set<String>()
        for machine in document.stateMachines {
            let m = machine.id
            guard machineIDs.insert(m).inserted else { throw FormatError.invalid("duplicate state machine id \(m)") }
            var stateIDs = Set<String>()
            for state in machine.states {
                guard stateIDs.insert(state.id).inserted else {
                    throw FormatError.invalid("state machine \(m): duplicate state id \(state.id)")
                }
                guard let duration = durations[state.sceneID] else {
                    throw FormatError.invalid("state machine \(m): state \(state.id) has unknown scene \(state.sceneID)")
                }
                guard state.startFrame >= 0, state.startFrame <= state.endFrame, state.endFrame <= duration else {
                    throw FormatError.invalid("state machine \(m): state \(state.id) frame range outside scene")
                }
            }
            guard stateIDs.contains(machine.initialState) else {
                throw FormatError.invalid("state machine \(m): unknown initial state \(machine.initialState)")
            }
            var inputs: [String: InputValue] = [:]
            for input in machine.inputs {
                guard inputs[input.name] == nil else {
                    throw FormatError.invalid("state machine \(m): duplicate input \(input.name)")
                }
                guard input.defaultValue.isFinite else {
                    throw FormatError.invalid("state machine \(m): input \(input.name) default is not finite")
                }
                inputs[input.name] = input.defaultValue
            }
            for t in machine.transitions {
                guard stateIDs.contains(t.from), stateIDs.contains(t.to) else {
                    throw FormatError.invalid("state machine \(m): transition \(t.from) -> \(t.to) names an unknown state")
                }
                for condition in t.conditions {
                    try validate(condition, inputs: inputs, machine: m)
                }
            }
        }
    }
}

extension FlareFormat {
    private static func validate(_ condition: Condition, inputs: [String: InputValue], machine m: String) throws {
        guard let declared = inputs[condition.input] else {
            throw FormatError.invalid("state machine \(m): condition names unknown input \(condition.input)")
        }
        guard declared.sameType(as: condition.value), condition.value.isFinite else {
            throw FormatError.invalid("state machine \(m): condition on \(condition.input) has the wrong value type")
        }
        if condition.op != .equal, case .bool = declared {
            throw FormatError.invalid("state machine \(m): condition compares bool input \(condition.input) with \(condition.op.rawValue)")
        }
    }
}
