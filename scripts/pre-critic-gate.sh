#!/usr/bin/env bash
#
# pre-critic-gate.sh — the mechanical checks a critic should never have to spend a round on.
#
# Runs, against the working tree at <head> and the range <base>..<head>:
#   rubocop     targeted RuboCop on the touched .rb files of server/ and worker/, counting only offenses
#               on lines the range added or changed (older offenses in a touched file do not fail it)
#   tsc         `tsc --noEmit` in frontend/ when the range touches frontend/
#   catalog     check-mcp-catalog-fresh.sh, when the range touches anything that can change the MCP tool
#               catalog (server/app|lib|config, extensions/, the catalog itself); --all forces it
#   purity      the core-purity hook on every touched source file (core names no extension; an extension
#               names no other), and the deployment-identifier scan on every touched file
#   messages    no AI attribution, private-extension name or control byte in any commit of the range
#               (lib/commit-range-scan.rb; private names derived from extensions/private/*)
#   leak-guards check-skill-executor-error-leak.sh and check-tool-not-found-leak.sh
#   gitleaks    `gitleaks detect` over the range's commits, matches redacted
#
# Usage:  scripts/pre-critic-gate.sh <base>..<head> [--json] [--all] [--skip a,b] [--only a,b]
#                                                  [--no-head-check]
# The working tree must be at <head> (the tools read files, not commits); pass --no-head-check to
# accept a dirty or different tree knowingly. Output is a compact summary meant to be pasted into a
# critic brief: one line per check, the first lines of any failure, and the verdict. Exit 0 all
# green, 1 something failed, 2 usage / environment.

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/landing-common.sh
. "$SELF_DIR/lib/landing-common.sh"

case "${1:-}" in -h|--help|"") sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac

RANGE="$1"; shift
JSON=0; ALL=0; SKIP=","; ONLY=""; HEAD_CHECK=1
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1; shift ;;
    --all) ALL=1; shift ;;
    --skip) SKIP=",${2:-},"; shift 2 ;;
    --only) ONLY=",${2:-},"; shift 2 ;;
    --no-head-check) HEAD_CHECK=0; shift ;;
    *) LC_DIE_CODE=2 lc_die "unknown option: $1" ;;
  esac
done
[[ "$RANGE" == *..* && "$RANGE" != *...* ]] || LC_DIE_CODE=2 lc_die "the range must look like <base>..<head>"
BASE="${RANGE%%..*}"; HEAD="${RANGE#*..}"

ROOT="${GATE_REPO_ROOT:-$(git -C "$SELF_DIR" rev-parse --show-toplevel)}"
MAIN_ROOT="$(lc_main_root "$ROOT")"
git -C "$ROOT" rev-parse --verify --quiet "$BASE^{commit}" >/dev/null || LC_DIE_CODE=2 lc_die "unknown base: $BASE"
HEAD_SHA="$(git -C "$ROOT" rev-parse --verify --quiet "$HEAD^{commit}")" || LC_DIE_CODE=2 lc_die "unknown head: $HEAD"
BASE_SHA="$(git -C "$ROOT" rev-parse "$BASE^{commit}")"
if [ "$HEAD_CHECK" -eq 1 ] && [ "$(git -C "$ROOT" rev-parse HEAD)" != "$HEAD_SHA" ]; then
  LC_DIE_CODE=2 lc_die "the working tree is at $(git -C "$ROOT" rev-parse --short HEAD), not $HEAD: check it out (the tools read files), or pass --no-head-check"
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
: >"$TMP/results.jsonl"

# Touched files: added / copied / modified / renamed, present at head.
mapfile -d '' TOUCHED < <(git -C "$ROOT" diff -z --name-only --diff-filter=ACMR "$BASE_SHA..$HEAD_SHA")
ALL_PATHS_FILE="$TMP/all-paths"; git -C "$ROOT" diff -z --name-only "$BASE_SHA..$HEAD_SHA" | tr '\0' '\n' >"$ALL_PATHS_FILE"
touched_matching() { local f; for f in "${TOUCHED[@]}"; do [[ "$f" =~ $1 ]] && [ -f "$ROOT/$f" ] && printf '%s\0' "$f"; done; return 0; }
touched_any() { command grep -Eq "$1" "$ALL_PATHS_FILE"; }

# record <name> <status> <detail-file-or-empty> <summary>
record() {
  local name="$1" status="$2" detail="$3" summary="$4" lines=""
  [ -z "$detail" ] || [ ! -s "$detail" ] || lines="$(command grep -v '^[[:space:]]*$' "$detail" | head -n 8 | cut -c1-220)"
  jq -cn --arg n "$name" --arg s "$status" --arg m "$summary" --arg d "$lines" '{name:$n, status:$s, summary:$m, detail:$d}' >>"$TMP/results.jsonl"
}
wanted() { [[ "$SKIP" != *",$1,"* ]] && { [ -z "$ONLY" ] || [[ "$ONLY" == *",$1,"* ]]; }; }

# ---- rubocop ---------------------------------------------------------------------------------------
check_rubocop() {
  local app total=0 nfiles=0 out="$TMP/rubocop.out" bad=0
  : >"$out"
  for app in server worker; do
    local files=(); mapfile -d '' files < <(touched_matching "^$app/.*\\.rb$")
    [ "${#files[@]}" -gt 0 ] || continue
    nfiles=$((nfiles + ${#files[@]}))
    local rel=(); local f; for f in "${files[@]}"; do rel+=("${f#"$app"/}"); done
    local json="$TMP/rubocop-$app.json" rrc=0
    (cd "$ROOT/$app" && bundle exec rubocop --force-exclusion --format json "${rel[@]}" >"$json" 2>"$TMP/rubocop-$app.err") || rrc=$?
    if [ "$rrc" -gt 1 ] || ! jq -e . "$json" >/dev/null 2>&1; then
      { echo "rubocop could not run in $app/ (exit $rrc):"; head -n 3 "$TMP/rubocop-$app.err"; } >>"$out"; bad=1; continue
    fi
    local res rc=0
    res="$(ruby "$SELF_DIR/lib/changed-line-offenses.rb" "$ROOT" "$BASE_SHA" "$HEAD_SHA" --prefix "$app/" <"$json")" || rc=$?
    if [ "$rc" -eq 2 ]; then echo "the changed-line filter failed in $app/" >>"$out"; bad=1; continue; fi
    total=$((total + $(jq -r .count <<<"$res")))
    jq -r '.offenses[] | "\(.file):\(.line) \(.cop) \(.message)"' <<<"$res" >>"$out"
  done
  if [ "$nfiles" -eq 0 ]; then record rubocop skip "" "no touched server/ or worker/ Ruby files"
  elif [ "$bad" -eq 1 ]; then record rubocop fail "$out" "$nfiles file(s); rubocop did not run cleanly"
  elif [ "$total" -gt 0 ]; then record rubocop fail "$out" "$nfiles file(s), $total offense(s) on changed lines"
  else record rubocop pass "" "$nfiles file(s), 0 offenses on changed lines"; fi
}

# ---- tsc -------------------------------------------------------------------------------------------
check_tsc() {
  if ! touched_any '^frontend/'; then record tsc skip "" "range does not touch frontend/"; return; fi
  local out="$TMP/tsc.out" rc=0
  (cd "$ROOT/frontend" && npx tsc --noEmit) >"$out" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then record tsc pass "" "tsc --noEmit clean"
  else record tsc fail "$out" "$(command grep -c 'error TS' "$out" || true) error(s)"; fi
}

# ---- catalog ---------------------------------------------------------------------------------------
check_catalog() {
  if [ "$ALL" -eq 0 ] && ! touched_any '^(server/(app|lib|config)/|extensions/|docs/reference/auto/mcp-tools\.md)'; then
    record catalog skip "" "range touches nothing that can change the MCP tool catalog"; return
  fi
  local out="$TMP/catalog.out" rc=0
  "$SELF_DIR/check-mcp-catalog-fresh.sh" >"$out" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then record catalog pass "" "docs/reference/auto/mcp-tools.md is fresh"
  else record catalog fail "$out" "the MCP tool catalog is stale (regenerate with the public bundle and commit it)"; fi
}

# ---- purity ----------------------------------------------------------------------------------------
check_purity() {
  local out="$TMP/purity.out" f n=0 hits=0 rc
  : >"$out"
  local hook="$ROOT/.claude/hooks/core-purity-check.sh" idscan="$ROOT/scripts/checks/deployment-identifier-check.sh"
  for f in "${TOUCHED[@]}"; do
    [ -f "$ROOT/$f" ] || continue
    n=$((n + 1))
    if [ -x "$hook" ] || [ -f "$hook" ]; then
      rc=0; jq -cn --arg p "$ROOT/$f" '{tool_input:{file_path:$p}}' | CLAUDE_PROJECT_DIR="$ROOT" bash "$hook" >"$TMP/hook.out" 2>&1 || rc=$?
      if [ "$rc" -eq 2 ]; then hits=$((hits + 1)); echo "core-purity: $f" >>"$out"; fi
    fi
    if [ -f "$idscan" ]; then
      rc=0; DEPLOYMENT_ID_ROOT="$ROOT" bash "$idscan" --file "$ROOT/$f" >"$TMP/id.out" 2>&1 || rc=$?
      # Only the file name is reported: the matched text is the deployment-local fact being protected.
      if [ "$rc" -ne 0 ] || [ -s "$TMP/id.out" ]; then hits=$((hits + 1)); echo "deployment identifier: $f" >>"$out"; fi
    fi
  done
  if [ "$hits" -gt 0 ]; then record purity fail "$out" "$hits finding(s) in $n touched file(s)"
  else record purity pass "" "$n touched file(s) clean"; fi
}

# ---- messages --------------------------------------------------------------------------------------
check_messages() {
  local out="$TMP/messages.out" rc=0
  ruby "$SELF_DIR/lib/commit-range-scan.rb" "$ROOT" "$BASE_SHA..$HEAD_SHA" --forbidden-from "$MAIN_ROOT/extensions/private" >"$out" 2>"$TMP/messages.err" || rc=$?
  if [ "$rc" -eq 0 ]; then record messages pass "" "$(jq -r '"\(.commits) commit(s), \(.private_names_checked) private name(s) checked"' "$out")"
  elif [ "$rc" -eq 1 ]; then
    jq -r '.problems[] | "\(.commit[0:12]) \(.rule)"' "$out" >"$TMP/messages.detail"
    record messages fail "$TMP/messages.detail" "$(jq -r '.problems | length' "$out") commit(s) break the publication rules"
  else record messages fail "$TMP/messages.err" "the scan could not run"; fi
}

# ---- leak guards -----------------------------------------------------------------------------------
check_leak_guards() {
  local out="$TMP/leak.out" rc=0 g bad=0
  : >"$out"
  for g in check-skill-executor-error-leak.sh check-tool-not-found-leak.sh; do
    rc=0; "$SELF_DIR/$g" >"$TMP/leak-one.out" 2>&1 || rc=$?
    if [ "$rc" -ne 0 ]; then bad=$((bad + 1)); echo "$g failed:" >>"$out"; head -n 3 "$TMP/leak-one.out" >>"$out"; fi
  done
  if [ "$bad" -gt 0 ]; then record leak-guards fail "$out" "$bad of 2 guard(s) failed"; else record leak-guards pass "" "2 of 2 guards clean"; fi
}

# ---- gitleaks --------------------------------------------------------------------------------------
check_gitleaks() {
  if ! command -v gitleaks >/dev/null 2>&1; then record gitleaks fail "" "gitleaks is not installed; nothing was scanned"; return; fi
  local out="$TMP/gitleaks.out" rc=0 cfg=()
  [ ! -f "$ROOT/.gitleaks.toml" ] || cfg=(--config="$ROOT/.gitleaks.toml")
  gitleaks detect --source="$ROOT" "${cfg[@]}" --log-opts="$BASE_SHA..$HEAD_SHA" --redact --no-banner >"$out" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then record gitleaks pass "" "no leaks in $BASE_SHA..$HEAD_SHA"
  else record gitleaks fail "$out" "gitleaks reported findings (matches redacted)"; fi
}

for name in rubocop tsc catalog purity messages leak-guards gitleaks; do
  wanted "$name" || { record "$name" skip "" "not selected"; continue; }
  case "$name" in
    rubocop) check_rubocop ;; tsc) check_tsc ;; catalog) check_catalog ;; purity) check_purity ;;
    messages) check_messages ;; leak-guards) check_leak_guards ;; gitleaks) check_gitleaks ;;
  esac
done

FAILED="$(jq -s '[.[] | select(.status == "fail")] | length' "$TMP/results.jsonl")"
if [ "$JSON" -eq 1 ]; then
  jq -s --arg range "$BASE_SHA..$HEAD_SHA" --argjson failed "$FAILED" '{range:$range, ok:($failed == 0), failed:$failed, checks:.}' "$TMP/results.jsonl"
else
  printf 'pre-critic gate %s..%s (%d file(s) touched)\n' "${BASE_SHA:0:12}" "${HEAD_SHA:0:12}" "${#TOUCHED[@]}"
  jq -r '"\(.status | ascii_upcase | .[0:4])  \(.name)\t\(.summary)" + (if .detail == "" then "" else "\n" + (.detail | split("\n") | map("      | " + .) | join("\n")) end)' "$TMP/results.jsonl"
  if [ "$FAILED" -eq 0 ]; then echo "RESULT: PASS"; else echo "RESULT: FAIL ($FAILED check(s))"; fi
fi
[ "$FAILED" -eq 0 ]
