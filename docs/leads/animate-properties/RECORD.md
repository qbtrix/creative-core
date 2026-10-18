# animate-properties lead record

Issue: #442 · Packet: docs/blueprints/core/features/animate-properties.md
Run: act-1a14ddaebc8-nwqn · Session: line lead (engine-contracts, animate-properties, color-profiles) · Started: 2026-10-18T07:15Z
Stage: 3 line wave 4 (AP-7, AP-8 building) + fixes from engine-contracts round 3
Base: 9d01972365f04da4fe6074e9bdd56ceab5b616a8
Next: Anatomy round 1 on the AP-sample/AP-export surface (includes the AP-7/AP-8 base-exporter edits). AP-4 waits on path-geometry PG-edit (#430); AP-9, AP-10 after.

## Slices
| slice | tasks | waits on | state | Slice-Done run | Mac-Finish |
|---|---|---|---|---|---|
| AP-a | AP-1, AP-2 | engine-contracts:EC-f | merged-done | 39118832683 | |
| AP-cmd | AP-3, AP-4 | AP-a; path-geometry:PG-edit (AP-4) | open | | |
| AP-sample | AP-5, AP-6 | AP-a | merged-done (run 39126063033, Linux green on d51ef90) | | |
| AP-export | AP-7, AP-8 | AP-sample | merged-done (run 39126063033, Linux green on d51ef90) | | |
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
- Wave 4 contract checks (wf_a5b3a585-9ef), after the lane merged both: AP-7 #480 also edited LottieExporter.swift (10+/10-: LottieItem ks/c/w widened to LottieProperty so keyed values fit, clamp through the shared unit); AP-8 #481 edited SVGExporter.swift (+3/-2, the seam so +Style sees layer tracks). The prompt allowed a hook in each base exporter; AP-7 went past one line but stayed on the seam the packet's Contract needs. Accepted; round 1 critics on AP-export will review both base-file edits. Everything else in both checks passed (232 lines/4 files and 102 lines/4 files, trailers, mutations 2/2 each).
- Merged: AP-1 #457, AP-2 #463, AP-6 #464, AP-5 #477, AP-3 #479 (d7ad60b).
- engine-contracts round 3 (f7413a6) routed 3 findings here: #1 (major) TrackCommands.notBuilt throws invalidDocument with an internal task id; #8 (major) no test that easing shapes the morph; #11 (minor) quad-to-cubic elevation untested. Fixer ap-r1 takes them; files kept disjoint from AP-7/AP-8.
- ap-r1 → #484 (head d6b1a9c, merged d51ef90): new CommandError.notBuilt for the shape key stubs (names the command and feature), easingShapesTheMorph and quadElevatesToCubic tests, two new FlareMorphSampling entries caught (4/4). Ops note: about 34 finished worktrees had filled the root disk to 99%; the lead removed the unlocked ones (now 42%).
- dev CI 39118832683 on 0660756: Linux green. AP-a merged-done.
- #461 (e158c87) amended brief rule 9: a message starting `Belt released this run.` means stop at once; every other chat message still never stops the lead. Applied to this run.
- "line N" in the wave column is the line lead's shared wave number (engine-contracts wave N runs beside it).
- AP-1 (#457) check flags accepted: (1) the five stub commands have no UndoPropertyTests step, because they throw `not built` and the packet gives undoSteps to AP-2/AP-3, which add the steps when the commands work; (2) it touched CommandFuzzTests, CommandRegistryTests and TrackCommandsTests to register the new ids and keep the gate green (TrackCommandsTests was pre-allowed). 340 lines, 7 files.

## Open
- AP-4 waits on path-geometry:PG-edit (#430: no PR yet). AP-cmd and AP-z wait with it.
