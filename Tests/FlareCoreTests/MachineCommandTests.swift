// MachineCommandTests.swift: the state machine commands undo exactly (remove
// puts the machine back at its index); a used id, "", or a state breaking a
// rule throws without changes; the family is registered, sampled and stepped.
import FlareCore
import Testing

@Suite struct MachineCommandTests {
    static let idle = MachineState(id: "idle", name: "Idle", sceneID: Fixtures.sceneID, startFrame: 0, endFrame: 10)
    static let hover = MachineState(id: "hover", name: "Hover", sceneID: Fixtures.sceneID, startFrame: 11, endFrame: 20)

    /// A two-state machine on `scene`: idle, and hover reached on "hover".
    static func button(_ id: String = "btn", scene: String = Fixtures.sceneID) -> StateMachine {
        let states = [idle, hover].map { s in var s = s; s.sceneID = scene; return s }
        return StateMachine(id: id, name: "Button", states: states,
                            transitions: [Transition(from: "idle", to: "hover", trigger: "hover")],
                            initialState: "idle")
    }

    /// The fixture document with machines "a", "btn" and "c".
    static func start() -> Document {
        var doc = Fixtures.document()
        doc.stateMachines = [button("a"), button(), button("c")]
        return doc
    }

    /// Performs `command` on `start()`, checks the result, then undo gives
    /// back the start exactly and redo gives back the result.
    static func performUndoRedo(_ command: some Command, _ check: (Document) -> Void) throws {
        var engine = CommandEngine(document: start())
        try engine.perform(command)
        let done = engine.document
        check(done)
        try engine.undo()
        #expect(engine.document == start())
        try engine.redo()
        #expect(engine.document == done)
    }

    @Test func addUndoRedoExact() throws {
        try Self.performUndoRedo(AddStateMachine(id: "nav", name: "Nav", firstState: Self.idle)) { doc in
            #expect(doc.stateMachines.map(\.id) == ["a", "btn", "c", "nav"])
            #expect(doc.stateMachines.last == StateMachine(id: "nav", name: "Nav", states: [Self.idle],
                                                           initialState: "idle"))
        }
    }

    @Test func renameUndoRedoExact() throws {
        try Self.performUndoRedo(RenameStateMachine(machineID: "btn", name: "Toggle")) { doc in
            #expect(doc.stateMachines.map(\.name) == ["Button", "Toggle", "Button"])
        }
    }

    @Test func removeUndoPutsItBackAtItsIndex() throws {
        try Self.performUndoRedo(RemoveStateMachine(machineID: "btn")) { doc in
            #expect(doc.stateMachines.map(\.id) == ["a", "c"])
        }
    }

    @Test func setInitialUndoRedoExact() throws {
        try Self.performUndoRedo(SetInitialState(machineID: "btn", stateID: "hover")) { doc in
            #expect(doc.stateMachines.map(\.initialState) == ["idle", "hover", "idle"])
        }
    }

    @Test func addWithUsedIDThrowsDuplicateID() {
        let add = AddStateMachine(id: "btn", name: "Again", firstState: Self.idle)
        Self.expectRefused(add, CommandError.duplicateID("btn"))
    }

    @Test func emptyNameThrows() {
        Self.expectRefused(AddStateMachine(id: "nav", name: "", firstState: Self.idle), CommandError.emptyName)
        Self.expectRefused(RenameStateMachine(machineID: "btn", name: ""), CommandError.emptyName)
    }

    @Test func firstStateOnMissingSceneThrowsInvalidMachine() {
        let state = MachineState(id: "lost", name: "Lost", sceneID: "ghost", startFrame: 0, endFrame: 1)
        let issue = MachineIssue(severity: .error, message: "state lost has unknown scene ghost", stateID: "lost")
        let add = AddStateMachine(id: "nav", name: "Nav", firstState: state)
        Self.expectRefused(add, CommandError.invalidMachine(issue))
    }

    @Test func unknownInitialStateThrowsInvalidMachine() {
        let issue = MachineIssue(severity: .error, message: "unknown initial state ghost", stateID: "ghost")
        Self.expectRefused(SetInitialState(machineID: "btn", stateID: "ghost"), CommandError.invalidMachine(issue))
    }

    @Test func missingMachineThrowsStateMachineNotFound() {
        Self.expectRefused(RenameStateMachine(machineID: "x", name: "X"), CommandError.stateMachineNotFound("x"))
        Self.expectRefused(RemoveStateMachine(machineID: "x"), CommandError.stateMachineNotFound("x"))
        Self.expectRefused(SetInitialState(machineID: "x", stateID: "idle"), CommandError.stateMachineNotFound("x"))
    }

    @Test func undoBeforeExecuteThrows() {
        var doc = Self.start()
        #expect(throws: CommandError.notExecuted) { try RenameStateMachine(machineID: "btn", name: "T").undo(&doc) }
        #expect(throws: CommandError.notExecuted) { try RemoveStateMachine(machineID: "btn").undo(&doc) }
        #expect(throws: CommandError.notExecuted) { try SetInitialState(machineID: "btn", stateID: "idle").undo(&doc) }
    }

    /// Both `execute` alone and `perform` throw `error` and change nothing.
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
        let ids: Set<String> = ["machine.add", "machine.rename", "machine.remove", "machine.setInitial"]
        #expect(ids.isSubset(of: Set(StateMachineCommands.all.map { $0.id })))
        #expect(ids.isSubset(of: Set(CommandRegistry.builtIn.ids)))
        #expect(Set(Self.registrySamples().map { type(of: $0).id }) == ids)
        #expect(Self.undoSteps.count == 4)
    }

    @Test(arguments: 0..<100)
    func machineUndoAllRestoresOriginal(seed: UInt64) throws {
        try assertUndoRestoresDocument(seed: seed, steps: Self.undoSteps)
    }

    /// One sample of each machine command, valid on
    /// `CommandRegistryTests.sampleDocument()`, whose machine "btn" plays scene "outro".
    static func registrySamples() -> [any Command] {
        [
            AddStateMachine(id: "nav", name: "Nav", firstState: MachineState(
                id: "home", name: "Home", sceneID: "outro", startFrame: 0, endFrame: 5)),
            RenameStateMachine(machineID: "btn", name: "Toggle"),
            RemoveStateMachine(machineID: "btn"),
            SetInitialState(machineID: "btn", stateID: "hover"),
        ]
    }

    static func anyMachine(_ e: CommandEngine, _ rng: inout SplitMix64) -> String {
        (e.document.stateMachines.map(\.id) + ["missing"]).randomElement(using: &rng) ?? "missing"
    }

    /// Machine steps. They cope with a document that has no machine: then they
    /// name "missing" and throw; the add step makes machines for the others.
    static let undoSteps: [UndoStep] = [
        { e, rng, nextID in
            nextID += 1
            let id = Int.random(in: 0..<5, using: &rng) == 0 ? anyMachine(e, &rng) : "M\(nextID)"
            let scene = Int.random(in: 0..<6, using: &rng) == 0 ? "missing" : Fixtures.sceneID
            let start = Int.random(in: -1...30, using: &rng)
            let state = MachineState(id: "st\(nextID)", name: "State", sceneID: scene,
                                     startFrame: start, endFrame: start + Int.random(in: -1...30, using: &rng))
            let name = Int.random(in: 0..<6, using: &rng) == 0 ? "" : "Machine \(nextID)"
            try e.perform(AddStateMachine(id: id, name: name, firstState: state))
        },
        { e, rng, _ in
            let name = Int.random(in: 0..<6, using: &rng) == 0 ? "" : "n\(Int.random(in: 0...30, using: &rng))"
            try e.perform(RenameStateMachine(machineID: anyMachine(e, &rng), name: name))
        },
        { e, rng, _ in try e.perform(RemoveStateMachine(machineID: anyMachine(e, &rng))) },
        { e, rng, _ in
            let id = anyMachine(e, &rng)
            let states = e.document.stateMachines.first { $0.id == id }?.states.map(\.id) ?? []
            let stateID = (states + ["missing"]).randomElement(using: &rng) ?? "missing"
            try e.perform(SetInitialState(machineID: id, stateID: stateID))
        },
    ]
}
