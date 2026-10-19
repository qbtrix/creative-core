# Feature lead playbook

A **lead** is one cloud session that takes 1 to N engine features of one line
(3 by default; contract rule 19) from their packets to merged, CI-green,
reviewed features. Belt starts it from the features' `feature-lead` issues. The lead plans the work, runs a swarm of builder agents that each open
one small PR, then runs the Anatomy loop (gate, test suite, mutation, critics,
fixers) until the feature holds up, and ends with the contact sheet.

The lead is an orchestrator. It writes plans, prompts and RECORD.md, not
feature code. Builders and fixers write code. The fast lane merges. Nobody
merges into `dev` by hand, and no agent ever merges.

Everything in CLAUDE.md and `docs/engineering.md` still holds for every agent
the lead starts: everything is a command with an exact undo, never crash,
Linux-safe Foundation only (Metal only in `CoreRenderMetal`), old files keep loading, a C4 owner for every new
source file, a mutation entry for every new invariant, one behavior per PR.

## Which loop

Look for a `## Slices` table in the packet.

- **With one (v3).** Contract rules 12 to 19 apply, done has two levels
  (rule 6), and the stages run as in "Stages in v3" below.
- **Without one (v2).** The stages below as written, and rule 6's v2 line.
  Rule 18 still applies: the first wave declares the signatures callers
  need, as stubs.

## The lead contract

Hand this to every session (the lead and each agent it starts) verbatim.

1. **Feature issue.** One GitHub issue per feature, labels `feature-lead` and `line:core`. Body links the packet `docs/blueprints/core/features/<feature>.md` and has one `Depends on:` line.
2. **Run.** Belt runs one cloud session per group of 1 to N feature issues on one line (a line lead, rule 19), from the trusted launch folder, with the repo's Auto settings (creative-apps#733, creative-core#263). A lead holds one in-flight slot however many PRs it opens.
3. **Status channel.** The lead pushes `docs/leads/<feature>/RECORD.md` and `timeline.tsv` to branch `lead/<feature>` after every stage. Belt reads the branch's last commit time; nothing else is polled besides PRs and issue comments.
4. **Swarm PRs.** Base `dev`, label `fast-lane`, at most 400 lines and 15 files. Body lines: `Belt-Lead: <run id>`, `Feature: <feature>`, for a v3 packet `Slice: <slice ids, comma separated>`, the `Mutate:` score lines (rule 14), then `Fast-Check: pass` and `Head: <full sha>` after `scripts/ci` passes. The lane merges them. Nobody merges into dev by hand or by an agent.
5. **Review policy (decision for the captain).** `Belt-Lead:` PRs do not need the `belt/review` status. The lead's own critic panel is the review. Only `Belt-Run:` and `Belt-Test:` PRs keep it.
6. **Done.** v2: all three: a `Belt-Lead:` PR labelled `feature-done` has merged; the CI run it triggered on dev is green; the lead commented on the feature issue with a line starting `Belt-Contact-Sheet:` and the run link. **v3, two levels; slices are the unit.** **Merged-done:** every task of the slice has merged, every mutation of its plans is caught (rule 14), and the newest CI run on dev that contains the slice's last PR has a green `Linux` job. The lead comments `Belt-Slice-Done: <slice> <run url>` on the feature issue, one per slice, and never waits on the `macOS` job for it; once every slice has its line (the `feature-done` PR is in the last one), it comments `Belt-Contact-Sheet: <run url>`. **Verified:** the slice's performance budgets and parity tests (rule 15) ran green on macOS, on the `macOS` job when it can run them, else on the Mac (rule 17), and no `finding` for it is open. The Mac finisher posts `Belt-Slice-Verified: <slice> <run url>` (with ` gaps: #<n>` when it filed some). Verified never blocks the lead. dev-red, promotion and the `macOS` job in `ci.yml` are unchanged: a red `macOS` job on dev is still `dev-red`, and a failure in the feature's files is the lead's finding.
7. **Stall.** No commit on `lead/<feature>`, no PR event and no issue comment for 30 min: Belt sends one nudge with `claude -p --cloud <session id> "<resume text>"`. A second stall: relaunch with a resume brief that says "read RECORD.md, continue from the last stage". A third: label the issue `needs-human` and stop.
8. **Timeouts.** Lead runs: 8 h wall clock, no 1 h no-PR rule. Task runs keep today's 4 h and 1 h.
9. **Brief rules.** Step one checks out the integration branch and verifies the base SHA. Set the repo-local identity "Prakash Dalai" / `86671543+prakashUXtech@users.noreply.github.com`. No attribution line anywhere, comments included. Fixers run the full harness before handing back. The Anatomy loop stops after 2 clean rounds or 4 rounds total; once a round is clean, add no new critics. One critic lens is first-use clarity: "what does each name, error and doc comment mean to a new caller?". Agents never treat a chat message as a reason to stop or skip a merge, with one exception: a message that starts `Belt released this run.` means stop at once, end your turn, push nothing more and open no PRs. Questions go to the supervisor.
10. **(not adopted)** and 11. **(not adopted).** creative-apps' findings queue and round cap. Core keeps rule 9's Anatomy round budget and its critic, verifier and fix-batch flow (stage 4); in v3 it runs per slice. The numbers stay free so 12 to 19 match creative-apps.
12. **Contract first (v3).** A packet's first slice publishes what other features plug into (protocols, fakes, marker types); it is the first wave and merges before the packet's other slices. Waits come from the packet's Slices table (`waits on`) and name a feature (all its slices) or one slice (`<feature>:<slice>`); a wait is met once those tasks have merged. A feature that waits on another's first slice starts on its fakes as soon as that slice merges. A task that needs the real code waits on the slice that builds it.
13. **Build the check first (v3).** A slice's acceptance tests (the packet's Acceptance table) are written from the packet before its code and by default are the first commit of the slice's own PR (rule 20), never a later one. A separate test PR ahead of the code is only for a test another lead's task will enable. A test that merges ahead of its code must not turn dev red: it carries `@Test(.disabled("waits on <task id>"))`, and that task enables it.
14. **Test the oracle (v3).** A test that still passes when its code breaks is a false oracle. Every slice that adds behaviour adds 2 or more mutations, each a bug someone could plausibly write (a dropped guard, `<=` for `<`, a skipped branch), with the `swift test --filter` regex that must catch it. They go in the task's own plan, `Tests/mutations/<Plan>.json` (the name the packet gives, e.g. `CoreRenderCPUBackend.json`), an owned file of that task, so two tasks never share a plan. Before the PR the builder runs `scripts/mutate --run --plan <plan>` until every entry is caught and ends the body with `Mutate: 5/5 <Plan>`. An escape is a missing test: add it; drop an entry only when the change can't alter behaviour. Code Linux can't build (Metal shaders, `CoreRenderMetal`) is covered by parity tests instead (rule 15); its Linux-safe parts in `CoreRender` take mutations as usual.
15. **Budgets and parity (v3; core's feel gate).** Part of Verified (rule 6); never blocks the lead. Core has no screens, so a slice is verified when (a) **budgets:** every row of the packet's Quality tests holds. Count budgets (allocations, copies, ops) are ordinary tests and gate in `scripts/ci`; time budgets (release only, `.serialized`, e.g. "dispatcher overhead ≤ 2%") are reported, not gated, and the Mac finisher times them on a release build. (b) **parity:** a backend slice's parity tests ran green against the CPU goldens within the packet's tolerance on a device (the `macOS` job if it has one, else the Mac), and the feature issue has its counts and worst delta. A parity test that skips for lack of a device is not green. (c) the critic panel's clarity lens (rule 9) found nothing open in the slice's public API.
16. **Shared module first (both loops; core's SuiteUI first).** Code more than one module or app needs goes in the lowest shared module that fits (CoreColor, CoreRaster, CoreRender), never a copy per module or per backend. A backend reuses CoreRaster's math (kernel builders, transfer tables, blend formulas) as data, not a re-derivation. The duplicate check in `scripts/ci` and the critic panel's reuse lens enforce it.
17. **Mac finishing (v3 slices Linux can't prove).** A slice whose code or checks need macOS (anything in `Sources/CoreRenderMetal/`, a parity suite, a release-only time budget) gets a Mac finisher pass before it is verified; the lead never waits on it. Once the slice is merged-done, the lead comments `Mac-Finish-Wanted: <slice> <run url>` and moves on. The finisher, a session on the Mac with Xcode, checks out `origin/dev`, runs `scripts/ci` and the slice's parity and budget suites on a release build, and checks every `Unverified API:` line in the slice's PR bodies against Apple's docs. It fixes what it finds in fast-lane PRs with the slice's `Slice:` line, then comments `Mac-Finish: <slice> <dev sha>` (or `... gaps: #<n>`), and `Belt-Slice-Verified:` when rule 6 holds. Finisher PRs don't count against the round budget.
18. **Backends and callers in parallel (both loops; contract widening).** After the contract slice, the backends and the callers run as parallel waves; neither waits on the other. The contract slice declares every signature the backends and callers need, as stubs: a stub returns the fake's value or throws the module's error with a reason (`RenderError.unsupported(op)`). Later slices fill in bodies and never change signatures. When a packet's contract slice misses one (every v2 packet and many v3 ones), the lead's first task is "declare the stubs", and once it merges the rest run in parallel. An engine feature has no UI slice: its packet says `ui_slice: none` and names the app feature that is its screen.
19. **Line lead (the default).** A lead takes 1 to N features of one line at once (N is 3 by default), each issue labelled with that line and linking its packet; its brief lists them under `Features:`, one `#<n> <title> <packet path>` per line. A packet may ask for a line of its own (metal-backend: one dedicated lead, slices one or two at a time). The lead makes one wave plan across its features; tasks of different features share a wave only when they own disjoint files. Bookkeeping stays per feature: its own `lead/<feature>` branch and RECORD.md, its own `Belt-Slice-Done:` lines and contact sheet, and one feature per PR. When one feature blocks, the lead keeps going on the others and says so on that feature's issue and in its RECORD's `Open`.
20. **Slice PRs (both loops).** Ship one PR per slice. Its first commit adds the failing test; later commits make it pass. Aim for 150-400 changed lines; fold any same-feature change under 50 lines into your next slice PR instead of its own PR. Open a test-only PR only for a contract test another lead will implement. After you open a slice PR, start the next slice at once on a branch stacked on it (rebase.updateRefs is on; the lane integrates). Never wait on CI. If the lane ejects one of your PRs with needs-fix, fix it first and restack the slices above it. Why: each PR costs a macOS CI slot; a test-first pair as two PRs doubled the factory's PR count (2026-10-19, docs/design/drafts/2026-10-19-agent-change-flow.md in paw-workspace).
21. **Waits are re-read, never assumed.** On every poll, re-read each thing you wait on from its source (`gh issue view`, `gh pr view`, the run) and start the work the moment it clears. Never repeat a "blocked" line from memory. Three identical blocked polls in a row means you stop polling and post one `Question for the supervisor:` comment on the feature issue naming the wait and what you would do instead, then work on another slice or feature you hold. Waiting on CI is never a reason to idle (rule 20).

## What you can and can't do here

- **Linux builds and tests everything but Metal.** Core is engine code: every
  module builds and every test target runs on Linux, except
  `CoreRenderMetal`, which builds empty there; its tests and parity suites
  run only on macOS (the `macOS` job, or the Mac, rule 17). `scripts/ci` is the whole gate
  (no-crash lint, C4 ownership, duplicate check, build, all tests), and
  `scripts/mutate` plants the bugs from `Tests/mutations/*.json`. You can run
  both yourself on any `dev` SHA, so a round never waits on CI to learn
  whether the engine holds.
- **Only the macOS build waits for CI.** The `macOS` job (an older Xcode's
  Swift 6.1) and the full `Mutation` job run only in the CI run on `dev`.
- **You can't dispatch CI** (the API answers 403). The lane dispatches it, at
  most once per lane run, after it merges a PR labelled `feature-done` or
  the 10th merged PR since the last CI run's head.
- **You can read runs.** `gh run list --workflow ci.yml --branch dev`, then
  `gh run view <id> --log-failed`; or the GitHub MCP `actions_*` and
  `get_job_logs` tools. Core uploads no screenshots; job logs are the record.
- **Worktrees start from the default branch,** not from `dev` or your base.
  Every agent's first step checks out `origin/dev` and verifies the base SHA
  (pilot lesson). The templates do this for you.

## Stages

Push RECORD.md and a `timeline.tsv` line to `lead/<feature>` at the end of
every stage, and at least every 20 minutes while you wait on CI or the lane,
so Belt never reads a quiet lead as a stall.

### 0. Set up

1. `git fetch origin dev && git rev-parse origin/dev`. That SHA is the base.
2. Set the repo-local identity (contract rule 9).
3. If `origin/lead/<feature>` exists, this is a resume: check it out, read
   RECORD.md and continue from its last stage. Otherwise create `lead/<feature>`
   from the base and write RECORD.md from the template below.
4. Check the issue's `Depends on:` line. If that issue is still open, comment
   so on the feature issue, record it, and stop.

### 1. Read the packet

Read the packet `docs/blueprints/core/features/<feature>.md`,
`docs/engineering.md`, `docs/review-rubric.md`, the C4 model (`docs/c4/model.json`, generated from `docs/c4/parts/`), the
`docs/gaps.md` entries it names and the code the tasks touch. Copy the
packet's tasks, acceptance tests and quality bars into RECORD.md. A task that
needs a new module or dependency, or edits a protected path, needs an issue
that approves it (CLAUDE.md), not a task. A task that needs app code becomes
a `needs-ui` issue in creative-apps.

### 2. Plan waves

Group the tasks into waves. A wave is a set of tasks that touch disjoint files
and don't depend on each other's unmerged code. Usually two: model types and
their codecs first, then the commands, evaluation and export that use them.
Prefer a new file per task (one per command family) over appending to a
shared one. Each task gets: an id, one behavior, the files it may touch, the
test that proves it, the mutation entry it adds when it brings an invariant,
and a size estimate under 400 lines and 15 files. Split anything bigger.

### 3. Build waves

For each wave run `docs/factory/workflows/build-wave.js` with the Workflow
tool (or one subagent per task with `isolation: "worktree"` if Workflow is
unavailable). One builder per task, in its own worktree, one PR per task
under contract rule 4. Then:

1. Wait for the lane to merge every PR of the wave. A PR the lane comments on
   (conflict, red, not eligible) goes back to its builder or a fixer: rebase
   on `origin/dev`, rerun `scripts/ci`, move the `Head:` line.
2. The next wave's base is the new `origin/dev` SHA. Record it.

### 4. The Anatomy loop

One round:

1. **Gate.** Check out the `origin/dev` SHA that holds every PR merged so far
   and run `scripts/ci`. It must print `CI: PASS`. A failure in the feature's
   files is this round's fix batch; any other failure goes to the open
   `dev-red` issue (CLAUDE.md, "Parallel agents").
2. **Test suite and mutation.** On the same SHA, run
   `scripts/mutate --validate` and
   `scripts/mutate --run --changed-since <the feature's first base>`. Every
   planted bug must be caught. An escaped mutant is a finding: the test that
   should have caught it is missing or too weak. If a CI run on `dev`
   contains the merges (the lane dispatches one after the 10th merge), read
   its `macOS` and `Mutation` jobs too; a red job there is a finding.
3. **Critic panel.** Run `docs/factory/workflows/critic-panel.js` on the
   feature's diff (`git diff <first base>..<SHA>`), the gate and mutation
   output and the packet. 3 to 7 lenses; the clarity lens is always one. It
   reads the public API as a new caller would: type and function names,
   error cases and their messages, doc comments, and the packet's examples.
   Critics only report; verifiers drop findings they can refute.
4. **Fix batch.** Group the confirmed findings into batches with disjoint
   files and run `docs/factory/workflows/fix-batch.js`. Every fixer runs the
   full harness before it hands back: a test that fails before the fix,
   `scripts/ci` until `CI: PASS`, and `scripts/mutate --run --changed-since
   origin/dev` with every planted bug caught. A parser or untrusted-input
   finding gets a seeded fuzz test that asserts it throws instead of
   crashing; a command finding gets a step in `UndoPropertyTests`.
5. Wait for the lane to merge the batch, then start the next round on the
   new `origin/dev` SHA.

**Round budget.** A round is **clean** when `scripts/ci` passes on the round's
SHA, every planted mutant is caught, any CI run on `dev` that contains the
merges is green, and the panel confirms no blocker or major finding. Stop
after **2 clean rounds** in a row or **4 rounds** in total, whichever comes
first. Once a round is clean, add no new critics or lenses: the next round
runs the same panel. After 4 rounds with findings still open, file each as a
`gap` issue (and a `docs/gaps.md` entry in a later PR) and finish anyway.

### 5. Finish

1. The last PR of the feature carries the `feature-done` label (a small last
   fix, the packet's status line, or the RECORD summary in the packet). The
   lane merges it and dispatches CI on `dev`.
2. When that run is green, comment on the feature issue:
   `Belt-Contact-Sheet: <run link>` plus one line per acceptance test and the
   test and mutation counts. A red run is round work, not done: back to
   stage 4 if the budget allows, else file `gap` issues and say so in the
   comment.
3. Push the final RECORD.md and stop.

## Stages in v3

The stages above, with these changes for a packet with slices:

- **2. Plan.** Take the waves from the packet's Build waves and check them
  against the code. The contract slice is wave 1 (rule 12); after it,
  backends and callers run in parallel (rule 18). Each task gets its slice,
  its acceptance test in its first code task or earlier (rule 13), and its
  2 or more mutations and plan (rule 14).
- **3 and 4. Waves and reviews.** Between waves, read the newest dev CI run.
  A slice whose tasks have all merged gets an Anatomy round (stage 4) on the
  SHA that holds them, under rule 9's budget, per slice. Its fixes go in the
  next wave beside new tasks. A slice that is merged-done gets its
  `Belt-Slice-Done:` line and, if it needs macOS, its `Mac-Finish-Wanted:`
  line (rule 17).
- **5. Finish.** The final task carries `feature-done` and sits in the last
  slice. Once every slice has its `Belt-Slice-Done:` line, post the contact
  sheet, set `Next: Mac finisher verifies <slices>`, push RECORD.md and stop.
  RECORD.md adds a `## Slices` table: `| slice | tasks | waits on | state
  (open, merged, merged-done, verified) | Slice-Done run | Mac-Finish |`.

## RECORD.md

`docs/leads/<feature>/RECORD.md` on `lead/<feature>`. Rewrite it in place;
the timeline keeps the history. A relaunched lead reads only this file.

```markdown
# <feature> lead record

Issue: #<n> · Packet: docs/blueprints/core/features/<feature>.md
Run: <Belt run id> · Session: <session id> · Started: <UTC time>
Stage: <0 setup | 1 packet | 2 plan | 3 wave <k> | 4 round <r> | 5 finish | done>
Base: <origin/dev SHA the current stage started from>
Next: <the one thing a resumed lead does first>

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |

## Decisions
- <what you chose and why, one line each>

## Open
- <blockers, needs-ui issues, gap issues filed>
```

`docs/leads/<feature>/timeline.tsv`: one appended line per event, tab
separated, header `utc	stage	event	ref	note`, for example
`2026-10-14T09:12Z	3	pr-opened	#270	task m1 keyframe hold easing`.
Events: `stage-start`, `stage-end`, `pr-opened`, `pr-merged`, `gate-run`,
`ci-run`, `round-clean`, `round-findings`, `heartbeat`, `stopped`.

## Workflow templates

In `docs/factory/workflows/`. Copy one into your scratchpad, run it with
`Workflow({scriptPath, args})`, and resume a broken run with
`resumeFromRunId`. Each file's header lists its `args`.

| Template | Stage | Does |
|---|---|---|
| `build-wave.js` | 3 | One builder per task in its own worktree, one PR each, then a checker that reads every PR against the contract. |
| `critic-panel.js` | 4 | One critic per lens over the feature's diff, gate and mutation output, then a verifier per finding that tries to refute it. Returns `clean` and the confirmed findings. |
| `fix-batch.js` | 4 | One fixer per batch in its own worktree, full harness, one PR each. |
