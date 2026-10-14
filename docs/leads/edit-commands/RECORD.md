# edit-commands lead record

Issue: #268 · Packet: docs/blueprints/core/features/edit-commands.md
Run: act-1a13b1450f1-6p7n · Session: claude/edit-commands-lead-rsmd3t · Started: 2026-10-14T15:00Z
Stage: 3 wave b
Base: 4cac701f50d6c434e6726917d6230db01e5167e5
Next: wait for wave b PRs (EC-2, EC-3, EC-5) and the lane merge, then wave c (EC-6)

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| EC-1 | a | 5 keyframe commands take `owner:`; MoveKeyframe.merge compares it; SceneLayerCommand deleted (finishes #176) | packet EC-1 row | existing suites + anyTarget symbol layers | FlareCore.json 10, 11 repointed, 15 re-anchored | #272 | merged |
| EC-4 | a | MoveGuide.merge | GuideCommands.swift, GuideMergeTests.swift, FlareGuideMerge.json | GuideMergeTests | FlareGuideMerge.json | #270 | merged |
| EC-2 | b | KeyframeOwnerTests (replaces #176) | KeyframeOwnerTests.swift, FlareKeyframeOwner.json | KeyframeOwnerTests | FlareKeyframeOwner.json | – | todo |
| EC-3 | b | SetKeyframe.merge for scrubs | Commands.swift, ScrubMergeTests.swift, FlareScrubMerge.json | ScrubMergeTests.twoHundredStepsAreOneCommand | FlareScrubMerge.json | – | todo |
| EC-5 | b | SetShapeStroke, SetShapePath | ShapeCommands.swift + tests | StrokePathCommandTests | FlareStrokePath.json | – | todo |
| EC-6 | c | DuplicateLayer | LayerCommands.swift + tests | DuplicateLayerTests | FlareDuplicateLayer.json | – | todo |
| EC-7a | d | SetSceneCanvas | SceneCommands.swift + tests | SceneCanvasCommandTests | FlareSceneCanvas.json | – | todo |
| EC-7b | e | RenameScene, ReorderScene, CommandError.emptyName | SceneCommands.swift, Command.swift + tests | SceneEditCommandTests | FlareSceneEdit.json | – | todo |
| EC-8 | f | AddInstance, RemoveInstance, invalidTransform, validate (finishes #178) | InstanceCommands.swift, Instance.swift, Command.swift, FlareFormat.swift, CommandRegistry.swift + tests | InstanceCommandsTests | FlareInstances.json | – | todo |
| EC-9 | g | SetInstanceTransform (drag merge), SetInstancePlayback (replaces #178) | InstanceCommands.swift + tests | InstanceTransformPlaybackTests | FlareInstancePlayback.json | – | todo |
| EC-10 | h | QB-L7 drag-step budget; feature-done | DragStepBudgetTests.swift | DragStepBudgetTests | – | – | todo |

Acceptance tests and quality bars: the packet's "Acceptance test per task" and "Quality tests" tables, verbatim.

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|

## Decisions
- Waves follow the packet (a EC-1+EC-4; b EC-2, EC-3, EC-5; c EC-6; d EC-7a; e EC-7b; f EC-8; g EC-9; h EC-10): the shared-test-file chain forces the sequence.
- gh CLI is not authenticated in this environment; PRs and labels go through the GitHub MCP tools.

## Open
- Builder branches are lead/edit-commands-<task> (a nested lead/edit-commands/<task> cannot coexist with the lead branch).
