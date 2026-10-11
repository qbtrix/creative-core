// StateMachine.swift: interactive state machines. A machine names states, each
// of which plays a frame range of one scene, and transitions between them that
// fire on a named trigger (an input such as "hover" or "click").
//
// Invariants (checked by FlareFormat.validate):
// - state machine ids are unique in a document; state ids are unique in a machine
// - every state's scene exists, and 0 <= startFrame <= endFrame <= durationFrames
// - initialState and every transition's from/to name a state of the same machine
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

    public init(
        id: String, name: String, states: [MachineState] = [], transitions: [Transition] = [],
        initialState: String
    ) {
        self.id = id
        self.name = name
        self.states = states
        self.transitions = transitions
        self.initialState = initialState
    }

    /// The state reached from `state` when `trigger` fires. The first transition
    /// in declaration order whose `from` and `trigger` match wins; if none
    /// matches, the machine stays in `state`.
    public func next(from state: String, trigger: String) -> String {
        transitions.first { $0.from == state && $0.trigger == trigger }?.to ?? state
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

/// Moves from state `from` to state `to` when `trigger` fires.
public struct Transition: Codable, Sendable, Hashable {
    public var from: String
    public var to: String
    public var trigger: String

    public init(from: String, to: String, trigger: String) {
        self.from = from
        self.to = to
        self.trigger = trigger
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
            for t in machine.transitions {
                guard stateIDs.contains(t.from), stateIDs.contains(t.to) else {
                    throw FormatError.invalid("state machine \(m): transition \(t.from) -> \(t.to) names an unknown state")
                }
            }
        }
    }
}
