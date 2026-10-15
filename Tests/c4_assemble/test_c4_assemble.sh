#!/usr/bin/env bash
# Tests/c4_assemble/test_c4_assemble.sh: fixture tests for scripts/c4-assemble,
# which builds docs/c4/model.json from docs/c4/parts/ (only the dev workflow,
# .github/workflows/generated.yml, commits its output). Covers: split then
# assemble reproduces a model byte for byte, sibling order, --check on a stale
# model, the part problems that fail (bad JSON, missing order, id/name
# mismatch, duplicate id, unknown relationship end), the repo's own parts
# assemble, and the workflow's guard on a scratch git repo: --absorb keeps a
# part edit, folds a direct model.json edit into the parts, and refuses a part
# changed both ways. The same file is scripts/c4-assemble in creative-apps.
# No network; needs bash, git and python3.
#
# Run: bash Tests/c4_assemble/test_c4_assemble.sh   (exit 0 = all pass)
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$here/../.."
asm="$repo/scripts/c4-assemble"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
# expect <name> <want exit> <want substring of output> <command...>
expect() {
  local name="$1" want="$2" sub="$3" got status; shift 3
  got=$("$@" 2>&1); status=$?
  if [[ "$status" == "$want" && "$got" == *"$sub"* ]]; then ok "$name"; else bad "$name (exit $status): $got"; fi
}

# --- c4-assemble -------------------------------------------------------------
c4="$tmp/c4"
mkdir -p "$c4/docs/c4"
cat >"$c4/docs/c4/model.json" <<'JSON'
{
  "version": "1.0",
  "scope": "fixture",
  "model": {
    "people": [],
    "systems": [
      {
        "id": "zeta",
        "name": "Zeta – é",
        "containers": [
          {
            "id": "z-app",
            "name": "App",
            "components": [
              {
                "id": "z-app-b",
                "paths": [
                  "Sources/B/"
                ]
              },
              {
                "id": "z-app-a",
                "paths": [
                  "Sources/A/"
                ]
              }
            ]
          },
          {
            "id": "a-lib",
            "name": "Lib",
            "components": []
          }
        ]
      },
      {
        "id": "alpha",
        "name": "Alpha",
        "containers": []
      }
    ],
    "relationships": [
      {
        "source": "z-app",
        "target": "a-lib"
      },
      {
        "source": "z-app-a",
        "target": "alpha"
      }
    ]
  }
}
JSON
cp "$c4/docs/c4/model.json" "$tmp/want.json"
python3 "$asm" --root "$c4" --split
python3 "$asm" --root "$c4" --out "$tmp/got.json"
if cmp -s "$tmp/want.json" "$tmp/got.json"; then ok "split then assemble is byte for byte (order kept, not sorted by id)"
else bad "split then assemble differs: $(diff "$tmp/want.json" "$tmp/got.json" | head -5)"; fi
[[ -f "$c4/docs/c4/parts/zeta/z-app/z-app-a.json" && -f "$c4/docs/c4/parts/zeta/system.json" ]] \
  && ok "split writes one file per component and per system" || bad "split layout"
expect "check passes on a current model" 0 "matches its parts" python3 "$asm" --root "$c4" --check
python3 - "$c4/docs/c4/parts/zeta/z-app/z-app-a.json" <<'PY'
import sys
p = sys.argv[1]
text = open(p).read().replace('"Sources/A/"', '"Sources/A2/"')
open(p, "w").write(text)
PY
expect "check fails on a stale model" 1 "differs from docs/c4/parts/" python3 "$asm" --root "$c4" --check
python3 "$asm" --root "$c4"
grep -q '"Sources/A2/"' "$c4/docs/c4/model.json" && ok "assemble writes the edited part" || bad "assemble did not write"
mkdir -p "$c4/docs/c4/parts/zeta/z-app"
printf '{"id": "z-app-c", "order": 5, "paths": ["Sources/C/"]}\n' >"$c4/docs/c4/parts/zeta/z-app/z-app-c.json"
python3 "$asm" --root "$c4" --out "$tmp/new.json"
first=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["model"]["systems"][0]["containers"][0]["components"][0]["id"])' "$tmp/new.json")
[[ "$first" == "z-app-c" ]] && ok "a new component part lands by its order" || bad "new part order: $first"
printf '{"id": "z-app-c", "paths": []}\n' >"$c4/docs/c4/parts/zeta/z-app/z-app-c.json"
expect "a part without order fails" 1 'needs an integer "order"' python3 "$asm" --root "$c4" --out "$tmp/x.json"
printf '{"id": "other", "order": 1}\n' >"$c4/docs/c4/parts/zeta/z-app/z-app-c.json"
expect "an id that differs from its file name fails" 1 "must match its name" python3 "$asm" --root "$c4" --out "$tmp/x.json"
printf '{"id": "z-app-c", "order": 1,' >"$c4/docs/c4/parts/zeta/z-app/z-app-c.json"
expect "bad JSON fails" 1 "not valid JSON" python3 "$asm" --root "$c4" --out "$tmp/x.json"
printf '{"id": "z-app-c", "order": 1, "relationships": [{"source": "z-app-c", "target": "nowhere"}]}\n' >"$c4/docs/c4/parts/zeta/z-app/z-app-c.json"
expect "an unknown relationship end fails" 1 "unknown target 'nowhere'" python3 "$asm" --root "$c4" --out "$tmp/x.json"
mkdir -p "$c4/docs/c4/parts/alpha/z-app"
printf '{"id": "z-app", "order": 1}\n' >"$c4/docs/c4/parts/alpha/z-app/container.json"
rm "$c4/docs/c4/parts/zeta/z-app/z-app-c.json"
expect "a duplicate id fails" 1 "id 'z-app' is used twice" python3 "$asm" --root "$c4" --out "$tmp/x.json"

# The repo's own parts: they assemble, and to the same components as model.json
# (equal when dev's generated workflow has run; a PR may only add or change parts).
if python3 "$asm" --root "$repo" --out "$tmp/repo.json" >/dev/null; then ok "the repo's docs/c4/parts/ assemble"
else bad "the repo's docs/c4/parts/ do not assemble: $(python3 "$asm" --root "$repo" --out "$tmp/repo.json")"; fi

# --- the Generated workflow's guard (git history) -----------------------------
# A scratch repo with scripts/ copied in; commit <msg> commits everything.
g="$tmp/g"
mkdir -p "$g/scripts" "$g/docs/c4"
cp "$asm" "$g/scripts/"
commit() { git -C "$g" add -A && git -C "$g" -c user.name=t -c user.email=t@t commit -q -m "$1"; }
git -C "$g" init -q
cp "$tmp/want.json" "$g/docs/c4/model.json"
python3 "$g/scripts/c4-assemble" --split
commit "consistent base"
edit() {  # edit <file> <python expression on the parsed JSON d>
  python3 - "$1" "$2" <<'PY'
import json, sys
p, expr = sys.argv[1], sys.argv[2]
d = json.load(open(p))
exec(expr)
open(p, "w").write(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
PY
}
P="$g/docs/c4/parts/zeta/z-app"
# A normal PR: a part edited, model.json untouched (stale). Absorb keeps the part.
edit "$P/z-app-a.json" 'd["paths"] = ["Sources/A3/"]'
commit "part edit"
expect "absorb keeps a part edit when model.json was not edited" 0 "no direct edits" python3 "$g/scripts/c4-assemble" --absorb
grep -q '"Sources/A3/"' "$g/docs/c4/model.json" && ok "absorb then writes model.json from the edited part" || bad "part edit lost"
commit "generated"
# A direct model.json edit plus a different part edit: both land.
edit "$g/docs/c4/model.json" 'd["model"]["systems"][0]["containers"][0]["components"][0]["paths"] = ["Sources/B9/"]; d["model"]["systems"][0]["containers"][0]["components"].append({"id": "z-app-new", "paths": ["Sources/N/"]})'
edit "$P/z-app-a.json" 'd["paths"] = ["Sources/A4/"]'
commit "direct model.json edit and a part edit"
expect "absorb folds a direct model.json edit into the parts" 0 "z-app-b.json written" python3 "$g/scripts/c4-assemble" --absorb
grep -q '"Sources/B9/"' "$P/z-app-b.json" && [[ -f "$P/z-app-new.json" ]] && ok "the direct edits became parts (an edited one and a new one)" || bad "direct edit not in parts"
grep -q '"Sources/B9/"' "$g/docs/c4/model.json" && grep -q '"Sources/A4/"' "$g/docs/c4/model.json" && grep -q '"z-app-new"' "$g/docs/c4/model.json" \
  && ok "model.json keeps both the direct edit and the part edit" || bad "absorb lost an edit"
expect "after absorb, model.json matches its parts" 0 "matches its parts" python3 "$g/scripts/c4-assemble" --root "$g" --check
commit "generated"
# The same part changed both ways: exit 2, nothing written.
edit "$g/docs/c4/model.json" 'd["model"]["systems"][0]["containers"][0]["components"][0]["paths"] = ["Sources/X/"]'
edit "$P/z-app-b.json" 'd["paths"] = ["Sources/Y/"]'
commit "conflict"
cp "$P/z-app-b.json" "$tmp/before.json"
expect "a part changed in its file and in model.json is a conflict" 2 "zeta/z-app/z-app-b.json changed both" python3 "$g/scripts/c4-assemble" --absorb
cmp -s "$P/z-app-b.json" "$tmp/before.json" && grep -q '"Sources/X/"' "$g/docs/c4/model.json" && ok "a conflict writes nothing" || bad "conflict wrote"
if [[ $fail -ne 0 ]]; then echo "c4-assemble tests: FAIL"; exit 1; fi
echo "c4-assemble tests: all pass"
