# Engineering rules

What good code looks like in FlareCore (CLAUDE.md covers picking work and
shipping it). Read this before you write code; check your diff against
`docs/review-rubric.md` before you open a PR.

Each rule names what enforces it. **Gate** means `scripts/ci` fails when the
rule is broken. **Test** names the test that catches it. **Review-only** means
nothing catches it yet, so the reviewer must; an open issue is cited where the
code breaks the rule today. When a review-only rule is broken twice, turn it
into a check or a test instead of repeating it here.

## Layers

FlareCore has four layers. Each depends only on the ones above it. CoreColor, CoreRaster, CoreAsset and CoreCatalog are separate modules (see CLAUDE.md); the compiler enforces their boundaries. CoreCatalog alone may import GRDB, and it maps GRDB's errors to `CatalogError`.

1. **Model**: `Document.swift`, `Fill.swift`, `Path.swift`, `Geometry.swift`,
   `Symbols.swift`, `Instance.swift`, `StateMachine.swift`, `MachineInputs.swift`,
   `ModelError.swift`, `LayerOwner.swift`. Plain values.
2. **Evaluation**: `Easing.swift`, `Timeline.swift`, `Sampling.swift`,
   `ShapeBounds.swift`, `HitTest.swift`. Read the model, never change it.
3. **Commands**: `Command.swift`, `CommandRegistry.swift`, `*Commands.swift`.
   The only code that changes a `Document`.
4. **Format and export**: `FlareFormat.swift`, `StateMachineValidation.swift`,
   `SymbolCycles.swift`, `Export/`.
   Bytes in, bytes out.

- **The model never refers to commands or the format.** No `CommandError`,
  `FormatError`, `Command` or `FlareFormat` in a model file. A model type that
  needs to fail throws `ModelError`, which the command layer maps with
  `CommandError.init(_:)` and the format layer with `FormatError.init(_:)`.
  Test: `ModelErrorTests.modelFilesNameNoUpperLayerType` (keep its file list in
  step with the model list above).
- **One error type per layer, and errors don't cross layers.** Today:
  `ModelError` and `GeometryError` (model), `TimelineError` (evaluation), `CommandError`
  (commands), `FormatError` (format), one per exporter. Add a case to your
  layer's enum before you add an enum. Never throw another layer's error to
  save a case. Review-only.
- **FoundationEssentials only, no Darwin API, no `try!` and friends.** Gate:
  the no-crash lint, and the Linux CI build fails on Darwin-only API.

## Reuse before you write

- **Search for the helper first.** Before you write a function, grep `Sources/`
  for its verb and its math. The usual repeats here: bezier point evaluation
  (`quadAt`/`cubicAt` in `Path.swift` and `quadPoint`/`cubicPoint` in
  `ShapeBounds.swift` are the same code twice), clamping (`min(max(x, lo), hi)`
  in four places), path flattening (`Path.flattened(tolerance:)`), and scene,
  layer or symbol lookup by id (the `Document` extensions beside each command
  family). If the helper is `private` elsewhere, make it `internal` and call
  it. Gate: the jscpd check in `scripts/ci` fails when duplicated lines in
  `Sources/` pass its threshold, which only goes down. Today's clones sit under
  it; that does not make them fine. Remove one, lower the number, same PR.
- **Subtract first.** If a change can delete code, delete it in the same PR.
  When you replace an API, move every caller and delete the old one; no shims
  inside this module. Review-only.

## The document stays valid

- **Every invariant lives in `FlareFormat.validate`.** If a document rule
  matters (unique ids, frames in range, finite sizes, no symbol cycles), it is
  checked there or in a function it calls. A rule that only lives in one
  command's guard is half a rule. Test: `FlareFormatTests`, `FormatLimitsTests`.
- **Commands keep the document valid.** For any valid document, a command that
  succeeds leaves a document that passes `FlareFormat.validate`, and its undo
  does too. Reject bad params with a `CommandError` before you mutate.
  Test: `CommandEngine.perform` validates every result and throws
  `CommandError.invalidDocument` instead of committing a broken one
  (`CommandEngineTests.performRejectsCommandsThatBreakTheFormat`). The guard
  is a backstop, not a substitute for rejecting bad params up front. A command
  that changes only one layer conforms to `LayerCommand` (listed in
  `LayerCommand.swift`) so the check is scoped to that layer; the undo property
  tests validate the whole document after every step to keep the scope honest.
- **Types first, guards second.** When a value can be wrong (a negative
  duration, an empty track), prefer a type that can't hold the wrong value.
  When that is impractical, validate at the boundary (decode, command params)
  and trust the value inside. Review-only.

## Commands

- **Every new command is listed in its family's `all` and every family is in
  `CommandRegistry.builtInFamilies`.** Otherwise it can't be journaled or
  replayed. Test: `CommandRegistryTests.samplesCoverEveryBuiltIn` covers what
  is registered; nothing yet catches a command that was never listed. Q2 (#98).
- **Every new command is a step in `UndoPropertyTests`.** Test:
  `UndoPropertyTests` (only for commands you add there; Q7 (#103) covers the
  families it skips today).
- **Commands encode their params only.** State that `execute` records for
  `undo` stays out of the encoded form (custom `CodingKeys`), so a decoded
  command is a fresh one. Review-only; Q3 (#99) tracks the commands that leak.
- **Old files keep loading.** New model fields decode from files without
  them. Test: `GoldenFileTests` plus the decode test you add.

## Export

- **Exporters cover every model feature.** When you add something drawable
  (a fill kind, a stroke option, instances), the SVG and Lottie exporters
  either draw it or throw a typed "unsupported" error; they never drop it in
  silence. Hit testing and bounds follow the same rule. Review-only; Q4 (#100)
  tracks stroke and instances.

## Tests

- **Test behavior, not wiring.** Call the public API with one concrete input
  and assert the literal result. A test that would still pass if the code under
  test returned a default value proves nothing; rewrite or delete it.
  Review-only.
- **Test across families, not just your slice.** A new command or model field
  also gets exercised with the others: undo after a mix of commands, validate
  after every step, encode and decode after execute. Per-file tests alone
  missed Q1, Q2 and Q7. Review-only until those land.
- **Bug fixes start red.** Write the test that reproduces the bug, see it fail,
  then fix the cause where every caller goes through, not the one path the
  report named. Grep for the same pattern elsewhere and fix those too.
  Review-only.
- **Seeded randomness, fuzz for parsers.** `SplitMix64` only. Anything that
  reads untrusted bytes gets a seeded fuzz test that asserts it throws instead
  of crashing. Review-only; copy the shape of `CommandFuzzTests`.
- **Proof is the gate.** "It compiles" is not done. Gate: `scripts/ci` prints
  `CI: PASS` on your rebased branch; the PR body names the proving test.

## Reading cost

- One idea per file; a new command family gets its own file. No wrapper with
  one caller and no decision in it: inline it. Each file opens with a short
  comment on what it is for now and the invariants a reader must keep; edit it
  when the file changes, history belongs in git. Review-only.
