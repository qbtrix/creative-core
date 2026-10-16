// MachineInputCommandTests.swift: adding, updating the default of and
// removing a machine's inputs undoes exactly (remove puts the input back at
// its index); a used name, a non-finite default, a type change, a missing
// input or one a condition still uses is refused without changes; sampled
// and stepped.
import FlareCore
import Testing

@Suite struct MachineInputCommandTests {
    static let on = MachineInput(name: "on", defaultValue: .bool(false))
    static let level = MachineInput(name: "level", defaultValue: .number(1))
    static let tap = Transition(from: "idle", to: "hover", trigger: "tap",
                                conditions: [Condition(input: "level", op: .greater, value: .number(0))])

    /// Machine "btn" of `TransitionCommandTests.start()` with inputs "on"
    /// (bool) and "level" (number), and a third transition (2) whose
    /// condition uses "level".
    static func start() -> Document {
        var doc = TransitionCommandTests.start()
        doc.stateMachines[1].inputs = [on, level]
        doc.stateMachines[1].transitions.append(tap)
        return doc
    }

    static func performUndoRedo(_ command: some Command, _ check: ([MachineInput]) -> Void) throws {
        var engine = CommandEngine(document: start())
        try engine.perform(command)
        let done = engine.document
        #expect(done.stateMachines.map(\.id) == ["a", "btn", "c"])
        #expect(done.stateMachines[0] == start().stateMachines[0])
        #expect(done.stateMachines[1].transitions == start().stateMachines[1].transitions)
        check(done.stateMachines[1].inputs)
        try engine.undo()
        #expect(engine.document == start())
        try engine.redo()
        #expect(engine.document == done)
    }

    @Test func addUndoRedoExact() throws {
        let speed = MachineInput(name: "speed", defaultValue: .number(2.5))
        try Self.performUndoRedo(AddMachineInput(machineID: "btn", input: speed)) { inputs in
            #expect(inputs == [Self.on, Self.level, speed])
        }
    }

    @Test func updateDefaultUndoRedoExact() throws {
        let new = MachineInput(name: "on", defaultValue: .bool(true))
        try Self.performUndoRedo(UpdateMachineInput(machineID: "btn", input: new)) { inputs in
            #expect(inputs == [new, Self.level])
        }
    }

    @Test func removeUndoPutsInputBackAtItsIndex() throws {
        try Self.performUndoRedo(RemoveMachineInput(machineID: "btn", name: "on")) { inputs in
            #expect(inputs == [Self.level])
        }
    }

    @Test func updateToAnotherTypeThrowsInputTypeChange() {
        Self.expectRefused(UpdateMachineInput(machineID: "btn", input: MachineInput(name: "on", defaultValue: .number(1))),
                           .inputTypeChange("on"))
        Self.expectRefused(UpdateMachineInput(machineID: "btn", input: MachineInput(name: "level", defaultValue: .bool(true))),
                           .inputTypeChange("level"))
    }

    @Test func removingInputAConditionUsesNamesTheTransition() {
        let issue = MachineIssue(severity: .error, message: "condition names unknown input level", transitionIndex: 2)
        Self.expectRefused(RemoveMachineInput(machineID: "btn", name: "level"), .invalidMachine(issue))
    }

    @Test func duplicateNameThrows() {
        let issue = MachineIssue(severity: .error, message: "duplicate input on")
        let again = MachineInput(name: "on", defaultValue: .number(3))
        Self.expectRefused(AddMachineInput(machineID: "btn", input: again), .invalidMachine(issue))
    }

    @Test func inputIssueNamesTheInputOnlyInItsMessage() throws {
        var doc = Self.start()
        var add = AddMachineInput(machineID: "btn", input: MachineInput(name: "level", defaultValue: .number(3)))
        do {
            try add.execute(&doc)
            Issue.record("a duplicate input name was accepted")
        } catch CommandError.invalidMachine(let issue) {
            #expect(issue.stateID == nil && issue.transitionIndex == nil)
            #expect(issue.message.contains("level"))
        }
        #expect(doc == Self.start())
    }

    @Test func nonFiniteDefaultThrows() {
        let nan = MachineInput(name: "speed", defaultValue: .number(.nan))
        Self.expectRefused(AddMachineInput(machineID: "btn", input: nan),
                           .invalidMachine(MachineIssue(severity: .error, message: "input speed default is not finite")))
        let inf = MachineInput(name: "level", defaultValue: .number(.infinity))
        Self.expectRefused(UpdateMachineInput(machineID: "btn", input: inf),
                           .invalidMachine(MachineIssue(severity: .error, message: "input level default is not finite")))
    }

    @Test func missingInputThrowsInputNotFound() {
        let ghost = MachineInput(name: "ghost", defaultValue: .bool(true))
        Self.expectRefused(UpdateMachineInput(machineID: "btn", input: ghost), .inputNotFound("ghost"))
        Self.expectRefused(RemoveMachineInput(machineID: "btn", name: "ghost"), .inputNotFound("ghost"))
    }

    @Test func missingMachineThrows() {
        Self.expectRefused(AddMachineInput(machineID: "x", input: Self.on), .stateMachineNotFound("x"))
        Self.expectRefused(UpdateMachineInput(machineID: "x", input: Self.on), .stateMachineNotFound("x"))
        Self.expectRefused(RemoveMachineInput(machineID: "x", name: "on"), .stateMachineNotFound("x"))
    }

    @Test func undoBeforeExecuteThrows() {
        var doc = Self.start()
        #expect(throws: CommandError.notExecuted) { try AddMachineInput(machineID: "btn", input: Self.on).undo(&doc) }
        #expect(throws: CommandError.notExecuted) { try UpdateMachineInput(machineID: "btn", input: Self.on).undo(&doc) }
        #expect(throws: CommandError.notExecuted) { try RemoveMachineInput(machineID: "btn", name: "on").undo(&doc) }
    }

    static func expectRefused(_ command: some Command, _ error: CommandError) {
        var cmd = command
        var doc = start()
        #expect(throws: error) { try cmd.execute(&doc) }
        #expect(doc == start())
        var engine = CommandEngine(document: start())
        #expect(throws: error) { try engine.perform(command) }
        #expect(engine.document == start())
        #expect(!engine.canUndo)
    }

    @Test func registeredSampledAndStepped() {
        let ids: Set<String> = ["machine.addInput", "machine.updateInput", "machine.removeInput"]
        #expect(ids.isSubset(of: Set(StateMachineCommands.all.map { $0.id })))
        #expect(ids.isSubset(of: Set(CommandRegistry.builtIn.ids)))
        #expect(Set(Self.registrySamples().map { type(of: $0).id }) == ids)
        #expect(Self.undoSteps.count == 3)
    }

    /// Machine, state, transition and input steps; input steps last.
    static let familySteps = MachineCommandTests.undoSteps + MachineStateCommandTests.undoSteps
        + TransitionCommandTests.undoSteps + undoSteps

    @Test(arguments: 0..<100)
    func inputUndoAllRestoresOriginal(seed: UInt64) throws {
        try assertUndoRestoresDocument(seed: seed, steps: Self.familySteps, start: TransitionCommandTests.start())
    }

    /// The seeds of `inputUndoAllRestoresOriginal` add transitions whose
    /// condition uses a declared input, then try to remove that input, which
    /// is refused. The start declares "on" but no condition uses it.
    @Test func inputStepsReachInUseRefusal() {
        var refused = 0
        for seed in UInt64(0)..<100 {
            var rng = SplitMix64(seed: seed)
            var engine = CommandEngine(document: TransitionCommandTests.start())
            var nextID = 0
            for _ in 0..<40 {
                let i = Int.random(in: 0..<Self.familySteps.count, using: &rng)
                do {
                    try Self.familySteps[i](&engine, &rng, &nextID)
                } catch CommandError.invalidMachine(let issue)
                    where i == Self.familySteps.count - 1 && issue.message.hasPrefix("condition names unknown input") {
                    refused += 1
                } catch {}
            }
        }
        #expect(refused > 0)
    }

    /// One sample of each input command, valid on
    /// `CommandRegistryTests.sampleDocument()`, whose machine "btn" has the
    /// bool input "on".
    static func registrySamples() -> [any Command] {
        [
            AddMachineInput(machineID: "btn", input: level),
            UpdateMachineInput(machineID: "btn", input: MachineInput(name: "on", defaultValue: .bool(true))),
            RemoveMachineInput(machineID: "btn", name: "on"),
        ]
    }

    /// An input name of machine `id`, or "missing".
    static func anyInput(_ e: CommandEngine, _ id: String, _ rng: inout SplitMix64) -> String {
        let names = e.document.stateMachines.first { $0.id == id }?.inputs.map(\.name) ?? []
        return (names + ["missing"]).randomElement(using: &rng) ?? "missing"
    }

    /// A bool or number value, sometimes not finite.
    static func randomValue(_ rng: inout SplitMix64) -> InputValue {
        switch Int.random(in: 0..<5, using: &rng) {
        case 0: return .number(.nan)
        case 1, 2: return .bool(Bool.random(using: &rng))
        default: return .number(Double(Int.random(in: -3...3, using: &rng)))
        }
    }

    /// Input steps. They cope with a document without machines or inputs:
    /// then they name "missing" and throw; the add step makes inputs.
    static let undoSteps: [UndoStep] = [
        { e, rng, _ in
            let machine = MachineCommandTests.anyMachine(e, &rng)
            let name = Bool.random(using: &rng) ? anyInput(e, machine, &rng) : "i\(Int.random(in: 0...3, using: &rng))"
            try e.perform(AddMachineInput(machineID: machine, input: MachineInput(name: name, defaultValue: randomValue(&rng))))
        },
        { e, rng, _ in
            let machine = MachineCommandTests.anyMachine(e, &rng)
            let name = anyInput(e, machine, &rng)
            try e.perform(UpdateMachineInput(machineID: machine, input: MachineInput(name: name, defaultValue: randomValue(&rng))))
        },
        { e, rng, _ in
            let machine = MachineCommandTests.anyMachine(e, &rng)
            try e.perform(RemoveMachineInput(machineID: machine, name: anyInput(e, machine, &rng)))
        },
    ]
}
