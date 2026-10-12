# FlareCore: agent instructions

FlareCore is the pure-Swift engine of Flare, a Mac-native 2D vector animation
studio ("Flare" is a working name). This repo holds only the engine: document
model, commands with undo, timeline, easing, file format and export. The Mac
app lives in another repo. Many agents work here at once; these rules keep
that safe and fast. AGENTS.md points here.

## Modules

- `Sources/FlareCore`: the animation engine (document, commands, timeline, format, export).
- `Sources/CoreColor`: color spaces and conversions, shared by every app. Depends on nothing.
- `Sources/CoreRaster`: pixel buffers, compositing and image operations. Depends only on CoreColor.
- `Sources/CoreAsset`: the shared asset model (`Asset`, `AssetRef`) and its manifest codec. Depends on nothing.
- `Sources/CoreCatalog`: the photo and metadata catalog over SQLite. Depends only on GRDB.

Each module has one error type (`ColorError`, `RasterError`, `AssetError`,
`CatalogError`) and its own test target. A new shared module needs an issue
that approves it, because it edits `Package.swift`. FlareCore must not import
the other modules yet.

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
- **Check current docs, not memory.** Before using any platform or library
  API (SwiftUI, AppKit, macOS 26 APIs, GRDB, Swift stdlib), check current docs
  with the docs MCP tools; don't rely on memory. If the tools are unavailable,
  say so in the PR body. `.mcp.json` provides them: `apple-docs`
  (`searchAppleDocumentation`, then `fetchAppleDocumentation`; Apple's
  developer docs, Swift stdlib and HIG, read live from developer.apple.com)
  and `context7` (`resolve-library-id`, then `query-docs`; GRDB is
  `/groue/grdb.swift/v7.11.1`, the version `Package.swift` pins, and Swift is
  `/swiftlang/swift`).
- **Every new source file has a C4 owner.** `scripts/ci` fails when a file
  under `Sources/` is not in exactly one component's `paths` in
  `docs/c4/model.json`. Add the file to the component it belongs to, or add a
  component, in the same PR, and keep that component's description true.
- **Everything is a command.** Any change to a `Document` goes through a type
  that conforms to `Command` (see `Sources/FlareCore/Command.swift`), with
  `execute` and an exact `undo`. Add new commands to the random steps in
  `Tests/FlareCoreTests/UndoPropertyTests.swift`.
- **Never crash.** Untrusted input throws a typed error. `scripts/ci` fails on
  `try!`, `as!`, `fatalError(`, `preconditionFailure(`, `precondition(`,
  `unowned ` and `.first!` / `.last!` anywhere in `Sources/`. Also avoid
  unchecked array indexing and Int overflow on values from files.
- **Every module stays Linux-safe.** Foundation only (CoreCatalog may also
  import GRDB), imported as
  `#if canImport(FoundationEssentials) import FoundationEssentials #else import Foundation #endif`.
  No AppKit, SwiftUI, Metal, CoreGraphics, Combine, `NSRegularExpression`,
  `String(format:)` or other Darwin-only API. Swift 6 language mode; code must
  compile with Swift 6.1 (the macOS runner's Xcode may be older than Linux's).
- **Value types and Sendable.** Model types are `struct`/`enum`, `Codable`,
  `Sendable`, `Hashable`. No classes in the model, no shared mutable state.
- **Old files keep loading.** A new model field must decode from v1 files that
  lack it (optional, or a custom `init(from:)` with `decodeIfPresent` and a
  default). Add a test that decodes a file without the field.
- **Every change gets a test.** Swift Testing (`import Testing`, `@Test`,
  `#expect`). Seeded randomness only (`SplitMix64` in `Tests/FlareCoreTests/Support.swift`).
- **Invariants get a mutation entry.** New logic with an invariant (a guard,
  a limit, a formula, an undo path) adds one entry to
  `Tests/mutations/<module>.json` in the same PR, and
  `scripts/mutate --run --only "<words from its note>"` must report it caught.
  A refactor that moves an anchor repoints it. See `docs/engineering.md`,
  "Mutation testing".
- **Parsers get property and fuzz tests.** Anything that reads untrusted bytes
  gets a seeded fuzz test that asserts it throws instead of crashing.
- **No new dependencies** without an issue that approves them. GRDB is
  approved for CoreCatalog only, pinned `exact:` in `Package.swift`; no other
  target may depend on it. On Linux it needs `libsqlite3-dev`, which
  `scripts/cloud-setup.sh` and the Linux CI job install. Ubuntu's SQLite has no
  WAL snapshots, so GRDB compiles its snapshot API out on Linux: use
  `DatabaseQueue`, `DatabaseMigrator`, records and SQL, never `DatabasePool`,
  `DatabaseSnapshotPool` or snapshot-backed observation.
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
- `scripts/ci` enforces the mechanical rules (no-crash lint, C4 ownership,
  duplicate code, build, tests). The rest are review-only, and the reviewer
  applies the rubric.

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
green including CI. A Belt PR (its body has a `Belt-Run:` or `Belt-Test:`
line) also waits for Belt's `belt/review` commit status to be success on its
head; `REQUIRE_BELT_REVIEW` in `scripts/fast-lane.sh` turns that off.
Otherwise the label is removed with a comment saying why, and the PR waits for
human review. A human reviews fast-lane merges after the fact and reverts
anything wrong.

## Commands

```bash
scripts/ci                                  # lint + C4 ownership + build + test: the gate
swift test --filter EasingTests             # one suite while iterating
bash Tests/fast_lane/test_fast_lane.sh      # fast-lane decision tests (needs jq)
scripts/mutate --validate                   # every mutation anchor resolves once
scripts/mutate --run --changed-since origin/main  # plant the bugs your diff touches
```

## Layout

- `Sources/FlareCore/Document.swift`: model (Document, Scene, Layer, Keyframe, Shape)
- `Sources/FlareCore/Command.swift`: `Command` protocol, `CommandEngine` (undo, redo, groups)
- `Sources/FlareCore/Commands.swift`: built-in commands
- `Sources/FlareCore/Easing.swift`, `Timeline.swift`: tweening
- `Sources/FlareCore/FlareFormat.swift`: `.flare` JSON format v1 and validation
- `Tests/FlareCoreTests/`: one test file per area, plus `Support.swift`
- `docs/gaps.md`: the ranked work list
