# tone-pack lead record

Issue: #432 · Packet: docs/blueprints/core/features/tone-pack.md
Run: act-1a150bfbcf7-sfwy · Session: cse_01NZM1f4cdnQ6PPn761pxTEp · Started: 2026-10-18T20:45Z
Stage: 3 wave 2
Base: 15e96dd47c720025f5ae49b3649608deb65ab216
Next: wave 2 builder running (TP-1 checks-first suites); then wave 3 once it merges

Line lead for #434, #433 and #432 (rule 19); one wave plan across the three
features, bookkeeping per feature. Packet v3 (has a Slices table).

## Tasks
| id | wave | slice | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|---|
| TP-0 | 1 | TP-a | Stubs for the contract slice's signatures (rule 18): the 13 ops, `CubeLUT.parse`, `AutoTone`; throwing ones throw `RasterError.invalid("not built")`, `inverted()` returns self | `Sources/CoreRaster/Tone/{ColorAdjust,ColorMix,ColorMap,CubeLUT,AutoTone}.swift`, `Tests/CoreRasterTests/ToneStubTests.swift` | `ToneStubTests` | none (no invariant) | #561 | merged |
| TP-2 | 1 | TP-a | Reference colours, `.cube` fixtures (identity 17³, warm 33³, five damaged) generated as text in code, the cast photo | `Tests/CoreRasterTests/ToneFixtures.swift` | every fixture parses or fails as labelled (checked in TP-5) | none | #569 | merged |
| TP-1 | 2 | TP-a | Checks first: six suites disabled by name | `Tests/CoreRasterTests/{ColorAdjust,ColorMix,ColorMap,ColorLUT,AutoTone}Tests.swift`, `Tests/CoreRenderTests/CPUColorTests.swift` | suites compile, disabled | none | | building |
| TP-3 | 3 | TP-mix | `vibrance`, `hueSaturation`, `hsl`; turns on `ColorAdjustTests` | `Sources/CoreRaster/Tone/ColorAdjust.swift`, its tests, `Tests/mutations/CoreRaster.ColorAdjust.json` | `ColorAdjustTests` | 3 (packet) | | planned |
| TP-4 | 3 | TP-mix | `blackAndWhite`, `channelMixer`, `colorBalance`; turns on `ColorMixTests` | `Sources/CoreRaster/Tone/ColorMix.swift`, its tests, `Tests/mutations/CoreRaster.ColorMix.json` | `ColorMixTests` | 3 (packet) | | planned |
| TP-5 | 3 | TP-map | `gradientMap`, LUT apply, `CubeLUT.parse` + fuzz, `posterized`, `thresholded`, `inverted`; turns on `ColorMapTests`, `ColorLUTTests` | `Sources/CoreRaster/Tone/ColorMap.swift`, `Sources/CoreRaster/Tone/CubeLUT.swift`, both tests, `Tests/mutations/CoreRaster.ColorMap.json`, `Tests/mutations/CoreRaster.CubeLUT.json` | `ColorMapTests`, `ColorLUTTests` | 5 (packet) | | planned |
| TP-6 | 3 | TP-map | `AutoTone.suggest`; turns on `AutoToneTests` | `Sources/CoreRaster/Tone/AutoTone.swift`, its tests, `Tests/mutations/CoreRaster.AutoTone.json` | `AutoToneTests` | 2 (packet) | | planned |
| TP-7 | 5 | TP-cpu | `CPUBackend+Color.swift` body; turns on `CPUColorTests` | `Sources/CoreRender/CPU/CPUBackend+Color.swift`, `Tests/CoreRenderTests/CPUColorTests.swift`, `Tests/mutations/CoreRenderCPUColor.json` | `CPUColorTests` | 2 (packet) | | planned |
| TP-8 | 6 | TP-cpu | `Samples+Color.swift` and CPU goldens | `Sources/CoreRender/Parity/Samples+Color.swift`, `Tests/CoreRenderTests/Golden/color/` | `CPUGoldenTests` | none: goldens | | planned |
| TP-9 | 7 | TP-z | KJ-TP walk; `ToneBudgetTests` (release, `.serialized`, reported) | `Tests/CoreRenderTests/ToneWalkTests.swift`, `Tests/CoreRasterTests/ToneBudgetTests.swift` | `ToneWalkTests.walk` | none | | planned |
| TP-10 | 8 | TP-z | Packet status line says built; `feature-done` | `docs/blueprints/core/features/tone-pack.md` | – | none | | planned |

## Acceptance (from the packet)
- TP-3 `ColorAdjustTests`: every op at neutral `==` identity; vibrance 100 moves a 10%-saturated pixel more than a 90% one and a skin tone half as much; `hueSaturation` matches Photo's formula on 1,000 seeded pixels within 1e-6; `hsl` blues −100 saturation greys pure blue, leaves pure red; alpha and alpha-0 pixels unchanged. Mutations: `s` for `1 − s` → `lowSaturationMovesMost`; skin damping dropped → `skinMovesHalf`; weights over one neighbour → `rangeWeightsSumToOne`.
- TP-4 `ColorMixTests`: default B&W of pure red is 0.40; identity matrix is identity; `monochrome` gives r == g == b; +shadows red leaves white; `preserveLuminosity` keeps luma within 1e-5. Mutations: weights by channel → `redWeightIsForty`; preserve skipped → `preserveKeepsLuma`; zone edges swapped → `whiteUnmovedByShadows`.
- TP-5 `ColorMapTests`: black-to-white map is luma; posterize 2 gives 0 and 1 only; threshold 0.5 splits at luma 0.5; `inverted()` twice `==`. `ColorLUTTests`: identity within 1e-5; warm look exact at 8 lattice points, within 1e-6 at 8 midpoints; damaged files throw (size 1, 66, short table, NaN, DOMAIN 0…2); 500 seeded mutated files throw or parse. Mutations: `floor` → `posterizeTwoLevels`; red not luma → `thresholdOnLuma`; blue-fastest → `redFastest`; domain skipped → `refusesOtherDomain`; nearest → `midpointsTrilinear`.
- TP-6 `AutoToneTests`: cast photo's suggestion neutralises the grey patch within 2/255; grey ramp suggests identity within 1e-3; all-black suggests identity, never NaN. Mutations: 1% clip → `rampIsIdentity`; empty bright set division → `blackSuggestsIdentity`.
- TP-7 `CPUColorTests`: each colour case on the CPU `==` its CoreRaster call; dispatcher over a fake with `.adjust` sends `.vibrance` to the CPU and `.contrast` to the fake. Mutations: threshold → posterized → `everyCaseEqualsDirect`; LUT twice → `lutOnce`.
- TP-8 `CPUGoldenTests` zero delta on every colour golden.
- TP-9 `ToneWalkTests.walk` (KJ-TP); `ToneBudgetTests`: each op on 24 MP ≤ 120 ms, LUT 33³ ≤ 180 ms (reported).

## Quality bars
| row | budget | test |
|---|---|---|
| Slider drag on a preview | each op ≤ 120 ms on 24 MP; 2 MP ≤ 12 ms | `ToneBudgetTests` (reported) |
| Identity at neutral | every op `==` identity at neutral | `ColorAdjustTests`, `ColorMixTests`, `ColorMapTests` |
| One Hue/Sat | one formula, in CoreRaster | jscpd; creative-apps W3 deletes Photo's |
| Never crashes | `.cube` fuzz; NaN parameters throw `RasterError.invalid` | `ColorLUTTests.fuzz`, every suite's NaN case |

## Slices
| slice | tasks | waits on | state | Slice-Done run | Mac-Finish |
|---|---|---|---|---|---|
| TP-a | TP-0, TP-1, TP-2 | engine-contracts:EC-a (merged on base) | open | | |
| TP-mix | TP-3, TP-4 | TP-a | open | | |
| TP-map | TP-5, TP-6 | TP-a | open | | |
| TP-cpu | TP-7, TP-8 | TP-mix, TP-map; engine-contracts:EC-b (merged on base) | open | | |
| TP-z | TP-9, TP-10 | TP-cpu | open | | wanted (budgets) |

## Rounds
| slice | round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|---|

## Decisions
- engine-contracts is satisfied on the base: the `ToneAdjustment` colour cases, `family`, the value types, `CPUBackend+Color.swift` and `Samples+Color.swift` are in code at a8a08d25.
- Added TP-0 (rule 18): the contract slice's ops don't exist yet, so TP-1's suites couldn't compile; TP-0 declares them as stubs, TP-3..6 fill the bodies.
- TP-2's `.cube` fixtures are generated as text in `ToneFixtures.swift`, not files under `Fixtures/luts/`: a 33³ table is ~36,000 lines (over the 400-line cap) and test resources would need a `Package.swift` edit (protected).
- `Tone/` is already owned by `image-ops`; no C4 edit.
- Combined wave plan: see affine-composite's RECORD (W1 TP-0, TP-2 · W2 TP-1 · W3 TP-3..6 · W5 TP-7 · W6 TP-8 · W7 TP-9 · W8 TP-10).

## Open
- TP-3: the packet names Photo's `HueSaturation.swift` in creative-apps as the formula, but that repo is outside this session's scope. Unless the formula is written down in creative-core, TP-3 implements the standard HSL hue rotation / saturation / lightness and records the gap on #432 for the W3 adoption to check pixel equality.
