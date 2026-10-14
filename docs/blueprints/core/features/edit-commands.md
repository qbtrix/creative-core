# Feature packet: edit-commands

**Feature:** the edits Flare's stage, inspector, timeline and scene list
perform, as undoable commands that work on scene and symbol layers alike:
keyframe commands with an owner, one merged command per scrub and per guide
drag, stroke and path edits, duplicate layer, scene canvas, rename and
reorder, and the instance commands (place, remove, move, playback).
**Line:** `line:core` · **Wave:** 1 (`waves.md`) · **Lead branch:** `lead/edit-commands`

**Covers:** #171 (Q5c, LC-5), #219 (LC-10), #216 (LC-7), #217 (LC-8), #173
(Q5e, LC-6). #171 closes with EC-2, #219 with EC-3, #216 with EC-6, #217
with EC-7, #173 with EC-9.

**Unblocks:** Flare `live-keys` (#171, #216, #219), `live-scenes` (#217,
#219) and, with `stage-geometry`, `live-stage` (#173, #216). The task order
below lands what `live-keys` and `live-scenes` wait on first.

**Depends on:** nothing open. Base: `origin/dev` 1b45592.

**Source:** Flare blueprint section 7.4 (rows LC-5 to LC-8 and LC-10) and
the approved Q5 design `docs/design/q5-layer-refs.md` (one init per command
with `owner:`, flat `sceneID` / `symbolID` keys, `ConvertToSymbol` stays
scene-only). Where an issue body and this packet differ, this packet wins.

## Existing work: finish, don't redo

Checked against `origin/dev` 1b45592 on 2026-10-14.

| PR | covers | state on dev | what this feature does with it |
|---|---|---|---|
| #176 keyframe commands take owner (closes #171) | `SetKeyframe`, `MoveKeyframe`, `RemoveKeyframe`, `SetKeyframeEasing`, `ShiftKeyframes` take `owner:`; `MoveKeyframe.merge` compares the owner; 39 test call sites moved; `KeyframeOwnerTests` | 49 commits behind `dev`; conflicts in `LayerCommand.swift`, `CommandRegistryTests.swift`, `LayerFlagsTests.swift`, `UndoPropertyTests.swift`. 410 changed lines, over the 400 cap | **EC-1 and EC-2 finish it.** EC-1 takes its source and call-site changes, rebased onto `dev`'s `LayerParamsCommand` helpers; EC-2 takes its `KeyframeOwnerTests.swift`. Builders start from `git checkout origin/claude/keyframe-commands-owner-jngaw5 -- <file>` and resolve against `dev`, never rewrite from scratch. EC-2's PR says "Replaces #176"; the lead closes #176 when EC-2 merges. |
| #178 instance commands on scene and symbol layers (closes #173) | `AddInstance`, `RemoveInstance`, `SetInstanceTransform` (drag merge), `CommandError.invalidTransform`, finite-transform validation in `FlareFormat.validate`, registry and undo-property entries | 48 commits behind `dev`; conflicts in `LayerCommand.swift` and `CommandRegistryTests.swift`; the lane refused it at 402 lines. It lacks `SetInstancePlayback` and the 100-step drag test LC-6 asks for | **EC-8 and EC-9 finish it.** EC-8 takes its three commands and the validation, with two changes that bring it under the cap and out of `stage-geometry`'s files: the `LayerCommand` conformance is declared on each struct in `InstanceCommands.swift` (no `LayerCommand.swift` edit), and `Transform.isFinite` goes in `Instance.swift`, not `Geometry.swift`. EC-9 adds `SetInstancePlayback` and the LC-6 acceptance test. EC-9's PR says "Replaces #178"; the lead closes #178 when EC-9 merges. |
| #163 `TileDiff` (CoreRaster) | – | Superseded: #164 merged the same feature and closed #156 | Not part of this feature; nothing here touches CoreRaster. |

## Journey steps

Proven on FlareCore values through a real `CommandEngine` (each step also
runs inside the mixed `UndoPropertyTests` property):

1. After `ConvertToSymbol` moves "ball" into `sym`,
   `SetKeyframe(owner: .symbol("sym"), layerID: "ball", ...)` keys it, and
   undo restores the symbol exactly. A key drag inside `sym` never merges
   with a drag of a scene layer that has the same id.
2. An inspector scrub of 200 `SetKeyframe` steps with one coalesce key is
   one undo entry holding one command, with the first old and the last new
   value. A guide drag of 50 `MoveGuide` steps is one command the same way.
3. A shape gets a stroke and a new path; each undo is exact; a negative or
   NaN width throws before any change.
4. Duplicate a layer: the copy sits above it with a fresh id and
   "<name> copy"; undo removes exactly the copy.
5. A scene is renamed, reordered and given a new canvas size and
   background; each undo is exact; a zero size or an index out of range
   throws.
6. `spark` is placed in a scene layer and in a layer of `sym`, dragged 100
   steps (one undo entry), set to play once from frame 4, and removed; each
   undo is exact. `sym` inside `sym` throws `invalidDocument` and changes
   nothing.

## Screens and states

The "screens" are the command families. Each rejects bad params with a
`CommandError` before it mutates anything (`docs/engineering.md`, "The
document stays valid"), and `CommandEngine.perform`'s validation is the
backstop.

| Family | Empty | Error | Loading |
|---|---|---|---|
| Keyframe (owner) | a missing track: `RemoveKeyframe` throws `keyframeNotFound`, as today | missing scene `sceneNotFound`, missing symbol `symbolNotFound`, missing layer `layerNotFound`, locked layer `layerLocked`, negative frame `invalidFrame`; an envelope with both or neither of `sceneID`/`symbolID` throws `malformedCommand` | – |
| Merges | the first step of a drag has nothing to merge into and is its own entry | a step for another owner, layer, property, frame or guide index never merges | – |
| Shape and layer | – | bad index `invalidIndex`; a stroke width that is negative or not finite throws what `Stroke.validate()` maps to (`invalidDocument`, as `SetShapeFill` does for fills); a path or point that is not finite throws the same way through the model check; duplicate of a missing layer `layerNotFound` | – |
| Scene | – | width or height ≤ 0 or not finite throws a new `CommandError.invalidCanvas` (no existing case fits); a non-finite background throws `invalidColor`; an empty name throws whatever `RenameLayer` throws for one, or a new `emptyName` case if it throws none; a reorder index outside `0..<scenes.count` throws `invalidIndex` | – |
| Instance | a layer with no instances: `RemoveInstance` / `SetInstanceTransform` / `SetInstancePlayback` at 0 throw `invalidIndex` | unknown symbol `symbolNotFound`; NaN or infinite transform `invalidTransform`; `firstFrame < 0` `invalidFrame`; a symbol placed inside itself fails `perform`'s owner-scoped validation with `invalidDocument` | – |

## Contract slice

```swift
// Commands.swift, KeyframeCommands.swift (EC-1): `sceneID:` becomes `owner:` on
SetKeyframe(owner: LayerOwner, layerID: String, property: String, keyframe: Keyframe)
MoveKeyframe(owner:layerID:property:from:to:)       // merge also compares owner
RemoveKeyframe(owner:layerID:property:frame:)
SetKeyframeEasing(owner:layerID:property:frame:easing:)
ShiftKeyframes(owner:layerID:fromFrame:toFrame:delta:)   // every other param unchanged
// The owner encodes flat (`sceneID` or `symbolID`), so every pre-owner
// envelope decodes and re-encodes byte for byte. `SceneLayerCommand` and its
// shim in LayerCommand.swift are deleted once nothing conforms to it.

// Commands.swift (EC-3)
extension SetKeyframe { public mutating func merge(_ next: SetKeyframe) -> Bool }
//   same owner, layerID, property and keyframe.frame: keep self.previous, take next.keyframe
// GuideCommands.swift (EC-4)
extension MoveGuide { public mutating func merge(_ next: MoveGuide) -> Bool }
//   same sceneID and index: keep the first old position, take next.position

// ShapeCommands.swift (EC-5): both in ShapeCommands.all
public struct SetShapeStroke: LayerParamsCommand   // id "shape.setStroke"; owner, layerID, index, stroke: Stroke?  (nil removes it)
public struct SetShapePath: LayerParamsCommand     // id "shape.setPath";   owner, layerID, index, path: Path?, points: [Point]
// LayerCommands.swift (EC-6): in LayerCommands.all
public struct DuplicateLayer: Command              // id "layer.duplicate"; owner, layerID; copy at index + 1, id "<id>-copy[-n]", name "<name> copy"
// SceneCommands.swift (EC-7): in SceneCommands.all
public struct SetSceneCanvas: Command              // id "scene.setCanvas"; sceneID, width, height, background: Color
public struct RenameScene: Command                 // id "scene.rename";    sceneID, name
public struct ReorderScene: Command                // id "scene.reorder";   sceneID, toIndex
// InstanceCommands.swift (EC-8, EC-9): new family InstanceCommands.all, one line in CommandRegistry.builtInFamilies
public struct AddInstance: LayerCommand            // id "instance.add";         owner, layerID, instance
public struct RemoveInstance: LayerCommand         // id "instance.remove";      owner, layerID, index
public struct SetInstanceTransform: LayerCommand   // id "instance.setTransform"; owner, layerID, index, transform; merges drags
public struct SetInstancePlayback: LayerCommand    // id "instance.setPlayback";  owner, layerID, index, firstFrame, loop   (EC-9)
// Command.swift (EC-8): CommandError gains `invalidTransform`.
// Instance.swift (EC-8): `extension Transform { var isFinite: Bool }` (internal), used by the commands and by validate.
// FlareFormat.swift (EC-8): validate rejects a non-finite instance transform.
```

Ids follow the existing `family.verb` names; the lead checks each against
`CommandRegistryTests.expectedIDs` before the builder starts. A new family
lists its own commands in its own file (`CommandRegistry.swift` says so), so
only EC-8 edits `CommandRegistry.swift`, and EC-5 to EC-7 add to existing
families. That is why LC-7 no longer waits on LC-6 and LC-8 no longer waits
on LC-7: those issue dependencies were registry-line stacking, which `dev`'s
per-family lists removed. The remaining order below is only test-file
stacking.

No task here edits `docs/c4/model.json`: `InstanceCommands.swift` is already
owned by the `symbols` component, every other file already exists, and
`stage-geometry` SG-1 (same wave, the file's owner) writes the description
words for these commands.

## Pseudocode

```
EC-1 keyframe owner: for each of the 5 commands
  replace `sceneID` with `owner: LayerOwner`; resolve with document.withEditableLayer(owner, layer:) / withLayer(owner, layer:)
  Codable: encodeAddress / decodeAddress (LayerCommand.swift) + the command's own keys  # flat sceneID|symbolID
  MoveKeyframe.merge: guard (next.owner, next.layerID, next.property, next.from) == (owner, layerID, property, to)
  conform to LayerCommand directly; delete SceneLayerCommand when nothing conforms

EC-3 SetKeyframe.merge(next):
  guard executed == true, next.owner == owner, next.layerID == layerID,
        next.property == property, next.keyframe.frame == keyframe.frame else false
  keyframe = next.keyframe ; return true          # previous (the first old key) stays
EC-4 MoveGuide.merge(next): guard next.sceneID == sceneID, next.index == index else false
  position = next.position ; return true          # the recorded old position stays

EC-5 SetShapeStroke.execute: guard index in shapes; guard stroke == nil || (width.isFinite && width >= 0) else throw
  old = shape.stroke ; shape.stroke = stroke      # undo: shape.stroke = old
EC-5 SetShapePath.execute: guard every point finite; old = (shape.path, shape.points); set both  # undo restores both
EC-6 DuplicateLayer.execute: guard layer exists; copy = layer; copy.id = fresh id not used in the owner's list;
  copy.name = name + " copy"; insert at index + 1        # undo removes at index + 1 after checking the id
EC-7 SetSceneCanvas: guard w, h finite and > 0, color finite; old = (w, h, bg); set   # undo restores old
     RenameScene: guard !name.isEmpty; ReorderScene: guard toIndex in 0..<count; move; undo moves back
EC-8 AddInstance: guard symbol exists, transform finite, firstFrame >= 0; append; undo removes last after checking it
     RemoveInstance: guard index; old = remove(at:); undo inserts old at index
     SetInstanceTransform: guard index, finite; old = transform; set; merge like TranslateShape (first old, last new)
EC-9 SetInstancePlayback: guard index, firstFrame >= 0; old = (firstFrame, loop); set; undo restores
```

## Tasks

Every task is one PR to `dev`: at most 400 changed lines and 15 files, label
`fast-lane`, body lines `Belt-Lead:`, `Feature: edit-commands`,
`Fast-Check: pass`, `Head:`. EC-10 also carries `feature-done`.

**Mutation plans.** `Tests/mutations/FlareCore.json` is owned by EC-1 only,
to repoint the three anchors in `Commands.swift` that the owner change
moves (the `MoveKeyframe.merge` guard and `SetKeyframe`'s `CodingKeys`),
keeping the bug each note names. Every new entry goes in the task's own plan
file named below (`scripts/mutate` reads every `*.json` in
`Tests/mutations/`).

**Shared test files.** `CommandRegistryTests.swift` (ids and samples) and
`UndoPropertyTests.swift` are edited by several tasks; they form one chain,
EC-1 → EC-5 → EC-6 → EC-7 → EC-8 → EC-9, each rebased on the one before.
EC-2, EC-3 and EC-4 touch neither and run beside the chain.

| id | issue | what | owned files | depends on | size |
|---|---|---|---|---|---|
| EC-1 | #171 (part; finishes #176) | The 5 keyframe commands take `owner:`; `MoveKeyframe.merge` compares it; call sites moved; `SceneLayerCommand` deleted; `FlareCore.json` anchors repointed | `Sources/FlareCore/Commands.swift`, `Sources/FlareCore/KeyframeCommands.swift`, `Sources/FlareCore/LayerCommand.swift`, `Sources/FlareCore/Document.swift` (only to delete the scene-only `withLayer(scene:)` pair if EC-1 removes its last caller), `Tests/FlareCoreTests/CoalesceTests.swift`, `Tests/FlareCoreTests/CommandEngineTests.swift`, `Tests/FlareCoreTests/CommandRegistryTests.swift`, `Tests/FlareCoreTests/KeyframeCommandsTests.swift`, `Tests/FlareCoreTests/LayerFlagsTests.swift`, `Tests/FlareCoreTests/UndoPropertyTests.swift`, `Tests/mutations/FlareCore.json` | – | ~290 |
| EC-2 | #171 (closes; replaces #176) | `KeyframeOwnerTests`: symbol keys, owner-aware merge, byte-identical scene envelopes, `symbolID` envelopes | `Tests/FlareCoreTests/KeyframeOwnerTests.swift`, `Tests/mutations/FlareKeyframeOwner.json` | EC-1 | ~160 |
| EC-3 | #219 (closes) | `SetKeyframe.merge` for scrubs | `Sources/FlareCore/Commands.swift`, `Tests/FlareCoreTests/ScrubMergeTests.swift`, `Tests/mutations/FlareScrubMerge.json` | EC-1 (`Commands.swift`), EC-4 (so #219 closes on the later PR) | ~120 |
| EC-4 | #219 (part) | `MoveGuide.merge` | `Sources/FlareCore/GuideCommands.swift`, `Tests/FlareCoreTests/GuideMergeTests.swift`, `Tests/mutations/FlareGuideMerge.json` | – | ~90 |
| EC-5 | #216 (part) | `SetShapeStroke`, `SetShapePath` | `Sources/FlareCore/ShapeCommands.swift`, `Tests/FlareCoreTests/StrokePathCommandTests.swift`, `Tests/FlareCoreTests/ShapeCommandsTests.swift` (its `undoSteps`), `Tests/FlareCoreTests/CommandRegistryTests.swift`, `Tests/mutations/FlareStrokePath.json` | EC-1 (test chain) | ~280 |
| EC-6 | #216 (closes) | `DuplicateLayer` | `Sources/FlareCore/LayerCommands.swift`, `Tests/FlareCoreTests/DuplicateLayerTests.swift`, `Tests/FlareCoreTests/LayerFlagsTests.swift` (its `undoSteps`), `Tests/FlareCoreTests/CommandRegistryTests.swift`, `Tests/mutations/FlareDuplicateLayer.json` | EC-5 (test chain) | ~200 |
| EC-7 | #217 (closes) | `SetSceneCanvas`, `RenameScene`, `ReorderScene` | `Sources/FlareCore/SceneCommands.swift`, `Tests/FlareCoreTests/SceneEditCommandTests.swift`, `Tests/FlareCoreTests/SceneCommandTests.swift` (its `undoSteps`), `Tests/FlareCoreTests/CommandRegistryTests.swift`, `Tests/mutations/FlareSceneEdit.json` | EC-6 (test chain) | ~330; over 400, canvas goes in its own PR first |
| EC-8 | #173 (part; finishes #178) | `AddInstance`, `RemoveInstance`, `SetInstanceTransform` (drag merge), `invalidTransform`, finite-transform validation; family registered | `Sources/FlareCore/InstanceCommands.swift`, `Sources/FlareCore/Instance.swift`, `Sources/FlareCore/Command.swift`, `Sources/FlareCore/FlareFormat.swift`, `Sources/FlareCore/CommandRegistry.swift`, `Tests/FlareCoreTests/InstanceCommandsTests.swift`, `Tests/FlareCoreTests/CommandRegistryTests.swift`, `Tests/FlareCoreTests/UndoPropertyTests.swift`, `Tests/mutations/FlareInstances.json` | EC-7 (test chain) | ~370 |
| EC-9 | #173 (closes; replaces #178) | `SetInstancePlayback`; the LC-6 acceptance (100-step drag, NaN, `firstFrame < 0`) | `Sources/FlareCore/InstanceCommands.swift`, `Tests/FlareCoreTests/InstancePlaybackTests.swift`, `Tests/FlareCoreTests/CommandRegistryTests.swift`, `Tests/mutations/FlareInstancePlayback.json` | EC-8 | ~200 |
| EC-10 | – | QB-L7 drag-step budget; `feature-done` | `Tests/FlareCoreTests/DragStepBudgetTests.swift` | EC-3, EC-4, EC-9 | ~100 |

Build waves inside the feature: **a** EC-1, EC-4; **b** EC-2, EC-3, EC-5;
**c** EC-6; **d** EC-7; **e** EC-8; **f** EC-9; **g** EC-10. After wave
**c**, #171, #216 and #219 are closed and Flare's `live-keys` can be filed;
after **d**, `live-scenes`; after **f** and `stage-geometry`, `live-stage`.

## Acceptance test per task

| id | test | fails when |
|---|---|---|
| EC-1 | Every existing test passes with the new call sites; `KeyframeCommandsTests.undoAllRestoresOriginal` starts from `Fixtures.withSymbol()` and `UndoPropertyTests.anyTarget` picks scene layers, symbol layers, missing layers and missing symbols for the keyframe steps; `KeyframeCommandsTests.keysALayerMovedIntoASymbol`: after `ConvertToSymbol`, `SetKeyframe(owner: .symbol("sym"), layerID: "ball", ...)` sets the key and undo restores the document exactly; `scripts/mutate --validate` is clean | a keyframe command can't reach a symbol layer, undo is inexact, or an anchor is stale |
| EC-2 | `KeyframeOwnerTests` (from #176): `dragInsideASymbolIsOneUndoEntryAndNeverMergesWithTheScene` (10 coalesced steps in `sym` are one entry; a scene drag with the same layer id, property and frame does not merge into it); `sceneEnvelopeStaysByteIdentical` for each of the 5 commands (hand-written pre-owner JSON decodes and re-encodes byte for byte); `symbolEnvelopeRoundTripsAndEditsTheSymbol`; `envelopeWithBothOrNeitherOwnerKeyThrows`; `lockedSymbolLayerAndMissingSymbolThrowWithoutChanges` | merge ignores the owner, an old envelope's bytes change, or a bad envelope decodes |
| EC-3 | `ScrubMergeTests.twoHundredStepsAreOneCommand`: 200 `SetKeyframe` steps on one key with one coalesce key leave one undo entry whose single command holds the first old key (`previous`) and the last new value; one `undo()` restores the document exactly; a step on another frame, property, layer or owner does not merge; `a.merge(b)` on a not-executed `a` returns false | a scrub leaves 2+ commands, undo restores a middle value, or unrelated steps merge |
| EC-4 | `GuideMergeTests`: 50 `MoveGuide` steps with one key are one command with the first old and last new position; one `undo()` restores it; a step for another guide index or scene does not merge | the old position is lost or other guides merge |
| EC-5 | `StrokePathCommandTests`: `SetShapeStroke` sets, replaces and removes (nil) a stroke, each undo exact; width −1, NaN and +∞ throw and change nothing; `SetShapePath` sets a cubic path and its points, undo restores both exactly; a NaN point throws; both work on a symbol layer; both are in `ShapeCommands.all`, sampled in `CommandRegistryTests` and steps in `ShapeCommandsTests.undoSteps` | a bad width lands, undo misses the points, or the command isn't registered |
| EC-6 | `DuplicateLayerTests`: duplicating "ball" gives "Ball copy" at index + 1 with an id no other layer of that owner has (twice in a row gives two distinct ids); the copy's shapes, tracks, instances and texts equal the original's; undo removes exactly the copy; a missing layer throws `layerNotFound`; it works inside `sym` | an id is reused, the copy lands elsewhere, or undo removes the wrong layer |
| EC-7 | `SceneEditCommandTests`: `SetSceneCanvas` to 1920 × 1080 with a new background and undo exact; width 0, −1 and NaN throw; `RenameScene` and undo exact, "" throws; `ReorderScene` of the first of 3 scenes to index 2 and undo exact; index 3 and −1 throw `invalidIndex`; all three sampled and in `SceneCommandTests.undoSteps` | a zero size or out-of-range index lands, or undo is inexact |
| EC-8 | `InstanceCommandsTests` (from #178): `addMoveRemoveEachUndoExactly` in a scene layer and in a layer of `sym`; `symbolInsideItselfIsInvalidAndChangesNothing`; `badParamsThrowBeforeAnyChange`; `validateRejectsNonFiniteInstanceTransform`; `setsOfOtherOwnersOrInstancesDoNotMerge`; the family is registered and in the mixed `UndoPropertyTests` | a NaN transform lands or validates, a cycle commits, or merge crosses instances |
| EC-9 | `InstancePlaybackTests`: a 100-step `SetInstanceTransform` drag with one key is one undo entry holding one command, and one `undo()` restores the first transform; `SetInstancePlayback(firstFrame: 4, loop: .playOnce)` and undo exact; `firstFrame: -1` throws `invalidFrame`; a NaN transform fails `FlareFormat.validate` on a hand-built document | a drag leaves 2+ entries, a negative first frame lands, or validate misses NaN |
| EC-10 | `DragStepBudgetTests` (below) | the median exceeds the budget |

## Quality tests

| quality row | budget (CI gate, debug) | test |
|---|---|---|
| QB-L7 one drag step through the engine (perform and validate) | ≤ 10 ms median of 100 steps each, on a seeded document of 200 layers: `SetInstanceTransform`, `SetKeyframe` scrub, `MoveGuide` | `DragStepBudgetTests.instanceDragStepWithinBudget`, `.scrubStepWithinBudget`, `.guideDragStepWithinBudget` |
| Undo stays exact across families | the mixed property runs every new command with every old one | `UndoPropertyTests` (seeded `SplitMix64`) |
| Untrusted envelopes never crash | every new id gets a malformed-params case | `CommandFuzzTests` stays green; `CommandRegistryTests.everyBuiltInRoundTripsAndBehavesTheSame` covers each new sample |
| Old files keep loading | no model field is added; pre-owner keyframe envelopes stay byte-identical | `KeyframeOwnerTests.sceneEnvelopeStaysByteIdentical`, `GoldenFileTests` |
| Mutation | every entry in the feature's plan files, and the repointed `FlareCore.json` entries, are caught | `scripts/mutate --run --changed-since <first base>` |

## Done check

- **Journeys green:** `scripts/ci` prints `CI: PASS` on the `dev` SHA that
  holds every merged task, and the CI run on `dev` the `feature-done` PR
  (EC-10) triggers is green (Linux, macOS on Swift 6.1, Mutation).
- **Audit zero new:** no new no-crash lint hit, the jscpd threshold not
  raised, `scripts/mutate --validate` clean, no escaped mutant; #176 and
  #178 closed as replaced.
- **Contact sheet:** `Belt-Contact-Sheet: <run link>` on the feature issue,
  one line per acceptance test above, and the test and mutation counts.
