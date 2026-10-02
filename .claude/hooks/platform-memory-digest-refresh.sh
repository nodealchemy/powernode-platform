#!/bin/bash
# Stop hook (IMP-de4ca2d3f7c5) — refreshes the platform-memory digest cache.
#
# Memory lives on the platform (Ai::SharedKnowledge tagged `memory`). A session that starts
# during an MCP blackout still needs it, so this renders Ai::MemoryDigest into the gitignored
# .claude/hooks/platform-memory-digest.local.md, which session-guidance-inject.sh prints at
# SessionStart. Same shape as codebase-index-apply.sh: the Rails boot is backgrounded so the
# hook returns inside its budget.
#
# Throttled to once per hour by a stamp file touched BEFORE the run, so a run that fails or
# produces nothing is not retried on every Stop. NEVER blocks — always exit 0.

cat >/dev/null 2>&1

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-/opt/powernode}"
HOOKS_DIR="$PROJECT_DIR/.claude/hooks"
DIGEST="$HOOKS_DIR/platform-memory-digest.local.md"
STAMP="$HOOKS_DIR/platform-memory-digest.local.stamp"
THROTTLE_SECONDS=3600

[[ -d "$PROJECT_DIR/server" ]] || exit 0
command -v bundle >/dev/null 2>&1 || exit 0

if [[ -f "$STAMP" ]]; then
  last="$(stat -c %Y "$STAMP" 2>/dev/null || echo 0)"
  now="$(date +%s)"
  age=$(( now - last ))
  # A future-dated stamp (clock skew) is stale, not fresh.
  (( age >= 0 && age < THROTTLE_SECONDS )) && exit 0
fi

mkdir -p "$HOOKS_DIR" 2>/dev/null
touch "$STAMP" 2>/dev/null

# flock -n: concurrent Stop hooks boot Rails once; timeout: a hung DB connect cannot pile up.
run_refresh() {
  cd "$PROJECT_DIR/server" || exit 1
  POWERNODE_MEMORY_DIGEST_PATH="$DIGEST" bundle exec rails runner \
    'Ai::MemoryDigest.write!(ENV.fetch("POWERNODE_MEMORY_DIGEST_PATH"))' >/dev/null 2>&1
}
(
  if command -v flock >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
    export PROJECT_DIR DIGEST
    exec 9>"$STAMP.lock" && flock -n 9 || exit 0
    timeout 180 bash -c "$(declare -f run_refresh); run_refresh"
  else
    run_refresh
  fi
) >/dev/null 2>&1 &

exit 0
