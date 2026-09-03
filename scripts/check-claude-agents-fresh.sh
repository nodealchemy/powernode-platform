#!/bin/bash
# Guard: .claude/agents/powernode/*.md (the COMMITTED Claude Code skeletons of
# the platform's CANONICAL agents — global, seeded, is_system) must reflect the
# canonical agents as `rails claude:sync_agents` renders them today
# (Ai::ClaudeExport::AgentSkeletonSync: routing description, tools allowlist,
# delegation section, BASE_GUARDRAILS). A seed change that adds/renames/retiers a
# canonical agent, or a renderer change, makes this fail until the files are
# regenerated and committed.
#
# Same shape as check-mcp-catalog-fresh.sh: regenerate with the PUBLIC bundle
# into a TEMP directory (never the tracked one — this check has no side
# effects), diff against the committed directory, exit by outcome:
#   0  fresh         regenerated set == committed set
#   1  stale         a file differs / is missing / is extra
#   2  unverifiable  the generator SUCCEEDED and produced NO canonical agent. The
#                    export reads the development database, and an install whose
#                    platform agent seeds never ran (fresh clone, reset dev DB)
#                    holds no canonical row — an EMPTY set is not evidence the
#                    committed files are stale, but it is not evidence they are
#                    fresh either, so this is reported as a WARN by
#                    pattern-validation.sh, never as a PASS.
#   3  broken        the generator itself FAILED (nonzero exit): a renderer
#                    exception, a pending migration, a bundle failure. This
#                    MUST NOT collapse into 2 — an unseeded checkout is the
#                    steady state here, so reporting a crash as the benign WARN
#                    hides every regression the check exists to catch. The
#                    generator's own output is replayed so the cause is visible.
#
# Test seams (scripts/checks/tests/check-claude-agents-fresh-test.sh):
#   CLAUDE_AGENTS_SYNC_CMD  replaces the generator; it must write into $TARGET_DIR
#   CLAUDE_AGENTS_DIR       replaces the committed directory
set -uo pipefail

cd "$(git rev-parse --show-toplevel)"

COMMITTED="${CLAUDE_AGENTS_DIR:-.claude/agents/powernode}"
REGEN_CMD='cd server && env -u BUNDLE_GEMFILE POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=0 POWERNODE_DEPLOYED=0 bundle exec rails claude:sync_agents'

tmp="$(mktemp -d)"
sync_log="$tmp.log"
trap 'rm -rf "$tmp" "$sync_log"' EXIT
export TARGET_DIR="$tmp"

# PIN THE GENERATION ENVIRONMENT (see check-mcp-catalog-fresh.sh): the tools
# allowlist reads PlatformApiToolRegistry.all_tools, which grows with the loaded
# extension engines under the maintainer bundle / a deployed node; the TRACKED
# files are the PUBLIC-bundle rendering. ACCOUNT_ID / INCLUDE_ACCOUNT are cleared
# so a caller's shell cannot turn the canonical export into an account export.
# The generator's exit status is LOAD-BEARING (never `>/dev/null 2>&1` alone):
# a crash also writes zero files, and zero files is the benign "unseeded
# checkout" WARN, so an ignored status would report every generator regression
# as the outcome this cell already reports on a good day.
if [[ -n "${CLAUDE_AGENTS_SYNC_CMD:-}" ]]; then
    bash -c "$CLAUDE_AGENTS_SYNC_CMD" >"$sync_log" 2>&1
    sync_status=$?
else
    (cd server && env -u BUNDLE_GEMFILE -u ACCOUNT_ID -u INCLUDE_ACCOUNT \
        POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=0 POWERNODE_DEPLOYED=0 \
        bundle exec rails claude:sync_agents) >"$sync_log" 2>&1
    sync_status=$?
fi

if [[ "$sync_status" -ne 0 ]]; then
    echo "Claude agent skeleton freshness could NOT be checked: the export FAILED (exit $sync_status)." >&2
    echo "  This is a broken generator, not an unseeded checkout — fix it, then re-run:" >&2
    echo "  $REGEN_CMD" >&2
    tail -n 20 "$sync_log" >&2 || true
    exit 3
fi

regen_count="$(find "$tmp" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)"
if [[ "$regen_count" -eq 0 ]]; then
    echo "Claude agent skeleton freshness is UNVERIFIABLE: the export produced no canonical agent." >&2
    echo "  The development database holds no global, is_system agent (platform agent seeds never ran here)." >&2
    echo "  Regenerate on a seeded install with: $REGEN_CMD" >&2
    exit 2
fi

mkdir -p "$COMMITTED"
if diff -r "$COMMITTED" "$tmp" >/dev/null 2>&1; then
    exit 0
fi

echo "Claude agent skeletons are stale — .claude/agents/powernode/ no longer matches the canonical agents:" >&2
diff -rq "$COMMITTED" "$tmp" 2>&1 | sed "s#$tmp#<regenerated>#g" >&2
echo "Regenerate with the PUBLIC bundle and commit the result (chore(claude)):" >&2
echo "  $REGEN_CMD" >&2
exit 1
