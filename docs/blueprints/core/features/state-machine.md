# Feature packet: state-machine

**Feature:** state machines Flare can edit and play. A public, non-throwing
issues query that the format's validation and every machine command share;
undoable commands for machines, states, transitions and inputs; a
deterministic runtime player; and `RenameSymbol`.
**Line:** `line:core` · **Wave:** 2 (`waves.md`) · **Lead branch:** `lead/state-machine`

**Covers:** #220 (LC-11a), #221 (LC-11b), #222 (LC-11c), #223 (LC-11d),
#224 (LC-11e), #225 (LC-12), #226 (LC-12b). #220 closes with SM-1, #226 with
SM-2, #221 with SM-3, #225 with SM-7, #222 with SM-4, #223 with SM-5, #224
with SM-6. It also finishes #101 (Q5): Q5a to Q5e are closed, and of the
command families #101 lists, only the state machine family is still
missing; the lead comments on #101 when SM-6 merges, and the captain closes
it.

**Unblocks:** Flare (qbtrix/creative-apps `docs/blueprints/flare.md`
section 7.5): LM-10 `LiveLibrary` (needs LC-12b), LM-11 `LiveMachines`
(needs LC-11a to LC-11e) and LM-12 `LivePreview` (needs LC-12), which IN-5
and IN-6 then make live.

**Depends on:** nothing open. Base: `origin/dev` f05665f. The issues'
`Depends on: #217 (LC-8)` is done (edit-commands closed it), and their
LC-11b after LC-8 order was one registry line each, which `dev`'s
per-family command lists removed.

**Source:** Flare blueprint section 7.4 (rows LC-11a to LC-12b) and its
model contracts `StateMachineEditing` and `StateMachinePreviewing` (section
6.2, `Contracts/InteractContracts.swift`), which say what the app calls. Where
an issue body and this packet differ, this packet wins.

**Existing work:** no open PR or branch covers these issues (checked against
`origin/dev` f05665f on 2026-10-16). The model is on `dev` since #85, #90 and
#91: `StateMachine`, `MachineState`, `Transition`, `MachineInput`,
`Condition`, `next(from:trigger:inputs:)`, and `validateStateMachines` in
`StateMachineValidation.swift`, which throws on the first broken rule. No
command touches `Document.stateMachines` today.

## Journey steps

Proven through a real `CommandEngine` on a scene `s` of 24 frames (the
`StateMachineTests.document()` shape), each undo exact:

1. Add machine "button" with first state `idle` (frames 0 to 10): it is the
   initial state and `issues` is empty.
2. Add states `hover` (11 to 24) and `pressed`: `issues` warns that each
   can't be reached from `idle`. Add transitions `idle -> hover` on
   `pointerEnter` and `hover -> idle` on `pointerExit`: the `hover` warning
   goes.
3. Add input `down` (bool, false) and a transition `hover -> pressed` on
   `click` when `down == true`: no issues.
4. Removing `hover` is refused and the refusal names transition 0; removing
   `down` is refused and names transition 2; updating `down` to a number is
   refused; removing `idle` is refused because it is the initial state.
   Nothing changes on any refusal.
5. A player started on "button" runs the script advance 5, fire
   `pointerEnter`, advance 20, set `down` true, fire `click`, advance 3 and
   gives the same frame trace on every run.
6. Rename symbol `sym` to "Bird"; "" is refused. Undo all gives back the
   start document.

## Screens and states

The "screens" are the issues query, the four command kinds and the player.
Every command rejects bad params with a `CommandError` before it changes
anything; `CommandEngine.perform`'s validation stays the backstop.

| Screen | Empty | Error | Loading |
|---|---|---|---|
| `issues(in:)` | a valid machine with every state reachable: `[]` | never throws. Each broken rule `validateStateMachines` checks today is an `.error` issue with today's wording, in today's order; a state the initial state can't reach is a `.warning` on that state | – |
| Machine commands | – | missing machine `stateMachineNotFound`; an id in use `duplicateID`; an empty name `emptyName`; a first state or initial state that breaks a rule `invalidMachine(issue)` | – |
| State commands | – | missing state `stateNotFound`; removing a state a transition names, or the initial state, `invalidMachine(issue)` whose issue names that transition or state; a bad scene or frame range `invalidMachine(issue)` | – |
| Transition commands | – | an index out of range `invalidIndex`; a `from` or `to` that names no state, or a condition that breaks a rule, `invalidMachine(issue)` | – |
| Input commands | – | missing input `inputNotFound`; a duplicate name or a non-finite default `invalidMachine(issue)`; an update to another type `inputTypeChange`; removing an input a condition uses `invalidMachine(issue)` naming that transition | – |
| `RenameSymbol` | – | missing symbol `symbolNotFound`; "" `emptyName` | – |
| `MachinePlayer` | a trigger no transition takes, or an unknown one: nothing changes | a missing machine `TimelineError.machineNotFound`; a machine with an error issue `TimelineError.invalidMachine(issue)`; `set` of an unknown input, another type or a non-finite number returns false and changes nothing; `advance` by 0 or less changes nothing | – |

## Contract slice

New public API. Names are binding for the lead and builders; doc comments
may add, not rename.

```swift
// StateMachineIssues.swift (SM-1), evaluation layer: reads the model, never changes it
public struct MachineIssue: Sendable, Hashable {
    public enum Severity: String, Sendable, Hashable { case error, warning }
    public var severity: Severity
    /// The rule, worded as `FlareFormat.validate` words it after "state machine <id>: ".
    public var message: String
    public var stateID: String?          // the state the issue is about, when there is one
    public var transitionIndex: Int?     // the transition, when there is one
}
extension StateMachine {
    /// Every rule `FlareFormat.validate` checks on this machine, as errors in
    /// the order it checks them, then one warning per state the initial
    /// state can't reach (any trigger, any condition). Never throws.
    public func issues(in document: Document) -> [MachineIssue]
}
// StateMachineValidation.swift (SM-1): validateStateMachines keeps only the
// duplicate machine id check and throws
// FormatError.invalid("state machine \(id): \(first error's message)").

// One new family, StateMachineCommands.all, in StateMachineCommands.swift;
// SM-3 adds its line to CommandRegistry.builtInFamilies and SM-4 to SM-6
// append their types to that `all`. Ids are "machine.<verb>".
public struct AddStateMachine: Command      // "machine.add";         id, name, firstState: MachineState (becomes initialState)
public struct RenameStateMachine: Command   // "machine.rename";      machineID, name
public struct RemoveStateMachine: Command   // "machine.remove";      machineID
public struct SetInitialState: Command      // "machine.setInitial";  machineID, stateID
// MachineStateCommands.swift (SM-4)
public struct AddMachineState: Command      // "machine.addState";    machineID, state
public struct UpdateMachineState: Command   // "machine.updateState"; machineID, state (found by state.id; replaces name, scene, range)
public struct RemoveMachineState: Command   // "machine.removeState"; machineID, stateID
// TransitionCommands.swift (SM-5)
public struct AddTransition: Command        // "machine.addTransition";    machineID, transition, index: Int? (nil appends; clamped, as AddSymbol)
public struct UpdateTransition: Command     // "machine.updateTransition"; machineID, index, transition
public struct RemoveTransition: Command     // "machine.removeTransition"; machineID, index
// MachineInputCommands.swift (SM-6)
public struct AddMachineInput: Command      // "machine.addInput";    machineID, input
public struct UpdateMachineInput: Command   // "machine.updateInput"; machineID, input (found by name; same type, new default)
public struct RemoveMachineInput: Command   // "machine.removeInput"; machineID, name
// SymbolCommands.swift (SM-2): in SymbolCommands.all
public struct RenameSymbol: Command         // "symbol.rename";       symbolID, name

// Command.swift: CommandError gains, each in the task that first throws it,
//   stateMachineNotFound(String), invalidMachine(MachineIssue)   (SM-3)
//   stateNotFound(String)                                        (SM-4)
//   inputNotFound(String), inputTypeChange(String)               (SM-6)
// and the `invalidIndex` doc comment adds "a transition index" (SM-5).

// MachinePlayer.swift (SM-7), evaluation layer
public struct MachinePlayer: Sendable, Hashable {
    public init(machineID: String, in document: Document) throws  // starts at the initial state's startFrame, inputs at their defaults
    public let machine: StateMachine
    public private(set) var stateID: String
    public private(set) var frame: Int                  // a scene frame in the current state's startFrame...endFrame
    public private(set) var inputs: [String: InputValue]
    public mutating func set(_ input: String, to value: InputValue) -> Bool
    public mutating func fire(_ trigger: String)        // a transition that fires restarts its target at startFrame, itself included
    public mutating func advance(frames count: Int)     // loops the current state's range
}
// Timeline.swift (SM-7): TimelineError gains machineNotFound(String) and invalidMachine(MachineIssue).
// StateMachine.swift (SM-7): one internal `firing(from:trigger:inputs:) -> Transition?`
// that `next` and the player share, so the first-match rule lives once.
```

**One rule set.** Every machine command applies its edit to a copy of the
machine, runs `issues(in:)` on it, and throws the first `.error` as
`invalidMachine(issue)` before it touches the document. So a command and the
format can never disagree on a rule, which is the drift the stage-geometry
critic panel found in other command code (#305). The issue carries the
transition index or state id, which is how "the refusal names the
transition" (LC-11c, LC-11e) is met, and what Flare's inline refusal reads.
Only `inputTypeChange` is a command rule with no format twin: validation
allows any default type, but the blueprint's update keeps the kind.

**Layers.** `StateMachineIssues.swift` and `MachinePlayer.swift` are
evaluation files. The format layer calls `issues(in:)`; commands carry a
`MachineIssue` in their error. Neither is a model file, so
`ModelErrorTests.modelFilesNameNoUpperLayerType` is unchanged.

## Pseudocode

```
SM-1 issues(in doc):
  durations = scene id -> durationFrames; out = []
  for state in states (in order): dup id -> error(stateID); unknown scene -> error(stateID), skip its range;
      bad range (start < 0, start > end, end > duration) -> error(stateID)
  initialState not a state -> error(stateID: initialState)
  for input in inputs: dup name -> error; non-finite default -> error      # first of a name wins
  for (i, t) in transitions: from or to unknown -> error(transitionIndex: i)
      for c in t.conditions: unknown input -> error(i); wrong type or non-finite -> error(i);
          bool with < or > -> error(i)
  reach = breadth-first from initialState over every transition
  for state not in reach -> warning("<id> can't be reached from <initial>", stateID)
validateStateMachines: dup machine id throw; if let e = first error of machine.issues(in: doc) throw "state machine <id>: <e.message>"

SM-3..SM-6 every machine command:
  i = machine index or throw stateMachineNotFound
  var m = doc.stateMachines[i]; apply the edit to m (not found -> its own error)
  if let e = m.issues(in: doc).first(severity == .error) throw invalidMachine(e)
  record what undo needs (the old machine part and its index); doc.stateMachines[i] = m
  undo: put the recorded part back at its index; encode params only (CodingKeys)

SM-7 player:
  init: machine = doc machine or throw machineNotFound; error issue -> throw invalidMachine
        stateID = initialState; frame = its startFrame; inputs = defaults
  fire(t): if let tr = machine.firing(from: stateID, trigger: t, inputs: inputs) { stateID = tr.to; frame = start(tr.to) }
  advance(n): guard n > 0; len = end - start + 1; frame = start + ((frame - start) + n % len) % len   # no overflow
  set(name, v): guard declared, same type, finite else false; inputs[name] = v; true
```

## Tasks

Every task is one PR to `dev`: at most 400 changed lines and 15 files, label
`fast-lane`, body lines `Belt-Lead:`, `Feature: state-machine`,
`Fast-Check: pass`, `Head:`. SM-8 also carries `feature-done`.

**Shared test files.** `CommandRegistryTests.swift` (`expectedIDs`, its
count of 44, the samples and `sampleDocument`) and `UndoPropertyTests.swift`
are edited by SM-2 to SM-6, and `StateMachineCommands.swift`'s `all` by SM-3
to SM-6, so they form one chain, SM-2 → SM-3 → SM-4 → SM-5 → SM-6, each
rebased on the one before. SM-3 also gives `sampleDocument` a machine (so
every machine sample is valid on it) and `CommandFuzzTests.randomDocument`
zero to two random machines (so fuzzed machine commands hit real machines);
the fuzz templates come from the registry samples, so SM-4 to SM-6 are
fuzzed by adding samples. SM-1 and SM-7 touch neither and run beside the
chain.

**Mutation plans.** Each task puts its entries in its own plan file. No
entry in `Tests/mutations/*.json` anchors a file this feature edits except
the ones it creates, so no repointing.

**C4 and docs.** SM-1 is the only task here that edits C4 parts or
`docs/engineering.md`. It adds `StateMachineIssues.swift`,
`StateMachineCommands.swift`, `MachineStateCommands.swift`,
`TransitionCommands.swift`, `MachineInputCommands.swift` and
`MachinePlayer.swift` to the `statemachine` part's paths (paths that don't
exist yet are fine) with a description that names the issues query, the
commands and the player; adds "rename" to the `symbols` description; and
adds `StateMachineIssues.swift`, `MachinePlayer.swift` and, for
`motion-tracks`, `Onion.swift` to engineering.md's evaluation list.

| id | issue | what | owned files | depends on | size |
|---|---|---|---|---|---|
| SM-1 | #220 (closes) | `MachineIssue`, `StateMachine.issues(in:)`; `validateStateMachines` over it with today's messages; C4 parts and the engineering.md lists | `Sources/FlareCore/StateMachineIssues.swift`, `Sources/FlareCore/StateMachineValidation.swift`, `Tests/FlareCoreTests/StateMachineIssuesTests.swift`, `Tests/mutations/FlareMachineIssues.json`, `docs/c4/parts/creative-core/flarecore/statemachine.json`, `docs/c4/parts/creative-core/flarecore/symbols.json`, `docs/engineering.md` | – | ~320 |
| SM-2 | #226 (closes) | `RenameSymbol` | `Sources/FlareCore/SymbolCommands.swift`, `Tests/FlareCoreTests/RenameSymbolTests.swift`, `Tests/FlareCoreTests/SymbolCommandsTests.swift` (its samples and `undoSteps`), `Tests/FlareCoreTests/CommandRegistryTests.swift`, `Tests/mutations/FlareRenameSymbol.json` | – | ~140 |
| SM-3 | #221 (closes) | The family and its line in `builtInFamilies`; `AddStateMachine`, `RenameStateMachine`, `RemoveStateMachine`, `SetInitialState`; `CommandError.stateMachineNotFound` and `.invalidMachine`; a machine in `sampleDocument` and in the fuzz document | `Sources/FlareCore/StateMachineCommands.swift`, `Sources/FlareCore/Command.swift`, `Sources/FlareCore/CommandRegistry.swift`, `Tests/FlareCoreTests/MachineCommandTests.swift`, `Tests/FlareCoreTests/CommandRegistryTests.swift`, `Tests/FlareCoreTests/UndoPropertyTests.swift`, `Tests/FlareCoreTests/CommandFuzzTests.swift`, `Tests/mutations/FlareMachineCommands.json` | SM-1, SM-2 (test chain) | ~360 |
| SM-4 | #222 (closes) | `AddMachineState`, `UpdateMachineState`, `RemoveMachineState`; `CommandError.stateNotFound` | `Sources/FlareCore/MachineStateCommands.swift`, `Sources/FlareCore/StateMachineCommands.swift` (its `all`), `Sources/FlareCore/Command.swift`, `Tests/FlareCoreTests/MachineStateCommandTests.swift`, `Tests/FlareCoreTests/CommandRegistryTests.swift`, `Tests/FlareCoreTests/UndoPropertyTests.swift`, `Tests/mutations/FlareMachineStates.json` | SM-3 | ~280 |
| SM-5 | #223 (closes) | `AddTransition`, `UpdateTransition`, `RemoveTransition`; the `invalidIndex` doc line | `Sources/FlareCore/TransitionCommands.swift`, `Sources/FlareCore/StateMachineCommands.swift` (its `all`), `Sources/FlareCore/Command.swift` (doc comment only), `Tests/FlareCoreTests/TransitionCommandTests.swift`, `Tests/FlareCoreTests/CommandRegistryTests.swift`, `Tests/FlareCoreTests/UndoPropertyTests.swift`, `Tests/mutations/FlareTransitions.json` | SM-4 | ~260 |
| SM-6 | #224 (closes) | `AddMachineInput`, `UpdateMachineInput`, `RemoveMachineInput`; `CommandError.inputNotFound` and `.inputTypeChange` | `Sources/FlareCore/MachineInputCommands.swift`, `Sources/FlareCore/StateMachineCommands.swift` (its `all`), `Sources/FlareCore/Command.swift`, `Tests/FlareCoreTests/MachineInputCommandTests.swift`, `Tests/FlareCoreTests/CommandRegistryTests.swift`, `Tests/FlareCoreTests/UndoPropertyTests.swift`, `Tests/mutations/FlareMachineInputs.json` | SM-5 | ~280 |
| SM-7 | #225 (closes) | `MachinePlayer`; `TimelineError.machineNotFound` and `.invalidMachine`; the shared internal `firing` | `Sources/FlareCore/MachinePlayer.swift`, `Sources/FlareCore/StateMachine.swift`, `Sources/FlareCore/Timeline.swift`, `Tests/FlareCoreTests/MachinePlayerTests.swift`, `Tests/mutations/FlareMachinePlayer.json` | SM-1 | ~260 |
| SM-8 | – | `MachineJourneyTests`: the six journey steps through one engine and one player; `feature-done` | `Tests/FlareCoreTests/MachineJourneyTests.swift` | SM-6, SM-7 | ~180 |

Build waves inside the feature: **a** SM-1, SM-2; **b** SM-3, SM-7; **c**
SM-4; **d** SM-5; **e** SM-6; **f** SM-8. After **a**, #220 and #226 are
closed (LM-10 can start once `main` holds SM-2); after **b**, #221 and #225;
after **e**, #222, #223, #224, and LM-11 and LM-12 can start once `main`
holds them.

## Acceptance test per task

| id | test | fails when |
|---|---|---|
| SM-1 | `StateMachineIssuesTests`: every existing `StateMachineTests` and `MachineInputTests` validation test passes; `validateMessagesStayTheSame`: for each case of `badReferenceThrows` (8) and `validationRejects` (4), and a non-finite default, `FlareFormat.validate` throws `FormatError.invalid` with the exact text recorded from `dev` before the change; an unreachable state is one `.warning` on that state and validate passes; a transition to an unknown state is an `.error` with its `transitionIndex`; a seeded run of 500 random machines (`SplitMix64`) agrees: validate throws exactly when `issues` has an error, with the first error's message | a message changes, the order changes which error comes first, a warning blocks validate, or an issue loses its index |
| SM-2 | `RenameSymbolTests`: rename and undo exact; "" throws `emptyName`; a missing id throws `symbolNotFound`; the command is in `SymbolCommands.all`, sampled, and in `SymbolCommandsTests.undoSteps` | an empty name lands or undo is inexact |
| SM-3 | `MachineCommandTests`: add, rename, remove and set initial, each undo exact; remove then undo puts the machine back at its index; add with an id in use throws `duplicateID`; "" throws `emptyName`; a first state on a missing scene throws `invalidMachine` with that state's id; set initial to an unknown state throws `invalidMachine`; the family is registered, sampled and in the mixed `UndoPropertyTests`; `CommandFuzzTests` runs with machines in its random documents | a refusal changes the document, undo is inexact, or the fuzz never reaches a machine |
| SM-4 | `MachineStateCommandTests`: add, update and remove a state, each undo exact; removing a state that transition 1 names throws `invalidMachine` whose issue has `transitionIndex == 1`; removing the initial state throws `invalidMachine` naming it; an update past the scene's duration throws; a missing state throws `stateNotFound`; sampled and in `UndoPropertyTests` | the refusal does not name the transition, or a dangling transition is committed |
| SM-5 | `TransitionCommandTests`: add (append and at an index), update and remove, each undo exact; an update whose `to` names an unknown state throws `invalidMachine`; index -1 and count throw `invalidIndex`; a condition on an unknown input throws; sampled and in `UndoPropertyTests` | an update to an unknown state lands, or undo puts a transition back at another index |
| SM-6 | `MachineInputCommandTests`: add, update default and remove, each undo exact; an update from bool to number throws `inputTypeChange`; removing an input a condition of transition 2 uses throws `invalidMachine` with `transitionIndex == 2`; a duplicate name and a NaN default throw; sampled and in `UndoPropertyTests` | a kind change lands, or a condition is left naming a missing input |
| SM-7 | `MachinePlayerTests`: on the button machine of `StateMachineTests.document()`, the script advance 5, fire `pointerEnter`, advance 20, fire `pointerExit`, advance 3 gives the trace `idle 5`, `hover 11`, `hover 17`, `idle 0`, `idle 3`, and the same trace on a second player; a self-transition restarts its state at `startFrame`; an unknown trigger and `advance(0)` change nothing; `advance(Int.max)` stays in range; `set` of an unknown input, another type or NaN returns false; a missing machine and a machine with an error issue throw; `next(from:trigger:inputs:)` still passes every `StateMachineTests` and `MachineInputTests` case | the trace differs between runs, a frame leaves its range, or the first-match rule differs between `next` and the player |
| SM-8 | `MachineJourneyTests`: the six journey steps above in order, on one engine, then undo all gives back the start document and redo all gives back the end | any step's refusal changes the document, or the trace or the final document differs |

## Quality tests

| quality row | budget | test |
|---|---|---|
| Deterministic replay (blueprint, LC-12) | the same input script gives the same frame trace, twice and against a literal | `MachinePlayerTests`, `MachineJourneyTests` |
| Undo stays exact across families | the mixed property runs every machine command with every old one | `UndoPropertyTests` (seeded `SplitMix64`) |
| Untrusted envelopes never crash | every new id gets fuzzed params on random documents that hold machines | `CommandFuzzTests`, `CommandRegistryTests.everyBuiltInRoundTripsAndBehavesTheSame` |
| One rule set | `issues` and `validate` agree on 500 seeded machines | `StateMachineIssuesTests` |
| Old files keep loading | no model field is added; validation messages unchanged | `StateMachineIssuesTests.validateMessagesStayTheSame`, `GoldenFileTests` |
| Drag steps stay cheap | `validateStateMachines` now runs `issues` on every perform; QB-L7 still holds | `DragStepBudgetTests` (unchanged, must stay green) |
| Mutation | every entry in the feature's plan files is caught | `scripts/mutate --run --changed-since <first base>`, run by the lead |

## Done check

- **Journeys green:** `scripts/ci` prints `CI: PASS` on the `dev` SHA that
  holds every merged task, and the CI run on `dev` the `feature-done` PR
  (SM-8) triggers is green (Linux, macOS on Swift 6.1, Mutation).
- **Audit zero new:** no new no-crash lint hit, the jscpd threshold not
  raised (the rules live once, in `issues`), `scripts/mutate --validate`
  clean, no escaped mutant.
- **Contact sheet:** `Belt-Contact-Sheet: <run link>` on the feature issue,
  one line per acceptance test above, and the test and mutation counts; a
  comment on #101 that its last open family landed.
