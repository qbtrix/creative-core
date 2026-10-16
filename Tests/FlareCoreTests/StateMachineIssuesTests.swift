// StateMachineIssuesTests.swift: the non-throwing issues query. Validation
// messages are the ones recorded from dev before validateStateMachines moved
// onto issues(in:); an unreachable state is a warning that never blocks
// validate; issues carry their state id or transition index; and a seeded run
// of random machines gives the first message of the old throwing validator.
import FlareCore
import Foundation
import Testing

@Suite struct StateMachineIssuesTests {
    static func message(_ doc: Document) -> String? {
        do {
            try FlareFormat.validate(doc)
            return nil
        } catch FormatError.invalid(let text) {
            return text
        } catch {
            return "unexpected \(error)"
        }
    }

    /// Recorded from `FlareFormat.validate` on dev before the change.
    static let recorded: [String: String] = [
        "unknown scene": "state machine m: state hover has unknown scene nope",
        "unknown from": "state machine m: transition nope -> hover names an unknown state",
        "unknown to": "state machine m: transition hover -> nope names an unknown state",
        "unknown initialState": "state machine m: unknown initial state nope",
        "range past duration": "state machine m: state hover frame range outside scene",
        "negative start": "state machine m: state idle frame range outside scene",
        "start after end": "state machine m: state idle frame range outside scene",
        "duplicate state": "state machine m: duplicate state id idle",
        "unknown input": "state machine m: condition names unknown input nope",
        "bool compared with <": "state machine m: condition compares bool input enabled with <",
        "value type mismatch": "state machine m: condition on level has the wrong value type",
        "duplicate input": "state machine m: duplicate input level",
        "non-finite default": "state machine m: input level default is not finite",
    ]

    static func badDocument(_ kind: String) -> Document {
        switch kind {
        case "unknown input": return MachineInputTests.document([Condition(input: "nope", op: .equal, value: .bool(true))])
        case "bool compared with <":
            return MachineInputTests.document([Condition(input: "enabled", op: .less, value: .bool(true))])
        case "value type mismatch":
            return MachineInputTests.document([Condition(input: "level", op: .equal, value: .bool(true))])
        case "duplicate input":
            var doc = MachineInputTests.document([])
            doc.stateMachines[0].inputs.append(MachineInput(name: "level", defaultValue: .number(1)))
            return doc
        case "non-finite default":
            var doc = MachineInputTests.document([])
            doc.stateMachines[0].inputs[1].defaultValue = .number(.nan)
            return doc
        default:
            return StateMachineTests.document { m in
                switch kind {
                case "unknown scene": m.states[1].sceneID = "nope"
                case "unknown from": m.transitions[0].from = "nope"
                case "unknown to": m.transitions[1].to = "nope"
                case "unknown initialState": m.initialState = "nope"
                case "range past duration": m.states[1].endFrame = 25
                case "negative start": m.states[0].startFrame = -1
                case "start after end": m.states[0].startFrame = 11
                default: m.states[1].id = "idle"
                }
            }
        }
    }

    @Test(arguments: recorded.keys.sorted())
    func validateMessagesStayTheSame(_ kind: String) throws {
        let doc = Self.badDocument(kind)
        #expect(Self.message(doc) == Self.recorded[kind], "\(kind)")
        let first = doc.stateMachines[0].issues(in: doc).first { $0.severity == .error }
        #expect(first.map { "state machine m: \($0.message)" } == Self.recorded[kind], "\(kind)")
    }

    @Test func unreachableStateIsOneWarning() throws {
        var doc = StateMachineTests.document()
        doc.stateMachines[0].states.append(
            MachineState(id: "lost", name: "Lost", sceneID: "s", startFrame: 0, endFrame: 0))
        doc.stateMachines[0].transitions.append(Transition(from: "lost", to: "idle", trigger: "back"))
        let issues = doc.stateMachines[0].issues(in: doc)
        #expect(issues == [MachineIssue(severity: .warning, message: "lost can't be reached from idle", stateID: "lost")])
        try FlareFormat.validate(doc)
    }

    @Test func reachabilityFollowsEveryTriggerAndCondition() {
        var doc = MachineInputTests.document([Condition(input: "enabled", op: .equal, value: .bool(false))])
        doc.stateMachines[0].states.append(MachineState(id: "far", name: "Far", sceneID: "s", startFrame: 0, endFrame: 0))
        doc.stateMachines[0].transitions.append(Transition(from: "on", to: "far", trigger: "other"))
        #expect(doc.stateMachines[0].issues(in: doc).isEmpty)
    }

    @Test func unknownTargetCarriesTransitionIndex() {
        let doc = StateMachineTests.document { $0.transitions[1].to = "nope" }
        let issues = doc.stateMachines[0].issues(in: doc)
        #expect(issues.first == MachineIssue(
            severity: .error, message: "transition hover -> nope names an unknown state", transitionIndex: 1))
        let condition = MachineInputTests.document([Condition(input: "nope", op: .equal, value: .bool(true))])
        #expect(condition.stateMachines[0].issues(in: condition).first?.transitionIndex == 0)
    }

    @Test func stateErrorsCarryStateID() {
        let doc = StateMachineTests.document { $0.states[1].sceneID = "nope" }
        #expect(doc.stateMachines[0].issues(in: doc).first?.stateID == "hover")
    }

    /// A small random machine over ids and inputs that are sometimes wrong.
    static func randomMachine(_ id: String, _ rng: inout SplitMix64) -> StateMachine {
        func pick<T>(_ xs: [T]) -> T { xs[Int(rng.next() % UInt64(xs.count))] }
        let ids = ["a", "b", "c", "d"]
        let states = (0..<Int(rng.next() % 4)).map { _ in
            MachineState(id: pick(ids), name: "x", sceneID: pick(["s", "s", "s", "t"]),
                         startFrame: pick([-1, 0, 0, 3, 9]), endFrame: pick([0, 4, 10, 11]))
        }
        let inputs = (0..<Int(rng.next() % 3)).map { _ in
            MachineInput(name: pick(["p", "q"]), defaultValue: pick([.bool(true), .number(1), .number(1), .number(.infinity)]))
        }
        let transitions = (0..<Int(rng.next() % 4)).map { _ in
            Transition(from: pick(ids), to: pick(ids), trigger: pick(["t", "u"]),
                       conditions: (0..<Int(rng.next() % 2)).map { _ in
                           Condition(input: pick(["p", "q", "r"]), op: pick([.equal, .less, .greater]),
                                     value: pick([.bool(false), .number(2), .number(.nan)]))
                       })
        }
        return StateMachine(id: id, name: id, states: states, transitions: transitions,
                            initialState: pick(ids), inputs: inputs)
    }

    /// Machines that break two rules give the message of the rule checked first.
    static let multiFault: [(String, Document)] = {
        var range = MachineInputTests.document([])
        range.stateMachines[0].states[0].startFrame = -1
        range.stateMachines[0].inputs[1].defaultValue = .number(.nan)
        var initial = MachineInputTests.document([])
        initial.stateMachines[0].initialState = "nope"
        initial.stateMachines[0].inputs.append(MachineInput(name: "level", defaultValue: .number(1)))
        var nan = MachineInputTests.document([Condition(input: "nope", op: .equal, value: .bool(true))])
        nan.stateMachines[0].inputs[1].defaultValue = .number(.nan)
        return [
            ("state machine m: state idle frame range outside scene", range),
            ("state machine m: unknown initial state nope", initial),
            ("state machine m: input level default is not finite", nan),
        ]
    }()

    @Test func firstBrokenRuleWinsAcrossChecks() {
        for (expected, doc) in Self.multiFault { #expect(Self.message(doc) == expected) }
    }

    @Test func unknownInitialStateIsTheOnlyIssue() {
        let doc = StateMachineTests.document { $0.initialState = "nope" }
        #expect(doc.stateMachines[0].issues(in: doc) == [
            MachineIssue(severity: .error, message: "unknown initial state nope", stateID: "nope")])
    }

    @Test func unreachableSharedIDWarnsOnce() {
        var doc = StateMachineTests.document()
        for _ in 0..<2 {
            doc.stateMachines[0].states.append(MachineState(id: "lost", name: "Lost", sceneID: "s", startFrame: 0, endFrame: 0))
        }
        let warnings = doc.stateMachines[0].issues(in: doc).filter { $0.severity == .warning }
        #expect(warnings == [MachineIssue(severity: .warning, message: "lost can't be reached from idle", stateID: "lost")])
    }

    /// The throwing validator from before issues(in:) existed (69c9f80),
    /// kept here as an independent oracle for the order of the checks.
    static func oracle(_ machine: StateMachine, _ document: Document) -> String? {
        func finite(_ v: InputValue) -> Bool { if case .number(let n) = v { n.isFinite } else { true } }
        func sameType(_ a: InputValue, _ b: InputValue) -> Bool {
            switch (a, b) {
            case (.bool, .bool), (.number, .number): true
            default: false
            }
        }
        var durations: [String: Int] = [:]
        for scene in document.scenes { durations[scene.id] = scene.durationFrames }
        var stateIDs = Set<String>()
        for state in machine.states {
            guard stateIDs.insert(state.id).inserted else { return "duplicate state id \(state.id)" }
            guard let duration = durations[state.sceneID] else { return "state \(state.id) has unknown scene \(state.sceneID)" }
            guard state.startFrame >= 0, state.startFrame <= state.endFrame, state.endFrame <= duration else {
                return "state \(state.id) frame range outside scene"
            }
        }
        guard stateIDs.contains(machine.initialState) else { return "unknown initial state \(machine.initialState)" }
        var inputs: [String: InputValue] = [:]
        for input in machine.inputs {
            guard inputs[input.name] == nil else { return "duplicate input \(input.name)" }
            guard finite(input.defaultValue) else { return "input \(input.name) default is not finite" }
            inputs[input.name] = input.defaultValue
        }
        for t in machine.transitions {
            guard stateIDs.contains(t.from), stateIDs.contains(t.to) else {
                return "transition \(t.from) -> \(t.to) names an unknown state"
            }
            for c in t.conditions {
                guard let declared = inputs[c.input] else { return "condition names unknown input \(c.input)" }
                guard sameType(declared, c.value), finite(c.value) else { return "condition on \(c.input) has the wrong value type" }
                if c.op != .equal, case .bool = declared { return "condition compares bool input \(c.input) with \(c.op.rawValue)" }
            }
        }
        return nil
    }

    @Test func randomMachinesAgreeWithOldValidator() {
        var rng = SplitMix64(seed: 312)
        var errors = 0
        for _ in 0..<500 {
            let machines = (0..<Int(rng.next() % 2 + 1)).map { Self.randomMachine("m\($0)", &rng) }
            let doc = Document(scenes: [Scene(id: "s", name: "S", durationFrames: 10)], stateMachines: machines)
            let expected = machines.lazy.compactMap { m in Self.oracle(m, doc).map { "state machine \(m.id): \($0)" } }.first
            if expected != nil { errors += 1 }
            #expect(Self.message(doc) == expected)
        }
        #expect(errors > 50 && errors < 500)
    }
}
