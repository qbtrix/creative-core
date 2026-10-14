# Core features: waves

The nine open `p1` engine issues that block Flare's wave 2 (qbtrix/creative-apps
`docs/blueprints/flare/features/waves.md`, merged as d56aa45), grouped into
two features, one feature-lead session each (`docs/factory/lead.md`). Both
run in wave 1, side by side: they wait on nothing, and they own no file in
common. Each packet lists its tasks, owned files, acceptance tests and how it
treats the open PRs. Base: `origin/dev` 1b45592 (2026-10-14).

| wave | feature | packet | covers | waits on | unblocks in Flare | feature issue |
|---|---|---|---|---|---|---|
| 1 | What the stage draws and what a click picks | `stage-geometry.md` | #213, #214, #215, #182 | nothing | `live-stage` (with `edit-commands`) | #267 |
| 1 | Undoable edits on scene and symbol layers | `edit-commands.md` | #171, #219, #216, #217, #173 | nothing | `live-keys`, `live-scenes`; `live-stage` (with `stage-geometry`) | #268 |

Flare's "waits on" cells, mapped to the task that closes each issue:

| Flare feature | waits on (creative-core) | closed by | ready when |
|---|---|---|---|
| `live-keys` | #171, #216, #219 | EC-2, EC-6, EC-3 | `main` contains EC-2, EC-3 and EC-6 (`edit-commands` build wave **c**) |
| `live-scenes` | #217, #219 | EC-7b, EC-3 | `main` contains EC-7b and EC-3 (build wave **e**) |
| `live-stage` | #213, #214, #215, #182, #173, #216 | SG-2, SG-4, SG-5, SG-7, EC-9, EC-6 | `main` contains both features; its ST-6 needs only rectangle and ellipse, so it can start once SG-6 is on `main`, before SG-7 closes #182 |

**Flare builds against creative-core `main`** (creative-apps `Package.swift`
pins `branch: "main"`), and `main` moves only when full CI on `dev` is
green. The lane dispatches that run after every 10 merged PRs, after a
`feature-done` merge, and daily; the two features together open about 19
PRs, so at least one mid-feature run is expected. A lead whose closing PRs
for a Flare feature have merged tells the supervisor, which files that Flare
feature issue once `main` holds them.

## Why this order

- **Two features, not more.** Every task that adds a command edits
  `CommandRegistryTests.swift` (its id set and samples), and most also edit
  `UndoPropertyTests.swift`. Two features in one wave may not share a file,
  so all command work is one feature (`edit-commands`), chained on those two
  test files. Everything that reads the model to draw, pick or bound, plus
  the path builders, touches none of them, so it is the other feature
  (`stage-geometry`) and runs at the same time. A third wave-1 feature would
  have to split one of these chains and share their files.
- **Keys and scenes first inside `edit-commands`.** The issues' old
  dependencies (LC-7 after LC-6, LC-8 after LC-7) were the order of one line
  each in `CommandRegistry.builtInFamilies`. On `dev` each family lists its
  own commands in its own file, and the shape, layer and scene families are
  already registered, so only the new instance family edits
  `CommandRegistry.swift`. The chain therefore runs keyframe owner (#171),
  stroke and path, duplicate (#216), scene edits (#217), then instances
  (#173), with the two merges (#219) beside it. `live-keys` and
  `live-scenes` can be filed hours before `live-stage`.
- **Open PRs are finished, not redone.** #176 (keyframe owner) and #178
  (instance commands) are 48 to 49 commits behind `dev`, conflict with it,
  and are each just over the 400-line cap. `edit-commands` EC-1/EC-2 and
  EC-8/EC-9 split and rebase them, starting from their branches; each
  replacing PR names the one it replaces, and the lead closes the old PR
  when the replacement merges. #163 (CoreRaster `TileDiff`) duplicates #164,
  which merged and closed #156; no packet touches it.

## Issue housekeeping (each lead, stage 0)

- Add `in-progress` to every issue its packet covers, so the Belt mandate
  doesn't race the lead with a task worker on the same issue.
- Edit the stale `Depends on:` lines: #216 ("#173") and #217 ("#216") now
  depend on nothing open; their old order was registry-line stacking that
  `dev`'s per-family command lists removed. Comment with a link to
  `edit-commands.md`.

## Files across the features

| file | owner in wave 1 |
|---|---|
| `docs/c4/model.json`, `docs/engineering.md` | `stage-geometry` SG-1 (it also writes the description words for `edit-commands`' commands; `edit-commands` adds no source file) |
| `Sources/FlareCore/Geometry.swift`, `Path.swift`, `ShapeBounds.swift`, `HitTest.swift`, `Export/SVGExporter.swift`, and the new `RenderList.swift`, `HitQuery.swift`, `Marquee.swift`, `WorldBounds.swift`, `PathBuilders*.swift` | `stage-geometry` |
| `Sources/FlareCore/Commands.swift`, `KeyframeCommands.swift`, `LayerCommand.swift`, `Document.swift`, `GuideCommands.swift`, `ShapeCommands.swift`, `LayerCommands.swift`, `SceneCommands.swift`, `InstanceCommands.swift`, `Instance.swift`, `Command.swift`, `FlareFormat.swift`, `CommandRegistry.swift` | `edit-commands` |
| `Tests/FlareCoreTests/CommandRegistryTests.swift`, `UndoPropertyTests.swift`, the family test files, `Tests/mutations/FlareCore.json` | `edit-commands` |
| new test files and new `Tests/mutations/<plan>.json` files | the task that names them (the names don't overlap) |

`#178` put `Transform.isFinite` in `Geometry.swift`; EC-8 moves it to
`Instance.swift` so the two features stay apart.

## Not in a packet (later)

The other blueprint engine rows wait for Flare's later features and are not
`p1` blockers of wave 2: LC-9 onion frames (G46), LC-11a to LC-11e state
machine commands, LC-12 player, LC-12b `RenameSymbol`, LC-13 Lottie tracks,
LC-14 `FlareBudgetTests` (SG-8 and EC-10 add the stage and drag budgets it
will extend). They become the next core features once these land.

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
