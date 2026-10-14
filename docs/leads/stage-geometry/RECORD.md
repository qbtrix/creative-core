# stage-geometry lead record

Issue: #267 · Packet: docs/blueprints/core/features/stage-geometry.md
Run: act-1a13b145104-0zef · Session: session_01HWAU426RJRzBTT7hAE7fER · Started: 2026-10-14T15:43Z
Stage: 4 round 1
Base: 1817e035cbfd08ddeeb476b185547503577044fe (wave d; feature's first base 3339b904450d73eeae5dc404593972b82f24f46e)
Next: once #284 (r1-b1) merges, run r1-b5 (hit-query findings 1, 7, 8, 13, 14 and the HitQuery mutation entries in rounds/round-1-panel.json) on the new dev; wait for r1-b2..b4 (wf_3a1f1967-58a) to merge; then round 2.

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| SG-1 | a | RenderList/Node/Item/Address, Scene/Symbol.renderList, Path.transformed(by:), rotation doc, C4 + engineering.md | RenderList.swift, Path.swift, Geometry.swift, docs/c4/model.json, docs/engineering.md | RenderListTests | FlareRenderList.json | #271 | merged 4cac701 |
| SG-2 | b | SVG exporter walks renderList nodes, same bytes (closes #213) | Export/SVGExporter.swift | SVGRenderListTests | FlareSVGWalk.json | #274 | merged 04c749f |
| SG-3 | b | RenderList.hit topmost, address, tolerance | HitQuery.swift, HitTest.swift | HitQueryTests | FlareHitQuery.json | #275 | merged 911507a |
| SG-5 | b | RenderItem.worldBounds, RenderList.worldBounds(of:) with stroke (closes #215) | WorldBounds.swift, ShapeBounds.swift | WorldBoundsTests | FlareWorldBounds.json | #277 | merged ae53f2e |
| SG-6 | b | PathBuilders rectangle, ellipse; GeometryError.nonFinite/.invalidSides | PathBuilders.swift, Geometry.swift | PathBuilderTests | FlarePathBuilders.json | #278 | merged 992ba1b |
| SG-4 | c | RenderList.marquee in paint order (closes #214) | Marquee.swift | MarqueeTests | FlareMarquee.json | #280 | merged 8fa8cc6 |
| SG-7 | c | PathBuilders polygon, star (closes #182) | PathBuilders+Polygon.swift | PolygonStarBuilderTests | FlarePolygonStar.json | #281 | merged 1817e03 |
| SG-8 | d | QB-L5/L6 stage budgets (feature-done moved to the last PR) | StageBudgetTests.swift | StageBudgetTests | – | – | #284 | lands with r1-b1 (hit prefilter) |

Acceptance tests and quality bars: the packet's "Acceptance test per task" and "Quality tests" tables, unchanged.

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|
| 1 | 1817e03 | FAIL only CoreRaster timing flake under load (passes alone) | 38/38 | – | clarity, contract, robustness, tests, design, compat | 18 confirmed (6 major: invalidSides doc, render-list fan-out unbounded, hit axis-scale and rule untested, hit scale and stroke-reach duplicated) + QB-L5 miss; full list rounds/round-1-panel.json | r1-b1 #284 (hit prefilter + SG-8: hit 2.3 ms alone, 3.4 ms under ci), r1-b2 (render list), r1-b3 (geometry/builders/marquee), r1-b4 (world-bounds test, layer docs); hit findings 1,7,8,13,14 as r1-b5 after #284 merges (same file) | no |

## Decisions
- Waves as the packet sets them: a SG-1; b SG-2, SG-3, SG-5, SG-6; c SG-4, SG-7; d SG-8.
- New files go to the existing `geometry` C4 component (packet allows either; fewer moving parts).
- `gh` has no valid token in this environment: builders open PRs and set labels through the GitHub MCP tools.
- The Swift toolchain was missing; installed with scripts/cloud-setup.sh.
- The GitHub MCP tool appends an attribution footer to PR bodies; the lane strips it from squash commits (checked 992ba1b). Builders are told to strip it; checked again in the critic round.
- QB-L5: SG-8's builder measured hit at 7-9 ms alone, 16.6 ms under scripts/ci (budget 10 ms). Budget kept; fix is a world-bounds prefilter in HitQuery.swift, shipped in one PR with SG-8's tests (branch sg/sg8 95194fb).
- Critic lenses fixed for every round: clarity, contract, robustness, tests, design, compat (no undo lens: the feature adds no commands).
- SG-8 ships without `feature-done`: lead.md runs the Anatomy loop before finish, and a feature-done merge dispatches the closing CI. The label goes on the feature's last PR (last fix batch, or the packet status line if the rounds are clean).
- Builder branches are `sg/<id>`: a ref `lead/stage-geometry` exists, so `lead/stage-geometry/<id>` cannot be created.
- Baseline scripts/ci on 3339b90: CI: PASS (635 tests).
- Added `in-progress` to #213, #214, #215, #182 (waves.md housekeeping).

## Open
- Agents share this machine: a subagent once left the lead checkout detached; check `git branch --show-current` before recording.
- Pre-run on 1817e03 (box loaded by the SG-8 builder): mutation 38/38 caught, validate OK (122 anchors); scripts/ci failed only on CoreRaster RetouchBoundsTests.smallDabOn12MegapixelsIsFast (2.24 s vs 1.5 s budget), which passes alone. Outside this feature; rerun the gate on a quiet box for round 1.
- Lead record went quiet 15:44-16:25 because the container restarted; Belt nudged once.
