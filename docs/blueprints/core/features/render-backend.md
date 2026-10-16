# Feature packet: render-backend

**Feature:** one `RenderBackend` contract every app's Model draws through,
with the CPU backend that wraps today's CoreRaster (the reference, pixel for
pixel what the apps draw now), a dispatcher that routes each op to the
preferred backend when it supports that op and is healthy and to the CPU
otherwise, and the parity harness (sample inputs, tolerances, golden files)
the Metal backend will be measured against. Linux-safe end to end.
**Line:** `line:core` · **Wave:** 3 (`waves.md`) · **Lead branch:** `lead/render-backend`

**Covers:** the dual-renderer design
(`paw-workspace/docs/design/drafts/2026-10-17-dual-renderer.md`, sections 1
and 5). The feature issue is the approval `Package.swift` needs (CLAUDE.md,
Modules): two new targets, `CoreRender` and `CoreRenderMetal`.

**Unblocks:** creative-core `metal-backend` (every slice of it); creative-apps
`canvas-host` CH-10's live presenter and each app's "Model draws through a
`RenderDispatcher`" adoption, through one bump PR.

**Depends on:** nothing open. Base: `origin/dev` cae920b (2026-10-17).

**Existing work:** none. `raster-throughput` (wave 2, RT-3) adds the in-place
`composite(_:x:y:mode:opacity:)` the CPU backend calls; RB-3 codes against
the free functions on `dev` and switches to the in-place one when RT-3 is on
`dev` (no wait: both give equal pixels, `CompositeInPlaceTests`).

## Slices

| slice | behavior (one sentence) | tasks | checks | waits on |
|---|---|---|---|---|
| RB-a | The two targets exist and build empty on Linux and macOS, and tests can code against `RenderBackend`, `RenderOp`, `RenderSurface`, `RenderError` and a `FakeBackend` that records calls and supports a chosen op set. | RB-1, RB-2 | `RenderBackendFakeTests` | nothing |
| RB-b | `CPUBackend` runs every op family through CoreRaster with results equal to the direct call, and `RenderDispatcher` routes each op by capability and health, records the last fallback, and never changes a pixel when it falls back. | RB-3, RB-4, RB-5 | `CPUBackendTests`, `RenderDispatcherTests` | RB-a (RB-3, RB-4, RB-5) |
| RB-c | The parity harness renders the sample set on any backend, compares two results within a stated tolerance, reads and writes goldens, and the CPU goldens for every family are checked in with the dispatcher's overhead budget. | RB-6, RB-7 | `ParityHarnessTests`, `RenderBudgetTests` | RB-b (RB-6, RB-7) |

`ui_slice: none`: an engine feature with no screen; its screen is
creative-apps `canvas-host`.

## Journey steps

Engine only. The apps' journeys that will run on it: creative-apps SJ27 and
SJ28 (canvas-host), Photo's brush and Halo's viewer journeys after adoption.

## Screens and states

None.

## Contract slice

```swift
// Sources/CoreRender/RenderOp.swift (RB-2)
public enum RenderOp: String, CaseIterable, Codable, Sendable {
    case display, composite, blendSeparable, blendNonSeparable, transform, resample, blur, adjust, retouch
}
public enum RenderError: Error, Equatable, Sendable {
    case unsupported(RenderOp), deviceLost(String), surfaceMismatch, raster(String)
}
// Sources/CoreRender/RenderSurface.swift
public struct RenderSurface: Sendable, Equatable {
    public let id: UUID, width: Int, height: Int, backend: String   // storage is the backend's
}
// Sources/CoreRender/RenderBackend.swift
public protocol RenderBackend: Sendable {
    var name: String { get }
    var supports: Set<RenderOp> { get }
    var isHealthy: Bool { get }
    func surface(_ buffer: PixelBuffer) throws -> RenderSurface
    func read(_ surface: RenderSurface) throws -> PixelBuffer
    func release(_ surface: RenderSurface)
    func display(_ s: RenderSurface, colorSpace: ColorSpace) throws -> [UInt8]
    func composite(_ s: RenderSurface, onto b: inout RenderSurface, x: Int, y: Int, mode: BlendMode, opacity: Float) throws
    func cropped(_ s: RenderSurface, x: Int, y: Int, width: Int, height: Int) throws -> RenderSurface
    func rotated(_ s: RenderSurface, _ turn: QuarterTurn) throws -> RenderSurface
    func resampled(_ s: RenderSurface, width: Int, height: Int, filter: ResampleFilter) throws -> RenderSurface
    func gaussianBlur(_ s: RenderSurface, sigma: Double) throws -> RenderSurface
    func unsharpMask(_ s: RenderSurface, amount: Double, sigma: Double, threshold: Double) throws -> RenderSurface
    func adjusted(_ s: RenderSurface, _ adjustment: ToneAdjustment) throws -> RenderSurface   // exposure, levels, curves, whiteBalance, contrast, highlightsShadows
    func cloned(_ s: RenderSurface, offset: (dx: Int, dy: Int), through mask: Mask) throws -> RenderSurface
}
public struct FakeBackend: RenderBackend { public var supports: Set<RenderOp>; public var healthy = true; /* records every call */ }
// Sources/CoreRender/RenderDispatcher.swift (RB-5)
public struct RenderDispatcher: Sendable {
    public init(preferred: (any RenderBackend)?, fallback: CPUBackend)
    public private(set) var lastFallback: (op: RenderOp, reason: String)?
    public func backend(for op: RenderOp) -> any RenderBackend   // preferred when it supports op and isHealthy, else fallback
    // one forwarding method per protocol method; a surface from the other backend is read and re-uploaded first
}
// Sources/CoreRender/Parity/ParityTolerance.swift (RB-6)
public struct ParityTolerance: Sendable { public let bytes: UInt8; public let linear: Float
    public static let standard = ParityTolerance(bytes: 2, linear: 1e-3)
    public static let nonSeparable = ParityTolerance(bytes: 4, linear: 4e-3) }
```

`Package.swift` (RB-1): `CoreRender` depends on `CoreRaster` and `CoreColor`;
`CoreRenderMetal` depends on `CoreRender` and holds one file,
`MetalBackend.swift`, wrapped whole in `#if canImport(Metal)`, so Linux builds
an empty module. Products for both; test targets `CoreRenderTests` and
`CoreRenderMetalTests`. Each new file has a C4 part owner (RB-1).

## Pseudocode

- **CPUSurface.** A class holding a `PixelBuffer`; `surface(_:)` copies in,
  `read` copies out, the ops call CoreRaster and store the result in a new
  surface. `composite(onto:)` mutates the backdrop surface's buffer in place.
- **Routing.** `backend(for:)`: `preferred` when `preferred.supports.contains(op)
  && preferred.isHealthy`, else `fallback`; when the choice differs from
  `preferred` and `preferred != nil`, set `lastFallback`. A surface made by
  one backend handed to the other is read and re-uploaded (`surfaceMismatch`
  only when sizes disagree).
- **Parity compare.** `ParityHarness.compare(a, b, tolerance)`: both as
  `rgba8(.sRGB)` bytes, max per-channel delta <= `bytes`, and on the linear
  Float buffers max delta <= `linear` for pixels whose alpha > 0.01; returns
  the worst pixel's location for the message.
- **Goldens.** `Tests/CoreRenderTests/Golden/<op>/<case>.rgba8` (raw bytes)
  with `<case>.json` (width, height, colour space, tolerance); Foundation
  only, no image codec. `ParityHarness.sampleSet(for: op)` builds inputs from
  seeded `randomPixel` buffers plus edge cases (alpha 0, 1e-45, opaque rows,
  sources off every edge).

## Tasks

| id | issue | what | owned files | depends on | size |
|---|---|---|---|---|---|
| RB-1 | feature issue (approves; `Package.swift` is a protected path, so the supervisor merges this PR) | The two targets, their test targets and products; the Linux-empty `MetalBackend.swift`; C4 parts for both containers | `Package.swift`, `Sources/CoreRender/CoreRender.swift`, `Sources/CoreRenderMetal/MetalBackend.swift`, `Tests/CoreRenderTests/TargetsTests.swift`, `Tests/CoreRenderMetalTests/TargetsTests.swift`, `docs/c4/parts/creative-core/corerender/container.json`, `docs/c4/parts/creative-core/corerender/contract.json`, `docs/c4/parts/creative-core/corerendermetal/container.json`, `docs/c4/parts/creative-core/corerendermetal/metal-backend.json` | – | ~160, 9 |
| RB-2 | – | `RenderOp`, `RenderError`, `RenderSurface`, `RenderBackend`, `ToneAdjustment`, `FakeBackend` and its tests; the CPU and dispatcher tests disabled | `Sources/CoreRender/RenderOp.swift`, `Sources/CoreRender/RenderSurface.swift`, `Sources/CoreRender/RenderBackend.swift`, `Sources/CoreRender/ToneAdjustment.swift`, `Sources/CoreRender/FakeBackend.swift`, `Tests/CoreRenderTests/RenderBackendFakeTests.swift`, `Tests/CoreRenderTests/CPUBackendTests.swift`, `Tests/CoreRenderTests/RenderDispatcherTests.swift` | RB-1 | ~340, 8 |
| RB-3 | – | `CPUBackend` and `CPUSurface`: surface, read, release, display, composite (in place) | `Sources/CoreRender/CPU/CPUBackend.swift`, `Sources/CoreRender/CPU/CPUSurface.swift`, `Tests/CoreRenderTests/CPUBackendTests.swift`, `Tests/mutations/CoreRenderCPUBackend.json`, `docs/c4/parts/creative-core/corerender/cpu-backend.json` | RB-2 | ~300, 5 |
| RB-4 | – | `CPUBackend` transform, resample, blur, adjust and retouch families | `Sources/CoreRender/CPU/CPUBackend+Ops.swift`, `Tests/CoreRenderTests/CPUBackendOpsTests.swift`, `Tests/mutations/CoreRenderCPUBackendOps.json` | RB-3 | ~280, 3 |
| RB-5 | – | `RenderDispatcher`: routing, health, `lastFallback`, cross-backend surfaces | `Sources/CoreRender/RenderDispatcher.swift`, `Tests/CoreRenderTests/RenderDispatcherTests.swift`, `Tests/mutations/CoreRenderDispatcher.json`, `docs/c4/parts/creative-core/corerender/dispatcher.json` | RB-3 | ~280, 4 |
| RB-6 | – | `ParityTolerance`, `ParityHarness` (sample sets, compare, golden read and write) | `Sources/CoreRender/Parity/ParityTolerance.swift`, `Sources/CoreRender/Parity/ParityHarness.swift`, `Tests/CoreRenderTests/ParityHarnessTests.swift`, `Tests/mutations/CoreRenderParity.json`, `docs/c4/parts/creative-core/corerender/parity.json` | RB-4 | ~320, 5 |
| RB-7 | – | CPU goldens for every family; `RenderBudgetTests` (dispatcher overhead, release only); `waves.md` status; `feature-done` | `Tests/CoreRenderTests/Golden/`, `Tests/CoreRenderTests/CPUGoldenTests.swift`, `Tests/CoreRenderTests/RenderBudgetTests.swift`, `docs/blueprints/core/features/waves.md` | RB-5, RB-6 | ~200, 3 + goldens |

## Build waves

- Wave 1: RB-1. Independent in this wave: RB-1 alone.
- Wave 2: RB-2. Independent in this wave: RB-2 alone.
- Wave 3: RB-3. Independent in this wave: RB-3 alone.
- Wave 4: RB-4, RB-5. Independent in this wave: both.
- Wave 5: RB-6. Independent in this wave: RB-6 alone.
- Wave 6: RB-7 (`feature-done`, final). Independent in this wave: RB-7 alone.

Longest chain: RB-1 → RB-2 → RB-3 → RB-4 → RB-6 → RB-7 (6).
Chain of 6: each step adds the types the next conforms to (targets, then the
protocol, then the backend the ops extend, then the harness that renders on
it); RB-7 carries `feature-done`.

## Acceptance test per task

Checks land with or before their code (RB-2 owns the CPU and dispatcher tests
disabled; RB-3 and RB-5 enable them). Mutation filters are
`swift test --filter` regexes.

| id | test | fails when | mutations (plan: label → filter) |
|---|---|---|---|
| RB-1 | `TargetsTests` in both test targets: `import CoreRender` and `import CoreRenderMetal` compile and a marker symbol exists; `scripts/ci` passes on Linux and macOS | a target is missing or Linux fails to build the Metal module | none: targets |
| RB-2 | `RenderBackendFakeTests`: `FakeBackend(supports: [.composite])` records a composite call and throws `.unsupported(.blur)` for a blur; `RenderOp.allCases` has 9 cases; `RenderError` is `Equatable` | a fake lies about support | none: contract and fakes |
| RB-3 | `CPUBackendTests`: `read(surface(b)) == b` for 50 seeded buffers; `display` equals `b.rgba8(colorSpace:)` byte for byte in sRGB and P3; `composite` equals the free `composite` for every `BlendMode` at opacities 0, 0.37, 1 with sources off every edge; a released surface throws `.surfaceMismatch` | a pixel differs from CoreRaster | `CoreRenderCPUBackend`: opacity ignored → `CPUBackendTests`; `read` returns the surface's stale copy after composite → `CPUBackendTests` |
| RB-4 | `CPUBackendOpsTests`: each op equals the CoreRaster call it wraps with `==` (crop, rotate, both filters, blur, unsharp, each `ToneAdjustment` case, cloned through a mask); every CoreRaster throw surfaces as `.raster(message)` with the same message | a wrapper reorders arguments or swallows a throw | `CoreRenderCPUBackendOps`: `rotated` maps 90 to 270 → `CPUBackendOpsTests`; `adjusted(.levels)` drops gamma → `CPUBackendOpsTests` |
| RB-5 | `RenderDispatcherTests`: with a fake preferring `[.composite]`, a blur goes to the CPU and `lastFallback == (.blur, "unsupported")`; an unhealthy fake routes everything to the CPU with reason "unhealthy"; nil preferred routes to the CPU with no fallback recorded; a fake surface handed to a CPU op is re-uploaded; the pixels equal the direct CPU result in every case | a fallback changes a pixel, or routing picks an unsupported op | `CoreRenderDispatcher`: `isHealthy` not checked → `RenderDispatcherTests`; `lastFallback` cleared on the next success → `RenderDispatcherTests` (it keeps the last) |
| RB-6 | `ParityHarnessTests`: `compare` passes two equal buffers, passes a 2/255 delta and fails a 3/255 one under `.standard`, passes 4/255 under `.nonSeparable`; a golden written then read round-trips bytes and header; `sampleSet(for:)` is deterministic (two calls equal) and covers the edge cases by name | the tolerance is off by one or goldens drift | `CoreRenderParity`: `<` for `<=` on the byte bound → `ParityHarnessTests`; alpha gate dropped (transparent pixels compared) → `ParityHarnessTests` |
| RB-7 | `CPUGoldenTests`: the CPU backend reproduces every golden with zero delta; `RenderBudgetTests` (release, `.serialized`): the dispatcher's composite of a 12 MP layer is within 2% of the direct CoreRaster call's median over 5 runs | a golden changes, or the dispatcher adds a copy | none: goldens and a budget |

## Quality tests

| quality row | budget | test |
|---|---|---|
| Dispatcher overhead | ≤ 2% over the direct CoreRaster call, 12 MP composite, median of 5 | `RenderBudgetTests` (release only; in `Tests/perf-suites` terms, reported by the macOS job) |
| Zero-delta reference | the CPU backend equals CoreRaster with `==` on every op | `CPUBackendTests`, `CPUBackendOpsTests` |
| Linux-safe | `scripts/ci` on Linux builds and tests `CoreRender`; `CoreRenderMetal` builds empty | `TargetsTests`, the Linux CI job |
| No crash | the no-crash lint over the new sources | `scripts/ci` |

## Done check

Per slice: its tests green on a `dev` run that contains its last PR (Linux
and macOS jobs), no open `finding`, every plan of its PRs scored with no
escape (`Mutate:` lines). RB-c also shows the goldens' count per family in
the contact sheet comment. Then `Belt-Contact-Sheet:` on the feature issue,
and the supervisor runs `scripts/bump-core` in creative-apps.

## Not in this packet

Metal (`metal-backend`). Tiled or evicted surfaces (metal-backend MB-h; the
CPU surface is one buffer). Presenting into a `CAMetalLayer` (creative-apps
canvas-host CH-10). GPU-side brush stamping: Photo paints in its Model today,
so a `stamp` op family lands only once an issue moves stamping into
CoreRaster.

## Open

- **Core's lead loop is v2.** This packet has a Slices table (creative-apps
  lead.md, rules 12 to 19). Until core's `lead.md` takes the v3 loop, a lead
  runs it as v2 with the slices as its waves and the acceptance table as its
  tests. Open decision for the captain in the design doc.
