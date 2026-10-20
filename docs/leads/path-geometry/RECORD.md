# path-geometry lead record

Issue: #430 · Packet: docs/blueprints/core/features/path-geometry.md
Run: act-1a15685b8d2-jkm8 · Session: https://claude.ai/code/session_0155HiDB6qGDiNT4Jp56T1UA · Resumed: 2026-10-19T23:36Z on dev fb09fdc2 (previous run act-1a1541f2193-03la)
Line lead for: layered-codecs (#438, already done by run act-1a14de006be-1kmq), masks-mattes (#431), path-geometry (#430)
Stage: 3 final slice PG-z: P6b open as #745 (ced9dc17, fast-lane + feature-done, CI: PASS 2062 tests)
Base: 0b5a641be359e283625fa5c798b8d02872fad344
Next: #745 merges and dispatches dev CI; Slice-Done PG-shape and PG-z on that run; then Anatomy round 3 on dev

## Slices
| slice | tasks | waits on | state | Slice-Done run | Mac-Finish |
|---|---|---|---|---|---|
| PG-a | PG-1, PG-7 | nothing | done | https://github.com/qbtrix/creative-core/actions/runs/39263347459 | none |
| PG-edit | PG-3, PG-4 (+ edit share of PG-2) | PG-a | done | https://github.com/qbtrix/creative-core/actions/runs/39289117245 | none |
| PG-measure | PG-5, PG-6 (+ measure share of PG-2) | PG-a | done | https://github.com/qbtrix/creative-core/actions/runs/39300831435 | none |
| PG-shape | PG-9, PG-10, PG-8 (+ shape share of PG-2) | PG-a | merged, waits a green dev run holding e2b83d0a | | none |
| PG-z | PG-11, PG-12 (`feature-done`) | every slice above | open | | none |

## PRs (rule 20: one PR per slice, failing test first; split where the 400-line cap forces it)
| pr id | slice | tasks | files (owned) | test | mutation plan | PR | state |
|---|---|---|---|---|---|---|---|
| P1 | PG-a | PG-1, PG-7 | PathOps/{PathOps,PathEdit,PathMeasure,PathOutline,PathBoolean}.swift, Geometry.swift, PathOpsShapeTests, PathAreaSupport, geometry.json | PathOpsShapeTests | none (declarations) | #713 | merged |
| P2 | PG-edit | PG-3, PG-4 | PathEdit.swift, PathFixtures, PathEditTests | PathEditTests | FlarePathEdit | #723 | merged |
| P3 | PG-measure | PG-5, PG-6 | PathMeasure.swift, PathPropertySupport, PathMeasureTests, PathTrimDashTests | both | FlarePathMeasure | #735 | merged 18:10 (ffc7dfef) |
| P4 | PG-shape | PG-9, PG-10 | PathBoolean.swift, PathBooleanTests, PathBooleanFuzzTests | both | FlarePathBoolean | #731 | merged 17:44 |
| P5 | PG-shape | PG-8 | PathOutline.swift, PathOutlineTests | PathOutlineTests | FlarePathOutline | #739 | merged 19:50 (e2b83d0a) |
| P6 | PG-z | PG-11, PG-12 | PathOpsWalkTests, PathOpsBudgetTests, geometry.json, packet | walk | none | | P6a #743 merged (fb09fdc2); P6b #745 open (ced9dc17, +207/-2, feature-done) |

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|
| 1 | a658945b | builders' gates | per plan, all caught | 39279766862 | correctness, robustness, reuse, tests+mutation, first-use clarity | 0 blockers, 5 should-fix, 7 nits (across both features) | lead/path-geometry-r1-b1 | no |
| 2 | 305975a7 | CI: PASS | 195/195 (136 + 59 re-run after an OOM kill) | | first-use clarity, contract, undo, robustness, tests+mutation | 18 (8 major, 10 minor; 1 nit skipped) across both features | lead/masks-mattes-r2-b1, lead/masks-mattes-r2-b2, lead/path-geometry-r2-b1 | no |
| 3 | 9714ff33 | CI: PASS | 221/221 | 39352093719 | first-use clarity, contract, undo, robustness, tests+mutation | 17 (5 major, 12 minor; 1 refuted) across both features | lead/path-geometry-r3-pg, lead/masks-mattes-r3-mm-model, lead/masks-mattes-r3-mm-export | no |
| 4 | 672d6b8c | CI: PASS | 230/230 | - | first-use clarity, contract, undo, robustness, tests+mutation | 10 (3 major, 7 minor; 0 refuted) across both features | lead/path-geometry-r4-pg, lead/masks-mattes-r4-mm (feature-done) | no (round cap reached) |

- Round-1 path fixes: PR #733 (lead/path-geometry-r1-b1, 5/5 FlarePathEdit, 95 lines). Fixed the quad and closing-segment insert test, the curved removeAnchor test, closest via cubicAt plus a 1e-9 stop, and the docs; Wang's step count moved to a shared `Path.cubicSegments`. The `<=` index-mutant finding is answered: the remove traps before any error, so the run still fails and the mutant counts as caught; its note is reworded.

- P5 note for round 3: `combine` returns sliver and zero-area contours when many nearly collinear edges meet at one point (865 contours unioning per-segment rectangles of a flattened circle). P5 sidesteps it with one offset loop per subpath; round 3 must look at `combine` itself.

- Round-2 path fixes: PR #741 (lead/path-geometry-r2-b1, merged 21:11 as 4de35272, 25/25, 191 lines). Dash cut binary-searches its span (a 20k-point dash went from >300 s to <3 s); `combine` gains `maxBooleanWork = 50,000,000` (pair tests, cuts, ray steps) and throws tooComplex past it, while maxBooleanVertices stays 200,000; non-finite cross products throw nonFinite; smooth/symmetric convert leaves the anchor unchanged on non-finite arms; docs for tooComplex, dashed and open subpaths in combine.

- P6 release budgets on Linux before #741 (dev 758f0c7a): nearest 15.7 ms (budget 2), trim 59.4 ms (5), dash [400, 200] 7,034 ms (5), union 2 x 5,000 22.0 ms (50, within). Walk passes. The scribble flattens to 401,801 points, 8.49M long. P6 is rebasing on #741 and fixing the rows still over; budgets are 'release, reported' (scripts/ci prints them in debug).

## Decisions
- Boolean time is bounded by a work cap, not a lower vertex cap (round 2): a real 2 x 100k input may hit the work cap first.
- One wave plan across masks-mattes and path-geometry (rule 19); layered-codecs was finished by the previous run (contact sheet on #438 at 2026-10-18T20:44Z), so this run only confirms it.
- Rule 20 overrides the packet's per-task PRs: PG-2's disabled suites are not a separate PR; each slice PR's first commit adds its own failing suite.
- PG-a carries PG-1 and PG-7 (area helpers); fixtures (PG-3) ride PG-edit and generators (PG-5) ride PG-measure.
- PG-shape is two PRs (boolean, then outline) because together they pass the 400-line cap and the outline unions through `combine`.
- Builder branches are `lead/path-geometry-<pr id>`.
- P4 boolean uses band-indexed pair splitting with per-segment ray-cast winding, not the packet's full sweep (marked `ponytail:`, the fallback is a sweep-line event queue). PG-11's 2×5,000-vertex ≤50 ms budget is the real test and is measured in P6. Output is polygons only, with no curve refit.

## Open
- none
- P6 at 33c586ec (on 4de35272), release: nearest 1.68 ms (2), trim 23.2 ms (5), dash 43.4 ms / 26 ms quiet (5), union 21-36 ms (50). Flatten alone of the random scribble is 5.7 ms (401,801 points, 8.49M long), so trim and dash cannot reach 5 ms on it.
- Decision (lead, 2026-10-19): PG-11's trim/dash/nearest rows run on a new seeded `handScribble()` (10,000 anchors, local steps, controls near anchors), a realistic drag-time stroke; budgets unchanged; `scribble()` kept for PG-3 tests. Recorded as a deviation in the packet. If still over, the rows go to the Mac finish.
- P6 on handScribble (128,064 long, 51,159 points), release x3: nearest 0.51-0.61 ms (2), trim 1.70-2.26 ms (5), dash 4.32-5.07 ms (5, thin: one run 0.07 over under load), union 20.6-23.4 ms (50). Dash at ~2.5x trim is a round-3 look; Mac finish confirms the margin.
- P6b #745 merged 23:47 as 47c283f (feature-done). dev CI run 39343832741 on 47c283f: Linux, Mutation, Mutation anchors, Fast lane tests green; macOS queued. PG-shape and PG-z Slice-Done wait on it.
- dev CI https://github.com/qbtrix/creative-core/actions/runs/39343832741 green on 47c283f (macOS too): Belt-Slice-Done PG-shape and PG-z posted on #430. Every path-geometry slice is merged-done. Contact sheet follows Anatomy round 3 on dev after masks-mattes' M7b.
- Anatomy round 3 started on dev 9714ff33 (masks-mattes' last PR merged), covering both features.
- Round 3 on 9714ff33: scripts/ci CI: PASS; mutate --changed-since base at 161/221 caught, 0 escaped so far. Next: critic panel.
- Round 3 on 9714ff33: mutate --changed-since base 221/221 caught (53.7 min). Critic panel running (clarity, contract, undo, robustness, tests), run wf_89ce91c1-7f8.
- Round 3 panel (wf_89ce91c1-7f8) on 9714ff33: not clean, 17 confirmed. Majors: outlined's bad width throws nonFinite with a NaN-only doc; outlined builds join/cap loops unbounded before combine's vertex cap; Stroker.vertex inner-side choice untested; render-list mask points not charged to maxExpandedPoints; SVG difference masks refused; SVG hard-clip predicate's feather/opacity/inverted conditions untested. Fix batch r3 (3 fixers, disjoint files) running; round 4 is the last.
- Fix batch r3 launched (wf_e581ccf2-fc2): r3-pg (outlined doc and loop cap, maxDashSteps public, trimmed doc, notBuilt, inner-join and period tests), r3-mm-model (render-list mask point charge, MatteLink/ClippedPath docs, matte-cycle doc, packet contract and Deviations), r3-mm-export (SVG difference masks, hard-clip predicate and filter-region tests, feather radius message). Each opens one fast-lane PR after CI: PASS and mutate.
- Round-3 fixes merged: #749 (r3-mm-model, b9a101f2, 27/27: mask points charged to maxExpandedPoints, ClippedPath and SetTrackMatte docs, packet contract and Deviations), #750 (r3-mm-export, 35bd344a, 12/12: SVG difference masks written, hard-clip predicate and outside-feather region tests, feather radius limit message), #751 (r3-pg, 672d6b8c, 16/16: outlined caps points before combine, inner-join pivot test, dash period overflow, outlined/nonFinite/trimmed docs, maxDashSteps public, notBuilt documented as not thrown). Left for the next PR: SVGExporter.export doc still lists "mask difference"; path-geometry packet still names notBuilt. Round 4 (last) started on 672d6b8c: gate, then mutate --changed-since 0b5a641b, then the panel with the same lenses.

- 2026-10-20T04:14:41Z Round 4 (last, cap) panel wf_d9fad7c0-bd3: 3 major (SVG export doc lists a mask-difference throw that no longer exists; matte cycle throws invalidDocument instead of a typed case; Ruler flattening has no point cap), 7 minor (clarity docs, error-case names, two mutation gaps in PathOutline). Final fix batch wf_efd98b53-ebf: one feature-done PR per feature. Anything the fixers leave open is filed as a gap issue.

- 2026-10-20T04:35:54Z Round-4 fixes: #754 (masks-mattes, feature-done, merged; typed CommandError.matteCycle, SVG export doc, ClipMask rename, mask docs; 43/43 mutants) and #755 (path-geometry, feature-done, open and clean; measure point cap Path.maxMeasurePoints, GeometryError.invalidStroke, tooComplex carries its cap, outline budget off-by-one, PathOps docs, packet notBuilt note; 29/29 mutants). All 10 round-4 findings fixed; no gap issues needed. Next: dev CI after the feature-done merges, then the contact sheets.
