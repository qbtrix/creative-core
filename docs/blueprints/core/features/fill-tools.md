# Feature packet: fill-tools

**Feature:** the raster engine behind the paint bucket, the magic wand,
select by colour range and the gradient tool: a flood-fill mask from a seed
pixel (tolerance, contiguous or global, 4- or 8-connected, anti-aliased
edge), a colour-range mask with soft fuzziness from a sampled colour, and a
raster gradient (linear, radial, angle, reflected, diamond; stops with
colour and alpha; optional dither) rendered into a layer-sized buffer. The
outputs are a `Mask` and a `PixelBuffer`: the bucket fills by compositing a
solid colour through the mask with `masks-mattes`' masked composite, so no
second compositing path exists.
**Line:** `line:core` · **Wave:** 6 (`waves.md`) · **Lead branch:** `lead/fill-tools`
**Status:** built. Merged PRs: #568 (FT-2), #589 (FT-0), #595 (FT-1),
#608 (FT-3), #623 (FT-4), #612 (FT-5), #622 (FT-6), #654 (FT-7), the
review fixes #649, #650, #683, #688, #689, #765, #766, and this packet's
closing `feature-done` PR (FT-8). Deviations from the text below: the
KJ-FT walk checks the gradient buffer alone, since `masks-mattes` is not
on dev yet, and the masked-composite step is #767; the release budgets
run and report, and a miss is a known issue (flood fill 531 ms, colour
range 153 ms, gradient 1.9 s on 4-core Linux; #767); the 2 bytes per
pixel memory bound is checked as the flood fill's counted scratch on
every platform, and the resident peak is only printed; `GradientSpace.linear`
keeps its name and means linear-light sRGB mixing, not the linear shape;
`gradient` and `gradientMap` share one public `PixelBuffer.maxGradientStops`
(64) and one hard-edge rule (when two stops share an offset, the later one wins); dither
applies to the straight colour before premultiplying.

**Covers:** beta-80 plan row E6 ("flood fill, raster gradient, colour
range"); Photo map rows 8 and 9 (paint bucket and gradient; magic wand and
colour range: "needs a raster flood fill and gradient op in CoreRaster").

**Depends on:** `engine-contracts` (EC-a: the `Fill/` folder in
`image-ops`, `FillTolerance`, `RasterGradientShape`). No render family:
fills run once per click, on the CPU through CoreRaster directly.

**C4:** container `coreraster`, component `image-ops`
(`Sources/CoreRaster/Fill/`). No new component.

**Clean-room.** Scanline flood fill and gradient rendering are textbook
techniques; colour distance in OKLab uses CoreColor's existing conversion.
No task reads another product's code.

## Slices

| slice | behavior (one sentence) | tasks | checks | waits on |
|---|---|---|---|---|
| FT-a | The checks and seeded images (regions, gradients, anti-aliased edges, a 100 MP worst case) are written, the checks disabled. | FT-1, FT-2 | `FloodFillTests`, `ColorRangeTests`, `RasterGradientTests` | engine-contracts:EC-a |
| FT-mask | A flood fill from a seed covers exactly the connected pixels within tolerance (or every matching pixel when global) with a soft edge, and a colour range covers pixels by their distance from the sampled colour with fuzziness falloff, both bounded in time and memory. | FT-3, FT-4 | `FloodFillTests`, `ColorRangeTests` | FT-a |
| FT-grad | A gradient renders each of the five shapes between two points with its stops, in a stated interpolation space, with dither breaking banding and none when off. | FT-5, FT-6 | `RasterGradientTests` | FT-a |
| FT-z | A walk fills a region, selects by colour and draws a gradient through the fill mask, the budgets hold, and the feature is built. | FT-7, FT-8 | `FillWalkTests`, `FillBudgetTests` | FT-mask, FT-grad |

`ui_slice: none`: engine only. Its screens: Photo's paint bucket, magic
wand, colour range and gradient tools (W3, Photo) and S5's selection tools.

## Journey steps

Engine only. KJ-FT (`FillWalkTests.walk`, FT-7): a seeded 2000 × 1500
image of three flat regions with anti-aliased borders; a flood fill at
tolerance 0.1 from region B covers B's pixels and half-covers its border
pixels; a global fill picks B's twin region too; a colour range on region
C's colour with fuzziness 0.2 covers C and fades across its border; a
radial gradient drawn into B's mask (through `masks-mattes`' composite when
it is on `dev`, else checked as the gradient buffer alone) matches its
analytic value at five radii.

## Screens and states

None.

## Contract slice

```swift
// Sources/CoreRaster/Fill/FloodFill.swift (FT-3)
public enum Connectivity: Hashable, Sendable { case four, eight }
extension PixelBuffer {
    public func floodMask(from seed: (x: Int, y: Int), tolerance: FillTolerance, contiguous: Bool = true,
                          connectivity: Connectivity = .four, antiAlias: Bool = true) throws -> Mask }
// Sources/CoreRaster/Fill/ColorRange.swift (FT-4)
extension PixelBuffer {
    public func sampledColor(at p: (x: Int, y: Int), radius: Int) throws -> RGBA            // mean of a (2r + 1)² box, r 0...2
    public func colorRangeMask(around color: RGBA, fuzziness: Float) throws -> Mask }       // 0...1
// Sources/CoreRaster/Fill/RasterGradient.swift (FT-5, FT-6)
public enum GradientSpace: Hashable, Sendable { case linear, perceptual }                   // linear light, or OKLab
public struct RasterGradientStop: Hashable, Sendable { public var offset: Float; public var color: RGBA }
extension PixelBuffer {
    public static func gradient(width: Int, height: Int, shape: RasterGradientShape, from a: Mask.Point, to b: Mask.Point,
                                stops: [RasterGradientStop], space: GradientSpace = .perceptual, dither: Bool = true) throws -> PixelBuffer }
```

## Pseudocode

- **Distance.** Colour distance is the Euclidean OKLab distance of the
  unpremultiplied colours (alpha difference counted as a fourth axis),
  through CoreColor; `FillTolerance.within(t)` accepts `d ≤ t`; `.exact`
  accepts `d == 0`.
- **floodMask.** Scanline fill with an explicit stack of spans (never
  recursion), a visited bitset; global mode tests every pixel. Anti-alias:
  a rejected pixel next to an accepted one gets coverage `1 − (d − t) / t`
  clamped to 0...1 (a one-pixel soft edge). Seeds outside the buffer throw.
- **colorRangeMask.** Coverage `1 − smoothstep(0, max(f, 1e-4), d)` per
  pixel; fuzziness 0 gives a hard mask of exact matches.
- **gradient.** Parameter `t` per pixel centre: linear, projection onto
  `a→b`; radial, distance from `a` over `|b − a|`; angle, `atan2` around
  `a` from the direction of `b`, over 360°; reflected, `|linear|` mirrored
  at `a`; diamond, Chebyshev distance in the `a→b` frame. Clamp `t` to
  0...1; interpolate stops (sorted, 2...64, finite) in the chosen space;
  dither adds ±0.5/255 blue-noise-like ordered dither (a fixed 8 × 8
  threshold matrix) before the 8-bit display encode would quantise, so it
  is deterministic.

## Tasks

| id | issue | what | owned files | depends on | size |
|---|---|---|---|---|---|
| FT-1 | feature issue | Checks first: `FloodFillTests`, `ColorRangeTests`, `RasterGradientTests` disabled by name | `Tests/CoreRasterTests/FloodFillTests.swift`, `Tests/CoreRasterTests/ColorRangeTests.swift`, `Tests/CoreRasterTests/RasterGradientTests.swift` | engine-contracts:EC-a | ~320, 3 |
| FT-2 | – | Seeded images and analytic gradient values | `Tests/CoreRasterTests/FillFixtures.swift` | engine-contracts:EC-a | ~140, 1 |
| FT-3 | – | `floodMask`; turns on `FloodFillTests` | `Sources/CoreRaster/Fill/FloodFill.swift`, `Tests/CoreRasterTests/FloodFillTests.swift`, `Tests/mutations/CoreRaster.FloodFill.json` | FT-1, FT-2 | ~300, 3 |
| FT-4 | – | `sampledColor`, `colorRangeMask`; turns on `ColorRangeTests` | `Sources/CoreRaster/Fill/ColorRange.swift`, `Tests/CoreRasterTests/ColorRangeTests.swift`, `Tests/mutations/CoreRaster.ColorRange.json` | FT-1, FT-2 | ~180, 3 |
| FT-5 | – | The five shapes and stop interpolation; turns on the shape cases | `Sources/CoreRaster/Fill/RasterGradient.swift`, `Tests/CoreRasterTests/RasterGradientTests.swift`, `Tests/mutations/CoreRaster.RasterGradient.json` | FT-1, FT-2 | ~300, 3 |
| FT-6 | – | Dither in its own file, its cases in a second suite | `Sources/CoreRaster/Fill/GradientDither.swift`, `Tests/CoreRasterTests/GradientDitherTests.swift`, `Tests/mutations/CoreRaster.GradientDither.json` | FT-5 | ~120, 3 |
| FT-7 | – | KJ-FT walk; `FillBudgetTests` (release, `.serialized`) | `Tests/CoreRasterTests/FillWalkTests.swift`, `Tests/CoreRasterTests/FillBudgetTests.swift` | FT-3, FT-4, FT-6 | ~160, 2 |
| FT-8 | – | The packet's status line; `feature-done` | `docs/blueprints/core/features/fill-tools.md` | FT-7 | ~5, 1 |

## Build waves

- Wave 1: FT-1, FT-2. Independent in this wave: both.
- Wave 2: FT-3, FT-4, FT-5. Independent in this wave: all three.
- Wave 3: FT-6. Independent in this wave: FT-6 alone.
- Wave 4: FT-7. Independent in this wave: FT-7 alone.
- Wave 5: FT-8 (`feature-done`, final). Independent in this wave: FT-8 alone.

Longest chain: FT-1 → FT-5 → FT-6 → FT-7 → FT-8 (5). Chain of 5: dither
runs inside the gradient's pixel loop, the walk draws the dithered
gradient, FT-8 is the status task.

## Acceptance test per task

| id | test | fails when | mutations (plan: label → filter) |
|---|---|---|---|
| FT-1, FT-2 | suites compile, disabled; fixtures build | – | – |
| FT-3 | `FloodFillTests`: region B's mask covers exactly B's interior and half-covers its border at tolerance 0.1; `.exact` stops at the first anti-aliased pixel; global mode includes the disconnected twin; 4- vs 8-connected differ on a diagonal-only link; a seed outside throws; a 100 MP all-one-colour fill finishes with peak extra memory ≤ 2 bytes per pixel | a fill leaks through a diagonal or recurses | `CoreRaster.FloodFill`: 8-neighbours used for `.four` → `FloodFillTests.fourConnectedStopsAtDiagonal`; tolerance `<` for `<=` → `.toleranceIsInclusive`; soft edge skipped → `.borderHalfCovered` |
| FT-4 | `ColorRangeTests`: fuzziness 0 covers only exact matches; 0.2 covers C fully and falls to 0 by distance 0.2; `sampledColor` radius 1 is the 3 × 3 mean; radius 3 throws | coverage doesn't fall off | `CoreRaster.ColorRange`: smoothstep edges swapped → `ColorRangeTests.fallsOffWithDistance`; mean over 2 × 2 → `.threeByThreeMean` |
| FT-5 | `RasterGradientTests`: each shape at five parameter points matches its analytic `t` within 1e-6; stops interpolate in OKLab (the midpoint of red to green differs from the linear midpoint by the expected amount); unsorted or one stop throws | a shape's `t` is wrong | `CoreRaster.RasterGradient`: reflected not mirrored → `RasterGradientTests.reflectedMirrors`; angle from the x axis not from `a→b` → `.angleStartsAtB`; `t` not clamped → `.clampsPastEnd` |
| FT-6 | `GradientDitherTests`: a dark 256-px ramp's 8-bit encode has no run longer than 12 px with dither and some with it off; two renders are `==` (deterministic) | banding survives or output is random | `CoreRaster.GradientDither`: dither amplitude 0 → `GradientDitherTests.breaksBanding`; matrix indexed by `x` only → `.usesBothAxes` |
| FT-7 | `FillWalkTests.walk`; `FillBudgetTests`: a 24 MP flood fill ≤ 120 ms; colour range ≤ 90 ms; gradient ≤ 60 ms (release, reported) | the walk's checks fail | none |
| FT-8 | status line says built | – | – |

## Quality tests

| quality row | budget | test |
|---|---|---|
| Click to fill | 24 MP flood fill ≤ 120 ms | `FillBudgetTests.flood24MP` (release, reported) |
| Bounded memory | 100 MP worst-case fill ≤ 2 extra bytes per pixel | `FloodFillTests.worstCaseMemory` |
| Deterministic | every op `==` across two runs | each suite |
| Never crashes | NaN colours, seeds outside, 0-size buffers throw | each suite's fuzz case |

## Done check

Per slice as usual; FT-z's budgets on the Mac (`Mac-Finish-Wanted: FT-z`).

## Adopted later

**W3:** Photo's paint bucket, magic wand, select colour range and gradient
tools (P+3.1), the bucket and gradient filling through `masks-mattes`'
masked composite; S5 adds the wand to the selection tools. Later adopters
(Flare and Halo fills) cost one adopt slice each.

## Not in this packet

Content-aware fill (`retouch-heal`'s fill from surroundings), pattern
fills, noise and freeform gradients, gradient editing UI (S17's gradient
rows).
