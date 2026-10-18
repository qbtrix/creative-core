# vector-import lead record

Issue: #439 · Packet: docs/blueprints/core/features/vector-import.md
Run: act-1a14de006be-1kmq · Session: https://claude.ai/code/session_01WN1jNn5SUWJXTALMBvtq64 · Started: 2026-10-18T07:20Z
Line lead for: preview-cache (#440), vector-import (#439), layered-codecs (#438)
Stage: 3 wave 3; Anatomy round 1 on finished slices
Base: b80c0871a391e1729578b0344c8884c10471c8ca
Next: VI-5 building, VI-7 building; Anatomy round 2 verdicts pending; Slice-Done waits on round-2 verdicts (dev CI run 360 on 72fbef6: Linux green)

## Slices
| slice | tasks | waits on | state | Slice-Done run | Mac-Finish |
|---|---|---|---|---|---|
| VI-a | VI-1, VI-2 | nothing | open | | |
| VI-svg | VI-3, VI-4, VI-5 | VI-a; engine-contracts:EC-f (met) | open | | |
| VI-lottie | VI-6, VI-7 | VI-a; engine-contracts:EC-f (met) | open | | |
| VI-z | VI-8, VI-9 | VI-svg, VI-lottie | open | | none |

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| VI-1 | 1 | values, errors, two stubs, `import` part | Sources/FlareCore/Import/Import.swift, Tests/FlareCoreTests/ImportShapeTests.swift, docs/c4/parts/creative-core/flarecore/import.json | ImportShapeTests | none | #449 (83b20aa) | merged |
| VI-2 | 2 | fixtures and every suite disabled | Tests/FlareCoreTests/Fixtures/import/, six suite files | suites compile | – | #478 (a59c5c2) | merged |
| VI-3 | 3 | XMLTokens | Import/XMLTokens.swift, XMLTokensTests | XMLTokensTests | FlareXMLTokens (3, 3/3 caught) | #491 | merged (72fbef6) |
| VI-4 | 3 | SVGPathData with arcs | Import/SVGPathData.swift, SVGPathDataTests | SVGPathDataTests | FlareSVGPathData (5, 5/5 caught) | #490 (d060a8a) | merged |
| VI-5 | after VI-3,4, EC-f | SVGImport.scene | Import/SVGImport.swift, SVGStyle.swift, SVGImportTests, SVGImportFuzzTests | both | FlareSVGImport (3) | | building |
| VI-6 | after VI-2, EC-f | Lottie shapes, static transform | Import/LottieImport.swift, LottieImportTests | LottieImportTests | FlareLottieImport (7, 7/7 caught) | #494 (71c00e8) | merged |
| VI-7 | after VI-6 | Lottie animation, masks, mattes | Import/LottieImport+Animation.swift, LottieImportAnimationTests, LottieImportFuzzTests | both | FlareLottieImportAnimation (3) | | building |
| VI-8 | after VI-5,7 | round trip and budgets | ImportRoundTripTests, ImportBudgetTests | KJ-VI | none | | open |
| VI-9 | last | part words, status, `feature-done` | import.json, packet | – | – | | open |

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|
| 1 (VI-a) | b80c087 | PASS | n/a (VI-a has no plan) | - | clarity, contract, undo, robustness, tests | 3 major: Lottie anchor/group tr (VI-6), Lottie Int(Double) traps on fr/ip/op (VI-6), arc large-arc/scale-up/rotation (VI-4); 4 downgraded to minor (ref cycles, fill none spec, ...) | builders VI-4, VI-6 + R1 doc batch (packet: anchor, fill=none, AddScene id, cycles) | no |

## Decisions
- One wave plan across the three features (rule 19); wave 1 is PC-1, VI-1, LC-1.
- VI-5, VI-6 waited on engine-contracts EC-f (at 9d01972: `LayerMask`, `TrackMatte`, `colorTracks` not on dev at 9d01972).

- Builder branches are `lead/<feature>-<task>` (a ref `lead/<feature>/<task>` cannot sit beside `lead/<feature>`).
- Wave 2 (9e826ac): PC-2, PC-6, VI-2, LC-2, LC-3, LC-5, disjoint files. `Hash/` is owned by `image-ops` and `Codecs/` by `codecs` on dev, so wave 2 needs no C4 edits.
- engine-contracts EC-f merged (#444, #447, #448): VI-5, VI-6, VI-7 wait only on their own tasks now.
- VI-2 left `tokens(_:)` (XMLTokensTests) and `path(_:)` (SVGPathDataTests) as throwing helpers: VI-3 and VI-4 replace their bodies and drop `.disabled`.
- From wave 3 builders run `scripts/ci` under one shared `flock` (wall-clock budgets failed under 6-way load).

## Open
- none

- 2026-10-18T13:44:23Z round 2: dev 8e258c5, gate PASS (EngineStress flake rerun), mutants 37/37, lenses 5, clean=no; majors n4/12 arc NaN trap (fixer lead/vector-import-R2-1), n1 depth cap + n8 group tr tests (VI-7 follow-up lead/vector-import-R2-2), n14 #488 checks (VI-5)

- 14:31Z: VI-7 #505 merged (8/8). VI-8 launches when VI-5 merges.

- 14:37Z: VI R2-1 fixer opened #506 (c3c284d, 7/7, +90/-17): arc throws on non-finite centre/sweep/radii, segment count clamped via Int(exactly:), ellipse test solves F.6.5/F.6.6. Closes n4/12, n9 on merge.
- 2026-10-18T14:54:08Z VI R2-1 #506 merged (14:37Z, c3c284d, 7/7): round-2 n4/12 and n9 closed.
- 2026-10-18T14:59:41Z VI R2-2 #512 opened (f5a3348, 12/12 FlareLottieImport): depth cap 250 with tooLarge, group tr tests, opacity clamp. Closes n1, n8/15 once merged. VI-8 notes: exporter shape order not reversed (LottieExporter.swift ~94), colour track index follows; masks/mattes exporter stubs.
- 2026-10-18T15:17:10Z VI R2-2 #512 merged 14:59Z (n1, n8/15 closed). macOS SIGBUS on deep recursion (Lottie maxDepth 250 on 512 KB thread stacks, #453): fixer R2-3 launched.
- 2026-10-18T15:24:19Z VI-5 #517 (read SVG documents) merged 5dfa965; VI-5 second PR in progress.
- 2026-10-18T15:40Z heartbeat: checking merges, dev CI and agents.
- 2026-10-18T15:43Z incident: the disk filled up at about 15:39Z. I deleted the .build caches of finished worktrees and told the running agents to rerun any gate that failed. No dev CI run newer than 364 yet. #518 (LC R2-2) needs a rebase onto 168c73d.
- 2026-10-18T16:05Z heartbeat.
- 2026-10-18T16:05Z Another session's PRs fix the macOS stack-depth SIGBUS: #520 (ORA read, write and ==), #521 (Lottie JSON), #522 (SVG groups). They are open and checked together on ci/macos-reds-combined. My R2-3 fixer is stood down so it doesn't duplicate them. VI-svg, VI-lottie and LC-ora merged-done still need a green Linux job on a dev run that holds their PRs.
- 2026-10-18T16:08Z The stack-depth fixer has stood down. #520 covers ORA completely. #521 (Lottie, from another session) leaves gaps that matter to this feature:
  - Nothing pins `checkNesting` yet. A deep non-group array would catch it.
  - No mutation entries cover the moved group-walk invariants: the shapes merge, `placed` and depth + 1.
  - No test checks that a group's own shape goes in once, at its first paint.
  - The JSON value's `==` and `hash` still recurse; that only matters to tests.

  Plan: after #521 merges, run a follow-up fixer PR in round 3 that reuses the unpushed lead/vector-import-R2-3 work in /tmp/claude-0/-home-user-creative-core/ddd489f2-63fc-556a-b5ff-d210f2448d09/scratchpad/vi (13 mutation entries, 25/25 caught, not gated yet).
- 2026-10-18T16:28Z #520-522 merged 16:08Z. Round 3: fixer lead/vector-import-R3-1 launched for the #521 gaps (checkNesting pin, group-walk mutations, own-shape test, iterative JSON ==/hash). VI-5 builder resumed to open its second PR. Dev CI run 370 queued.
- 2026-10-18T16:51Z Heartbeat. Dev CI 369 Linux green; macOS SIGBUS gone after #520-522 (red only on a preview-cache budget test). R3-1 Lottie fixer gating; VI-5 second PR builder running.
- 16:54Z Belt-Slice-Done posted for VI-a and VI-lottie on run 39143654502. VI-svg waits on VI-5's second PR. Resumed VI R3-1, which had stopped early.
- 17:16Z Heartbeat: run 370 (7fcd04d) has Linux green. macOS is red only on EngineStressTests (7.0 s vs 5 s), which is outside this lead; groupManyBudget passed. All round-3 agents are gating, queued on the CI lock. No new lead PRs since #525 and #526. VI-svg waits on VI-5's second PR.
- 17:38Z Heartbeat: all five round-3 agents are gating, serialized on the CI lock. No lead PR is open. Dev run 373 (66bd163, #535 engine-stress perf) is queued. Disk: 17 GB free.
