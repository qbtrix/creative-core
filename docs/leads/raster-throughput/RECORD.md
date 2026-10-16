# raster-throughput lead record

Issue: #311 · Packet: docs/blueprints/core/features/raster-throughput.md (in PR #310, read from branch docs/core-packets-wave2)
Run: act-1a142b4b264-6dd2 · Session: claude/raster-throughput-lead-pyis7l · Started: 2026-10-16T03:05Z
Stage: 4 round 1
Base: f7b9bcfb2d91d5c151e289864008f76f75c64314 (round 1; first base f05665f5b54a461ab4a4e981ed7d7b01d7ab37ed)
Next: round 1: gate + mutate running on f7b9bcf (scratchpad/r1), then the critic panel

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

## Decisions
- Packet not yet on dev (PR #310 open); builders read it from origin/docs/core-packets-wave2.
- Swift was missing in the container; ran scripts/cloud-setup.sh (Swift 6.3.3).
- gh CLI is not authenticated here; builders push their branch and the lead opens PRs and labels through the GitHub MCP (author prakashUXtech, on the lane allowlist).
- Task branches are `rt/<id>` (a `lead/raster-throughput/<id>` ref would clash with the lead branch).
- Builders run as worktree subagents (Agent tool), per the playbook's fallback.
- Session restarted after wave a builders finished; resumed from their pushed branches.
- RT-2 shipped correct but slow (2-6x faster than today, 15x over budget): the 8-step search in DisplayTransfer.encode dominates. Added task RT-2b rather than widening RT-2.
- RT-2b: bucket-table encode + @inlinable; bytes identical; 2.4-3.5x faster. Further SIMD row API would change the contract slice: not done without the captain.
- RT-5 opened without `feature-done`: the Anatomy loop follows it, so the last fix PR (or a RECORD/packet status PR) carries `feature-done`.
- RT-5 keeps the packet's budgets unchanged (no self-widening); misses go in the contact sheet and a gap issue.
- RT-2 starts from rt/rt-1 before #319 merges, and rebases on dev once it does.

## Open
- RT-5 release medians (3 runs): rgba8 173-176 ms (30), init 109-113 (30), copy band 44-59 (10), paste band 36-38 (10), merge 120-124 (60), flatten 241-286 (120), merge band 40-49 (20), tile 0.61-0.78 (0.5); opaque row copy 75-81 report-only. All 8 gated rows FAIL; equality checks pass. Composite has no allocation floor: round-1 perf target.
- Budgets: after RT-2b, 12 MP rgba8 175 ms sRGB / ~200 ms P3, init ~118 ms (budget 30), tile 0.72 ms (0.5), four bands 42 ms (10). Floor on this box: fresh 48 MB alloc 23-28 ms, 192 MB 85-94 ms (page faults). Raised with the supervisor on #311; gap issue to file at finish unless the captain re-baselines.
- Under 4-builder load, FlareCore EngineStressTests.thousandCommandsNearTheLayerLimitStayInBudget and StageBudgetTests.hitWithinBudget miss their wall-clock budgets (not this feature's files); quiet reruns pass. Watch the dev CI run.
