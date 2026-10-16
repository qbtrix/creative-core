// MachineStateCommandTests.swift: adding, updating and removing a machine's
// states undoes exactly (remove puts the state back at its index); a state a
// transition names, the initial state, a range past the scene or a missing
// state is refused without changes; the commands are sampled and stepped.
import FlareCore
import Testing

@Suite struct MachineStateCommandTests {
    static let s = Fixtures.sceneID
    static let pressed = MachineState(id: "pressed", name: "Pressed", sceneID: s, startFrame: 21, endFrame: 30)

    /// Machine "btn": idle, hover and pressed; transition 0 is idle -> hover
    /// and transition 1, the only one naming "pressed", is idle -> pressed.
    static func start() -> Document {
        var doc = MachineCommandTests.start()
        doc.stateMachines[1].states.append(pressed)
        doc.stateMachines[1].transitions.append(Transition(from: "idle", to: "pressed", trigger: "press"))
        return doc
    }

    static func performUndoRedo(_ command: some Command, _ check: (StateMachine) -> Void) throws {
        var engine = CommandEngine(document: start())
        try engine.perform(command)
        let done = engine.document
        #expect(done.stateMachines.map(\.id) == ["a", "btn", "c"])
        #expect(done.stateMachines[0] == start().stateMachines[0])
        check(done.stateMachines[1])
        try engine.undo()
        #expect(engine.document == start())
        try engine.redo()
        #expect(engine.document == done)
    }

    @Test func addUndoRedoExact() throws {
        let state = MachineState(id: "off", name: "Off", sceneID: Self.s, startFrame: 31, endFrame: 48)
        try Self.performUndoRedo(AddMachineState(machineID: "btn", state: state)) { m in
            #expect(m.states.map(\.id) == ["idle", "hover", "pressed", "off"])
            #expect(m.states.last == state)
        }
    }

    @Test func updateUndoRedoExact() throws {
        let state = MachineState(id: "hover", name: "Over", sceneID: Self.s, startFrame: 5, endFrame: 48)
        try Self.performUndoRedo(UpdateMachineState(machineID: "btn", state: state)) { m in
            #expect(m.states.map(\.id) == ["idle", "hover", "pressed"])
            #expect(m.states[1] == state)
        }
    }

    @Test func removeUndoPutsStateBackAtItsIndex() throws {
        var doc = Self.start()
        doc.stateMachines[1].transitions = [Transition(from: "idle", to: "pressed", trigger: "press")]
        var engine = CommandEngine(document: doc)
        try engine.perform(RemoveMachineState(machineID: "btn", stateID: "hover"))
        #expect(engine.document.stateMachines[1].states.map(\.id) == ["idle", "pressed"])
        try engine.undo()
        #expect(engine.document == doc)
        try engine.redo()
        #expect(engine.document.stateMachines[1].states.map(\.id) == ["idle", "pressed"])
    }

    @Test func removingStateATransitionNamesThrowsWithItsIndex() {
        let issue = MachineIssue(severity: .error, message: "transition idle -> pressed names an unknown state",
                                 transitionIndex: 1)
        Self.expectRefused(RemoveMachineState(machineID: "btn", stateID: "pressed"), .invalidMachine(issue))
    }

    @Test func removingInitialStateThrowsNamingIt() {
        let issue = MachineIssue(severity: .error, message: "unknown initial state idle", stateID: "idle")
        Self.expectRefused(RemoveMachineState(machineID: "btn", stateID: "idle"), .invalidMachine(issue))
    }

    @Test func updatePastSceneDurationThrows() {
        let state = MachineState(id: "hover", name: "Hover", sceneID: Self.s, startFrame: 11, endFrame: 49)
        let issue = MachineIssue(severity: .error, message: "state hover frame range outside scene", stateID: "hover")
        Self.expectRefused(UpdateMachineState(machineID: "btn", state: state), .invalidMachine(issue))
    }

    @Test func addWithUsedStateIDThrows() {
        let issue = MachineIssue(severity: .error, message: "duplicate state id idle", stateID: "idle")
        Self.expectRefused(AddMachineState(machineID: "btn", state: MachineCommandTests.idle), .invalidMachine(issue))
    }

    @Test func missingStateOrMachineThrows() {
        let ghost = MachineState(id: "ghost", name: "G", sceneID: Self.s, startFrame: 0, endFrame: 1)
        Self.expectRefused(UpdateMachineState(machineID: "btn", state: ghost), .stateNotFound("ghost"))
        Self.expectRefused(RemoveMachineState(machineID: "btn", stateID: "ghost"), .stateNotFound("ghost"))
        Self.expectRefused(AddMachineState(machineID: "x", state: ghost), .stateMachineNotFound("x"))
        Self.expectRefused(UpdateMachineState(machineID: "x", state: ghost), .stateMachineNotFound("x"))
        Self.expectRefused(RemoveMachineState(machineID: "x", stateID: "idle"), .stateMachineNotFound("x"))
    }

    @Test func undoBeforeExecuteThrows() {
        var doc = Self.start()
        #expect(throws: CommandError.notExecuted) { try AddMachineState(machineID: "btn", state: Self.pressed).undo(&doc) }
        #expect(throws: CommandError.notExecuted) { try UpdateMachineState(machineID: "btn", state: Self.pressed).undo(&doc) }
        #expect(throws: CommandError.notExecuted) { try RemoveMachineState(machineID: "btn", stateID: "hover").undo(&doc) }
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
        let ids: Set<String> = ["machine.addState", "machine.updateState", "machine.removeState"]
        #expect(ids.isSubset(of: Set(StateMachineCommands.all.map { $0.id })))
        #expect(ids.isSubset(of: Set(CommandRegistry.builtIn.ids)))
        #expect(Set(Self.registrySamples().map { type(of: $0).id }) == ids)
        #expect(Self.undoSteps.count == 3)
    }

    @Test(arguments: 0..<100)
    func machineStateUndoAllRestoresOriginal(seed: UInt64) throws {
        try assertUndoRestoresDocument(seed: seed, steps: MachineCommandTests.undoSteps + Self.undoSteps)
    }

    /// One sample of each state command, valid on
    /// `CommandRegistryTests.sampleDocument()`, whose machine "btn" has
    /// transition idle -> hover and unnamed state "off". They use scene "s1"
    /// (48 frames), which the fuzz's random documents also hold.
    static func registrySamples() -> [any Command] {
        [
            AddMachineState(machineID: "btn", state: MachineState(
                id: "pressed", name: "Pressed", sceneID: Self.s, startFrame: 21, endFrame: 30)),
            UpdateMachineState(machineID: "btn", state: MachineState(
                id: "hover", name: "Over", sceneID: Self.s, startFrame: 12, endFrame: 40)),
            RemoveMachineState(machineID: "btn", stateID: "off"),
        ]
    }

    static func anyState(_ e: CommandEngine, _ machineID: String, _ rng: inout SplitMix64) -> String {
        let states = e.document.stateMachines.first { $0.id == machineID }?.states.map(\.id) ?? []
        return (states + ["missing"]).randomElement(using: &rng) ?? "missing"
    }

    /// A state with id `id`, sometimes on a missing scene or with a range
    /// outside the 48-frame fixture scene.
    static func randomState(_ id: String, _ rng: inout SplitMix64) -> MachineState {
        let scene = Int.random(in: 0..<6, using: &rng) == 0 ? "missing" : Fixtures.sceneID
        let start = Int.random(in: -1...40, using: &rng)
        return MachineState(id: id, name: "S", sceneID: scene, startFrame: start,
                            endFrame: start + Int.random(in: -1...12, using: &rng))
    }

    /// State steps. They cope with a document that has no machine: then they
    /// name "missing" and throw.
    static let undoSteps: [UndoStep] = [
        { e, rng, nextID in
            nextID += 1
            let machine = MachineCommandTests.anyMachine(e, &rng)
            let id = Int.random(in: 0..<5, using: &rng) == 0 ? anyState(e, machine, &rng) : "st\(nextID)"
            try e.perform(AddMachineState(machineID: machine, state: randomState(id, &rng)))
        },
        { e, rng, _ in
            let machine = MachineCommandTests.anyMachine(e, &rng)
            let id = anyState(e, machine, &rng)
            try e.perform(UpdateMachineState(machineID: machine, state: randomState(id, &rng)))
        },
        { e, rng, _ in
            let machine = MachineCommandTests.anyMachine(e, &rng)
            try e.perform(RemoveMachineState(machineID: machine, stateID: anyState(e, machine, &rng)))
        },
    ]
}
