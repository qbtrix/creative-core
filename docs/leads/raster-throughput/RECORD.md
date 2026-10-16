# raster-throughput lead record

Issue: #311 · Packet: docs/blueprints/core/features/raster-throughput.md (in PR #310, read from branch docs/core-packets-wave2)
Run: act-1a142b4b264-6dd2 · Session: claude/raster-throughput-lead-pyis7l · Started: 2026-10-16T03:05Z
Stage: 4 round 3
Base: fe5bc5347337b361a511c148b58fbd56163e09fb (round 3; first base f05665f5b54a461ab4a4e981ed7d7b01d7ab37ed)
Next: wait for the lane on #331 (feature-done) and the CI run it dispatches on dev; round 4 (last) on that SHA; then the contact sheet and the gap issue for the budgets

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| RT-1 | a | `DisplayTransfer`: decode table, encode thresholds, byte rule | Sources/CoreColor/DisplayTransfer.swift, Tests/CoreColorTests/DisplayTransferTests.swift, Tests/mutations/CoreColorDisplayTransfer.json, docs/c4/parts/creative-core/corecolor/color-spaces.json | DisplayTransferTests | CoreColorDisplayTransfer.json (6/6 caught) | #319 | merged |
| RT-3 | a | in-place `composite(_:x:y:mode:opacity:)`, free functions call it, opaque `.normal` row copy, `updateRow` | Sources/CoreRaster/Composite.swift, Sources/CoreRaster/PixelBuffer.swift, Tests/CoreRasterTests/CompositeInPlaceTests.swift, Tests/mutations/CoreRasterCompositeInPlace.json, docs/c4/parts/creative-core/coreraster/compositing.json | CompositeInPlaceTests | CoreRasterCompositeInPlace.json (3/3 caught) | #320 | merged |
| RT-4 | a | `smallDabOn12MegapixelsIsFast` times thread CPU time (closes #300) | Tests/CoreRasterTests/RetouchBoundsTests.swift, Tests/CoreRasterTests/Support.swift | smallDabOn12MegapixelsIsFast + helper busy-loop check | – | #318 | merged |
| RT-2 | b | `rgba8` / `init(rgba8:)` over `DisplayTransfer`; region `rgba8(x:y:width:height:)` | Sources/CoreRaster/DisplayBytes.swift, Tests/CoreRasterTests/DisplayBytesFastPathTests.swift, Tests/mutations/CoreRaster.json, Tests/mutations/CoreRasterDisplayBytes.json, docs/c4/parts/creative-core/coreraster/pixel-buffer.json | DisplayBytesFastPathTests | repoint 3 CoreRaster.json entries + CoreRasterDisplayBytes.json | – | #321 | merged |
| RT-2b | b2 | display encode by bucket table, inlinable across modules, to reach RT-5's budgets (RT-2 measured rgba8 450 ms, init 137 ms vs 30 ms) | Sources/CoreColor/DisplayTransfer.swift, Sources/CoreRaster/DisplayBytes.swift, their tests and mutation plans | existing equivalence tests + bucket invariant test | CoreColorDisplayTransfer.json (10/10 caught) | #322 | merged |
| RT-5 | c | release budgets on one core and four; `feature-done` (closes #309) | Tests/CoreRasterTests/RasterThroughputBudgetTests.swift | RasterThroughputBudgetTests | – | #323 | merged |

Acceptance tests and quality bars: the packet's "Acceptance test per task" and "Quality tests" tables (binding; not copied to avoid drift).

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|
| 1 | f7b9bcf | PASS (814 tests) | 39/39 (validate: 203 anchors) | – (not dispatched yet) | clarity, contract, robustness, tests, compat, performance | 4 major, 9 minor (scratchpad r1/findings.md) | #324 (r1-b1, merged), #325 (r1-b2, merged), #326 (r1-b3, merged) | no |
| 2 | f27f104 | PASS (816 tests) | 43/43 (validate: 207 anchors) | – | same 6 | 1 major (opacity==1 half of the opaque-row guard untested, no mutation entry), 2 minor | #327 (r2-b1, merged) | no |
| 3 | fe5bc53 | PASS (816 tests) | 44/44 (validate: 208 anchors) | – | same 6 | 0 blocker/major; 3 minor (C4 compositing description, band labels, region check duplicates cropped's) | #331 (r3-b1, feature-done) | yes |

## Decisions
- Packet not yet on dev (PR #310 open); builders read it from origin/docs/core-packets-wave2.
- Swift was missing in the container; ran scripts/cloud-setup.sh (Swift 6.3.3).
- gh CLI is not authenticated here; builders push their branch and the lead opens PRs and labels through the GitHub MCP (author prakashUXtech, on the lane allowlist).
- Task branches are `rt/<id>` (a `lead/raster-throughput/<id>` ref would clash with the lead branch).
- Builders run as worktree subagents (Agent tool), per the playbook's fallback.
- Session restarted after wave a builders finished; resumed from their pushed branches.
- RT-2 shipped correct but slow (2-6x faster than today, 15x over budget): the 8-step search in DisplayTransfer.encode dominates. Added task RT-2b rather than widening RT-2.
- RT-2b: bucket-table encode + @inlinable; bytes identical; 2.4-3.5x faster. Further SIMD row API would change the contract slice: not done without the captain.
- Round 3 minors ride the last PR, which carries `feature-done`; round 4 (the budget's last) runs on the SHA it lands, with the CI run it dispatches.
- Round 1 finding 11 (best of 3 vs median): keep the median of 5; the packet's Done check says medians.
- Round 1: internal `updateRow` may take an UnsafeMutableBufferPointer (same name and contract); public API unchanged.
- RT-5 opened without `feature-done`: the Anatomy loop follows it, so the last fix PR (or a RECORD/packet status PR) carries `feature-done`.
- RT-5 keeps the packet's budgets unchanged (no self-widening); misses go in the contact sheet and a gap issue.
- RT-2 starts from rt/rt-1 before #319 merges, and rebases on dev once it does.

## Open
- Round 3 release medians (fe5bc53, 3 runs, ms): copy 146/147/150 (30), paste 113/109/113 (30), copy band 38/33/37 (10), paste band 37/33/34 (10), merge 107/105/103 (60), flatten 211/219/228 (120), merge band 29/30/35 (20), tile 0.43/0.71/0.46 (0.5; 2 of 3 within).
- Round 2 release medians (f27f104, quiet box, 3 runs, ms): copy 152/156/154 (30), paste 115/121/108 (30), copy band 38/36/35 (10), paste band 37/39/36 (10), merge 105/101/97 (60), flatten 209/210/215 (120), merge band 29/32/29 (20), tile 0.43/0.43/0.76 (0.5; 2 of 3 within), opaque copy 57-60 and multiply 104-107 report-only.
- Finding 6's Float alpha table not done: it moves a CoreRaster.json anchor ("decoding display bytes does not premultiply"); ~10% on decode. Candidate for round 2.
- FlareCore EngineStressTests.thousandCommandsNearTheLayerLimitStayInBudget misses its 5 s wall budget under load 6-8 (6.1-6.9 s); not this feature's file.
- RT-5 release medians (3 runs): rgba8 173-176 ms (30), init 109-113 (30), copy band 44-59 (10), paste band 36-38 (10), merge 120-124 (60), flatten 241-286 (120), merge band 40-49 (20), tile 0.61-0.78 (0.5); opaque row copy 75-81 report-only. All 8 gated rows FAIL; equality checks pass. Composite has no allocation floor: round-1 perf target.
- Budgets: after RT-2b, 12 MP rgba8 175 ms sRGB / ~200 ms P3, init ~118 ms (budget 30), tile 0.72 ms (0.5), four bands 42 ms (10). Floor on this box: fresh 48 MB alloc 23-28 ms, 192 MB 85-94 ms (page faults). Raised with the supervisor on #311; gap issue to file at finish unless the captain re-baselines.
- Under 4-builder load, FlareCore EngineStressTests.thousandCommandsNearTheLayerLimitStayInBudget and StageBudgetTests.hitWithinBudget miss their wall-clock budgets (not this feature's files); quiet reruns pass. Watch the dev CI run.
