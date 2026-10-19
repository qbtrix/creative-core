# image-codecs lead record

Issue: #562 · Packet: docs/blueprints/core/features/image-codecs.md
Run: act-1a1511a1174-tlch · Started: 2026-10-18T22:40Z
Line lead for: image-codecs (#562), preview-cache (#440, already done), vector-import (#439, VI-z left)
Stage: IC-png Anatomy round 3 (fix batch); IC-jpeg Anatomy round 4 (fix batch, last round)
Base: 9385de9 (wave 4)
Next: r3-png-b1, r3-png-b2 PRs merge, then IC-png round 4 (last allowed); r4-jpeg-b1 PR merges, which ends IC-jpeg's Anatomy loop

## Slices
| slice | tasks | waits on | state | Slice-Done run | Mac-Finish |
|---|---|---|---|---|---|
| IC-a | IC-1, IC-2 | nothing | merged-done | 384 (641739b) | none |
| IC-png | IC-3, IC-4, IC-5 | IC-a | built, round 1 | | none |
| IC-jpeg | IC-6, IC-7, IC-8 | IC-a | open | | none |
| IC-z | IC-9, IC-10 | IC-png, IC-jpeg | open | | wanted (release budgets) |

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| IC-1 | 1 | stubs Inflate, Deflate, PNG(Info, Codec), JPEG(Info); crc32 moved to ByteReader; codecs part | Codecs/{Inflate,Deflate,PNG,JPEG,ByteReader,ZipStore}.swift, ImageCodecShapeTests, codecs.json | ImageCodecShapeTests, ZipStore tests | – | #575 (2268443) | merged |
| IC-2 | 2 | seven suites disabled, spec-built fixtures | Tests/CoreRasterTests/{Inflate,PNGRead,PNGWrite,PNGFuzz,JPEGRead,JPEGWrite,JPEGFuzz}Tests, Fixtures/{PNG,JPEG}Fixtures | suites compile | – | #590, #592, #594, #599; macOS fix #607 | merged |
| IC-3 | 3 | Inflate, Deflate bodies | Inflate.swift, Deflate.swift, InflateTests | InflateTests | CoreRaster.Inflate (3) | #625 (526da94) | merged |
| IC-6 | 3 | JPEG info, baseline read | JPEG.swift, JPEGReadTests, JPEGFuzzTests | baseline half | CoreRaster.JPEG (2) | #627 (22a5fdd) | merged |
| IC-4 | 4 | PNG info, read, decodePNG | PNG.swift, PNGReadTests, PNGFuzzTests | PNGReadTests | CoreRaster.PNG (3) | #637 (b4d80e2) | merged 05:14Z |
| IC-5 | 4 | PNG write, encodePNG | PNGWrite.swift, PNGWriteTests | PNGWriteTests | CoreRaster.PNGWrite (2) | #636 (a4df142) | merged 06:10Z (2e3ac14) |
| IC-7 | 4 | progressive JPEG | JPEGProgressive.swift, JPEGReadTests | progressive half | CoreRaster.JPEGProgressive (1+) | #635 (a686651) | merged (dev 81ae63c) |
| IC-8 | 4 | baseline JPEG write | JPEGWrite.swift, JPEGWriteTests | JPEGWriteTests | CoreRaster.JPEGWrite (2) | #634 (8e31fe9) | merged |
| IC-9 | 5 | KJ-IC walk, budgets | ImageCodecWalkTests, ImageCodecBudgetTests | walk | – | | open |
| IC-10 | 6 | waves.md, codecs part, feature-done | waves.md, codecs.json | c4-assemble --check | – | | open |

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|
| 1 (IC-a) | 080366a | n/a (dev ci run 384 Linux green; Swift on dev) | n/a (IC-a has no plan) | 384 | clarity, check correctness vs specs | 0 blocker/major; 3 minor: PNGReadTests:64 comment says passes 2 and 3 empty (only 3) → IC-4; JPEG.write doc 'alpha dropped' ambiguous for premultiplied input → IC-8; InflateTests.fuzzed passes Data slices (startIndex 2) → IC-3's #625 passes it, no change | IC-4, IC-8 builders | yes (1 of 2) |
| 1 (IC-jpeg) | 81ae63c | PASS (1770 tests) | 7/7 (JPEG 2, JPEGProgressive 3, JPEGWrite 2) | - | clarity, contract, robustness, tests | 5 major (tests: EOBn runs and progressive restart untested, scan-order AC clause, coded-block bound indistinguishable, writer stuffing/ZRL untested), 7 minor (orientation doc, decimal marker messages, scan work budget, DNL/MCU guards, padding/alpha, guard mutation entries, ZZBench stray); 1 refuted | wf_4cb93cd0-ecb: b1 progressive, b2 reader guards+messages, b3 writer+ZZBench | no |

## Decisions
- Waves from the packet; IC-1 shares wave 1 with vector-import's R3-3 reader perf fixer (disjoint files: CoreRaster/Codecs vs FlareCore/Import).
- Builders run as worktree subagents, PRs through the GitHub MCP tools (the container's gh token is invalid). Builder branches `lead/image-codecs-<task>`.
- Every gate (`scripts/ci`, `scripts/mutate --run`) runs under one shared flock so wall-clock budgets see an unloaded box (previous lead's lesson).
- IC-7 has one mutation in the packet; rule 14 wants 2 or more, so its builder adds a second (e.g. DC refinement bit).

## Open
- `ZipStore.crc32` is a one-line forward (callers RawPixelCodec, ORAContainerTests are outside IC-1); a later task that may touch PixelCodec.swift can remove it.

## Notes
- 2026-10-19T00:10Z: IC-1 #575 merged 22:38Z. Helpers: `ByteReader.crc32`, internal `Deflate.adler32`; `Deflate.zlib` writes stored blocks at every level until IC-3; stubs end "waits on IC-<n>" and `ImageCodecShapeTests.stubsThrowCodecErrors` lists them, so each filling task drops its calls there; IC-10 replaces the C4 "declared stubs" sentence.
- IC-2's fixtures failed the macOS type checker (long `[UInt8]` `+` chains, a FlattenSequence conversion): dev-red #604, runs 381/383. #607 (641739b) splits them into typed intermediates; run 384 confirms. Builders keep byte chains short and typed.
- IC-3 and IC-6 also drop their rows from `ImageCodecShapeTests.stubsThrowCodecErrors` (that file is IC-1's, but the stub list names the filling task; one extra file each).
- Wave 3: IC-3 #625 (398 lines, 3/3 CoreRaster.Inflate; inflate 48 MB in 0.37 s release) and IC-6 #627 (399 lines, 2/2 CoreRaster.JPEG; 24 MP 4:2:0 in ~1.15 s release; seams for IC-7: JPEGDecoder.nextScan/scanHeader/entropy, JPEGBits, JPEGHuffman, coefficients[c] natural order, pixels(); hook line in JPEG.read) merged.
- IC-a round 2 is skipped: IC-a's files are test fixtures that wave 4 enables; their next check is each slice's own round (rule: per slice, under budget).
- Wave 4: #635 (IC-7, 3/3) and #636 (IC-5, 2/2) went dirty after #634 merged and their bodies carried an attribution footer; builders are rebasing and stripping it. #636 keeps 4 PNGWriteTests disabled "waits on IC-4" (round trips, ihdrDepthRecorded, ORA); the lead enables them after IC-4 merges.
- Budget risk for IC-9: IC-5 measured 12 MP PNG write ~8.5 s release locally (Deflate.zlib level 6 ~7.6 s on a very repetitive synthetic image) vs the 2.5 s budget. Likely long hash chains on repetitive input; IC-9 measures on the packet's image and, if over, a Deflate chain-limit fix task goes in before IC-z.
- IC-4 #637: reader in new PNGRead.swift (PNG.swift forwards); 3/3 CoreRaster.PNG; 12 MP decode 0.78 s release (budget 1.5 s). Whichever of #636/#637 merges second enables the four "waits on IC-4" PNGWriteTests.
- The GitHub MCP server appends an attribution footer to every PR body it creates; each builder strips it with update_pull_request after create.
- Stray: Tests/CoreRasterTests/ZZBench.swift came in with #625 (48 MB benchmark printing timings each test run). Route its removal into the IC-png/IC-jpeg Anatomy fix batch.
- #636 rebase: duplicate PNG.paeth (reader and writer) collapsed to the reader's copy; stubsThrowCodecErrors deleted (no stubs remain); head a4df142, CI PASS (1776 tests), PNGWrite 2/2, PNG 3/3.
- IC-jpeg r1 fix batch wf_4cb93cd0-ecb: b1 #648 (54e1a55, 12/12 JPEGProgressive, adds 64-pass scan budget), b2 #651 (4130d91, 5/5 JPEG), b3 #645 (c68428c, 7/7 JPEGWrite, merged 06:16Z). Branches use lead/image-codecs-r1-jpeg-bN (a nested name clashes with lead/image-codecs).
| 1 (IC-png) | c4baa59 | PASS (1789 tests) | 8/8 (Inflate 3, PNG 3, PNGWrite 2) | - | clarity, contract, robustness, tests | 12 confirmed, 1 refuted. Major: bloated IDAT throws tooLarge("inflate: ...") not damaged; Adam7 per-pass prior-row reset untested; PNG inflate cap at IHDR bytes untested; Deflate window guard untested and no Deflate mutation plan. Minor: lower-layer messages (no IEND/IDAT), read doc alpha and throws list, tooLarge text names no limit, level range docs, Deflate golden bytes, incomplete Huffman code, six PNG refusals untested, filter tie-break untested | fix batch wf_9d39d94a-8d4: b1 reader, b2 writer, b3 zlib | no |
| 2 (IC-jpeg) | a672a6b | PASS (1799 tests) | 25/25 (JPEG 6, JPEGProgressive 12, JPEGWrite 7) | - | clarity, contract, robustness, tests | 9 confirmed, 1 refuted. Major: progressive coefficient-store bound 384 blocks/byte (48x looser than needed, ~3.2 GB from a 33 KB file); second-SOF refusal unpinned; entropy-decoder trap guards (Huffman code space and others) untested and unplanned. Minor: scan-pass tooLarge undocumented, tooLarge texts name no limit, damaged texts use array index and joined rules, three progressiveScanChecks cases pass without their clause, short-scan guard not isolated, EXIF orientation out-of-range untested | fix batch wf_a005f679-d21: b1 JPEG.swift/JPEGWrite, b2 JPEGProgressive/JPEGDecode | no |
| IC-jpeg | 3 | 891372e | 8 (1 major, 7 minor; 1 refuted) | fix batch r3-jpeg-b1 wf_63bfcf02-52b |
| IC-png | 2 | 891372e | 9 (3 major, 6 minor; 0 refuted) | fix batches r2-png-b1, r2-png-b2 wf_5340cfcc-4ff |
| IC-png | 3 | 124c35e | 7 (2 major, 5 minor; 1 refuted) | fix batches r3-png-b1 (#696), r3-png-b2 (#692, merged) |
| IC-jpeg | 4 | 3d9c151 | 9 (2 major, 7 minor; 0 refuted); gate: local budget test outside the feature flaked, dev Linux CI green on 8cd57c6 | fix batch r4-jpeg-b1 |
