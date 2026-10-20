# masks-mattes lead record

Issue: #431 · Packet: docs/blueprints/core/features/masks-mattes.md
Run: act-1a15685b8d2-jkm8 · Session: https://claude.ai/code/session_0155HiDB6qGDiNT4Jp56T1UA · Resumed: 2026-10-19T23:36Z on dev fb09fdc2 (previous run act-1a1541f2193-03la)
Line lead for: layered-codecs (#438, already done), masks-mattes (#431), path-geometry (#430)
Stage: 3 final slice MM-z: M7 (623 lines) split into M7a (feather, 268), M7a2 (contours, composite skip, 24 MP budgets, 240) and M7b (walk and docs, 204, `feature-done`), stacked on dev fb09fdc2; gating
Base: 0b5a641be359e283625fa5c798b8d02872fad344
Next: M7a #746 open; M7a2 gating (stacked); M7b after #745 (P6b) merges; then Anatomy round 3 on dev

## Slices
| slice | tasks | waits on | state | Slice-Done run | Mac-Finish |
|---|---|---|---|---|---|
| MM-a | MM-1, MM-2 (folded into the first raster and vector PRs) | engine-contracts:EC-a, EC-f (both slice-done 2026-10-18) | done | https://github.com/qbtrix/creative-core/actions/runs/39279766862 | none |
| MM-raster | MM-3, MM-4, MM-5 | MM-a, engine-contracts:EC-b (done) | open | | wanted (release budgets) |
| MM-vector | MM-6, MM-7, MM-8 | MM-a | done | https://github.com/qbtrix/creative-core/actions/runs/39298046683 | none |
| MM-z | MM-9, MM-10 (`feature-done`) | MM-raster, MM-vector, path-geometry (MM-10) | open | | wanted (budgets) |

## PRs (rule 20: one PR per slice, failing test first; split where the 400-line cap forces it)
| pr id | slice | tasks | files (owned) | test | mutation plan | PR | state |
|---|---|---|---|---|---|---|---|
| M1 | MM-a + MM-raster | MM-1 (ops share), MM-3 | Masks/MaskFeather, Masks/MaskContours, MaskFixtures, MaskOpsTests | MaskOpsTests | CoreRaster.MaskFeather, CoreRaster.MaskContours | #718 | merged |
| M2 | MM-raster | MM-1 (composite share), MM-4 | Masks/MaskFromBuffer, Compositing/CompositeMasked, MaskCompositeTests | MaskCompositeTests | CoreRaster.CompositeMasked | #726 | merged |
| M3 | MM-raster | MM-5 | CPUBackend+MaskedComposite, Samples+MaskedComposite, CPUMaskedCompositeTests, goldens | CPUMaskedCompositeTests | CoreRenderCPUMaskedComposite | #737 | merged 18:16 (27542391) |
| M4 | MM-a + MM-vector | MM-2 (commands share, fixture), MM-6 | MaskCommands.swift, MaskCommandsTests, UndoPropertyTests, Fixtures/masks.flare | MaskCommandsTests | FlareMaskCommands | #720 | merged |
| M5 | MM-vector | MM-7 | RenderList.swift, MatteRenderListTests | MatteRenderListTests | FlareMatteRenderList | #724 | merged |
| M6 | MM-vector | MM-8 | Export/SVGExporter+Masks, Export/LottieExporter+Masks, both suites | both | FlareMaskExport | #729 | merged 17:06 (ccd78ae6) |
| M7a | MM-z | MM-9 (feather) | Blur, Masks/MaskFeather, MaskFeatherBoxTests | MaskFeatherBoxTests | CoreRaster.MaskFeather | #746 | open (5/5 caught) |
| M7a2 | MM-z | MM-9 (contours, composite, budgets) | Composite, CompositeMasked, Masks/MaskContours, MaskBudgetTests | MaskBudgetTests, MaskOpsTests | CoreRaster.MaskContours, CoreRaster.CompositeMasked | | gating, stacked on M7a |
| M7b | MM-z | MM-10 | MaskWalkTests (FlareCore, CoreRender), mask-walk.flare, geometry.json, packet, waves.md | MaskWalkTests | none | | waits M7a2 + path-geometry P6b |

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|
| 1 | a658945b | builders' gates | per plan, all caught | 39279766862 | correctness, robustness, reuse, tests+mutation, first-use clarity | 0 blockers, 5 should-fix, 7 nits (across both features) | lead/masks-mattes-r1-b1 | no |
| 2 | 305975a7 | CI: PASS | 195/195 (136 + 59 re-run after an OOM kill) | | first-use clarity, contract, undo, robustness, tests+mutation | 18 (8 major, 10 minor; 1 nit skipped) across both features | lead/masks-mattes-r2-b1, lead/masks-mattes-r2-b2, lead/path-geometry-r2-b1 | no |
| 3 | 9714ff33 | CI: PASS | 221/221 | 39352093719 | first-use clarity, contract, undo, robustness, tests+mutation | 17 (5 major, 12 minor; 1 refuted) across both features | lead/path-geometry-r3-pg, lead/masks-mattes-r3-mm-model, lead/masks-mattes-r3-mm-export | no |
| 4 | 672d6b8c | CI: PASS | 230/230 | - | first-use clarity, contract, undo, robustness, tests+mutation | 10 (3 major, 7 minor; 0 refuted) across both features | lead/path-geometry-r4-pg, lead/masks-mattes-r4-mm (feature-done) | no (round cap reached) |

- Round-1 masks fixes: PR #730 (lead/masks-mattes-r1-b1), merged 17:34.
- Round-1 masks raster fix: PR #738 (lead/masks-mattes-r1-b2), merged 18:24 (305975a7).

- For the next round (from M3 #737): the CPUGoldenTests header still says "133 samples in 8 goldens" (should be 145 in 9), left out for the 15-file cap. CoreRenderDispatcherW1#3 and #4 (the flipped and applying fallbacks) escape on dev, because eachNewMethodReachesTheCPU only checks the masked composite. Fold both into the next masks PR. M3 also edits ParitySamples, ParityPack and the four W1/dispatcher/parity/CPU suites, and repointed CoreRenderDispatcherW1#5.

- Round-2 masks model and export fixes: PR #740 (lead/masks-mattes-r2-b2, merged 20:44 as 758f0c7a, 43/43, 192 lines). ConvertToSymbol now refuses to split a matte pair; SVG blur is feather / 3 (MM-8 amended); export docs list every unsupported reason; Lottie mask paths are written closed; one matte level documented and pinned; overflow-safe feather scale; expectRefused takes the exact error.

- Round-2 masks raster fixes: PR #742 (lead/masks-mattes-r2-b1, merged 22:00 as 1c7ea8e1, 15/15, 129 lines). Gaussian kernel is identity when 2 sigma^2 is not normal, NaN-safe feather clamp; `contours` throws RasterError.invalid past `Mask.maxContourSegments = 4,000,000`; crossing-level test and entry; winding doc (positive shoelace in y-down = outer); W1 route test covers flipped and boxBlur; golden header 145 in 9.
- M7 (MM-z) built on lead/masks-mattes-M7 (66091bb5, 294 lines, gate PASS); PR held until r2-b1 merges, then rebase (`try` on contours) and open with `feature-done`. Linux release budgets at 6000 x 4000: masked composite 1.34 x (budget 1.3 x), feather r20 6159 ms (budget 250 ms), contours 258 ms (budget 60 ms). Feather is ~25 x over: the separable Gaussian is O(radius) per pixel; a perf fix (constant-time-per-pixel blur) goes out after r2-b1 merges, since that batch owns Blur.swift. The Mac finisher's release run decides verified.

## Decisions
- Feather is one quantity everywhere: the blur radius, sigma = feather / 3 (round 2; SVG was feather / 2).
- Rule 20: MM-1 and MM-2 (disabled checks) are not their own PRs; each slice PR adds its own failing suite as its first commit. MM-a is slice-done once M1 and M4 (which carry the fixtures) merge.
- MM-10 edits `geometry.json`, which path-geometry's last PR also edits, so M7 runs after path-geometry's P6 merges.
- Builder branches are `lead/masks-mattes-<pr id>`.

- Lottie mask `x` is Expand in the Lottie spec, not feather (the packet said feather). M6 writes `x: 0` and refuses feather as `unsupported("mask feather")`; SVG difference masks and nested mattes are refused too. Packet note to fix in M7.

## Open
- none
- M7 at f0e682aa (on 1c7ea8e1): 712 lines / 16 files, CI: PASS, mutate 25/25. Release 6000x4000: masked composite 1.20x (1.3x), contours 52.6 ms (60), feather r20 722 ms (250, over; was 6,159). Feather is now a 4-pass extended box (Gwosdek et al. 2011) past sigma 2, within 0.025 of the exact Gaussian; no golden moved.
- Decision (lead, 2026-10-19): split M7 into M7a (CoreRaster perf, on dev) and M7b (walk, budgets, docs, stacked; feature-done, Mac-Finish-Wanted). One bounded try at a column-strip vertical pass; if feather stays over, it goes to the Mac finish and round 3.
- M7a #746 merged 23:55 as b9f53dc (extended-box feather). M7a2 (contour pre-scan, masked composite skip, 24 MP budget rows; 240 lines) rebased to 3306eb6 on b9f53dc, gating. M7b (walk, packet built, waves rows; feature-done) stacked on it, opens once M7a2 merges.
- dev CI https://github.com/qbtrix/creative-core/actions/runs/39343832741 green on 47c283f: Belt-Slice-Done MM-raster and Mac-Finish-Wanted MM-raster posted on #431. M7a2 opened as #747 (3306eb6, CI: PASS, mutate 6/6 MaskContours, 5/5 CompositeMasked). M7b gating on it.
- #747 (M7a2) merged as 96e6718. M7b opened as #748 (feature-done, 52945a68, CI: PASS, 208 lines). Its merge dispatches dev CI; MM-z Slice-Done and Mac-Finish-Wanted wait on that run, then Anatomy round 3 on dev.
- #748 (M7b, feature-done) merged as 9714ff3; dev CI run 39352093719 dispatched. Anatomy round 3 started on 9714ff33 (gate + mutate --changed-since base, then the panel with the round-2 lenses).
- dev CI https://github.com/qbtrix/creative-core/actions/runs/39352093719 green on 9714ff3 (Linux, macOS, Mutation): Belt-Slice-Done MM-z and Mac-Finish-Wanted MM-z posted on #431. Every masks-mattes slice is merged-done.
- Round 3 on 9714ff33: scripts/ci CI: PASS; mutate --changed-since base at 161/221 caught, 0 escaped so far. Next: the critic panel (clarity, contract, undo, robustness, tests) once mutation finishes.
- Round 3 on 9714ff33: mutate --changed-since base 221/221 caught (53.7 min). Critic panel running (clarity, contract, undo, robustness, tests), run wf_89ce91c1-7f8.
- Round 3 panel (wf_89ce91c1-7f8) on 9714ff33: not clean, 17 confirmed. Majors: outlined's bad width throws nonFinite with a NaN-only doc; outlined builds join/cap loops unbounded before combine's vertex cap; Stroker.vertex inner-side choice untested; render-list mask points not charged to maxExpandedPoints; SVG difference masks refused; SVG hard-clip predicate's feather/opacity/inverted conditions untested. Fix batch r3 (3 fixers, disjoint files) running; round 4 is the last.
- Fix batch r3 launched (wf_e581ccf2-fc2): r3-pg (outlined doc and loop cap, maxDashSteps public, trimmed doc, notBuilt, inner-join and period tests), r3-mm-model (render-list mask point charge, MatteLink/ClippedPath docs, matte-cycle doc, packet contract and Deviations), r3-mm-export (SVG difference masks, hard-clip predicate and filter-region tests, feather radius message). Each opens one fast-lane PR after CI: PASS and mutate.
- Round-3 fixes merged: #749 (r3-mm-model, b9a101f2, 27/27: mask points charged to maxExpandedPoints, ClippedPath and SetTrackMatte docs, packet contract and Deviations), #750 (r3-mm-export, 35bd344a, 12/12: SVG difference masks written, hard-clip predicate and outside-feather region tests, feather radius limit message), #751 (r3-pg, 672d6b8c, 16/16: outlined caps points before combine, inner-join pivot test, dash period overflow, outlined/nonFinite/trimmed docs, maxDashSteps public, notBuilt documented as not thrown). Left for the next PR: SVGExporter.export doc still lists "mask difference"; path-geometry packet still names notBuilt. Round 4 (last) started on 672d6b8c: gate, then mutate --changed-since 0b5a641b, then the panel with the same lenses.

- 2026-10-20T04:14:41Z Round 4 (last, cap) panel wf_d9fad7c0-bd3: 3 major (SVG export doc lists a mask-difference throw that no longer exists; matte cycle throws invalidDocument instead of a typed case; Ruler flattening has no point cap), 7 minor (clarity docs, error-case names, two mutation gaps in PathOutline). Final fix batch wf_efd98b53-ebf: one feature-done PR per feature. Anything the fixers leave open is filed as a gap issue.

- 2026-10-20T04:35:54Z Round-4 fixes: #754 (masks-mattes, feature-done, merged; typed CommandError.matteCycle, SVG export doc, ClipMask rename, mask docs; 43/43 mutants) and #755 (path-geometry, feature-done, open and clean; measure point cap Path.maxMeasurePoints, GeometryError.invalidStroke, tooComplex carries its cap, outline budget off-by-one, PathOps docs, packet notBuilt note; 29/29 mutants). All 10 round-4 findings fixed; no gap issues needed. Next: dev CI after the feature-done merges, then the contact sheets.

## Finish

- dev CI run https://github.com/qbtrix/creative-core/actions/runs/39370425442 on e09c6c30 is green (Linux, macOS, Mutation, anchors, fast-lane tests); Promote moved main to e09c6c30.
- Belt-Contact-Sheet posted on #431: https://github.com/qbtrix/creative-core/issues/431#issuecomment-6284657995
- Lead stopped: every slice is done, the feature-done PR is merged, and no gap issues are open from this run.
