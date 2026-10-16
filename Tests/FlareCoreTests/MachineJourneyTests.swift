// MachineJourneyTests.swift: the state machine feature's six journey steps, in
// order, through one CommandEngine and one MachinePlayer. Every refusal leaves
// the document as it was; undo all gives back the start, redo all the end.
import FlareCore
import Testing

@Suite struct MachineJourneyTests {
    /// Scene "s" (24 frames) and symbol "sym", no machine.
    static func start() -> Document {
        var doc = Fixtures.withSymbol()
        doc.scenes = [Scene(id: "s", name: "S", durationFrames: 24)]
        return doc
    }

    static func state(_ id: String, _ start: Int, _ end: Int) -> MachineState {
        MachineState(id: id, name: id, sceneID: "s", startFrame: start, endFrame: end)
    }

    static func button(_ engine: CommandEngine) -> StateMachine? {
        engine.document.stateMachines.first { $0.id == "button" }
    }

    static func issues(_ engine: CommandEngine) -> [MachineIssue]? {
        button(engine)?.issues(in: engine.document)
    }

    static func unreachable(_ id: String) -> MachineIssue {
        MachineIssue(severity: .warning, message: "\(id) can't be reached from idle", stateID: id)
    }

    /// Performs `command`, expects `expected`, and checks nothing changed.
    static func refuse(_ engine: inout CommandEngine, _ command: some Command, _ expected: CommandError) {
        let before = engine.document
        #expect(throws: expected) { try engine.perform(command) }
        #expect(engine.document == before)
    }

    /// The packet's player script; one trace entry per advance or fire.
    static func trace(_ player: inout MachinePlayer) -> [String] {
        var out: [String] = []
        func note() { out.append("\(player.stateID) \(player.frame)") }
        player.advance(frames: 5); note()
        player.fire("pointerEnter"); note()
        player.advance(frames: 20); note()
        let accepted = player.set("down", to: .bool(true))
        #expect(accepted)
        player.fire("click"); note()
        player.advance(frames: 3); note()
        return out
    }

    @Test func journeyThroughOneEngineAndOnePlayer() throws {
        let start = Self.start()
        var engine = CommandEngine(document: start)

        // 1. Add machine "button" with first state idle: initial, no issues.
        try engine.perform(AddStateMachine(id: "button", name: "Button", firstState: Self.state("idle", 0, 10)))
        #expect(Self.button(engine)?.initialState == "idle")
        #expect(Self.issues(engine) == [])

        // 2. hover and pressed are unreachable until idle <-> hover exist.
        try engine.perform(AddMachineState(machineID: "button", state: Self.state("hover", 11, 19)))
        try engine.perform(AddMachineState(machineID: "button", state: Self.state("pressed", 20, 24)))
        #expect(Self.issues(engine) == [Self.unreachable("hover"), Self.unreachable("pressed")])
        try engine.perform(AddTransition(
            machineID: "button", transition: Transition(from: "idle", to: "hover", trigger: "pointerEnter")))
        try engine.perform(AddTransition(
            machineID: "button", transition: Transition(from: "hover", to: "idle", trigger: "pointerExit")))
        #expect(Self.issues(engine) == [Self.unreachable("pressed")])

        // 3. Input down and hover -> pressed on click when down == true: no issues.
        try engine.perform(AddMachineInput(machineID: "button", input: MachineInput(name: "down", defaultValue: .bool(false))))
        try engine.perform(AddTransition(machineID: "button", transition: Transition(
            from: "hover", to: "pressed", trigger: "click",
            conditions: [Condition(input: "down", op: .equal, value: .bool(true))])))
        #expect(Self.issues(engine) == [])

        // 4. Four refusals; nothing changes on any of them.
        Self.refuse(&engine, RemoveMachineState(machineID: "button", stateID: "hover"), .invalidMachine(MachineIssue(
            severity: .error, message: "transition idle -> hover names an unknown state", transitionIndex: 0)))
        Self.refuse(&engine, RemoveMachineInput(machineID: "button", name: "down"), .invalidMachine(MachineIssue(
            severity: .error, message: "condition names unknown input down", transitionIndex: 2)))
        Self.refuse(&engine, UpdateMachineInput(machineID: "button", input: MachineInput(name: "down", defaultValue: .number(1))),
                    .inputTypeChange("down"))
        Self.refuse(&engine, RemoveMachineState(machineID: "button", stateID: "idle"), .invalidMachine(MachineIssue(
            severity: .error, message: "unknown initial state idle", stateID: "idle")))

        // 5. The player script gives the literal trace, twice.
        let expected = ["idle 5", "hover 11", "hover 13", "pressed 20", "pressed 23"]
        var player = try MachinePlayer(machineID: "button", in: engine.document)
        #expect(Self.trace(&player) == expected)
        var second = try MachinePlayer(machineID: "button", in: engine.document)
        #expect(Self.trace(&second) == expected)
        #expect(player == second)

        // 6. Rename sym to "Bird"; "" is refused.
        try engine.perform(RenameSymbol(symbolID: "sym", name: "Bird"))
        #expect(engine.document.symbols.first { $0.id == "sym" }?.name == "Bird")
        Self.refuse(&engine, RenameSymbol(symbolID: "sym", name: ""), .emptyName)

        // Undo all gives back the start document; redo all gives back the end.
        let end = engine.document
        var undos = 0
        while engine.canUndo {
            try engine.undo()
            undos += 1
        }
        #expect(undos == 8)
        #expect(engine.document == start)
        for _ in 0..<undos { try engine.redo() }
        #expect(engine.document == end)
    }
}
