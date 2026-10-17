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
| 3 | A `RenderBackend` contract, the CPU backend over CoreRaster, the dispatcher and the parity harness | `render-backend.md` | dual-renderer design 2026-10-17 (sections 1, 5) | p1 | nothing (RT-3's in-place composite is a swap, not a wait) | creative-apps `canvas-host` CH-10 (live presenter); every app's Model drawing through a `RenderDispatcher` | file when ready | planned |
| 4 | The Metal backend, one op family per slice behind capability flags, each with a parity test; one dedicated lead on its own Belt line | `metal-backend.md` | dual-renderer design 2026-10-17 (sections 1, 5, 7) | p2 | render-backend | Automatic and GPU in Settings > Rendering doing anything; big-document speed in Photo and Halo | file when ready | planned |

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
- **Runner answer (metal-backend, MB-2).** The macos-15 runner exposes a
  Metal device: dev CI run 39010063417 ran `MetalPipelinesTests` there, so
  the parity suite runs on dev's macOS job, not only on the lead's Mac.

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
