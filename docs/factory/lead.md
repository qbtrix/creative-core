# Feature lead playbook

A **lead** is one cloud session that takes one engine feature from its packet
to a merged, CI-green, reviewed feature. Belt starts it from a `feature-lead`
issue. The lead plans the work, runs a swarm of builder agents that each open
one small PR, then runs the Anatomy loop (gate, test suite, mutation, critics,
fixers) until the feature holds up, and ends with the contact sheet.

The lead is an orchestrator. It writes plans, prompts and RECORD.md, not
feature code. Builders and fixers write code. The fast lane merges. Nobody
merges into `dev` by hand, and no agent ever merges.

Everything in CLAUDE.md and `docs/engineering.md` still holds for every agent
the lead starts: everything is a command with an exact undo, never crash,
Linux-safe Foundation only, old files keep loading, a C4 owner for every new
source file, a mutation entry for every new invariant, one behavior per PR.

## The lead contract

Hand this to every session (the lead and each agent it starts) verbatim.

1. **Feature issue.** One GitHub issue per feature, labels `feature-lead` and `line:core`. Body links the packet `docs/blueprints/core/features/<feature>.md` and has one `Depends on:` line.
2. **Run.** Belt runs one cloud session per feature issue (a lead), from the trusted launch folder, with the repo's Auto settings (creative-apps#733, creative-core#263). A lead holds one in-flight slot however many PRs it opens.
3. **Status channel.** The lead pushes `docs/leads/<feature>/RECORD.md` and `timeline.tsv` to branch `lead/<feature>` after every stage. Belt reads the branch's last commit time; nothing else is polled besides PRs and issue comments.
4. **Swarm PRs.** Base `dev`, label `fast-lane`, at most 400 lines and 15 files. Body lines: `Belt-Lead: <run id>`, `Feature: <feature>`, then `Fast-Check: pass` and `Head: <full sha>` after `scripts/ci` passes. The lane merges them. Nobody merges into dev by hand or by an agent.
5. **Review policy (decision for the captain).** `Belt-Lead:` PRs do not need the `belt/review` status. The lead's own critic panel is the review. Only `Belt-Run:` and `Belt-Test:` PRs keep it.
6. **Done.** All three: a `Belt-Lead:` PR labelled `feature-done` has merged; the CI run it triggered on dev is green; the lead commented on the feature issue with a line starting `Belt-Contact-Sheet:` and the run link.
7. **Stall.** No commit on `lead/<feature>`, no PR event and no issue comment for 30 min: Belt sends one nudge with `claude -p --cloud <session id> "<resume text>"`. A second stall: relaunch with a resume brief that says "read RECORD.md, continue from the last stage". A third: label the issue `needs-human` and stop.
8. **Timeouts.** Lead runs: 8 h wall clock, no 1 h no-PR rule. Task runs keep today's 4 h and 1 h.
9. **Brief rules.** Step one checks out the integration branch and verifies the base SHA. Set the repo-local identity "Prakash Dalai" / `86671543+prakashUXtech@users.noreply.github.com`. No attribution line anywhere, comments included. Fixers run the full harness before handing back. The Anatomy loop stops after 2 clean rounds or 4 rounds total; once a round is clean, add no new critics. One critic lens is first-use clarity: "what does each name, error and doc comment mean to a new caller?". Agents never treat a chat message as a reason to stop or skip a merge; questions go to the supervisor.

## What you can and can't do here

- **Linux builds and tests everything.** Core is engine code: every module
  builds and every test target runs on Linux. `scripts/ci` is the whole gate
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
