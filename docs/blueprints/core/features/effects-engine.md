# Feature packet: effects-engine

**Feature:** the layer effects and filters every raster and motion app
shares, as CoreRaster ops behind one entry point,
`PixelBuffer.applying(_ effect: LayerEffect)`, and the CPU backend's new
`effect` family: box and motion blur (beside today's Gaussian), denoise
(edge-preserving), clarity (local contrast), outer and inner glow, drop and
inner shadow, and an alpha stroke (outside, inside, centre). Each effect
keeps the buffer's size; a caller that needs room for a shadow or glow pads
first (`affine-composite`'s `padded`). Linux-safe.
**Line:** `line:core` · **Wave:** 6 (`waves.md`) · **Lead branch:** `lead/effects-engine`
**Status:** planned

**Covers:** beta-80 plan row E4 (re-cut: Halo #39, the effects stack, whose
pixel half is built here once instead of inside Halo); Photo's layer styles
and filter rows, Library's noise reduction and clarity, Design's shadow row
(raster half).

**Depends on:** `engine-contracts` (EC-a: `Effects/` in `image-ops`, the
`effect` family, `LayerEffect` and `StrokePosition`; EC-b: the CPU and parity
seam files).

**C4:** container `coreraster`, component `image-ops`
(`Sources/CoreRaster/Effects/`); container `corerender`, components
`cpu-backend` (`CPUBackend+Effect.swift`) and `parity`
(`Samples+Effect.swift`). The effect *stack* (which effects a layer has,
their order, on and off, editable later) is suite-kernel `Effects`, a new
component S2 adds in creative-apps; this packet is only the pixels. No new
component here.

**Clean-room.** Box and motion blur, the bilateral filter, unsharp-mask
clarity, the exact Euclidean distance transform (Felzenszwalb and
Huttenlocher's published method), the anti-aliased edge distance strokes
measure (Gustavson and Strand's published 2011 method) and alpha-based
glows, shadows and strokes are public techniques; no task reads another product's code.

## Slices

| slice | behavior (one sentence) | tasks | checks | waits on |
|---|---|---|---|---|
| FX-a | Every effect's checks, reference images and seeded buffers are written, the checks disabled. | FX-1, FX-2 | `BlurFamilyTests`, `DenoiseClarityTests`, `AlphaEffectTests`, `CPUEffectTests` | engine-contracts:EC-a |
| FX-blur | Box and motion blur spread by their radius and angle, denoise smooths flat areas while keeping edges, and clarity raises local contrast without moving the mean, each identity at zero. | FX-3, FX-4 | `BlurFamilyTests`, `DenoiseClarityTests` | FX-a |
| FX-alpha | An exact distance field from alpha gives strokes outside, inside and centred at a width, and glows and shadows (outer and inner, offset, blurred, coloured) composite under or over the layer by the published conventions. | FX-5, FX-6 | `AlphaEffectTests`, `DistanceFieldTests` | FX-a |
| FX-cpu | `applying(_:)` runs every `LayerEffect` case, the CPU backend's `applying` equals it with `==`, and the CPU goldens are in. | FX-7, FX-8 | `CPUEffectTests`, `CPUGoldenTests` | FX-blur, FX-alpha; engine-contracts:EC-b |
| FX-z | A walk styles one layer with a stack of four effects on the CPU backend, the budgets hold, and the feature is built. | FX-9, FX-10 | `EffectWalkTests`, `EffectBudgetTests` | FX-cpu |

`ui_slice: none`: engine only. Its screens: S2 effects stack and layer
styles (Halo, Photo, Library, Design) and its SuiteUI effects panel.

## Journey steps

Engine only. KJ-FX (`EffectWalkTests.walk`, FX-9): a 600 × 400 layer with
a white rounded-rectangle shape on transparency, padded by 40 px, then
through a `RenderDispatcher` over a fake without `effect`: drop shadow (dx 8,
dy 8, blur 12, 50% black), stroke 4 px outside in blue, outer glow 16 px,
and `clarity(amount: 30, radius: 30)` on the result; each step equals the direct CoreRaster call,
and the shadow's darkest pixel sits 8 px right and down of the shape's
corner.

## Screens and states

None.

## Contract slice

`LayerEffect`, `StrokePosition` and the `effect` family are
`engine-contracts`'. This feature adds:

```swift
// Sources/CoreRaster/Effects/Effects.swift (FX-7)
extension PixelBuffer { public func applying(_ effect: LayerEffect) throws -> PixelBuffer }   // same size
// Sources/CoreRaster/Effects/BlurFamily.swift (FX-3)
extension PixelBuffer {
    public func boxBlurred(radius: Double) throws -> PixelBuffer                     // three passes approach a Gaussian; 0 is identity
    public func motionBlurred(degrees: Double, distance: Double) throws -> PixelBuffer
}
// Sources/CoreRaster/Effects/DenoiseClarity.swift (FX-4)
extension PixelBuffer {
    public func denoised(strength: Double, detail: Double) throws -> PixelBuffer     // 0...1 each
    public func clarity(amount: Double, radius: Double) throws -> PixelBuffer        // -100...100
}
// Sources/CoreRaster/Effects/DistanceField.swift (FX-5)
public struct DistanceField: Sendable { public let width: Int, height: Int
    public init(alpha buffer: PixelBuffer, level: Float = 0.5) throws
    public func outside(x: Int, y: Int) -> Float; public func inside(x: Int, y: Int) -> Float }
// Sources/CoreRaster/Effects/AlphaEffects.swift (FX-5 stroke, FX-6 glow and shadow)
extension PixelBuffer {
    public func stroked(color: RGBA, width: Double, position: StrokePosition) throws -> PixelBuffer
    public func glowing(color: RGBA, radius: Double, intensity: Double, inner: Bool) throws -> PixelBuffer
    public func shadowed(color: RGBA, dx: Double, dy: Double, blur: Double, inner: Bool) throws -> PixelBuffer
}
```

## Pseudocode

- **Edges.** Every effect clamps sampling at the buffer's edge (transparent
  outside for alpha effects, edge-extend for blurs on opaque content). Radius
  and distance caps: 0...1,000 px; strength and amount ranges as in the
  signatures; anything else throws `RasterError.invalid`.
- **boxBlurred.** Separable running sums of radius `r`, three passes (the
  result approaches a Gaussian); premultiplied, so colour doesn't bleed from
  transparent pixels.
- **motionBlurred.** Average of samples along the angle, `distance` long,
  bilinear, centred; the sample count is `ceil(distance)` + 1, capped at
  1,001.
- **denoised.** A bilateral filter: spatial sigma 1 + 4 × strength px,
  range sigma (1 − detail) × 0.2 in linear luma; chroma smoothed at twice the
  spatial sigma (colour noise goes first).
- **clarity.** `unsharpMask` with a large radius (no default; 30 px is the recommended value), its
  amount scaled by a mid-tone weight (luma 0.2...0.8 full, 0 at the ends) so
  shadows and highlights don't clip; negative amounts blend toward the
  blurred copy.
- **DistanceField.** Exact squared Euclidean distance transform (two 1D
  lower-envelope passes) to the alpha ≥ level set and to its complement;
  the field is in pixels.
- **stroked.** Coverage from one unsigned distance `d` to the anti-aliased
  alpha edge, not to pixel centres: every edge pixel gets a sub-pixel edge
  point from its alpha and its 3 × 3 alpha gradient (Gustavson and Strand,
  "Anti-aliased Euclidean distance transform", Pattern Recognition Letters,
  2011), `DistanceField.transform` finds each pixel's nearest edge pixel
  exactly, and `d` is the nearest of the edge points of it and its eight
  neighbours. Outside (off the alpha ≥ 0.5 shape) and inside (on it) both
  use `smoothstep(w + 0.5, w − 0.5, d)`, centre ±w/2; the stroke goes
  under the layer for outside, over it for inside and centre (clipped to the
  layer for inside).
- **glowing / shadowed.** Outer: the layer's alpha (offset for a shadow),
  Gaussian blurred by `radius` or `blur`, tinted, scaled by intensity or
  opacity, composited under the layer. Inner: the inverted alpha, blurred,
  offset, clipped by the layer's alpha, composited over it. `RGBA`
  colours are linear premultiplied like the buffers.

## Tasks

| id | issue | what | owned files | depends on | size |
|---|---|---|---|---|---|
| FX-1 | feature issue (re-cut of creative-apps Halo #39's pixel half) | Checks first: five suites disabled by name | `Tests/CoreRasterTests/BlurFamilyTests.swift`, `Tests/CoreRasterTests/DenoiseClarityTests.swift`, `Tests/CoreRasterTests/AlphaEffectTests.swift`, `Tests/CoreRasterTests/DistanceFieldTests.swift`, `Tests/CoreRenderTests/CPUEffectTests.swift` | engine-contracts:EC-a | ~360, 5 |
| FX-2 | – | Reference images (a disc, a 1 px line, a noisy flat patch with an edge, a text-like glyph mask) and analytic expectations | `Tests/CoreRasterTests/EffectFixtures.swift` | engine-contracts:EC-a | ~160, 1 |
| FX-3 | – | `boxBlurred`, `motionBlurred`; turns on `BlurFamilyTests` | `Sources/CoreRaster/Effects/BlurFamily.swift`, `Tests/CoreRasterTests/BlurFamilyTests.swift`, `Tests/mutations/CoreRaster.BlurFamily.json` | FX-1, FX-2 | ~260, 3 |
| FX-4 | – | `denoised`, `clarity`; turns on `DenoiseClarityTests` | `Sources/CoreRaster/Effects/DenoiseClarity.swift`, `Tests/CoreRasterTests/DenoiseClarityTests.swift`, `Tests/mutations/CoreRaster.DenoiseClarity.json` | FX-1, FX-2 | ~280, 3 |
| FX-5 | – | `DistanceField` and `stroked`; turns on `DistanceFieldTests` and the stroke cases | `Sources/CoreRaster/Effects/DistanceField.swift`, `Sources/CoreRaster/Effects/AlphaEffects.swift`, `Tests/CoreRasterTests/DistanceFieldTests.swift`, `Tests/CoreRasterTests/AlphaEffectTests.swift`, `Tests/mutations/CoreRaster.DistanceField.json` | FX-1, FX-2 | ~320, 5 |
| FX-6 | – | `glowing`, `shadowed` in a second file; turns on their cases | `Sources/CoreRaster/Effects/AlphaEffects+Light.swift`, `Tests/CoreRasterTests/AlphaEffectLightTests.swift`, `Tests/mutations/CoreRaster.AlphaEffects.json` | FX-5 | ~260, 3 |
| FX-7 | – | `applying(_:)` over every case; the CPU body; turns on `CPUEffectTests` | `Sources/CoreRaster/Effects/Effects.swift`, `Sources/CoreRender/CPU/CPUBackend+Effect.swift`, `Tests/CoreRenderTests/CPUEffectTests.swift`, `Tests/mutations/CoreRenderCPUEffect.json` | FX-3, FX-4, FX-6, engine-contracts:EC-b | ~160, 4 |
| FX-8 | – | `Samples+Effect.swift` and the CPU goldens | `Sources/CoreRender/Parity/Samples+Effect.swift`, `Tests/CoreRenderTests/Golden/effect/` | FX-7 | ~120, 1 + goldens |
| FX-9 | – | KJ-FX walk; `EffectBudgetTests` (release, `.serialized`) | `Tests/CoreRenderTests/EffectWalkTests.swift`, `Tests/CoreRasterTests/EffectBudgetTests.swift` | FX-8 | ~180, 2 |
| FX-10 | – | The packet's status line; `feature-done` | `docs/blueprints/core/features/effects-engine.md` | FX-9 | ~5, 1 |

FX-6 adds `AlphaEffects+Light.swift` rather than editing FX-5's file, and
its own test file, so the two only chain through the distance field they
both read (FX-6 calls FX-5's types).

## Build waves

- Wave 1: FX-1, FX-2. Independent in this wave: both.
- Wave 2: FX-3, FX-4, FX-5. Independent in this wave: all three.
- Wave 3: FX-6. Independent in this wave: FX-6 alone.
- Wave 4: FX-7. Independent in this wave: FX-7 alone.
- Wave 5: FX-8. Independent in this wave: FX-8 alone.
- Wave 6: FX-9. Independent in this wave: FX-9 alone.
- Wave 7: FX-10 (`feature-done`, final). Independent in this wave: FX-10 alone.

Longest chain: FX-1 → FX-5 → FX-6 → FX-7 → FX-8 → FX-9 → FX-10 (7).
Chain of 7: glow reads the distance field's types, `applying` calls every
op, the goldens are rendered by the CPU body, the walk and budgets time
them, FX-10 is the status task.

## Acceptance test per task

| id | test | fails when | mutations (plan: label → filter) |
|---|---|---|---|
| FX-1, FX-2 | suites compile, disabled; fixtures build | – | – |
| FX-3 | `BlurFamilyTests`: radius 0 and distance 0 are `==` identity; a disc's box blur keeps total premultiplied alpha within 1e-4; a 1 px vertical line under a horizontal motion blur of 9 spreads over 10 columns and no rows; a transparent neighbour never tints an edge; radius 2,000 throws | energy is lost or the blur runs along the wrong axis | `CoreRaster.BlurFamily`: sample count `distance` for `distance + 1` → `BlurFamilyTests.motionSpreadsTen`; unpremultiplied sum → `.noBleedFromTransparent`; angle in radians treated as degrees → `.horizontalSpreadsColumns` |
| FX-4 | `DenoiseClarityTests`: noise std on the flat patch drops ≥ 60% at strength 1 while the edge's 10–90% rise stays within 1 px; clarity 50 raises the std of a mid-grey texture and keeps its mean within 1/255; zero is identity | an edge blurs or the mean moves | `CoreRaster.DenoiseClarity`: range sigma ignored (plain Gaussian) → `DenoiseClarityTests.edgeKept`; mid-tone weight dropped → `.highlightsUnclipped` |
| FX-5 | `DistanceFieldTests`: the field of a single pixel equals the Euclidean distance exactly on a 64 × 64 grid; `AlphaEffectTests` stroke cases: a 4 px outside stroke of a disc covers the ring r…r+4 (area within 1%), inside covers r−4…r, centre r−2…r+2 | the field is city-block or a stroke lands on the wrong side | `CoreRaster.DistanceField`: one pass only → `DistanceFieldTests.exactEuclidean`; level `>=` for `>` → `.levelIsInclusive`; outside and inside swapped → `AlphaEffectTests.outsideStrokeIsOutside` |
| FX-6 | `AlphaEffectLightTests`: a drop shadow's centroid moves by (dx, dy); inner shadow never paints outside alpha; outer glow never paints inside the opaque shape over it; intensity 0 is identity | a shadow is offset the wrong way or a glow covers the layer | `CoreRaster.AlphaEffects`: dy sign flipped → `AlphaEffectLightTests.shadowMovesDown`; inner not clipped → `.innerStaysInside` |
| FX-7 | `CPUEffectTests`: every case of `LayerEffect` through the CPU backend `==` `applying(_:)`; a dispatcher over a fake without `effect` sends all to the CPU | a case maps to the wrong op | `CoreRenderCPUEffect`: `.glow(inner: true)` sent as outer → `CPUEffectTests.everyCaseEqualsDirect`; `.stroke` drops the position → `.strokeKeepsPosition` |
| FX-8 | `CPUGoldenTests`: zero delta on every effect golden | a golden changes | none: goldens |
| FX-9 | `EffectWalkTests.walk`; `EffectBudgetTests`: shadow + stroke + glow on a 2,000 × 2,000 layer ≤ 150 ms; denoise of 24 MP ≤ 1.5 s (release, reported) | the walk's checks fail | none |
| FX-10 | status line says built | – | – |

## Quality tests

| quality row | budget | test |
|---|---|---|
| Layer style on a 4 MP layer | shadow + stroke + glow ≤ 150 ms (CPU, release) | `EffectBudgetTests.styleStack` (reported) |
| Denoise a photo | 24 MP ≤ 1.5 s | `EffectBudgetTests.denoisePhoto` (reported) |
| Identity at zero | every effect at zero strength `==` identity | each suite's zero case |
| Never crashes | NaN, infinite and over-cap parameters throw; 200 seeded parameter sets per effect | each suite's fuzz case |

## Done check

Per slice as usual; FX-z's budgets on the Mac (`Mac-Finish-Wanted: FX-z`).
Then the contact sheet with the walk and the two budget numbers.

## Adopted later

- **W2:** S2 effects stack and layer styles, editable later (Halo first,
  then Photo, Library, Design), on suite-kernel `Effects` and the SuiteUI
  effects panel; S3 adjustment layers.
- **W3:** Halo drops its own effect code (#39 re-cut); Library's noise
  reduction and clarity rows.
- **W4:** R2 ports the `effect` family to Metal.

## Not in this packet

Bevel and emboss, satin, pattern overlay (v1). Lens and zoom blur. The
effect stack's order, on and off, and its save format (suite-kernel
`Effects`, S2). Vector shadows in Design's own renderer (adopt slice).
