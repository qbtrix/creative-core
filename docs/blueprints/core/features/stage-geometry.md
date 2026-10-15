# Feature packet: stage-geometry

**Feature:** what the stage draws and what a click picks. One ordered render
list per frame that the stage, hit testing, bounds and the SVG exporter all
read; a topmost hit with an address and a zoom tolerance; a marquee; world
bounds that include the stroke; and path builders for the Rectangle,
Ellipse, Polygon and Star tools.
**Line:** `line:core` · **Wave:** 1 (`waves.md`) · **Lead branch:** `lead/stage-geometry`
**Status:** shipped. Merged PRs: #271, #274, #275, #277, #278, #280, #281,
#284, #287, #288, #289, #290, #295, #297, #301, #302, #303, and this
packet's closing `feature-done` PR. Where this packet and the code differ,
the code and its doc comments win.

**Covers:** #213 (LC-1, G45), #214 (LC-2), #215 (LC-3), #182 (LC-4). #213
closes with SG-2, #214 with SG-4, #215 with SG-5, #182 with SG-7.

**Unblocks:** Flare `live-stage` (qbtrix/creative-apps
`docs/blueprints/flare/features/live-stage.md`), together with
`edit-commands` (#173, #216). Its ST-1 to ST-5 wait on #213, #214 and #215;
ST-6 waits on #182.

**Depends on:** nothing open. Base: `origin/dev` 1b45592.

**Source:** Flare blueprint section 7.4 (qbtrix/creative-apps
`docs/blueprints/flare.md`, rows LC-1 to LC-4); where an issue body and this
packet differ, this packet wins, because it was checked against `dev` on
2026-10-14.

**Existing work:** no open PR covers any of these issues. PR #163 (CoreRaster
`TileDiff`) is unrelated and already superseded: #164 merged the same
feature and closed #156, and `Sources/CoreRaster/TileDiff.swift` is on
`dev`. No task here touches it; it can be closed without merging.

## Journey steps

The engine has no UI. Its journeys are the calls Flare's live types make
(live-stage steps 3 to 5), proven on FlareCore values in
`Tests/FlareCoreTests/` with the fixtures in `Support.swift`:

1. A scene with a visible layer, a hidden layer, a text layer and an
   instance of a symbol that itself holds an instance gives a render list
   whose items are in paint order, the hidden layer absent, the text listed
   with an empty outline, and the nested shape's opacity the product of every
   layer opacity on its way down (instances have no opacity of their own).
2. The SVG exporter writes the same bytes as before it moved onto the list.
3. A point 4 pt off a 0-width stroke hits that shape at tolerance 4; the
   topmost of two overlapping shapes wins; a locked, hidden or text item is
   never hit; the hit says where the item lives (owner, instance chain,
   layer, shape index).
4. A marquee returns the items it touches in paint order, without locked,
   hidden or text items.
5. The world bounds of a rotated rectangle are within 1e-9 of the rotated
   corners; a stroke widens them by half its width.
6. The Rectangle, Ellipse, Polygon and Star builders give closed paths whose
   curves are cubics (QB-V1). Rectangle and ellipse bounds equal the box;
   polygon and star vertices sit on the ellipse inscribed in the box (SG-7),
   so their bounds lie inside it and touch it only where a vertex does.

## Screens and states

The "screens" are the public queries. Each must answer every state without
crashing.

| Query | Empty | Error | Loading |
|---|---|---|---|
| `renderList` | a scene or symbol with no layers: an empty list; a layer with no shapes still appears as a group node (the SVG exporter writes its `<g>`), with no items | an instance whose symbol is missing or cyclic: a `.unresolved(symbolID)` node in the tree, no items in `items`; nothing throws (the SVG exporter turns that node into its existing `unresolvedSymbol` error). Instance expansion spends at most `RenderList.maxExpandedPoints`; past it every further instance is `.unresolved` and `isTruncated` is true, because a small file whose symbols fan out would otherwise build billions of items. The SVG exporter rejects a truncated list with `SVGExportError.sceneTooLarge` (SG-2) | none: built per frame, inside QB-L6 |
| `hit` | no item under the point: `nil` | a tolerance that is negative or not finite: `nil` (never a throw on a pointer move); an item whose matrix can't be inverted (zero scale) is skipped | – |
| `marquee` | a rect that touches nothing, or a zero-area rect: `[]` | a rect with a non-finite edge: `[]`; an item with a finite outline but no finite world box is picked by every valid rect, an item with no finite outline box is never picked (approved deviation, SG-4) | – |
| `worldBounds` | no items, or only text items: `nil` | a non-finite matrix or stroke width: that item is left out | – |
| `PathBuilders` | a zero-width or zero-height rect: a degenerate, finite path (no NaN) | a rect, radius or ratio that is not finite: `GeometryError.nonFinite`; a polygon side count or star point count outside `3...PathBuilders.maxSides`: `GeometryError.invalidSides`; a finite star inner ratio outside (0, 1]: `GeometryError.invalidRatio` | – |

## Contract slice

New public API, all in the evaluation layer (reads the model, never changes
it). Names are binding for the lead and builders; doc comments may add, not
rename.

```swift
// RenderList.swift (SG-1)
public struct RenderList: Sendable, Hashable {
    /// The tree, for exporters that keep groups: one node per visible layer.
    public var nodes: [RenderNode]
    /// The leaves in paint order, matrices and opacity already multiplied
    /// down the tree: what the stage draws and hit testing reads.
    public var items: [RenderItem]
}
public indirect enum RenderNode: Sendable, Hashable {
    case layer(RenderLayer)              // id, name, local Transform, opacity, isLocked, children
    case shape(index: Int, Shape)        // a layer's shape, in its layer's space
    case text(index: Int, TextShape)
    case instance(index: Int, Instance, symbolID: String, frame: Double, children: [RenderNode])
    case unresolved(index: Int, symbolID: String)
}
public struct RenderItem: Sendable, Hashable {
    public var address: RenderAddress
    public var outline: Path             // in the item's local space; empty for text
    public var fill: Fill?               // nil for text
    public var stroke: Stroke?
    public var matrix: Matrix            // local -> scene space, y down
    public var opacity: Double           // product of every layer opacity on the way down
    public var isLocked: Bool            // the leaf layer or any host layer above it is locked
    public var isText: Bool
}
public struct RenderAddress: Sendable, Hashable {
    public var owner: LayerOwner         // the layer list the walk started from
    public var hosts: [InstanceHost]     // (layerID, instanceIndex) from the top down; empty at top level
    public var layerID: String           // the leaf layer
    public var shapeIndex: Int?          // nil for text
    public var textIndex: Int?           // nil for shapes
}
public struct InstanceHost: Sendable, Hashable { public var layerID: String; public var instanceIndex: Int }

extension Scene  { public func renderList(at frame: Double, symbols: [Symbol]) -> RenderList }
extension Symbol { public func renderList(at frame: Double, symbols: [Symbol]) -> RenderList }   // edit in place
extension Path   { public func transformed(by m: Matrix) -> Path }   // in Path.swift; reused by SG-3, SG-5

// Geometry.swift (SG-1): the Transform.rotation doc comment becomes
// "Degrees, clockwise on screen: scene space is y down, as the exporters draw it."

// HitQuery.swift (SG-3)
extension RenderList {
    /// The topmost unlocked, non-text item under `point` (scene space), with
    /// `tolerance` added to the stroke reach and to the fill edge.
    public func hit(_ point: Point, tolerance: Double = 0, rule: FillRule = .nonZero) -> RenderAddress?
}
// Marquee.swift (SG-4)
extension RenderList {
    /// Unlocked, non-text items whose world bounds (with stroke) intersect
    /// `rect`, in paint order, each address once.
    public func marquee(_ rect: Rect) -> [RenderAddress]
}
// WorldBounds.swift (SG-5)
extension RenderItem { public var worldBounds: Rect? }                    // stroke included
extension RenderList { public func worldBounds(of addresses: [RenderAddress]) -> Rect? }   // union; nil when empty
// PathBuilders.swift (SG-6), PathBuilders+Polygon.swift (SG-7)
public enum PathBuilders {
    public static func rectangle(in rect: Rect, cornerRadius: Double = 0) throws -> Path
    public static func ellipse(in rect: Rect) throws -> Path
    public static func polygon(in rect: Rect, sides: Int) throws -> Path
    public static func star(in rect: Rect, points: Int, innerRatio: Double) throws -> Path
}
// Geometry.swift (SG-6, SG-7): GeometryError gains `nonFinite`, `invalidSides`
// and `invalidRatio`.
// RenderList.swift: `static let maxExpandedPoints`, `var isTruncated`.
// SVGExporter.swift (SG-2): SVGExportError gains `sceneTooLarge`.
```

**Approved deviation (SG-4).** The marquee does not use the world box alone.
An item with a finite outline but no finite world box (a non-finite stroke
width, or a finite stroke that overflows once scaled) paints a stroke with no
finite reach, so every valid rect picks it; a nil box never hides an item.
An item with no finite outline box (an empty outline or a non-finite matrix)
draws nothing and is never picked.

**Why a tree and not only a flat list.** #213 asks for the SVG golden to stay
byte-identical. The exporter writes one `<g>` per visible layer (empty ones
included) and one nested `<g>` per instance, so a flat list of leaves can't
reproduce its bytes. The tree keeps that structure; `items` is the flat view
the stage and hit testing read. Both come from one walk, so they can't drift.

**Paint order** is the SVG exporter's today: layers in array order; inside a
layer, its shapes in order, then its texts, then its instances in order, each
instance's symbol layers recursively. Later items paint on top.

## Pseudocode

```
renderList(layers, owner, frame, symbols):                       # SG-1
  nodes = []; items = []
  walk(layers, frame, path: [], hosts: [], parent: identity, opacity: 1, locked: false)
walk(layers, frame, path, hosts, parent, opacity, locked):
  for layer in layers where layer.isVisible:
    (t, o) = layer.placement(at: frame)
    m = parent * t.matrix ; op = opacity * o ; lk = locked || layer.isLocked
    children = []
    for (i, s) in layer.shapes:   children += .shape(i, s); items += item(s, m, op, lk)
    for (i, x) in layer.texts:    children += .text(i, x);  items += textItem(x, m, op, lk)
    for (i, inst) in layer.instances:
      guard (sym, local) = inst.resolve(in: symbols, frame, path) else { children += .unresolved(i, inst.symbolID); continue }
      inner = walk(sym.layers, local, path + [sym.id], hosts + [(layer.id, i)], m * inst.transform.matrix, op, lk)
      children += .instance(i, inst, sym.id, local, inner)
    nodes += .layer(id, name, t, o, layer.isLocked, children)

SVGExporter.render(scene): for node in scene.renderList(at:symbols:).nodes: emit(node)   # SG-2
  .layer -> <g id|data-id ...> children </g> ; .shape -> <path>; .text -> throw unsupported("text")
  .instance -> <g data-symbol matrix(inst.transform)> children </g> ; .unresolved -> throw unresolvedSymbol

hit(point, tolerance, rule):                                       # SG-3
  guard tolerance.isFinite, tolerance >= 0 else nil
  for item in items.reversed() where !item.isLocked && !item.isText:
    guard inv = item.matrix.inverted() else continue    # zero scale: skip
    local = inv.apply(point)                             # same space as Layer.hits / Shape.hits
    if item's Shape contains local (rule) or its stroke reach (width / 2) -> return item.address
    if tolerance > 0: world = item.outline.transformed(by: item.matrix)   # affine maps a cubic to a cubic
       if distance(point, flattened(world)) <= tolerance + (stroke width / 2) * scale(item.matrix) -> return item.address
  return nil

marquee(rect): items.filter { !locked && !text && worldBounds?.intersects(rect) } .map(address)   # SG-4
worldBounds(item): bounds(outline.transformed(by: matrix)) widened by stroke.width * scale(matrix) / 2   # SG-5
  scale(m) = sqrt(max(a*a + b*b, c*c + d*d))        # the larger axis, so the box never clips the stroke

rectangle(rect, r): r = clamp(r, 0, min(w, h) / 2); 4 lines + 4 cubic corners (k = 0.5522847498 * r), closed   # SG-6
ellipse(rect): move to top midpoint; 4 cubics through the edge midpoints, handles k * rx, k * ry; close
polygon(rect, n): n >= 3; vertices on the ellipse inscribed in rect, first at the top, clockwise; lines; close   # SG-7
star(rect, n, ratio): 2n vertices alternating outer and inner (ratio in (0, 1]); lines; close
```

## Tasks

Every task is one PR to `dev`: at most 400 changed lines and 15 files, label
`fast-lane`, body lines `Belt-Lead:`, `Feature: stage-geometry`,
`Fast-Check: pass`, `Head:`. SG-8 also carries `feature-done`.

**Mutation plans.** Each task puts its new entries in its own plan file
(`Tests/mutations/<plan>.json`; `scripts/mutate` reads every `*.json`
there). No task here edits `Tests/mutations/FlareCore.json`: `edit-commands`
owns it in this wave. SG-2 must keep the one `SVGExporter.swift` anchor in
`FlareCore.json` (the radial-radius line in the gradient code) byte-identical,
which a walk-only change does.

**C4.** SG-1 is the only task here that edits `docs/c4/model.json`. It adds
every new file of this feature to the `geometry` component (or a new
`render` component, if the lead prefers; one owner per file either way):
`RenderList.swift`, `HitQuery.swift`, `Marquee.swift`, `WorldBounds.swift`,
`PathBuilders*.swift` (the check accepts globs and paths that don't exist
yet), and rewrites the descriptions to stay true. Because `edit-commands`
may not edit the file in this wave, SG-1 also adds to the `symbols`
description "the instance add, remove, move and playback commands", and to
`document-commands` "stroke, path and duplicate-layer commands, scene
canvas, rename and reorder", which `edit-commands` lands in the same wave.

| id | issue | what | owned files | depends on | size |
|---|---|---|---|---|---|
| SG-1 | #213 (part) | `RenderList`, `RenderNode`, `RenderItem`, `RenderAddress`; `Scene.renderList` and `Symbol.renderList`; `Path.transformed(by:)`; the `Transform.rotation` doc fix; C4 entries and descriptions; the evaluation list in `docs/engineering.md` | `Sources/FlareCore/RenderList.swift`, `Sources/FlareCore/Path.swift`, `Sources/FlareCore/Geometry.swift`, `docs/c4/model.json`, `docs/engineering.md`, `Tests/FlareCoreTests/RenderListTests.swift`, `Tests/mutations/FlareRenderList.json` | – | ~330 |
| SG-2 | #213 (closes) | The SVG exporter walks `renderList(...).nodes` instead of the scene; same bytes | `Sources/FlareCore/Export/SVGExporter.swift`, `Tests/FlareCoreTests/SVGRenderListTests.swift`, `Tests/mutations/FlareSVGWalk.json` | SG-1 | ~180 |
| SG-3 | #214 (part) | `RenderList.hit(_:tolerance:rule:)`: topmost, address, tolerance, locked/hidden/text skipped; the stroke-distance helper in `HitTest.swift` becomes `internal` and is reused, not copied | `Sources/FlareCore/HitQuery.swift`, `Sources/FlareCore/HitTest.swift`, `Tests/FlareCoreTests/HitQueryTests.swift`, `Tests/mutations/FlareHitQuery.json` | SG-1 | ~250 |
| SG-4 | #214 (closes) | `RenderList.marquee(_:)` in paint order | `Sources/FlareCore/Marquee.swift`, `Tests/FlareCoreTests/MarqueeTests.swift`, `Tests/mutations/FlareMarquee.json` | SG-3, SG-5 | ~150 |
| SG-5 | #215 (closes) | `RenderItem.worldBounds` and `RenderList.worldBounds(of:)` with stroke; reuses `Path.bounds` from `ShapeBounds.swift` (no second bounds routine) | `Sources/FlareCore/WorldBounds.swift`, `Sources/FlareCore/ShapeBounds.swift`, `Tests/FlareCoreTests/WorldBoundsTests.swift`, `Tests/mutations/FlareWorldBounds.json` | SG-1 | ~200 |
| SG-6 | #182 (part) | `PathBuilders.rectangle(in:cornerRadius:)` and `ellipse(in:)`; `GeometryError.nonFinite` and `.invalidSides` | `Sources/FlareCore/PathBuilders.swift`, `Sources/FlareCore/Geometry.swift`, `Tests/FlareCoreTests/PathBuilderTests.swift`, `Tests/mutations/FlarePathBuilders.json` | SG-1 (`Geometry.swift` only: rebase on it) | ~250 |
| SG-7 | #182 (closes) | `PathBuilders.polygon` and `star` | `Sources/FlareCore/PathBuilders+Polygon.swift`, `Tests/FlareCoreTests/PolygonStarBuilderTests.swift`, `Tests/mutations/FlarePolygonStar.json` | SG-6 | ~200 |
| SG-8 | – | Stage budgets QB-L5 and QB-L6 on a seeded 1,000-shape scene; `feature-done` | `Tests/FlareCoreTests/StageBudgetTests.swift` | SG-2, SG-4 | ~120 |

Build waves inside the feature: **a** SG-1; **b** SG-2, SG-3, SG-5, SG-6
(disjoint files); **c** SG-4, SG-7; **d** SG-8. LC-14 (`FlareBudgetTests`,
the drag and export budgets) is not in this packet; SG-8's file is new and
LC-14 can extend it later.

## Acceptance test per task

| id | test | fails when |
|---|---|---|
| SG-1 | `RenderListTests`: on a test-built scene (visible layer with two shapes, hidden layer, text layer, an instance of `outer` whose layer holds an instance of `inner`), `items` lists the visible shapes in paint order with exact addresses; the hidden layer's shapes are absent from `items` and from `nodes`; the text item has `isText`, an empty outline and its `textIndex`; a leaf in `inner` has opacity equal to the product of its three layer opacities (0.5 × 0.5 × 0.8 = 0.2 exactly) and its matrix equals the product of the chain within 1e-12; a locked host layer marks every item below it `isLocked`; an instance of a missing symbol gives one `.unresolved` node and no item; `Symbol.renderList` on `inner` lists only `inner`'s layers with owner `.symbol("inner")`; `Path.transformed(by:)` maps each cubic's three points | an item is missing or out of order, a hidden layer draws, opacity is added instead of multiplied, or the lock doesn't reach nested items |
| SG-2 | `SVGRenderListTests`: for `Fixtures.document()`, `Fixtures.withSymbol()` and the SG-1 nested scene without its text layer and missing-symbol instance (those throw) at frames 0, 12 and 23, the export equals the string literal recorded from the pre-change exporter (recorded in the test before the exporter changes); a text layer still throws `unsupported("text")`; a missing symbol still throws `unresolvedSymbol`; every existing `SVGExporterTests` passes unchanged | one byte of the SVG changes, or an error case is swallowed |
| SG-3 | `HitQueryTests`: a 0-width stroked open line, hit 4 pt off at tolerance 4 returns its address, at tolerance 3.9 returns nil; two overlapping squares return the later one; a locked or text item over a shape returns the shape under it; a hidden layer is never hit; a point inside a nested instance's shape returns the full `hosts` chain; a negative or NaN tolerance returns nil; a seeded `SplitMix64` run of 200 points agrees with `Layer.hits` on whether anything is hit (tolerance 0, no locked layers; at tolerance 0 both use `Shape.hits` in local space, so they agree exactly, strokes included) | tolerance is ignored or double counted, paint order is reversed, locked or text items are picked, or the address loses its chain |
| SG-4 | `MarqueeTests`: a rect around two of three shapes returns those two in paint order; a rect over only a locked layer returns `[]`; a rect touching only a stroke's outer half (outside the outline, inside the stroke) picks it; a zero-area or NaN rect returns `[]` | the order changes, a locked or text item is picked, or the stroke is left out |
| SG-5 | `WorldBoundsTests`: a 100 × 50 rectangle rotated 30° has bounds within 1e-9 of its four rotated corners; a 10-wide stroke widens each side by 5 (at scale 1) and by 10 (at scale 2); a cubic's world bounds are tight (not its control-point box) within 1e-9; `worldBounds(of: [])` and a text-only selection are nil; the union of two items equals the union of their boxes | rotation is ignored, the stroke is left out or scaled wrong, or the box uses control points |
| SG-6 | `PathBuilderTests`: `ellipse(in: (10, 20)–(210, 120))` is one move, four cubics and a close; its `bounds` equal the rect within 1e-6; every point of `flattened(tolerance: 0.01)` satisfies ((x − cx)/rx)² + ((y − cy)/ry)² = 1 within 1e-3; `rectangle(cornerRadius: 999)` on a 100 × 40 rect clamps to 20 and stays inside the rect; radius 0 gives 4 lines; a NaN rect throws `nonFinite`; a zero-size rect gives finite points; a shape built from each survives `FlareFormat` encode and decode unchanged | a corner overshoots, a curve is flattened to lines, NaN leaks, or the clamp uses the long side |
| SG-7 | `PolygonStarBuilderTests`: `polygon(sides: 6)` has 6 vertices on the inscribed ellipse within 1e-9, the first at the top center; `sides: 2` throws `invalidSides`; `star(points: 5, innerRatio: 0.5)` has 10 vertices alternating radius r and r/2; a ratio of 0, of 1.5 or NaN throws | a vertex is off the ellipse, the count is wrong, or a bad ratio is accepted |
| SG-8 | `StageBudgetTests.renderListWithinBudget` and `.hitWithinBudget` (below) | the median exceeds the budget |

## Quality tests

| quality row | budget (CI gate, debug) | test |
|---|---|---|
| QB-L6 render list per frame | ≤ 20 ms for a seeded scene of 1,000 shapes in 50 layers with 10 instances, median of 20 runs | `StageBudgetTests.renderListWithinBudget` |
| QB-L5 hit per pointer move | ≤ 10 ms for one `hit` on the same scene's list, median of 50 runs at seeded points | `StageBudgetTests.hitWithinBudget` |
| QB-V1 curves stay curves | each `cubic` in a shape's outline is a `cubic` in its `RenderItem.outline`; every builder curve is a `cubic` | `RenderListTests.cubicsKept`, `PathBuilderTests.ellipseIsFourCubics` |
| Never crash | 1,000 seeded random scenes (random NaN transforms, missing symbols, cycles) build a list, hit and bound without trapping | `RenderListTests.seededScenesNeverTrap` |
| Mutation | every entry in the feature's plan files is caught | `scripts/mutate --run --changed-since <first base>`, run by the lead: CI's Mutation job plants at most 15 entries changed since `main`, so the local run is the proof. Per-task plan files depart from `engineering.md`'s `<module>.json` wording on purpose (no two tasks append to one JSON list); `scripts/mutate` globs every `*.json`, `--validate` and `--changed-since` included |

## Done check

- **Journeys green:** `scripts/ci` prints `CI: PASS` on the `dev` SHA that
  holds every merged task, and the CI run on `dev` the `feature-done` PR
  (SG-8) triggers is green (Linux, macOS on Swift 6.1, Mutation).
- **Audit zero new:** no new no-crash lint hit, the jscpd threshold not
  raised, `scripts/mutate --validate` clean, no escaped mutant.
- **Contact sheet:** `Belt-Contact-Sheet: <run link>` on the feature issue,
  one line per acceptance test above, and the test and mutation counts. Core
  has no screenshots; the run's job logs are the record.
