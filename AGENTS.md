# Agent instructions

Read [CLAUDE.md](CLAUDE.md). It is the single source of the agent rules for
this repo (start here, the loop, the rules, parallel work, the fast lane) and
applies to every coding agent, not only Claude.

The loop in one line: branch from `origin/dev`, `scripts/ci` must print
`CI: PASS`, then open one PR to `dev` with `Closes #<n>`, the `fast-lane`
label, and the lines `Fast-Check: pass` and `Head: <sha>` for the pushed head.
Never target `main`.
