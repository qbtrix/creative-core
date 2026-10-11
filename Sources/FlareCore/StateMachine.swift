// StateMachine.swift: interactive state machines. A machine names states, each
// of which plays a frame range of one scene, and transitions between them that
// fire on a named trigger (an input such as "hover" or "click").
//
// Invariants (checked by FlareFormat.validate):
// - state machine ids are unique in a document; state ids are unique in a machine
// - every state's scene exists, and 0 <= startFrame <= endFrame <= durationFrames
// - initialState and every transition's from/to name a state of the same machine
// - input names are unique in a machine; every condition names a declared input,
//   its value has the input's type, and `<`/`>` compare number inputs only
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public struct StateMachine: Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var states: [MachineState]
    public var transitions: [Transition]
    public var initialState: String
    /// Declared inputs. Empty in files written before inputs existed.
    public var inputs: [MachineInput]

    public init(
        id: String, name: String, states: [MachineState] = [], transitions: [Transition] = [],
        initialState: String, inputs: [MachineInput] = []
    ) {
        self.id = id
        self.name = name
        self.states = states
        self.transitions = transitions
        self.initialState = initialState
        self.inputs = inputs
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, states, transitions, initialState, inputs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        states = try c.decode([MachineState].self, forKey: .states)
        transitions = try c.decode([Transition].self, forKey: .transitions)
        initialState = try c.decode(String.self, forKey: .initialState)
        inputs = try c.decodeIfPresent([MachineInput].self, forKey: .inputs) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(states, forKey: .states)
        try c.encode(transitions, forKey: .transitions)
        try c.encode(initialState, forKey: .initialState)
        if !inputs.isEmpty { try c.encode(inputs, forKey: .inputs) }
    }

    /// The state reached from `state` when `trigger` fires. The first transition
    /// in declaration order whose `from` and `trigger` match and whose conditions
    /// all hold wins; if none matches, the machine stays in `state`. `values`
    /// gives current input values; a missing input uses its declared default.
    public func next(from state: String, trigger: String, inputs values: [String: InputValue] = [:]) -> String {
        var current: [String: InputValue] = [:]
        for input in inputs where current[input.name] == nil { current[input.name] = input.defaultValue }
        for (name, value) in values { current[name] = value }
        return transitions.first { t in
            t.from == state && t.trigger == trigger && t.conditions.allSatisfy { $0.holds(current[$0.input]) }
        }?.to ?? state
    }
}

/// One state: plays frames `startFrame...endFrame` of scene `sceneID`.
public struct MachineState: Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var sceneID: String
    public var startFrame: Int
    public var endFrame: Int

    public init(id: String, name: String, sceneID: String, startFrame: Int, endFrame: Int) {
        self.id = id
        self.name = name
        self.sceneID = sceneID
        self.startFrame = startFrame
        self.endFrame = endFrame
    }
}

/// Moves from state `from` to state `to` when `trigger` fires and every
/// condition holds.
public struct Transition: Codable, Sendable, Hashable {
    public var from: String
    public var to: String
    public var trigger: String
    public var conditions: [Condition]

    public init(from: String, to: String, trigger: String, conditions: [Condition] = []) {
        self.from = from
        self.to = to
        self.trigger = trigger
        self.conditions = conditions
    }

    private enum CodingKeys: String, CodingKey { case from, to, trigger, conditions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        from = try c.decode(String.self, forKey: .from)
        to = try c.decode(String.self, forKey: .to)
        trigger = try c.decode(String.self, forKey: .trigger)
        conditions = try c.decodeIfPresent([Condition].self, forKey: .conditions) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(from, forKey: .from)
        try c.encode(to, forKey: .to)
        try c.encode(trigger, forKey: .trigger)
        if !conditions.isEmpty { try c.encode(conditions, forKey: .conditions) }
    }
}

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
