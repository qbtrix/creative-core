# Feature packet: metal-backend

**Feature:** the Metal `RenderBackend`, grown one op family at a time behind
`supports` flags, each family landing with the parity test that proves it
matches the CPU backend within the stated tolerance, so the dispatcher routes
only what Metal does right and the apps stay shippable on CPU after every
PR. Sized for one dedicated lead working slowly on its own Belt line: many
small slices, one family each.
**Line:** `line:core` (its own Belt line, one lead) · **Wave:** 4 (`waves.md`) · **Lead branch:** `lead/metal-backend`

**Covers:** the dual-renderer design
(`paw-workspace/docs/design/drafts/2026-10-17-dual-renderer.md`, sections 1,
5 and 7). macOS only: every file under `Sources/CoreRenderMetal/` is wrapped
whole in `#if canImport(Metal)`; the Linux-safe parts (capability state,
tiling math, pipeline cache keys) live in `Sources/CoreRender/Metal/` with
no Metal import, so mutations run on Linux.

**Unblocks:** Automatic and GPU in creative-apps' Settings > Rendering doing
anything; canvas-host CH-10's live presenter; big-document and live-effect
speed in Photo and Halo.

**Depends on:** `render-backend` (RB-a for the targets and the contract, RB-c
for the harness and the CPU goldens). Base: `origin/dev` after `render-backend`'s
`feature-done`.

**Where parity runs.** core's `ci.yml` has a macOS job (`macos-15`,
`scripts/ci` on dev runs). Every parity test is
`.enabled(if: MetalBackend.defaultDevice != nil)`; the macos-15 runner
exposes a Metal device (dev CI run 39010063417: `MetalPipelinesTests` ran
there; recorded in `waves.md`), so parity runs on dev's macOS job. If a later
runner skips, the lead runs the suite on its Mac before each `Fast-Check:` and
the Mac finisher posts the counts. Linux never builds Metal.

## Slices

| slice | behavior (one sentence) | tasks | checks | waits on |
|---|---|---|---|---|
| MB-a | `MetalBackend` exists with a device, a queue, upload and download of tiled `rgba16Float` surfaces, an empty `supports`, a health probe that drops to CPU on device loss, and a pipeline cache; the parity suite is scaffolded with every family disabled. | MB-1, MB-2 | `MetalSurfaceTests`, `MetalCapabilitiesTests`, `ParityTests` (scaffold) | render-backend (RB-a: MB-1; RB-c: MB-2) |
| MB-b | Display encodes through the same `DisplayTransfer` tables as the CPU, and `.normal` composite with opacity and offsets matches within `.standard`. | MB-3, MB-4 | `ParityTests/display`, `ParityTests/compositeNormal` | MB-a (MB-3, MB-4) |
| MB-c | The twelve separable blend modes match within `.standard`, including the opaque-row path. | MB-5, MB-6 | `ParityTests/blendSeparable` | MB-b (MB-5) |
| MB-d | Crop, quarter turns and both resample filters match within `.standard`. | MB-7, MB-8 | `ParityTests/transform`, `ParityTests/resample` | MB-a (MB-7, MB-8) |
| MB-e | Hue, saturation, color and luminosity match within `.nonSeparable`, with the clip-colour edge cases. | MB-9, MB-10 | `ParityTests/blendNonSeparable` | MB-c (MB-9) |
| MB-f | Gaussian blur and unsharp mask match within `.standard`. | MB-11, MB-12 | `ParityTests/blur` | MB-d (MB-11) |
| MB-g | Every `ToneAdjustment` matches within `.standard`. | MB-13, MB-14 | `ParityTests/adjust` | MB-a (MB-13) |
| MB-h | Clone through a mask matches; surfaces tile and evict to the CPU copy under a memory bound; `residentBytes` is reported; the feature is done. | MB-15, MB-16, MB-17 | `ParityTests/retouch`, `MetalTilingTests`, `MetalBudgetTests` | MB-b to MB-g (MB-17) |

`ui_slice: none`: an engine feature with no screen. Each slice is one
family; a slice's `supports` entry is added by its last task, so the
dispatcher never routes a family whose parity test isn't green.

## Journey steps

Engine only. On the apps' side: creative-apps SJ28 (GPU picked, the status
reads "Metal (<device>)"), and Photo's and Halo's journeys unchanged on GPU.

## Screens and states

None.

## Contract slice

```swift
// Sources/CoreRender/Metal/MetalCapabilities.swift (MB-1, Linux-safe)
public struct MetalCapabilities: Equatable, Sendable {
    public private(set) var supported: Set<RenderOp>
    public private(set) var healthy: Bool
    public private(set) var lastError: String?
    public mutating func enable(_ op: RenderOp)
    public mutating func fail(_ reason: String)      // healthy = false, supported stays (for the status note)
    public mutating func recover()                   // after a new device
}
// Sources/CoreRender/Metal/SurfaceTiling.swift (MB-1, Linux-safe)
public struct SurfaceTiling: Equatable, Sendable {    // 256 px tiles, as CoreRaster's Tiles.swift
    public init(width: Int, height: Int) throws
    public var tileCount: Int; public func rect(_ index: Int) throws -> TileRect
    public func tiles(touching x: Int, y: Int, width: Int, height: Int) -> [Int]
}
// Sources/CoreRender/Metal/PipelineKey.swift (MB-2, Linux-safe)
public struct PipelineKey: Hashable, Codable, Sendable { public let op: RenderOp; public let variant: String }
// Sources/CoreRenderMetal/MetalBackend.swift (MB-1, #if canImport(Metal))
public final class MetalBackend: RenderBackend, @unchecked Sendable {
    public static var defaultDevice: MTLDevice? { MTLCreateSystemDefaultDevice() }
    public init(device: MTLDevice, cacheURL: URL?) throws
    public var name: String                          // "Metal (<device.name>)"
    public var supports: Set<RenderOp>               // capabilities.supported when healthy, else []
    public var isHealthy: Bool
    public var residentBytes: Int
    // the protocol's methods; an op outside `supports` throws .unsupported(op)
}
```

## Pseudocode

- **Surfaces.** `MetalSurface`: one `MTLTexture` per tile (`rgba16Float`,
  linear, premultiplied), `SurfaceTiling` for the grid, and a CPU
  `PixelBuffer` shadow filled on `read` or eviction. `surface(_:)` uploads
  Float32 to Float16 per tile; `read` downloads and converts back.
- **Display.** A compute kernel reads the Float16 texture, applies the
  `DisplayTransfer` decode-free encode through a 1-D table texture uploaded
  from `DisplayTransfer(.sRGB)` or `.displayP3`, clamps and rounds exactly as
  `rgba8` does, writes `rgba8Unorm`. Parity: 2/255.
- **Composite.** One kernel per blend family with the W3C formulas from
  `BlendMode.swift`, straight colours computed from premultiplied inputs with
  the same alpha guards (alpha <= 1e-6 treated as 0, the CPU's rule).
- **Pipeline cache.** `MTLBinaryArchive` at `cacheURL`; a missing or stale
  archive compiles on a background queue while `supports` excludes the
  family, so the first frames draw on CPU and nothing stalls.
- **Health.** A command buffer error or a lost device calls
  `capabilities.fail(reason)`; `isHealthy` turns false; the dispatcher routes
  everything to the CPU and records the reason. `recover()` on a new device.
- **Memory.** `residentBytes` sums tile textures; above `budgetBytes` (half of
  `device.recommendedMaxWorkingSetSize`) the least recently used tiles are
  released after their shadow is current.

## Tasks

| id | issue | what | owned files | depends on | size |
|---|---|---|---|---|---|
| MB-1 | – | `MetalCapabilities`, `SurfaceTiling` (Linux-safe, with mutations); `MetalBackend` with device, queue, `MetalSurface` upload and download; `supports` empty | `Sources/CoreRender/Metal/MetalCapabilities.swift`, `Sources/CoreRender/Metal/SurfaceTiling.swift`, `Tests/CoreRenderTests/MetalCapabilitiesTests.swift`, `Tests/CoreRenderTests/SurfaceTilingTests.swift`, `Tests/mutations/CoreRenderMetalCapabilities.json`, `Tests/mutations/CoreRenderSurfaceTiling.json`, `Sources/CoreRenderMetal/MetalBackend.swift`, `Sources/CoreRenderMetal/MetalSurface.swift`, `Tests/CoreRenderMetalTests/MetalSurfaceTests.swift`, `docs/c4/parts/creative-core/corerender/metal-support.json`, `docs/c4/parts/creative-core/corerendermetal/metal-backend.json` | – | ~380, 11 |
| MB-2 | – | `PipelineKey` and the `MTLBinaryArchive` cache; health probe and `fail`/`recover` wiring; `ParityTests` scaffold, every family disabled; the runner-device answer in `waves.md` | `Sources/CoreRender/Metal/PipelineKey.swift`, `Sources/CoreRenderMetal/MetalPipelines.swift`, `Tests/CoreRenderMetalTests/MetalPipelinesTests.swift`, `Tests/CoreRenderMetalTests/ParityTests.swift`, `Tests/mutations/CoreRenderMetalCapabilities.json`, `docs/blueprints/core/features/waves.md` | MB-1 | ~300, 6 |
| MB-3 | – | Display kernel over the `DisplayTransfer` table texture; enables `ParityTests/display`; `supports += .display` | `Sources/CoreRenderMetal/Shaders/DisplayShader.swift`, `Sources/CoreRenderMetal/MetalBackend+Display.swift`, `Tests/CoreRenderMetalTests/ParityTests+Display.swift` | MB-2 | ~220, 3 |
| MB-4 | – | `.normal` composite with opacity and offsets, in place on the backdrop's tiles; enables `compositeNormal`; `supports += .composite` | `Sources/CoreRenderMetal/Shaders/CompositeShader.swift`, `Sources/CoreRenderMetal/MetalBackend+Composite.swift`, `Tests/CoreRenderMetalTests/ParityTests+Composite.swift` | MB-2 | ~260, 3 |
| MB-5 | – | The twelve separable modes as kernel variants; enables `blendSeparable` | `Sources/CoreRenderMetal/Shaders/BlendSeparableShader.swift`, `Sources/CoreRenderMetal/MetalBackend+BlendSeparable.swift`, `Tests/CoreRenderMetalTests/ParityTests+BlendSeparable.swift` | MB-4 | ~300, 3 |
| MB-6 | – | Opaque-row fast path (a blit when the source row is opaque at opacity 1) with equal pixels; `supports += .blendSeparable` | `Sources/CoreRenderMetal/MetalBackend+OpaqueRows.swift`, `Tests/CoreRenderMetalTests/ParityTests+OpaqueRows.swift` | MB-5 | ~160, 2 |
| MB-7 | – | Crop and quarter turns as blits and a rotate kernel; enables `transform`; `supports += .transform` | `Sources/CoreRenderMetal/Shaders/TransformShader.swift`, `Sources/CoreRenderMetal/MetalBackend+Transform.swift`, `Tests/CoreRenderMetalTests/ParityTests+Transform.swift` | MB-2 | ~220, 3 |
| MB-8 | – | Bilinear and lanczos3 as two separable passes with clamp-to-edge taps and normalised weights; enables `resample`; `supports += .resample` | `Sources/CoreRenderMetal/Shaders/ResampleShader.swift`, `Sources/CoreRenderMetal/MetalBackend+Resample.swift`, `Tests/CoreRenderMetalTests/ParityTests+Resample.swift` | MB-2 | ~300, 3 |
| MB-9 | – | Hue, saturation, color, luminosity with Lum, Sat, SetLum, SetSat, ClipColor; enables `blendNonSeparable` at `.nonSeparable` | `Sources/CoreRenderMetal/Shaders/BlendNonSeparableShader.swift`, `Sources/CoreRenderMetal/MetalBackend+BlendNonSeparable.swift`, `Tests/CoreRenderMetalTests/ParityTests+BlendNonSeparable.swift` | MB-5 | ~280, 3 |
| MB-10 | – | ClipColor edge cases (lum at 0 and 1, grey sources) in Float32 math inside the kernel; `supports += .blendNonSeparable` | `Sources/CoreRenderMetal/Shaders/BlendNonSeparableShader.swift`, `Tests/CoreRenderMetalTests/ParityTests+BlendNonSeparable.swift` | MB-9 | ~120, 2 |
| MB-11 | – | Gaussian blur, two passes, the CPU's kernel builder uploaded as weights; enables `blur` | `Sources/CoreRenderMetal/Shaders/BlurShader.swift`, `Sources/CoreRenderMetal/MetalBackend+Blur.swift`, `Tests/CoreRenderMetalTests/ParityTests+Blur.swift` | MB-8 | ~240, 3 |
| MB-12 | – | Unsharp mask over the blur; `supports += .blur` | `Sources/CoreRenderMetal/MetalBackend+Unsharp.swift`, `Tests/CoreRenderMetalTests/ParityTests+Unsharp.swift` | MB-11 | ~140, 2 |
| MB-13 | – | Exposure, levels, curves (the curve as a 1-D table) on unpremultiplied values; enables `adjust` | `Sources/CoreRenderMetal/Shaders/AdjustShader.swift`, `Sources/CoreRenderMetal/MetalBackend+Adjust.swift`, `Tests/CoreRenderMetalTests/ParityTests+Adjust.swift` | MB-2 | ~280, 3 |
| MB-14 | – | White balance, contrast, highlights and shadows; `supports += .adjust` | `Sources/CoreRenderMetal/Shaders/AdjustShader.swift`, `Sources/CoreRenderMetal/MetalBackend+Adjust.swift`, `Tests/CoreRenderMetalTests/ParityTests+Adjust.swift` | MB-13 | ~220, 3 |
| MB-15 | – | Clone through a mask; enables `retouch`; `supports += .retouch` | `Sources/CoreRenderMetal/Shaders/RetouchShader.swift`, `Sources/CoreRenderMetal/MetalBackend+Retouch.swift`, `Tests/CoreRenderMetalTests/ParityTests+Retouch.swift` | MB-4 | ~220, 3 |
| MB-16 | – | LRU eviction to the shadow under `budgetBytes`; `residentBytes`; `MetalBudgetTests` (release, reported; the speed p95 enables with MB-4) | `Sources/CoreRenderMetal/MetalSurface+Eviction.swift`, `Sources/CoreRenderMetal/MetalBackend+Memory.swift`, `Tests/CoreRenderMetalTests/MetalTilingTests.swift`, `Tests/CoreRenderMetalTests/MetalBudgetTests.swift` | MB-1 (memory); MB-4 (speed p95) | ~240, 4 |
| MB-17 | – | Every family on; the parity counts and the runner answer in `waves.md`; `feature-done` | `docs/blueprints/core/features/waves.md`, `Tests/CoreRenderMetalTests/ParityTests.swift` | MB-3 to MB-16 | ~80, 2 |

## Build waves

- Wave 1: MB-1. Independent in this wave: MB-1 alone.
- Wave 2: MB-2, MB-16. Independent in this wave: both.
- Wave 3: MB-3, MB-4, MB-7, MB-8, MB-13. Independent in this wave: all five.
- Wave 4: MB-5, MB-11, MB-14, MB-15. Independent in this wave: all four.
- Wave 5: MB-6, MB-9, MB-12. Independent in this wave: all three.
- Wave 6: MB-10. Independent in this wave: MB-10 alone.
- Wave 7: MB-17 (`feature-done`, final). Independent in this wave: MB-17 alone.

Longest chain: MB-1 → MB-2 → MB-4 → MB-5 → MB-9 → MB-10 → MB-17 (7).
Chain of 7: the backend, then its pipelines, then the composite kernel the
blend variants extend (separable, then non-separable in the same shader file,
then its edge cases); MB-17 carries `feature-done`. One lead builds this
slowly: a wave with five independent tasks is still taken one or two at a
time, each PR with its parity run on the lead's Mac.

## Acceptance test per task

Parity tests are `.enabled(if: MetalBackend.defaultDevice != nil)` and
compare against the CPU goldens from `render-backend` RB-7 with
`ParityHarness.compare`. Linux-safe tests carry mutations; shader code is
covered by parity, not mutations.

| id | test | fails when | mutations (plan: label → filter) |
|---|---|---|---|
| MB-1 | `MetalCapabilitiesTests`: `enable` then `fail` gives `supported` kept and `healthy` false; `recover` restores; `SurfaceTilingTests`: 4096 x 2160 gives 16 x 9 tiles (4096 is exactly 16 columns; 4097 adds a 1 px 17th), the last column 0 px wide never exists, `tiles(touching:)` on a rect spanning two tiles gives both; `MetalSurfaceTests` (macOS, device): `read(surface(b))` within 1e-3 of `b` for 20 seeded buffers (Float16 round trip), `residentBytes` equals tiles x bytes | tiling is off by one or a round trip loses more than Float16 | `CoreRenderMetalCapabilities`: `fail` clears `supported` → `MetalCapabilitiesTests`; `CoreRenderSurfaceTiling`: `<=` for `<` on the last tile → `SurfaceTilingTests` |
| MB-2 | `MetalPipelinesTests`: a cold cache compiles and writes the archive; a warm start loads without compiling (a counter); a corrupt archive recompiles and rewrites; `fail` after a mocked command-buffer error turns `isHealthy` false and `supports` empty; `ParityTests` scaffold lists every family disabled with "waits on MB-n" | the cache is ignored, or an error leaves `supports` on | `CoreRenderMetalCapabilities`: `recover` keeps `lastError` → `MetalCapabilitiesTests`; `PipelineKey` ignores `variant` in `==` → `MetalPipelinesTests` |
| MB-3 | `ParityTests/display`: the display golden set in sRGB and P3 within 2/255; every byte value per channel round-trips | the table or the rounding differs | none: shader |
| MB-4 | `ParityTests/compositeNormal`: opacities 0, 0.37, 1, sources off every edge and corner, wholly outside, alpha 1e-45 source; within `.standard` | an edge pixel or an alpha guard differs | none: shader |
| MB-5 | `ParityTests/blendSeparable`: twelve modes at three opacities within `.standard` | a formula differs | none: shader |
| MB-6 | `ParityTests/opaqueRows`: an opaque `.normal` row at opacity 1 equals the golden with zero delta; a row with one 0.999 alpha pixel takes the kernel path | the blit runs on a non-opaque row | none: shader |
| MB-7 | `ParityTests/transform`: crop at every corner, three turns, zero delta (exact copies) | a turn maps wrong | none: shader |
| MB-8 | `ParityTests/resample`: both filters up and down at 5 sizes within `.standard`; a constant image stays constant | weights don't normalise | none: shader |
| MB-9 | `ParityTests/blendNonSeparable`: four modes within `.nonSeparable` on the seeded set | SetLum or SetSat differs | none: shader |
| MB-10 | the same suite's edge rows: lum 0 and 1, grey sources, within `.nonSeparable` | ClipColor skips a bound | none: shader |
| MB-11 | `ParityTests/blur`: sigma 0, 0.5, 3, 20 within `.standard`; clamp-to-edge at the borders | a border reads black | none: shader |
| MB-12 | `ParityTests/unsharp`: amount, sigma, threshold grid within `.standard` | the threshold compares the wrong way | none: shader |
| MB-13 | `ParityTests/adjust`: exposure, levels, curves within `.standard`, in linear and sRGB encodings | premultiply order differs | none: shader |
| MB-14 | `ParityTests/adjust` develop rows within `.standard` | a slider's sign flips | none: shader |
| MB-15 | `ParityTests/retouch`: clone with offsets off the edge through rect, ellipse and polygon masks within `.standard` | a mask edge differs | none: shader |
| MB-16 | `MetalTilingTests`: above `budgetBytes` the LRU tile is released after its shadow is current and `read` still equals the golden; `MetalBudgetTests` (release): a 4K x 20-layer composite's `residentBytes` stays under the budget; sample-to-result p95 ≤ 4 ms per composite, reported | eviction loses pixels | none: device-bound (Linux can't run it) |
| MB-17 | `ParityTests` has no disabled family; `supports == Set(RenderOp.allCases)`; `waves.md` records the counts | a family is still off | none |

## Quality tests

| quality row | budget | test |
|---|---|---|
| Parity per family | `.standard` 2/255 and 1e-3; `.nonSeparable` 4/255 | `ParityTests/*` |
| First launch | a cold cache draws on CPU (no stall); compile finishes off the main queue | `MetalPipelinesTests` |
| Fallback | device loss routes every op to the CPU within one op and records the reason | `MetalCapabilitiesTests`, `RenderDispatcherTests` (render-backend) |
| Memory | 4K x 20 uploaded layers under half the working set; eviction keeps pixels | `MetalTilingTests`, `MetalBudgetTests` (release only, on the lead's or finisher's Mac; skipped by the debug `scripts/ci`) |
| Speed | 4K composite p95 ≤ 4 ms (Metal) against ≤ 8 ms CPU, reported | `MetalBudgetTests` (disabled until MB-4; then release only, on the lead's or finisher's Mac) |
| Linux-safe | `scripts/ci` on Linux builds `CoreRenderMetal` empty and tests `CoreRender/Metal/` with mutations | the Linux CI job |

## Done check

Per slice: its parity test green on a device (the macOS job when it has one,
else the lead's Mac with the run recorded in the PR body), the Linux job
green, no open `finding`, mutations scored for the Linux-safe files, and
`supports` extended only in the slice's last task. The lead posts one line
per slice on the feature issue with the parity counts and the worst delta.
Then `Belt-Contact-Sheet:` and a `scripts/bump-core` in creative-apps.

## Not in this packet

Presenting into a `CAMetalLayer` (creative-apps canvas-host). Brush stamping
(no core op yet). Float32 textures for a precision mode. A Vulkan or other
GPU path.

## Decisions (captain, 2026-10-17)

1. **Metal lives in core as `CoreRenderMetal`.** It is the only module that
   may import Metal; every file in it is wrapped in `#if canImport(Metal)` and
   Linux builds it empty (CLAUDE.md, "Every module stays Linux-safe").
2. **The Rendering setting is suite-wide,** set once in the launcher's
   Settings pane, not per app.
3. **Core runs v3.** `docs/factory/lead.md` has rules 12 to 19 and the
   two-level done (merged-done on Linux, verified on the Mac).

## Deviations (lead, 2026-10-17, slice MB-a)

- **No on-disk `MTLBinaryArchive`.** The archive at `cacheURL` described under
  Pseudocode and in MB-2 is dropped. Pipelines rely on Metal's own shader
  cache plus an in-process memo keyed by `PipelineKey`. `cacheURL` stays in
  `MetalBackend.init` as a reserved parameter so callers need not change if an
  archive returns.
- **Background compile is deferred to MB-17.** A family's first pipeline
  compiles on first use, under the backend's lock; MB-3 shipped that way.
  Compiling off the caller's queue while `supports` excludes the family, and
  the First launch row, move to MB-17. `preparePipeline` builds caller
  kernels in a memo of their own, so it cannot warm or replace a built-in
  pipeline.
- **`PipelineKey.validated` bounds the variant** at 64 UTF-8 bytes
  (`PipelineKey.maxVariantLength`) as well as checking it is an identifier.
- **`recover()` keeps the same device.** `device` is fixed at init, so
  `recover()` makes a new queue on it, runs the probe, and clears the failure
  only if the probe passes. After a real device loss the app opens a new
  `MetalBackend` on a new device instead (Pseudocode, "Health").
- **MB-16 as built.** (1) The Speed row's sample-to-result p95 needs the
  composite kernel, so `MetalBudgetTests.fourKCompositeP95Under4ms` stays
  disabled until MB-4 enables it; MB-4 (or MB-17, if MB-4 lands first without
  it) owns turning it on. (2) The Memory row uploads twenty 4K layers and
  checks `residentBytes` after each, with no composite between them; the
  composite variant arrives with the speed test. (3) `MetalBudgetTests` runs
  only in an optimized build, so dev's debug `scripts/ci` skips it; the lead
  or the Mac finisher runs it on release and reports it, and MB-h's done check
  needs that run recorded, not the skipped CI test. (4) The budget lives in
  three places: `budgetBytes` in `MetalBackend.swift`, its default formula in
  `SurfaceTiling.defaultBudget` (Linux-safe, tested in `SurfaceTilingTests`,
  mutated in `CoreRenderSurfaceTiling`), and eviction in
  `MetalBackend+Memory.swift` and `MetalSurface+Eviction.swift`.
- **Shaders are Swift strings, not `.metal` files.** Each family's MSL is a
  `static let source` in `Sources/CoreRenderMetal/Shaders/<Name>Shader.swift`,
  compiled at runtime with `makeLibrary(source:)` through `MetalPipelines`,
  as MB-2 built the probe. A `.metal` file would need the Metal toolchain at
  build time and a resources entry in `Package.swift`. The Tasks rows name
  the Swift files.
- **MB-1's tile count.** 4096 x 2160 gives 16 x 9 tiles, not 17 x 9: 4096 is
  exactly 16 columns of 256. `SurfaceTilingTests` asserts 16 x 9, and 4097
  adds a 1 px 17th column.
- **MB-2's `PipelineKey` mutation.** `PipelineKey` uses synthesized
  `Hashable`, so "`==` ignores `variant`" has no anchor to plant. The
  key-equality test lives in `PipelineKeyTests`, and `CoreRenderPipelineKey`
  plants the `functionName` and `validated` mutations instead.
- **Round 3 findings for MB-a** (19 confirmed, fix rounds exhausted) are listed
  in `docs/leads/metal-backend/round3-findings.md` on `lead/metal-backend`.
  The two majors shipped in #385 (slice MB-b); the rest are doc and test
  polish for MB-17.

## Deviations (lead, 2026-10-17, slices MB-b and MB-d)

- **`.composite` needs read-write texture tier 2.** MB-4 composites in place,
  so init adds `.composite` only when `device.readWriteTextureSupport ==
  .tier2` (`compositesInPlace`), not unconditionally. On other Macs the
  dispatcher routes composite to the CPU backend.
- **`.display`, `.transform` and `.resample` start enabled at init**, with
  tier-2 `.composite`. While the backend is unhealthy `supports` is empty and
  each of these ops throws `unsupported(<family>)`, not `deviceLost`.
- **MB-3 display tables are constant buffers.** CoreColor's byte rules go up
  as Float thresholds (found by bisection) and a Float P3 matrix in constant
  buffers (`DisplayTable`), not a 1-D table texture. Evicted tiles encode
  from their shadows on the CPU with `PixelBuffer.rgba8`.
- **MB-8 resamples whole images, not tiles.** It reads the surface through
  the CPU into a float4 buffer, runs both separable passes over whole-image
  buffers in CoreRaster's pass order, and scatters into the new surface's
  tiles. Its taps are CoreRaster's own (`ResampleFilter.taps`, made public
  for this), flattened by `ResampleTable`. A valid size whose largest real
  buffer (`ResampleTable.peakPixels`, at most max(input, output) pixels)
  exceeds the device's `maxBufferLength` throws `unsupported(.resample)`
  without failing the backend; the caller resamples on the CPU backend. The
  CPU backend has no such limit.
- **Linux-safe helpers not in the Tasks' owned files.** `DisplayTable`
  (MB-3), `CompositeMap` (MB-4), `OpaqueRows` and its `RowRun` (MB-6),
  `TileMap` (MB-7), `ResampleTable` (MB-8), `BlurTable` (MB-11),
  `UnsharpRule` (MB-12) and `AdjustTable` (MB-13, MB-14) in
  `Sources/CoreRender/Metal/`, their `Tests/CoreRenderTests` suites
  (`<Name>Tests.swift`; `UnsharpRuleTests.swift` for `UnsharpRule`) and their
  `Tests/mutations/CoreRender<Name>.json` plans (`CoreRenderUnsharp.json` for
  `UnsharpRule`) belong to those tasks. They hold the GPU paths' math so it
  builds, tests and mutates on Linux. `ParityPack`
  (`Sources/CoreRender/Parity/ParityPack.swift`, #399: how the CPU goldens
  are packed, tested in `CPUGoldenTests` and `ParityHarnessTests`, planted in
  `CoreRenderParity.json`) belongs to the parity scaffold (MB-2).
- **Parity oracle.** Goldens cover only `sampleSet(for:)` and are byte
  compares. The wider grids each family promises (sizes, offsets, turns,
  evicted runs) compare with the CPU backend run on the GPU's Float16 pixels
  (`cpu.surface(try metal.read(src))`): Float16 storage turns alpha 1e-45
  into 0 and rounds every value, so a Float32 CPU reference is not
  bit-comparable. Transform and resample also read their golden bands on the
  original samples, so upload loss counts there.
- **Shaders are Swift strings**, as recorded for MB-a.

## Deviations (lead, 2026-10-17, slices MB-c, MB-f and MB-g)

- **Helpers outside the owned files.** `OpaqueRows` (MB-6), `BlurTable`
  (MB-11), `UnsharpRule` (MB-12), `AdjustTable` (MB-13, MB-14) and
  `ParityPack` are listed, with their suites and plans, in the MB-b/MB-d
  helpers bullet above.
- **MB-11 copies the CPU's kernel builder.** CoreRaster's `gaussianKernel`
  is private, so `BlurTable` builds the same weights itself (2 ceil(3 sigma)
  + 1 taps of exp(-x^2 / 2 sigma^2), normalised in Double, stored as Float;
  sigma 0 is the single weight 1) and throws the CPU backend's exact errors.
  `BlurTableTests` holds it to CoreRaster's output; the GPU uploads these
  weights, not the CPU builder's.
- **MB-11 and MB-12 blur whole images, not tiles**, as MB-8 resamples: the
  surface is read through the CPU into a float4 buffer, both passes run over
  whole-image buffers, and the result scatters into the new surface's tiles
  with MB-8's scatter kernel. An input whose buffers (width x height x 16
  bytes) exceed the device's `maxBufferLength` throws
  `unsupported(.blur)` for `gaussianBlur` and `unsharpMask` alike, as
  resample throws `unsupported(.resample)`, without failing the backend; the
  caller runs the op on the CPU backend, which has no such limit. (The
  switch from `raster` to `unsupported` lands with batch r3f1.)
- **`.blendSeparable` needs read-write tier 2 too.** MB-6 adds
  `.blendSeparable` only on a tier-2 device (`compositesInPlace`), as MB-4
  adds `.composite`; elsewhere the dispatcher routes those modes to the CPU.
- **MB-13's curve table is a probed buffer.** Levels, curves and contrast go
  up as `AdjustTable`'s `channel` table, a buffer of the values that
  `CPUBackend.adjusted` gives on a probe row of grey pixels, not a 1-D
  texture of CoreRaster's formulas; exposure and white balance as per-channel
  gains, highlights and shadows as a gain per luminance.

## Open

- **The runner's device.** Answered: the macos-15 runner exposes a Metal
  device (dev CI run 39010063417, where `MetalPipelinesTests` ran).
