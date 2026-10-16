# state-machine lead record

Issue: #312 · Packet: docs/blueprints/core/features/state-machine.md (on dev since #310)
Run: act-1a1448178f5-56p5 · Session: claude/state-machine-feature-lead-016ymp (resumed 2026-10-16T11:40Z; earlier ynzph3, 8z5qtw; earlier run act-1a142b4b29a-bnb2) · Started: 2026-10-16T03:16Z
Stage: 4 round 1
Base: 8c445c7 (round 1; wave f 57b645c; wave e 6689fa1; wave d 5cb1494; wave c 670a6ed; wave b f27f104; wave a base 69c9f80 is the feature's first base)
Next: round 1 critic panel running on 69c9f80..8c445c7; then fix batch or round 2

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| SM-1 | a | `MachineIssue`, `StateMachine.issues(in:)`; `validateStateMachines` over it, today's messages; C4 parts, engineering.md lists (closes #220) | StateMachineIssues.swift, StateMachineValidation.swift, StateMachineIssuesTests.swift, FlareMachineIssues.json, c4 parts statemachine + symbols, engineering.md | StateMachineIssuesTests (validateMessagesStayTheSame, 500 seeded machines agree) | FlareMachineIssues.json | #316 | merged |
| SM-2 | a | `RenameSymbol` (closes #226) | SymbolCommands.swift, RenameSymbolTests.swift, SymbolCommandsTests.swift, CommandRegistryTests.swift, FlareRenameSymbol.json | RenameSymbolTests | FlareRenameSymbol.json | #314 | merged |
| SM-3 | b | family + registry line; Add/Rename/Remove StateMachine, SetInitialState; CommandError.stateMachineNotFound, .invalidMachine; machine in sampleDocument (#221 part) | StateMachineCommands.swift, Command.swift, CommandRegistry.swift, MachineCommandTests.swift, CommandRegistryTests.swift, UndoPropertyTests.swift, FlareMachineCommands.json | MachineCommandTests | FlareMachineCommands.json | #330 | merged |
| SM-7 | b | `MachinePlayer`; TimelineError cases; shared internal `firing` (closes #225) | MachinePlayer.swift, StateMachine.swift, Timeline.swift, MachinePlayerTests.swift, FlareMachinePlayer.json | MachinePlayerTests | FlareMachinePlayer.json | #329 | merged |
| SM-4 | c | Add/Update/Remove MachineState; CommandError.stateNotFound; machines in fuzz document (closes #222, #221) | MachineStateCommands.swift, StateMachineCommands.swift, Command.swift, MachineStateCommandTests.swift, CommandRegistryTests.swift, UndoPropertyTests.swift, CommandFuzzTests.swift, FlareMachineStates.json | MachineStateCommandTests | FlareMachineStates.json | #335 | merged |
| SM-5 | d | Add/Update/Remove Transition; invalidIndex doc line (closes #223) | TransitionCommands.swift, StateMachineCommands.swift, Command.swift (doc), TransitionCommandTests.swift, CommandRegistryTests.swift, UndoPropertyTests.swift, FlareTransitions.json | TransitionCommandTests | FlareTransitions.json | #336 | merged |
| SM-6 | e | Add/Update/Remove MachineInput; CommandError.inputNotFound, .inputTypeChange (closes #224) | MachineInputCommands.swift, StateMachineCommands.swift, Command.swift, MachineInputCommandTests.swift, CommandRegistryTests.swift, UndoPropertyTests.swift, FlareMachineInputs.json | MachineInputCommandTests | FlareMachineInputs.json | #337 | merged |
| SM-8 | f | MachineJourneyTests: six journey steps, one engine, one player | MachineJourneyTests.swift | MachineJourneyTests | – | #338 | merged |

Acceptance tests and quality bars: the packet's "Acceptance test per task" and "Quality tests" tables, verbatim.

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|
| 1 | 8c445c7 | PASS on 57b645c (885 tests); SM-8 head PASS (886) | 72/72 (changed since 69c9f80) | 38877588760 green (5cb1494, through SM-4) | clarity, contract, undo, robustness, tests, design | running | – | – |

## Decisions
- Waves follow the packet (a SM-1+SM-2; b SM-3+SM-7; c SM-4; d SM-5; e SM-6; f SM-8): the shared test files chain SM-2 to SM-6.
- Builder branches are `lead/state-machine-<task>`: a nested `lead/state-machine/<task>` cannot coexist with the lead branch.
- #310 merged during setup; wave a starts from 69c9f80 (f05665f + the packet docs only).
- The `feature-done` label goes on the last PR after the Anatomy loop (SM-8 if the loop is clean, else the last fix), so the CI run it triggers covers every fix.
- Resumed after a stall: wave b had merged (#329 SM-7, #330 SM-3) by dev 670a6ed.
- SM-4 (#335) also edited MachineCommandTests (+2 -2): SM-3's test said its ids equal `all`, now a subset. Accepted; later machine tasks may need the same.
- Resumed again (run act-1a1448178f5-56p5): wave d had merged (#336 SM-5) by dev 6689fa1.
- Container restarted mid wave e; #337 (SM-6) had merged by dev 57b645c. #101 told its last family landed.
- Round 1 runs on 57b645c beside the SM-8 build: SM-8 adds only a test file, and builders never wait on critics.
- PRs, labels and comments go through the GitHub MCP tools (no gh auth in cloud sessions).

## Open
- Builders' PR bodies got a server-appended attribution footer; the lane stripped it on merge (#314, #316). Templates now tell builders to PATCH it out.
- The container lacked Swift; scripts/cloud-setup.sh installed 6.3.3. #220-#226 labelled in-progress.
