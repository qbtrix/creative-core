# Feature packet: vector-import

**Feature:** FlareCore reads the two vector formats it already writes: an
SVG reader (paths with every path command including arcs, basic shapes,
groups with transforms, fills, strokes, opacity, linear and radial
gradients, clip paths as layer masks, simple text) and a Lottie reader
(shape layers with groups, paths, rectangles, ellipses, fills, strokes and
gradient fills, the transform with its animated position, scale, rotation
and opacity, masks and track mattes, solid layers), each into a `Document`
that passes `FlareFormat.validate`, plus an import report that lists what
was skipped. This is the inverse of `export`, and the oracle is the round
trip: what FlareCore writes, it reads back equal.
**Line:** `line:core` · **Wave:** 5 (`waves.md`) · **Lead branch:** `lead/vector-import`
**Status:** built. Merged PRs: #449, #478, #488, #490, #491, #494, #505,
#506, #512, #517, #521, #522, #542, #544, #556, #580, and this packet's
closing `feature-done` PR. Where this packet and the code differ, the code
and its doc comments win.

**Covers:** beta-80 plan row E11 ("SVG and Lottie readers; vector paste
between apps"); Flare map row 2 ("import SVG ... FlareCore `Path` takes
every SVG path segment; no parser. Design's import of Flare's SVG (#366)
wants the same reader") and its "open a Lottie JSON" row; Halo's and
Design's SVG import rows.

**Depends on:** nothing for SVG. The Lottie slice's masks, mattes and
animated colour need `engine-contracts:EC-f` (the model fields); everything
else runs at once. Base: `origin/dev` 4f91e04.

**C4:** container `flarecore`, ✚ new component `import`
(`docs/c4/parts/creative-core/flarecore/import.json`, `paths:
["Sources/FlareCore/Import/"]`, `order` 45: after `export`, its inverse),
added by VI-1, the task that adds its first file. The paste half of the
plan row is creative-apps `suite-pasteboard`, which already carries an SVG
representation; it is adoption, not code here.

**Clean-room.** SVG 1.1 and SVG 2 (W3C) and the published Lottie
specification; no task reads another product's code. The XML tokenizer is
a small pure-Swift reader written here (Foundation's XML parser is not in
FoundationEssentials on Linux).

## Slices

| slice | behavior (one sentence) | tasks | checks | waits on |
|---|---|---|---|---|
| VI-a | `SVGImport`, `LottieImport`, `ImportReport` and `ImportError` exist as documented stubs in the new `import` component, fixtures are in, and every check is written and disabled. | VI-1, VI-2 | `ImportShapeTests` | nothing |
| VI-svg | A bounded XML tokenizer and the path-data parser read every SVG path command (arcs become cubics), and the SVG reader turns shapes, groups, transforms, fills, strokes, gradients, clip paths and simple text into layers, reporting what it skips. | VI-3, VI-4, VI-5 | `XMLTokensTests`, `SVGPathDataTests`, `SVGImportTests`, `SVGImportFuzzTests` | VI-a; engine-contracts:EC-f (VI-5: clip paths become `LayerMask`s) |
| VI-lottie | The Lottie reader turns shape and solid layers, their shapes, fills, strokes, gradients, masks, mattes and animated transform, opacity and colour into a `Document` whose keyframes and easings sample as the file says. | VI-6, VI-7 | `LottieImportTests`, `LottieImportFuzzTests` | VI-a; engine-contracts:EC-f |
| VI-z | Every export fixture round-trips (written by `SVGExporter` or `LottieExporter`, read back equal within tolerance), the budgets hold, and the feature is built. | VI-8, VI-9 | `ImportRoundTripTests`, `ImportBudgetTests` | VI-svg, VI-lottie |

`ui_slice: none`: engine only. Its screens: Flare's File > Import and Open
of a Lottie (A2), Design's and Halo's SVG import, and vector paste between
the apps (W3).

## Journey steps

Engine only. KJ-VI (`ImportRoundTripTests.walk`, VI-8): the reference
scene exported to SVG and read back (every path's flattened points within
1e-6, fills equal, layer order kept); exported to Lottie and read back
(every track's samples at 20 frames equal within 1e-9); a hand-written SVG
with an arc, a skewed group and a radial gradient opens with the report
listing a skipped `<filter>`.

## Screens and states

None.

## Contract slice

```swift
// Sources/FlareCore/Import/Import.swift (VI-1)
public struct ImportReport: Sendable, Hashable { public var skipped: [String] }                 // "filter (3)", "use (1)", one per kind with a count
public enum ImportError: Error, Equatable, Sendable { case notThisFormat, damaged(String), tooLarge(String), unsupported(String) }
public enum SVGImport {
    public static let maxBytes = 32 << 20; public static let maxElements = 200_000; public static let maxDepth = 256
    public static func scene(from data: Data, name: String) throws -> (Scene, ImportReport) }   // one scene; viewBox → size
public enum LottieImport {
    public static let maxBytes = 64 << 20; public static let maxLayers = 5_000
    public static func document(from data: Data) throws -> (Document, ImportReport) }
// Sources/FlareCore/Import/XMLTokens.swift (VI-3): start tags with attributes, end tags, text; entities &lt; &gt; &amp; &quot; &apos; &#n;
// Sources/FlareCore/Import/SVGPathData.swift (VI-4): public static func path(_ d: String) throws -> Path
```

## Pseudocode

- **Bounds.** Every reader checks the byte size first, counts elements or
  layers and depth as it goes, and throws `tooLarge` past the caps: a count
  equal to its cap reads, one past it throws (the doc comments in
  `Import.swift` say what each cap counts); no recursion deeper than
  `maxDepth`; every number must be finite.
- **References.** A gradient's `href` chain and a `clip-path` reference
  resolve with a visited set of ids, at most `SVGImport.maxDepth` links deep.
  A reference that comes back to an id already visited, or goes deeper than
  that, is a cycle: the reader drops that reference (the gradient keeps what
  it resolved so far, the shape gets no clip mask) and counts it in the
  `ImportReport` as `reference cycle (n)`. A cycle never hangs and never
  throws.
- **Path data.** Commands M m L l H h V v C c S s Q q T t A a Z z with
  implicit repeats; numbers by the SVG grammar (signs, decimals, exponents,
  `1.5.5` as two numbers); arcs to cubics by the published endpoint-to-centre
  conversion, one cubic per ≤ 90° of sweep; a bad token throws `damaged`
  with its offset.
- **SVG.** `viewBox` (else `width`/`height`, else 1000 × 1000) gives the
  scene size; each `path`, `rect` (`rx`/`ry` through `PathBuilders.rectangle`),
  `circle`, `ellipse`, `line`, `polyline`, `polygon` is a shape on a layer
  per top-level element; `g` nests by composing its `transform` (matrix,
  translate, scale, rotate with centre, skewX, skewY) into its children;
  presentation attributes and the `style` attribute's declarations for
  fill, stroke, stroke-width, linejoin, linecap, opacity, fill-opacity;
  paint: `Shape.fill` is a non-optional `Fill`, so a shape with no `fill`
  anywhere up its ancestors takes SVG's initial value, `.solid(.black)`, and
  `fill="none"` becomes `.solid(Color(r: 0, g: 0, b: 0, a: 0))` (a clear
  solid; `Color` carries alpha `a`); `fill-opacity` and `opacity` multiply
  into the fill colour's `a`; a missing `stroke` or `stroke="none"` is
  `stroke == nil`;
  `linearGradient` and `radialGradient` (with `href` inheritance and
  `gradientTransform` on the endpoints) become `Fill.linear`/`.radial`;
  `clipPath` becomes an `add` `LayerMask`; `text` with one style becomes a
  `TextShape`; everything else (`filter`, `use`, `pattern`, `image`,
  `mask` with luminance, CSS selectors) is skipped and counted.
- **SVG into a document.** `SVGImport.scene` returns a `Scene`, not a
  document change. It enters a document only through the existing
  `AddScene(scene:index:)` command, after the caller sets `scene.id` to an id
  no scene in `document.scenes` has (`AddScene` throws
  `CommandError.duplicateID` otherwise), so undo removes exactly that scene
  and leaves the document as it was.
- **Lottie.** Top level `w`, `h`, `fr`, `ip`, `op` → the scene's size, fps
  and duration; layers bottom to top as the format orders them; `ty` 4
  shape layers: `gr` groups flattened into shapes with their `tr` (`a`, `p`,
  `s`, `r`, `o`), `sh` paths (vertices with in and out tangents to cubics),
  `rc`, `el`, `fl`, `st`, `gf`; `ty` 1 solids as a rectangle; `ks`
  transform: `a`, `p`, `s`, `r`, `o` static or keyframed (`k` arrays with
  `t`, `s`, `i`/`o` bezier handles → `Easing` cubic, `h: 1` → hold);
  `masksProperties` and `tt`/`td` into `LayerMask` and `TrackMatte`;
  animated `fl.c` into `colorTracks`. Precomps (`ty` 0), images (`ty` 2),
  text (`ty` 5) and expressions are skipped and counted.
- **Lottie anchor.** `Transform` has no anchor field, so the anchor `a` is
  folded into the geometry: each vertex `v` of the layer's shapes is stored
  as `v − a`, and the layer's `Transform` takes `p` (`x`, `y`), `s`
  (`scaleX`, `scaleY`, percent / 100) and `r` (`rotation`). A placed point
  is then R·S·(v − a) + p, which is `Transform.matrix` (translate · rotate ·
  scale) applied to `v − a`. A keyframed `a` reads its first key and is
  counted in the report as `anchor animation (n)`.
- **Lottie groups.** A group's `tr` composes onto its shapes: each vertex is
  mapped by T(p)·R·S·T(−a) of the group, inner group first, then each
  enclosing group's, before the layer's `ks` applies; the group's `o`
  multiplies into its shapes' fill and stroke alpha. A keyframed group `tr`
  reads its first key and is counted as `group animation (n)`.
- **Lottie numbers.** `fr`, `ip`, `op`, `st` and each keyframe `t` are JSON
  numbers. Each is rounded (`.rounded()`) and converted with `Int(exactly:)`;
  a value that is not finite or does not convert throws
  `ImportError.damaged` naming the field. Then a range check: `fr` in
  1...240, and `ip`, `op`, `st` and every `t` in 0...1_000_000; outside it
  throws `ImportError.damaged` naming the field and the value. No file value
  reaches `Int` arithmetic before this check, so nothing overflows.

## Tasks

| id | issue | what | owned files | depends on | size |
|---|---|---|---|---|---|
| VI-1 | feature issue | The values, errors, the two stubs, the `import` part; `ImportShapeTests` | `Sources/FlareCore/Import/Import.swift`, `Tests/FlareCoreTests/ImportShapeTests.swift`, `docs/c4/parts/creative-core/flarecore/import.json` | – | ~140, 3 |
| VI-2 | – | Fixtures (hand-written SVGs per feature, published-sample-style Lottie files written here, damaged files) and every suite disabled | `Tests/FlareCoreTests/Fixtures/import/`, `Tests/FlareCoreTests/XMLTokensTests.swift`, `Tests/FlareCoreTests/SVGPathDataTests.swift`, `Tests/FlareCoreTests/SVGImportTests.swift`, `Tests/FlareCoreTests/SVGImportFuzzTests.swift`, `Tests/FlareCoreTests/LottieImportTests.swift`, `Tests/FlareCoreTests/LottieImportFuzzTests.swift` | VI-1 | ~380, 6 + fixtures |
| VI-3 | – | `XMLTokens`; turns on `XMLTokensTests` | `Sources/FlareCore/Import/XMLTokens.swift`, `Tests/FlareCoreTests/XMLTokensTests.swift`, `Tests/mutations/FlareXMLTokens.json` | VI-2 | ~240, 3 |
| VI-4 | – | `SVGPathData` with arcs; turns on `SVGPathDataTests` | `Sources/FlareCore/Import/SVGPathData.swift`, `Tests/FlareCoreTests/SVGPathDataTests.swift`, `Tests/mutations/FlareSVGPathData.json` | VI-2 | ~300, 3 |
| VI-5 | – | `SVGImport.scene` (elements, transforms, styles, gradients, clip paths, text, the report); turns on `SVGImportTests`, `SVGImportFuzzTests` | `Sources/FlareCore/Import/SVGImport.swift`, `Sources/FlareCore/Import/SVGStyle.swift`, `Tests/FlareCoreTests/SVGImportTests.swift`, `Tests/FlareCoreTests/SVGImportFuzzTests.swift`, `Tests/mutations/FlareSVGImport.json` | VI-3, VI-4, engine-contracts:EC-f | ~390, 5 |
| VI-6 | – | Lottie shapes, solids, fills, strokes, gradients and the static transform | `Sources/FlareCore/Import/LottieImport.swift`, `Tests/FlareCoreTests/LottieImportTests.swift`, `Tests/mutations/FlareLottieImport.json` | VI-2, engine-contracts:EC-f | ~360, 3 |
| VI-7 | – | Lottie keyframes, easings, holds, masks, mattes and colour tracks in a second file; turns on `LottieImportFuzzTests` | `Sources/FlareCore/Import/LottieImport+Animation.swift`, `Tests/FlareCoreTests/LottieImportAnimationTests.swift`, `Tests/FlareCoreTests/LottieImportFuzzTests.swift`, `Tests/mutations/FlareLottieImportAnimation.json` | VI-6 | ~340, 4 |
| VI-8 | – | KJ-VI: the round-trip suite over every export fixture; `ImportBudgetTests` (release, `.serialized`) | `Tests/FlareCoreTests/ImportRoundTripTests.swift`, `Tests/FlareCoreTests/ImportBudgetTests.swift` | VI-5, VI-7 | ~200, 2 |
| VI-9 | – | The `import` part's final words; the packet's status line; `feature-done` | `docs/c4/parts/creative-core/flarecore/import.json`, `docs/blueprints/core/features/vector-import.md` | VI-8 | ~20, 2 |

## Build waves

- Wave 1: VI-1. Independent in this wave: VI-1 alone.
- Wave 2: VI-2. Independent in this wave: VI-2 alone.
- Wave 3: VI-3, VI-4, VI-6. Independent in this wave: all three (VI-6 once engine-contracts' EC-f has merged).
- Wave 4: VI-5, VI-7. Independent in this wave: both.
- Wave 5: VI-8. Independent in this wave: VI-8 alone.
- Wave 6: VI-9 (`feature-done`, final). Independent in this wave: VI-9 alone.

Longest chain: VI-1 → VI-2 → VI-3 → VI-5 → VI-8 → VI-9 (6). Chain of 6:
the checks need the stubs, the reader walks the tokenizer's tokens, the
round trip reads with the reader, VI-9 is the prose task.

## Acceptance test per task

| id | test | fails when | mutations (plan: label → filter) |
|---|---|---|---|
| VI-1 | `ImportShapeTests`: stubs throw `unsupported("not built")`; errors are `Equatable` | a signature is missing | none |
| VI-2 | suites compile, disabled; fixtures load as bytes | – | – |
| VI-3 | `XMLTokensTests`: tags, attributes in both quote styles, self-closing, comments and CDATA skipped, the five entities and numeric references decoded; an unclosed tag, a bad entity and depth 257 throw | a token is lost or depth is unbounded | `FlareXMLTokens`: `&apos;` not decoded → `XMLTokensTests.decodesEntities`; depth check `>` for `>=` → `.depthCapped`; comment end `-->` matched at `->` → `.skipsComments` |
| VI-4 | `SVGPathDataTests`: each command, absolute and relative, with implicit repeats; `1.5.5` is two numbers; `S` and `T` reflect the previous control point; a quarter arc's midpoint is within 1e-9 of the circle; a zero-radius arc is a line; a bad token throws with its offset | a command reads wrong | `FlareSVGPathData`: relative `l` treated as absolute → `SVGPathDataTests.relativeLine`; reflection skipped for `S` → `.smoothReflects`; arc sweep flag inverted → `.arcSweepFlag` |
| VI-5 | `SVGImportTests`: each fixture gives the expected layers, shapes, fills and strokes; a rotated group's child lands where the transform says; gradient `href` inherits stops; a clip path is one `add` mask; a shape with no fill has `fill == .solid(.black)` (`.missingFillIsBlack`) and `fill="none"` gives `fill == .solid(Color(r: 0, g: 0, b: 0, a: 0))` (`.fillNoneIsClear`); a gradient whose `href` points back to itself and a `clip-path` chain that loops each import within 1 s with `reference cycle (n)` in the report (`.referenceCyclesEnd`); a scene added with `AddScene` and undone leaves the document equal to before; the report counts skipped kinds; the scene validates; `SVGImportFuzzTests`: 1,000 seeded mutations throw or import, never crash, each under 1 s | a transform composes in the wrong order, or a damaged file crashes | `FlareSVGImport`: group transform applied after the child's → `SVGImportTests.groupTransformOrder`; `style` loses to the attribute → `.styleWinsOverAttribute`; fill-opacity ignored → `.fillOpacity` |
| VI-6 | `LottieImportTests`: shapes, solids, fills, strokes and gradients of each fixture; the static transform, with an anchor `a` of (10, 20) placing a vertex at R·S·(v − a) + p within 1e-9 (`.anchorFolded`) and a group `tr` composing onto its shapes (`.groupTransform`); `fr: 29.97` imports as 30 fps; `fr: 0`, `fr: 241`, `ip: -1`, `op: 1000001`, `op: 1e300` and a keyframe `t: 1e300` each throw `ImportError.damaged` (`.frameRanges`); the result validates | a shape or style is lost, or a frame value passes unchecked | `FlareLottieImport`: vertex tangents added to the wrong vertex → `LottieImportTests.tangentsRelativeToVertex`; layer order reversed → `.bottomToTop`; anchor added instead of subtracted → `.anchorFolded`; fps range `1...240` widened to `0...240` → `.frameRanges` |
| VI-7 | `LottieImportAnimationTests`: a keyframed position samples equal to the file's bezier at 10 frames within 1e-9; `h: 1` holds; masks and `tt: 3` read as luma; colour keys land in `colorTracks`; `LottieImportFuzzTests`: 1,000 mutations throw or import | an easing or hold is wrong | `FlareLottieImportAnimation`: `i` and `o` handles swapped → `LottieImportAnimationTests.easingHandles`; hold ignored → `.holdKeys`; `tt` 3 read as alpha → `.lumaMatte` |
| VI-8 | `ImportRoundTripTests` (KJ-VI); `ImportBudgetTests`: a 2 MB SVG ≤ 150 ms; a 5 MB Lottie ≤ 250 ms (release, reported) | a round trip differs | none |
| VI-9 | the part names both readers; status line says built | – | – |

## Quality tests

| quality row | budget | test |
|---|---|---|
| Open a big SVG | 2 MB ≤ 150 ms | `ImportBudgetTests.bigSVG` (release, reported) |
| Open a big Lottie | 5 MB ≤ 250 ms | `ImportBudgetTests.bigLottie` |
| Never crashes | 2,000 fuzz cases throw or import, each under 1 s; caps on bytes, elements, layers and depth | the two fuzz suites |
| Round trip | export then import is equal within the stated tolerances | `ImportRoundTripTests` |
| Linux-safe | Foundation only; no XML parser dependency | `scripts/ci` |

## Done check

Per slice as usual. No Mac finisher (no time gate beyond reported budgets).
Then the contact sheet with the round-trip counts.

## Adopted later

- **W3:** A2 Lottie round trip in Flare (open Lottie, write dotLottie);
  Flare's and Halo's SVG import (F+1.9, H+1.7); Design's SVG import (D+0.6,
  #366); vector paste between apps through `suite-pasteboard`'s SVG item.

## Not in this packet

dotLottie packaging (A2), precomps, image layers and expressions in Lottie,
SVG `use`, `pattern`, `filter`, embedded images and CSS stylesheets, PDF
and other closed vector formats.
