# Feature packet: masks-mattes

**Feature:** the one mask and matte engine for raster and vector documents.
Raster (CoreRaster): feather a selection mask, trace its outlines (marching
ants) and its covered bounds, make a mask from a buffer's alpha or
luminance (track mattes, luma mattes), and composite a layer through a mask
in place, on the CPU backend through the new `maskedComposite` family.
Vector (FlareCore): layer masks (path, add/subtract/intersect/difference,
feather, opacity, invert) and track mattes (alpha, luma, both inverted) as
commands with exact undo, carried by the render list as clip and matte
entries, and written by the SVG and Lottie exporters.
**Line:** `line:core` · **Wave:** 6 (`waves.md`) · **Lead branch:** `lead/masks-mattes`
**Status:** built

**Covers:** beta-80 plan row E2; Photo blueprint 8.4 CR-3 (`Mask.feathered`),
CR-4 (`Mask.contours`, `Mask.coveredBounds`), CR-6 (the masked composite);
Halo's masks and track mattes and Flare's masks (maps' rows behind S4).

**Depends on:** `engine-contracts` (EC-a for the CoreRaster folders and the
`maskedComposite` family, EC-b for the CPU and parity seam files, EC-f for
`LayerMask`, `TrackMatte`, `MaskCommands.swift` and the exporter seams);
`path-geometry` only for MM-10's description edit of the `geometry` part.

**C4:** containers `coreraster` (components `image-ops`: `Masks/`;
`compositing`: `Compositing/`), `corerender` (`cpu-backend`, `parity`) and
`flarecore` (`document-commands`: `MaskCommands.swift`; `geometry`: the
render list's clip and matte; `export`). ⚠ No mask module: masks extend
`image-ops` and `compositing`, and `LayerTree` attributes in the kernel
later (S4). No new component, so no new part; every folder and seam file is
already in its part (EC-1, EC-6).

**Clean-room.** Feather, marching squares and source-over with coverage are
public image-processing techniques; SVG masking (W3C) and the Lottie
`masksProperties` and track matte fields (lottie-spec) are published
formats. No task reads another product's code.

## Slices

| slice | behavior (one sentence) | tasks | checks | waits on |
|---|---|---|---|---|
| MM-a | The raster and vector checks are written and disabled, with a fixture document (a shape layer with two masks and a luma-matted layer) and seeded masks. | MM-1, MM-2 | `MaskOpsTests`, `MaskCompositeTests`, `MaskCommandsTests`, `MatteRenderListTests` | engine-contracts:EC-a (MM-1), engine-contracts:EC-f (MM-2) |
| MM-raster | A mask feathers by a radius, traces its outlines and bounds, comes from a buffer's alpha or luminance (inverted or not), and a layer composites through it in place, equal on the CPU backend and the direct CoreRaster call. | MM-3, MM-4, MM-5 | `MaskOpsTests`, `MaskCompositeTests`, `CPUMaskedCompositeTests` | MM-a; engine-contracts:EC-a (MM-3, MM-4), engine-contracts:EC-b (MM-5) |
| MM-vector | Adding, editing, removing and reordering layer masks and setting a track matte are commands with exact undo that refuse cycles and locked layers, the render list gives each item its clip paths and matte source, and SVG and Lottie write both. | MM-6, MM-7, MM-8 | `MaskCommandsTests`, `MatteRenderListTests`, `SVGMaskExportTests`, `LottieMaskExportTests` | MM-a |
| MM-z | A walk masks a Halo-style layer stack end to end on both halves, the budgets hold, and the feature is built. | MM-9, MM-10 | `MaskWalkTests`, `MaskBudgetTests` | MM-raster, MM-vector; path-geometry (MM-10) |

`ui_slice: none`: engine only. Its screens: S4 masks and track mattes on
layers (Halo, Flare, Photo, Design) and S5 selection tools (Photo's marching
ants and feather).

## Journey steps

Engine only. KJ-MM (`MaskWalkTests.walk`, MM-9): a 512 × 512 photo layer,
an ellipse mask feathered 12 px, its contour traced (one closed outline, no
gap), composited through the mask at opacity 0.8 onto white on the CPU
backend through a `RenderDispatcher` (equal to the direct call byte for
byte); then a `.flare` with a text layer luma-matting a gradient layer, the
matte set by command, undone and redone, its render list naming the matte,
and its SVG and Lottie outputs carrying the mask and `tt: 3`.

## Screens and states

None.

## Contract slice

The family, the CPU and parity seam files and the model types are
`engine-contracts`'. This feature adds:

```swift
// Sources/CoreRaster/Masks/MaskFeather.swift (MM-3)
extension Mask {
    public func feathered(radius: Double) throws -> Mask                 // sigma = radius / 3; 0 returns self; values stay in 0...1
}
// Sources/CoreRaster/Masks/MaskContours.swift (MM-3)
extension Mask {
    public func contours(level: Float = 0.5) throws -> [[Mask.Point]]   // closed outlines, outer positive shoelace (y-down); throws past maxContourSegments
    public var coveredBounds: (x: Int, y: Int, width: Int, height: Int)? { get }   // nil when empty
}
// Sources/CoreRaster/Masks/MaskFromBuffer.swift (MM-4)
extension Mask {
    public init(from buffer: PixelBuffer, _ source: MatteSource, inverted: Bool = false) throws
}
// Sources/CoreRaster/Compositing/CompositeMasked.swift (MM-4)
extension PixelBuffer {
    public mutating func composite(_ src: PixelBuffer, x: Int, y: Int, mode: BlendMode, opacity: Float,
                                   mask: Mask, maskX: Int, maskY: Int) throws   // coverage outside the mask is 0
}
// Sources/FlareCore/MaskCommands.swift (MM-6)
public struct AddLayerMask: LayerCommand { owner, layerID, mask: LayerMask, index: Int? }
public struct SetLayerMask: LayerCommand { owner, layerID, index, mask: LayerMask }   // merges with the next one on the same mask (drag)
public struct RemoveLayerMask: LayerCommand { owner, layerID, index }
public struct MoveLayerMask: LayerCommand { owner, layerID, from, to }
public struct SetTrackMatte: LayerCommand { owner, layerID, matte: TrackMatte? }   // refuses self, a cycle, another owner
// Sources/FlareCore/RenderList.swift (MM-7): each paint item gains
//   clips: [ClippedPath]   // the layer's masks in world space, in order, with mode, feather, opacity, inverted
//   matte: MatteLink?      // the matte source's item index and kind; the source item is flagged isMatteSource
```

## Pseudocode

- **feathered.** Coverage as a one-channel buffer, the separable Gaussian
  CoreRaster's `gaussianBlur` already uses (its weights, not a copy), clamp
  to 0...1. Radius non-finite or negative throws.
- **contours.** Marching squares at `level` with linear interpolation on
  edges; the saddle cell resolved by the cell's mean; outlines joined into
  closed rings; at most `width × height` steps.
- **Mask(from:).** `.alpha`: unpremultiplied alpha. `.luminance`: Rec. 709
  luma of the linear colour, times alpha (a transparent pixel is 0).
  `inverted`: 1 − value.
- **Masked composite.** Per pixel: effective opacity = `opacity ×
  coverage(x − maskX, y − maskY)`; then the existing blend for `mode`. A
  row whose coverage is all 0 is skipped; a row at full coverage takes the
  unmasked fast path.
- **Render list.** A layer's masks are combined in order: start from full
  (first mask `add`) or empty; `add` unions, `subtract` removes,
  `intersect` keeps the overlap, `difference` toggles. The list hands the
  paths and modes on; it does not rasterize (each app's renderer does). A
  matte source is drawn only as a matte unless the layer is visible in its
  own right, which is the published convention.
- **Exporters.** SVG: masks without feather become one `<clipPath>` per
  item; with feather or opacity, a `<mask>` with a Gaussian blur filter of
  `feather / 3` (feather is one quantity everywhere: the blur radius, sigma =
  feather / 3, the radius `Mask.feathered(radius:)` takes); a luma matte is a `<mask mask-type="luminance">` holding the
  source's group. Lottie: `masksProperties` (`mode` a, s, i, f; `x` feather;
  `o` opacity; `inv`), and `tt` 1–4 on the matted layer with `td: 1` on the
  source, the source written directly above it.

## Tasks

| id | issue | what | owned files | depends on | size |
|---|---|---|---|---|---|
| MM-1 | feature issue | Checks first, raster: `MaskOpsTests`, `MaskCompositeTests`, `CPUMaskedCompositeTests` disabled by name; seeded masks in `MaskFixtures` | `Tests/CoreRasterTests/MaskOpsTests.swift`, `Tests/CoreRasterTests/MaskCompositeTests.swift`, `Tests/CoreRasterTests/MaskFixtures.swift`, `Tests/CoreRenderTests/CPUMaskedCompositeTests.swift` | engine-contracts:EC-a | ~300, 4 |
| MM-2 | – | Checks first, vector: `MaskCommandsTests` cases and `undoSteps`, `MatteRenderListTests`, `SVGMaskExportTests`, `LottieMaskExportTests` disabled; the fixture document | `Tests/FlareCoreTests/MaskCommandsTests.swift`, `Tests/FlareCoreTests/MatteRenderListTests.swift`, `Tests/FlareCoreTests/SVGMaskExportTests.swift`, `Tests/FlareCoreTests/LottieMaskExportTests.swift`, `Tests/FlareCoreTests/Fixtures/masks.flare` | engine-contracts:EC-f | ~340, 5 |
| MM-3 | – | `feathered`, `contours`, `coveredBounds`; turns on their `MaskOpsTests` | `Sources/CoreRaster/Masks/MaskFeather.swift`, `Sources/CoreRaster/Masks/MaskContours.swift`, `Tests/CoreRasterTests/MaskOpsTests.swift`, `Tests/mutations/CoreRaster.MaskFeather.json`, `Tests/mutations/CoreRaster.MaskContours.json` | MM-1 | ~320, 5 |
| MM-4 | – | `Mask(from:_:inverted:)` and the in-place masked composite; turns on `MaskCompositeTests` and the from-buffer cases | `Sources/CoreRaster/Masks/MaskFromBuffer.swift`, `Sources/CoreRaster/Compositing/CompositeMasked.swift`, `Tests/CoreRasterTests/MaskCompositeTests.swift`, `Tests/mutations/CoreRaster.CompositeMasked.json` | MM-1 | ~300, 4 |
| MM-5 | – | CPU body of the masked composite (through the store's lock, like `composite`); its parity samples and CPU goldens | `Sources/CoreRender/CPU/CPUBackend+MaskedComposite.swift`, `Sources/CoreRender/Parity/Samples+MaskedComposite.swift`, `Tests/CoreRenderTests/CPUMaskedCompositeTests.swift`, `Tests/CoreRenderTests/Golden/maskedComposite/`, `Tests/mutations/CoreRenderCPUMaskedComposite.json` | MM-4, engine-contracts:EC-b | ~260, 5 + goldens |
| MM-6 | – | The five mask and matte commands, registry entries, `undoSteps`; turns on `MaskCommandsTests` | `Sources/FlareCore/MaskCommands.swift`, `Tests/FlareCoreTests/MaskCommandsTests.swift`, `Tests/mutations/FlareMaskCommands.json` | MM-2 | ~360, 3 |
| MM-7 | – | The render list's `clips` and `matte`; turns on `MatteRenderListTests` | `Sources/FlareCore/RenderList.swift`, `Tests/FlareCoreTests/MatteRenderListTests.swift`, `Tests/mutations/FlareMatteRenderList.json` | MM-2 | ~240, 3 |
| MM-8 | – | SVG and Lottie mask and matte writers; turns on both export suites | `Sources/FlareCore/Export/SVGExporter+Masks.swift`, `Sources/FlareCore/Export/LottieExporter+Masks.swift`, `Tests/FlareCoreTests/SVGMaskExportTests.swift`, `Tests/FlareCoreTests/LottieMaskExportTests.swift`, `Tests/mutations/FlareMaskExport.json` | MM-7 | ~320, 5 |
| MM-9 | – | KJ-MM walk, raster half in CoreRenderTests and vector half in FlareCoreTests (one suite name, so `MaskWalkTests.walk` runs both); `MaskBudgetTests` (release, `.serialized`) | `Tests/CoreRenderTests/MaskWalkTests.swift`, `Tests/FlareCoreTests/MaskWalkTests.swift`, `Tests/FlareCoreTests/Fixtures/mask-walk.flare`, `Tests/CoreRasterTests/MaskBudgetTests.swift` | MM-3, MM-5, MM-6, MM-8 | ~300, 4 |
| MM-10 | – | `geometry` part names the render list's clips and matte; the packet's status line and its `waves.md` row; the deviations note; `feature-done` | `docs/c4/parts/creative-core/flarecore/geometry.json`, `docs/blueprints/core/features/masks-mattes.md`, `docs/blueprints/core/features/waves.md` | MM-9, path-geometry | ~60, 3 |

## Build waves

- Wave 1: MM-1, MM-2. Independent in this wave: both.
- Wave 2: MM-3, MM-4, MM-6, MM-7. Independent in this wave: all four.
- Wave 3: MM-5, MM-8. Independent in this wave: both.
- Wave 4: MM-9. Independent in this wave: MM-9 alone.
- Wave 5: MM-10 (`feature-done`, final). Independent in this wave: MM-10 alone.

Longest chain: MM-2 → MM-7 → MM-8 → MM-9 → MM-10 (5). Chain of 5: the
writers read the render list's new entries, the walk exports through them,
MM-10 is the prose task.

## Acceptance test per task

| id | test | fails when | mutations (plan: label → filter) |
|---|---|---|---|
| MM-1 | the four suites compile, disabled | – | – |
| MM-2 | the vector suites compile, disabled; the fixture validates | – | – |
| MM-3 | `MaskOpsTests`: radius 0 returns self; a 64 px square feathered 6 keeps area within 1% and its edge row reads 0.5 at the edge; values stay in 0...1; NaN radius throws; `contours` of a ring gives 2 closed outlines (outer CCW, inner CW) with every point within 0.5 px of the analytic circle; empty mask has no contours and nil bounds; bounds of a 10 × 4 block at (3, 7) are exact | feather leaks past 1 or an outline is open | `CoreRaster.MaskFeather`: sigma = radius (not /3) → `MaskOpsTests.edgeIsHalfAtTheEdge`; clamp dropped → `.featherStaysInRange`. `CoreRaster.MaskContours`: saddle resolved by a fixed corner → `.saddleFollowsMean`; bounds use `<` for `<=` on max → `.boundsAreExact` |
| MM-4 | `MaskCompositeTests`: a full mask equals the unmasked composite with `==`; an empty mask leaves the backdrop; a half mask at opacity 1 equals the unmasked composite at 0.5 for every `BlendMode`; mask offset off every edge; luminance of white is 1, of black 0, of transparent white 0; `inverted` flips | coverage is ignored, or offset misplaced | `CoreRaster.CompositeMasked`: coverage read at `(x, y)` not `(x − maskX, y − maskY)` → `MaskCompositeTests.maskOffsetMoves`; skip-row test reads `> 0` as `>= 0` → `.emptyMaskLeavesBackdrop`; luminance ignores alpha → `.transparentIsZero` |
| MM-5 | `CPUMaskedCompositeTests`: the CPU backend equals the direct call for 50 seeded layer, mask and offset sets; a released surface throws `surfaceMismatch`; goldens reproduce with zero delta | a pixel differs from CoreRaster | `CoreRenderCPUMaskedComposite`: mask offsets swapped → `CPUMaskedCompositeTests.equalsDirect`; backdrop written outside the lock → `.concurrentCompositesApplyInTurn` |
| MM-6 | `MaskCommandsTests`: each command performs, undoes and redoes exactly; `SetLayerMask` drags merge into one step; a self matte, a two-step cycle, a source in another owner, a locked layer and an index out of range are refused with the document unchanged; the family's steps in `UndoPropertyTests` | undo leaves a trace, or a cycle is allowed | `FlareMaskCommands`: cycle check one step deep → `MaskCommandsTests.refusesCycleTwoDeep`; `MoveLayerMask` undo swaps the wrong pair → `.moveUndoesExactly`; merge across different masks → `.mergeOnlySameMask` |
| MM-7 | `MatteRenderListTests`: clip paths are in world space through the layer's and instances' matrices; a matte names its source's index and the source is flagged; a hidden matted layer gives no item; masks keep their order | a clip is in local space or the order flips | `FlareMatteRenderList`: clip skips the instance matrix → `MatteRenderListTests.clipInWorldSpace`; masks reversed → `.masksKeepOrder` |
| MM-8 | `SVGMaskExportTests`: the fixture writes one `clipPath`, one feathered `mask` with a blur of feather / 3, a `mask-type="luminance"` for the luma matte, byte-stable; `LottieMaskExportTests`: `masksProperties` modes and `tt: 3` with `td: 1` directly above; a non-finite value throws | a mode or matte kind is written wrong | `FlareMaskExport`: `difference` written as `s` → `LottieMaskExportTests.modesMapExactly`; `td` source written below → `.sourceAboveMatted`; blur uses half the feather → `SVGMaskExportTests.blurIsAThirdOfFeather` |
| MM-9 | `MaskWalkTests.walk` (KJ-MM); `MaskBudgetTests`: a 24 MP masked composite ≤ 1.3 × the unmasked one; feather of a 24 MP mask at radius 20 ≤ 250 ms; contours of a 24 MP selection ≤ 60 ms (release, reported) | the halves disagree on the walk | none: walk and budgets |
| MM-10 | the `geometry` part names clips and mattes | – | – |

## Quality tests

| quality row | budget | test |
|---|---|---|
| Masked composite cost | ≤ 1.3 × unmasked, 24 MP, median of 5 | `MaskBudgetTests.maskedCompositeCost` (release, reported) |
| Marching ants per frame | contours of a 24 MP selection ≤ 60 ms | `MaskBudgetTests.contoursFast` |
| Zero-delta reference | CPU backend `==` the CoreRaster call | `CPUMaskedCompositeTests` |
| Exact undo | every mask command in the cross-family property | `UndoPropertyTests` |
| Never crashes | 200 seeded masks with NaN, infinite and huge feathers throw or return | `MaskOpsTests.fuzz` |

## Done check

Per slice: tasks merged, checks green on the newest dev run with its last
PR, plans scored with no escape. MM-raster also goes to the Mac finisher
for the release budgets (rule 17, `Mac-Finish-Wanted: MM-raster`). Then the
contact sheet with the walk's numbers.

## Adopted later

- **W2:** S4 masks and track mattes on layers (Halo first; Flare, Photo,
  Design; re-cut of Photo PV-5 masks); S5 selection tools (feather and
  marching ants for Photo and Design; re-cut of PV-5); S6 Select Subject
  hands its mask to the same composite.
- **W4:** R2 ports the `maskedComposite` family to Metal and removes it from
  `notOnMetalYet`.

## Not in this packet

Rasterizing vector masks (each app's renderer does, from the render list's
paths). Refine edge and select-by-colour (S5 and `fill-tools`' colour range).
Mask animation over time beyond what `SetLayerMask` keys through
`animate-properties` (path keys on a mask use the same `PathKeyframe` type,
a W2 follow-up).

## Deviations (lead, 2026-10-19, slice MM-z)

- **Feather is one quantity everywhere: the blur radius.** A mask's
  `feather` is the radius of the Gaussian that softens its edge, with
  sigma = feather / 3 (the kernel reaches ceil(feather) pixels), in
  CoreRaster's `feathered(radius:)`, in the render list and in every
  exporter. The SVG exporter's blur is `stdDeviation` = feather / 3, so an
  exported mask matches the raster one.
- **Lottie `x` is the mask expansion** (lottie-spec `x`, the offset that
  grows or shrinks the mask path), not a feather. The exporter always writes
  `x: 0`; a mask with feather above 0 throws `unsupported("mask feather")`
  rather than write a hard edge in its place. The importer skips a mask with
  a nonzero `x` as "mask expansion".
- **The walk is split across two modules under one suite name.**
  CoreRenderTests can't import FlareCore, so `MaskWalkTests.walk` has a
  vector half (FlareCoreTests: command, undo, file, render list, SVG,
  Lottie) and a raster half (CoreRenderTests: feather, contours, composite
  through the dispatcher). The filter `MaskWalkTests` runs both.
- **Lottie text stand-in.** The Lottie exporter doesn't write text yet, so
  the walk checks the text source throws `unsupported("text")`, then swaps
  in a white box over the glyphs to check `td: 1` directly above `tt: 3`.
- **Budgets** (`MaskBudgetTests`, 6000 x 4000) are report-only in a debug
  build, which is what `scripts/ci` runs; an optimized build gates them, and
  the Mac finisher runs them there. Linux release numbers (shared cloud
  container, 4 cores, one run of 5-run medians), before and after this
  slice's fixes: masked composite 1.34 x to 1.20 x (202.6 ms vs 169.2 ms;
  budget 1.3 x); contours 257.7 ms to 52.6 ms (budget 60 ms); feather radius
  20 6159 ms to 722 ms (budget 250 ms), still over. The budgets stand: the
  Mac finisher's numbers decide verified-done.
- **Feather past sigma 2 is an extended box, not the exact Gaussian.**
  `feathered(radius:)` keeps sigma = radius / 3. Up to sigma 2 (radius 6) it
  is the exact Gaussian, so the goldens are unchanged (none moved). Past it,
  four passes per axis of the extended box filter (Gwosdek, Grewenig, Bruhn,
  Weickert, "Theoretical Foundations of Gaussian Convolution by Extended Box
  Filtering", SSVM 2011), whose variances sum to sigma² exactly, cost the same
  per pixel at any radius. They stay within 0.025 of the exact Gaussian
  (`MaskFeatherBoxTests`; 0.0171 on its seeded masks). `gaussianBlur` itself
  is unchanged and exact. The contour pass lists mixed cells from row flags
  first, and a masked composite keeps a weight-0 pixel's backdrop as is.
- **Built before path-geometry's last slices merged**, so the waves table and
  the C4 description may need a rebase onto them.
