// MachinePlayerTests.swift: playing a state machine. A script of advances and
// triggers gives the same literal trace on every run, a fired transition
// restarts its target, frames never leave the state's range (even near
// Int.max), bad inputs are refused, and bad machines throw.
import FlareCore
import Testing

@Suite struct MachinePlayerTests {
    static func trace(_ player: inout MachinePlayer) -> [String] {
        var out: [String] = []
        func note() { out.append("\(player.stateID) \(player.frame)") }
        player.advance(frames: 5); note()
        player.fire("pointerEnter"); note()
        player.advance(frames: 20); note()
        player.fire("pointerExit"); note()
        player.advance(frames: 3); note()
        return out
    }

    @Test func scriptGivesLiteralTraceOnEveryPlayer() throws {
        let doc = StateMachineTests.document()
        var first = try MachinePlayer(machineID: "m", in: doc)
        #expect(first.stateID == "idle" && first.frame == 0 && first.inputs.isEmpty)
        let expected = ["idle 5", "hover 11", "hover 17", "idle 0", "idle 3"]
        #expect(Self.trace(&first) == expected)
        var second = try MachinePlayer(machineID: "m", in: doc)
        #expect(Self.trace(&second) == expected)
        #expect(first == second)
    }

    @Test func selfTransitionRestartsAtStartFrame() throws {
        let doc = StateMachineTests.document { $0.transitions.append(Transition(from: "hover", to: "hover", trigger: "press")) }
        var player = try MachinePlayer(machineID: "m", in: doc)
        player.fire("pointerEnter")
        player.advance(frames: 4)
        #expect(player.stateID == "hover" && player.frame == 15)
        player.fire("press")
        #expect(player.stateID == "hover" && player.frame == 11)
    }

    @Test func unknownTriggerAndNonPositiveAdvanceChangeNothing() throws {
        var player = try MachinePlayer(machineID: "m", in: StateMachineTests.document())
        player.advance(frames: 7)
        let before = player
        player.fire("nope")
        player.fire("pointerExit")  // a trigger only hover takes
        player.advance(frames: 0)
        player.advance(frames: -3)
        player.advance(frames: Int.min)
        #expect(player == before)
    }

    @Test func advanceLoopsAndStaysInRange() throws {
        var player = try MachinePlayer(machineID: "m", in: StateMachineTests.document())
        player.advance(frames: 11)
        #expect(player.frame == 0)
        player.advance(frames: Int.max)
        #expect(player.frame == Int.max % 11)
        var rng = SplitMix64(seed: 225)
        for _ in 0..<200 {
            player.advance(frames: Int.random(in: 0...Int.max, using: &rng))
            #expect((0...10).contains(player.frame))
        }
    }

    @Test func stateSpanningAllOfIntNeverOverflows() throws {
        let machine = StateMachine(
            id: "big", name: "Big",
            states: [MachineState(id: "all", name: "All", sceneID: "s", startFrame: 0, endFrame: Int.max)],
            initialState: "all")
        let doc = Document(scenes: [Scene(id: "s", name: "S", durationFrames: Int.max)], stateMachines: [machine])
        try FlareFormat.validate(doc)
        var player = try MachinePlayer(machineID: "big", in: doc)
        player.advance(frames: Int.max)
        #expect(player.frame == Int.max)
        player.advance(frames: 1)
        #expect(player.frame == 0)
        player.advance(frames: Int.max)
        player.advance(frames: Int.max)
        #expect(player.frame == Int.max - 1)
        var rng = SplitMix64(seed: 7)
        for _ in 0..<200 {
            player.advance(frames: Int.random(in: 1...Int.max, using: &rng))
            #expect(player.frame >= 0)
        }
    }

    @Test func setRefusesUnknownOtherTypeAndNonFinite() throws {
        var player = try MachinePlayer(machineID: "m", in: MachineInputTests.document([]))
        let before = player
        let refused = [
            player.set("nope", to: .bool(true)), player.set("enabled", to: .number(1)),
            player.set("level", to: .bool(true)), player.set("level", to: .number(.nan)),
            player.set("level", to: .number(.infinity)),
        ]
        #expect(refused == [false, false, false, false, false])
        #expect(player == before)
        let accepted = player.set("level", to: .number(3))
        #expect(accepted)
        #expect(player.inputs["level"] == .number(3))
    }

    @Test func fireAgreesWithNextUnderConditions() throws {
        let conditions = [
            Condition(input: "level", op: .greater, value: .number(2)),
            Condition(input: "enabled", op: .equal, value: .bool(true)),
        ]
        let doc = MachineInputTests.document(conditions)
        let machine = try #require(doc.stateMachines.first)
        for level in [0.0, 2, 3, 9] {
            for enabled in [true, false] {
                var player = try MachinePlayer(machineID: "m", in: doc)
                let setLevel = player.set("level", to: .number(level))
                let setEnabled = player.set("enabled", to: .bool(enabled))
                #expect(setLevel && setEnabled)
                player.fire("click")
                #expect(player.stateID == machine.next(from: "idle", trigger: "click", inputs: player.inputs))
                #expect(player.stateID == (level > 2 && enabled ? "on" : "idle"))
            }
        }
    }

    @Test func missingMachineThrows() {
        #expect(throws: TimelineError.stateMachineNotFound("x")) {
            try MachinePlayer(machineID: "x", in: StateMachineTests.document())
        }
    }

    @Test func machineWithErrorIssueThrowsFirstError() throws {
        let doc = StateMachineTests.document { $0.transitions[0].to = "nope" }
        let machine = try #require(doc.stateMachines.first)
        let issue = try #require(machine.issues(in: doc).first { $0.severity == .error })
        #expect(throws: TimelineError.invalidMachine(issue)) { try MachinePlayer(machineID: "m", in: doc) }
    }

    @Test func warningOnlyMachinePlays() throws {
        let doc = StateMachineTests.document { $0.transitions.removeAll() }
        let machine = try #require(doc.stateMachines.first)
        #expect(machine.issues(in: doc).contains { $0.severity == .warning })
        let player = try MachinePlayer(machineID: "m", in: doc)
        #expect(player.stateID == "idle")
    }
}
