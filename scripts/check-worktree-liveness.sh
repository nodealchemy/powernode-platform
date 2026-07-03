#!/usr/bin/env bash
# check-worktree-liveness.sh — is anything actually alive/working in a worktree right now?
#
# WHY THIS EXISTS
# ----------------
# During overnight multi-agent drains, "is this worktree still in use" was answered ad hoc with a
# manual ps + PPID-tracing procedure repeated by hand across sessions — and got it wrong at least
# once (an agent misidentified its own background process as a foreign collision). This script
# standardizes that procedure: find every process referencing the worktree path, walk each one's
# ancestry back to the nearest `claude --resume <session-id>` process, and classify it as OWN
# (same session that invoked this script), FOREIGN (a different session), or UNKNOWN (no claude
# ancestor found — can't prove either way). Read-only: it only reports, never signals/kills.
#
# USAGE
#   scripts/check-worktree-liveness.sh <worktree-path> [own-session-id]
#
# own-session-id is the Claude Code session id (as passed to `claude --resume <id>`) that is
# invoking this script. If omitted, it is derived by walking this script's OWN process ancestry
# for a `claude --resume <session-id>` frame — this works because the script is normally invoked
# from within that session's Bash tool, so its own parent chain IS the "own session" chain.
#
# EXIT CODES
#   0 — clear: no live processes reference the worktree path
#   1 — own-session activity found (descends from own-session-id), nothing foreign/unknown
#   2 — foreign or unknown activity found (review before acting)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
  echo "Usage: $0 <worktree-path> [own-session-id]" >&2
  exit 64
}

[[ $# -ge 1 && $# -le 2 ]] || usage

WORKTREE_PATH="$1"
OWN_SESSION_ID="${2:-}"

if [[ ! -d "$WORKTREE_PATH" ]]; then
  echo "error: worktree path does not exist: $WORKTREE_PATH" >&2
  exit 64
fi

# Normalize to an absolute, symlink-resolved path so substring matching against /proc cmdlines
# (which the kernel reports fully-resolved) doesn't miss matches due to a relative or symlinked
# path from the caller.
WORKTREE_PATH="$(cd "$WORKTREE_PATH" && pwd -P)"

# ps -eo pid,ppid,etimes,cmd gives us everything in one pass; process-handling style follows
# this repo's existing convention of shelling to `ps`/`pgrep` rather than parsing /proc directly
# (see scripts/manage-proxy-hosts.sh). `|| true` keeps a transient ps failure from tripping
# `set -e` and aborting with no diagnostic — an empty snapshot just yields zero matches below.
PS_SNAPSHOT="$(ps -eo pid=,ppid=,etimes=,cmd= 2>/dev/null || true)"

# Build lookup tables: PPID_OF[pid]=ppid, ETIMES_OF[pid]=elapsed, CMD_OF[pid]=cmd
# `read` with exactly 4 target vars puts all remaining whitespace-split fields into the last
# one (cmd), so this naturally reassembles a multi-word command line without extra awk/sed passes.
declare -A PPID_OF ETIMES_OF CMD_OF
while IFS=' ' read -r pid ppid etimes cmd; do
  [[ -z "$pid" ]] && continue
  PPID_OF["$pid"]="$ppid"
  ETIMES_OF["$pid"]="$etimes"
  CMD_OF["$pid"]="$cmd"
done <<<"$PS_SNAPSHOT"

# find_claude_session_ancestor <pid> — walk ppid chain from pid; return (via echo) the session id
# of the nearest ancestor (or self) matching `claude ... --resume <session-id>`, or empty if none
# found by the time we hit pid 1 or run out of known ancestors.
#
# The "claude" token is anchored to start-of-string or a preceding space/slash so it matches the
# binary name (or its path), not an arbitrary substring inside an unrelated flag like
# "--claude-workdir" — that would otherwise fabricate a session id from a non-claude process.
find_claude_session_ancestor() {
  local pid="$1"
  local guard=0
  while [[ -n "$pid" && "$pid" != "0" && "$pid" != "1" && $guard -lt 200 ]]; do
    local cmd="${CMD_OF[$pid]:-}"
    if [[ "$cmd" =~ (^|[[:space:]/])claude[^[:space:]]*[[:space:]].*--resume[[:space:]]+([^[:space:]]+) ]]; then
      echo "${BASH_REMATCH[2]}"
      return 0
    fi
    pid="${PPID_OF[$pid]:-}"
    guard=$((guard + 1))
  done
  return 1
}

# Derive our own session id if not supplied, by tracing our own ancestry the same way.
if [[ -z "$OWN_SESSION_ID" ]]; then
  OWN_SESSION_ID="$(find_claude_session_ancestor "$$" || true)"
fi

if [[ -z "$OWN_SESSION_ID" ]]; then
  echo -e "${YELLOW}warning:${NC} could not determine own Claude session id (no --resume ancestor found for pid $$)." >&2
  echo "          all matches with a claude ancestor will be classified relative to no known 'own' session," >&2
  echo "          so nothing will be classified OWN — pass it explicitly as the second argument if known." >&2
fi

# is_self_invocation <cmd> — true if cmd's own program token (argv[0], or argv[1] when argv[0] is
# a shell interpreter) is this script itself, rather than merely mentioning its filename
# somewhere in arguments/text. Every invocation of this script necessarily has WORKTREE_PATH in
# its own argv (that's how the path gets passed in), so the checker's own process — and a
# sandbox/wrapper duplicate with an identical cmdline — would always self-match on path alone.
# That's noise, not worktree activity, and must be excluded; but the exclusion is deliberately
# narrow (program-token match, not a filename substring search anywhere in the command line) so
# it does NOT also swallow genuine foreign/own activity that merely references the script's name,
# e.g. `grep check-worktree-liveness.sh` or an editor with the script open — those are real
# activity this tool exists to report, not self-noise.
SELF_BASENAME="$(basename "$0")"
is_self_invocation() {
  local cmd="$1"
  local first second
  read -r first second _ <<<"$cmd"
  [[ "$first" == "$SELF_BASENAME" || "$first" == *"/$SELF_BASENAME" ]] && return 0
  case "$first" in
    bash | sh | zsh | dash | */bash | */sh | */zsh | */dash)
      [[ "$second" == "$SELF_BASENAME" || "$second" == *"/$SELF_BASENAME" ]] && return 0
      ;;
  esac
  return 1
}

# Find every live PID whose command line references the worktree path as a whole path component
# (preceded by start-of-string/whitespace, followed by end-of-string/whitespace/"/") rather than
# an unanchored substring — otherwise a sibling worktree whose name is a string-prefix of this
# one (e.g. "liveness-script" vs "liveness-script-v2") would false-match.
# shellcheck disable=SC2016 # single-quoted sed pattern is intentional literal regex, not expansion
WORKTREE_PATH_ESCAPED="$(printf '%s' "$WORKTREE_PATH" | sed 's/[.[\*^$()+?{|]/\\&/g')"
declare -a MATCH_PIDS=()
for pid in "${!CMD_OF[@]}"; do
  cmd="${CMD_OF[$pid]}"
  if [[ "$cmd" =~ (^|[[:space:]])$WORKTREE_PATH_ESCAPED($|[[:space:]/]) ]] && ! is_self_invocation "$cmd"; then
    MATCH_PIDS+=("$pid")
  fi
done

if [[ ${#MATCH_PIDS[@]} -eq 0 ]]; then
  echo -e "${GREEN}clear${NC} — no live processes reference $WORKTREE_PATH"
  exit 0
fi

FOUND_OWN=0
FOUND_OTHER=0

printf "%-8s %-8s %-10s %-10s %s\n" "PID" "PPID" "ELAPSED" "CLASS" "CMD"
printf '%.0s-' {1..100}; echo

for pid in "${MATCH_PIDS[@]}"; do
  ppid="${PPID_OF[$pid]:-?}"
  etimes="${ETIMES_OF[$pid]:-?}"
  cmd="${CMD_OF[$pid]:-?}"

  session_id="$(find_claude_session_ancestor "$pid" || true)"

  if [[ -z "$session_id" ]]; then
    class="UNKNOWN"
    color="$YELLOW"
    FOUND_OTHER=1
  elif [[ -n "$OWN_SESSION_ID" && "$session_id" == "$OWN_SESSION_ID" ]]; then
    class="OWN"
    color="$GREEN"
    FOUND_OWN=1
  else
    class="FOREIGN"
    color="$RED"
    FOUND_OTHER=1
  fi

  printf "%-8s %-8s %-10s ${color}%-10s${NC} %s\n" "$pid" "$ppid" "${etimes}s" "$class" "$cmd"
done

echo
if [[ $FOUND_OTHER -eq 1 ]]; then
  echo -e "${RED}foreign/unknown activity detected${NC} in $WORKTREE_PATH — review before acting."
  exit 2
elif [[ $FOUND_OWN -eq 1 ]]; then
  echo -e "${GREEN}own-session activity${NC} detected in $WORKTREE_PATH."
  exit 1
else
  echo -e "${GREEN}clear${NC} — no live processes reference $WORKTREE_PATH"
  exit 0
fi
