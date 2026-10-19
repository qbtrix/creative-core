# effects-engine lead record

Issue: #433 · Packet: docs/blueprints/core/features/effects-engine.md
Run: act-1a150bfbcf7-sfwy · Session: cse_01NZM1f4cdnQ6PPn761pxTEp · Started: 2026-10-18T20:45Z
Stage: 4 round 5 panel done (5 confirmed); fixes r5-b1..b3 running (wf_a0fba459-99d). FX-alpha reaches its round cap (rounds 2-5); FX-cpu 3 rounds; FX-z 1
Base: 4feaaf9fac3cc050901f8b459a0908515a927f54
Next: round 5 panel; then FX-10 (feature-done), Belt-Slice-Done FX-z, Mac-Finish-Wanted FX-z

Line lead for #434, #433 and #432 (rule 19); one wave plan across the three
features, bookkeeping per feature. Packet v3 (has a Slices table).

## Tasks
| id | wave | slice | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|---|
| FX-0 | 1 | FX-a | Stubs for the contract slice's signatures (rule 18): `applying(_: LayerEffect)`, `boxBlurred`, `motionBlurred`, `denoised`, `clarity`, `DistanceField`, `stroked`, `glowing`, `shadowed`; each throws `RasterError.invalid("not built")` | `Sources/CoreRaster/Effects/{Effects,BlurFamily,DenoiseClarity,DistanceField,AlphaEffects,AlphaEffects+Light}.swift`, `Tests/CoreRasterTests/EffectStubTests.swift` | `EffectStubTests` | none (no invariant) | #565 | merged |
| FX-2 | 1 | FX-a | Reference images (disc, 1 px line, noisy flat patch with an edge, glyph mask) and analytic expectations | `Tests/CoreRasterTests/EffectFixtures.swift` | fixtures build | none | #570 | merged |
| FX-1 | 2 | FX-a | Checks first: five suites disabled by name | `Tests/CoreRasterTests/{BlurFamily,DenoiseClarity,AlphaEffect,DistanceField}Tests.swift`, `Tests/CoreRenderTests/CPUEffectTests.swift` | suites compile, disabled | none | #577 | merged |
| FX-3 | 3 | FX-blur | `boxBlurred`, `motionBlurred`; turns on `BlurFamilyTests` | `Sources/CoreRaster/Effects/BlurFamily.swift`, its tests, `Tests/mutations/CoreRaster.BlurFamily.json` | `BlurFamilyTests` | 3 (packet) | #579 | merged |
| FX-4 | 3 | FX-blur | `denoised`, `clarity`; turns on `DenoiseClarityTests` | `Sources/CoreRaster/Effects/DenoiseClarity.swift`, its tests, `Tests/mutations/CoreRaster.DenoiseClarity.json` | `DenoiseClarityTests` | 2 (packet) | #586 | merged |
| FX-5 | 3 | FX-alpha | `DistanceField`, `stroked`; turns on `DistanceFieldTests` and stroke cases | `Sources/CoreRaster/Effects/DistanceField.swift`, `Sources/CoreRaster/Effects/AlphaEffects.swift`, both tests, `Tests/mutations/CoreRaster.DistanceField.json` | `DistanceFieldTests`, `AlphaEffectTests` | 3 (packet) | #588 | merged |
| FX-6 | 4 | FX-alpha | `glowing`, `shadowed`; their cases | `Sources/CoreRaster/Effects/AlphaEffects+Light.swift`, `Tests/CoreRasterTests/AlphaEffectLightTests.swift`, `Tests/mutations/CoreRaster.AlphaEffects.json` | `AlphaEffectLightTests` | 2 (packet) | #605 | merged |
| FX-7 | 5 | FX-cpu | `applying(_:)` over every case; the CPU body; turns on `CPUEffectTests` | `Sources/CoreRaster/Effects/Effects.swift`, `Sources/CoreRender/CPU/CPUBackend+Effect.swift`, `Tests/CoreRenderTests/CPUEffectTests.swift`, `Tests/mutations/CoreRenderCPUEffect.json` | `CPUEffectTests` | 2 (packet) | #611 | merged (77b74a1) |
| FX-8 | 6 | FX-cpu | `Samples+Effect.swift` and CPU goldens | `Sources/CoreRender/Parity/Samples+Effect.swift`, `Tests/CoreRenderTests/Golden/effect/` | `CPUGoldenTests` | none: goldens | #640 | merged (2298d3f) |
| FX-9 | 7 | FX-z | KJ-FX walk; `EffectBudgetTests` (release, `.serialized`, reported) | `Tests/CoreRenderTests/EffectWalkTests.swift`, `Tests/CoreRasterTests/EffectBudgetTests.swift` | `EffectWalkTests.walk` | none | #699 (8613770) | merged |
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
| FX-a | FX-0, FX-1, FX-2 | engine-contracts:EC-a (merged on base) | merged-done | https://github.com/qbtrix/creative-core/actions/runs/39174242588 | |
| FX-blur | FX-3, FX-4 | FX-a | merged-done | https://github.com/qbtrix/creative-core/actions/runs/39180267199 | |
| FX-alpha | FX-5, FX-6 | FX-a | merged-done | https://github.com/qbtrix/creative-core/actions/runs/39188534008 | |
| FX-cpu | FX-7, FX-8 | FX-blur, FX-alpha; engine-contracts:EC-b (merged on base) | merged-done | https://github.com/qbtrix/creative-core/actions/runs/39208393584 | |
| FX-z | FX-9, FX-10 | FX-cpu | open | | wanted (budgets) |

## Rounds
| slice | round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|---|
| FX-a, FX-blur | 1 | 5ea5ae5 | PASS (try 5, budget retries under load) | 70/70 (BlurFamily 3/3) | - | clarity, contract, tests, robustness | 7 (2 major: motion blur not centred; box blur both-axes/three-pass untested; 5 minor), 1 refuted | #593 (r1-b1, merged; Mutate 9/9) | no |
| FX-alpha, FX-blur, FX-a | 2 | 7d8af79 | PASS | 66/66 | - | clarity, contract, tests, robustness | 16 (4 major: LayerEffect radius unit differs per case; glow/shadow no fuzz; glow intensity and reach untested; clarity/denoise can store +inf; 12 minor), 1 refuted | r2-b1 #631 merged (be6cc41); r2-b2 #629 merged (e001b84); r2-b3 #639 merged (6199d27) | no |
| FX-a, FX-blur, FX-alpha, FX-cpu | 3 | 2298d3f | PASS | 109/109 | - | clarity, contract, tests, robustness | 10 (1 major: denoise overflow guard has no test or mutation; 9 minor: error messages blame valid params, padded-size error, StrokePosition docs, packet glow/motion wording, diagonal edge offset untested, denoise working-set cap, parity applied path untested), 1 refuted | r3-b3 #652 merged (a672a6b), r3-b2 #653 merged (f67d23f), r3-b1 #655 merged (59275e0), r3-b4 #658 merged (e9fa096) | no |
| FX-a, FX-blur, FX-alpha, FX-cpu | 4 | e9fa096 | PASS | 176/176 | - | clarity, contract, tests, robustness | 8 (3 major: FX-9 unbuilt; bilateral bands past 64 lines untested; shadow-inner sample is identity; 5 minor: glow/shadow remedy, maxDenoisePixels unseen, LayerEffect inner/intensity docs, sigma-0 branch untested, paddedWorkSize no mutation), 1 refuted | #685 merged (ef57810), r4-b3 #690 merged (37e5897), #691 merged (91bc56e), r4-b4 #699 merged (8613770) | no |
| FX-alpha, FX-cpu, FX-z | 5 | 8613770 | PASS | 37/37 | - | clarity, contract, tests, robustness | 5 (1 major: stroke/glow/shadow overflow guards untested and unmutated; 4 minor: stroke padding error blames width, clarity radius cap undocumented, KJ-FX walk never calls padded(), distance-field guard gaps), 0 refuted | r5-b1, r5-b2, r5-b3 running (wf_a0fba459-99d) | no |

## Decisions
- FX-5 (#588): stroke distance measured to the sub-pixel anti-aliased edge (Gustavson & Strand 2011 edge points over the exact EDT's nearest seed + 8 neighbours); field−0.5 missed the 1% ring test by +7.2%. Shape is alpha ≥ 0.5; off-buffer is transparent; level inclusive; width 0...1000.
- FX-4 (#586): `denoised` is a separable luma-guided bilateral (x then y; full 2-D would miss FX-9's budget), chroma at 2× spatial sigma; alpha kept, colour averaged premultiplied; `clarity` unsharp against `gaussianBlur` with sigma = radius/3 and the packet's midtone weight, no clamp at 1.
- FX-3 (#579): motion blur takes ceil(d)+1 samples at step d/ceil(d) starting at the whole pixel floor(-d/2), so an axis-aligned integer distance covers exactly d+1 columns; odd d sits half a pixel off centre (d=9 covers -5...4). Blurs edge-extend; box blur is three running-sum passes; FX-3 removed its rows from EffectStubTests.
- engine-contracts is satisfied on the base: `LayerEffect`, `StrokePosition`, the `effect` family, `CPUBackend+Effect.swift` and `Samples+Effect.swift` are in code at a8a08d25.
- Added FX-0 (rule 18): the contract slice's signatures don't exist yet, so FX-1's suites couldn't compile; FX-0 declares them as stubs in the files the packet assigns, and FX-3..7 fill the bodies without changing signatures.
- FX-1 waits on FX-0 and FX-2, so it is wave 2.
- `Effects/` is already owned by `image-ops`; no C4 edit.
- Combined wave plan: see affine-composite's RECORD (W1 FX-0, FX-2 · W2 FX-1 · W3 FX-3, FX-4, FX-5 · W4 FX-6 · W5 FX-7 · W6 FX-8 · W7 FX-9 · W8 FX-10).

## Open
- FX-3 must sample motion/directional blur at whole-pixel steps: FX-1 tests expect exactly 10 occupied columns for distance 9.
- FX-5 stroke coverage must hit the ring area within 1%: shift the distance field 0.5 px or measure to the edge (pixel-centre smoothstep comes out ~13% short).
- none
