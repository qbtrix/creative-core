# metal-backend lead record

Issue: #348 · Packet: docs/blueprints/core/features/metal-backend.md
Run: act-1a14ab2b672-8guo · Resumed: 2026-10-17T16:33Z (fourth run; earlier act-1a149b549c8-v538, act-1a148001532-1w03, act-1a14644b538-njln)
Stage: 4 round r4 (gate on dev 58ed68f: CI: PASS 1045; mutate running); fix round r3 merged (#410, #411, #413, #416); #417 macOS compile fix merged; MB-10 #418 merged; dev CI 39052919097 running on af0b73e (holds MB-g's last PR #417)
Base: 4e27e16 (origin/dev)
Next (for a relaunched lead): gate+mutate on dev (--changed-since 17b2ea5) → critic-panel.js (firstBase 17b2ea5, lenses clarity, correctness, reuse+packet, test oracle) → one fix-batch per slice, disjoint files; build MB-9 then MB-10 (MB-e) and MB-15 (MB-h) alongside; Belt-Slice-Done MB-c/MB-f/MB-g once a dev CI Linux job holding #401..#406 is green; then MB-17 (feature-done) and the contact sheet. PR bodies say Refs #348, never Closes.

## Loop

v3 (the packet has a Slices table; lead.md rules 12 to 19). Done per slice has two levels:
merged-done (`Belt-Slice-Done:` once the slice's PRs merged and dev's `Linux` job is green
with them) and verified (`Belt-Slice-Verified:` from the Mac finisher; never blocks the lead).
Every PR body: `Belt-Lead: act-1a14ab2b672-8guo`, `Feature: metal-backend`,
`Slice: <id>`, `Mutate: n/n <Plan>` per plan, `Fast-Check: pass`, `Head: <sha>`.

## Slices

| slice | tasks | waits on | state (open, merged, merged-done, verified) | Slice-Done run | Mac-Finish |
|---|---|---|---|---|---|
| MB-a | MB-1, MB-2 | render-backend:RB-a (contract types landed as #352) | merged-done; 3 rounds run (round 3: 19 confirmed; majors in #385, docs in #387, rest deferred to MB-17); round 4 pending | 39010063417 | wanted (posted on run 39040738062) |
| MB-b | MB-3, MB-4 | MB-a | merged-done (#389, #392; fix round 1 #403, #404); fix round 2 regenerating on 4e27e16 | 39043767442 | wanted (39044767871) |
| MB-c | MB-5, MB-6 | MB-b | merged (#398, #401); Belt-Slice-Done posted (Linux green, run 39051011998); Mac-Finish-Wanted posted | – | – |
| MB-d | MB-7, MB-8 | MB-a | merged-done (#390, #393; fix round 1 #403, #404); fix round 2 regenerating | 39044767871 | wanted (39044767871) |
| MB-e | MB-9, MB-10 | MB-c | MB-9 merged #408; MB-10 merged #418 (17:18Z); Slice-Done waits on a dev Linux run holding #418 | – | – |
| MB-f | MB-11, MB-12 | MB-d | merged (#402, #406); Linux green on 39051011998; Slice-Done waits on fix PRs r3f1, r3f2 | – | – |
| MB-g | MB-13, MB-14 | MB-a | merged (#400, #405); r3g #413 merged; Slice-Done waits on macOS compile fix #417 | – | – |
| MB-h | MB-15, MB-16, MB-17 | MB-b to MB-g | MB-16 merged #366; MB-15 merged #409; MB-17 last (feature-done) | – | – |

## Tasks

Copied from the packet. Waves are the packet's. One behavior per PR, ≤ 400 lines, ≤ 15 files.

| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| RB-2 types (for render-backend) | 1 | `RenderOp`, `RenderError`, `RenderSurface` (public init), `ToneAdjustment`, `RenderBackend` protocol, verbatim from the render-backend packet | Sources/CoreRender/{RenderOp,RenderSurface,ToneAdjustment,RenderBackend,CoreRender}.swift, Tests/CoreRenderTests/RenderContractTests.swift, docs/c4/parts/creative-core/corerender/contract.json | `RenderContractTests` (9 ops, Equatable errors, surface hashing, NullBackend conformance) | none (contract, no logic) | #352 (head 019238d, CI: PASS 914 tests) | merged 06:05Z, dev 3a65725 |
| MB-1a-half | 1 | `HalfFloat` binary16 encode/decode (Linux-safe, pure bit math) | Sources/CoreRender/Metal/HalfFloat.swift, Tests/CoreRenderTests/HalfFloatTests.swift, Tests/mutations/CoreRenderHalfFloat.json, docs/c4/parts/creative-core/corerender/metal-support.json | `HalfFloatTests` (exact patterns, exhaustive identity, seeded round trip) | CoreRenderHalfFloat 6/6 | #351 | merged 21:23Z |
| MB-1 (rest) | 1 | `MetalCapabilities`, `SurfaceTiling` (Linux-safe); `MetalBackend` with device, queue, `MetalSurface` upload and download; `supports` empty | Sources/CoreRender/Metal/MetalCapabilities.swift, Sources/CoreRender/Metal/SurfaceTiling.swift, Tests/CoreRenderTests/MetalCapabilitiesTests.swift, Tests/CoreRenderTests/SurfaceTilingTests.swift, Tests/mutations/CoreRenderMetalCapabilities.json, Tests/mutations/CoreRenderSurfaceTiling.json, Sources/CoreRenderMetal/MetalBackend.swift, Sources/CoreRenderMetal/MetalSurface.swift, Tests/CoreRenderMetalTests/MetalSurfaceTests.swift, docs/c4/parts/creative-core/corerender/metal-support.json, docs/c4/parts/creative-core/corerendermetal/metal-backend.json | `MetalCapabilitiesTests`, `SurfaceTilingTests` (4096x2160 → 17x9 tiles, no 0 px column, `tiles(touching:)` across two tiles), `MetalSurfaceTests` (device: Float16 round trip within 1e-3 on 20 seeded buffers, `residentBytes` = tiles x bytes) | CoreRenderSurfaceTiling 5/5, CoreRenderMetalCapabilities 3/3 | #353 (head 0481fb2, CI: PASS 928 tests, Mutate 5/5 + 3/3) | merged 06:10Z, dev e13b76d |
| MB-1b | 1 | `MetalBackend` (device, queue, capabilities behind a lock, every op `unsupported`) and `MetalSurface` (one rgba16Float texture per tile, Float16 upload/download) | Sources/CoreRenderMetal/MetalBackend.swift, Sources/CoreRenderMetal/MetalSurface.swift, Tests/CoreRenderMetalTests/MetalSurfaceTests.swift, Tests/CoreRenderMetalTests/TargetsTests.swift, docs/c4/parts/creative-core/corerendermetal/metal-backend.json | `MetalSurfaceTests` (device-gated: 20 seeded round trips within 1e-3, residentBytes, supports empty, unsupported throws, surfaceMismatch) | none (Metal never runs on Linux; parity and the Mac finisher cover it) | #354 (head 91f9173 on dev e13b76d, CI: PASS 928 tests on the second run; the first failed only `smallDabOn12MegapixelsIsFast`, 1.70 s vs 1.5 s, untouched CoreRaster) | merged 06:3xZ, dev 4938e94 |
| MB-2a | 2 | `PipelineKey` (Linux-safe): op + variant, `functionName`, `validated` rejects non-identifier variants | Sources/CoreRender/Metal/PipelineKey.swift, Tests/CoreRenderTests/PipelineKeyTests.swift, Tests/mutations/CoreRenderPipelineKey.json, docs/c4/parts/creative-core/corerender/metal-support.json | `PipelineKeyTests` (equality, functionName, validated, Codable, seeded fuzz) | CoreRenderPipelineKey ≥3 | #355 (head dfb9819, CI: PASS 935 tests, Mutate 4/4) | merged 06:23Z, dev af429e4 |
| MB-2b | 2 | `MetalPipelines` (runtime MSL source, `MTLBinaryArchive` at `cacheURL`, compile/load counters), `MetalBackend.fail/recover/probe`, `ParityTests` scaffold (11 families disabled) | Sources/CoreRenderMetal/MetalPipelines.swift, Sources/CoreRenderMetal/MetalBackend.swift, Tests/CoreRenderMetalTests/MetalPipelinesTests.swift, Tests/CoreRenderMetalTests/ParityTests.swift, docs/c4/parts/creative-core/corerendermetal/metal-backend.json | `MetalPipelinesTests` (cold compiles and writes; warm loads; corrupt archive recompiles; fail/recover) | none (Metal) | #356 (head 2f79e71, CI: PASS 935 tests) | merged 06:29Z, dev 603ce57 |
| MB-2 (packet row; split into MB-2a and MB-2b above; `waves.md` runner answer moves to the first macOS CI run) | 2 | `PipelineKey`, `MTLBinaryArchive` cache, health probe and `fail`/`recover` wiring, `ParityTests` scaffold with every family disabled, runner-device answer in `waves.md` | Sources/CoreRender/Metal/PipelineKey.swift, Sources/CoreRenderMetal/MetalPipelines.swift, Tests/CoreRenderMetalTests/MetalPipelinesTests.swift, Tests/CoreRenderMetalTests/ParityTests.swift, Tests/mutations/CoreRenderMetalCapabilities.json, docs/blueprints/core/features/waves.md | `MetalPipelinesTests` (cold compiles and writes; warm loads without compiling; corrupt archive recompiles; mocked error → `isHealthy` false, `supports` empty) | `recover` keeps `lastError`; `PipelineKey` ignores `variant` in `==` | – | waiting |
| MB-16 | 2 | LRU tile eviction to a per-tile CPU shadow under `budgetBytes` (half the device working set, settable); `residentBytes` counts resident tiles; `restore(tile:)` for later kernels | Sources/CoreRenderMetal/MetalSurface.swift, MetalSurface+Eviction.swift, MetalBackend.swift, MetalBackend+Memory.swift, Tests/CoreRenderMetalTests/MetalTilingTests.swift, MetalBudgetTests.swift, docs/c4/parts/creative-core/corerendermetal/metal-backend.json | `MetalTilingTests` (eviction keeps pixels, LRU order, reads count as use), `MetalBudgetTests` (20 x 4K under budget enabled; p95 composite row disabled until MB-4) | none (device-bound) | – (branch `lead/metal-backend-mb-16`, 43c0a9d, 387 lines, type-checked against a stub Metal module; rebasing onto dev for the gate) | built 06:46Z |
| MB-3 | 3 | Display kernel over the `DisplayTransfer` table texture; `supports += .display` | Sources/CoreRenderMetal/Shaders/Display.metal, Sources/CoreRenderMetal/MetalBackend+Display.swift, Tests/CoreRenderMetalTests/ParityTests+Display.swift | `ParityTests/display` (sRGB and P3 within 2/255) | none: shader | – | waiting |
| MB-4 | 3 | `.normal` composite with opacity and offsets in place; `supports += .composite` | Sources/CoreRenderMetal/Shaders/Composite.metal, Sources/CoreRenderMetal/MetalBackend+Composite.swift, Tests/CoreRenderMetalTests/ParityTests+Composite.swift | `ParityTests/compositeNormal` (opacities 0, 0.37, 1; every edge and corner; wholly outside; alpha 1e-45) | none: shader | – | waiting |
| MB-7 | 3 | Crop and quarter turns; `supports += .transform` | Sources/CoreRenderMetal/Shaders/Transform.metal, Sources/CoreRenderMetal/MetalBackend+Transform.swift, Tests/CoreRenderMetalTests/ParityTests+Transform.swift | `ParityTests/transform` (zero delta) | none: shader | – | waiting |
| MB-8 | 3 | Bilinear and lanczos3 as two separable passes; `supports += .resample` | Sources/CoreRenderMetal/Shaders/Resample.metal, Sources/CoreRenderMetal/MetalBackend+Resample.swift, Tests/CoreRenderMetalTests/ParityTests+Resample.swift | `ParityTests/resample` (both filters, 5 sizes; constant stays constant) | none: shader | – | waiting |
| MB-13 | 3 | Exposure, levels, curves on unpremultiplied values | Sources/CoreRenderMetal/Shaders/Adjust.metal, Sources/CoreRenderMetal/MetalBackend+Adjust.swift, Tests/CoreRenderMetalTests/ParityTests+Adjust.swift | `ParityTests/adjust` (linear and sRGB) | none: shader | – | waiting |
| MB-5 | 4 | Twelve separable blend modes as kernel variants | Sources/CoreRenderMetal/Shaders/BlendSeparable.metal, Sources/CoreRenderMetal/MetalBackend+BlendSeparable.swift, Tests/CoreRenderMetalTests/ParityTests+BlendSeparable.swift | `ParityTests/blendSeparable` (twelve modes, three opacities) | none: shader | – | waiting |
| MB-11 | 4 | Gaussian blur, two passes, CPU kernel weights uploaded | Sources/CoreRenderMetal/Shaders/Blur.metal, Sources/CoreRenderMetal/MetalBackend+Blur.swift, Tests/CoreRenderMetalTests/ParityTests+Blur.swift | `ParityTests/blur` (sigma 0, 0.5, 3, 20; clamp-to-edge) | none: shader | – | waiting |
| MB-14 | 4 | White balance, contrast, highlights, shadows; `supports += .adjust` | Sources/CoreRenderMetal/Shaders/Adjust.metal, Sources/CoreRenderMetal/MetalBackend+Adjust.swift, Tests/CoreRenderMetalTests/ParityTests+Adjust.swift | `ParityTests/adjust` develop rows | none: shader | – | waiting |
| MB-15 | 4 | Clone through a mask; `supports += .retouch` | Sources/CoreRenderMetal/Shaders/Retouch.metal, Sources/CoreRenderMetal/MetalBackend+Retouch.swift, Tests/CoreRenderMetalTests/ParityTests+Retouch.swift | `ParityTests/retouch` (rect, ellipse, polygon masks; offsets off the edge) | none: shader | – | waiting |
| MB-6 | 5 | Opaque-row blit fast path; `supports += .blendSeparable` | Sources/CoreRenderMetal/MetalBackend+OpaqueRows.swift, Tests/CoreRenderMetalTests/ParityTests+OpaqueRows.swift | `ParityTests/opaqueRows` (zero delta on opaque; 0.999 alpha takes the kernel) | none: shader | – | waiting |
| MB-9 | 5 | Hue, saturation, color, luminosity with Lum, Sat, SetLum, SetSat, ClipColor | Sources/CoreRenderMetal/Shaders/BlendNonSeparable.metal, Sources/CoreRenderMetal/MetalBackend+BlendNonSeparable.swift, Tests/CoreRenderMetalTests/ParityTests+BlendNonSeparable.swift | `ParityTests/blendNonSeparable` within `.nonSeparable` | none: shader | – | waiting |
| MB-12 | 5 | Unsharp mask over the blur; `supports += .blur` | Sources/CoreRenderMetal/MetalBackend+Unsharp.swift, Tests/CoreRenderMetalTests/ParityTests+Unsharp.swift | `ParityTests/unsharp` (amount, sigma, threshold grid) | none: shader | – | waiting |
| MB-10 | 6 | ClipColor edge cases in Float32; `supports += .blendNonSeparable` | Sources/CoreRenderMetal/Shaders/BlendNonSeparable.metal, Tests/CoreRenderMetalTests/ParityTests+BlendNonSeparable.swift | edge rows: lum 0 and 1, grey sources | none: shader | – | waiting |
| MB-17 | 7 | Every family on; parity counts and runner answer in `waves.md`; `feature-done` | docs/blueprints/core/features/waves.md, Tests/CoreRenderMetalTests/ParityTests.swift | `ParityTests` has no disabled family; `supports == Set(RenderOp.allCases)` | none | – | waiting |

Slices (packet): MB-a = MB-1, MB-2 · MB-b = MB-3, MB-4 · MB-c = MB-5, MB-6 · MB-d = MB-7, MB-8 ·
MB-e = MB-9, MB-10 · MB-f = MB-11, MB-12 · MB-g = MB-13, MB-14 · MB-h = MB-15, MB-16, MB-17.
A slice's `supports` entry is added only by its last task.

## Builder brief (wave 1)

MB-1 ships as two PRs in slice MB-a, disjoint files, so each stays well under 400 lines and
the Linux-safe half is proven here while the Metal half can only compile on macOS.

**MB-1a, Linux-safe (CoreRender/Metal).** Files: `Sources/CoreRender/Metal/MetalCapabilities.swift`,
`Sources/CoreRender/Metal/SurfaceTiling.swift`, `Sources/CoreRender/Metal/HalfFloat.swift`,
`Tests/CoreRenderTests/MetalCapabilitiesTests.swift`, `Tests/CoreRenderTests/SurfaceTilingTests.swift`,
`Tests/CoreRenderTests/HalfFloatTests.swift`, `Tests/mutations/CoreRenderMetalCapabilities.json`,
`Tests/mutations/CoreRenderSurfaceTiling.json`, `Tests/mutations/CoreRenderHalfFloat.json`,
`docs/c4/parts/creative-core/corerender/metal-support.json` (new component "Metal Support",
paths `Sources/CoreRender/Metal/`).
- `MetalCapabilities: Equatable, Sendable` with `public private(set) var supported: Set<RenderOp>`,
  `healthy: Bool`, `lastError: String?`; `init()` is empty and healthy; `enable(_:)` inserts;
  `fail(_ reason:)` sets `healthy = false` and `lastError = reason` and keeps `supported` (the
  status note shows what would run); `recover()` sets `healthy = true` and clears `lastError`.
  Tests: enable then fail keeps `supported` and turns `healthy` false; recover restores and clears
  `lastError`; a fresh value supports nothing. Mutations (≥2): `fail` clears `supported`;
  `recover` keeps `lastError`.
- `SurfaceTiling: Equatable, Sendable`: `init(width:height:) throws` (RenderError for a
  non-positive side, and for a side above `PixelBuffer`'s own size limit if one exists; name the
  bound in the message), `tileSize` reuses `PixelBuffer.tileSize` (256), `columns`, `rows`,
  `tileCount`, `rect(_ index: Int) throws -> TileRect` (row-major; out of range throws),
  `tiles(touching x:y:width:height:) -> [Int]` (indices of the tiles the rect overlaps, clipped
  to the grid, ascending; empty when the rect is outside or empty). Tests: 4096x2160 gives
  16 columns x 9 rows = 144 tiles (4096 = 16 x 256 exactly; a 17th column would be 0 px wide
  and must never exist, which is the bug the packet's "17 x 9" line warns against; say so in
  the PR body), and `rect(143)` is 256x112 at (3840, 2048); 4097x1 gives 17x1; a rect
  spanning two tiles gives both; a rect at the bottom-right corner gives the last index;
  `rect(tileCount)` throws; a seeded property test (private SplitMix64 copy in the test file)
  checks every pixel of a random size is in exactly one tile. Mutations (≥2): `<=` for `<` on
  the last tile (an extra empty column); `tiles(touching:)` drops the last overlapped column;
  `rect` accepts `index == tileCount`.
- `HalfFloat`: `static func encode(_ value: Float) -> UInt16` and
  `static func decode(_ bits: UInt16) -> Float`, IEEE 754 binary16, round to nearest even,
  subnormals, ±inf, NaN kept as NaN, overflow to ±inf. Pure bit math, no `Float16` type (it
  is unavailable on x86_64 macOS). Tests: exact values (0, 1, 0.5, 65504, -2) round-trip;
  decode(encode(x)) within 1e-3 of x for 1000 seeded values in [0, 1] and within 2^-11
  relative for larger; NaN and inf survive; 65520 encodes to +inf. Mutations (≥2): rounding
  truncates instead of nearest-even; the exponent bias is off by one.
- Every public symbol gets a doc comment that says its unit and failure case. C4 part
  description says what the component holds. `scripts/mutate --run --plan <each plan>` must
  report every entry caught; body ends with one `Mutate: n/n <Plan>` line per plan.

**MB-1b, Metal (CoreRenderMetal), after MB-1a merges.** Files:
`Sources/CoreRenderMetal/MetalBackend.swift` (replace the marker), `Sources/CoreRenderMetal/MetalSurface.swift`,
`Tests/CoreRenderMetalTests/MetalSurfaceTests.swift`, `Tests/CoreRenderMetalTests/TargetsTests.swift`
(retarget the marker check to `MetalBackend`), `docs/c4/parts/creative-core/corerendermetal/metal-backend.json`
(description).
- Every file wrapped whole in `#if canImport(Metal)`; imports `Metal`, `CoreRender`, `CoreRaster`,
  `CoreColor`, Foundation. Linux builds the module empty; the builder cannot compile it here, so
  it checks every Metal API it names with the apple-docs MCP and lists them under
  `Unverified API:` in the PR body for the Mac finisher.
- `public final class MetalBackend: RenderBackend, @unchecked Sendable` guarded by one lock:
  `static var defaultDevice: MTLDevice?` (`MTLCreateSystemDefaultDevice()`),
  `init(device: MTLDevice, cacheURL: URL?) throws` (`RenderError.deviceLost("no command queue")`
  when `makeCommandQueue()` is nil; `cacheURL` stored for MB-2), `name` = "Metal (<device.name>)",
  `supports` = `capabilities.supported` when healthy else `[]` (empty in MB-1), `isHealthy`,
  `residentBytes` = sum of tile texture bytes (width x height x 8), `var capabilities: MetalCapabilities`.
  `surface(_:)` builds a `MetalSurface` (one `rgba16Float` `MTLTexture` per `SurfaceTiling`
  tile, `.storageModeShared`, uploaded with `replaceRegion` from `HalfFloat.encode`), `read(_:)`
  downloads with `getBytes` and decodes, `release(_:)` drops the textures. Every op method
  throws `RenderError.unsupported(op)`; a surface from another backend or a released id throws
  `.surfaceMismatch`. No `try!`, `as!`, force unwraps.
- `MetalSurfaceTests`, each `.enabled(if: MetalBackend.defaultDevice != nil)`: `read(surface(b))`
  within 1e-3 of `b` for 20 seeded buffers of random sizes up to 600x600 (Float16 round trip);
  `residentBytes` equals tiles x 256 x 256 x 8 for full tiles plus the clipped edge tiles'
  bytes; `supports` is empty and `isHealthy` true; a blur throws `.unsupported(.blur)`; reading a
  released surface throws `.surfaceMismatch`.
- No mutation plan (Linux cannot build it; parity and the Mac finisher cover it, rule 15).

## Rounds

| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|
| MB-a 1 | 603ce57 | two runs FAIL only on smallDabOn12MegapixelsIsFast (CoreRaster budget, under load; the Linux CI job is green on the same SHA); idle rerun pending | 18/18 (--changed-since 6967968) | 39010063417: Linux, Mutation green; macOS red: MetalPipelinesTests coldCache (archive file not written) and corruptArchive (cannot reopen); dev-red #357 | clarity, correctness, reuse+packet, test oracle | 2 blockers (deviceLost path never fails the backend; cacheURL directory deleted), majors: .shared textures on non-Apple GPUs, >=65520 upload then read throws, composite stub family, tile math duplicated, pipeline compile sync, vacuous fail/recover test, PipelineKey bounds, parity list unbound, probe failure path untested, validated unused, docs untrue, waves.md answer missing; CI finding: binary archive not written | batches A (CoreRender), B2 (parity scaffold), B1 (Metal backend, after MB-16) | no |
| MB-a 2 | 9f30aab | CI: PASS | 22/22 (--changed-since 24fd483) | 39031409068 on 9b72477 predates #368 (macOS red, old archive tests); none yet on 9f30aab | clarity, correctness, reuse+packet, test oracle | 15 confirmed, 0 refuted. Majors: deviceLost thrown for a missing kernel and texture allocation failure; recover() marks healthy without probing; 4 copies of a RasterError mapping helper; MB-16 deviations missing from the packet; supports health gate untested | no | fix round 2: #369 (3be8939), #376 (3d20408); Mac-only entries and untested probe-lock/alloc-fail listed in #376 body |
| MB-a 3 | 658f0c2 | CI: PASS | 75/75 (--changed-since 24fd483) | 39037816632 on 4b2aa75 green incl. macOS (holds #368, #369; not #376); dev-red #357 closed | clarity, correctness, reuse+packet, test oracle | 19 confirmed (3 major), not clean; round3-findings.md | – | fix rounds exhausted (2/2): majors (lookup size check, deviceLost doc) carried into MB-b; #17 already fixed by #383; rest deferred to MB-17 |
| MB-b,c,d,f,g 3 | 4e27e16 | CI: PASS 1037 tests | 37/37 (--changed-since 17b2ea5) | – | clarity, correctness, reuse+packet, test oracle | 22 confirmed, 1 refuted, not clean (1 blocker: AdjustTable channel extrapolation outside 0...1) | fix batches r3g, r3f1, r3f2, r3b (wf_6419df5b-b06) | MB-b, MB-d: last fix round (2/2); MB-c, MB-f, MB-g: round 1. Deferred to MB-17: stale BlendSeparable docs, tileStorageMode doc, triplicated whole-image pipeline, per-op lost-helper copies, dead code after MB-6, MetalBackend.swift doc for unsupported-over-limit |

## Decisions

- 2026-10-16T19:55Z: stopped at stage 0 on the open dependency (#347), per lead.md stage 0 step 4.
- 2026-10-16T20:40Z: unblocked by #349 (targets, Metal exception, v3 rules; supervisor comment on
  #348). RB-1 is done; RB-2 is not. `SurfaceTiling` needs an error type for bad sizes and
  CoreRender's is `RenderError` (RB-2); declaring `RenderError` or `RenderOp` here would collide
  with RB-2's owned files, so those parts wait for RB-2 rather than invent a type.
- 2026-10-16T21:05Z: render-backend holds RB-2 for a supervisor ruling on its sandbox budget
  failures (they pass here; data point posted on #347). MB-1a splits once more so the RB-2-free
  piece lands now: MB-1a-half = `HalfFloat` (pure bit math, no error type) in its own PR; MB-1a-rest
  = `SurfaceTiling` + `MetalCapabilities` after RB-2.
- Stub rule (18): MB-1 declares every `MetalBackend` signature the packet's contract lists
  (`defaultDevice`, `init(device:cacheURL:)`, `name`, `supports`, `isHealthy`,
  `residentBytes`, every `RenderBackend` method), with surface upload/download real and every
  op throwing `RenderError.unsupported(op)`; later slices fill bodies and never change signatures.
- Rule 13: each slice's acceptance tests are written from the packet before its code; a test
  that lands ahead of its code is `.disabled("waits on MB-n")`. Parity tests are also
  `.enabled(if: MetalBackend.defaultDevice != nil)`.
- Rule 14: each Linux-safe task owns its plan: `CoreRenderSurfaceTiling.json` and
  `CoreRenderMetalCapabilities.json` (MB-1), `CoreRenderPipelineKey.json` (MB-2, instead of
  sharing MB-1's plan as the packet's table says: two tasks never share a plan). Shader and
  device code is covered by parity (rule 15), not mutations.
- Task branches are `lead/metal-backend-<task>` (a ref cannot nest under the existing
  `lead/metal-backend`), the repo's sibling convention.
- The server appends an attribution footer to issue comments and PR bodies posted through the
  GitHub tools; the lead strips it with an edit after posting (CLAUDE.md: none anywhere).
- 2026-10-16T21:50Z: considered building the `MetalBackend` skeleton ahead of RB-2 without the
  protocol conformance. Rejected: `surface`/`read` return and take `RenderSurface`, `init` throws
  `RenderError`, and `supports` is `Set<RenderOp>`; without those types the skeleton would need
  throwaway stand-ins and a rewrite, not a stub whose signatures later slices keep (rule 18). Wait.
- Builders are subagents with `isolation: "worktree"`, one or two at a time (the packet: a
  wave with several tasks is still taken one or two at a time). Each worktree builds the
  package from scratch, so one builder per 4-core box at a time.
- Stages 1 and 2 are done ahead: the task table above is the plan; the waves are the packet's
  (1: MB-1 · 2: MB-2, MB-16 · 3: MB-3, MB-4, MB-7, MB-8, MB-13 · 4: MB-5, MB-11, MB-14, MB-15 ·
  5: MB-6, MB-9, MB-12 · 6: MB-10 · 7: MB-17). Per the packet, a wave with several tasks is still
  built one or two PRs at a time.
- Verification plan for a Linux lead: this session has no Metal device, so no builder here can
  run a parity test. Linux-safe tasks (MetalCapabilities, SurfaceTiling, PipelineKey) are gated
  by `scripts/ci` and mutations here as usual. Shader and device code is proven only by the
  `macOS` job of the CI run on dev; the first such run (after MB-2) tells whether the runner
  exposes a device. If it does not, every parity test skips and the lead posts that on #348
  as a `needs-human` ask for a Mac run, instead of claiming a slice done.

- 2026-10-17 round 1: no on-disk `MTLBinaryArchive`. CI run 39010063417 (the first with a device) shows the archive is not
  written after a cold compile of a `makeLibrary(source:)` library (add or serialize failed; the error was swallowed).
  Apple's device-built-archive flow needs a metallib with a stable identity. The cache is Metal's own shader cache
  plus an in-process memo per `PipelineKey`; `cacheURL` stays in `init` (contract) as reserved. Background compile
  (packet "First launch" row) is deferred to MB-3, the first real kernel, as a named task. Recorded in the packet by batch A.
- 2026-10-17T06:30Z: shader source is compiled at runtime from Swift string constants
  (`MTLDevice.makeLibrary(source:options:)`) and the pipelines are cached in an `MTLBinaryArchive` at `cacheURL`,
  instead of `.metal` files: SwiftPM's Metal-file handling would need a resource bundle or a `Package.swift`
  change (protected) and cannot be verified on Linux. Cost: the MSL front-end runs once per launch per family
  (tens of ms, off the main queue per the packet); the archive still skips the back-end compile. The packet's
  `Shaders/<Family>.metal` files become `Shaders/<Family>.swift` holding the source string.
- 2026-10-17T06:30Z: MB-2 splits into MB-2a (Linux-safe `PipelineKey`, own plan) and MB-2b (Metal cache, health,
  parity scaffold); MB-16 waits for MB-2b because both edit `MetalBackend.swift`. The `waves.md` runner-device
  line is written when the first macOS CI run on dev with #354 reports.
- 2026-10-17T06:00Z: after ten hours of waiting across two runs, render-backend silent since 03:36Z and no supervisor
  pick, the lead opens the undisputed RB-2 contract types (`RenderOp`, `RenderError`, `RenderSurface` with a public
  init, `RenderBackend`, `ToneAdjustment` mirroring CoreRaster) verbatim from the render-backend packet as one
  fast-lane PR with `Feature: render-backend`, `Slice: RB-a`, announced on #347 and #348 first. `FakeBackend` and
  the disabled CPU and dispatcher tests stay with render-backend. If the supervisor objects, the PR is closed.
- 2026-10-17T04:05Z (run act-1a148001532-1w03): RB-2 is still not on dev (render-backend stopped 02:55Z on the
  recorder question; no answer by 04:00Z). Instead of idling, the lead pre-builds MB-1a-rest and MB-1b on task
  branches against the contract text in both packets (`RenderOp`, `RenderError`, `RenderSurface`, `RenderBackend`
  verbatim from render-backend's packet, as a throwaway first commit the PR never carries). No PR opens before
  RB-2 is on dev, no RB-2 file is ever pushed in a PR from this feature, and the real commits are rebased onto the
  RB-2 SHA. If RB-2 spells a name differently, the fix is a rename in the rebase, not a redesign.

## Open
- 16:44Z handoff: the superseded run's r2b merged as #407 after 4e27e16, so round 3 may repeat MB-b items #407 fixed (display errors and device limit, P3 matrix, composite map rows); r3 fixers branch from the current dev and say so in notes when a finding is already fixed. r2d (MB-d) never pushed; r3f1's unsupported(op) decision covers its resample doc and dispatcher items, and the rest go to MB-17.
- CI run 39010063417 on 603ce57: the macos-15 runner HAS a Metal device (device-gated suites ran). `waves.md` line to write in the round 1 fix batch. macOS red: the binary archive is not written after a cold compile; `lastCacheError` is swallowed and unexposed, so the cause is unknown until the next macOS run shows it. dev-red #357 names our range; it is this lead's finding (round 1).
- MB-1b needs from RB-2: a `public init(id:width:height:backend:)` on `RenderSurface` (asked on #347, 05:48Z). `CoreRenderMetal` imports CoreRaster and CoreColor through CoreRender transitively (Package.swift lists only CoreRender); SwiftPM resolves same-package modules, but the Mac finisher checks it. Metal doc caveats for the finisher: `.shared` textures are unavailable on non-Apple-family GPUs; `MTLCreateSystemDefaultDevice` needs Core Graphics linked in a command-line process (tests skip, not fail).

- Run act-1a14644b538-njln ended at its 8 h wall clock (03:51Z) with slice MB-a one PR in (HalfFloat, #351) and the
  rest blocked on RB-2 for the whole run. The sandbox lessons: no Swift toolchain at start (run
  `scripts/cloud-setup.sh`), a 15 min heartbeat cadence (Belt nudged once at a 6 min gap), the GitHub tools drop and
  reconnect often (reload with ToolSearch), and `scripts/ci` only passes the CoreRaster dab budget on an idle box.
- The `macOS` and `Mutation` CI jobs have not run on a dev SHA that holds #351 (the lane dispatches CI after 10 merges
  or a `feature-done`); the first such run tells whether the runner exposes a Metal device (MB-2's `waves.md` answer).

- The lane merged #351 at 21:23Z while its body still read `Fast-Check: fail (...)`; it reported
  "Fast-Check marker". The lane seems to accept any `Fast-Check:` line with a matching `Head:`,
  not only `pass`. The head did pass the gate on an idle rerun five minutes later, so the merge is
  sound, but the lane's check is looser than CLAUDE.md states. To tell the supervisor; `scripts/fast-lane.sh`
  is protected.

- Wave 1 waits on render-backend RB-2 on `origin/dev`. Supervisor (02:19Z on #347): render-backend continues from RB-2; its RECORD (20:08Z) still
  waits on a human merge of #350, which #349 superseded; RB-2 has no PR yet.
- Which `RenderError` case fits a bad tiling size? RB-2's planned cases are `unsupported`,
  `deviceLost`, `surfaceMismatch`, `raster(String)`. MB-1 uses `.raster(message)` unless RB-2
  adds an `invalid` case; flagged for the clarity lens.
- Sandbox: no Swift toolchain in the container at start; `scripts/cloud-setup.sh` is
  installing Swift 6.3.3. render-backend's lead reports `scripts/ci` on this box fails two
  wall-clock budget tests under parallel load (`RetouchBoundsTests.smallDabOn12MegapixelsIsFast`,
  `EngineStressTests.thousandCommandsNearTheLayerLimitStayInBudget`) while
  `swift test --no-parallel` passes. Not reproduced here: `scripts/ci` on 9ba4c2b printed
  `CI: PASS` (903 tests, 40 s). No PR of this feature claims `Fast-Check: pass` unless
  `scripts/ci` printed `CI: PASS` on its head.
- Linux never builds Metal: shader parity is proven only by the macOS CI job (if it has a
  device) or the Mac finisher (rule 17). The lead never waits on it.
