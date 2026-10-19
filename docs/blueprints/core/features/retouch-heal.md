# Feature packet: retouch-heal

**Feature:** the retouch engine Photo's heal, spot heal, patch, dodge, burn,
sponge and smudge tools stand on, in CoreRaster: a true heal (source
texture cloned through a mask with its colour solved to blend seamlessly
into the destination's edges), fill from surroundings (remove a spot or an
object by building it from nearby texture, then healing the seam), and
per-dab ops (dodge and burn in a tonal range, sponge saturation, smudge with
a carried colour). Patch is a heal whose offset the user drags, so it has no
op of its own. Every op works on the dab or mask's bounds only, so a brush
stays at dab speed.
**Line:** `line:core` · **Wave:** 6 (`waves.md`) · **Lead branch:** `lead/retouch-heal`
**Status:** planned

**Covers:** beta-80 plan row E7 ("true heal, spot heal, patch, dodge/burn and
smudge dabs"); Photo blueprint 8.4 CR-7 (`healed(offset:through:)`, the
heal creative-core#232 specified and closed with `cloned` only); Photo map
rows 5 and 12 and its retouch row 9.

**Depends on:** `engine-contracts` (EC-a: the `Heal/` folder). It adds no
render family: the plan's "corerender `retouch`" is not grown, because the
`retouch` family's Metal kernel exists for `cloned` and a heal solve is an
edit-time op on a dab's bounds, run on the CPU through CoreRaster like
Photo's brush today. A GPU heal is R2's to add as its own family when a
profile asks for it (see Not in this packet).

**C4:** container `coreraster`, component `image-ops`
(`Sources/CoreRaster/Heal/`). No new component. The dab spacing and
pressure are suite-kernel `Stroke`'s (editor-kernel EK-stroke), used by the
app, not here.

**Clean-room.** The heal is the published gradient-domain (Poisson) image
editing method; fill from surroundings is the published randomized
patch-correspondence method followed by that heal; dodge, burn and sponge
are exposure and saturation weighted by a tonal range. No task reads
another product's code.

## Slices

| slice | behavior (one sentence) | tasks | checks | waits on |
|---|---|---|---|---|
| RH-a | The checks and fixtures (textured photos with spots, seams and a known gradient field) are written, the checks disabled. | RH-1, RH-2 | `HealTests`, `FillFromSurroundingsTests`, `ToneDabTests`, `SmudgeTests` | engine-contracts:EC-a |
| RH-heal | A heal clones texture through a mask and solves its colour so the result meets the destination's edge with no seam, and fill from surroundings removes a masked spot with texture from outside the mask, deterministic for a seed. | RH-3, RH-4 | `HealTests`, `FillFromSurroundingsTests` | RH-a |
| RH-dab | Dodge and burn lighten and darken only their tonal range under a dab, sponge raises or lowers saturation, and smudge drags a carried colour along successive dabs that fades by strength. | RH-5, RH-6 | `ToneDabTests`, `SmudgeTests` | RH-a |
| RH-z | A walk removes a spot, heals a patch and dodges, burns and smudges along a stroke of dabs, the budgets hold, and the feature is built. | RH-7, RH-8 | `RetouchWalkTests`, `RetouchBudgetTests` | RH-heal, RH-dab |

`ui_slice: none`: engine only. Its screens: Photo's heal, spot heal, patch,
dodge, burn, sponge and smudge tools (W3, Photo), drawn with the kernel's
brush cursor.

## Journey steps

Engine only. KJ-RH (`RetouchWalkTests.walk`, RH-7): a 2400 × 1600 textured
fixture with three dark spots and a known smooth light gradient; spot 1
filled from surroundings (the spot's mean within 3/255 of its ring's mean,
its texture variance within 25% of the ring's); spot 2 healed from an
offset (the seam's gradient error ≤ 1/255 per pixel along the mask edge);
a 30-dab dodge stroke on midtones lifts midtones and leaves pixels under
luma 0.2 within 1/255; a 20-dab smudge moves the colour along the stroke.

## Screens and states

None.

## Contract slice

```swift
// Sources/CoreRaster/Heal/Heal.swift (RH-3)
extension PixelBuffer {
    public static let maxHealPixels = 4_000_000                                       // the mask's covered area; more throws
    public func healed(offset: (dx: Int, dy: Int), through mask: Mask) throws -> PixelBuffer     // CR-7; only the mask's bounds change
}
// Sources/CoreRaster/Heal/FillFromSurroundings.swift (RH-4)
extension PixelBuffer {
    public func filledFromSurroundings(_ mask: Mask, seed: UInt64, patchRadius: Int = 3) throws -> PixelBuffer }
// Sources/CoreRaster/Heal/ToneDabs.swift (RH-5)
public enum TonalRange: Hashable, Sendable { case shadows, midtones, highlights }
extension PixelBuffer {
    public mutating func dodge(_ dab: Mask, x: Int, y: Int, range: TonalRange, exposure: Float) throws    // 0...1
    public mutating func burn(_ dab: Mask, x: Int, y: Int, range: TonalRange, exposure: Float) throws
    public mutating func sponge(_ dab: Mask, x: Int, y: Int, amount: Float) throws }                       // -1...1
// Sources/CoreRaster/Heal/Smudge.swift (RH-6)
public struct SmudgeState: Sendable { public init(strength: Float)                                         // 0...1
    public mutating func dab(_ dab: Mask, x: Int, y: Int, on buffer: inout PixelBuffer) throws }           // first dab picks up only
```

## Pseudocode

- **healed.** Copy the source (the buffer shifted by `offset`) inside the
  mask's bounds; per channel solve `Δf = Δg` inside the mask (g the source)
  with `f = destination` on the mask's boundary, by successive
  over-relaxation (ω 1.9) on premultiplied linear values, iterating until
  the largest change is < 1e-5 or 500 sweeps; feathered masks blend the
  solved result by coverage. Pixels outside the bounds are copied, never
  recomputed. More than `maxHealPixels` covered throws.
- **filledFromSurroundings.** Dilate the mask by `patchRadius`; for each
  hole pixel, a randomized nearest-neighbour search (seeded SplitMix64; 5
  iterations of propagation and random search) for the best `2r + 1` patch
  centred outside the hole; fill from the matches coarse to fine on a
  3-level pyramid; then heal the filled region against the ring, so its
  tone meets the edge. Same seed, same pixels.
- **Tone dabs.** Weight per pixel: dab coverage × range weight at the
  pixel's straight Rec. 709 luma (shadows: `1 − smoothstep(0.2, 0.4, luma)`,
  midtones: `smoothstep(0.2, 0.4, luma) × (1 − smoothstep(0.6, 0.8, luma))`,
  highlights: `smoothstep(0.6, 0.8, luma)`; the three sum to 1). The
  windows are this narrow because the acceptance needs exactly zero weight
  outside a range: a midtone dab must leave luma 0.1 and 0.95 within 1/255
  (RH-5) and pixels under luma 0.2 within 1/255 (the walk), which a
  triangular `1 − |2 luma − 1|` midtone (weight 0.2 at luma 0.1) cannot
  pass. Dodge multiplies linear colour by `1 + exposure × weight`, burn by
  `1 − exposure × weight × 0.5`, so at full weight exposure 1 doubles
  (dodge) or halves (burn) it; sponge scales chroma by
  `1 + amount × coverage`. Colour clamps to 0...alpha; alpha unchanged.
- **Smudge.** Hold a carried patch the dab's size; each dab blends the
  carried patch onto the buffer by `strength × coverage`, then replaces the
  carried patch with what is now under the dab (so the colour drags and
  fades). The first dab only picks up.

## Tasks

| id | issue | what | owned files | depends on | size |
|---|---|---|---|---|---|
| RH-1 | feature issue (also closes the CR-7 ask; creative-core#232 was its spec) | Checks first: four suites disabled by name | `Tests/CoreRasterTests/HealTests.swift`, `Tests/CoreRasterTests/FillFromSurroundingsTests.swift`, `Tests/CoreRasterTests/ToneDabTests.swift`, `Tests/CoreRasterTests/SmudgeTests.swift` | engine-contracts:EC-a | ~320, 4 |
| RH-2 | – | Fixtures: textured photo with spots, a known gradient field, dab masks | `Tests/CoreRasterTests/RetouchFixtures.swift` | engine-contracts:EC-a | ~140, 1 |
| RH-3 | – | `healed`; turns on `HealTests` | `Sources/CoreRaster/Heal/Heal.swift`, `Tests/CoreRasterTests/HealTests.swift`, `Tests/mutations/CoreRaster.Heal.json` | RH-1, RH-2 | ~280, 3 |
| RH-4 | – | `filledFromSurroundings`; turns on `FillFromSurroundingsTests` | `Sources/CoreRaster/Heal/FillFromSurroundings.swift`, `Tests/CoreRasterTests/FillFromSurroundingsTests.swift`, `Tests/mutations/CoreRaster.FillFromSurroundings.json` | RH-3 | ~360, 3 |
| RH-5 | – | `dodge`, `burn`, `sponge`; turns on `ToneDabTests` | `Sources/CoreRaster/Heal/ToneDabs.swift`, `Tests/CoreRasterTests/ToneDabTests.swift`, `Tests/mutations/CoreRaster.ToneDabs.json` | RH-1, RH-2 | ~200, 3 |
| RH-6 | – | `SmudgeState`; turns on `SmudgeTests` | `Sources/CoreRaster/Heal/Smudge.swift`, `Tests/CoreRasterTests/SmudgeTests.swift`, `Tests/mutations/CoreRaster.Smudge.json` | RH-1, RH-2 | ~160, 3 |
| RH-7 | – | KJ-RH walk; `RetouchBudgetTests` (release, `.serialized`) | `Tests/CoreRasterTests/RetouchWalkTests.swift`, `Tests/CoreRasterTests/RetouchBudgetTests.swift` | RH-4, RH-5, RH-6 | ~180, 2 |
| RH-8 | – | The packet's status line; `feature-done` | `docs/blueprints/core/features/retouch-heal.md` | RH-7 | ~5, 1 |

RH-4 waits on RH-3 because it heals its fill with `healed`.

## Build waves

- Wave 1: RH-1, RH-2. Independent in this wave: both.
- Wave 2: RH-3, RH-5, RH-6. Independent in this wave: all three.
- Wave 3: RH-4. Independent in this wave: RH-4 alone.
- Wave 4: RH-7. Independent in this wave: RH-7 alone.
- Wave 5: RH-8 (`feature-done`, final). Independent in this wave: RH-8 alone.

Longest chain: RH-1 → RH-3 → RH-4 → RH-7 → RH-8 (5). Chain of 5: the fill
heals its seam through `healed`, the walk uses both, RH-8 is the status
task.

## Acceptance test per task

| id | test | fails when | mutations (plan: label → filter) |
|---|---|---|---|
| RH-1, RH-2 | suites compile, disabled; fixtures build | – | – |
| RH-3 | `HealTests`: healing a patch of the known gradient field from an offset reproduces the field inside the mask within 1/255 (the texture's gradients kept, the tone matched); pixels outside the mask's bounds `==` the input; a mask over `maxHealPixels` throws; a zero offset with a full mask is identity; an offset off the buffer throws | a seam shows or pixels outside change | `CoreRaster.Heal`: boundary condition from the source not the destination → `HealTests.matchesDestinationEdge`; convergence test `>` for `<` (one sweep) → `.reproducesField`; bounds loop over the whole buffer → `.outsideBoundsUntouched` |
| RH-4 | `FillFromSurroundingsTests`: spot 1's mean within 3/255 of its ring, variance within 25%; same seed `==`, another seed differs; no hole pixel is copied from inside the hole; an empty mask is identity | a hole fills from itself or a seam shows | `CoreRaster.FillFromSurroundings`: candidate patches allowed inside the hole → `FillFromSurroundingsTests.neverCopiesFromHole`; heal step skipped → `.toneMeetsRing`; seed ignored (fixed) → `.seedChangesFill` |
| RH-5 | `ToneDabTests`: a midtone dodge lifts luma 0.5 and leaves luma 0.1 and 0.95 within 1/255; burn mirrors; sponge +1 raises chroma, −1 greys; alpha never changes; exposure 0 is identity | the wrong range moves | `CoreRaster.ToneDabs`: midtone weight `|2l − 1|` (inverted) → `ToneDabTests.midtonesOnly`; coverage ignored → `.dabCoverageWeights`; burn gain `−exposure` → `.dodgeBurnMagnitude`; weight on premultiplied luma, colour clamped to 1 → `.translucentUsesStraightLuma` |
| RH-6 | `SmudgeTests`: the first dab changes nothing; ten dabs along a line move a red edge's colour forward and its strength fades monotonically; strength 0 is identity | colour doesn't drag or never fades | `CoreRaster.Smudge`: carried patch not replaced after a dab → `SmudgeTests.colourFades`; first dab paints → `.firstDabPicksUp` |
| RH-7 | `RetouchWalkTests.walk`; `RetouchBudgetTests`: heal of a 200 px dab ≤ 12 ms; fill from surroundings of a 300 × 300 spot ≤ 400 ms; a tone dab of 200 px ≤ 1 ms (release, reported) | the walk's checks fail | none |
| RH-8 | status line says built | – | – |

## Quality tests

| quality row | budget | test |
|---|---|---|
| Heal at dab speed | 200 px dab ≤ 12 ms | `RetouchBudgetTests.healDab` (release, reported) |
| Remove a spot | 300 × 300 ≤ 400 ms | `RetouchBudgetTests.removeSpot` |
| Local only | nothing outside the mask's or dab's bounds changes | each suite's `outsideBoundsUntouched` |
| Deterministic | same seed, same pixels | `FillFromSurroundingsTests` |
| Never crashes | NaN, out-of-range strengths and offsets off the buffer throw | each suite's fuzz case |

## Done check

Per slice as usual; RH-z's budgets on the Mac (`Mac-Finish-Wanted: RH-z`).

## Adopted later

**W3:** Photo's heal (true heal replaces the per-dab mean shift in
`PhotoRetouch.swift`), spot heal, patch, dodge, burn, sponge and smudge
(P+4.4), each spaced by kernel `Stroke` and drawn with its brush cursor;
Library's spot removal later costs one adopt slice.

## Not in this packet

Content-aware move and scale, a GPU heal family (add one with R2 when a
profile shows the CPU heal over budget), blur and sharpen brushes (an app
can dab `gaussianBlur` and `unsharpMask` through a mask today), generative
fill.
