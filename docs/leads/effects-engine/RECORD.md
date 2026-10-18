# effects-engine lead record

Issue: #433 · Packet: docs/blueprints/core/features/effects-engine.md
Run: act-1a150bfbcf7-sfwy · Session: cse_01NZM1f4cdnQ6PPn761pxTEp · Started: 2026-10-18T20:45Z
Stage: 3 wave 2
Base: 15e96dd47c720025f5ae49b3649608deb65ab216
Next: wave 2 builder running (FX-1 checks-first suites); then wave 3 once it merges

Line lead for #434, #433 and #432 (rule 19); one wave plan across the three
features, bookkeeping per feature. Packet v3 (has a Slices table).

## Tasks
| id | wave | slice | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|---|
| FX-0 | 1 | FX-a | Stubs for the contract slice's signatures (rule 18): `applying(_: LayerEffect)`, `boxBlurred`, `motionBlurred`, `denoised`, `clarity`, `DistanceField`, `stroked`, `glowing`, `shadowed`; each throws `RasterError.invalid("not built")` | `Sources/CoreRaster/Effects/{Effects,BlurFamily,DenoiseClarity,DistanceField,AlphaEffects,AlphaEffects+Light}.swift`, `Tests/CoreRasterTests/EffectStubTests.swift` | `EffectStubTests` | none (no invariant) | #565 | merged |
| FX-2 | 1 | FX-a | Reference images (disc, 1 px line, noisy flat patch with an edge, glyph mask) and analytic expectations | `Tests/CoreRasterTests/EffectFixtures.swift` | fixtures build | none | #570 | merged |
| FX-1 | 2 | FX-a | Checks first: five suites disabled by name | `Tests/CoreRasterTests/{BlurFamily,DenoiseClarity,AlphaEffect,DistanceField}Tests.swift`, `Tests/CoreRenderTests/CPUEffectTests.swift` | suites compile, disabled | none | | building |
| FX-3 | 3 | FX-blur | `boxBlurred`, `motionBlurred`; turns on `BlurFamilyTests` | `Sources/CoreRaster/Effects/BlurFamily.swift`, its tests, `Tests/mutations/CoreRaster.BlurFamily.json` | `BlurFamilyTests` | 3 (packet) | | planned |
| FX-4 | 3 | FX-blur | `denoised`, `clarity`; turns on `DenoiseClarityTests` | `Sources/CoreRaster/Effects/DenoiseClarity.swift`, its tests, `Tests/mutations/CoreRaster.DenoiseClarity.json` | `DenoiseClarityTests` | 2 (packet) | | planned |
| FX-5 | 3 | FX-alpha | `DistanceField`, `stroked`; turns on `DistanceFieldTests` and stroke cases | `Sources/CoreRaster/Effects/DistanceField.swift`, `Sources/CoreRaster/Effects/AlphaEffects.swift`, both tests, `Tests/mutations/CoreRaster.DistanceField.json` | `DistanceFieldTests`, `AlphaEffectTests` | 3 (packet) | | planned |
| FX-6 | 4 | FX-alpha | `glowing`, `shadowed`; their cases | `Sources/CoreRaster/Effects/AlphaEffects+Light.swift`, `Tests/CoreRasterTests/AlphaEffectLightTests.swift`, `Tests/mutations/CoreRaster.AlphaEffects.json` | `AlphaEffectLightTests` | 2 (packet) | | planned |
| FX-7 | 5 | FX-cpu | `applying(_:)` over every case; the CPU body; turns on `CPUEffectTests` | `Sources/CoreRaster/Effects/Effects.swift`, `Sources/CoreRender/CPU/CPUBackend+Effect.swift`, `Tests/CoreRenderTests/CPUEffectTests.swift`, `Tests/mutations/CoreRenderCPUEffect.json` | `CPUEffectTests` | 2 (packet) | | planned |
| FX-8 | 6 | FX-cpu | `Samples+Effect.swift` and CPU goldens | `Sources/CoreRender/Parity/Samples+Effect.swift`, `Tests/CoreRenderTests/Golden/effect/` | `CPUGoldenTests` | none: goldens | | planned |
| FX-9 | 7 | FX-z | KJ-FX walk; `EffectBudgetTests` (release, `.serialized`, reported) | `Tests/CoreRenderTests/EffectWalkTests.swift`, `Tests/CoreRasterTests/EffectBudgetTests.swift` | `EffectWalkTests.walk` | none | | planned |
| FX-10 | 8 | FX-z | Packet status line says built; `feature-done` | `docs/blueprints/core/features/effects-engine.md` | – | none | | planned |

## Acceptance (from the packet)
- FX-3 `BlurFamilyTests`: radius 0 and distance 0 `==` identity; disc box blur keeps total premultiplied alpha within 1e-4; 1 px vertical line under horizontal motion blur 9 spreads over 10 columns and no rows; transparent neighbour never tints an edge; radius 2,000 throws. Mutations: sample count `distance` → `motionSpreadsTen`; unpremultiplied sum → `noBleedFromTransparent`; radians as degrees → `horizontalSpreadsColumns`.
- FX-4 `DenoiseClarityTests`: noise std on the flat patch drops ≥ 60% at strength 1, the edge's 10–90% rise within 1 px; clarity 50 raises a mid-grey texture's std, keeps its mean within 1/255; zero is identity. Mutations: range sigma ignored → `edgeKept`; mid-tone weight dropped → `highlightsUnclipped`.
- FX-5 `DistanceFieldTests`: single-pixel field equals Euclidean distance exactly on 64 × 64; `AlphaEffectTests`: 4 px outside stroke of a disc covers r…r+4 (area within 1%), inside r−4…r, centre r−2…r+2. Mutations: one pass → `exactEuclidean`; `>=` for `>` → `levelIsInclusive`; outside/inside swapped → `outsideStrokeIsOutside`.
- FX-6 `AlphaEffectLightTests`: drop shadow centroid moves by (dx, dy); inner shadow never paints outside alpha; outer glow never paints inside the opaque shape; intensity 0 identity. Mutations: dy sign → `shadowMovesDown`; inner not clipped → `innerStaysInside`.
- FX-7 `CPUEffectTests`: every `LayerEffect` case on the CPU `==` `applying(_:)`; dispatcher over a fake without `effect` sends all to the CPU. Mutations: inner glow as outer → `everyCaseEqualsDirect`; stroke drops position → `strokeKeepsPosition`.
- FX-8 `CPUGoldenTests` zero delta on every effect golden.
- FX-9 `EffectWalkTests.walk` (KJ-FX); `EffectBudgetTests`: shadow + stroke + glow on 2,000 × 2,000 ≤ 150 ms; denoise 24 MP ≤ 1.5 s (reported).

## Quality bars
| row | budget | test |
|---|---|---|
| Layer style on a 4 MP layer | shadow + stroke + glow ≤ 150 ms | `EffectBudgetTests.styleStack` (reported) |
| Denoise a photo | 24 MP ≤ 1.5 s | `EffectBudgetTests.denoisePhoto` (reported) |
| Identity at zero | every effect at zero `==` identity | each suite's zero case |
| Never crashes | NaN, infinite, over-cap throw; 200 seeded parameter sets per effect | each suite's fuzz case |

## Slices
| slice | tasks | waits on | state | Slice-Done run | Mac-Finish |
|---|---|---|---|---|---|
| FX-a | FX-0, FX-1, FX-2 | engine-contracts:EC-a (merged on base) | open | | |
| FX-blur | FX-3, FX-4 | FX-a | open | | |
| FX-alpha | FX-5, FX-6 | FX-a | open | | |
| FX-cpu | FX-7, FX-8 | FX-blur, FX-alpha; engine-contracts:EC-b (merged on base) | open | | |
| FX-z | FX-9, FX-10 | FX-cpu | open | | wanted (budgets) |

## Rounds
| slice | round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|---|

## Decisions
- engine-contracts is satisfied on the base: `LayerEffect`, `StrokePosition`, the `effect` family, `CPUBackend+Effect.swift` and `Samples+Effect.swift` are in code at a8a08d25.
- Added FX-0 (rule 18): the contract slice's signatures don't exist yet, so FX-1's suites couldn't compile; FX-0 declares them as stubs in the files the packet assigns, and FX-3..7 fill the bodies without changing signatures.
- FX-1 waits on FX-0 and FX-2, so it is wave 2.
- `Effects/` is already owned by `image-ops`; no C4 edit.
- Combined wave plan: see affine-composite's RECORD (W1 FX-0, FX-2 · W2 FX-1 · W3 FX-3, FX-4, FX-5 · W4 FX-6 · W5 FX-7 · W6 FX-8 · W7 FX-9 · W8 FX-10).

## Open
- none
