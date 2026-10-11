// MachineInputTests.swift: state machine inputs and conditions. A transition
// fires only when its conditions hold, missing inputs use defaults, validation
// rejects unknown inputs and type mismatches, and old machines still decode.
import FlareCore
import Foundation
import Testing

@Suite struct MachineInputTests {
    static func machine(_ conditions: [Condition]) -> StateMachine {
        StateMachine(
            id: "m", name: "Button",
            states: ["idle", "on"].map { MachineState(id: $0, name: $0, sceneID: "s", startFrame: 0, endFrame: 0) },
            transitions: [Transition(from: "idle", to: "on", trigger: "click", conditions: conditions)],
            initialState: "idle",
            inputs: [
                MachineInput(name: "enabled", defaultValue: .bool(true)),
                MachineInput(name: "level", defaultValue: .number(0)),
            ])
    }

    static func document(_ conditions: [Condition]) -> Document {
        Document(scenes: [Scene(id: "s", name: "S", durationFrames: 1)], stateMachines: [machine(conditions)])
    }

    @Test func transitionFiresOnlyWhenConditionHolds() {
        let m = Self.machine([Condition(input: "enabled", op: .equal, value: .bool(true))])
        #expect(m.next(from: "idle", trigger: "click") == "on")
        #expect(m.next(from: "idle", trigger: "click", inputs: ["enabled": .bool(false)]) == "idle")
        #expect(m.next(from: "idle", trigger: "click", inputs: ["enabled": .bool(true)]) == "on")
    }

    @Test func numberComparisons() {
        let m = Self.machine([
            Condition(input: "level", op: .greater, value: .number(2)),
            Condition(input: "level", op: .less, value: .number(5)),
        ])
        let results = [0.0, 2, 3, 4.5, 5, 9].map { m.next(from: "idle", trigger: "click", inputs: ["level": .number($0)]) }
        #expect(results == ["idle", "idle", "on", "on", "idle", "idle"])
        #expect(m.next(from: "idle", trigger: "click") == "idle")
        #expect(m.next(from: "idle", trigger: "click", inputs: ["level": .bool(true)]) == "idle")
    }

    @Test func roundTripIsByteStable() throws {
        let doc = Self.document([Condition(input: "level", op: .greater, value: .number(1.5))])
        let first = try FlareFormat.encode(doc)
        let decoded = try FlareFormat.decode(first)
        #expect(decoded == doc)
        #expect(try FlareFormat.encode(decoded) == first)
    }

    @Test func machineWithoutInputsDecodesAndLeavesKeysOut() throws {
        let json = #"""
        {"format":"flare","version":1,"document":{"scenes":[{"id":"s","name":"S","fps":24,"durationFrames":1,"layers":[]}],
         "stateMachines":[{"id":"m","name":"M","initialState":"a",
          "states":[{"id":"a","name":"A","sceneID":"s","startFrame":0,"endFrame":0}],
          "transitions":[{"from":"a","to":"a","trigger":"t"}]}]}}
        """#
        let doc = try FlareFormat.decode(Data(json.utf8))
        #expect(doc.stateMachines[0].inputs.isEmpty)
        #expect(doc.stateMachines[0].transitions[0].conditions.isEmpty)
        let text = String(decoding: try FlareFormat.encode(doc), as: UTF8.self)
        #expect(!text.contains("inputs"))
        #expect(!text.contains("conditions"))
    }

    @Test(arguments: ["unknown input", "bool compared with <", "value type mismatch", "duplicate input"])
    func validationRejects(_ kind: String) {
        var doc: Document
        switch kind {
        case "unknown input": doc = Self.document([Condition(input: "nope", op: .equal, value: .bool(true))])
        case "bool compared with <": doc = Self.document([Condition(input: "enabled", op: .less, value: .bool(true))])
        case "value type mismatch": doc = Self.document([Condition(input: "level", op: .equal, value: .bool(true))])
        default:
            doc = Self.document([])
            doc.stateMachines[0].inputs.append(MachineInput(name: "level", defaultValue: .number(1)))
        }
        #expect("\(kind)") { try FlareFormat.validate(doc) } throws: { error in
            guard case FormatError.invalid = error else { return false }
            return true
        }
    }

    @Test func validConditionsPass() throws {
        try FlareFormat.validate(Self.document([
            Condition(input: "enabled", op: .equal, value: .bool(false)),
            Condition(input: "level", op: .less, value: .number(3)),
        ]))
    }

    @Test func fuzzedInputJSONThrowsInsteadOfCrashing() throws {
        let doc = Self.document([Condition(input: "level", op: .greater, value: .number(1))])
        let base = Array(try FlareFormat.encode(doc))
        var rng = SplitMix64(seed: 48)
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
