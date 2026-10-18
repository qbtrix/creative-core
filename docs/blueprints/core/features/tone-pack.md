# Feature packet: tone-pack

**Feature:** the colour adjustments every raster app shares, as CoreRaster
ops and the CPU backend's new `color` family: vibrance; hue, saturation and
lightness (the one copy, moved from Photo); per-range HSL (eight hue
ranges); black and white with six channel weights and an optional tint;
channel mixer; colour balance (shadows, midtones, highlights, preserve
luminosity); gradient map; 3D LUT apply with a `.cube` reader; posterize;
threshold; invert; and an auto tone that suggests levels and white balance
from a histogram. Linux-safe; Float32 linear premultiplied in and out, like
every op today.
**Line:** `line:core` · **Wave:** 6 (`waves.md`) · **Lead branch:** `lead/tone-pack`

**Covers:** beta-80 plan row E3 ("vibrance, auto, HSL, B&W, mixers, LUT,
Hue/Sat into core"); Photo blueprint 8.4 CR-5 (Hue/Saturation into
CoreRaster); Photo map rows 13 and 10 (colour adjustments), Library's
develop colour rows, Halo's colour correction row.

**Depends on:** `engine-contracts` (EC-a: `Tone/` in `image-ops`, the
`color` family and the W1 `ToneAdjustment` cases with their value types;
EC-b: `CPUBackend+Color.swift` and `Samples+Color.swift`).

**C4:** container `coreraster`, component `image-ops` (`Sources/CoreRaster/Tone/`);
container `corerender`, components `contract` (`ToneAdjustment`'s colour
cases, EC's), `cpu-backend` (`CPUBackend+Color.swift`) and `parity`
(`Samples+Color.swift`). ⚠ Photo's `HueSaturation.swift` moves here (TP-3
keeps its output); Photo deletes its copy in its W3 adoption. No new
component.

**Clean-room.** Every formula is stated here from public colour science
(Rec. 709 luma, HSL hue sectors, trilinear interpolation, the published
`.cube` LUT text format) or from this suite's own Photo code; no task reads
another product's code.

## Slices

| slice | behavior (one sentence) | tasks | checks | waits on |
|---|---|---|---|---|
| TP-a | Every colour op's checks and the reference colours, `.cube` fixtures and seeded buffers are written, the checks disabled. | TP-1, TP-2 | `ColorAdjustTests`, `ColorMixTests`, `ColorMapTests`, `ColorLUTTests`, `AutoToneTests`, `CPUColorTests` | engine-contracts:EC-a |
| TP-mix | Vibrance, hue/saturation/lightness, per-range HSL, black and white, channel mixer and colour balance change colour by their formulas, leave alpha and fully transparent pixels alone, and are identity at their neutral settings. | TP-3, TP-4 | `ColorAdjustTests`, `ColorMixTests` | TP-a |
| TP-map | Gradient map, LUT apply, `.cube` read, posterize, threshold and invert map colours by their tables, a damaged `.cube` throws, and auto tone suggests levels and a white balance that neutralise a cast. | TP-5, TP-6 | `ColorMapTests`, `ColorLUTTests`, `AutoToneTests` | TP-a |
| TP-cpu | The CPU backend runs every colour case through CoreRaster with `==` results, a `RenderDispatcher` sends them to the CPU while the old tone cases still go to the preferred backend, and the CPU goldens are in. | TP-7, TP-8 | `CPUColorTests`, `CPUGoldenTests` | TP-mix, TP-map; engine-contracts:EC-b |
| TP-z | A walk takes one photo through every colour op on the CPU backend, the budgets hold, and the feature is built. | TP-9, TP-10 | `ToneWalkTests`, `ToneBudgetTests` | TP-cpu |

`ui_slice: none`: engine only. Its screen: S1 tone and colour adjustments as
inspector rows and adjustment kinds (Photo, Library, Halo).

## Journey steps

Engine only. KJ-TP (`ToneWalkTests.walk`, TP-9): a seeded 1024 × 683
"photo" with a warm cast; auto tone's suggestion applied (the mean of the
grey patch within 2/255 of neutral); then vibrance 30, HSL blues −20
saturation, black and white default, invert twice (identity), a 17³ `.cube`
identity LUT (identity within 1e-5), posterize 4 (4 levels per channel);
every step through a `RenderDispatcher` over a fake that supports `.adjust`
only, so the colour cases land on the CPU and `contrast` on the fake.

## Screens and states

None.

## Contract slice

The `ToneAdjustment` cases, `family` and the value types (`HSLAdjustment`,
`GrayMix`, `ChannelMatrix`, `ToneBalance`, `GradientMapStop`, `ColorLUT`) are
`engine-contracts`'. This feature adds the CoreRaster ops:

```swift
// Sources/CoreRaster/Tone/ColorAdjust.swift (TP-3)
extension PixelBuffer {
    public func vibrance(_ amount: Float) throws -> PixelBuffer                                   // -100...100
    public func hueSaturation(hue: Float, saturation: Float, lightness: Float) throws -> PixelBuffer   // degrees, -100...100
    public func hsl(_ adjustment: HSLAdjustment) throws -> PixelBuffer
}
// Sources/CoreRaster/Tone/ColorMix.swift (TP-4)
extension PixelBuffer {
    public func blackAndWhite(_ mix: GrayMix) throws -> PixelBuffer
    public func channelMixer(_ m: ChannelMatrix) throws -> PixelBuffer
    public func colorBalance(_ b: ToneBalance) throws -> PixelBuffer
}
// Sources/CoreRaster/Tone/ColorMap.swift (TP-5)
extension PixelBuffer {
    public func gradientMap(_ stops: [GradientMapStop]) throws -> PixelBuffer       // 2...64 stops, sorted
    public func applying(_ lut: ColorLUT) throws -> PixelBuffer                      // trilinear, on sRGB-encoded values
    public func posterized(levels: Int) throws -> PixelBuffer                        // 2...255
    public func thresholded(_ level: Float) throws -> PixelBuffer                    // 0...1 on luma
    public func inverted() -> PixelBuffer
}
// Sources/CoreRaster/Tone/CubeLUT.swift (TP-5)
public enum CubeLUT { public static func parse(_ text: String) throws -> ColorLUT }   // LUT_3D_SIZE, DOMAIN_MIN/MAX 0...1 only
// Sources/CoreRaster/Tone/AutoTone.swift (TP-6)
public struct AutoTone: Hashable, Sendable { public var inBlack: Float, inWhite: Float, gamma: Float, temperature: Float, tint: Float
    public static func suggest(for buffer: PixelBuffer) throws -> AutoTone }       // reads Histogram, clips 0.1% each end
```

## Pseudocode

- **Working space.** Ops that are defined on display values (HSL ranges,
  gradient map, LUT, posterize, threshold) unpremultiply, encode sRGB with
  CoreColor's `TransferCurve`, apply, decode and premultiply; linear ops
  (channel mixer, vibrance's chroma scale) stay linear. A pixel with alpha 0
  is passed through untouched. Each op's header says which space it uses.
- **vibrance.** Saturation boost weighted by `1 − s` (low-saturation
  pixels move most) and damped for skin hues (hue 15°–50°) by half; negative
  amounts desaturate evenly.
- **hueSaturation.** The formula in Photo's `HueSaturation.swift` at
  creative-apps `origin/dev` (this suite's code), so the adoption is a swap
  with equal pixels.
- **hsl.** Eight ranges centred at 0, 30, 60, 120, 180, 240, 270, 300
  degrees; a pixel's weight per range is a raised cosine over the
  neighbouring centres, so weights sum to 1; shifts are summed by weight.
- **blackAndWhite.** Gray = Σ weight(hue range) × luma-normalised channel,
  the six weights in percent (default 40, 60, 40, 60, 20, 80); `tint` mixes
  the result through a soft-light of the tint colour.
- **colorBalance.** Shifts per tonal zone weighted by smoothsteps over
  luma (shadows < 0.33, highlights > 0.66); `preserveLuminosity` rescales
  the result to the input's luma.
- **LUT.** `.cube` text: comments `#`, `TITLE`, `LUT_3D_SIZE n` (2...65),
  `DOMAIN_MIN`/`DOMAIN_MAX` (only 0 0 0 and 1 1 1 accepted, else throw),
  then `n³` lines of three finite floats, red fastest. Apply: trilinear on
  the sRGB-encoded value, clamped to 0...1.
- **AutoTone.** Per-channel histogram; black and white points at 0.1% and
  99.9% of the luma histogram; gamma that puts the median at 0.5;
  temperature and tint from the mean of the brightest 5% non-clipped pixels,
  mapped back through `whiteBalance`'s own model so applying it neutralises
  that mean.

## Tasks

| id | issue | what | owned files | depends on | size |
|---|---|---|---|---|---|
| TP-1 | feature issue | Checks first: the six suites disabled by name | `Tests/CoreRasterTests/ColorAdjustTests.swift`, `Tests/CoreRasterTests/ColorMixTests.swift`, `Tests/CoreRasterTests/ColorMapTests.swift`, `Tests/CoreRasterTests/ColorLUTTests.swift`, `Tests/CoreRasterTests/AutoToneTests.swift`, `Tests/CoreRenderTests/CPUColorTests.swift` | engine-contracts:EC-a | ~380, 6 |
| TP-2 | – | Reference colours (hand-computed expected values per op), `.cube` fixtures (identity 17³, a warm look 33³, five damaged files), the cast photo | `Tests/CoreRasterTests/ToneFixtures.swift`, `Tests/CoreRasterTests/Fixtures/luts/` | engine-contracts:EC-a | ~200, 1 + fixtures |
| TP-3 | – | `vibrance`, `hueSaturation` (Photo's formula), `hsl`; turns on `ColorAdjustTests` | `Sources/CoreRaster/Tone/ColorAdjust.swift`, `Tests/CoreRasterTests/ColorAdjustTests.swift`, `Tests/mutations/CoreRaster.ColorAdjust.json` | TP-1, TP-2 | ~340, 3 |
| TP-4 | – | `blackAndWhite`, `channelMixer`, `colorBalance`; turns on `ColorMixTests` | `Sources/CoreRaster/Tone/ColorMix.swift`, `Tests/CoreRasterTests/ColorMixTests.swift`, `Tests/mutations/CoreRaster.ColorMix.json` | TP-1, TP-2 | ~300, 3 |
| TP-5 | – | `gradientMap`, LUT apply, `CubeLUT.parse` with its fuzz test, `posterized`, `thresholded`, `inverted`; turns on `ColorMapTests`, `ColorLUTTests` | `Sources/CoreRaster/Tone/ColorMap.swift`, `Sources/CoreRaster/Tone/CubeLUT.swift`, `Tests/CoreRasterTests/ColorMapTests.swift`, `Tests/CoreRasterTests/ColorLUTTests.swift`, `Tests/mutations/CoreRaster.ColorMap.json`, `Tests/mutations/CoreRaster.CubeLUT.json` | TP-1, TP-2 | ~380, 6 |
| TP-6 | – | `AutoTone.suggest`; turns on `AutoToneTests` | `Sources/CoreRaster/Tone/AutoTone.swift`, `Tests/CoreRasterTests/AutoToneTests.swift`, `Tests/mutations/CoreRaster.AutoTone.json` | TP-1, TP-2 | ~200, 3 |
| TP-7 | – | `CPUBackend+Color.swift` body: each colour case calls its CoreRaster op; turns on `CPUColorTests` | `Sources/CoreRender/CPU/CPUBackend+Color.swift`, `Tests/CoreRenderTests/CPUColorTests.swift`, `Tests/mutations/CoreRenderCPUColor.json` | TP-3, TP-4, TP-5, engine-contracts:EC-b | ~160, 3 |
| TP-8 | – | `Samples+Color.swift` (one sample per case on the edge-case buffers) and the CPU goldens | `Sources/CoreRender/Parity/Samples+Color.swift`, `Tests/CoreRenderTests/Golden/color/` | TP-7 | ~120, 1 + goldens |
| TP-9 | – | KJ-TP walk; `ToneBudgetTests` (release, `.serialized`) | `Tests/CoreRenderTests/ToneWalkTests.swift`, `Tests/CoreRasterTests/ToneBudgetTests.swift` | TP-6, TP-8 | ~180, 2 |
| TP-10 | – | the packet's status line; `feature-done` | `docs/blueprints/core/features/tone-pack.md` | TP-9 | ~10, 1 |

## Build waves

- Wave 1: TP-1, TP-2. Independent in this wave: both.
- Wave 2: TP-3, TP-4, TP-5, TP-6. Independent in this wave: all four.
- Wave 3: TP-7. Independent in this wave: TP-7 alone.
- Wave 4: TP-8. Independent in this wave: TP-8 alone.
- Wave 5: TP-9. Independent in this wave: TP-9 alone.
- Wave 6: TP-10 (`feature-done`, final). Independent in this wave: TP-10 alone.

Longest chain: TP-1 → TP-3 → TP-7 → TP-8 → TP-9 → TP-10 (6). Chain of 6:
the CPU body calls the ops, the goldens are rendered by the CPU body, the
walk reads them, TP-10 is the prose task.

## Acceptance test per task

| id | test | fails when | mutations (plan: label → filter) |
|---|---|---|---|
| TP-1 | six suites compile, disabled | – | – |
| TP-2 | every fixture parses or fails as labelled | – | – |
| TP-3 | `ColorAdjustTests`: every op at neutral is `==` identity; vibrance 100 moves a 10%-saturated pixel more than a 90% one and a skin tone half as much; `hueSaturation` matches Photo's formula on 1,000 seeded pixels within 1e-6; `hsl` blues −100 saturation greys a pure blue and leaves a pure red; alpha and alpha-0 pixels unchanged | a range bleeds or alpha moves | `CoreRaster.ColorAdjust`: vibrance weight `s` for `1 − s` → `ColorAdjustTests.lowSaturationMovesMost`; skin damping dropped → `.skinMovesHalf`; HSL weights don't sum to 1 (cosine over one neighbour) → `.rangeWeightsSumToOne` |
| TP-4 | `ColorMixTests`: default B&W of pure red is 0.40 luma-normalised; an identity matrix is identity; `monochrome` gives r == g == b; colour balance +shadows red leaves a white pixel; `preserveLuminosity` keeps luma within 1e-5 | a weight is read from the wrong channel | `CoreRaster.ColorMix`: weights indexed by channel not hue range → `ColorMixTests.redWeightIsForty`; preserve skipped → `.preserveKeepsLuma`; zone smoothstep edges swapped → `.whiteUnmovedByShadows` |
| TP-5 | `ColorMapTests`: a black-to-white map is the luma; posterize 2 gives only 0 and 1; threshold 0.5 splits at luma 0.5; `inverted()` twice is `==`; `ColorLUTTests`: identity LUT within 1e-5; the warm look matches hand values at 8 lattice points exactly and at 8 midpoints within 1e-6; each damaged file throws (size 1, 66, short table, NaN, DOMAIN 0…2); 500 seeded mutated files throw or parse, never crash | a lattice point is off or a damaged file loads | `CoreRaster.ColorMap`: posterize rounds with `floor` → `ColorMapTests.posterizeTwoLevels`; threshold compares red not luma → `.thresholdOnLuma`. `CoreRaster.CubeLUT`: blue-fastest order → `ColorLUTTests.redFastest`; domain check skipped → `.refusesOtherDomain`; interpolation nearest → `.midpointsTrilinear` |
| TP-6 | `AutoToneTests`: the cast photo's suggestion applied neutralises the grey patch within 2/255; a clean grey ramp suggests identity within 1e-3; an all-black buffer suggests identity, never NaN | a cast survives or a flat image gives NaN | `CoreRaster.AutoTone`: clip 1% for 0.1% → `AutoToneTests.rampIsIdentity`; division by an empty bright set → `.blackSuggestsIdentity` |
| TP-7 | `CPUColorTests`: each colour case on the CPU backend `==` its CoreRaster call; a `RenderDispatcher` over a fake with `.adjust` sends `.vibrance` to the CPU and `.contrast` to the fake | a case calls the wrong op | `CoreRenderCPUColor`: `.threshold` mapped to `posterized` → `CPUColorTests.everyCaseEqualsDirect`; LUT applied twice → `.lutOnce` |
| TP-8 | `CPUGoldenTests` reproduces every colour golden with zero delta | a golden changes | none: goldens |
| TP-9 | `ToneWalkTests.walk` (KJ-TP); `ToneBudgetTests`: each colour op on 24 MP ≤ 120 ms, LUT 33³ ≤ 180 ms (release, reported) | the walk's checks fail | none: walk and budgets |
| TP-10 | status line says built | – | – |

## Quality tests

| quality row | budget | test |
|---|---|---|
| Slider drag on a preview | each op ≤ 120 ms on 24 MP (CPU, release); 2 MP preview ≤ 12 ms | `ToneBudgetTests` (reported; the Mac finisher records them) |
| Identity at neutral | every op `==` identity at its neutral value | `ColorAdjustTests`, `ColorMixTests`, `ColorMapTests` |
| One Hue/Sat | the suite has one hue/saturation formula, in CoreRaster | jscpd in `scripts/ci`; creative-apps' W3 adoption deletes Photo's |
| Never crashes | the `.cube` fuzz; NaN parameters throw `RasterError.invalid` | `ColorLUTTests.fuzz`, every suite's NaN case |

## Done check

Per slice: tasks merged, checks green on the newest dev run with its last
PR, plans scored with no escape; TP-z's budgets on the Mac
(`Mac-Finish-Wanted: TP-z`). Then the contact sheet with each op's 24 MP
time.

## Adopted later

- **W2:** S1 tone and colour adjustments as inspector rows and adjustment
  kinds (Photo first, then Library develop, Halo); S3 adjustment layers as a
  kernel layer kind.
- **W3:** Photo deletes `HueSaturation.swift` and draws through the `color`
  family; Library's develop and Halo's colour rows adopt the same cases.
- **W4:** R2 ports the `color` family to Metal.

## Not in this packet

Selective colour and curves per channel beyond today's `curves` (v1).
Camera raw colour (Library raw, W3). Colour profiles and 16-bit
(`color-profiles`). `.3dl` and other LUT formats.
