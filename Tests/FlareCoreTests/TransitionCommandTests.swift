// TransitionCommandTests.swift: adding (appended, at an index, clamped),
// updating and removing a machine's transitions undoes exactly (remove puts
// the transition back at its index); an unknown state or input, or an index
// outside the transitions, is refused without changes; sampled and stepped.
import FlareCore
import Testing

@Suite struct TransitionCommandTests {
    static let leave = Transition(from: "hover", to: "idle", trigger: "leave")
    static let click = Transition(from: "hover", to: "hover", trigger: "click")

    /// Machine "btn": idle and hover, transitions idle -> hover (0) and
    /// hover -> idle (1), and a bool input "on".
    static func start() -> Document {
        var doc = MachineCommandTests.start()
        doc.stateMachines[1].transitions.append(leave)
        doc.stateMachines[1].inputs = [MachineInput(name: "on", defaultValue: .bool(false))]
        return doc
    }

    static func performUndoRedo(_ command: some Command, _ check: ([Transition]) -> Void) throws {
        var engine = CommandEngine(document: start())
        try engine.perform(command)
        let done = engine.document
        #expect(done.stateMachines.map(\.id) == ["a", "btn", "c"])
        #expect(done.stateMachines[0] == start().stateMachines[0])
        check(done.stateMachines[1].transitions)
        try engine.undo()
        #expect(engine.document == start())
        try engine.redo()
        #expect(engine.document == done)
    }

    @Test func addAppendsUndoRedoExact() throws {
        try Self.performUndoRedo(AddTransition(machineID: "btn", transition: Self.click)) { t in
            #expect(t.map(\.trigger) == ["hover", "leave", "click"])
        }
    }

    @Test func addAtIndexUndoRedoExact() throws {
        try Self.performUndoRedo(AddTransition(machineID: "btn", transition: Self.click, index: 1)) { t in
            #expect(t.map(\.trigger) == ["hover", "click", "leave"])
        }
    }

    @Test func addClampsIndex() throws {
        try Self.performUndoRedo(AddTransition(machineID: "btn", transition: Self.click, index: -1)) { t in
            #expect(t.map(\.trigger) == ["click", "hover", "leave"])
        }
        try Self.performUndoRedo(AddTransition(machineID: "btn", transition: Self.click, index: 99)) { t in
            #expect(t.map(\.trigger) == ["hover", "leave", "click"])
        }
    }

    @Test func updateUndoRedoExact() throws {
        let new = Transition(from: "idle", to: "hover", trigger: "tap",
                             conditions: [Condition(input: "on", op: .equal, value: .bool(true))])
        try Self.performUndoRedo(UpdateTransition(machineID: "btn", index: 0, transition: new)) { t in
            #expect(t == [new, Self.leave])
        }
    }

    @Test func removeUndoPutsTransitionBackAtItsIndex() throws {
        try Self.performUndoRedo(RemoveTransition(machineID: "btn", index: 0)) { t in
            #expect(t == [Self.leave])
        }
    }

    @Test func updateToUnknownStateThrows() {
        let bad = Transition(from: "idle", to: "ghost", trigger: "hover")
        let issue = MachineIssue(severity: .error, message: "transition idle -> ghost names an unknown state",
                                 transitionIndex: 0)
        Self.expectRefused(UpdateTransition(machineID: "btn", index: 0, transition: bad), .invalidMachine(issue))
    }

    @Test func conditionOnUnknownInputThrows() {
        let bad = Transition(from: "idle", to: "hover", trigger: "tap",
                             conditions: [Condition(input: "ghost", op: .equal, value: .bool(true))])
        let issue = MachineIssue(severity: .error, message: "condition names unknown input ghost", transitionIndex: 2)
        Self.expectRefused(AddTransition(machineID: "btn", transition: bad), .invalidMachine(issue))
    }

    @Test func indexOutsideTransitionsThrows() {
        for i in [-1, 2] {
            Self.expectRefused(UpdateTransition(machineID: "btn", index: i, transition: Self.click), .invalidIndex(i))
            Self.expectRefused(RemoveTransition(machineID: "btn", index: i), .invalidIndex(i))
        }
    }

    @Test func missingMachineThrows() {
        Self.expectRefused(AddTransition(machineID: "x", transition: Self.click), .stateMachineNotFound("x"))
        Self.expectRefused(UpdateTransition(machineID: "x", index: 0, transition: Self.click),
                           .stateMachineNotFound("x"))
        Self.expectRefused(RemoveTransition(machineID: "x", index: 0), .stateMachineNotFound("x"))
    }

    @Test func undoBeforeExecuteThrows() {
        var doc = Self.start()
        #expect(throws: CommandError.notExecuted) { try AddTransition(machineID: "btn", transition: Self.click).undo(&doc) }
        #expect(throws: CommandError.notExecuted) {
            try UpdateTransition(machineID: "btn", index: 0, transition: Self.click).undo(&doc)
        }
        #expect(throws: CommandError.notExecuted) { try RemoveTransition(machineID: "btn", index: 0).undo(&doc) }
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
        let ids: Set<String> = ["machine.addTransition", "machine.updateTransition", "machine.removeTransition"]
        #expect(ids.isSubset(of: Set(StateMachineCommands.all.map { $0.id })))
        #expect(ids.isSubset(of: Set(CommandRegistry.builtIn.ids)))
        #expect(Set(Self.registrySamples().map { type(of: $0).id }) == ids)
        #expect(Self.undoSteps.count == 3)
    }

    @Test(arguments: 0..<100)
    func transitionUndoAllRestoresOriginal(seed: UInt64) throws {
        try assertUndoRestoresDocument(seed: seed, steps: MachineCommandTests.undoSteps
                                       + MachineStateCommandTests.undoSteps + Self.undoSteps)
    }

    /// One sample of each transition command, valid on
    /// `CommandRegistryTests.sampleDocument()`, whose machine "btn" has
    /// states idle, hover and off and transition idle -> hover.
    static func registrySamples() -> [any Command] {
        [
            AddTransition(machineID: "btn", transition: leave, index: 0),
            UpdateTransition(machineID: "btn", index: 0, transition: Transition(from: "idle", to: "off", trigger: "off")),
            RemoveTransition(machineID: "btn", index: 0),
        ]
    }

    /// A transition index of machine `id`, sometimes -1 or the count.
    static func anyIndex(_ e: CommandEngine, _ id: String, _ rng: inout SplitMix64) -> Int {
        let count = e.document.stateMachines.first { $0.id == id }?.transitions.count ?? 0
        return Int.random(in: -1...count, using: &rng)
    }

    /// A transition between states of machine `id` (or "missing"), about 1 in
    /// 5 with a condition on one of its inputs (or "missing").
    static func randomTransition(_ e: CommandEngine, _ id: String, _ rng: inout SplitMix64) -> Transition {
        var t = Transition(from: MachineStateCommandTests.anyState(e, id, &rng),
                           to: MachineStateCommandTests.anyState(e, id, &rng),
                           trigger: "t\(Int.random(in: 0...3, using: &rng))")
        if Int.random(in: 0..<5, using: &rng) == 0 {
            let name = MachineInputCommandTests.anyInput(e, id, &rng)
            let declared = e.document.stateMachines.first { $0.id == id }?.inputs.first { $0.name == name }
            t.conditions = [randomCondition(name, declared?.defaultValue, &rng)]
        }
        return t
    }

    /// A condition on `input` with a value of the `declared` type (a bool for
    /// an undeclared input), 1 in 4 of the other type.
    static func randomCondition(_ input: String, _ declared: InputValue?, _ rng: inout SplitMix64) -> Condition {
        var isNumber = false
        if case .number = declared { isNumber = true }
        if Int.random(in: 0..<4, using: &rng) == 0 { isNumber.toggle() }
        guard isNumber else { return Condition(input: input, op: .equal, value: .bool(Bool.random(using: &rng))) }
        let op = [ConditionOp.equal, .less, .greater].randomElement(using: &rng) ?? .equal
        return Condition(input: input, op: op, value: .number(Double(Int.random(in: -3...3, using: &rng))))
    }

    /// Transition steps. They cope with a document without machines or
    /// transitions: then they name "missing" or a bad index and throw.
    static let undoSteps: [UndoStep] = [
        { e, rng, _ in
            let machine = MachineCommandTests.anyMachine(e, &rng)
            let index: Int? = Bool.random(using: &rng) ? nil : Int.random(in: -2...4, using: &rng)
            try e.perform(AddTransition(machineID: machine, transition: randomTransition(e, machine, &rng), index: index))
        },
        { e, rng, _ in
            let machine = MachineCommandTests.anyMachine(e, &rng)
            let index = anyIndex(e, machine, &rng)
            try e.perform(UpdateTransition(machineID: machine, index: index, transition: randomTransition(e, machine, &rng)))
        },
        { e, rng, _ in
            let machine = MachineCommandTests.anyMachine(e, &rng)
            try e.perform(RemoveTransition(machineID: machine, index: anyIndex(e, machine, &rng)))
        },
    ]
}
