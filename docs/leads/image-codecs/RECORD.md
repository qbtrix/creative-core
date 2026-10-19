# image-codecs lead record

Issue: #562 · Packet: docs/blueprints/core/features/image-codecs.md
Run: act-1a1511a1174-tlch · Started: 2026-10-18T22:40Z
Line lead for: image-codecs (#562), preview-cache (#440, already done), vector-import (#439, VI-z left)
Stage: 3 wave 2
Base: 62a84e9 (wave 2)
Next: IC-2 (disabled suites, fixtures) building; wave 3 is IC-3 + IC-6 once it merges

## Slices
| slice | tasks | waits on | state | Slice-Done run | Mac-Finish |
|---|---|---|---|---|---|
| IC-a | IC-1, IC-2 | nothing | open | | none |
| IC-png | IC-3, IC-4, IC-5 | IC-a | open | | none |
| IC-jpeg | IC-6, IC-7, IC-8 | IC-a | open | | none |
| IC-z | IC-9, IC-10 | IC-png, IC-jpeg | open | | wanted (release budgets) |

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| IC-1 | 1 | stubs Inflate, Deflate, PNG(Info, Codec), JPEG(Info); crc32 moved to ByteReader; codecs part | Codecs/{Inflate,Deflate,PNG,JPEG,ByteReader,ZipStore}.swift, ImageCodecShapeTests, codecs.json | ImageCodecShapeTests, ZipStore tests | – | #575 (2268443) | merged |
| IC-2 | 2 | seven suites disabled, spec-built fixtures | Tests/CoreRasterTests/{Inflate,PNGRead,PNGWrite,PNGFuzz,JPEGRead,JPEGWrite,JPEGFuzz}Tests, Fixtures/{PNG,JPEG}Fixtures | suites compile | – | | building |
| IC-3 | 3 | Inflate, Deflate bodies | Inflate.swift, Deflate.swift, InflateTests | InflateTests | CoreRaster.Inflate (3) | | open |
| IC-6 | 3 | JPEG info, baseline read | JPEG.swift, JPEGReadTests, JPEGFuzzTests | baseline half | CoreRaster.JPEG (2) | | open |
| IC-4 | 4 | PNG info, read, decodePNG | PNG.swift, PNGReadTests, PNGFuzzTests | PNGReadTests | CoreRaster.PNG (3) | | open |
| IC-5 | 4 | PNG write, encodePNG | PNGWrite.swift, PNGWriteTests | PNGWriteTests | CoreRaster.PNGWrite (2) | | open |
| IC-7 | 4 | progressive JPEG | JPEGProgressive.swift, JPEGReadTests | progressive half | CoreRaster.JPEGProgressive (1+) | | open |
| IC-8 | 4 | baseline JPEG write | JPEGWrite.swift, JPEGWriteTests | JPEGWriteTests | CoreRaster.JPEGWrite (2) | | open |
| IC-9 | 5 | KJ-IC walk, budgets | ImageCodecWalkTests, ImageCodecBudgetTests | walk | – | | open |
| IC-10 | 6 | waves.md, codecs part, feature-done | waves.md, codecs.json | c4-assemble --check | – | | open |

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|

## Decisions
- Waves from the packet; IC-1 shares wave 1 with vector-import's R3-3 reader perf fixer (disjoint files: CoreRaster/Codecs vs FlareCore/Import).
- Builders run as worktree subagents, PRs through the GitHub MCP tools (the container's gh token is invalid). Builder branches `lead/image-codecs-<task>`.
- Every gate (`scripts/ci`, `scripts/mutate --run`) runs under one shared flock so wall-clock budgets see an unloaded box (previous lead's lesson).
- IC-7 has one mutation in the packet; rule 14 wants 2 or more, so its builder adds a second (e.g. DC refinement bit).

## Open
- `ZipStore.crc32` is a one-line forward (callers RawPixelCodec, ORAContainerTests are outside IC-1); a later task that may touch PixelCodec.swift can remove it.

## Notes
- 2026-10-19T00:10Z: IC-1 #575 merged 22:38Z. Helpers: `ByteReader.crc32`, internal `Deflate.adler32`; `Deflate.zlib` writes stored blocks at every level until IC-3; stubs end "waits on IC-<n>" and `ImageCodecShapeTests.stubsThrowCodecErrors` lists them, so each filling task drops its calls there; IC-10 replaces the C4 "declared stubs" sentence.
