// StateMachineIssues.swift: evaluation layer. Every rule FlareFormat.validate
// checks on a state machine, as a list of issues instead of a throw, plus a
// warning per state the initial state can't reach. Reads the model, never
// changes it. The format layer and the machine commands share this one rule set.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// One broken rule (an error) or a likely mistake (a warning) in a state machine.
public struct MachineIssue: Sendable, Hashable {
    public enum Severity: String, Sendable, Hashable { case error, warning }
    public var severity: Severity
    /// The rule, worded as `FlareFormat.validate` words it after "state machine <id>: ".
    public var message: String
    /// The state the issue is about, when there is one.
    public var stateID: String?
    /// The index of the transition the issue is about, when there is one.
    public var transitionIndex: Int?

    public init(severity: Severity, message: String, stateID: String? = nil, transitionIndex: Int? = nil) {
        self.severity = severity
        self.message = message
        self.stateID = stateID
        self.transitionIndex = transitionIndex
    }
}

extension StateMachine {
    /// Every rule `FlareFormat.validate` checks on this machine, as errors in
    /// the order it checks them, then one warning per state the initial
    /// state can't reach (any trigger, any condition). Never throws.
    public func issues(in document: Document) -> [MachineIssue] {
        var out: [MachineIssue] = []
        func error(_ message: String, state: String? = nil, transition: Int? = nil) {
            out.append(MachineIssue(severity: .error, message: message, stateID: state, transitionIndex: transition))
        }
        var durations: [String: Int] = [:]
        for scene in document.scenes { durations[scene.id] = scene.durationFrames }
        var stateIDs = Set<String>()
        for state in states {
            if !stateIDs.insert(state.id).inserted { error("duplicate state id \(state.id)", state: state.id) }
            guard let duration = durations[state.sceneID] else {
                error("state \(state.id) has unknown scene \(state.sceneID)", state: state.id)
                continue
            }
            if !(state.startFrame >= 0 && state.startFrame <= state.endFrame && state.endFrame <= duration) {
                error("state \(state.id) frame range outside scene", state: state.id)
            }
        }
        let initialKnown = stateIDs.contains(initialState)
        if !initialKnown { error("unknown initial state \(initialState)", state: initialState) }
        var declared: [String: InputValue] = [:]
        for input in inputs {
            guard declared[input.name] == nil else {
                error("duplicate input \(input.name)")
                continue
            }
            if !input.defaultValue.isFinite { error("input \(input.name) default is not finite") }
            declared[input.name] = input.defaultValue
        }
        for (i, t) in transitions.enumerated() {
            if !(stateIDs.contains(t.from) && stateIDs.contains(t.to)) {
                error("transition \(t.from) -> \(t.to) names an unknown state", transition: i)
            }
            for c in t.conditions {
                guard let input = declared[c.input] else {
                    error("condition names unknown input \(c.input)", transition: i)
                    continue
                }
                if !(input.sameType(as: c.value) && c.value.isFinite) {
                    error("condition on \(c.input) has the wrong value type", transition: i)
                } else if c.op != .equal, case .bool = input {
                    error("condition compares bool input \(c.input) with \(c.op.rawValue)", transition: i)
                }
            }
        }
        guard initialKnown else { return out }
        let reached = reachable()
        var warned = Set<String>()
        for state in states where !reached.contains(state.id) && warned.insert(state.id).inserted {
            out.append(MachineIssue(
                severity: .warning, message: "\(state.id) can't be reached from \(initialState)", stateID: state.id))
        }
        return out
    }

    /// The ids reachable from the initial state over every transition,
    /// breadth-first. Linear in states plus transitions.
    private func reachable() -> Set<String> {
        var targets: [String: [String]] = [:]
        for t in transitions { targets[t.from, default: []].append(t.to) }
        var seen: Set<String> = [initialState]
        var queue = [initialState]
        var head = 0
        while head < queue.count {
            let id = queue[head]
            head += 1
            for to in targets[id] ?? [] where seen.insert(to).inserted { queue.append(to) }
        }
        return seen
    }
}
