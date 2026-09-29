#!/usr/bin/env bash
#
# land.sh — the dev-improve landing path as one command: scan, fast-forward check, merge, build,
# promote, verify, and the dev_complete_task evidence. It reproduces, step for step, what the driver
# otherwise types by hand; it decides nothing.
#
# Usage:
#   scripts/land.sh <task_key> --core-sha <sha> --modules a,b,c [options]
#
#   --core-sha <sha>       REQUIRED. The reviewed core commit to land on the target branch (for an
#                          extension-only change pass the current remote target tip).
#   --ext-path <path>      The extension submodule the commit belongs to (or LAND_EXT_PATH).
#   --ext-sha <sha>        The reviewed extension commit. It is pushed first and the core gitlink is
#                          then bumped to it (a generated pointer commit) unless <core-sha> already
#                          carries it.
#   --modules a,b,c        REQUIRED. Module slugs to build (dispatched with expand_dependents:false; the
#                          planner only accepts slugs changed in the range).
#   --module-id slug=uuid  Repeatable. The NodeModule id to promote when the module's name is not its
#                          slug (default: resolved from the module list by exact name).
#   --merge-via git|mcp|none   git (default): plain fast-forward pushes to the remotes, the recipe as
#                          typed by hand. mcp: dev_merge_increment (parks for a person's approval; the
#                          script stops with exit 3, and a re-run picks up where it left off). none: the
#                          commits are already on the target.
#   --core-source-ref/--ext-source-ref <branch>   mcp mode: the branch holding each reviewed commit.
#   --attest <json|file>   mcp mode: the gate_attestation for the merge.
#   --evidence <json|file> The test evidence to carry into dev_complete_task, e.g.
#                          {"framework":"rspec","passed":12,"failed":0,"command":"..."}.
#   --loop <id-or-name>    The Ralph loop, needed with --complete.
#   --complete             Call dev_complete_task with the evidence. Without it the evidence JSON is
#                          only printed.
#   --skip-verify          Do not run verify-hub-deploy.sh (recorded as skipped in the evidence).
#   --skip-catalog-check   Do not run check-mcp-catalog-fresh.sh first.
#   --no-fetch             Do not fetch the remotes' target branches first.
#   --dry-run              Do every READ-ONLY step (config, scans, fast-forward checks) and print the
#                          steps that would mutate; push nothing, call no MCP verb.
#
# Steps stop at the FIRST failure with a message naming it. Exit: 0 done, 1 a step failed, 2 usage or
# configuration, 3 parked for approval (merge or promotion; approve, then re-run).
#
# Output: progress on stderr; ONE JSON evidence document on stdout.
#
# Configuration comes from the environment or the gitignored local config (scripts/landing.env.example):
#   LAND_MCP_URL (required), LAND_MCP_TOKEN_ENV (name of the variable holding the bearer token;
#   default POWERNODE_MCP_TOKEN), LAND_MCP_TOOL_PREFIX (default "platform."), LAND_CORE_REMOTE /
#   LAND_EXT_REMOTE (default origin), LAND_TARGET_BRANCH (default develop), LAND_EXT_PATH (the extension
#   submodule path; default: the only public submodule in .gitmodules, if there is exactly one),
#   LAND_SOURCE_REPO (owner/repo the build diff is taken against; default derived
#   from the core remote), LAND_PROMOTE_ENVS (default "staging ops"), LAND_POLL_INTERVAL,
#   LAND_POLL_TIMEOUT, LAND_CORE_REPOSITORY / LAND_EXT_REPOSITORY (platform repository ids or full names,
#   mcp merge mode only).
#
# STATUS OF THE WIRE FORMAT: the JSON-RPC calls follow scripts/mcp-smoke-test.sh (POST tools/call with a
# bearer token) and the verb parameters were read from the tool definitions; the spec drives them against
# a local mock server. It has NOT been run against a live control plane, whose transport details (session
# handshake, tool-name prefix) may need LAND_MCP_TOOL_PREFIX or a different LAND_MCP_URL.

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/landing-common.sh
. "$SELF_DIR/lib/landing-common.sh"

case "${1:-}" in -h|--help|"") sed -n '2,52p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac

TASK_KEY="$1"; shift
CORE_SHA=""; EXT_SHA=""; MODULES=""; MERGE_VIA="git"; LOOP=""; COMPLETE=0
SKIP_VERIFY=0; SKIP_CATALOG=0; NO_FETCH=0; DRY=0; EXT_PATH_ARG=""
CORE_REF=""; EXT_REF=""; ATTEST=""; EVIDENCE=""
declare -A MODULE_ID_OVERRIDE=()
usage_die() { LC_DIE_CODE=2 lc_die "$*"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --core-sha) CORE_SHA="${2:-}"; shift 2 ;;
    --ext-sha) EXT_SHA="${2:-}"; shift 2 ;;
    --ext-path) EXT_PATH_ARG="${2:-}"; shift 2 ;;
    --modules) MODULES="${2:-}"; shift 2 ;;
    --module-id) [[ "${2:-}" == *=* ]] || usage_die "--module-id needs slug=uuid"; MODULE_ID_OVERRIDE["${2%%=*}"]="${2#*=}"; shift 2 ;;
    --merge-via) MERGE_VIA="${2:-}"; shift 2 ;;
    --core-source-ref) CORE_REF="${2:-}"; shift 2 ;;
    --ext-source-ref) EXT_REF="${2:-}"; shift 2 ;;
    --attest) ATTEST="${2:-}"; shift 2 ;;
    --evidence) EVIDENCE="${2:-}"; shift 2 ;;
    --loop) LOOP="${2:-}"; shift 2 ;;
    --complete) COMPLETE=1; shift ;;
    --skip-verify) SKIP_VERIFY=1; shift ;;
    --skip-catalog-check) SKIP_CATALOG=1; shift ;;
    --no-fetch) NO_FETCH=1; shift ;;
    --dry-run) DRY=1; shift ;;
    *) usage_die "unknown option: $1" ;;
  esac
done

[[ "$TASK_KEY" =~ ^[A-Za-z0-9._-]+$ ]] || usage_die "task_key looks wrong: $TASK_KEY"
lc_valid_sha "$CORE_SHA" || usage_die "--core-sha is required (7-40 hex)"
[ -z "$EXT_SHA" ] || lc_valid_sha "$EXT_SHA" || usage_die "--ext-sha must be 7-40 hex"
[ -n "$MODULES" ] || usage_die "--modules is required (comma-separated slugs)"
[[ "$MODULES" =~ ^[A-Za-z0-9._-]+(,[A-Za-z0-9._-]+)*$ ]] || usage_die "--modules must be comma-separated slugs"
case "$MERGE_VIA" in git|mcp|none) ;; *) usage_die "--merge-via must be git, mcp or none" ;; esac
[ "$COMPLETE" -eq 0 ] || [ -n "$LOOP" ] || usage_die "--complete needs --loop"

REPO_ROOT="${LAND_REPO_ROOT:-$(lc_repo_root)}"
lc_load_config "$REPO_ROOT"
MAIN_ROOT="$(lc_main_root "$REPO_ROOT")"

CORE_REMOTE="${LAND_CORE_REMOTE:-origin}"; EXT_REMOTE="${LAND_EXT_REMOTE:-origin}"
TARGET="${LAND_TARGET_BRANCH:-develop}"
EXT_PATH="${EXT_PATH_ARG:-${LAND_EXT_PATH:-}}"
if [ -z "$EXT_PATH" ] && [ -n "$EXT_SHA" ]; then
  mapfile -t _subs < <(git -C "$REPO_ROOT" config -f "$REPO_ROOT/.gitmodules" --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}')
  [ "${#_subs[@]}" -eq 1 ] || usage_die "--ext-sha needs to know which extension: pass --ext-path or set LAND_EXT_PATH (.gitmodules lists ${#_subs[@]})"
  EXT_PATH="${_subs[0]}"
fi
EXT_DIR="$REPO_ROOT/${EXT_PATH:-.}"
PREFIX="${LAND_MCP_TOOL_PREFIX-platform.}"
TOKEN_ENV="${LAND_MCP_TOKEN_ENV:-POWERNODE_MCP_TOKEN}"
PROMOTE_ENVS="${LAND_PROMOTE_ENVS:-staging ops}"
POLL_INTERVAL="${LAND_POLL_INTERVAL:-20}"; POLL_TIMEOUT="${LAND_POLL_TIMEOUT:-2400}"

[[ "$TOKEN_ENV" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || usage_die "LAND_MCP_TOKEN_ENV must be a variable name"
lc_require LAND_MCP_URL
[ -n "${!TOKEN_ENV:-}" ] || LC_DIE_CODE=2 lc_die "the bearer token variable $TOKEN_ENV is empty (LAND_MCP_TOKEN_ENV names it)"
[ -z "$EXT_SHA" ] || [ -d "$EXT_DIR/.git" ] || [ -f "$EXT_DIR/.git" ] || usage_die "--ext-sha given but $EXT_PATH is not a git checkout"
if [ "$MERGE_VIA" = mcp ]; then
  lc_require LAND_CORE_REPOSITORY
  [ -z "$EXT_SHA" ] || lc_require LAND_EXT_REPOSITORY
  [ -n "$ATTEST" ] || usage_die "--merge-via mcp needs --attest (the gate_attestation)"
fi

gitc() { git -C "$REPO_ROOT" "$@"; }
gite() { git -C "$EXT_DIR" "$@"; }
json_arg() { # a JSON string or a file holding one -> compact JSON
  if [ -f "$1" ]; then jq -c . "$1"; else printf '%s' "$1" | jq -c .; fi
}
step() { lc_info "step $1: $2"; }
would() { lc_info "  (dry-run) would: $*"; }

# ---- MCP over HTTP ---------------------------------------------------------------------------------
HDR_FILE="$(mktemp)"; chmod 600 "$HDR_FILE"
trap 'rm -f "$HDR_FILE"' EXIT
printf 'Authorization: Bearer %s\n' "${!TOKEN_ENV}" >"$HDR_FILE"   # header file: keeps the token out of argv

# mcp_call <tool> <args-json>  -> the tool's result JSON on stdout.
# rc 0 ok; 1 the call failed or the tool said success:false; 3 the tool parked for approval.
mcp_call() {
  local tool="$1" args="$2" payload resp body
  payload="$(jq -cn --arg t "${PREFIX}${tool}" --argjson a "$args" \
    '{jsonrpc:"2.0", id:1, method:"tools/call", params:{name:$t, arguments:$a}}')"
  resp="$(curl -sS -m 180 -X POST "$LAND_MCP_URL" -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' -H "@$HDR_FILE" -d "$payload" 2>&1)" \
    || { lc_info "  $tool: transport failure"; return 1; }
  # A streamable-HTTP server may answer as one SSE event.
  if [[ "$resp" == *"data:"* && "$resp" != "{"* ]]; then resp="$(printf '%s\n' "$resp" | sed -n 's/^data: *//p' | tail -n 1)"; fi
  printf '%s' "$resp" | jq -e . >/dev/null 2>&1 || { lc_info "  $tool: the endpoint did not answer JSON"; return 1; }
  if [ -n "$(printf '%s' "$resp" | jq -r '.error.message // empty')" ]; then
    lc_info "  $tool: $(printf '%s' "$resp" | jq -r '.error.message' | head -c 300)"; return 1
  fi
  body="$(printf '%s' "$resp" | jq -r '.result.content[0].text // empty')"
  printf '%s' "$body" | jq -e . >/dev/null 2>&1 || { lc_info "  $tool: the result was not JSON"; return 1; }
  if [ "$(printf '%s' "$body" | jq -r '.success | tostring')" = "false" ]; then
    lc_info "  $tool refused: $(printf '%s' "$body" | jq -r '.error // "no reason given"' | head -c 400)"; return 1
  fi
  printf '%s\n' "$body"
  if [ "$(printf '%s' "$body" | jq -r '.pending // false')" = "true" ]; then return 3; fi
  return 0
}
# Call and stop the script on failure (rc 1) or park (rc 3).
mcp_must() {
  local out rc=0
  out="$(mcp_call "$1" "$2")" || rc=$?
  case "$rc" in
    0) printf '%s\n' "$out" ;;
    3) lc_info "  $1 parked for approval (operation $(printf '%s' "$out" | jq -r '.deferred_operation_id // .approval_request_id // "?"')). Approve it, then re-run this command: finished steps are skipped."
       LC_DIE_CODE=3 lc_die "parked for approval; nothing further was done" ;;
    *) LC_DIE_CODE=1 lc_die "$1 failed; stopping here" ;;
  esac
}

# ---- 1. read-only preflight: scans and fast-forward checks -----------------------------------------
resolve() { git -C "$1" rev-parse --verify --quiet "$2^{commit}" || return 1; }
CORE_FULL="$(resolve "$REPO_ROOT" "$CORE_SHA")" || LC_DIE_CODE=2 lc_die "core commit $CORE_SHA is not in this repository"
EXT_FULL=""
if [ -n "$EXT_SHA" ]; then EXT_FULL="$(resolve "$EXT_DIR" "$EXT_SHA")" || LC_DIE_CODE=2 lc_die "extension commit $EXT_SHA is not in $EXT_PATH"; fi

if [ "$NO_FETCH" -eq 0 ]; then
  step 0 "fetch $TARGET from the remotes (read-only)"
  gitc fetch --quiet "$CORE_REMOTE" "$TARGET" || LC_DIE_CODE=1 lc_die "could not fetch $CORE_REMOTE/$TARGET"
  [ -z "$EXT_FULL" ] || gite fetch --quiet "$EXT_REMOTE" "$TARGET" || LC_DIE_CODE=1 lc_die "could not fetch $EXT_REMOTE/$TARGET for $EXT_PATH"
fi
CORE_TIP="$(resolve "$REPO_ROOT" "refs/remotes/$CORE_REMOTE/$TARGET")" || LC_DIE_CODE=1 lc_die "no $CORE_REMOTE/$TARGET ref"
EXT_TIP=""
[ -z "$EXT_FULL" ] || EXT_TIP="$(resolve "$EXT_DIR" "refs/remotes/$EXT_REMOTE/$TARGET")" || LC_DIE_CODE=1 lc_die "no $EXT_REMOTE/$TARGET ref in $EXT_PATH"

if [ "$SKIP_CATALOG" -eq 0 ]; then
  step 1 "the MCP tool catalog is fresh"
  "$SELF_DIR/check-mcp-catalog-fresh.sh" >&2 || LC_DIE_CODE=1 lc_die "the MCP tool catalog is stale; regenerate and commit it before landing"
fi

scan_range() { # repo label base head
  local repo="$1" label="$2" base="$3" head="$4" out rc=0
  out="$(ruby "$SELF_DIR/lib/commit-range-scan.rb" "$repo" "$base..$head" --forbidden-from "$MAIN_ROOT/extensions/private")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf '%s\n' "$out" >&2
    LC_DIE_CODE=1 lc_die "$label range $base..$head failed the publication scan (AI attribution, private-extension name or control byte); nothing was pushed"
  fi
  lc_info "  $label: $(printf '%s' "$out" | jq -r '"\(.commits) commit(s), \(.private_names_checked) private name(s) checked, clean"')"
}
ff_check() { # repo label tip sha
  local repo="$1" label="$2" tip="$3" sha="$4"
  if git -C "$repo" merge-base --is-ancestor "$sha" "$tip"; then
    lc_info "  $label: $sha is already on $TARGET"; return 0
  fi
  git -C "$repo" merge-base --is-ancestor "$tip" "$sha" ||
    LC_DIE_CODE=1 lc_die "$label: $sha is not a fast-forward of $TARGET ($tip); rebase it onto the remote first"
}

step 2 "publication scan and fast-forward checks"
ff_check "$REPO_ROOT" core "$CORE_TIP" "$CORE_FULL"
if gitc merge-base --is-ancestor "$CORE_FULL" "$CORE_TIP"; then :; else scan_range "$REPO_ROOT" core "$CORE_TIP" "$CORE_FULL"; fi
if [ -n "$EXT_FULL" ]; then
  ff_check "$EXT_DIR" extension "$EXT_TIP" "$EXT_FULL"
  if gite merge-base --is-ancestor "$EXT_FULL" "$EXT_TIP"; then :; else scan_range "$EXT_DIR" extension "$EXT_TIP" "$EXT_FULL"; fi
fi

# ---- 2. merge ---------------------------------------------------------------------------------------
BUILD_BASE="$CORE_TIP"
FINAL_CORE="$CORE_FULL"; POINTER_COMMIT=""
gitlink_at() { gitc ls-tree "$1" "$EXT_PATH" 2>/dev/null | awk '{print $3}'; }

make_pointer_commit() {
  local parent="$1" idx tree scope short
  idx="$(mktemp -u)"
  GIT_INDEX_FILE="$idx" git -C "$REPO_ROOT" read-tree "$parent"
  GIT_INDEX_FILE="$idx" git -C "$REPO_ROOT" update-index --cacheinfo "160000,$EXT_FULL,$EXT_PATH"
  tree="$(GIT_INDEX_FILE="$idx" git -C "$REPO_ROOT" write-tree)"
  rm -f "$idx"
  scope="$(basename "$EXT_PATH")"; short="${EXT_FULL:0:12}"
  git -C "$REPO_ROOT" commit-tree "$tree" -p "$parent" -m "chore($scope): bump extension pointer to $short"
}

need_pointer=0
if [ -n "$EXT_FULL" ] && [ "$(gitlink_at "$CORE_FULL")" != "$EXT_FULL" ]; then need_pointer=1; fi

core_on_target=0; gitc merge-base --is-ancestor "$CORE_FULL" "$CORE_TIP" && core_on_target=1
ext_on_target=1; [ -z "$EXT_FULL" ] || { ext_on_target=0; gite merge-base --is-ancestor "$EXT_FULL" "$EXT_TIP" && ext_on_target=1; }
pointer_on_target=1
if [ "$need_pointer" -eq 1 ]; then [ "$(gitlink_at "$CORE_TIP")" = "$EXT_FULL" ] || pointer_on_target=0; fi

# Waits until the remote target contains <sha>; used after an mcp merge dispatch.
wait_for_target() { # repo remote sha label
  local waited=0
  while ! { git -C "$1" fetch --quiet "$2" "$TARGET" && git -C "$1" merge-base --is-ancestor "$3" "refs/remotes/$2/$TARGET"; }; do
    [ "$waited" -lt "${LAND_MERGE_TIMEOUT:-900}" ] || LC_DIE_CODE=1 lc_die "$4 did not reach $TARGET within ${LAND_MERGE_TIMEOUT:-900}s"
    sleep "$POLL_INTERVAL"; waited=$((waited + POLL_INTERVAL))
  done
}

step 3 "merge ($MERGE_VIA)"
case "$MERGE_VIA" in
  none)
    [ "$core_on_target" -eq 1 ] && [ "$ext_on_target" -eq 1 ] && [ "$pointer_on_target" -eq 1 ] ||
      LC_DIE_CODE=1 lc_die "--merge-via none, but not everything is on $TARGET yet"
    ;;
  git)
    if [ "$DRY" -eq 1 ]; then
      [ "$ext_on_target" -eq 1 ] || would "push extension $EXT_FULL to $EXT_REMOTE:$TARGET"
      [ "$core_on_target" -eq 1 ] || would "push core $CORE_FULL to $CORE_REMOTE:$TARGET"
      [ "$pointer_on_target" -eq 1 ] || would "commit a gitlink bump to ${EXT_FULL:0:12} on top of it and push that"
    else
      if [ "$ext_on_target" -eq 0 ]; then
        gite push --quiet "$EXT_REMOTE" "$EXT_FULL:refs/heads/$TARGET" || LC_DIE_CODE=1 lc_die "extension push was refused; nothing further was done"
        lc_info "  extension pushed"
      fi
      if [ "$core_on_target" -eq 0 ]; then
        gitc push --quiet "$CORE_REMOTE" "$CORE_FULL:refs/heads/$TARGET" || LC_DIE_CODE=1 lc_die "core push was refused; the extension is already pushed"
        lc_info "  core pushed"
      fi
      if [ "$pointer_on_target" -eq 0 ]; then
        parent="$CORE_FULL"; [ "$core_on_target" -eq 1 ] && parent="$CORE_TIP"
        POINTER_COMMIT="$(make_pointer_commit "$parent")"
        gitc push --quiet "$CORE_REMOTE" "$POINTER_COMMIT:refs/heads/$TARGET" || LC_DIE_CODE=1 lc_die "the pointer bump push was refused; core and the extension are already pushed"
        lc_info "  pointer bump ${POINTER_COMMIT:0:12} pushed"
      fi
    fi
    ;;
  mcp)
    if [ "$DRY" -eq 1 ]; then
      [ "$core_on_target" -eq 1 ] || would "dev_merge_increment core $CORE_FULL"
      [ "$ext_on_target" -eq 1 ] && [ "$pointer_on_target" -eq 1 ] || would "dev_merge_increment extension $EXT_FULL with a pointer bump"
    else
      attest="$(json_arg "$ATTEST")"
      if [ "$core_on_target" -eq 0 ]; then
        [ -n "$CORE_REF" ] || usage_die "--merge-via mcp needs --core-source-ref"
        mcp_must dev_merge_increment "$(jq -cn --arg r "$LAND_CORE_REPOSITORY" --arg s "$CORE_REF" --arg t "$TARGET" --arg sha "$CORE_FULL" --argjson a "$attest" \
          '{repository:$r, source_ref:$s, target_branch:$t, expected_source_sha:$sha, gate_attestation:$a}')" >/dev/null
        wait_for_target "$REPO_ROOT" "$CORE_REMOTE" "$CORE_FULL" core
      fi
      if [ -n "$EXT_FULL" ] && { [ "$ext_on_target" -eq 0 ] || [ "$pointer_on_target" -eq 0 ]; }; then
        [ -n "$EXT_REF" ] || usage_die "--merge-via mcp needs --ext-source-ref"
        mcp_must dev_merge_increment "$(jq -cn --arg r "$LAND_EXT_REPOSITORY" --arg p "$LAND_CORE_REPOSITORY" --arg path "$EXT_PATH" \
          --arg s "$EXT_REF" --arg t "$TARGET" --arg sha "$EXT_FULL" --argjson a "$attest" \
          '{repository:$r, source_ref:$s, target_branch:$t, expected_source_sha:$sha, gate_attestation:$a,
            pointer_bump:{parent_repository:$p, submodule_path:$path}}')" >/dev/null
        wait_for_target "$EXT_DIR" "$EXT_REMOTE" "$EXT_FULL" extension
        gitc fetch --quiet "$CORE_REMOTE" "$TARGET"
      fi
    fi
    ;;
esac

# The core commit the build and the hub check are about: the pointer commit we made, the tip an
# approved dev_merge_increment left behind, the tip a --merge-via none / already-landed run found, or the
# reviewed commit itself.
if [ -n "$POINTER_COMMIT" ]; then
  FINAL_CORE="$POINTER_COMMIT"
elif [ "$MERGE_VIA" = mcp ] && [ "$DRY" -eq 0 ]; then
  gitc fetch --quiet "$CORE_REMOTE" "$TARGET"
  FINAL_CORE="$(resolve "$REPO_ROOT" "refs/remotes/$CORE_REMOTE/$TARGET")"
elif [ "$core_on_target" -eq 1 ]; then
  FINAL_CORE="$CORE_TIP"
fi

# ---- 3. build --------------------------------------------------------------------------------------
SOURCE_REPO="${LAND_SOURCE_REPO:-}"
if [ -z "$SOURCE_REPO" ]; then
  url="$(gitc remote get-url "$CORE_REMOTE" 2>/dev/null || true)"
  SOURCE_REPO="$(printf '%s' "${url%.git}" | awk -F'[/:]' 'NF>=2{print $(NF-1) "/" $NF}')"
fi
[ -n "$SOURCE_REPO" ] || LC_DIE_CODE=2 lc_die "cannot derive the core source repository; set LAND_SOURCE_REPO"

IFS=',' read -r -a SLUGS <<<"$MODULES"
slugs_json="$(printf '%s\n' "${SLUGS[@]}" | jq -R . | jq -sc .)"
BATCH_ID=""; BATCH_STATUS="not_run"; DISPATCHED_AT="$(date +%s)"
step 4 "build batch $BUILD_BASE..$FINAL_CORE for: $MODULES"
if [ "$DRY" -eq 1 ]; then
  would "dispatch_module_build_batch base=${BUILD_BASE:0:12} head=${FINAL_CORE:0:12} source_repo=$SOURCE_REPO modules=$MODULES expand_dependents=false"
  would "poll get_module_build_batch until finished (every ${POLL_INTERVAL}s, at most ${POLL_TIMEOUT}s)"
else
  out="$(mcp_must system_dispatch_module_build_batch "$(jq -cn --arg b "$BUILD_BASE" --arg h "$FINAL_CORE" --arg r "$SOURCE_REPO" --argjson m "$slugs_json" \
    '{base_sha:$b, head_sha:$h, source_repo:$r, module_slugs:$m, expand_dependents:false, trigger:"manual"}')")"
  BATCH_ID="$(printf '%s' "$out" | jq -r '.module_build_batch.id // empty')"
  [ -n "$BATCH_ID" ] || LC_DIE_CODE=1 lc_die "the dispatch answered without a batch id"
  lc_info "  batch $BATCH_ID"
  poll_started=$SECONDS
  while :; do
    polled_at=$SECONDS
    out="$(mcp_must system_get_module_build_batch "$(jq -cn --arg id "$BATCH_ID" '{batch_id:$id, wait_seconds:30}')")"
    BATCH_STATUS="$(printf '%s' "$out" | jq -r '.module_build_batch.status')"
    case "$BATCH_STATUS" in
      complete) break ;;
      partial|failed|cancelled)
        LC_DIE_CODE=1 lc_die "build batch $BATCH_ID ended $BATCH_STATUS: $(printf '%s' "$out" | jq -r '[.module_build_batch.modules[]? | select(.state != "succeeded") | "\(.module)=\(.state)"] | join(", ")'); nothing was promoted" ;;
    esac
    [ $((SECONDS - poll_started)) -lt "$POLL_TIMEOUT" ] || LC_DIE_CODE=1 lc_die "build batch $BATCH_ID still $BATCH_STATUS after ${POLL_TIMEOUT}s; nothing was promoted"
    # The verb long-polls; only pace ourselves when it answered at once.
    if [ $((SECONDS - polled_at)) -lt 5 ]; then sleep "$POLL_INTERVAL"; fi
  done
  lc_info "  batch complete"
fi

# ---- 4. promote ------------------------------------------------------------------------------------
declare -A MODULE_ID=()
resolve_module_ids() {
  local slug cursor="" page out
  for slug in "${SLUGS[@]}"; do [ -z "${MODULE_ID_OVERRIDE[$slug]:-}" ] || MODULE_ID[$slug]="${MODULE_ID_OVERRIDE[$slug]}"; done
  local missing=0; for slug in "${SLUGS[@]}"; do [ -n "${MODULE_ID[$slug]:-}" ] || missing=1; done
  [ "$missing" -eq 1 ] || return 0
  for page in 1 2 3 4 5 6 7 8 9 10; do
    out="$(mcp_must system_list_modules "$(jq -cn --arg c "$cursor" '{limit:100} + (if $c == "" then {} else {cursor:$c} end)')")"
    for slug in "${SLUGS[@]}"; do
      [ -n "${MODULE_ID[$slug]:-}" ] || MODULE_ID[$slug]="$(printf '%s' "$out" | jq -r --arg n "$slug" '[.modules[]? | select(.name == $n) | .id] | first // empty')"
    done
    cursor="$(printf '%s' "$out" | jq -r '.next_cursor // empty')"
    [ -n "$cursor" ] || break
  done
  for slug in "${SLUGS[@]}"; do
    [ -n "${MODULE_ID[$slug]:-}" ] || LC_DIE_CODE=1 lc_die "no module named '$slug' in the module list; pass --module-id $slug=<uuid>"
  done
}

step 5 "promote ($PROMOTE_ENVS)"
PROMOTED="[]"
if [ "$DRY" -eq 1 ]; then
  would "resolve module ids for: $MODULES"
  for env in $PROMOTE_ENVS; do would "promote_module_version into '$env' for each module, in order"; done
else
  resolve_module_ids
  for env in $PROMOTE_ENVS; do
    for slug in "${SLUGS[@]}"; do
      out="$(mcp_must system_promote_module_version "$(jq -cn --arg e "$env" --arg m "${MODULE_ID[$slug]}" '{environment:$e, module_id:$m}')")"
      lc_info "  $slug -> $env $(printf '%s' "$out" | jq -r '.promotion_criteria_warning // "ok"' | head -c 200)"
      PROMOTED="$(printf '%s' "$PROMOTED" | jq -c --arg e "$env" --arg s "$slug" '. + [{environment:$e, module:$s}]')"
    done
  done
fi

# ---- 5. verify -------------------------------------------------------------------------------------
VERIFY='{"status":"skipped"}'
step 6 "verify the hub"
if [ "$SKIP_VERIFY" -eq 1 ]; then
  lc_info "  skipped (--skip-verify)"
elif [ "$DRY" -eq 1 ]; then
  would "verify-hub-deploy.sh ${FINAL_CORE:0:12}${EXT_FULL:+ ${EXT_FULL:0:12}} --since <dispatch time>"
else
  vout=""; vrc=0
  vout="$("${LAND_VERIFY_SCRIPT:-$SELF_DIR/verify-hub-deploy.sh}" "$FINAL_CORE" ${EXT_FULL:+"$EXT_FULL"} --since "$DISPATCHED_AT")" || vrc=$?
  VERIFY="$(printf '%s' "$vout" | jq -c . 2>/dev/null || echo '{}')"
  [ "$vrc" -eq 0 ] || { printf '%s\n' "$VERIFY" >&2; LC_DIE_CODE=1 lc_die "hub verification failed (verify-hub-deploy.sh exit $vrc); the task must not be completed"; }
fi

# ---- 6. evidence -----------------------------------------------------------------------------------
ev_json="{}"; [ -z "$EVIDENCE" ] || ev_json="$(json_arg "$EVIDENCE")"
landing="$(jq -cn --arg core "$FINAL_CORE" --arg ext "$EXT_FULL" --arg batch "$BATCH_ID" --arg bstatus "$BATCH_STATUS" \
  --arg target "$TARGET" --arg via "$MERGE_VIA" --argjson promoted "$PROMOTED" --argjson verify "$VERIFY" --argjson dry "$DRY" \
  '{landed_core_sha:$core, landed_ext_sha:(if $ext == "" then null else $ext end), target_branch:$target, merge_via:$via,
    batch_id:(if $batch == "" then null else $batch end), batch_status:$bstatus, promoted:$promoted, hub_verification:$verify,
    dry_run:($dry == 1)}')"
check_results="$(jq -cn --argjson l "$landing" --argjson e "$ev_json" '{landing:$l} + (if ($e | length) > 0 then {evidence:$e} else {} end)')"
complete_args="$(jq -cn --arg loop "$LOOP" --arg key "$TASK_KEY" --arg sha "$FINAL_CORE" --argjson cr "$check_results" \
  '{loop_id:$loop, task_key:$key, outcome:"passed", summary:("Landed on the target branch, built, promoted and verified by scripts/land.sh"), commit_sha:$sha, check_results:$cr}')"

if [ "$COMPLETE" -eq 1 ] && [ "$DRY" -eq 0 ]; then
  step 7 "dev_complete_task"
  [ "$ev_json" != "{}" ] || lc_info "  no --evidence given: the pass will record as attested, not verified"
  mcp_must dev_complete_task "$complete_args" >/dev/null
  lc_info "  task $TASK_KEY completed"
elif [ "$COMPLETE" -eq 1 ]; then
  would "dev_complete_task for $TASK_KEY on loop $LOOP"
fi
printf '%s\n' "$complete_args"
lc_info "$( [ "$DRY" -eq 1 ] && echo 'dry-run finished: nothing was pushed, built or promoted' || echo 'landing finished' )"
