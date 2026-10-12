<!-- Q5 design proposal (#101): how a command names a layer that lives in a scene or in a symbol. Options, recommendation, migration, tests and the issue breakdown. Proposal only; nothing here is built. -->
# Q5: editing symbol layers through commands

**Issue:** #101 · **Status:** proposal, waiting on a design call · **Date:** 2026-10-12

## 1. Problem

Layers live in two places, `Scene.layers` and `Symbol.layers` (`Document.swift:106`, `:125`). Commands can only reach the first.

- `Document.withLayer(scene:layer:)` looks only in `scenes` (`Document.swift:405-411`). `withEditableLayer` wraps it (`:417-422`). The 18 commands listed in `LayerCommand.swift:5-25` all go through these two, or around them.
- `AddLayer` and `RemoveLayer` index `document.scenes[s].layers` directly (`Commands.swift:36-49`, `:69-81`). So does `ReorderLayer.move` (`LayerCommands.swift:84-93`).
- The `LayerCommand` protocol requires `sceneID` (`Command.swift:53-57`), and `perform` hands it to the scoped validator (`Command.swift:154-155`).
- The scoped validator from #109 finds the layer list only in `scenes` (`FlareFormat.swift:116-119`). A symbol layer would fall back to the full `validate`. That is correct, but it brings back the O(document) cost #109 removed.
- `MoveKeyframe.merge` and `TranslateShape.merge` compare `sceneID` (`Commands.swift:183`, `ShapeCommands.swift:133`).

The failure on main today:

```swift
var e = CommandEngine(document: Fixtures.document())
try e.perform(ConvertToSymbol(sceneID: "s1", layerIDs: ["ball"], symbolID: "sym", name: "Sym"))
try e.perform(SetKeyframe(sceneID: "sym", layerID: "ball", property: "x",
                          keyframe: Keyframe(frame: 3, value: 10)))
// throws CommandError.sceneNotFound("sym"): sceneIndex never looks in symbols (Document.swift:396-401)
```

After `ConvertToSymbol` the moved layers are frozen. No command can key, rename, lock or reorder them, or add a layer beside them.

The issue also lists model parts with no command at all (families in `CommandRegistry.swift:25-37`):

- instances: only `ConvertToSymbol` creates one (`SymbolCommands.swift:137`); nothing adds, removes or moves one
- shape stroke: `ShapeCommands.all` has no stroke command (`ShapeCommands.swift:13`)
- canvas size and background: `SceneCommands.all` is add, remove and timing (`SceneCommands.swift:12`)
- state machines: no family

Only instances and stroke are layer content, so only they depend on this decision.

**Nested symbols need no path.** `Document.symbols` is a flat list (`Document.swift:28`), and an instance names its symbol by id (`Instance.swift:25`). Nesting exists only while drawing, through `Instance.resolve` (`Symbols.swift:51-57`). Editing a symbol at any depth edits its one definition, so a symbol id plus a layer id is a complete address. Per-instance overrides would need a path. The model has none, and this proposal adds none.

## 2. Options

### A. Tag the owner of the layer list

One model enum says where a layer list lives. Commands carry it in place of `sceneID`, next to the `layerID` they already have.

```swift
// LayerOwner.swift, model layer
public enum LayerOwner: Codable, Sendable, Hashable, CustomStringConvertible {
    case scene(String)
    case symbol(String)
    public var description: String        // "scene s1", "symbol sym": today's owner strings
}

extension Document {
    /// The one resolver. Throws ModelError.sceneNotFound or .symbolNotFound.
    mutating func withLayers<T>(_ owner: LayerOwner, _ body: (inout [Layer]) throws -> T) throws -> T
    func layers(of owner: LayerOwner) -> [Layer]?                     // read-only, for validation
    mutating func withLayer<T>(_ owner: LayerOwner, layer: String, _ body: (inout Layer) throws -> T) throws -> T
    mutating func withEditableLayer<T>(_ owner: LayerOwner, layer: String, _ body: (inout Layer) throws -> T) throws -> T
}

try e.perform(SetKeyframe(owner: .symbol("sym"), layerID: "ball", property: "x", keyframe: k))
```

- **Command families.** The 18 layer, keyframe, shape and text commands swap `sceneID` for `owner`. Most only change their `withLayer` calls. `AddLayer`, `RemoveLayer` and `ReorderLayer` move onto `withLayers`. The two `merge` guards compare `owner`. The text helpers `editText` and `restoreText` (`TextCommands.swift:27-46`) take an owner. Scene-only commands (guides, labels, timing, add and remove scene, `ConvertToSymbol`) keep `sceneID`.
- **Journal and registry encoding.** Flat keys. A scene owner writes `"sceneID"`, a symbol owner writes `"symbolID"`, beside `"layerID"`. `LayerOwner.init(from:)` reads exactly one of the two from the command's own decoder. Both or neither throws, and the registry turns that into `malformedCommand` (`CommandRegistry.swift:64-67`). Scene envelopes stay byte-identical, so old journals decode and `encodedCommandCarriesParamsOnly` (`CommandRegistryTests.swift:110-116`) passes unedited. The cost: each of the 18 commands hand-writes `init(from:)` and `encode(to:)`, about 9 lines each, because synthesized Codable would nest the owner. A scratch script on Swift 6.3 (macOS) confirmed that two keyed containers on one encoder merge into one params object through the registry's `superEncoder` path (`CommandRegistry.swift:116`). Q5a's test proves it on Linux.
- **Validation.** `validate(_:layer:scene:since:)` (`FlareFormat.swift:113-137`) becomes `validate(_:layer:owner:since:)` and reads both lists with `layers(of:)`. Messages use `owner.description`, today's `"scene \(id)"` form (`:122`, `:126`). Cycle checks already run on every scoped call (`:135`), so an `AddLayer` that puts an instance of `sym` inside `sym` is still rejected.
- **Undo.** The owner is a param, so undo resolves the same list. No new undo state. Undo is LIFO, so a later `RemoveSymbol` is undone before an earlier edit to that symbol's layers.
- **Errors.** The resolver is model code, so it needs `ModelError.symbolNotFound`. Both exhaustive mappers grow one case (`Command.swift:103-110`, `FlareFormat.swift:30-35`). `Document.symbolIndex` throws `CommandError` from a Document extension today (`SymbolCommands.swift:20-23`); it moves beside `sceneIndex` (`Document.swift:396-401`) and throws the model error.
- **Apps.** `FlareWorkspace` holds `selectedSceneID: String?` (creative-apps `Sources/FlareModel/FlareWorkspace.swift:15`). It becomes `editing: LayerOwner?`. Double-clicking an instance sets `.symbol(id)`. The timeline lists `document.layers(of: editing)`, and every command the canvas builds passes `owner: editing`. The breadcrumb back to the scene is app state only.
- **AI agents.** One command set covers both places. The S4 catalog (`docs/design/suite.md:158`) describes the owner as "exactly one of sceneID, symbolID". Each envelope stays self-contained, which S5 replay needs (`suite.md:159`).

### B. A `LayerContainer` protocol over Scene and Symbol

```swift
public protocol LayerContainer { var id: String { get }; var layers: [Layer] { get set } }
extension Scene: LayerContainer {}
extension Symbol: LayerContainer {}
try e.perform(SetKeyframe(containerID: "sym", layerID: "ball", property: "x", keyframe: k))
```

Conformance is free: both types already have `id` and `layers`. But a bare id is ambiguous. Scene ids and symbol ids are checked in two separate sets (`FlareFormat.swift:141-143`, `:156-158`), so a valid file can hold a scene "a" and a symbol "a" today. B must either add a cross-kind uniqueness rule, which rejects files that load now, or search scenes first, which makes symbol "a" unreachable. A kind tag fixes it, and then B is A plus a protocol nobody calls generically: the validator already works on `[Layer]` (`FlareFormat.swift:176`).

- Command families, undo, apps: as in A.
- Encoding: a new `containerID` key, so every scene envelope changes bytes and each command needs a `sceneID` fallback decoder to read old journals.
- Validation: same rewrite as A, plus the uniqueness rule if B keeps bare ids.
- Agents: the catalog cannot say which kind an id names.

### C. Symbol-edit mode

An "edit symbol" command switches context. Layer commands keep `sceneID` and resolve against the current mode.

- **Where the mode lives.** `execute` gets only `inout Document` (`Command.swift:37`), and the engine holds no context (`Command.swift:118-132`). The mode would sit in the `Document`, so UI state lands in `.flare` files and in `validate`.
- **Journal.** Decoded commands stay fresh (`Command.swift:26-27`), but what a `keyframe.set` with `sceneID: "s1"` edits now depends on earlier envelopes. A partial journal replays wrong.
- **Undo.** Undoing a symbol edit after leaving the mode must still hit the symbol, so each command records its real target anyway. That is A through the back door.
- **Agents.** They must track hidden state that the catalog cannot describe.
- **Stateless variant.** A `symbol.edit {symbolID, command}` wrapper runs an inner scene command on a scratch scene that holds the symbol's layers. No command changes, but the inner command carries a dummy `sceneID`, errors name a scene that does not exist, the wrapper must forward `merge` and scoped validation, and every layer can be addressed two ways.

C's user experience, double-click to edit in place, is the right one. It belongs in the app (A's Apps bullet), not in the engine.

## 3. Recommendation

Take A, with the owner as the only new type.

**The decision it changes:** the issue sketches a `LayerRef` that bundles owner and layer, `.symbol("sym", layer: "ball")`. This proposal tags only the owner and leaves `layerID` where it is.

- `AddLayer` names a list, not a layer. Its `layerID` already comes from the layer it inserts (`LayerCommand.swift:6`). A bundled ref would still need a second, owner-only type.
- The `layerID` wire key and the `LayerCommand.layerID` requirement stay untouched. Only `sceneID` becomes `owner`.
- A `LayerRef` struct can be added when a second caller needs one value, such as app selection. Until then it is a type with no job.

B is dropped because the kind tag is mandatory (separate namespaces), which makes it A. C is dropped because it breaks the self-contained envelope that journals and agents rely on.

## 4. Migration

**`.flare` files: nothing to migrate.** No model field changes, the format stays version 1, and `GoldenFileTests` do not move. `LayerOwner` lives only in command params.

**Journals and envelopes.** Every envelope written before Q5 has `sceneID` and decodes as `.scene(id)`. A scene-owned command encodes byte for byte as before. This follows the `decodeIfPresent` pattern of `Document.swift:55-58`, with one difference: there is no default. Neither key present is malformed, never "the first scene".

**Transition.** Q5a changes the `LayerCommand` requirement from `sceneID` to `owner`. Until a family migrates, its line in `LayerCommand.swift` computes `owner` as `.scene(sceneID)`, and `withLayer(scene:layer:)` forwards to the owner form. Q5d deletes both. This is a time-boxed exception to "no shims" (`docs/engineering.md:54-56`). The alternative is one atomic PR far over the 400-line cap: 132 test call sites pass `sceneID:` to these commands today.

**Test plan.**

1. **Property test.** `Fixtures.withSymbol()` adds symbol `sym` with two layers, and the mixed `UndoPropertyTests` property starts from it. `anyLayer` (`UndoPropertyTests.swift:46-51`) becomes `anyTarget`: a scene layer, a symbol layer, or a missing owner. The harness already runs a full `validate` after every undo and redo (`Support.swift:79-88`), which keeps the scoped check honest for symbol owners.
2. **Round trip.** A `symbolSamples()` list holds one symbol-owned sample per migrated command and runs through the loops of `everyBuiltInRoundTripsAndBehavesTheSame` and `everyBuiltInEncodesTheSameAfterExecute`. It is a separate list because `samplesCoverEveryBuiltIn` expects one sample per id (`CommandRegistryTests.swift:81`). `sampleDocument()` gives `spark` a layer.
3. **Old envelopes.** One hand-written pre-Q5 envelope per family decodes, performs and re-encodes byte-identical. `decodesHandWrittenEnvelope` (`CommandRegistryTests.swift:150-151`) and `encodedCommandCarriesParamsOnly` stay unedited. `malformedEnvelopeThrows` (`:170-178`) gains "both keys" and "neither key". In the round-trip loop, every sample that is `any LayerCommand` asserts that its `params` holds exactly one of `"sceneID"` and `"symbolID"` at the top level, so one command left on synthesized Codable (which would nest the owner) fails the suite.
4. **Fuzz.** `CommandFuzzTests.randomDocument` (`CommandFuzzTests.swift:28-50`) adds symbols with layers, and its templates pick up `symbolSamples()`.
5. **Scoped validator.** `layerScopedValidateCatchesTheTouchedLayer` (`CommandEngineTests.swift:171-186`) gains symbol cases: a duplicate id, an empty track and a self-instance cycle.

## 5. Work breakdown

Five issues in the `docs/gaps.md` format. Q5b to Q5d land in order, because each one edits `LayerCommand.swift`, `CommandRegistryTests.swift` and `UndoPropertyTests.swift`. Line counts are additions plus deletions.

### Q5a: LayerOwner, resolver and owner-scoped validation
- Priority p2, size M. Depends on nothing.
- Behavior: new model file `LayerOwner.swift` with the enum, its flat Codable (exactly one of `sceneID`, `symbolID`) and `description`. `Document.withLayers(_:_:)`, `layers(of:)`, and owner forms of `withLayer` and `withEditableLayer`. `ModelError.symbolNotFound`, mapped in `CommandError.init` and `FormatError.init`. `symbolIndex` moves into the model. `LayerCommand` requires `owner`; each conformance computes `.scene(sceneID)`. `perform` and `validate(_:layer:owner:since:)` use it. No command changes params yet.
- Acceptance test: `layers(of: .symbol("sym"))` returns the symbol's layers and `withLayer(.symbol("ghost"), ...)` throws `ModelError.symbolNotFound("ghost")`. `LayerOwner` decodes `{"sceneID":"s1"}` and `{"symbolID":"a"}`, throws on both or neither keys, and a test command registered in a fresh `CommandRegistry()` encodes it flat beside its own keys and decodes it back. The scoped validator rejects a duplicate id, an empty track and a self-instance cycle in a symbol, with `"symbol sym: ..."` messages. Every existing test passes, and `encodedCommandCarriesParamsOnly` is not edited.
- Files: new `Sources/FlareCore/LayerOwner.swift`, `Document.swift`, `ModelError.swift`, `Command.swift`, `LayerCommand.swift`, `FlareFormat.swift`, `SymbolCommands.swift`, `docs/engineering.md` (model file list), `ModelErrorTests.swift` (same list), `Support.swift` (`Fixtures.withSymbol()`), new `LayerOwnerTests.swift`, `CommandEngineTests.swift`. About 250 lines.

### Q5b: Layer list commands edit symbol layers
- Priority p2, size M. Depends on Q5a.
- Behavior: `AddLayer`, `RemoveLayer`, `RenameLayer`, `ReorderLayer` and `SetLayerFlags` take `owner:` in place of `sceneID:` and work on symbol layers. `AddLayer`, `RemoveLayer` and `ReorderLayer`, which index `scenes` directly today, go through `withLayers`. Scene envelopes encode as before.
- Acceptance test: add, rename, reorder, lock and remove a layer of `sym`; each undo restores the document exactly. Their pre-Q5 envelopes decode and re-encode byte-identical. Symbol-owned samples join the round-trip loops, and the mixed undo property runs these steps against both owners.
- Files: `Commands.swift`, `LayerCommands.swift`, `LayerCommand.swift`, and the 9 test files that build these commands (50 call sites). About 320 lines.

### Q5c: Keyframe commands edit symbol layers
- Priority p2, size M. Depends on Q5b.
- Behavior: `SetKeyframe`, `MoveKeyframe`, `RemoveKeyframe`, `SetKeyframeEasing` and `ShiftKeyframes` take `owner:`. `MoveKeyframe.merge` compares the owner.
- Acceptance test: the issue's test, written as `SetKeyframe(owner: .symbol("sym"), layerID: "ball", ...)`, passes. A 10-step coalesced `MoveKeyframe` drag inside `sym` is one undo entry, and a drag with the same layer id in the scene does not merge with it. Old envelopes stay byte-identical.
- Files: `Commands.swift`, `KeyframeCommands.swift`, `LayerCommand.swift`, and the 6 test files that build these commands (39 call sites). About 280 lines.

### Q5d: Shape and text commands edit symbol layers; the scene-only path goes away
- Priority p2, size M. Depends on Q5c.
- Behavior: `AddShape`, `RemoveShape`, `SetShapeFill`, `TranslateShape` and the four text commands take `owner:`. `TranslateShape.merge` compares the owner; `editText` and `restoreText` take one. Delete `withLayer(scene:layer:)` and the computed owners in `LayerCommand.swift`. `docs/engineering.md` names `LayerOwner` as the layer address.
- Acceptance test: add, fill, translate and remove a shape in `sym`, and add and edit text there, each with exact undo. A locked symbol layer throws `layerLocked`. `grep "withLayer(scene:" Sources` finds nothing.
- Files: `Commands.swift`, `ShapeCommands.swift`, `TextCommands.swift`, `Document.swift`, `LayerCommand.swift`, `docs/engineering.md`, and the 7 test files that build these commands (43 call sites). About 340 lines.

### Q5e: Instance commands
- Priority p2, size M. Depends on Q5d.
- Behavior: new family `InstanceCommands.swift`: `AddInstance(owner:layerID:instance:)`, `RemoveInstance(owner:layerID:index:)` and `SetInstanceTransform(owner:layerID:index:transform:)`, which merges consecutive drags. An unknown symbol throws `symbolNotFound` before any change. An instance of a symbol inside itself fails `perform`'s validation. `validate` gains "instance transforms are finite", because nothing checks it today (`FlareFormat.swift:205-211`).
- Acceptance test: place `spark` in a scene layer and in a layer of `sym`, move it and remove it, each undo exact. Placing `sym` inside `sym` throws `invalidDocument` and changes nothing. A NaN transform throws. The family is registered, sampled and in the mixed undo property.
- Files: new `Sources/FlareCore/InstanceCommands.swift`, `CommandRegistry.swift`, `LayerCommand.swift`, `FlareFormat.swift`, new `InstanceCommandsTests.swift`, `CommandRegistryTests.swift`, `UndoPropertyTests.swift`. About 300 lines.

Not in this breakdown, each its own gap row once this is approved: `SetShapeStroke` (a shape command, so it takes `owner`), `SetSceneCanvas` for size and background (scene-scoped), and the state machine family (document-scoped). None of them depends on the open questions below.

## 6. Open questions

1. **Call sites.** This plan moves all 132 test call sites to `owner:` and keeps one init per command, per `docs/engineering.md:54-56`. The other path keeps `init(sceneID:layerID:...)` forever as a convenience: fewer changed lines, but two ways to build every layer command. Which one?
2. **Nested authoring.** Should `ConvertToSymbol` also take an owner, so layers inside a symbol can become a nested symbol? It stays scene-only in this plan.
3. **Encoding.** Flat `sceneID`/`symbolID` keys cost about 160 lines of hand-written Codable across 18 commands, and buy byte-identical old envelopes. Nested `"owner": {...}` saves no code, because old journals still need a `sceneID` fallback decoder. Is flat the right call?
