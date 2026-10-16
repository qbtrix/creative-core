# state-machine lead record

Issue: #312 · Packet: docs/blueprints/core/features/state-machine.md (on dev since #310)
Run: act-1a142b4b29a-bnb2 · Session: claude/state-machine-feature-lead-8z5qtw · Started: 2026-10-16T03:16Z
Stage: 3 wave a
Base: 69c9f80df6d02f0cea518549e22133bef891efec (dev after #310 merged the packet; brief base f05665f verified first)
Next: wait for the wave-a builders (SM-1, SM-2) to open their PRs, then for the lane to merge them

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| SM-1 | a | `MachineIssue`, `StateMachine.issues(in:)`; `validateStateMachines` over it, today's messages; C4 parts, engineering.md lists (closes #220) | StateMachineIssues.swift, StateMachineValidation.swift, StateMachineIssuesTests.swift, FlareMachineIssues.json, c4 parts statemachine + symbols, engineering.md | StateMachineIssuesTests (validateMessagesStayTheSame, 500 seeded machines agree) | FlareMachineIssues.json | – | building |
| SM-2 | a | `RenameSymbol` (closes #226) | SymbolCommands.swift, RenameSymbolTests.swift, SymbolCommandsTests.swift, CommandRegistryTests.swift, FlareRenameSymbol.json | RenameSymbolTests | FlareRenameSymbol.json | – | building |
| SM-3 | b | family + registry line; Add/Rename/Remove StateMachine, SetInitialState; CommandError.stateMachineNotFound, .invalidMachine; machine in sampleDocument (#221 part) | StateMachineCommands.swift, Command.swift, CommandRegistry.swift, MachineCommandTests.swift, CommandRegistryTests.swift, UndoPropertyTests.swift, FlareMachineCommands.json | MachineCommandTests | FlareMachineCommands.json | – | waits SM-1, SM-2 |
| SM-7 | b | `MachinePlayer`; TimelineError cases; shared internal `firing` (closes #225) | MachinePlayer.swift, StateMachine.swift, Timeline.swift, MachinePlayerTests.swift, FlareMachinePlayer.json | MachinePlayerTests | FlareMachinePlayer.json | – | waits SM-1 |
| SM-4 | c | Add/Update/Remove MachineState; CommandError.stateNotFound; machines in fuzz document (closes #222, #221) | MachineStateCommands.swift, StateMachineCommands.swift, Command.swift, MachineStateCommandTests.swift, CommandRegistryTests.swift, UndoPropertyTests.swift, CommandFuzzTests.swift, FlareMachineStates.json | MachineStateCommandTests | FlareMachineStates.json | – | waits SM-3 |
| SM-5 | d | Add/Update/Remove Transition; invalidIndex doc line (closes #223) | TransitionCommands.swift, StateMachineCommands.swift, Command.swift (doc), TransitionCommandTests.swift, CommandRegistryTests.swift, UndoPropertyTests.swift, FlareTransitions.json | TransitionCommandTests | FlareTransitions.json | – | waits SM-4 |
| SM-6 | e | Add/Update/Remove MachineInput; CommandError.inputNotFound, .inputTypeChange (closes #224) | MachineInputCommands.swift, StateMachineCommands.swift, Command.swift, MachineInputCommandTests.swift, CommandRegistryTests.swift, UndoPropertyTests.swift, FlareMachineInputs.json | MachineInputCommandTests | FlareMachineInputs.json | – | waits SM-5 |
| SM-8 | f | MachineJourneyTests: six journey steps, one engine, one player | MachineJourneyTests.swift | MachineJourneyTests | – | – | waits SM-6, SM-7 |

Acceptance tests and quality bars: the packet's "Acceptance test per task" and "Quality tests" tables, verbatim.

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|

## Decisions
- Waves follow the packet (a SM-1+SM-2; b SM-3+SM-7; c SM-4; d SM-5; e SM-6; f SM-8): the shared test files chain SM-2 to SM-6.
- Builder branches are `lead/state-machine-<task>`: a nested `lead/state-machine/<task>` cannot coexist with the lead branch.
- #310 merged during setup; wave a starts from 69c9f80 (f05665f + the packet docs only).
- The `feature-done` label goes on the last PR after the Anatomy loop (SM-8 if the loop is clean, else the last fix), so the CI run it triggers covers every fix.
- PRs, labels and comments go through the GitHub MCP tools (no gh auth in cloud sessions).

## Open
- The container lacked Swift; scripts/cloud-setup.sh installed 6.3.3. #220-#226 labelled in-progress.
