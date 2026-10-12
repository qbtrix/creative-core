<!-- Flare swarm pilot (round 1): what we ran, the numbers, what broke, what we learned, and the factory plan it points to. -->
# Flare swarm pilot, round 1: analysis

**Date:** 2026-10-11 · **Repo:** [qbtrix/flare-core](https://github.com/qbtrix/flare-core) (public, GPL-3.0) · **Status:** done. All 41 gaps (G0 to G40) closed. The repo was renamed to qbtrix/creative-core afterwards.

## What we ran

A raw baseline, without Belt, loom, C4 or soul:

| Part | What |
|---|---|
| Queue | 41 GitHub issues (G0 to G40) from `docs/gaps.md` |
| Workers | Claude Code cloud sessions (Ubuntu, Swift 6.3.3), one issue each, then stop |
| Gate | `scripts/ci`: no-crash lint, build and test on Linux and macOS |
| Merge | Fast lane: small, green, allowlisted PRs merge themselves into `main` |
| Supervisor | One local session (me): files issues, launches workers and rebasers, fixes the lane |

## Numbers

**Final (15:22 to 18:39 UTC, 3 h 17 min):** 42 PRs merged by the fast lane (6,810 lines), 49 PRs merged in total, all 41 gap issues closed, zero human feature merges. The tail ran slower because of the main guard's one-slot queue and starvation. The table below is the snapshot at 112 min.

| Metric | Value |
|---|---|
| PRs merged by the fast lane | **33**, with zero human merges |
| Infra PRs merged by the supervisor | 6 (lane fixes, attribution, golden fix) |
| Lines through the lane | 5,280 (median PR 152 lines) |
| Time from PR open to merge | median about 1 min, p90 25 min, max 34 min |
| Gap issues closed | 32 of 41 |
| Engine size now | about 6,200 lines of Swift (sources and tests), 22 source files, 167+ tests |
| Throughput | about **18 merges an hour** at peak; about 1 per CI cycle (about 3 min) once the main guard was on |

Extrapolated, that's 300 to 450 merges a day per repo if the queue stays full. That's echelon's range, but it's an extrapolation, not a measured day.

## What broke, in order, and the fix that is now in place

1. **Lane stalled on `mergeable: UNKNOWN`** right after another merge. Fix: retry, then sweep after merges (#32).
2. **Shared registration files** (the undo step list and the command registry) made parallel PRs conflict. Fix: per-family lists (G0, #35). Lesson: design the code so each agent owns its own files.
3. **AI attribution trailers** came from cloud sessions, which ignore local settings. Fix: repo `.claude/settings.json`, plus stripping the trailers in squash commits (#61).
4. **Linked issues didn't auto-close** on GITHUB_TOKEN merges. Fix: the lane closes them (#68).
5. **`main` went red unseen.** Two green PRs merged a minute apart broke the golden test. GITHUB_TOKEN merges trigger no CI, so nothing caught it, and **7 workers correctly stopped**. Fixes: the golden update (#69), then the main guard (#70): CI after every merge, hold while `main` is red, refresh stale PRs.
6. **Refreshed PRs stalled.** A bot push parks the PR's CI as `action_required`, so the lane never saw the CI it dispatched. Fix: read checks off the head commit (#87).
7. **Nothing re-checked refreshed PRs.** CI that the lane dispatches with GITHUB_TOKEN fires no `workflow_run`. Fix: a 5-minute schedule (#89). GitHub hadn't fired it hours later, so the supervisor dispatched sweeps by hand.
8. **Starvation.** A fresh PR that arrives green takes the merge slot, and older PRs go stale again. Fix needed: oldest first.
9. **Superseded by 6:** A bot push parks the PR's CI as `action_required`. Fix: read checks off the head commit (#87).
7. **Launcher problems.** `claude --cloud` needs a TTY (fixed with a pty wrapper), and sessions start from the local checkout's branch (fixed with a clean `origin/main` launch clone).

## Verdict

- **Workers: proven.** Cloud agents turn a well-written issue into a green, tested, 50 to 300 line PR in 3 to 10 minutes, reliably. They followed the rules, including stopping on a red `main`.
- **Fast lane: proven, after six fixes.** Every fix came from a real failure in this run. The final shape is effectively a one-slot merge queue.
- **Bottleneck moved twice:**
  - First to **integration**: conflicts and stale CI.
  - Then to the **supervisor**: a human-in-the-loop session launching, rebasing and relaunching by hand. That's the job Belt's foreman exists to do.
- **Not tested yet:**
  - UI and app work, including taste and human-like click testing.
  - A long unattended run of 12 hours or more.
  - Token cost. Measure with `/usage` before scaling.

## Lessons to carry into the factory

1. **Issues are the interface.** A precise issue with acceptance, files and dependencies is most of the quality.
2. **Ownership beats conflict resolution.** Structure code so parallel work touches different files.
3. **Guard `main`, not just PRs.** "Green PR" is not "green main". Test the combination before merging.
4. **Cloud workers ignore your machine.** Their settings, rules and tools have to live in the repo.
5. **Rules work.** Workers obeyed CLAUDE.md exactly, including the inconvenient parts. Write rules as if they'll be followed literally, because they will be.
6. **The supervisor is the product.** Everything I did by hand is the spec for Belt's foreman: fill the queue, launch, rebase, relaunch, fix the lane, curate lessons.

## Next: factory v1 (reuse first, invent as little as possible)

| Factory part | Reuse | New |
|---|---|---|
| Queue | GitHub issues + `gaps.md` | the foreman writes issues from the design docs |
| Workers | Claude Code cloud (pty launcher) | a Belt develop station "cloud" mode (#2411 seat) |
| Gate | `scripts/ci` + fast lane + main guard | packaged once as a reusable lane kit for every app repo |
| Supervisor | mandates foreman (pocketpaw) | port the pilot's manual moves into it |
| Board | Belt live feed and atlas PRs (#2432, #2433) | rows for cloud sessions |
| Human-like tests | `verify-<app>` skill pattern | XCUITest on GitHub macOS runners plus a control port per app |
| Shared cores | FlareCore + Pulley stack-pack seam (pulley#20) | a Swift stack pack; cores as Swift packages |

Apps, in order: Flare, Design, Photo, Library, Halo. Prism comes later.
