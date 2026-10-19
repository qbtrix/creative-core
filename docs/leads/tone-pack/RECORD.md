# tone-pack lead record

Issue: #432 · Packet: docs/blueprints/core/features/tone-pack.md
Run: act-1a1543c8a5f-6y14 (relaunch; first run act-1a150bfbcf7-sfwy) · Started: 2026-10-18T20:45Z · Relaunched: 2026-10-19T13:05Z
Stage: 4 round 5 fixes re-dispatched after relaunch (first run's wf_206056b3-8d3 died: r5-b1 left a commit on lead/tone-pack-r5-b1 with no PR, r5-b2 and r5-b3 pushed nothing)
Base: 0b5a641be359e283625fa5c798b8d02872fad344
Next: r5 fixes merge; round 6 for TP-cpu, TP-z only (TP-a, TP-mix, TP-map at round cap); then TP-10 (feature-done), Belt-Slice-Done TP-z, Mac-Finish-Wanted TP-z

Line lead for #434, #433 and #432 (rule 19); one wave plan across the three
features, bookkeeping per feature. Packet v3 (has a Slices table).

## Tasks
| id | wave | slice | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|---|
| TP-0 | 1 | TP-a | Stubs for the contract slice's signatures (rule 18): the 13 ops, `CubeLUT.parse`, `AutoTone`; throwing ones throw `RasterError.invalid("not built")`, `inverted()` returns self | `Sources/CoreRaster/Tone/{ColorAdjust,ColorMix,ColorMap,CubeLUT,AutoTone}.swift`, `Tests/CoreRasterTests/ToneStubTests.swift` | `ToneStubTests` | none (no invariant) | #561 | merged |
| TP-2 | 1 | TP-a | Reference colours, `.cube` fixtures (identity 17³, warm 33³, five damaged) generated as text in code, the cast photo | `Tests/CoreRasterTests/ToneFixtures.swift` | every fixture parses or fails as labelled (checked in TP-5) | none | #569 | merged |
| TP-1 | 2 | TP-a | Checks first: six suites disabled by name | `Tests/CoreRasterTests/{ColorAdjust,ColorMix,ColorMap,ColorLUT,AutoTone}Tests.swift`, `Tests/CoreRenderTests/CPUColorTests.swift` | suites compile, disabled | none | #576, #581 | merged |
| TP-3 | 3 | TP-mix | `vibrance`, `hueSaturation`, `hsl`; turns on `ColorAdjustTests` | `Sources/CoreRaster/Tone/ColorAdjust.swift`, its tests, `Tests/mutations/CoreRaster.ColorAdjust.json` | `ColorAdjustTests` | 3 (packet) | #578 | merged |
| TP-4 | 3 | TP-mix | `blackAndWhite`, `channelMixer`, `colorBalance`; turns on `ColorMixTests` | `Sources/CoreRaster/Tone/ColorMix.swift`, its tests, `Tests/mutations/CoreRaster.ColorMix.json` | `ColorMixTests` | 3 (packet) | #582 | merged |
| TP-5 | 3 | TP-map | `gradientMap`, LUT apply, `CubeLUT.parse` + fuzz, `posterized`, `thresholded`, `inverted`; turns on `ColorMapTests`, `ColorLUTTests` | `Sources/CoreRaster/Tone/ColorMap.swift`, `Sources/CoreRaster/Tone/CubeLUT.swift`, both tests, `Tests/mutations/CoreRaster.ColorMap.json`, `Tests/mutations/CoreRaster.CubeLUT.json` | `ColorMapTests`, `ColorLUTTests` | 5 (packet) | #585 | merged |
| TP-6 | 3 | TP-map | `AutoTone.suggest`; turns on `AutoToneTests` | `Sources/CoreRaster/Tone/AutoTone.swift`, its tests, `Tests/mutations/CoreRaster.AutoTone.json` | `AutoToneTests` | 2 (packet) | #600 | merged |
| TP-7 | 5 | TP-cpu | `CPUBackend+Color.swift` body; turns on `CPUColorTests` | `Sources/CoreRender/CPU/CPUBackend+Color.swift`, `Tests/CoreRenderTests/CPUColorTests.swift`, `Tests/mutations/CoreRenderCPUColor.json` | `CPUColorTests` | 2 (packet) | #609 | merged |
| TP-8 | 6 | TP-cpu | `Samples+Color.swift` and CPU goldens | `Sources/CoreRender/Parity/Samples+Color.swift`, `Tests/CoreRenderTests/Golden/color/` | `CPUGoldenTests` | none: goldens | #638 | merged (52b0fdc) |
| TP-9 | 7 | TP-z | KJ-TP walk; `ToneBudgetTests` (release, `.serialized`, reported) | `Tests/CoreRenderTests/ToneWalkTests.swift`, `Tests/CoreRasterTests/ToneBudgetTests.swift` | `ToneWalkTests.walk` | none | #698 (7f81db8) | merged |
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
| TP-a | TP-0, TP-1, TP-2 | engine-contracts:EC-a (merged on base) | merged-done | https://github.com/qbtrix/creative-core/actions/runs/39180267199 | |
| TP-mix | TP-3, TP-4 | TP-a | merged-done | https://github.com/qbtrix/creative-core/actions/runs/39180267199 | |
| TP-map | TP-5, TP-6 | TP-a | merged-done | https://github.com/qbtrix/creative-core/actions/runs/39188534008 | |
| TP-cpu | TP-7, TP-8 | TP-mix, TP-map; engine-contracts:EC-b (merged on base) | merged-done | https://github.com/qbtrix/creative-core/actions/runs/39208393584 | |
| TP-z | TP-9, TP-10 | TP-cpu | open | | wanted (budgets) |

## Rounds
| slice | round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|---|
| TP-a, TP-mix | 1 | 5ea5ae5 | PASS (try 5, budget retries under load) | 70/70 | - | clarity, contract, tests, robustness | 11 (7 major: HSLShift hue unit; hueSaturation parity claim; preserveLuminosity clamp breaks luma; hsl, vibrance, colorBalance, channelMixer, blackAndWhite mutants escape; 4 minor), 0 refuted | #596 (r1-b1, merged; 8/8), #597 (r1-b2, merged; 10/10) | no |
| TP-map | 2 | 7d8af79 | PASS | 66/66 | - | clarity, contract, tests, robustness | 10 (3 major: AutoTone public docs; AutoTone levels untested; gradientMap untested; 7 minor), 0 refuted | b1 #617 merged (28b5528), b2 #628 merged (9385de9), b4 #630 merged (9cd326b), b3 #632 merged (60faf3a); round 2 fixes all merged | no |
| TP-mix, TP-map | 3 | 77b74a1 | PASS | 133/133 | - | clarity, contract, tests, robustness | 9 (4 major: WB bright set must use non-clipped pixels; clip guard untested; brightShare untested; 5 minor), 0 refuted; excluded: TP-8 not built (stale, merged after 77b74a1), JPEG SOF2 unbounded alloc (image-codecs, out of feature) | r3-b1 #643 merged (33e9202), r3-b2 #642 merged (48cbaf9) | no |
| TP-mix, TP-map, TP-cpu | 4 | d902951 | PASS | 148/148 | - | clarity, contract, tests, robustness | 8 (1 major: TP-9 unbuilt; 7 minor), 0 refuted | r4-b2 #670 merged (f4cf85d), r4-b3 #675 merged (25915ce); r4-b1 #678 merged (3197e99), r4-b4 #698 merged (7f81db8) | no |
| TP-mix, TP-map, TP-cpu, TP-z | 5 | 7f81db8 | PASS | 40/40 (tone plans) | - | clarity, contract, tests, robustness | 9 (1 major: colour ops miss release budgets 4-70x and ToneBudgetTests disabled in every optimized build; 8 minor: ToneAdjustment doc names wrong file, invert space unstated, gradientMap stop error lacks index, W1 tone value inits undocumented, walk auto tone skips dispatcher, AutoTone gamma/minimumSpan/white-balance pass-two untested), 4 refuted | r5-b1, r5-b2, r5-b3 running (wf_206056b3-8d3) | no |

## Decisions
- TP-5 (#585): map ops on encoded values via `mappingStraight`; `inverted` is a − c on linear premultiplied (exact double inversion); `.cube` parse per packet, size 2...65, domain exactly 0…1; blue-fastest mutant moved to the apply stride (parser keeps file order); ColorMix helpers made internal for reuse.
- TP-4 (#582): B&W gray = min + (max − min) × w, w blending the two neighbouring hue-range weights by hue, on encoded values (red 0.40, blue 0.20, greys stay grey); colour balance: shift 100 at full zone weight moves a channel halfway to 1 or 0 (packet gives no strength; Anatomy TP-mix critics to check); channel mixer on linear values. Made ColorAdjust mappingStraight and Adjustments smoothstep internal for reuse.
- TP-3 (#578) packet calls: vibrance's 1 − s weight uses linear saturation (display saturation failed lowSaturationMovesMost); skin range 15°–50° on display hue; hsl range hue 100 = 30°; grey pixels pass hsl untouched; hueSaturation hue −180...180 throws outside, other sliders −100...100; HSLShift clamps. Standard HSL math; Photo pixel-equality check stays with the adoption.
- TP-1 split at the 400-line cap: A (#576, ColorAdjust + ColorMix + ToneCheck helpers, 254 lines), B (ColorMap, ColorLUT, AutoTone, CPUColor, 296 lines) opens after A merges.
- engine-contracts is satisfied on the base: the `ToneAdjustment` colour cases, `family`, the value types, `CPUBackend+Color.swift` and `Samples+Color.swift` are in code at a8a08d25.
- Added TP-0 (rule 18): the contract slice's ops don't exist yet, so TP-1's suites couldn't compile; TP-0 declares them as stubs, TP-3..6 fill the bodies.
- TP-2's `.cube` fixtures are generated as text in `ToneFixtures.swift`, not files under `Fixtures/luts/`: a 33³ table is ~36,000 lines (over the 400-line cap) and test resources would need a `Package.swift` edit (protected).
- `Tone/` is already owned by `image-ops`; no C4 edit.
- Relaunch (2026-10-19T13:05Z, run act-1a1543c8a5f-6y14): this run leads #432 only; lead/tone-pack rebased onto dev 0b5a641. r5-b3 speeds the colour ops without changing a pixel (unsafe loops, rows in parallel), so the goldens and 1e-6 pins hold; the release budget runs come back on as reported rows (packet: time budgets reported, Mac finisher records them).
- Combined wave plan: see affine-composite's RECORD (W1 TP-0, TP-2 · W2 TP-1 · W3 TP-3..6 · W5 TP-7 · W6 TP-8 · W7 TP-9 · W8 TP-10).

## Open
- TP-3: the packet names Photo's `HueSaturation.swift` in creative-apps as the formula, but that repo is outside this session's scope. Unless the formula is written down in creative-core, TP-3 implements the standard HSL hue rotation / saturation / lightness and records the gap on #432 for the W3 adoption to check pixel equality.
