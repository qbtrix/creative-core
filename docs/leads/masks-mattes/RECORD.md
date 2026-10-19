# masks-mattes lead record

Issue: #431 · Packet: docs/blueprints/core/features/masks-mattes.md
Run: act-1a1541f2193-03la · Session: https://claude.ai/code/session_01UoKtqjbgWBMsvLqfXb3f42 · Started: 2026-10-19T12:57Z
Line lead for: layered-codecs (#438, already done), masks-mattes (#431), path-geometry (#430)
Stage: 3 wave 2
Base: 0b5a641be359e283625fa5c798b8d02872fad344
Next: M3 (CPU composite) and M6 (exporters) building stacked; rebase and open once their bases merged (both merged)

## Slices
| slice | tasks | waits on | state | Slice-Done run | Mac-Finish |
|---|---|---|---|---|---|
| MM-a | MM-1, MM-2 (folded into the first raster and vector PRs) | engine-contracts:EC-a, EC-f (both slice-done 2026-10-18) | done | https://github.com/qbtrix/creative-core/actions/runs/39279766862 | none |
| MM-raster | MM-3, MM-4, MM-5 | MM-a, engine-contracts:EC-b (done) | open | | wanted (release budgets) |
| MM-vector | MM-6, MM-7, MM-8 | MM-a | open | | none |
| MM-z | MM-9, MM-10 (`feature-done`) | MM-raster, MM-vector, path-geometry (MM-10) | open | | wanted (budgets) |

## PRs (rule 20: one PR per slice, failing test first; split where the 400-line cap forces it)
| pr id | slice | tasks | files (owned) | test | mutation plan | PR | state |
|---|---|---|---|---|---|---|---|
| M1 | MM-a + MM-raster | MM-1 (ops share), MM-3 | Masks/MaskFeather, Masks/MaskContours, MaskFixtures, MaskOpsTests | MaskOpsTests | CoreRaster.MaskFeather, CoreRaster.MaskContours | #718 | merged |
| M2 | MM-raster | MM-1 (composite share), MM-4 | Masks/MaskFromBuffer, Compositing/CompositeMasked, MaskCompositeTests | MaskCompositeTests | CoreRaster.CompositeMasked | #726 | merged |
| M3 | MM-raster | MM-5 | CPUBackend+MaskedComposite, Samples+MaskedComposite, CPUMaskedCompositeTests, goldens | CPUMaskedCompositeTests | CoreRenderCPUMaskedComposite | | building, stacked on M2 |
| M4 | MM-a + MM-vector | MM-2 (commands share, fixture), MM-6 | MaskCommands.swift, MaskCommandsTests, UndoPropertyTests, Fixtures/masks.flare | MaskCommandsTests | FlareMaskCommands | #720 | merged |
| M5 | MM-vector | MM-7 | RenderList.swift, MatteRenderListTests | MatteRenderListTests | FlareMatteRenderList | #724 | merged |
| M6 | MM-vector | MM-8 | Export/SVGExporter+Masks, Export/LottieExporter+Masks, both suites | both | FlareMaskExport | #729 | merged 17:06 (ccd78ae6) |
| M7 | MM-z | MM-9, MM-10 | MaskWalkTests, MaskBudgetTests, geometry.json, packet | walk | none | | waits all + path-geometry P6 |

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|
| 1 | a658945b | builders' gates | per plan, all caught | 39279766862 | correctness, robustness, reuse, tests+mutation, first-use clarity | 0 blockers, 5 should-fix, 7 nits (across both features) | lead/masks-mattes-r1-b1 | no |

- Round-1 masks fixes: PR #730 (lead/masks-mattes-r1-b1), in lane.

## Decisions
- Rule 20: MM-1 and MM-2 (disabled checks) are not their own PRs; each slice PR adds its own failing suite as its first commit. MM-a is slice-done once M1 and M4 (which carry the fixtures) merge.
- MM-10 edits `geometry.json`, which path-geometry's last PR also edits, so M7 runs after path-geometry's P6 merges.
- Builder branches are `lead/masks-mattes-<pr id>`.

- Lottie mask `x` is Expand in the Lottie spec, not feather (the packet said feather). M6 writes `x: 0` and refuses feather as `unsupported("mask feather")`; SVG difference masks and nested mattes are refused too. Packet note to fix in M7.

## Open
- none
