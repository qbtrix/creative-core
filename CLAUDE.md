# FlareCore: agent instructions

FlareCore is the pure-Swift engine of Flare, a Mac-native 2D vector animation
studio ("Flare" is a working name). This repo holds only the engine: document
model, commands with undo, timeline, easing, file format and export. The Mac
app lives in another repo. Many agents work here at once; these rules keep
that safe and fast. AGENTS.md points here.

## Start here

1. If you were given an issue, do that issue.
2. Otherwise pick the highest-priority open issue labelled `gap` that is not
   labelled `in-progress` (`p1` before `p2` before `p3`, then the lowest G
   number). Add the `in-progress` label to it before you start:
   ```bash
   gh issue list --label gap --state open --json number,title,labels
   gh issue edit <n> --add-label in-progress
   ```
3. The full ranked list, with acceptance tests, is `docs/gaps.md`.

## The loop

1. **Orient.** Read this file, the issue, and the code it touches. Check the
   issue's "Depends on"; if a dependency has not merged, pick another issue.
2. **Implement with tests.** Write the test from the issue's acceptance test,
   then the code.
3. **Gate.** Run `scripts/ci`. It must print `CI: PASS`. It is the only gate
   and it is what CI runs on Linux and macOS.
4. **Ship.** `git fetch origin && git rebase origin/main`, rerun `scripts/ci`,
   then open ONE small PR to `main` that closes the issue (`Closes #<n>` in the
   body). Add the label `fast-lane` to the PR. Then stop.
5. Don't ask questions. If the issue is impossible as written, comment on the
   issue saying why, remove `in-progress`, and stop.

## Rules

- **One behavior per PR.** Ideally under 200 changed lines, hard cap 400, at
  most 15 files.
- **Everything is a command.** Any change to a `Document` goes through a type
  that conforms to `Command` (see `Sources/FlareCore/Command.swift`), with
  `execute` and an exact `undo`. Add new commands to the random steps in
  `Tests/FlareCoreTests/UndoPropertyTests.swift`.
- **Never crash.** Untrusted input throws a typed error. `scripts/ci` fails on
  `try!`, `as!`, `fatalError(`, `preconditionFailure(`, `precondition(`,
  `unowned ` and `.first!` / `.last!` anywhere in `Sources/`. Also avoid
  unchecked array indexing and Int overflow on values from files.
- **FlareCore stays Linux-safe.** Foundation only, imported as
  `#if canImport(FoundationEssentials) import FoundationEssentials #else import Foundation #endif`.
  No AppKit, SwiftUI, Metal, CoreGraphics, Combine, `NSRegularExpression`,
  `String(format:)` or other Darwin-only API. Swift 6 language mode; code must
  compile with Swift 6.0 (the macOS runner's Xcode may be older than Linux's).
- **Value types and Sendable.** Model types are `struct`/`enum`, `Codable`,
  `Sendable`, `Hashable`. No classes in the model, no shared mutable state.
- **Old files keep loading.** A new model field must decode from v1 files that
  lack it (optional, or a custom `init(from:)` with `decodeIfPresent` and a
  default). Add a test that decodes a file without the field.
- **Every change gets a test.** Swift Testing (`import Testing`, `@Test`,
  `#expect`). Seeded randomness only (`SplitMix64` in `Tests/FlareCoreTests/Support.swift`).
- **Parsers get property and fuzz tests.** Anything that reads untrusted bytes
  gets a seeded fuzz test that asserts it throws instead of crashing.
- **No new dependencies** without an issue that approves them.
- **PR title** in Conventional Commits (`feat(timeline): hold easing`). The body
  says what changed, why, and which test proves it.
- **No AI attribution anywhere.** Commits, PR titles and bodies, and issue
  comments carry no `Co-Authored-By: Claude`, no `Claude-Session:` link and no
  "Generated with Claude Code" line. `.claude/settings.json` turns these off;
  if your tooling adds one anyway, delete it before you push. The fast lane
  also strips them from the squash commit.
- **Clean-room.** Never copy code, files or text from Adobe products or from
  GPL-incompatible sources. Behavior may come only from public documentation
  and specs. This repo is GPL-3.0.

## Quality

- Read `docs/engineering.md` before you write code. It holds the design rules
  for this codebase (layers, errors, reuse, validity, commands, export, tests).
- Before you open a PR, check your diff against `docs/review-rubric.md` and
  fix every "no".
- `scripts/ci` enforces the mechanical rules (no-crash lint, duplicate code,
  build, tests). The rest are review-only, and the reviewer applies the rubric.

## Parallel agents

- Many agents work at once. Keep to your issue's files. Prefer adding a new
  file (one per command family, e.g. `SceneCommands.swift`) over appending to
  a shared one; it avoids merge conflicts.
- Rebase on `main` before opening the PR, and rerun `scripts/ci` after.
- If `main` is red because of someone else's merge, do not fix it in your PR.
  Comment on your issue with the failing test name and stop.
- Never edit `.github/`, `CLAUDE.md`, `AGENTS.md`, `scripts/ci`,
  `scripts/cloud-setup.sh`, `scripts/fast-lane.sh`, `Package.swift` or
  `LICENSE` unless your issue says to. Those PRs need human review.

## Fast lane

A PR labelled `fast-lane` is merged automatically by
`.github/workflows/fast-lane.yml` when all of these hold: base `main`, author
on the allowlist in `scripts/fast-lane.sh`, at most 400 changed lines and 15
files, no protected path touched (the list above), mergeable, and every check
green including CI. Otherwise the label is removed with a comment saying why,
and the PR waits for human review. A human reviews fast-lane merges after the
fact and reverts anything wrong.

## Commands

```bash
scripts/ci                                  # lint + build + test: the gate
swift test --filter EasingTests             # one suite while iterating
bash Tests/fast_lane/test_fast_lane.sh      # fast-lane decision tests (needs jq)
```

## Layout

- `Sources/FlareCore/Document.swift`: model (Document, Scene, Layer, Keyframe, Shape)
- `Sources/FlareCore/Command.swift`: `Command` protocol, `CommandEngine` (undo, redo, groups)
- `Sources/FlareCore/Commands.swift`: built-in commands
- `Sources/FlareCore/Easing.swift`, `Timeline.swift`: tweening
- `Sources/FlareCore/FlareFormat.swift`: `.flare` JSON format v1 and validation
- `Tests/FlareCoreTests/`: one test file per area, plus `Support.swift`
- `docs/gaps.md`: the ranked work list
