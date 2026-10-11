// StateMachineTests.swift: state machine model. Old files decode with none, a
// document with one round-trips byte-stable, every bad reference throws, and
// `next` steps through transitions (first match wins, unknown trigger stays).
import FlareCore
import Foundation
import Testing

@Suite struct StateMachineTests {
    static func document(_ edit: (inout StateMachine) -> Void = { _ in }) -> Document {
        var machine = StateMachine(
            id: "m", name: "Button",
            states: [
                MachineState(id: "idle", name: "Idle", sceneID: "s", startFrame: 0, endFrame: 10),
                MachineState(id: "hover", name: "Hover", sceneID: "s", startFrame: 11, endFrame: 24),
            ],
            transitions: [
                Transition(from: "idle", to: "hover", trigger: "pointerEnter"),
                Transition(from: "hover", to: "idle", trigger: "pointerExit"),
            ],
            initialState: "idle")
        edit(&machine)
        return Document(scenes: [Scene(id: "s", name: "S", durationFrames: 24)], stateMachines: [machine])
    }

    @Test func oldFileDecodesWithNoStateMachines() throws {
        let json = #"{"format":"flare","version":1,"document":{"scenes":[{"id":"s","name":"S","fps":24,"durationFrames":1,"layers":[]}]}}"#
        let doc = try FlareFormat.decode(Data(json.utf8))
        #expect(doc.stateMachines.isEmpty)
        #expect(doc.scenes.count == 1)
    }

    @Test func roundTripIsByteStable() throws {
        let first = try FlareFormat.encode(Self.document())
        let decoded = try FlareFormat.decode(first)
        #expect(decoded == Self.document())
        #expect(try FlareFormat.encode(decoded) == first)
    }

    @Test func noStateMachinesLeavesKeyOut() throws {
        let data = try FlareFormat.encode(Document(scenes: [Scene(id: "s", name: "S")]))
        #expect(!String(decoding: data, as: UTF8.self).contains("stateMachines"))
    }

    @Test func fullDurationRangeIsValid() throws {
        try FlareFormat.validate(Self.document { $0.states[0].endFrame = 24 })
    }

    @Test func duplicateMachineIDThrows() throws {
        var doc = Self.document()
        doc.stateMachines.append(doc.stateMachines[0])
        #expect { try FlareFormat.validate(doc) } throws: { error in
            guard case FormatError.invalid = error else { return false }
            return true
        }
    }

    @Test(arguments: [
        "unknown scene", "unknown from", "unknown to", "unknown initialState",
        "range past duration", "negative start", "start after end", "duplicate state",
    ])
    func badReferenceThrows(_ kind: String) throws {
        let doc = Self.document { m in
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
        #expect("\(kind)") { try FlareFormat.validate(doc) } throws: { error in
            guard case FormatError.invalid = error else { return false }
            return true
        }
        #expect(throws: FormatError.self) { try FlareFormat.encode(doc) }
    }

    @Test func decodeRejectsBadMachineInFile() {
        let json = #"""
        {"format":"flare","version":1,"document":{"scenes":[],"stateMachines":[
          {"id":"m","name":"M","states":[],"transitions":[],"initialState":"x"}]}}
        """#
        #expect { try FlareFormat.decode(Data(json.utf8)) } throws: { error in
            guard case FormatError.invalid = error else { return false }
            return true
        }
    }

    static let button = StateMachine(
        id: "b", name: "Button",
        states: ["idle", "hover", "pressed"].map {
            MachineState(id: $0, name: $0, sceneID: "s", startFrame: 0, endFrame: 0)
        },
        transitions: [
            Transition(from: "idle", to: "hover", trigger: "enter"),
            Transition(from: "hover", to: "idle", trigger: "exit"),
            Transition(from: "hover", to: "pressed", trigger: "down"),
            Transition(from: "pressed", to: "hover", trigger: "up"),
            Transition(from: "pressed", to: "idle", trigger: "exit"),
        ],
        initialState: "idle")

    @Test func buttonFollowsTriggerScript() {
        let script: [(trigger: String, expected: String)] = [
            ("enter", "hover"), ("down", "pressed"), ("down", "pressed"), ("up", "hover"),
            ("enter", "hover"), ("exit", "idle"), ("up", "idle"), ("enter", "hover"),
            ("down", "pressed"), ("exit", "idle"),
        ]
        var state = Self.button.initialState
        for (i, step) in script.enumerated() {
            state = Self.button.next(from: state, trigger: step.trigger)
            #expect(state == step.expected, "step \(i): \(step.trigger)")
        }
    }

    @Test func unknownTriggerIsNoOp() {
        for state in ["idle", "hover", "pressed"] {
            #expect(Self.button.next(from: state, trigger: "teleport") == state)
        }
        #expect(Self.button.next(from: "nowhere", trigger: "enter") == "nowhere")
    }

    @Test func firstMatchingTransitionWins() {
        var machine = Self.button
        machine.transitions.insert(Transition(from: "idle", to: "pressed", trigger: "enter"), at: 0)
        #expect(machine.next(from: "idle", trigger: "enter") == "pressed")
        #expect(Self.button.next(from: "idle", trigger: "enter") == "hover")
    }

    @Test func fuzzedMachineJSONThrowsInsteadOfCrashing() throws {
        let base = Array(try FlareFormat.encode(Self.document()))
        var rng = SplitMix64(seed: 46)
        for _ in 0..<300 {
            var bytes = base
            for _ in 0..<Int(rng.next() % 4 + 1) {
                let i = Int(rng.next() % UInt64(bytes.count))
                bytes[i] = UInt8(truncatingIfNeeded: rng.next())
            }
            _ = try? FlareFormat.decode(Data(bytes))
        }
    }
}
