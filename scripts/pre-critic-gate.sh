#!/usr/bin/env bash
#
# pre-critic-gate.sh — the mechanical checks a critic should never have to spend a round on.
#
# Runs, against the working tree at <head> and the range <base>..<head>:
#   rubocop     targeted RuboCop on the touched .rb files of server/ and worker/, counting only offenses
#               on lines the range added or changed (older offenses in a touched file do not fail it).
#               worker/ has no RuboCop of its own, so its files are linted from server/ with server/'s
#               bundle and config; where that config cannot load or leaves a worker file uninspected, the
#               check is a SKIP naming the reason (never a failure for that, never a silent pass)
#   tsc         `tsc --noEmit` in frontend/ when the range touches frontend/
#   catalog     check-mcp-catalog-fresh.sh, when the range touches anything that can change the MCP tool
#               catalog (server/app|lib|config, extensions/, the catalog itself); --all forces it
#   purity      the core-purity hook on every touched source file (core names no extension; an extension
#               names no other), and the deployment-identifier scan on every touched file
#   messages    no AI attribution, private-extension name or control byte in any commit of the range
#               (lib/commit-range-scan.rb; private names derived from extensions/private/*)
#   leak-guards check-skill-executor-error-leak.sh and check-tool-not-found-leak.sh
#   gitleaks    `gitleaks detect` over the range's commits, matches redacted
#   ext-*       messages, purity and gitleaks (ext-messages, ext-purity, ext-gitleaks) over the extension commits:
#               those behind a gitlink bump in the range, and, for a nested extension checkout with no bump, its
#               origin/develop..HEAD (the executor's work, before land.sh bumps the pointer).
#               RuboCop on extension Ruby files is not part of the gate.
#
# The deployment-identifier list is gitignored, so it is looked up in the worktree and then the main checkout;
# with none the purity checks FAIL (GATE_ALLOW_NO_IDENTIFIER_LIST=1 accepts that knowingly). A missing purity
# hook or scanner fails too, and so does a hook that errors.
#
# Usage:  scripts/pre-critic-gate.sh <base>..<head> [--json] [--all] [--skip a,b] [--only a,b]
#                                                  [--no-head-check] [--allow-dirty]
# The working tree must be at <head> (the tools read files, not commits; --no-head-check accepts a different
# one) and free of uncommitted tracked changes in core and each extension checkout (--allow-dirty accepts them).
# Output is a compact summary meant to be pasted into a
# critic brief: one line per check, the first lines of any failure, and the verdict. Exit 0 all
# green, 1 something failed, 2 usage / environment.

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/landing-common.sh
. "$SELF_DIR/lib/landing-common.sh"

case "${1:-}" in -h|--help|"") sed -n '2,/^set -uo/{/^set -uo/!p}' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac

RANGE="$1"; shift
JSON=0; ALL=0; SKIP=","; ONLY=""; HEAD_CHECK=1; ALLOW_DIRTY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1; shift ;;
    --all) ALL=1; shift ;;
    --skip) SKIP=",${2:-},"; shift 2 ;;
    --only) ONLY=",${2:-},"; shift 2 ;;
    --no-head-check) HEAD_CHECK=0; shift ;;
    --allow-dirty) ALLOW_DIRTY=1; shift ;;
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

# The tools read files, not commits: uncommitted tracked changes in core or a nested extension checkout would be
# linted and scanned INSTEAD of the commit under review.
if [ "$ALLOW_DIRTY" -eq 0 ]; then
  _dirty=""
  if [ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no --ignore-submodules=all 2>/dev/null)" ]; then _dirty=" core"; fi
  while IFS= read -r _p; do
    [ -e "$ROOT/$_p/.git" ] || continue
    [ -z "$(git -C "$ROOT/$_p" status --porcelain --untracked-files=no 2>/dev/null)" ] || _dirty="$_dirty $_p"
  done < <(git -C "$ROOT" config -f "$ROOT/.gitmodules" --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}')
  [ -z "$_dirty" ] || LC_DIE_CODE=2 lc_die "uncommitted tracked changes in:$_dirty. The gate would check them instead of the commit; commit or stash them, or pass --allow-dirty knowingly"
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
  local app total=0 nfiles=0 out="$TMP/rubocop.out" bad=0 notes="$TMP/rubocop.skip" root_real
  : >"$out"; : >"$notes"
  root_real="$(cd "$ROOT" && pwd -P)"
  for app in server worker; do
    local files=(); mapfile -d '' files < <(touched_matching "^$app/.*\\.rb$")
    [ "${#files[@]}" -gt 0 ] || continue
    nfiles=$((nfiles + ${#files[@]}))
    local args=() f; for f in "${files[@]}"; do args+=("${f#"$app"/}"); done
    # worker/ files are named from server/, and --config is explicit: RuboCop otherwise looks for a config
    # above each FILE, finds none for worker/, and lints it with RuboCop's defaults instead.
    if [ "$app" = worker ]; then
      if [ ! -f "$ROOT/server/.rubocop.yml" ]; then echo "worker/: server/.rubocop.yml does not exist" >>"$notes"; continue; fi
      args=(--config "$ROOT/server/.rubocop.yml"); for f in "${files[@]}"; do args+=("../$f"); done
    fi
    local json="$TMP/rubocop-$app.json" rrc=0
    (cd "$ROOT/server" && bundle exec rubocop --force-exclusion --format json "${args[@]}" >"$json" 2>"$TMP/rubocop-$app.err") || rrc=$?
    if [ "$rrc" -gt 1 ] || ! jq -e . "$json" >/dev/null 2>&1; then
      # RuboCop loads but the server config does not apply to worker/ files: a skip, not a failure. (The probe
      # is a bare require: every `rubocop` invocation in server/, even --version, loads the config first.)
      if [ "$app" = worker ] && (cd "$ROOT/server" && bundle exec ruby -e 'require "rubocop"') >/dev/null 2>&1; then
        { echo "worker/: server/'s config could not be applied (exit $rrc):"; head -n 3 "$TMP/rubocop-$app.err"; } >>"$notes"; continue
      fi
      { echo "rubocop could not run in server/ for $app/ (exit $rrc):"; head -n 3 "$TMP/rubocop-$app.err"; } >>"$out"; bad=1; continue
    fi
    if [ "$app" = worker ]; then
      # Paths outside server/ come back absolute: make them worker/-relative, as the changed-line filter expects.
      jq --arg a "$ROOT/worker/" --arg b "$root_real/worker/" \
        '.files |= map(.path |= (if startswith($a) then .[($a | length):] elif startswith($b) then .[($b | length):] elif startswith("../worker/") then .[10:] else . end))' \
        "$json" >"$json.rel" && mv "$json.rel" "$json"
      local unseen; unseen="$(printf '%s\n' "${files[@]#worker/}" | sort -u | comm -23 - <(jq -r '.files[].path' "$json" | sort -u) | wc -l)"
      [ "$unseen" -eq 0 ] || echo "worker/: $unseen of ${#files[@]} worker/ file(s) not inspected under server/'s config (excluded by it)" >>"$notes"
    fi
    local res rc=0
    res="$(ruby "$SELF_DIR/lib/changed-line-offenses.rb" "$ROOT" "$BASE_SHA" "$HEAD_SHA" --prefix "$app/" <"$json")" || rc=$?
    if [ "$rc" -eq 2 ]; then echo "the changed-line filter failed in $app/" >>"$out"; bad=1; continue; fi
    total=$((total + $(jq -r .count <<<"$res")))
    jq -r '.offenses[] | "\(.file):\(.line) \(.cop) \(.message)"' <<<"$res" >>"$out"
  done
  cat "$notes" >>"$out"
  if [ "$nfiles" -eq 0 ]; then record rubocop skip "" "no touched server/ or worker/ Ruby files"
  elif [ "$bad" -eq 1 ]; then record rubocop fail "$out" "$nfiles file(s); rubocop did not run cleanly"
  elif [ "$total" -gt 0 ]; then record rubocop fail "$out" "$nfiles file(s), $total offense(s) on changed lines"
  elif [ -s "$notes" ]; then record rubocop skip "$out" "$nfiles file(s), 0 offenses on changed lines where linted; worker/ not linted (see detail)"
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
# The deployment-identifier list is gitignored, so a worktree has none: it is read from the main checkout.
# No list anywhere is a FAILURE (the scan would otherwise pass vacuously); GATE_ALLOW_NO_IDENTIFIER_LIST=1
# accepts that knowingly (a public clone that has no deployment to protect).
ID_LIST=""
for _c in "${DEPLOYMENT_ID_LIST:-}" "$ROOT/.claude/hooks/deployment-identifiers.local.txt" "$MAIN_ROOT/.claude/hooks/deployment-identifiers.local.txt"; do
  [ -n "$_c" ] && [ -f "$_c" ] && { ID_LIST="$_c"; break; }
done

# scan_paths <out-file> <abs-path>...  ->  PURITY_N / PURITY_HITS / PURITY_PROBLEMS
scan_paths() {
  local out="$1"; shift
  local f rc rel hook="$ROOT/.claude/hooks/core-purity-check.sh" idscan="$ROOT/scripts/checks/deployment-identifier-check.sh"
  PURITY_N=0; PURITY_HITS=0; PURITY_PROBLEMS=""
  [ -f "$hook" ] || PURITY_PROBLEMS="the core-purity hook is missing ($hook);"
  [ -f "$idscan" ] || PURITY_PROBLEMS="$PURITY_PROBLEMS the deployment-identifier scan is missing;"
  if [ -z "$ID_LIST" ] && [ "${GATE_ALLOW_NO_IDENTIFIER_LIST:-0}" != 1 ]; then
    PURITY_PROBLEMS="$PURITY_PROBLEMS no deployment-identifier list found (worktree or main checkout), so identifiers were NOT scanned;"
  fi
  for f in "$@"; do
    [ -f "$f" ] || continue
    PURITY_N=$((PURITY_N + 1)); rel="${f#"$ROOT"/}"
    if [ -f "$hook" ]; then
      rc=0; jq -cn --arg p "$f" '{tool_input:{file_path:$p}}' | CLAUDE_PROJECT_DIR="$ROOT" bash "$hook" >"$TMP/hook.out" 2>&1 || rc=$?
      case "$rc" in
        0) ;;
        2) PURITY_HITS=$((PURITY_HITS + 1)); echo "core-purity: $rel" >>"$out" ;;
        *) PURITY_HITS=$((PURITY_HITS + 1)); echo "core-purity hook errored (exit $rc): $rel" >>"$out" ;;
      esac
    fi
    if [ -f "$idscan" ] && { [ -n "$ID_LIST" ] || [ "${GATE_ALLOW_NO_IDENTIFIER_LIST:-0}" = 1 ]; }; then
      rc=0; env DEPLOYMENT_ID_ROOT="$ROOT" DEPLOYMENT_ID_LIST="${ID_LIST:-/nonexistent}" bash "$idscan" --file "$f" >"$TMP/id.out" 2>&1 || rc=$?
      # Only the file name is reported: the matched text is the deployment-local fact being protected.
      if [ "$rc" -ne 0 ] || [ -s "$TMP/id.out" ]; then PURITY_HITS=$((PURITY_HITS + 1)); echo "deployment identifier: $rel" >>"$out"; fi
    fi
  done
}

purity_record() { # name out label
  local name="$1" out="$2"
  [ -z "$PURITY_PROBLEMS" ] || echo "$PURITY_PROBLEMS" >>"$out"
  if [ "$PURITY_HITS" -gt 0 ] || [ -n "$PURITY_PROBLEMS" ]; then
    record "$name" fail "$out" "$PURITY_HITS finding(s) in $PURITY_N touched file(s)${PURITY_PROBLEMS:+; the check could not run fully}"
  else record "$name" pass "" "$PURITY_N touched file(s) clean"; fi
}

check_purity() {
  local out="$TMP/purity.out" abs=() f
  : >"$out"
  for f in "${TOUCHED[@]}"; do abs+=("$ROOT/$f"); done
  scan_paths "$out" "${abs[@]}"
  purity_record purity "$out"
}

# ---- extension ranges ------------------------------------------------------------------------------
# A core range carries an extension change only as a gitlink bump, so the commits behind it are read from the
# extension checkout: messages, purity and gitleaks. Where core has no bump yet, each nested extension checkout's
# origin/develop..HEAD is gated instead. (RuboCop on extension Ruby files is NOT run here.)
mapfile -t EXT_BUMPS < <(git -C "$ROOT" diff --raw --no-abbrev "$BASE_SHA..$HEAD_SHA" | awk -F'[ \t]' '$1 == ":160000" && $2 == "160000" && $5 == "M" {print $6 "\t" $3 "\t" $4}' | cut -c1-400)
# Nested extension checkouts whose HEAD is ahead of origin/develop: the executor's not-yet-landed extension work,
# which core does not point at yet (the usual state when this gate runs, before land.sh bumps the pointer).
while IFS= read -r _p; do
  [ -e "$ROOT/$_p/.git" ] || continue
  [[ "$_p" != extensions/private/* ]] || continue
  printf '%s\n' "${EXT_BUMPS[@]}" | cut -f1 | command grep -qxF -- "$_p" && continue
  _tip="$(git -C "$ROOT/$_p" rev-parse --verify --quiet "refs/remotes/origin/develop^{commit}" || true)"
  _head="$(git -C "$ROOT/$_p" rev-parse --verify --quiet "HEAD^{commit}" || true)"
  if [ -z "$_tip" ] || [ -z "$_head" ]; then EXT_BUMPS+=("$_p"$'\t\t'); continue; fi   # unreadable: fails in ext_each
  [ "$(git -C "$ROOT/$_p" rev-list --count "$_tip..$_head" 2>/dev/null || echo 0)" -gt 0 ] && EXT_BUMPS+=("$_p"$'\t'"$_tip"$'\t'"$_head")
done < <(git -C "$ROOT" config -f "$ROOT/.gitmodules" --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}')
ext_each() { # callback name: called as cb <path> <old> <new> <dir>; sets EXT_FAIL / EXT_N
  local cb="$1" line path old new
  for line in "${EXT_BUMPS[@]}"; do
    IFS=$'\t' read -r path old new <<<"$line"
    EXT_N=$((EXT_N + 1))
    if [ ! -e "$ROOT/$path/.git" ] || ! git -C "$ROOT/$path" cat-file -e "$old^{commit}" 2>/dev/null || ! git -C "$ROOT/$path" cat-file -e "$new^{commit}" 2>/dev/null; then
      EXT_FAIL=$((EXT_FAIL + 1)); echo "$path: the range's commits are not readable in the checkout (bumped commits missing, or no origin/develop), so it cannot be gated" >>"$TMP/ext.out"; continue
    fi
    "$cb" "$path" "$old" "$new" "$ROOT/$path"
  done
}
ext_msgs_cb() {
  local rc=0 o="$TMP/ext-msg.json"
  ruby "$SELF_DIR/lib/commit-range-scan.rb" "$4" "$2..$3" --forbidden-from "$MAIN_ROOT/extensions/private" >"$o" 2>>"$TMP/ext.out" || rc=$?
  if [ "$rc" -ne 0 ]; then EXT_FAIL=$((EXT_FAIL + 1)); if [ "$rc" -eq 1 ]; then jq -r --arg p "$1" '.problems[] | "\($p) \(.commit[0:12]) \(.rule)"' "$o" >>"$TMP/ext.out"; else echo "$1: the scan could not run" >>"$TMP/ext.out"; fi; fi
}
ext_gitleaks_cb() {
  local rc=0 cfg=()
  [ ! -f "$ROOT/.gitleaks.toml" ] || cfg=(--config="$ROOT/.gitleaks.toml")
  gitleaks detect --source="$4" "${cfg[@]}" --log-opts="$2..$3" --redact --no-banner >"$TMP/ext-gl.out" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || { EXT_FAIL=$((EXT_FAIL + 1)); echo "$1: gitleaks reported findings (matches redacted)" >>"$TMP/ext.out"; }
}
ext_purity_cb() {
  local files=() f
  while IFS= read -r -d '' f; do files+=("$4/$f"); done < <(git -C "$4" diff -z --name-only --diff-filter=ACMR "$2..$3")
  scan_paths "$TMP/ext.out" "${files[@]}"
  EXT_FAIL=$((EXT_FAIL + PURITY_HITS)); EXT_FILES=$((EXT_FILES + PURITY_N))
  [ -z "$PURITY_PROBLEMS" ] || { EXT_FAIL=$((EXT_FAIL + 1)); echo "$PURITY_PROBLEMS" >>"$TMP/ext.out"; }
}
check_ext() { # name callback
  local name="$1" cb="$2"
  if [ "${#EXT_BUMPS[@]}" -eq 0 ]; then record "$name" skip "" "no extension pointer bump and no extension checkout ahead of origin/develop"; return; fi
  : >"$TMP/ext.out"; EXT_FAIL=0; EXT_N=0; EXT_FILES=0
  ext_each "$cb"
  if [ "$EXT_FAIL" -gt 0 ]; then record "$name" fail "$TMP/ext.out" "$EXT_FAIL problem(s) across $EXT_N bumped extension(s)"
  else record "$name" pass "" "$EXT_N bumped extension range(s) clean"; fi
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

for name in rubocop tsc catalog purity messages leak-guards gitleaks ext-messages ext-purity ext-gitleaks; do
  wanted "$name" || { record "$name" skip "" "not selected"; continue; }
  case "$name" in
    rubocop) check_rubocop ;; tsc) check_tsc ;; catalog) check_catalog ;; purity) check_purity ;;
    messages) check_messages ;; leak-guards) check_leak_guards ;; gitleaks) check_gitleaks ;;
    ext-messages) check_ext ext-messages ext_msgs_cb ;; ext-purity) check_ext ext-purity ext_purity_cb ;; ext-gitleaks) check_ext ext-gitleaks ext_gitleaks_cb ;;
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
