#!/bin/bash
# Guard: .claude/agents/powernode/*.md (the COMMITTED Claude Code skeletons —
# since streamlining campaign C4 the thin loaders of the four canonical-roster
# survivors, Ai::Agents::CanonicalRoster) must match what `rails
# claude:sync_agents` renders today (Ai::ClaudeExport::ThinLoader). A roster or
# renderer change makes this fail until the files are regenerated and
# committed. The thin loaders read no database row, so a seed change cannot.
#
# Same shape as check-mcp-catalog-fresh.sh: regenerate with the PUBLIC bundle
# into a TEMP directory (never the tracked one — this check has no side
# effects), diff against the committed directory, exit by outcome:
#   0  fresh         regenerated set == committed set
#   1  stale         a file differs / is missing / is extra
#   2  unverifiable  the generator SUCCEEDED and produced NO file. The canonical
#                    export no longer reads the database, so this now means a
#                    generator that wrote nothing; it is still reported as a WARN
#                    by pattern-validation.sh, never as a PASS.
#   3  broken        the generator itself FAILED (nonzero exit): a renderer
#                    exception, a pending migration, a bundle failure. This
#                    MUST NOT collapse into 2 — an unseeded checkout is the
#                    steady state here, so reporting a crash as the benign WARN
#                    hides every regression the check exists to catch. The
#                    generator's own output is replayed so the cause is visible.
#
# SIZE GATE: scripts/check-claude-agents-size.sh (per-agent tools-list and
# whole-roster byte ceilings, which can only be lowered) runs first, against the
# same committed directory. It needs no database, so it is enforced even on an
# unseeded checkout: a size violation turns outcome 0 or 2 into 1. Outcome 3
# (broken generator) is left as 3, and 1 stays 1.
#
# Test seams (scripts/checks/tests/check-claude-agents-fresh-test.sh):
#   CLAUDE_AGENTS_SYNC_CMD  replaces the generator; it must write into $TARGET_DIR
#   CLAUDE_AGENTS_DIR       replaces the committed directory
set -uo pipefail

cd "$(git rev-parse --show-toplevel)"

COMMITTED="${CLAUDE_AGENTS_DIR:-.claude/agents/powernode}"
REGEN_CMD='cd server && env -u BUNDLE_GEMFILE POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=0 POWERNODE_DEPLOYED=0 bundle exec rails claude:sync_agents'

# Size gate first; its output goes to stderr with the rest of this check.
size_status=0
CLAUDE_AGENTS_DIR="$COMMITTED" bash scripts/check-claude-agents-size.sh >&2 || size_status=$?

# finish STATUS: exit with STATUS, raised to 1 (a FAIL) when the size gate failed,
# except that a broken generator (3) keeps its own outcome.
finish() {
    local status="$1"
    if [[ "$size_status" -ne 0 && "$status" -ne 3 ]]; then
        status=1
    fi
    exit "$status"
}

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
    echo "  The thin loaders could not be rendered (Ai::Agents::CanonicalRoster / ThinLoader failed to load)." >&2
    echo "  Fix the loader, then regenerate with: $REGEN_CMD" >&2
    finish 2
fi

mkdir -p "$COMMITTED"
if diff -r "$COMMITTED" "$tmp" >/dev/null 2>&1; then
    finish 0
fi

echo "Claude agent skeletons are stale — .claude/agents/powernode/ no longer matches the canonical agents:" >&2
diff -rq "$COMMITTED" "$tmp" 2>&1 | sed "s#$tmp#<regenerated>#g" >&2
echo "Regenerate with the PUBLIC bundle and commit the result (chore(claude)):" >&2
echo "  $REGEN_CMD" >&2
exit 1
