# Contributing

Thank you for helping build the suite. This repo is GPL-3.0 (`LICENSE`), and
everything you contribute is released to everyone under it.

## Sign the CLA first

Every outside contribution (code, docs, tests, art) needs a signed
Contributor License Agreement before it can be merged. The agreement is in
`CLA.md`. Sign it once; it covers your later contributions to this repo and
to qbtrix/creative-apps.

How to sign: fill in and sign `CLA.md`, then send it as the maintainers
direct. The signing process is being set up together with the legal review
of the agreement; until it is ready, outside pull requests are welcome but
wait before they merge.

If your employer may own what you write, get their permission first (CLA
section 4).

### Why a CLA

The suite is open core (`docs/licensing.md` in qbtrix/creative-apps): the
core is free and GPL-3.0 for everyone, and the official build also ships closed paid modules (Team,
AI, Enterprise) next to it, which is what pays for the free core. That only
works while one owner can license the whole core both ways. The CLA gives
the owner that right for your contribution.

You keep your copyright and may use your work however you like. The CLA does
not change the core's license: your contribution stays GPL-3.0 for
everyone.

## How work is done here

`CLAUDE.md` is the working guide for everyone, people and agents: picking an
issue (ranked in `docs/gaps.md`), branching from `dev`, the `scripts/ci`
gate, the PR shape and the rules. Read `docs/engineering.md` before writing
code.
