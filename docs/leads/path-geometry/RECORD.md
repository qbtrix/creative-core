# path-geometry lead record

Issue: #430 · Packet: docs/blueprints/core/features/path-geometry.md
Run: act-1a1541f2193-03la · Session: https://claude.ai/code/session_01UoKtqjbgWBMsvLqfXb3f42 · Started: 2026-10-19T12:57Z
Line lead for: layered-codecs (#438, already done by run act-1a14de006be-1kmq), masks-mattes (#431), path-geometry (#430)
Stage: 3 wave 2
Base: 0b5a641be359e283625fa5c798b8d02872fad344
Next: P2 (PG-edit) PR opening after rebase; P3 (measure) stacked on P2; P4 (boolean) building; P5, P6 wait

## Slices
| slice | tasks | waits on | state | Slice-Done run | Mac-Finish |
|---|---|---|---|---|---|
| PG-a | PG-1, PG-7 | nothing | done | https://github.com/qbtrix/creative-core/actions/runs/39263347459 | none |
| PG-edit | PG-3, PG-4 (+ edit share of PG-2) | PG-a | open | | none |
| PG-measure | PG-5, PG-6 (+ measure share of PG-2) | PG-a | open | | none |
| PG-shape | PG-9, PG-10, PG-8 (+ shape share of PG-2) | PG-a | open | | none |
| PG-z | PG-11, PG-12 (`feature-done`) | every slice above | open | | none |

## PRs (rule 20: one PR per slice, failing test first; split where the 400-line cap forces it)
| pr id | slice | tasks | files (owned) | test | mutation plan | PR | state |
|---|---|---|---|---|---|---|---|
| P1 | PG-a | PG-1, PG-7 | PathOps/{PathOps,PathEdit,PathMeasure,PathOutline,PathBoolean}.swift, Geometry.swift, PathOpsShapeTests, PathAreaSupport, geometry.json | PathOpsShapeTests | none (declarations) | #713 | merged |
| P2 | PG-edit | PG-3, PG-4 | PathEdit.swift, PathFixtures, PathEditTests | PathEditTests | FlarePathEdit | | rebasing onto dev |
| P3 | PG-measure | PG-5, PG-6 | PathMeasure.swift, PathPropertySupport, PathMeasureTests, PathTrimDashTests | both | FlarePathMeasure | | building, stacked on P2 |
| P4 | PG-shape | PG-9, PG-10 | PathBoolean.swift, PathBooleanTests, PathBooleanFuzzTests | both | FlarePathBoolean | | building |
| P5 | PG-shape | PG-8 | PathOutline.swift, PathOutlineTests | PathOutlineTests | FlarePathOutline | | waits P4 |
| P6 | PG-z | PG-11, PG-12 | PathOpsWalkTests, PathOpsBudgetTests, geometry.json, packet | walk | none | | waits all |

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|

## Decisions
- One wave plan across masks-mattes and path-geometry (rule 19); layered-codecs was finished by the previous run (contact sheet on #438 at 2026-10-18T20:44Z), so this run only confirms it.
- Rule 20 overrides the packet's per-task PRs: PG-2's disabled suites are not a separate PR; each slice PR's first commit adds its own failing suite.
- PG-a carries PG-1 and PG-7 (area helpers); fixtures (PG-3) ride PG-edit and generators (PG-5) ride PG-measure.
- PG-shape is two PRs (boolean, then outline) because together they pass the 400-line cap and the outline unions through `combine`.
- Builder branches are `lead/path-geometry-<pr id>`.

## Open
- none
