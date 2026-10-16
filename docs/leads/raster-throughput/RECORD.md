# raster-throughput lead record

Issue: #311 · Packet: docs/blueprints/core/features/raster-throughput.md (in PR #310, read from branch docs/core-packets-wave2)
Run: act-1a142b4b264-6dd2 · Session: claude/raster-throughput-lead-pyis7l · Started: 2026-10-16T04:00Z
Stage: 3 wave a
Base: f05665f5b54a461ab4a4e981ed7d7b01d7ab37ed
Next: build wave a (RT-1, RT-3, RT-4), then wait on the lane

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| RT-1 | a | `DisplayTransfer`: decode table, encode thresholds, byte rule | Sources/CoreColor/DisplayTransfer.swift, Tests/CoreColorTests/DisplayTransferTests.swift, Tests/mutations/CoreColorDisplayTransfer.json, docs/c4/parts/creative-core/corecolor/color-spaces.json | DisplayTransferTests | CoreColorDisplayTransfer.json | – | building |
| RT-3 | a | in-place `composite(_:x:y:mode:opacity:)`, free functions call it, opaque `.normal` row copy, `updateRow` | Sources/CoreRaster/Composite.swift, Sources/CoreRaster/PixelBuffer.swift, Tests/CoreRasterTests/CompositeInPlaceTests.swift, Tests/mutations/CoreRasterCompositeInPlace.json, docs/c4/parts/creative-core/coreraster/compositing.json | CompositeInPlaceTests | CoreRasterCompositeInPlace.json | – | building |
| RT-4 | a | `smallDabOn12MegapixelsIsFast` times thread CPU time (closes #300) | Tests/CoreRasterTests/RetouchBoundsTests.swift, Tests/CoreRasterTests/Support.swift | smallDabOn12MegapixelsIsFast + helper busy-loop check | – | – | building |
| RT-2 | b | `rgba8` / `init(rgba8:)` over `DisplayTransfer`; region `rgba8(x:y:width:height:)` | Sources/CoreRaster/DisplayBytes.swift, Tests/CoreRasterTests/DisplayBytesFastPathTests.swift, Tests/mutations/CoreRaster.json, Tests/mutations/CoreRasterDisplayBytes.json, docs/c4/parts/creative-core/coreraster/pixel-buffer.json | DisplayBytesFastPathTests | repoint 3 CoreRaster.json entries + CoreRasterDisplayBytes.json | – | waits on RT-1 |
| RT-5 | c | release budgets on one core and four; `feature-done` (closes #309) | Tests/CoreRasterTests/RasterThroughputBudgetTests.swift | RasterThroughputBudgetTests | – | – | waits on RT-2, RT-3 |

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

## Open
- none
