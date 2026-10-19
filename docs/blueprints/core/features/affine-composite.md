# Feature packet: affine-composite

**Feature:** free transforms for raster layers, once: resample a buffer
through any affine map (scale, rotate, skew, translate) with transparent
outside and today's `ResampleFilter` kernels, identity bit for bit; flip
exactly; resize the canvas (pad or crop around an anchor); and composite a
layer onto a backdrop *through* an affine map in place, so a moved, scaled
and rotated layer never needs a full-size intermediate copy. CoreRaster ops
plus the CPU backend's new `affine` family.
**Line:** `line:core` · **Wave:** 6 (`waves.md`) · **Lead branch:** `lead/affine-composite`
**Status:** planned

**Covers:** beta-80 plan row E5 ("affine composite, flip, canvas pad (CR-1,
CR-2, H6)"); Photo blueprint 8.4 CR-1 and CR-2 (PV-7 transform and flip);
the suite's H6 (Halo's image and footage layers, "needs affine composite").

**Depends on:** `engine-contracts` (EC-a: `Affine/` and `Compositing/`
folders, `AffineMatrix`, `FlipAxis`, `CanvasAnchor`, the `affine` family;
EC-b: `CPUBackend+Affine.swift`, `Samples+Affine.swift`).

**C4:** container `coreraster`, components `image-ops`
(`Sources/CoreRaster/Affine/`) and `compositing`
(`Compositing/CompositeAffine.swift`); container `corerender`, components
`cpu-backend` and `parity`. No new component.

**Clean-room.** Inverse-mapped resampling and source-over compositing are
public techniques; no task reads another product's code.

## Slices

| slice | behavior (one sentence) | tasks | checks | waits on |
|---|---|---|---|---|
| AC-a | The checks for every op and seeded layers and matrices are written, the checks disabled. | AC-1, AC-2 | `AffineOpsTests`, `CompositeAffineTests`, `CPUAffineTests` | engine-contracts:EC-a |
| AC-geo | A buffer resamples through any invertible matrix with transparent outside (identity and whole-pixel translations are exact copies), flips exactly, and the canvas pads or crops around any of nine anchors. | AC-3, AC-4 | `AffineOpsTests` | AC-a |
| AC-comp | A layer composites onto a backdrop through a matrix in place, equal to transforming it first and compositing the copy, touching only the transformed bounds, and the CPU backend runs the three `affine` calls with `==` results. | AC-5, AC-6 | `CompositeAffineTests`, `CPUAffineTests` | AC-geo; engine-contracts:EC-b (AC-6) |
| AC-z | The parity samples and goldens are in, a walk free-transforms a photo layer and a footage frame, the budgets hold, and the feature is built. | AC-7, AC-8, AC-9 | `CPUGoldenTests`, `AffineWalkTests`, `AffineBudgetTests` | AC-comp |

`ui_slice: none`: engine only. Its screens: S7 transform handles (Photo,
Design, Halo; re-cut of PV-7) and S20 placed images and footage.

## Journey steps

Engine only. KJ-AC (`AffineWalkTests.walk`, AC-8): a 3000 × 2000 layer
scaled 0.5, rotated 30° about its centre and moved (40, 25), composited
through the matrix onto a 4000 × 3000 white backdrop on the CPU backend:
equal within 1/255 to transform-then-composite, and only the rotated
bounds' rows changed; flipped twice is the input; the canvas padded to
5000 × 3000 at `.right` keeps the image's right edge at x 5000; a
1920 × 1080 frame placed at 0.25 scale with bilinear.

## Screens and states

None.

## Contract slice

```swift
// Sources/CoreRaster/Affine/AffineTransform.swift (AC-3)
extension PixelBuffer {
    public func transformed(_ m: AffineMatrix, width: Int, height: Int, filter: ResampleFilter) throws -> PixelBuffer  // singular m throws
    public func flipped(_ axis: FlipAxis) -> PixelBuffer
}
// Sources/CoreRaster/Affine/CanvasSize.swift (AC-4)
extension PixelBuffer { public func padded(width: Int, height: Int, anchor: CanvasAnchor) throws -> PixelBuffer }   // smaller crops
// Sources/CoreRaster/Compositing/CompositeAffine.swift (AC-5)
extension PixelBuffer {
    public mutating func composite(_ src: PixelBuffer, through m: AffineMatrix, mode: BlendMode, opacity: Float,
                                   filter: ResampleFilter) throws }
public extension AffineMatrix { func bounds(of width: Int, _ height: Int) -> (x: Int, y: Int, width: Int, height: Int)? }    // nil when non-finite
```

## Pseudocode

- **transformed.** For each output pixel centre `(x + 0.5, y + 0.5)`, map
  through `m.inverse` into the source; sample with the filter's kernel over
  premultiplied values; outside the source is transparent (zero).
  Fast paths: identity copies; a matrix that is a whole-pixel translation
  copies rows. A scale-only matrix has no separable fast path through
  `resized(width:height:filter:)`, because `resized` reads clamp-to-edge
  while `transformed` reads transparent outside the source.
  Any scale below 1 widens the kernel by the scale (no aliasing), as
  `resized(width:height:filter:)` does.
- **flipped.** Row reversal (vertical) or per-row element reversal
  (horizontal); no filter.
- **padded.** New buffer of the size, transparent; the old image placed at
  the anchor's offset (`(newW − oldW) × {0, 0.5, 1}`, rounded down);
  smaller sizes crop by the same offsets.
- **composite(through:).** Bounds of the source's corners under `m`,
  clipped to the backdrop; for each backdrop pixel in them, sample the
  source as `transformed` does and blend in place by the existing row blend
  for `mode`; rows outside the bounds aren't touched.

## Tasks

| id | issue | what | owned files | depends on | size |
|---|---|---|---|---|---|
| AC-1 | feature issue | Checks first: `AffineOpsTests`, `CompositeAffineTests`, `CPUAffineTests` disabled by name | `Tests/CoreRasterTests/AffineOpsTests.swift`, `Tests/CoreRasterTests/CompositeAffineTests.swift`, `Tests/CoreRenderTests/CPUAffineTests.swift` | engine-contracts:EC-a | ~300, 3 |
| AC-2 | – | Seeded layers (with transparent borders and hard edges) and matrices (identity, translations, 90° multiples, skews, near-singular) | `Tests/CoreRasterTests/AffineFixtures.swift` | engine-contracts:EC-a | ~120, 1 |
| AC-3 | – | `transformed` with its fast paths, `flipped`; turns on those cases | `Sources/CoreRaster/Affine/AffineTransform.swift`, `Tests/CoreRasterTests/AffineOpsTests.swift`, `Tests/mutations/CoreRaster.AffineTransform.json` | AC-1, AC-2 | ~340, 3 |
| AC-4 | – | `padded`; its cases in a second suite | `Sources/CoreRaster/Affine/CanvasSize.swift`, `Tests/CoreRasterTests/CanvasSizeTests.swift`, `Tests/mutations/CoreRaster.CanvasSize.json` | AC-2 | ~140, 3 |
| AC-5 | – | `composite(through:)` and `AffineMatrix.bounds`; turns on `CompositeAffineTests` | `Sources/CoreRaster/Compositing/CompositeAffine.swift`, `Tests/CoreRasterTests/CompositeAffineTests.swift`, `Tests/mutations/CoreRaster.CompositeAffine.json` | AC-3 | ~300, 3 |
| AC-6 | – | CPU bodies for `transformed`, `flipped`, `composite(through:)`; turns on `CPUAffineTests` | `Sources/CoreRender/CPU/CPUBackend+Affine.swift`, `Tests/CoreRenderTests/CPUAffineTests.swift`, `Tests/mutations/CoreRenderCPUAffine.json` | AC-5, engine-contracts:EC-b | ~200, 3 |
| AC-7 | – | `Samples+Affine.swift` and the CPU goldens | `Sources/CoreRender/Parity/Samples+Affine.swift`, `Tests/CoreRenderTests/Golden/affine/` | AC-6 | ~120, 1 + goldens |
| AC-8 | – | KJ-AC walk; `AffineBudgetTests` (release, `.serialized`) | `Tests/CoreRenderTests/AffineWalkTests.swift`, `Tests/CoreRasterTests/AffineBudgetTests.swift` | AC-4, AC-7 | ~160, 2 |
| AC-9 | – | The packet's status line; `feature-done` | `docs/blueprints/core/features/affine-composite.md` | AC-8 | ~5, 1 |

## Build waves

- Wave 1: AC-1, AC-2. Independent in this wave: both.
- Wave 2: AC-3, AC-4. Independent in this wave: both.
- Wave 3: AC-5. Independent in this wave: AC-5 alone.
- Wave 4: AC-6. Independent in this wave: AC-6 alone.
- Wave 5: AC-7. Independent in this wave: AC-7 alone.
- Wave 6: AC-8. Independent in this wave: AC-8 alone.
- Wave 7: AC-9 (`feature-done`, final). Independent in this wave: AC-9 alone.

Longest chain: AC-1 → AC-3 → AC-5 → AC-6 → AC-7 → AC-8 → AC-9 (7). Chain
of 7: the composite samples through `transformed`'s sampler, the CPU calls
the composite, the goldens come from the CPU, the walk and budgets time
them, AC-9 is the status task.

## Acceptance test per task

| id | test | fails when | mutations (plan: label → filter) |
|---|---|---|---|
| AC-1, AC-2 | suites compile, disabled; fixtures build | – | – |
| AC-3 | `AffineOpsTests`: identity and a (7, −3) translation are `==` copies (shifted); a 90° rotation about the centre equals `rotated(.degrees90)`; a 2× scale of a checkerboard keeps edge positions within 0.5 px; outside pixels are exactly 0; a singular matrix throws; `flipped` twice is `==` and once mirrors pixel (0, 0) to (w − 1, 0) | a pixel centre is off by half or outside isn't clear | `CoreRaster.AffineTransform`: sample at `(x, y)` not the centre → `AffineOpsTests.ninetyEqualsRotated`; inverse not used (forward map) → `.scaleKeepsEdges`; translation fast path off by one → `.translationIsExact`; vertical flip reverses columns → `.flipMirrorsRows` |
| AC-4 | `CanvasSizeTests`: padding 100 × 50 to 200 × 100 at each of nine anchors places the image at the expected offset; shrinking crops by the same rule; size 0 throws | an anchor offset is wrong | `CoreRaster.CanvasSize`: centre offset rounds up → `CanvasSizeTests.centreRoundsDown`; right uses `oldW − newW` → `.rightAnchorKeepsRightEdge` |
| AC-5 | `CompositeAffineTests`: for 50 seeded layers and matrices and every `BlendMode`, through-composite equals transform-then-composite within 1/255 (`==` for whole-pixel translations); backdrop rows outside the bounds are untouched; a matrix that maps the layer off the backdrop changes nothing | a pixel differs or rows outside change | `CoreRaster.CompositeAffine`: bounds from two corners only → `CompositeAffineTests.rotatedBoundsCoverCorners`; opacity applied twice → `.equalsTransformThenComposite` |
| AC-6 | `CPUAffineTests`: each `affine` call on the CPU `==` the direct op; a dispatcher over a fake without `affine` routes all three to the CPU | a wrapper reorders arguments | `CoreRenderCPUAffine`: width and height swapped → `CPUAffineTests.equalsDirect`; flip axis inverted → `.flipAxisKept` |
| AC-7 | `CPUGoldenTests` zero delta on every affine golden | a golden changes | none |
| AC-8 | `AffineWalkTests.walk`; `AffineBudgetTests`: a 12 MP layer through a rotate-scale onto 12 MP ≤ 140 ms bilinear, ≤ 260 ms Lanczos-3 (release, reported) | the walk's checks fail | none |
| AC-9 | status line says built | – | – |

## Quality tests

| quality row | budget | test |
|---|---|---|
| Live transform drag (preview) | a 2 MP preview layer through-composite ≤ 12 ms | `AffineBudgetTests.previewDrag` (release, reported) |
| Commit a transform | 12 MP rotate-scale ≤ 140 ms bilinear | `AffineBudgetTests.commit12MP` |
| Exact where it can be | identity and whole-pixel translations are `==` | `AffineOpsTests` |
| Never crashes | NaN or infinite matrices and sizes past the buffer cap throw | `AffineOpsTests.fuzz` |

## Done check

Per slice as usual; AC-z's budgets on the Mac (`Mac-Finish-Wanted: AC-z`).
Then the contact sheet with the walk and the budgets.

## Adopted later

- **W2:** S7 transform handles: rotate, scale, flip, canvas size (Photo
  first; Design, Halo; re-cut of PV-7) on kernel `Transform`/`Box`; S20
  placed images and footage, image fills, crop in frame (Design, Flare,
  Halo) composite through it.
- **W3:** Halo's image and footage layers (H6); Photo's PV-7 swaps in.
- **W4:** R2 ports the `affine` family to Metal.

## Not in this packet

Perspective and warp (non-affine), liquify, content-aware scale. Sub-layer
transforms of vector content (FlareCore's `Matrix` already does those).
