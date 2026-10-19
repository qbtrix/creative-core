# path-geometry lead record

Issue: #430 · Packet: docs/blueprints/core/features/path-geometry.md
Run: act-1a1541f2193-03la · Session: https://claude.ai/code/session_01UoKtqjbgWBMsvLqfXb3f42 · Started: 2026-10-19T12:57Z
Line lead for: layered-codecs (#438, already done by run act-1a14de006be-1kmq), masks-mattes (#431), path-geometry (#430)
Stage: 4 round 2 (dev f99bcc4e; gate and mutation running)
Base: 0b5a641be359e283625fa5c798b8d02872fad344
Next: P3 (measure) and P4 (boolean) open once their regates pass; PG-edit done (run 39289117245)

## Slices
| slice | tasks | waits on | state | Slice-Done run | Mac-Finish |
|---|---|---|---|---|---|
| PG-a | PG-1, PG-7 | nothing | done | https://github.com/qbtrix/creative-core/actions/runs/39263347459 | none |
| PG-edit | PG-3, PG-4 (+ edit share of PG-2) | PG-a | done | https://github.com/qbtrix/creative-core/actions/runs/39289117245 | none |
| PG-measure | PG-5, PG-6 (+ measure share of PG-2) | PG-a | open | | none |
| PG-shape | PG-9, PG-10, PG-8 (+ shape share of PG-2) | PG-a | open | | none |
| PG-z | PG-11, PG-12 (`feature-done`) | every slice above | open | | none |

## PRs (rule 20: one PR per slice, failing test first; split where the 400-line cap forces it)
| pr id | slice | tasks | files (owned) | test | mutation plan | PR | state |
|---|---|---|---|---|---|---|---|
| P1 | PG-a | PG-1, PG-7 | PathOps/{PathOps,PathEdit,PathMeasure,PathOutline,PathBoolean}.swift, Geometry.swift, PathOpsShapeTests, PathAreaSupport, geometry.json | PathOpsShapeTests | none (declarations) | #713 | merged |
| P2 | PG-edit | PG-3, PG-4 | PathEdit.swift, PathFixtures, PathEditTests | PathEditTests | FlarePathEdit | #723 | merged |
| P3 | PG-measure | PG-5, PG-6 | PathMeasure.swift, PathPropertySupport, PathMeasureTests, PathTrimDashTests | both | FlarePathMeasure | #735 | merged 18:10 (ffc7dfef) |
| P4 | PG-shape | PG-9, PG-10 | PathBoolean.swift, PathBooleanTests, PathBooleanFuzzTests | both | FlarePathBoolean | #731 | merged 17:44 |
| P5 | PG-shape | PG-8 | PathOutline.swift, PathOutlineTests | PathOutlineTests | FlarePathOutline | | building, stacked on P4 |
| P6 | PG-z | PG-11, PG-12 | PathOpsWalkTests, PathOpsBudgetTests, geometry.json, packet | walk | none | | waits all |

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|
| 1 | a658945b | builders' gates | per plan, all caught | 39279766862 | correctness, robustness, reuse, tests+mutation, first-use clarity | 0 blockers, 5 should-fix, 7 nits (across both features) | lead/path-geometry-r1-b1 | no |

- Round-1 path fixes: PR #733 (lead/path-geometry-r1-b1, 5/5 FlarePathEdit, 95 lines). Fixed the quad and closing-segment insert test, the curved removeAnchor test, closest via cubicAt plus a 1e-9 stop, and the docs; Wang's step count moved to a shared `Path.cubicSegments`. The `<=` index-mutant finding is answered: the remove traps before any error, so the run still fails and the mutant counts as caught; its note is reworded.

## Decisions
- One wave plan across masks-mattes and path-geometry (rule 19); layered-codecs was finished by the previous run (contact sheet on #438 at 2026-10-18T20:44Z), so this run only confirms it.
- Rule 20 overrides the packet's per-task PRs: PG-2's disabled suites are not a separate PR; each slice PR's first commit adds its own failing suite.
- PG-a carries PG-1 and PG-7 (area helpers); fixtures (PG-3) ride PG-edit and generators (PG-5) ride PG-measure.
- PG-shape is two PRs (boolean, then outline) because together they pass the 400-line cap and the outline unions through `combine`.
- Builder branches are `lead/path-geometry-<pr id>`.
- P4 boolean uses band-indexed pair splitting with per-segment ray-cast winding, not the packet's full sweep (marked `ponytail:`, the fallback is a sweep-line event queue). PG-11's 2×5,000-vertex ≤50 ms budget is the real test and is measured in P6. Output is polygons only, with no curve refit.

## Open
- none
