# affine-composite lead record

Issue: #434 · Packet: docs/blueprints/core/features/affine-composite.md
Run: act-1a150bfbcf7-sfwy · Session: cse_01NZM1f4cdnQ6PPn761pxTEp · Started: 2026-10-18T20:45Z
Stage: 3 wave 3
Base: 4feaaf9fac3cc050901f8b459a0908515a927f54
Next: AC-3 building; AC-4 after it (3 builders max across the line); then W4 AC-5

Line lead for #434, #433 and #432 (rule 19); one wave plan across the three
features, bookkeeping per feature. Packet v3 (has a Slices table).

## Tasks
| id | wave | slice | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|---|
| AC-0 | 1 | AC-a | Stubs for the contract slice's signatures (rule 18): `transformed`, `flipped`, `padded`, `composite(through:)`, `AffineMatrix.bounds`; throwing ones throw `RasterError.invalid("not built")`, `flipped` returns self | `Sources/CoreRaster/Affine/AffineTransform.swift`, `Sources/CoreRaster/Affine/CanvasSize.swift`, `Sources/CoreRaster/Compositing/CompositeAffine.swift`, `Tests/CoreRasterTests/AffineStubTests.swift` | `AffineStubTests` | none (no invariant) | #563 | merged |
| AC-2 | 1 | AC-a | Seeded layers (transparent borders, hard edges) and matrices (identity, translations, 90° multiples, skews, near-singular) | `Tests/CoreRasterTests/AffineFixtures.swift` | fixtures build | none | #571 | merged |
| AC-1 | 2 | AC-a | Checks first: `AffineOpsTests`, `CompositeAffineTests`, `CPUAffineTests` disabled by name (`waits on AC-3/5/6`) | the three test files | suites compile, disabled | none | #574 | merged |
| AC-3 | 3 | AC-geo | `transformed` with fast paths, `flipped`; turns on those cases | `Sources/CoreRaster/Affine/AffineTransform.swift`, `Tests/CoreRasterTests/AffineOpsTests.swift`, `Tests/mutations/CoreRaster.AffineTransform.json` | `AffineOpsTests` | 4 (packet) | #583 | open |
| AC-4 | 3 | AC-geo | `padded` around nine anchors; its cases in `CanvasSizeTests` | `Sources/CoreRaster/Affine/CanvasSize.swift`, `Tests/CoreRasterTests/CanvasSizeTests.swift`, `Tests/mutations/CoreRaster.CanvasSize.json` | `CanvasSizeTests` | 2 (packet) | | building |
| AC-5 | 4 | AC-comp | `composite(through:)`, `AffineMatrix.bounds`; turns on `CompositeAffineTests` | `Sources/CoreRaster/Compositing/CompositeAffine.swift`, `Tests/CoreRasterTests/CompositeAffineTests.swift`, `Tests/mutations/CoreRaster.CompositeAffine.json` | `CompositeAffineTests` | 2 (packet) | | planned |
| AC-6 | 5 | AC-comp | CPU bodies for the three `affine` calls; turns on `CPUAffineTests` | `Sources/CoreRender/CPU/CPUBackend+Affine.swift`, `Tests/CoreRenderTests/CPUAffineTests.swift`, `Tests/mutations/CoreRenderCPUAffine.json` | `CPUAffineTests` | 2 (packet) | | planned |
| AC-7 | 6 | AC-z | `Samples+Affine.swift` and CPU goldens | `Sources/CoreRender/Parity/Samples+Affine.swift`, `Tests/CoreRenderTests/Golden/affine/` | `CPUGoldenTests` | none: goldens | | planned |
| AC-8 | 7 | AC-z | KJ-AC walk; `AffineBudgetTests` (release, `.serialized`, reported) | `Tests/CoreRenderTests/AffineWalkTests.swift`, `Tests/CoreRasterTests/AffineBudgetTests.swift` | `AffineWalkTests.walk` | none | | planned |
| AC-9 | 8 | AC-z | Packet status line says built; `feature-done` | `docs/blueprints/core/features/affine-composite.md` | – | none | | planned |

## Acceptance (from the packet)
- AC-3 `AffineOpsTests`: identity and a (7, −3) translation are `==` copies; 90° about the centre equals `rotated(.degrees90)`; 2× scale of a checkerboard keeps edges within 0.5 px; outside exactly 0; singular throws; `flipped` twice `==`, once mirrors (0, 0) to (w − 1, 0). Mutations: centre sampling → `ninetyEqualsRotated`; forward map → `scaleKeepsEdges`; translation off by one → `translationIsExact`; vertical flip reverses columns → `flipMirrorsRows`.
- AC-4 `CanvasSizeTests`: 100 × 50 → 200 × 100 at nine anchors; shrink crops by the same rule; size 0 throws. Mutations: centre rounds up → `centreRoundsDown`; right uses `oldW − newW` → `rightAnchorKeepsRightEdge`.
- AC-5 `CompositeAffineTests`: 50 seeded layers and matrices × every `BlendMode` equal transform-then-composite within 1/255 (`==` for whole-pixel translations); rows outside bounds untouched; off-backdrop changes nothing. Mutations: bounds from two corners → `rotatedBoundsCoverCorners`; opacity twice → `equalsTransformThenComposite`.
- AC-6 `CPUAffineTests`: each call `==` the direct op; dispatcher over a fake without `affine` routes all three to the CPU. Mutations: width/height swapped → `equalsDirect`; flip axis inverted → `flipAxisKept`.
- AC-7 `CPUGoldenTests` zero delta on every affine golden.
- AC-8 `AffineWalkTests.walk` (KJ-AC); `AffineBudgetTests`: 12 MP rotate-scale onto 12 MP ≤ 140 ms bilinear, ≤ 260 ms Lanczos-3 (reported).

## Quality bars
| row | budget | test |
|---|---|---|
| Live transform drag | 2 MP through-composite ≤ 12 ms | `AffineBudgetTests.previewDrag` (reported) |
| Commit a transform | 12 MP rotate-scale ≤ 140 ms bilinear | `AffineBudgetTests.commit12MP` |
| Exact where it can be | identity and whole-pixel translations `==` | `AffineOpsTests` |
| Never crashes | NaN/infinite matrices, sizes past the cap throw | `AffineOpsTests.fuzz` |

## Slices
| slice | tasks | waits on | state | Slice-Done run | Mac-Finish |
|---|---|---|---|---|---|
| AC-a | AC-0, AC-1, AC-2 | engine-contracts:EC-a (merged on base) | open | | |
| AC-geo | AC-3, AC-4 | AC-a | open | | |
| AC-comp | AC-5, AC-6 | AC-geo; engine-contracts:EC-b (merged on base) | open | | |
| AC-z | AC-7, AC-8, AC-9 | AC-comp | open | | wanted (budgets) |

## Rounds
| slice | round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|---|

## Decisions
- AC-3 (head 352eb29): no scale-only resampled fast path (resized edge-extends, which would break outside-is-transparent); downscale widens the kernel per axis for any shrink below 1 by the source step, capped at source size, so pure rotation is not blurred. Fast paths: identity, whole-pixel translation, quarter turns and mirrors. AC-3 removed its rows from AffineStubTests.
- engine-contracts is satisfied on the base: `AffineMatrix`, `FlipAxis`, `CanvasAnchor`, the `affine` family, `CPUBackend+Affine.swift` and `Samples+Affine.swift` are in code at a8a08d25.
- Added AC-0 (rule 18): the packet's contract slice names signatures that don't exist yet, so the checks-first suites couldn't compile; AC-0 declares them as stubs and AC-3/4/5 fill the bodies without changing signatures.
- AC-1 waits on AC-0 and AC-2 (its suites call the stubs and the fixtures), so it is wave 2.
- `Affine/` and `Compositing/` are already owned by `image-ops` and `compositing` in docs/c4/parts, so new files need no C4 edit.
- Combined wave plan (line lead): W1 AC-0, AC-2, FX-0, FX-2, TP-0, TP-2 · W2 AC-1, FX-1, TP-1 · W3 AC-3, AC-4, FX-3, FX-4, FX-5, TP-3, TP-4, TP-5, TP-6 · W4 AC-5, FX-6 · W5 AC-6, FX-7, TP-7 · W6 AC-7, FX-8, TP-8 · W7 AC-8, FX-9, TP-9 · W8 AC-9, FX-10, TP-10.

## Open
- AC-5 must add the composite bad-input test (throws, backdrop unchanged); AC-1 (#574) dropped it to fit the 400-line cap.
- none
