# animate-properties lead record

Issue: #442 · Packet: docs/blueprints/core/features/animate-properties.md
Run: act-1a14ddaebc8-nwqn · Session: line lead (engine-contracts, animate-properties, color-profiles) · Started: 2026-10-18T07:15Z
Stage: 3 line wave 3
Base: 9d01972365f04da4fe6074e9bdd56ceab5b616a8
Next: AP-1 PR merges, then AP-2 (checks first)

## Slices
| slice | tasks | waits on | state | Slice-Done run | Mac-Finish |
|---|---|---|---|---|---|
| AP-a | AP-1, AP-2 | engine-contracts:EC-f | open | | |
| AP-cmd | AP-3, AP-4 | AP-a; path-geometry:PG-edit (AP-4) | open | | |
| AP-sample | AP-5, AP-6 | AP-a | open | | |
| AP-export | AP-7, AP-8 | AP-sample | open | | |
| AP-z | AP-9, AP-10 | AP-cmd, AP-export | open | | |

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| AP-1 | line 3 | command and sampler stubs | TrackCommands(+Shape), Sampling+Tracks | TrackShapeTests | none | | building on 83b20aa |
| AP-2 | line 4 | checks first, disabled; fixture | six test suites, Fixtures/tracks.flare | compile | – | | waits AP-1 |
| AP-3 | line 5 | colour key commands | TrackCommands.swift | TrackCommandsTests | FlareTrackCommands (3) | | waits AP-2 |
| AP-4 | – | shape key commands + compatibility | TrackCommands+Shape.swift | ShapeKeyCompatTests | FlareShapeKeys (3) | | waits AP-2, path-geometry:PG-edit |
| AP-5 | line 5 | sampledColor | Sampling+Tracks.swift | ColorSamplingTests | FlareColorSampling (3) | | waits AP-2 |
| AP-6 | line 5 | sampledPath | Sampling+TracksMorph.swift | MorphSamplingTests | FlareMorphSampling (2) | | waits AP-2 |
| AP-7 | line 6 | Lottie animated keys | LottieExporter+Tracks.swift | LottieTrackExportTests | FlareLottieTrackExport (2) | | waits AP-5, AP-6 |
| AP-8 | line 6 | SVG values at frame | SVGExporter+Style.swift | SVGStyleAtFrameTests | FlareSVGStyleAtFrame (2) | | waits AP-5, AP-6 |
| AP-9 | – | KJ-AP walk, budgets | TrackWalkTests, TrackBudgetTests | walk | none | | waits AP-3,4,7,8 |
| AP-10 | – | status line, feature-done | packet | – | – | | waits AP-9 |

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|

## Decisions
- dev CI 39118832683 on 0660756: Linux green. AP-a merged-done.
- #461 (e158c87) amended brief rule 9: a message starting `Belt released this run.` means stop at once; every other chat message still never stops the lead. Applied to this run.
- "line N" in the wave column is the line lead's shared wave number (engine-contracts wave N runs beside it).
- AP-1 (#457) check flags accepted: (1) the five stub commands have no UndoPropertyTests step, because they throw `not built` and the packet gives undoSteps to AP-2/AP-3, which add the steps when the commands work; (2) it touched CommandFuzzTests, CommandRegistryTests and TrackCommandsTests to register the new ids and keep the gate green (TrackCommandsTests was pre-allowed). 340 lines, 7 files.

## Open
- AP-4 waits on path-geometry:PG-edit (#430: no PR yet). AP-cmd and AP-z wait with it.
