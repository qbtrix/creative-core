# FlareCore

FlareCore is the engine of Flare, a Mac-native 2D vector animation studio:
drawing, a timeline with tweens, symbols, interactive state machines, and
export. "Flare" is a working name.

This repo is only the engine, in pure Swift. It builds and tests on macOS and
Linux and depends on Foundation alone. The Mac app will live in a separate repo.

What is here now:

- a document model (scenes, layers, keyframes, simple vector shapes)
- a command engine: every change is a named command with undo, redo and grouping
- easing (linear and cubic-bezier) and keyframe interpolation
- the `.flare` file format, version 1 (JSON)

The work list is [docs/gaps.md](docs/gaps.md).

## How it is built

FlareCore is built in the open by a crew of AI coding agents working from
GitHub issues. Small, low-risk changes that pass CI can merge on their own;
changes to CI, build files, agent rules or anything risky wait for human
review. Agent rules are in [CLAUDE.md](CLAUDE.md).

## Running the checks

You need Swift 6.1 or newer. On Linux you also need the SQLite headers
(`apt-get install libsqlite3-dev`), for CoreCatalog.

```bash
scripts/ci
```

That runs a lint that rejects crash-prone code, `swift build` and `swift test`,
and prints `CI: PASS` or `CI: FAIL`. CI runs the same script on Linux and macOS.

## License

GPL-3.0. See [LICENSE](LICENSE).
