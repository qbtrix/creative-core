# edit-commands lead record

Issue: #268 · Packet: docs/blueprints/core/features/edit-commands.md
Run: act-1a13b1450f1-6p7n · Session: claude/edit-commands-lead-rsmd3t · Started: 2026-10-14T15:00Z
Stage: 4 round 2
Base: 923c083d9a79c802455584fe891c9eb594a96a5a
Next: finish round 2 mutation; merge r2-b1; round 3 (same lenses) on the new SHA; then the feature-done PR

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| EC-1 | a | 5 keyframe commands take `owner:`; MoveKeyframe.merge compares it; SceneLayerCommand deleted (finishes #176) | packet EC-1 row | existing suites + anyTarget symbol layers | FlareCore.json 10, 11 repointed, 15 re-anchored | #272 | merged |
| EC-4 | a | MoveGuide.merge | GuideCommands.swift, GuideMergeTests.swift, FlareGuideMerge.json | GuideMergeTests | FlareGuideMerge.json | #270 | merged |
| EC-2 | b | KeyframeOwnerTests (replaces #176) | KeyframeOwnerTests.swift, FlareKeyframeOwner.json | KeyframeOwnerTests | FlareKeyframeOwner.json | #276 | merged |
| EC-3 | b | SetKeyframe.merge for scrubs | Commands.swift, ScrubMergeTests.swift, FlareScrubMerge.json | ScrubMergeTests.twoHundredStepsAreOneCommand | FlareScrubMerge.json | #273 | merged |
| EC-5 | b | SetShapeStroke, SetShapePath | ShapeCommands.swift + tests | StrokePathCommandTests | FlareStrokePath.json | #279 | merged |
| EC-6 | c | DuplicateLayer | LayerCommands.swift + tests | DuplicateLayerTests | FlareDuplicateLayer.json | #282 | merged |
| EC-7a | d | SetSceneCanvas | SceneCommands.swift + tests | SceneCanvasCommandTests | FlareSceneCanvas.json | #283 | merged |
| EC-7b | e | RenameScene, ReorderScene, CommandError.emptyName | SceneCommands.swift, Command.swift + tests | SceneEditCommandTests | FlareSceneEdit.json | #285 | merged |
| EC-8 | f | AddInstance, RemoveInstance, invalidTransform, validate (finishes #178) | InstanceCommands.swift, Instance.swift, Command.swift, FlareFormat.swift, CommandRegistry.swift + tests | InstanceCommandsTests | FlareInstances.json | #286 | merged |
| EC-9 | g | SetInstanceTransform (drag merge), SetInstancePlayback (replaces #178) | InstanceCommands.swift + tests | InstanceTransformPlaybackTests | FlareInstancePlayback.json | #291 | merged |
| EC-10 | h | QB-L7 drag-step budget; feature-done | DragStepBudgetTests.swift | DragStepBudgetTests | – | #292 | merged |

Acceptance tests and quality bars: the packet's "Acceptance test per task" and "Quality tests" tables, verbatim.

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|
| 1 | 94d993b | PASS (740 tests) | 94/94 (validate: 151 anchors) | - | clarity, contract, undo, robustness, tests | 9 (1 major: SetInstanceTransform merge owner guard untested; 8 minor: docs/labels/errors, SetKeyframe coalesce step, AddInstance undo guard untested) | #293, #294 (merged) | no |
| 2 | 923c083 | PASS (743 tests) | 97/97 (validate: 154 anchors) | none on dev yet (last CI run 09:30Z predates the feature) | same five | 6 minor (DuplicateLayer undo error, two messages without ids, ScrubMerge frame-24 value, registry header count, dead scene-only withLayer pair, Transform.isFinite y untested); 0 blocker/major | r2-b1 (wf_8a395b4a-49a) | yes |

## Decisions
- Waves follow the packet (a EC-1+EC-4; b EC-2, EC-3, EC-5; c EC-6; d EC-7a; e EC-7b; f EC-8; g EC-9; h EC-10): the shared-test-file chain forces the sequence.
- gh CLI is not authenticated in this environment; PRs and labels go through the GitHub MCP tools.

- EC-10 (drag-step budget) ships without `feature-done`: the Anatomy loop runs after it, and the feature-done label goes on the last PR (a final fix or the packet status line), so the CI run it dispatches covers every fix.

## Open
- #176 closed as replaced by #272 + #276; #178 closed as replaced by #286 + #291.
- Builder gates flake on timing-budget tests (RetouchBounds, EngineStress budget) under 4-CPU load; reruns pass. Watch in the Anatomy gate.
- Builder branches are lead/edit-commands-<task> (a nested lead/edit-commands/<task> cannot coexist with the lead branch).
