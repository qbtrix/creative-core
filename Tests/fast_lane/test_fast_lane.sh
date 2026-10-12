#!/usr/bin/env bash
# Tests/fast_lane/test_fast_lane.sh: fixture tests for the pure `decide`
# function in scripts/fast-lane.sh. No network, needs bash and jq.
#
# checks-green.json is a check rollup shaped like a green creative-core PR: the CI
# workflow's Linux and macOS jobs plus one SKIPPED CI job, a non-CI workflow
# check, a commit status, the fast-lane workflow's own in-progress check and a
# Copilot review check (decide must ignore the last two). Each case mutates a
# base PR / file list / rollup with jq and may pass main CI health (green|red,
# default green) and a merge-queue removal reason (default none).
#
# Run: bash Tests/fast_lane/test_fast_lane.sh   (exit 0 = all pass)
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/fast-lane.sh
source "$here/../../scripts/fast-lane.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

BASE_PR='{"number":1,"state":"OPEN","isDraft":false,"baseRefName":"main",
  "labels":[{"name":"fast-lane"}],"author":{"login":"prakashUXtech"},
  "additions":120,"deletions":30,"changedFiles":2,
  "mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","headRefOid":"abc123",
  "commits":[{"messageHeadline":"fix(flare): keep the playhead","messageBody":"Closes #1\n\nBelt-Run: act-1"}],
  "mq":{"enabled":true,"inQueue":false}}'
BASE_FILES=$'Sources/FlareCore/Timeline.swift\nTests/FlareCoreTests/TimelineTests.swift'

# check <name> <expected stdout prefix> <pr jq> <files> <checks jq> [main health] [dequeued]
check() {
  local name="$1" want="$2" prq="$3" files="$4" chq="$5" health="${6:-green}" dequeued="${7:-}" got
  jq "$prq" <<<"$BASE_PR" >"$tmp/pr.json"
  printf '%s\n' "$files" >"$tmp/files.txt"
  jq "$chq" "$here/checks-green.json" >"$tmp/checks.json"
  got=$(decide "$tmp/pr.json" "$tmp/files.txt" "$tmp/checks.json" "$health" "$dequeued" 2>/dev/null)
  if [[ "$got" == "$want"* ]]; then
    echo "ok   $name -> $got"
  else
    echo "FAIL $name: want '$want*', got '$got'"; fail=1
  fi
}

check "happy path" "eligible|150|2|5" . "$BASE_FILES" .
check "claude app bot author is not allowlisted" "not-eligible|author app/claude is not on the fast-lane allowlist" '.author.login = "app/claude"' "$BASE_FILES" .
check "deny path hit" "not-eligible|touches protected paths: .github/workflows/ci.yml" \
  . $'.github/workflows/ci.yml\nsrc/x.py' .
check "deny Package.swift" "not-eligible|touches protected paths: Package.swift" \
  . $'Package.swift\nSources/FlareCore/Easing.swift' .
check "deny gate scripts" "not-eligible|touches protected paths: scripts/ci, scripts/cloud-setup.sh" \
  . $'scripts/ci\nscripts/cloud-setup.sh' .
check "deny agent rules, any case" "not-eligible|touches protected paths: docs/agents.md" \
  . 'docs/agents.md' .
check "similar names are allowed" "eligible|150|2|5" \
  . $'scripts/ci-helpers.sh\nSources/FlareCore/PackageSwiftNotes.swift' .
check "too big (lines)" "not-eligible|too big: 401 lines" '.additions = 401 | .deletions = 0' "$BASE_FILES" .
check "too big (files)" "not-eligible|too big: 150 lines, 16 files" '.changedFiles = 16' "$BASE_FILES" .
check "non-allowlisted author" "not-eligible|author someone is not on the fast-lane allowlist" \
  '.author.login = "someone"' "$BASE_FILES" .
check "all hard rules listed" "not-eligible|author someone is not on the fast-lane allowlist;too big" \
  '.author.login = "someone" | .additions = 999' "$BASE_FILES" .
check "no checks present fails closed" "pending|no passing check" . "$BASE_FILES" '[]'
check "only non-CI checks fails closed" "pending|no passing check" . "$BASE_FILES" \
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
check "base not main" "skip|base is dev" '.baseRefName = "dev"' "$BASE_FILES" .
check "mergeable unknown" "pending|not mergeable yet (UNKNOWN/UNKNOWN)" \
  '.mergeable = "UNKNOWN" | .mergeStateStatus = "UNKNOWN"' "$BASE_FILES" .
check "conflicting" "pending|not mergeable yet (CONFLICTING/DIRTY)" \
  '.mergeable = "CONFLICTING" | .mergeStateStatus = "DIRTY"' "$BASE_FILES" .
check "main red" "pending|main is red" . "$BASE_FILES" . red
check "red main does not mask hard rules" "not-eligible|too big" '.additions = 999' "$BASE_FILES" . red
check "blocked by the queue ruleset but green is eligible" "eligible|150|2|5" \
  '.mergeStateStatus = "BLOCKED"' "$BASE_FILES" .
check "already queued" "skip|already in the merge queue" '.mq.inQueue = true' "$BASE_FILES" .
check "no merge queue on main yet" "pending|no merge queue on main" '.mq.enabled = false' "$BASE_FILES" .
check "missing queue state fails closed" "pending|no merge queue on main" 'del(.mq)' "$BASE_FILES" .
check "removed from the queue at this head" "dequeued|failed_checks" . "$BASE_FILES" . green failed_checks
check "a red check outranks a queue removal" "red|Linux" . "$BASE_FILES" \
  'map(if .name == "Linux" then .conclusion = "FAILURE" else . end)' green failed_checks
check "co-author trailer in a commit" "not-eligible|a commit message carries AI attribution" \
  '.commits[0].messageBody += "\n\nCo-Authored-By: Claude <noreply@anthropic.com>"' "$BASE_FILES" .
check "session link in a commit" "not-eligible|a commit message carries AI attribution" \
  '.commits += [{"messageHeadline":"wip","messageBody":"Claude-Session: https://claude.ai/code/x"}]' "$BASE_FILES" .
check "a human co-author is fine" "eligible|150|2|5" \
  '.commits[0].messageBody += "\n\nCo-authored-by: Pat <pat@example.com>"' "$BASE_FILES" .

# dequeue_reason <removed at> <reason> <newest head CI run created at>
dq() {
  local name="$1" want="$2" got
  got=$(dequeue_reason "$3" "$4" "$5")
  if [[ "$got" == "$want" ]]; then echo "ok   $name -> '$got'"; else echo "FAIL $name: want '$want', got '$got'"; fail=1; fi
}
dq "never removed" "" "" "" "2026-10-12T10:00:00Z"
dq "removed after the head's CI ran" "failed_checks" "2026-10-12T11:00:00Z" failed_checks "2026-10-12T10:00:00Z"
dq "a push after the removal clears it" "" "2026-10-12T11:00:00Z" failed_checks "2026-10-12T12:00:00Z"
dq "the merged removal never holds" "" "2026-10-12T11:00:00Z" merged "2026-10-12T10:00:00Z"
dq "manual removal holds" "manual" "2026-10-12T11:00:00Z" manual "2026-10-12T10:00:00Z"
dq "no CI run at all fails closed" "removed" "2026-10-12T11:00:00Z" "" ""

# strip_attribution drops the footer cloud sessions add to PR bodies and keeps the rest.
body=$'Fixes the thing.\n\nCloses #1\n\n---\n_Generated by [Claude Code](https://claude.ai/code/session_x)_'
got=$(printf '%s\n' "$body" | strip_attribution)
if [[ "$got" == *"Closes #1"* && "$got" != *"Generated by"* ]]; then
  echo "ok   strip_attribution drops the cloud footer"
else
  echo "FAIL strip_attribution: got '$got'"; fail=1
fi

exit "$fail"
