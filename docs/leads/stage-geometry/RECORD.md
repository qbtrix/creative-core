# stage-geometry lead record

Issue: #267 · Packet: docs/blueprints/core/features/stage-geometry.md
Run: act-1a13b145104-0zef · Session: session_01HWAU426RJRzBTT7hAE7fER · Started: 2026-10-14T15:43Z
Stage: 3 wave a
Base: 3339b904450d73eeae5dc404593972b82f24f46e
Next: check SG-1's PR; once the lane merges it, record the new origin/dev SHA and build wave b (SG-2, SG-3, SG-5, SG-6).

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| SG-1 | a | RenderList/Node/Item/Address, Scene/Symbol.renderList, Path.transformed(by:), rotation doc, C4 + engineering.md | RenderList.swift, Path.swift, Geometry.swift, docs/c4/model.json, docs/engineering.md | RenderListTests | FlareRenderList.json | – | building |
| SG-2 | b | SVG exporter walks renderList nodes, same bytes (closes #213) | Export/SVGExporter.swift | SVGRenderListTests | FlareSVGWalk.json | – | planned |
| SG-3 | b | RenderList.hit topmost, address, tolerance | HitQuery.swift, HitTest.swift | HitQueryTests | FlareHitQuery.json | – | planned |
| SG-5 | b | RenderItem.worldBounds, RenderList.worldBounds(of:) with stroke (closes #215) | WorldBounds.swift, ShapeBounds.swift | WorldBoundsTests | FlareWorldBounds.json | – | planned |
| SG-6 | b | PathBuilders rectangle, ellipse; GeometryError.nonFinite/.invalidSides | PathBuilders.swift, Geometry.swift | PathBuilderTests | FlarePathBuilders.json | – | planned |
| SG-4 | c | RenderList.marquee in paint order (closes #214) | Marquee.swift | MarqueeTests | FlareMarquee.json | – | planned |
| SG-7 | c | PathBuilders polygon, star (closes #182) | PathBuilders+Polygon.swift | PolygonStarBuilderTests | FlarePolygonStar.json | – | planned |
| SG-8 | d | QB-L5/L6 stage budgets; feature-done | StageBudgetTests.swift | StageBudgetTests | – | – | planned |

Acceptance tests and quality bars: the packet's "Acceptance test per task" and "Quality tests" tables, unchanged.

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|

## Decisions
- Waves as the packet sets them: a SG-1; b SG-2, SG-3, SG-5, SG-6; c SG-4, SG-7; d SG-8.
- New files go to the existing `geometry` C4 component (packet allows either; fewer moving parts).
- `gh` has no valid token in this environment: builders open PRs and set labels through the GitHub MCP tools.
- The Swift toolchain was missing; installed with scripts/cloud-setup.sh.
- Added `in-progress` to #213, #214, #215, #182 (waves.md housekeeping).

## Open
- none
