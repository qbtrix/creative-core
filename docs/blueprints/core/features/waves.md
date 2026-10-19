# Core features: waves

Engine features, one feature-lead session each (`docs/factory/lead.md`).
Wave 1 shipped. Wave 2 takes the open `needs-core` asks from Photo and Flare
and the `gap` issue #300: three features, side by side. They wait on
nothing and own no file in common. Each packet lists its tasks, owned
files, acceptance tests and budgets. The priority column ranks the
features; the source issues carry their own labels (#220 to #225 and #228 are
`p3`, #226, #218 and #227 `p2`, #309 and #300 have none). Base for wave 2: `origin/dev` f05665f
(2026-10-16).

| wave | feature | packet | covers | priority | waits on | unblocks in the apps | feature issue | status |
|---|---|---|---|---|---|---|---|---|
| 1 | What the stage draws and what a click picks | `stage-geometry.md` | #213, #214, #215, #182 | p1 | nothing | Flare `live-stage` | #267 | shipped (#306) |
| 1 | Undoable edits on scene and symbol layers | `edit-commands.md` | #171, #219, #216, #217, #173 | p1 | nothing | Flare `live-keys`, `live-scenes`, `live-stage` | #268 | shipped (#299) |
| 2 | Whole-image raster work at display speed | `raster-throughput.md` | #309, #300 | p1 | nothing | Photo `photo-edit` (PB-15, PB-16) and the brush tile render | #311 | planned |
| 2 | State machines Flare can edit and play | `state-machine.md` | #220, #221, #222, #223, #224, #225, #226 | p2 | nothing | Flare LM-10, LM-11, LM-12 | #312 | planned |
| 2 | Onion frames, Lottie tracks and the core budgets | `motion-tracks.md` | #218, #227, #228 | p2 | nothing | Flare LM-8, LM-13a; the QB-L5 to QB-L8 model budgets | #313 | planned |
| 3 | A `RenderBackend` contract, the CPU backend over CoreRaster, the dispatcher and the parity harness | `render-backend.md` | dual-renderer design 2026-10-17 (sections 1, 5) | p1 | nothing (RT-3's in-place composite is a swap, not a wait) | creative-apps `canvas-host` CH-10 (live presenter); every app's Model drawing through a `RenderDispatcher` | #347 | built on `dev` (RB-1 to RB-7); `RenderBudgetTests` fails on release until the CPU composite stops copying its backdrop |
| 4 | The Metal backend, one op family per slice behind capability flags, each with a parity test; one dedicated lead on its own Belt line | `metal-backend.md` | dual-renderer design 2026-10-17 (sections 1, 5, 7) | p2 | render-backend | Automatic and GPU in Settings > Rendering doing anything; big-document speed in Photo and Halo | file when ready | planned |
| 5 | The W1 contract: four CPU-first render families, the W1 tone cases, CoreRaster W1 values, the W1 FlareCore model fields and the registry, undo and exporter seams | `engine-contracts.md` | beta-80 plan section 8 (the shared-file halves of E2, E3, E4, E5, E8, E14) | p1 | nothing | every wave-6 packet | file when ready | planned |
| 5 | Path edit math, measure, trim, dash, stroke outline and booleans on FlareCore `Path` | `path-geometry.md` | E1 (the unfiled core path issue; Q5 answered: FlareCore geometry) | p1 | nothing | Design Pen F7, S17, S18, `text-engine` (type on a path), `animate-properties` (morph) | file when ready | planned |
| 5 | PSD read and write, OpenRaster moved in from Photo, a neutral `LayeredImage` (new `coreraster/codecs`) | `layered-codecs.md` | E10 | p1 | nothing | Photo PSD open and save, G1's deep-PSD fixtures, `color-profiles` | file when ready | planned |
| 5 | SVG and Lottie readers (new `flarecore/import`) | `vector-import.md` | E11 | p2 | nothing (its Lottie slice: `engine-contracts:EC-f`) | Flare A2, SVG import in Flare, Halo and Design, vector paste | file when ready | planned |
| 5 | A disk preview store with offline volumes (new `coreasset/thumbnail-store`) and a perceptual hash with duplicate groups | `preview-cache.md` | E12 | p2 | nothing (its hash slice: `engine-contracts:EC-a`) | Library previews, offline drives and the duplicate finder | file when ready | planned |
| 6 | Mask feather, outlines, mattes from alpha or luma, the masked composite; vector layer masks and track mattes | `masks-mattes.md` | E2; Photo CR-3, CR-4, CR-6 | p1 | engine-contracts | S4, S5 (Halo, Flare, Photo, Design) | file when ready | planned |
| 6 | The colour family: vibrance, Hue/Sat (moved from Photo), HSL, B&W, mixers, colour balance, gradient map, LUT, posterize, threshold, invert, auto tone | `tone-pack.md` | E3; Photo CR-5 | p1 | engine-contracts | S1, S3 (Photo, Library, Halo) | file when ready | planned |
| 6 | The effect family: box and motion blur, denoise, clarity, glow, shadows, stroke | `effects-engine.md` | E4 (re-cut of Halo #39's pixels) | p1 | engine-contracts | S2 (Halo, Photo, Library, Design) | file when ready | built |
| 6 | The affine family: free transform, flip, canvas size, composite through a matrix | `affine-composite.md` | E5; Photo CR-1, CR-2; H6 | p1 | engine-contracts | S7, S20 (Photo, Design, Halo, Flare) | file when ready | planned |
| 6 | Flood fill, colour range and raster gradients | `fill-tools.md` | E6 | p2 | engine-contracts | Photo's bucket, wand, colour range and gradient | file when ready | planned |
| 6 | True heal, fill from surroundings, dodge, burn, sponge, smudge | `retouch-heal.md` | E7; Photo CR-7 | p2 | engine-contracts | Photo's retouch tools | file when ready | planned |
| 6 | Styled runs, paragraphs, type on a path, layout from measured advances, SVG text | `text-engine.md` | E8 (core half) | p1 | engine-contracts, path-geometry | creative-apps `shell-text`, S21, every app's text tool | file when ready | planned |
| 6 | Colour, stroke and shape-morph keys, their sampling and export | `animate-properties.md` | E14 | p2 | engine-contracts, path-geometry | S16; Flare's inspector keys | file when ready | planned |
| 6 | ICC profiles (new `corecolor/icc-profiles`), assign and convert, 16-bit PSD and ORA | `color-profiles.md` | E13 | p2 | layered-codecs | Photo's profiles and 16-bit documents | file when ready | planned |
| 5 | PNG and JPEG on Foundation alone (pure-Swift inflate and deflate) in `coreraster/codecs` | `image-codecs.md` | beta-80 W0 (AI-accessible first): Linux headless I/O | p0 | nothing | creative-apps `adopt-command-catalog` AC-p2 and AC-l3 (Photo and Library headless), the `afterglow` CLI's pixel expectations and the real-jobs suites on Linux | #562 | built |

What the apps wait on, mapped to the task that closes each issue:

| app task | waits on (creative-core) | closed by | ready when |
|---|---|---|---|
| Photo `photo-edit` (creative-apps #1075): the PB-15 and PB-16 release gates | #309 | RT-5 (the API lands in RT-2 and RT-3) | `main` holds RT-2 and RT-3; then creative-apps files the one adoption PR the packet describes |
| Flare LM-10 `LiveLibrary` | #226 | SM-2 | `main` holds SM-2 (`state-machine` build wave **a**) |
| Flare LM-11 `LiveMachines` | #220, #221, #222, #223, #224 | SM-1, SM-3, SM-4, SM-5, SM-6 | `main` holds SM-6 (build wave **e**) |
| Flare LM-12 `LivePreview` | #225 | SM-7 | `main` holds SM-7 (build wave **b**) |
| Flare LM-8 `LiveOnion` | #218 | MT-1 | `main` holds MT-1 (`motion-tracks` build wave **a**) |
| Flare LM-13a `LiveExport` | #227 | MT-4 | `main` holds MT-4 (build wave **c**) |
| Flare IN-1 and IN-7 model budgets | #228 | MT-5 | `main` holds MT-5 |
| creative-apps `canvas-host` CH-10 (the live `MetalPresenting`) and each app's "Model draws through a `RenderDispatcher`" adoption | render-backend | RB-5 (the dispatcher), RB-7 (`feature-done`) | `main` holds RB-7; then one `scripts/bump-core` PR in creative-apps |
| creative-apps Settings > Rendering: Automatic and GPU draw on Metal | metal-backend | MB-3 and MB-4 (display and composite), then each family's last task | `main` holds the family; each lands in the apps through its own bump |

**The apps build against creative-core `main`**, which moves only when full
CI on `dev` is green. The lane dispatches that run after every 10 merged
PRs, after a `feature-done` merge, and daily; wave 2 opens about 18 PRs, so
at least one mid-wave run is expected. A lead whose closing PRs for an app
task have merged tells the supervisor, which files or wakes that app's
feature once `main` holds them.

## Waves 5 and 6: the beta-80 W1 engines (2026-10-18)

The captain approved the beta-80 plan (`paw-workspace/docs/design/drafts/2026-10-18-beta-80-plan.md`)
on 2026-10-18. Its W1 wave is these fourteen packets; the suite's media and
text halves (E9, E8's Core Text and the font picker) are creative-apps
packets (`docs/blueprints/suite/features/shell-media.md`, `shell-text.md`,
`docs/blueprints/suiteui/features/font-picker.md`). Base: `origin/dev`
4f91e04.

- **One contract first.** Four engines widen the `RenderBackend` contract
  and three add FlareCore model fields, and each of those changes lands in a
  file all of them would otherwise share (`RenderOp.swift`,
  `RenderBackend.swift`, `ToneAdjustment.swift`, `FakeBackend.swift`,
  `RenderDispatcher.swift`, `CPUBackend+Ops.swift`, `ParitySamples.swift`,
  `Document.swift`, `FlareFormat.swift`, `CommandRegistry.swift`,
  `UndoPropertyTests.swift`, the two exporters, and the `image-ops`,
  `compositing` and `corerender` parts). `engine-contracts` makes every one
  of those edits once, with stubs and one seam file per family, so the nine
  wave-6 features own disjoint files and run at once.
- **CPU first, Metal later.** The four new families (`maskedComposite`,
  `affine`, `effect`, `color`) are in `RenderOp.notOnMetalYet`; Metal
  claims none of them, so the dispatcher sends them to the CPU and
  `everyFamilyIsOn` stays green. R2 (beta-80 W4) ports them one family at a
  time and removes each from the set.
- **Wave 5 runs beside the contract.** `path-geometry`, `layered-codecs`,
  `vector-import` and `preview-cache` touch no seam file, so they start with
  `engine-contracts` (their few slices that need a seam name it).
- **No shared status line.** Each W1 feature's last task sets the
  `**Status:**` line in its own packet, not this table, so nine
  `feature-done` PRs never conflict here; this table's status column is
  refreshed by the supervisor.

| file | owner in waves 5 and 6 |
|---|---|
| the seam files above, `W1Model.swift`, `W1Values.swift`, the four `CPUBackend+<Family>.swift` and `Samples+<Family>.swift` stubs, the five exporter seam files, `MaskCommands.swift`, `TextStyleCommands.swift`, `TrackCommands.swift` and their test files (created) | `engine-contracts` (wave 5), then the wave-6 feature its name says |
| `Sources/FlareCore/PathOps/`, `Geometry.swift`, the `flarecore/geometry` part | `path-geometry` (`masks-mattes`' MM-10 edits the part after it) |
| `Sources/CoreRaster/Codecs/`, the `coreraster/codecs` part | `layered-codecs` (`color-profiles` after it) |
| `Sources/FlareCore/Import/`, the `flarecore/import` part | `vector-import` |
| `Sources/CoreAsset/Thumbnails/`, `Sources/CoreRaster/Hash/`, the `coreasset/thumbnail-store` part | `preview-cache` |
| `Sources/CoreRaster/{Masks,Compositing/CompositeMasked}`, `RenderList.swift` | `masks-mattes` |
| `Sources/CoreRaster/Tone/` | `tone-pack` |
| `Sources/CoreRaster/Effects/` | `effects-engine` |
| `Sources/CoreRaster/Affine/`, `Compositing/CompositeAffine.swift` | `affine-composite` |
| `Sources/CoreRaster/Fill/` | `fill-tools` |
| `Sources/CoreRaster/Heal/` | `retouch-heal` |
| `TextLayout*.swift`, `TextStyleCommands*.swift`, `SVGExporter+Text*.swift` | `text-engine` |
| `TrackCommands*.swift`, `Sampling+Tracks*.swift` | `animate-properties` |
| `Sources/CoreColor/ICC/`, the `corecolor/icc-profiles` part | `color-profiles` |
| new test files and `Tests/mutations/<plan>.json` files, `Tests/CoreRenderTests/Golden/<family>/` | the task that names them |

## Why this order

- **Three features at once.** Their files don't meet (table below).
  `raster-throughput` stays in CoreColor and CoreRaster. `state-machine`
  owns the command layer's shared files (`Command.swift`,
  `CommandRegistry.swift`, `CommandRegistryTests.swift`,
  `UndoPropertyTests.swift`, `CommandFuzzTests.swift`). `motion-tracks` owns
  the Lottie exporter, a new `Onion.swift` and a new budget test, and adds
  no command.
- **raster-throughput first when slots are short.** It is the one `p1`:
  Photo's `photo-edit` is building, and its Copy plus Paste of 12 MP takes
  about 390 ms against PB-15's 120 ms (#309).
- **One command chain inside state-machine.** Every task that adds a command
  edits `CommandRegistryTests.swift` and `UndoPropertyTests.swift`, so those
  tasks run one after another. `RenameSymbol` (`p2`, LM-10) goes first, then
  machines, states, transitions and inputs, which is the issues' own order.
  The issues' old `Depends on: #217` was one registry line each; `dev`'s
  per-family lists removed that, and #217 is closed. The issues query and
  the player touch neither file and run beside the chain.
- **Lottie tasks in a row, budgets last.** The three Lottie tasks share
  `LottieExporter.swift`, so they chain; onion frames run beside them; the
  budgets come last so QB-L8 times the exporter that ships.

- **Waves 3 and 4 (dual renderer, 2026-10-17).** `render-backend` is small and
  Linux-safe and gates everything GPU; it runs as soon as a slot opens.
  `metal-backend` is one lead's slow line: many small slices, one op family
  each, never more than one or two PRs in flight, so the apps stay shippable
  on CPU after every merge. Its `Package.swift` edit (RB-1) is a protected
  path: the supervisor merges that PR.
- **Runner answer (metal-backend, MB-2).** The hosted macOS runner exposes a
  Metal device (Apple Paravirtual device; dev CI run 39010063417 first ran
  `MetalPipelinesTests` there), and the "Metal (macOS)" PR check from #414
  builds and tests CoreRenderMetal on it for every Metal PR, so the parity
  suite runs in CI, not only on the lead's Mac. The budgets
  (`MetalBudgetTests`) run release-only, so CI's debug build skips them; the
  Mac finisher runs and records them.
- **Metal-backend parity counts (MB-17).** 11 parity families
  (`ParityTests.families`, bound one to one by `familiesAreBoundToTests`)
  with 20 device-gated parity tests, `everyFamilyIsOn` among them, and no
  disabled family. The Linux-safe helpers are planted in 17
  `Tests/mutations/CoreRender*.json` plans, 121 entries: AdjustTable 7,
  BlurTable 5, CPUBackend 5, CPUBackendOps 13, CompositeMap 5, Dispatcher 12,
  DisplayTable 4, Fake 9, HalfFloat 6, MetalCapabilities 8, OpaqueRows 4,
  Parity 11, PipelineKey 5, ResampleTable 5, SurfaceTiling 11, TileMap 4,
  Unsharp 7. `scripts/ci` on Linux runs 1048 tests.

## Issue housekeeping (each lead, stage 0)

- Add `in-progress` to every issue its packet covers, so the Belt mandate
  doesn't race the lead with a task worker on the same issue.
- Edit the stale `Depends on:` lines and comment with a link to the packet:
  #221 ("#220 (LC-11a), #217 (LC-8)") now depends on #220 only, inside the
  packet; #226 ("#217 (LC-8)") and #228 ("#213, #214, #173, #219") depend on
  nothing open. #222 to #224 keep their chain, which the packet keeps as
  test-file stacking.

## Files across the features (wave 2)

| file | owner in wave 2 |
|---|---|
| `Sources/CoreColor/DisplayTransfer.swift`, `Sources/CoreRaster/DisplayBytes.swift`, `Composite.swift`, `PixelBuffer.swift`, their tests, `Tests/CoreRasterTests/RetouchBoundsTests.swift`, `Tests/CoreRasterTests/Support.swift`, `Tests/mutations/CoreRaster.json`, `docs/c4/parts/creative-core/corecolor/`, `docs/c4/parts/creative-core/coreraster/` | `raster-throughput` |
| `Sources/FlareCore/StateMachine.swift`, `StateMachineValidation.swift`, `SymbolCommands.swift`, `Command.swift`, `CommandRegistry.swift`, `Timeline.swift`, and the new `StateMachineIssues.swift`, `StateMachineCommands.swift`, `MachineStateCommands.swift`, `TransitionCommands.swift`, `MachineInputCommands.swift`, `MachinePlayer.swift` | `state-machine` |
| `Tests/FlareCoreTests/CommandRegistryTests.swift`, `UndoPropertyTests.swift`, `CommandFuzzTests.swift`, `SymbolCommandsTests.swift`; `docs/c4/parts/creative-core/flarecore/statemachine.json`, `symbols.json`; `docs/engineering.md` | `state-machine` (SM-1 also writes `Onion.swift` into engineering.md's evaluation list for `motion-tracks`) |
| `Sources/FlareCore/Export/LottieExporter.swift`, the new `Onion.swift`, `docs/c4/parts/creative-core/flarecore/timeline.json`, `export.json` | `motion-tracks` |
| new test files and new `Tests/mutations/<plan>.json` files | the task that names them (the names don't overlap) |

`Timeline.swift` stays with `state-machine` (the player's errors join
`TimelineError`), which is why onion frames live in a new `Onion.swift` as
an extension of `Timeline`.

## Not in a packet

- **#304** (stage-geometry follow-ups) touches `RenderList.swift`,
  `Marquee.swift`, `WorldBounds.swift`, `Geometry.swift` and `Instance.swift`.
  No wave-2 packet touches those files, and none is about the render list's
  names or mutants, so it stays a `gap` issue for a task worker.
- **#305** (command-code gaps) touches `LayerCommands.swift`,
  `SceneCommands.swift`, `ShapeCommands.swift`, `Document.swift` and
  `FlareFormat.swift`, which no wave-2 packet touches. It stays a `gap`
  issue. A worker that picks it up while `state-machine` runs should rebase
  on that feature's `Command.swift` changes if it adds a `ModelError` case.
- **#212** (DOC-2, copy G45 to G54 into `docs/gaps.md`) is a docs task with
  no code; no packet edits `docs/gaps.md`. Once `motion-tracks` lands, G46 and
  G52 are done.
- **Later, no issue yet:** Histogram's sRGB axis still encodes per pixel
  (it can adopt `DisplayTransfer`); Lottie export of animated tracks inside
  symbols; creative-apps' adoption PR for `raster-throughput`, which that
  repo files.

## The lead contract

Every feature lead and every task below codes against this. It is handed
verbatim to every session, and each feature issue carries it.

1. **Feature issue.** One GitHub issue per feature, labels `feature-lead` and `line:<app>`. Body links the packet `docs/blueprints/<app>/features/<feature>.md` and has one `Depends on:` line.
2. **Run.** Belt runs one cloud session per feature issue (a lead), from the trusted launch folder, with the repo's Auto settings (creative-apps#733, creative-core#263). A lead holds one in-flight slot however many PRs it opens.
3. **Status channel.** The lead pushes `docs/leads/<feature>/RECORD.md` and `timeline.tsv` to branch `lead/<feature>` after every stage. Belt reads the branch's last commit time; nothing else is polled besides PRs and issue comments.
4. **Swarm PRs.** Base `dev`, label `fast-lane`, at most 400 lines and 15 files. Body lines: `Belt-Lead: <run id>`, `Feature: <feature>`, then `Fast-Check: pass` and `Head: <full sha>` after `scripts/ci` passes. The lane merges them. Nobody merges into dev by hand or by an agent.
5. **Review policy (decision for the captain).** `Belt-Lead:` PRs do not need the `belt/review` status. The lead's own critic panel is the review. Only `Belt-Run:` and `Belt-Test:` PRs keep it.
6. **Done.** All three: a `Belt-Lead:` PR labelled `feature-done` has merged; the CI run it triggered on dev is green; the lead commented on the feature issue with a line starting `Belt-Contact-Sheet:` and the run link.
7. **Stall.** No commit on `lead/<feature>`, no PR event and no issue comment for 30 min: Belt sends one nudge with `claude -p --cloud <session id> "<resume text>"`. A second stall: relaunch with a resume brief that says "read RECORD.md, continue from the last stage". A third: label the issue `needs-human` and stop.
8. **Timeouts.** Lead runs: 8 h wall clock, no 1 h no-PR rule. Task runs keep today's 4 h and 1 h.
9. **Brief rules.** Step one checks out the integration branch and verifies the base SHA. Set the repo-local identity "Prakash Dalai" / `86671543+prakashUXtech@users.noreply.github.com`. No attribution line anywhere, comments included. Fixers run the full harness before handing back. The Anatomy loop stops after 2 clean rounds or 4 rounds total; once a round is clean, add no new critics. One critic lens is first-use clarity: "what does each number and label mean to someone new?". Agents never treat a chat message as a reason to stop or skip a merge; questions go to the supervisor.

## Wave 5, W0 row: AI-accessible first (2026-10-19)

The captain's call that every action is a command, driven alike by the
menus, the `afterglow` CLI and the MCP server, became the beta-80 plan's
W0 (`paw-workspace/docs/design/drafts/2026-10-18-beta-80-plan.md`). Its
command layer lives in creative-apps (`suiteui/command-catalog`,
`suite/afterglow-cli`, `suite/afterglow-mcp`, `suiteui/adopt-command-catalog`).
FlareCore needs no change: its `CommandEngine` stays Flare's document
engine, and the catalog takes its envelope, id rule and error contract as
they are. Core's one piece is `image-codecs`: without a Foundation-only PNG
codec, Photo and Library can't open or write a real file on Linux, so the
CLI and the real-jobs suites couldn't run there. It owns new files in
`Codecs/` only and waits on nothing.
