#!/usr/bin/env bash
# Tests/fast_lane/test_fast_lane.sh: fixture tests for the pure `decide`
# function in scripts/fast-lane.sh, its PROTECTED list against CLAUDE.md's
# "Never edit" bullet, and whole sweeps against a stub `gh`. No network,
# needs bash and jq.
#
# checks-green.json is a check rollup shaped like a green flare-core PR: the CI
# workflow's Linux and macOS jobs plus one SKIPPED CI job, a non-CI workflow
# check, a commit status, the fast-lane workflow's own in-progress check and a
# Copilot review check (decide must ignore the last two). Each case mutates a
# base PR / file list / rollup with jq. Most crew PRs have no CI on their head
# (CI runs on dev), so the worker's Fast-Check marker cases start from `[]`.
#
# Run: bash Tests/fast_lane/test_fast_lane.sh   (exit 0 = all pass)
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/fast-lane.sh
source "$here/../../scripts/fast-lane.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

HEAD_SHA="0123456789abcdef0123456789abcdef01234567"
BASE_PR='{"number":1,"state":"OPEN","isDraft":false,"baseRefName":"dev",
  "labels":[{"name":"fast-lane"}],"author":{"login":"prakashUXtech"},
  "additions":120,"deletions":30,"changedFiles":2,
  "mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","headRefOid":"'"$HEAD_SHA"'",
  "body":"Closes #1"}'
BASE_FILES=$'Sources/FlareCore/Timeline.swift\nTests/FlareCoreTests/TimelineTests.swift'

# check <name> <expected stdout prefix> <pr jq> <files> <checks jq>
check() {
  local name="$1" want="$2" prq="$3" files="$4" chq="$5" got
  jq "$prq" <<<"$BASE_PR" >"$tmp/pr.json"
  printf '%s\n' "$files" >"$tmp/files.txt"
  jq "$chq" "$here/checks-green.json" >"$tmp/checks.json"
  got=$(decide "$tmp/pr.json" "$tmp/files.txt" "$tmp/checks.json" 2>/dev/null)
  if [[ "$got" == "$want"* ]]; then
    echo "ok   $name -> $got"
  else
    echo "FAIL $name: want '$want*', got '$got'"; fail=1
  fi
}

check "happy path" "eligible|150|2|5 checks green" . "$BASE_FILES" .
check "claude app bot author is not allowlisted" "not-eligible|author app/claude is not on the fast-lane allowlist" '.author.login = "app/claude"' "$BASE_FILES" .
check "deny path hit" "not-eligible|touches protected paths: .github/workflows/ci.yml" \
  . $'.github/workflows/ci.yml\nsrc/x.py' .
check "deny Package.swift" "not-eligible|touches protected paths: Package.swift" \
  . $'Package.swift\nSources/FlareCore/Easing.swift' .
check "deny gate scripts" "not-eligible|touches protected paths: scripts/ci, scripts/cloud-setup.sh" \
  . $'scripts/ci\nscripts/cloud-setup.sh' .
check "deny agent rules, any case" "not-eligible|touches protected paths: docs/agents.md" \
  . 'docs/agents.md' .
check "similar names are allowed" "eligible|150|2|5 checks green" \
  . $'scripts/ci-helpers.sh\nSources/FlareCore/PackageSwiftNotes.swift' .
check "deny .claude, Package.resolved, scripts/mutate and a nested CLAUDE.md" \
  "not-eligible|touches protected paths: .claude/settings.json, Package.resolved, scripts/mutate, Sources/FlareCore/CLAUDE.md" \
  . $'.claude/settings.json\nPackage.resolved\nscripts/mutate\nSources/FlareCore/CLAUDE.md' .
check "too big (lines)" "not-eligible|too big: 401 lines" '.additions = 401 | .deletions = 0' "$BASE_FILES" .
check "too big (files)" "not-eligible|too big: 150 lines, 16 files" '.changedFiles = 16' "$BASE_FILES" .
check "non-allowlisted author" "not-eligible|author someone is not on the fast-lane allowlist" \
  '.author.login = "someone"' "$BASE_FILES" .
check "all hard rules listed" "not-eligible|author someone is not on the fast-lane allowlist;too big" \
  '.author.login = "someone" | .additions = 999' "$BASE_FILES" .
check "no checks and no marker fails closed" "pending|no passing CI check and no Fast-Check: pass marker for head $HEAD_SHA" \
  . "$BASE_FILES" '[]'
check "only non-CI checks fails closed" "pending|no passing CI check" . "$BASE_FILES" \
  '[.[] | select(.__typename == "StatusContext")]'
check "one red check" "red|Linux" . "$BASE_FILES" \
  'map(if .name == "Linux" then .conclusion = "FAILURE" else . end)'
check "red status context" "red|ci/external" . "$BASE_FILES" \
  'map(if .context == "ci/external" then .state = "FAILURE" else . end)'
check "pending check" "pending|1 checks still running" . "$BASE_FILES" \
  'map(if .name == "macOS" then .status = "IN_PROGRESS" | .conclusion = null else . end)'
check "draft PR" "skip|PR is a draft" '.isDraft = true' "$BASE_FILES" .
check "no label" "skip|no fast-lane label" '.labels = []' "$BASE_FILES" .
check "already merged" "skip|PR is MERGED" '.state = "MERGED"' "$BASE_FILES" .
check "base main is retargeted to dev" "retarget|main" '.baseRefName = "main"' "$BASE_FILES" .
check "base main without the label is left alone" "skip|no fast-lane label" \
  '.baseRefName = "main" | .labels = []' "$BASE_FILES" .
check "other base is skipped" "skip|base is release, not dev" '.baseRefName = "release"' "$BASE_FILES" .
check "mergeable unknown" "pending|not mergeable yet (UNKNOWN/UNKNOWN)" \
  '.mergeable = "UNKNOWN" | .mergeStateStatus = "UNKNOWN"' "$BASE_FILES" .
check "conflicting after an earlier merge" "conflict|$HEAD_SHA" \
  '.mergeable = "CONFLICTING" | .mergeStateStatus = "DIRTY"' "$BASE_FILES" .
check "behind dev is still eligible (no freshness rule)" "eligible|150|2|5 checks green" \
  '.mergeStateStatus = "BEHIND"' "$BASE_FILES" .
check "red CI outranks a conflict" "red|Linux" \
  '.mergeable = "CONFLICTING" | .mergeStateStatus = "DIRTY"' "$BASE_FILES" \
  'map(if .name == "Linux" then .conclusion = "FAILURE" else . end)'

# PROTECTED is exactly the backticked paths in CLAUDE.md's "**Never edit**"
# bullet, and decide refuses a file under each one.
# shellcheck disable=SC2016 # the backticks are literal markdown
claude_list=$(awk '/^- \*\*Never edit\*\*/ {on = 1} on && /^$/ {exit} on' "$here/../../CLAUDE.md" \
  | grep -oE '`[^`]+`' | tr -d '`' | sort -u)
lane_list=$(printf '%s\n' "${PROTECTED[@]}" | sort -u)
if [[ -n "$claude_list" && "$claude_list" == "$lane_list" ]]; then
  echo "ok   PROTECTED matches CLAUDE.md's Never edit list"
else
  echo "FAIL PROTECTED vs CLAUDE.md: $(diff <(echo "$claude_list") <(echo "$lane_list") | grep '^[<>]' | paste -sd' ' -)"; fail=1
fi
for p in "${PROTECTED[@]}"; do
  f="$p"; [[ "$p" == */ ]] && f="${p}x.swift"
  check "refuses $f" "not-eligible|touches protected paths: $f" . "$f" .
done

# The worker's marker: a line `Fast-Check: pass`, then `Head: <full head sha>`.
mark() { printf '.body = "Closes #1\n\n%s\n%s"' "$1" "$2"; }
MARKED=$(mark "Fast-Check: pass" "Head: $HEAD_SHA")
check "marker on the head, no CI: eligible" "eligible|150|2|Fast-Check marker" "$MARKED" "$BASE_FILES" '[]'
check "the lane's own running check (no workflow name) is ignored" "eligible|150|2|Fast-Check marker" "$MARKED" \
  "$BASE_FILES" '[{"__typename":"CheckRun","name":"fast-lane","workflowName":"","status":"IN_PROGRESS","conclusion":""}]'
check "marker with stray spaces still counts" "eligible|150|2|Fast-Check marker" \
  "$(mark "  Fast-Check: pass " "Head: $HEAD_SHA  ")" "$BASE_FILES" '[]'
check "marker with CRLF line ends still counts" "eligible|150|2|Fast-Check marker" \
  '.body = "Closes #1\r\nFast-Check: pass\r\nHead: '"$HEAD_SHA"'\r\n"' "$BASE_FILES" '[]'
check "marker for an older head waits" "pending|no passing CI check and no Fast-Check: pass marker" \
  "$(mark "Fast-Check: pass" "Head: ffffffffffffffffffffffffffffffffffffffff")" "$BASE_FILES" '[]'
check "short sha in the marker waits" "pending|no passing CI check" \
  "$(mark "Fast-Check: pass" "Head: ${HEAD_SHA:0:7}")" "$BASE_FILES" '[]'
check "Fast-Check: fail waits" "pending|no passing CI check" \
  "$(mark "Fast-Check: fail" "Head: $HEAD_SHA")" "$BASE_FILES" '[]'
check "Head line apart from the Fast-Check line waits" "pending|no passing CI check" \
  "$(mark "Fast-Check: pass" "x\nHead: $HEAD_SHA")" "$BASE_FILES" '[]'
check "Head line alone waits" "pending|no passing CI check" \
  '.body = "Head: '"$HEAD_SHA"'"' "$BASE_FILES" '[]'
check "marker does not outrank a red check" "red|Linux" "$MARKED" "$BASE_FILES" \
  'map(if .name == "Linux" then .conclusion = "FAILURE" else . end)'
check "marker does not outrank a running check" "pending|1 checks still running" "$MARKED" "$BASE_FILES" \
  'map(if .name == "macOS" then .status = "IN_PROGRESS" | .conclusion = null else . end)'
check "marker does not outrank hard rules" "not-eligible|too big" "$MARKED | .additions = 999" "$BASE_FILES" '[]'
check "marker does not outrank a conflict" "conflict|$HEAD_SHA" \
  "$MARKED | .mergeable = \"CONFLICTING\" | .mergeStateStatus = \"DIRTY\"" "$BASE_FILES" '[]'
check "marker on a draft is skipped" "skip|PR is a draft" "$MARKED | .isDraft = true" "$BASE_FILES" '[]'

# Belt PRs (a body line starting Belt-Run: or Belt-Test:) also need Belt's
# belt/review commit status at success on the head; other PRs ignore it.
BELT='.body = "Closes #1\n\nBelt-Run: act-1"'
review() { printf '. + [{"__typename":"StatusContext","context":"belt/review","state":"%s"}]' "$1"; }
# The review gate cases run with the gate on; the shipped default may be off.
REQUIRE_BELT_REVIEW=1
check "belt PR, review missing: waits" "pending|waiting for review" "$BELT" "$BASE_FILES" .
check "belt PR, review pending: waits" "pending|waiting for review" "$BELT" "$BASE_FILES" "$(review PENDING)"
check "belt PR, review success: eligible" "eligible|150|2|5 checks green" "$BELT" "$BASE_FILES" "$(review SUCCESS)"
check "belt PR, review failure: red" "red|review failed" "$BELT" "$BASE_FILES" "$(review FAILURE)"
check "belt PR, review error: red" "red|review failed" "$BELT" "$BASE_FILES" "$(review ERROR)"
check "a Belt-Test line makes a belt PR too" "pending|waiting for review" '.body = "Belt-Test: t-9"' "$BASE_FILES" .
check "red CI outranks the review" "red|Linux" "$BELT" "$BASE_FILES" \
  "$(review SUCCESS) | map(if .name == \"Linux\" then .conclusion = \"FAILURE\" else . end)"
check "non-belt PR ignores belt/review" "eligible|150|2|5 checks green" . "$BASE_FILES" "$(review FAILURE)"
check "belt PR with a marker still waits for review" "pending|waiting for review" \
  "$BELT | .body += \"\\nFast-Check: pass\\nHead: $HEAD_SHA\"" "$BASE_FILES" '[]'
REQUIRE_BELT_REVIEW=0
check "gate off: belt PR needs no review" "eligible|150|2|5 checks green" "$BELT" "$BASE_FILES" .
REQUIRE_BELT_REVIEW=1

# strip_attribution drops the footer cloud sessions add to PR bodies and keeps the rest.
body=$'Fixes the thing.\n\nCloses #1\n\n---\n_Generated by [Claude Code](https://claude.ai/code/session_x)_'
got=$(printf '%s\n' "$body" | strip_attribution)
if [[ "$got" == *"Closes #1"* && "$got" != *"Generated by"* ]]; then
  echo "ok   strip_attribution drops the cloud footer"
else
  echo "FAIL strip_attribution: got '$got'"; fail=1
fi

# With the gate off, a Belt PR with no review is eligible like any other.
REQUIRE_BELT_REVIEW=0
check "gate off: belt PR without review is eligible" "eligible|150|2|5 checks green" '.body = "x\nBelt-Run: act-1"' "$BASE_FILES" .

# A whole sweep against a stub `gh` that answers from per-PR fixtures and logs
# every write: #4 and #7 are eligible, #5 is based on main, #6 conflicts.
# sweep <PRs labelled feature-done> runs main() and leaves the writes in $sw/calls.
# Files come from $sw/files.<n>.json (raw API shape, the lane's --jq applied).
sw="$tmp/sweep"
gh() {
  local a="$*" n
  case "$a" in
    "pr list "*) for n in 7 6 5 4; do [[ -e "$sw/$n.merged" ]] || echo "$n"; done ;;
    "pr view "*"--json title "*) echo "title $2" ;;
    "pr view "*"--json body "*) jq -r .body "$sw/$3.json" ;;
    "pr view "*"--json closingIssuesReferences "*) ;;
    "pr view "*) cat "$sw/$3.json" ;;
    "api "*"/check-runs"*|"api "*"/status "*) echo '[]' ;;
    "api "*"/pulls/"*"/files "*)
      n="${2#*/pulls/}"; n="${n%%/*}"
      if [[ -e "$sw/files.$n.json" ]]; then jq -r "${!#}" "$sw/files.$n.json"
      else jq -rn '[{filename: "Sources/FlareCore/Timeline.swift", status: "modified"}]' | jq -r "${!#}"; fi ;;
    "api "*"/issues/"*"/comments "*) n="${2#*/issues/}"; cat "$sw/${n%%/*}.comments" 2>/dev/null || true ;;
    "pr comment "*) echo "$a" >>"$sw/calls"; printf '%s\n' "${!#}" >>"$sw/$3.comments" ;;
    "pr merge "*) echo "$a" >>"$sw/calls"; touch "$sw/$3.merged" ;;
    "pr edit "*"--base "*) echo "$a" >>"$sw/calls"; jq '.baseRefName = "dev"' "$sw/$3.json" >"$sw/x" && mv "$sw/x" "$sw/$3.json" ;;
    *) echo "$a" >>"$sw/calls" ;;
  esac
}
sweep() {
  rm -rf "$sw"; mkdir -p "$sw"; : >"$sw/calls"
  local n
  for n in 4 5 6 7; do jq --argjson n "$n" '.number = $n' <<<"$BASE_PR" | jq "$MARKED" >"$sw/$n.json"; done
  jq '.baseRefName = "main"' "$sw/5.json" >"$sw/x" && mv "$sw/x" "$sw/5.json"
  jq '.mergeable = "CONFLICTING" | .mergeStateStatus = "DIRTY"' "$sw/6.json" >"$sw/x" && mv "$sw/x" "$sw/6.json"
  for n in "$@"; do jq '.labels += [{"name":"feature-done"}]' "$sw/$n.json" >"$sw/x" && mv "$sw/x" "$sw/$n.json"; done
  ( main ) >/dev/null 2>&1 || { echo "FAIL sweep: main exited non-zero"; fail=1; }
}
expect() {  # expect <name> <actual> <wanted>
  if [[ "$2" == "$3" ]]; then echo "ok   sweep: $1"; else echo "FAIL sweep: $1: want '$3', got '$2'"; fail=1; fi
}
sweep
expect "merges every eligible PR, oldest first, and the retargeted one on the re-sweep" \
  "$(grep -oE '^pr merge [0-9]+' "$sw/calls" | paste -sd, -)" "pr merge 4,pr merge 7,pr merge 5"
expect "retargets the main-based PR once" "$(grep -c '^pr edit 5 .*--base dev' "$sw/calls")" 1
expect "one conflict comment" "$(grep -c '^pr comment 6 .*conflicts with dev' "$sw/calls")" 1
expect "never merges the conflicting PR" "$(grep -c '^pr merge 6' "$sw/calls")" 0
expect "routine merges start no CI" "$(grep -c '^workflow run' "$sw/calls")" 0
sweep 4 7
expect "feature-done merges dispatch CI on dev once" "$(grep -c '^workflow run ci.yml .*--ref dev' "$sw/calls")" 1
# A rename away from a protected path is refused under its old name.
rm -rf "$sw"; mkdir -p "$sw"; : >"$sw/calls"
jq '.number = 4' <<<"$BASE_PR" | jq "$MARKED" >"$sw/4.json"
echo '[{"filename": "tools/mutate", "previous_filename": "scripts/mutate", "status": "renamed"}]' >"$sw/files.4.json"
( main 4 ) >/dev/null 2>&1 || { echo "FAIL sweep: main exited non-zero"; fail=1; }
expect "a rename away from a protected path is refused" \
  "$(grep -c '^pr comment 4 .*touches protected paths: scripts/mutate\.' "$sw/calls")" 1
expect "never merges it" "$(grep -c '^pr merge 4' "$sw/calls")" 0
exit "$fail"
