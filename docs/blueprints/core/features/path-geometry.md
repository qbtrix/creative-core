# Feature packet: path-geometry

**Feature:** the one path engine the suite edits vectors with, on FlareCore's
`Path`: an anchors view (corner, smooth and symmetric points with handles)
that round-trips to `Path`; nearest point, insert a point without changing
the shape, remove a point, convert a point's kind; arc length and the point
and tangent at a length; trim (start, end, offset; whole path or each
contour); dash (a pattern and a phase); outline a stroke (width, join, cap,
miter limit) into a fillable path; and the four booleans (union, subtract,
intersect, exclude) under either fill rule. Linux-safe, value types only.
**Line:** `line:core` · **Wave:** 5 (`waves.md`) · **Lead branch:** `lead/path-geometry`
**Status:** built (PG-1 to PG-12). Merged PRs: #713, #723, #731, #733, #735,
#739, #741, and PG-z (walk, budgets, this status line).

**Covers:** beta-80 plan row E1 ("path geometry: edit math, booleans, dash
and trim outlines", the unfiled core issue); captain's answer to Q5 and kernel
decision 2 (2026-10-18): the path type stays FlareCore `geometry`, SuiteKernel
and DesignModel link FlareCore. Design's map row "Pen tool ... waits on a
core path-geometry issue".

**Depends on:** nothing open. It owns `flarecore/geometry` and touches no
file `engine-contracts` owns, so it runs beside it in wave 5. Base:
`origin/dev` 4f91e04.

**C4:** container `flarecore`, component `geometry` (existing; ⚠ the
duplication guard: no kernel copy of a path type and no new module). PG-1
adds `Sources/FlareCore/PathOps/` to the part's `paths` and PG-12 rewrites
its description. No new component.

**Clean-room.** Behaviour from public geometry (de Casteljau subdivision,
arc length by flattening, polygon clipping from the published literature)
and this repo's `Path`; no task reads another product's code.

## Slices

| slice | behavior (one sentence) | tasks | checks | waits on |
|---|---|---|---|---|
| PG-a | `Path` declares every edit, measure, trim, dash, outline and boolean entry point and the anchors view as documented stubs that throw `GeometryError.notBuilt`, with the checks for every later slice and the area oracle written, the checks disabled. | PG-1, PG-2, PG-7 | `PathOpsShapeTests` | nothing |
| PG-edit | The anchors view round-trips any path, `nearest` finds the closest point on a curve, inserting a point keeps the drawn shape, removing one joins its neighbours, and converting a point mirrors or frees its handles. | PG-3, PG-4 | `PathEditTests` | PG-a |
| PG-measure | Length, point and tangent at a length, trim in both modes and dash with a phase cut the path where a ruler along it says, open or closed. | PG-5, PG-6 | `PathMeasureTests`, `PathTrimDashTests` | PG-a |
| PG-shape | Union, subtract, intersect and exclude of two paths give the filled area set algebra says, under even-odd and nonzero, for touching, nested and self-crossing input, refusing input past the size cap instead of hanging; and a stroke outlines (through `combine`) into a closed path whose area matches the stroked area for every join and cap, the miter limit falling back to a bevel. | PG-9, PG-10, PG-8 | `PathBooleanTests`, `PathBooleanFuzzTests`, `PathOutlineTests` | PG-a |
| PG-z | A walk draws a star, dashes it, trims it, outlines it and subtracts a circle, the budgets hold, and the feature is built. | PG-11, PG-12 | `PathOpsWalkTests`, `PathOpsBudgetTests` | every slice above |

`ui_slice: none`: an engine feature; its screens are Design's Pen (F7) and
point editing (S18), Flare's Direct Select (S18) and the strokes rows (S17).

## Journey steps

Engine only. KJ-PG (`PathOpsWalkTests.walk`, PG-11): a 5-point star from
`PathBuilders.star`; its `contours` round-trip; insert a point at t 0.5 of
edge 2 (area unchanged within 1e-9); dash `[10, 5]` (each piece 10 long along
the path); trim 0.25...0.75 (length is half); outline at width 4 with round
joins (area within 1% of the analytic band); subtract a centred circle
(area = star − circle within 0.5%).

## Screens and states

None.

## Contract slice

```swift
// Sources/FlareCore/PathOps/PathOps.swift (PG-1)
public enum AnchorKind: String, Codable, Sendable, Hashable { case corner, smooth, symmetric }
public struct PathAnchor: Codable, Sendable, Hashable { public var point: Point; public var handleIn: Point?; public var handleOut: Point?; public var kind: AnchorKind }
public struct PathContour: Codable, Sendable, Hashable { public var anchors: [PathAnchor]; public var closed: Bool }
public struct PathLocation: Sendable, Hashable { public var element: Int; public var t: Double; public var point: Point; public var distance: Double }
public enum TrimMode: String, Codable, Sendable, Hashable { case together, eachContour }
public enum BooleanOp: String, Codable, Sendable, Hashable { case union, subtract, intersect, exclude }
// GeometryError gains (Geometry.swift): notBuilt(String), invalidLocation, invalidPattern, tooComplex(Int)

// Sources/FlareCore/PathOps/PathEdit.swift (PG-1 stubs, PG-4 bodies)
extension Path {
    public var contours: [PathContour] { get }                 // quads raised to cubics; a handle equal to its point is nil
    public init(contours: [PathContour])
    public func nearest(to p: Point, tolerance: Double) throws -> PathLocation?      // nil for an empty path
    public func inserting(at location: PathLocation) throws -> Path                  // de Casteljau split, shape unchanged
    public func removingAnchor(contour: Int, index: Int) throws -> Path              // neighbours keep their outer handles
    public func converting(contour: Int, index: Int, to kind: AnchorKind) throws -> Path
}
// Sources/FlareCore/PathOps/PathMeasure.swift (PG-1 stubs, PG-6 bodies)
extension Path {
    public func length(tolerance: Double) throws -> Double
    public func sample(atLength s: Double, tolerance: Double) throws -> (point: Point, tangent: Point)?   // unit tangent
    public func trimmed(start: Double, end: Double, offset: Double, mode: TrimMode, tolerance: Double) throws -> Path
    public func dashed(_ pattern: [Double], phase: Double, tolerance: Double) throws -> Path
}
// Sources/FlareCore/PathOps/PathOutline.swift (PG-1 stub, PG-8 body)
extension Path { public func outlined(width: Double, join: Stroke.Join, cap: Stroke.Cap, miterLimit: Double, tolerance: Double) throws -> Path }
// Sources/FlareCore/PathOps/PathBoolean.swift (PG-1 stub, PG-10 body)
extension Path {
    public static let maxBooleanVertices = 200_000
    public static func combine(_ op: BooleanOp, _ a: Path, _ b: Path, rule: FillRule, tolerance: Double) throws -> Path
}
```

## Pseudocode

- **contours.** Walk elements; `move` opens a contour; `line` adds an anchor
  with nil handles; `quad` becomes a cubic (c1 = p0 + 2/3(c − p0), c2 = p1 +
  2/3(c − p1)); `close` sets `closed`. Kind: nil handles → corner; handles
  collinear through the point → smooth; collinear and equal length →
  symmetric (within 1e-9).
- **inserting.** Split element `e` at `t` (de Casteljau); a line splits at the
  lerp. `t` outside 0...1 or a missing element throws `invalidLocation`.
- **removingAnchor.** Drop the anchor; the previous anchor's out-handle and
  the next one's in-handle join as one cubic (a line when both are nil). The
  last anchor of a contour removes the contour.
- **converting.** corner: both handles nil. smooth: keep directions, make
  them collinear along the bisector of the two handle directions (the
  chord's direction when a handle is nil, length a third of the neighbour
  chord). symmetric: smooth, then both lengths their mean.
- **Measure.** Flatten once (`flattened(tolerance:)`), prefix sums of segment
  lengths; `sample` binary-searches the sums. `trimmed`: map `start`, `end`
  (0...1) plus `offset` (wraps) onto the total length (together) or each
  contour's (eachContour); `start > end` after wrap gives two pieces. Output
  is polyline pieces of the flattened path (curves are not re-fitted; marked
  `ponytail:` with the ceiling "exact cubic trim if a caller needs editable
  curves").
- **dashed.** Pattern entries finite and ≥ 0, sum > 0, at most 64 entries,
  else `invalidPattern`; an odd count repeats once (the SVG rule); `phase`
  shifts the start; each contour restarts the pattern.
- **outlined.** Offset each flattened segment by ±w/2; joins: miter until
  the miter length passes `miterLimit × w/2`, then bevel; round adds an arc
  flattened at `tolerance`; caps on open contours: butt, square (w/2 out),
  round. The union of the pieces under nonzero is the result (it reuses
  `combine`).
- **combine.** Flatten both; refuse more than `maxBooleanVertices` with
  `tooComplex(count)`; a sweep-line polygon clipper (the published
  Martinez–Rueda–Feito method) that splits edges at crossings, labels each
  edge's in/out by the fill rule, and keeps edges per op; collinear overlaps
  and touching vertices are merged with a 1e-9 snap. Output contours are
  closed, outer counter-clockwise, holes clockwise.

## Tasks

| id | issue | what | owned files | depends on | size |
|---|---|---|---|---|---|
| PG-1 | feature issue | The types, the four stub files, the new `GeometryError` cases, the `geometry` part gains `Sources/FlareCore/PathOps/`; `PathOpsShapeTests` | `Sources/FlareCore/PathOps/PathOps.swift`, `Sources/FlareCore/PathOps/PathEdit.swift`, `Sources/FlareCore/PathOps/PathMeasure.swift`, `Sources/FlareCore/PathOps/PathOutline.swift`, `Sources/FlareCore/PathOps/PathBoolean.swift`, `Sources/FlareCore/Geometry.swift`, `Tests/FlareCoreTests/PathOpsShapeTests.swift`, `docs/c4/parts/creative-core/flarecore/geometry.json` | – | ~240, 8 |
| PG-2 | – | Checks first: `PathEditTests`, `PathMeasureTests`, `PathTrimDashTests`, `PathOutlineTests`, `PathBooleanTests`, all disabled by name (`waits on PG-4` …) | `Tests/FlareCoreTests/PathEditTests.swift`, `Tests/FlareCoreTests/PathMeasureTests.swift`, `Tests/FlareCoreTests/PathTrimDashTests.swift`, `Tests/FlareCoreTests/PathOutlineTests.swift`, `Tests/FlareCoreTests/PathBooleanTests.swift` | PG-1 | ~380, 5 |
| PG-3 | – | Fixtures for the edit and measure checks (`PathFixtures`: star, ring, figure-eight, a 3-contour glyph, a 10,000-anchor scribble) | `Tests/FlareCoreTests/PathFixtures.swift` | PG-1 | ~140, 1 |
| PG-4 | – | Edit bodies: `contours`, `init(contours:)`, `nearest`, `inserting`, `removingAnchor`, `converting`; turns on `PathEditTests` | `Sources/FlareCore/PathOps/PathEdit.swift`, `Tests/FlareCoreTests/PathEditTests.swift`, `Tests/mutations/FlarePathEdit.json` | PG-2, PG-3 | ~320, 3 |
| PG-5 | – | Seeded property generators for measure, trim and dash (random closed and open paths, patterns, phases) | `Tests/FlareCoreTests/PathPropertySupport.swift` | PG-1 | ~120, 1 |
| PG-6 | – | Measure, trim and dash bodies; turns on `PathMeasureTests`, `PathTrimDashTests` | `Sources/FlareCore/PathOps/PathMeasure.swift`, `Tests/FlareCoreTests/PathMeasureTests.swift`, `Tests/FlareCoreTests/PathTrimDashTests.swift`, `Tests/mutations/FlarePathMeasure.json` | PG-2, PG-5 | ~340, 4 |
| PG-7 | – | Area helpers for the outline and boolean oracles (signed shoelace area of flattened output, point sampling against `HitTest`) | `Tests/FlareCoreTests/PathAreaSupport.swift` | PG-1 | ~100, 1 |
| PG-8 | – | Outline body; turns on `PathOutlineTests` | `Sources/FlareCore/PathOps/PathOutline.swift`, `Tests/FlareCoreTests/PathOutlineTests.swift`, `Tests/mutations/FlarePathOutline.json` | PG-2, PG-7, PG-10 | ~300, 3 |
| PG-9 | – | Boolean fuzz harness: 500 seeded polygon pairs (touching, nested, collinear, self-crossing) checked by point sampling | `Tests/FlareCoreTests/PathBooleanFuzzTests.swift` | PG-1, PG-7 | ~160, 1 |
| PG-10 | – | Boolean body; turns on `PathBooleanTests` and the fuzz harness | `Sources/FlareCore/PathOps/PathBoolean.swift`, `Tests/FlareCoreTests/PathBooleanTests.swift`, `Tests/FlareCoreTests/PathBooleanFuzzTests.swift`, `Tests/mutations/FlarePathBoolean.json` | PG-2, PG-9 | ~390, 4 |
| PG-11 | – | KJ-PG walk; `PathOpsBudgetTests` (release, `.serialized`) | `Tests/FlareCoreTests/PathOpsWalkTests.swift`, `Tests/FlareCoreTests/PathOpsBudgetTests.swift` | PG-4, PG-6, PG-8, PG-10 | ~160, 2 |
| PG-12 | – | The `geometry` part's description names the path ops; the packet's status line; `feature-done` | `docs/c4/parts/creative-core/flarecore/geometry.json`, `docs/blueprints/core/features/path-geometry.md` | PG-11 | ~50, 2 |

PG-8 waits on PG-10 because the outline unions its pieces through `combine`.
PG-12 owns only this packet and its own part; `docs/engineering.md` and
`waves.md` belong to `engine-contracts`' EC-10, so no two wave-5 features
share a file.

## Build waves

- Wave 1: PG-1. Independent in this wave: PG-1 alone.
- Wave 2: PG-2, PG-3, PG-5, PG-7. Independent in this wave: all four.
- Wave 3: PG-4, PG-6, PG-9. Independent in this wave: all three.
- Wave 4: PG-10. Independent in this wave: PG-10 alone.
- Wave 5: PG-8. Independent in this wave: PG-8 alone.
- Wave 6: PG-11. Independent in this wave: PG-11 alone.
- Wave 7: PG-12 (`feature-done`, final). Independent in this wave: PG-12 alone.

Longest chain: PG-1 → PG-7 → PG-9 → PG-10 → PG-8 → PG-11 → PG-12 (7).
Chain of 7: the fuzz harness needs the area helpers, the boolean body turns
the harness on, the outline unions through the boolean, the walk and the
budget time the finished ops, PG-12 is the prose task.

## Acceptance test per task

| id | test | fails when | mutations (plan: label → filter) |
|---|---|---|---|
| PG-1 | `PathOpsShapeTests`: every entry point exists and a stub throws `notBuilt` naming itself; `GeometryError` cases are `Equatable` | a signature is missing | none: declarations |
| PG-2 | the five suites compile, disabled by name | – | – |
| PG-3 | fixtures build without throwing; the scribble has 10,000 anchors | – | – |
| PG-4 | `PathEditTests`: `Path(contours: p.contours)` draws `p` (flattened points within 1e-9) for every fixture; `nearest` on a cubic finds the analytic foot within 1e-6; `inserting` keeps area and length within 1e-9 and adds one anchor; `removingAnchor` on a 4-anchor closed contour leaves 3; `converting(.symmetric)` gives equal, opposite handles; a bad index throws `invalidLocation` | the shape moves on insert, or a handle flips | `FlarePathEdit`: split uses `t` for both halves (shape moves) → `PathEditTests.insertKeepsShape`; symmetric keeps lengths → `.symmetricEqualizes`; index check `<=` for `<` → `.badIndexThrows` |
| PG-5 | generators are deterministic per seed | – | – |
| PG-6 | `PathMeasureTests`: a 100 × 50 rectangle is 300 long; `sample(atLength: 150)` is the far corner with tangent (−1, 0); `PathTrimDashTests`: trim 0...1 is the path, 0.25...0.75 is half its length, offset 0.5 with 0.75...0.25 gives two pieces summing to half; `[10, 5]` on 300 gives 20 dashes of 10; an odd pattern repeats; a zero-sum or negative pattern throws `invalidPattern`; 300 seeded paths: trimmed length = (end − start) × length within 1e-6 | a cut lands off the ruler | `FlarePathMeasure`: binary search returns the segment after → `PathMeasureTests.sampleAtCorner`; offset not wrapped → `PathTrimDashTests.offsetWraps`; odd pattern not doubled → `.oddPatternRepeats`; contour restart skipped in `eachContour` → `.eachContourRestarts` |
| PG-7 | helpers agree with `ShapeBounds` on fixtures | – | – |
| PG-8 | `PathOutlineTests`: an open line of length 100 at width 10 has area 1,000 (butt), 1,100 (square), 1,000 + 25π (round) within 0.5%; a 10° zig at miter limit 4 bevels, at 40 miters; a closed square's outline is a ring of the right area; `width ≤ 0` or non-finite throws | a join or cap adds the wrong area | `FlarePathOutline`: miter limit compared to `w` not `w/2` → `PathOutlineTests.miterLimitBevels`; square cap adds `w` → `.squareCapAddsHalf`; round join skipped on the inside turn → `.roundJoinArea` |
| PG-9 | the harness runs (disabled until PG-10) | – | – |
| PG-10 | `PathBooleanTests`: two overlapping squares: union, subtract, intersect and exclude areas exact; nested squares subtract to a ring with a clockwise hole; touching squares union to one contour; a figure-eight under even-odd vs nonzero differ as expected; `maxBooleanVertices + 1` throws `tooComplex`; fuzz: 500 pairs, 64 sampled points each agree with `HitTest` on `a op b` | a sample point disagrees with set algebra | `FlarePathBoolean`: exclude keeps edges inside both → `PathBooleanTests.excludeDropsOverlap`; fill rule ignored (always even-odd) → `.nonZeroDiffers`; snap 1e-9 removed (touching squares stay two) → `.touchingUnionIsOne`; vertex cap off by one → `.capThrows` |
| PG-11 | `PathOpsWalkTests.walk` (KJ-PG); `PathOpsBudgetTests`: nearest on the 10,000-anchor scribble ≤ 2 ms; dash and trim of it ≤ 5 ms; a 2 × 5,000-vertex boolean ≤ 50 ms (release, reported) | the ops disagree on the walk | none: walk and budgets |
| PG-12 | the part names `PathOps/`; status line says built | – | – |

PG-11 deviation (lead decision, PG-z): the budget scribble is `PathFixtures.handScribble()`, a local hand-drawn stroke (each anchor at most 20 from the last, controls within that step), not the random `scribble()`, whose controls span the whole 1000 box. That one is 8.49 M long and flattens to 401,801 points at tolerance 0.5. Flattening it alone took 5.7 ms in release, so trim (23.2 ms) and dash (43.4 ms) could not meet 5 ms. No pen stroke looks like that.

## Quality tests

| quality row | budget | test |
|---|---|---|
| Drag-time edit | `nearest` on 10,000 anchors ≤ 2 ms (one pointer move) | `PathOpsBudgetTests.nearestOnScribble` (release, reported) |
| Boolean on a real logo | 2 × 5,000 vertices ≤ 50 ms | `PathOpsBudgetTests.booleanLogo` (release, reported) |
| Never hangs | `tooComplex` past `maxBooleanVertices`; every loop bounded by element count | `PathBooleanTests.capThrows` |
| Never crashes | 500 seeded boolean pairs and 300 trim and dash paths, NaN and infinite coordinates included, throw or return | `PathBooleanFuzzTests`, `PathTrimDashTests` |
| Linux-safe | Foundation only | `scripts/ci` |

## Done check

Per slice: tasks merged, checks green on the newest dev run containing its
last PR, every plan scored with no escape. No Mac finisher (no Metal, no
time gate). Then `Belt-Contact-Sheet:` with the walk's areas and the budget
numbers, and the supervisor bumps creative-core in creative-apps.

## Adopted later

- **W2:** S17 strokes, dashes, trim paths and the gradient editor (Design,
  Flare, Halo); S18 point editing and booleans (Design, Flare: re-cut of
  Flare's Direct Select F4b); S19 shape tools reuse `PathBuilders`; E8
  `text-engine` uses `sample(atLength:)` for type on a path; S16's motion
  path uses the same measure.
- **W3:** Design Pen F7 (waits on E1 in the plan) and Components F8.

## Not in this packet

Offset path (inset and outset of a fill), exact cubic trim and boolean
results that keep curves (both polyline today, marked `ponytail:`), and the
model fields for dashes and trim on `Stroke` (S17 adds them through
`engine-contracts`' seams or its own task).
