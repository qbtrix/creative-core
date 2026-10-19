# masks-mattes lead record

Issue: #431 · Packet: docs/blueprints/core/features/masks-mattes.md
Run: act-1a15685b8d2-jkm8 · Session: https://claude.ai/code/session_0155HiDB6qGDiNT4Jp56T1UA · Resumed: 2026-10-19T23:36Z on dev fb09fdc2 (previous run act-1a1541f2193-03la)
Line lead for: layered-codecs (#438, already done), masks-mattes (#431), path-geometry (#430)
Stage: 3 final slice MM-z: M7 (623 lines) split into M7a (feather, 268), M7a2 (contours, composite skip, 24 MP budgets, 240) and M7b (walk and docs, 204, `feature-done`), stacked on dev fb09fdc2; gating
Base: 0b5a641be359e283625fa5c798b8d02872fad344
Next: open M7a and M7a2 once gated; M7b after P6b (#path-geometry PG-z) merges (both edit geometry.json); then Anatomy round 3 on dev

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
| M7a | MM-z | MM-9 (feather) | Blur, Masks/MaskFeather, MaskFeatherBoxTests | MaskFeatherBoxTests | CoreRaster.MaskFeather | | gating |
| M7a2 | MM-z | MM-9 (contours, composite, budgets) | Composite, CompositeMasked, Masks/MaskContours, MaskBudgetTests | MaskBudgetTests, MaskOpsTests | CoreRaster.MaskContours, CoreRaster.CompositeMasked | | gating, stacked on M7a |
| M7b | MM-z | MM-10 | MaskWalkTests (FlareCore, CoreRender), mask-walk.flare, geometry.json, packet, waves.md | MaskWalkTests | none | | waits M7a2 + path-geometry P6b |

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|
| 1 | a658945b | builders' gates | per plan, all caught | 39279766862 | correctness, robustness, reuse, tests+mutation, first-use clarity | 0 blockers, 5 should-fix, 7 nits (across both features) | lead/masks-mattes-r1-b1 | no |
| 2 | 305975a7 | CI: PASS | 195/195 (136 + 59 re-run after an OOM kill) | | first-use clarity, contract, undo, robustness, tests+mutation | 18 (8 major, 10 minor; 1 nit skipped) across both features | lead/masks-mattes-r2-b1, lead/masks-mattes-r2-b2, lead/path-geometry-r2-b1 | no |

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
