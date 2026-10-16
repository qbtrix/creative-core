// StateMachine.swift: interactive state machines. A machine names states, each
// of which plays a frame range of one scene, and transitions between them that
// fire on a named trigger (an input such as "hover" or "click").
//
// Invariants (checked on load by StateMachineValidation.swift):
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
        return firing(from: state, trigger: trigger, inputs: current)?.to ?? state
    }

    /// The first-match rule `next` and `MachinePlayer` share: the first
    /// transition in declaration order whose `from` and `trigger` match and
    /// whose conditions all hold against `values` (no defaults merged), or nil.
    func firing(from state: String, trigger: String, inputs values: [String: InputValue]) -> Transition? {
        transitions.first { t in
            t.from == state && t.trigger == trigger && t.conditions.allSatisfy { $0.holds(values[$0.input]) }
        }
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
