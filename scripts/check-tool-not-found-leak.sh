#!/bin/bash
#
# check-tool-not-found-leak.sh — RecordNotFound WHERE-clause leak regression guard
# =============================================================================
# IMP-f6f80b585b19. ActiveRecord::RecordNotFound#message for a SCOPED relation
# (`account.things.find(id)`, `.where(...).find`, any belongs_to/has_many
# finder) appends ` [WHERE "table"."column" = $1]` (Rails 8.1) — a raw table
# and column name. An MCP tool's #call rescue result is persisted to
# ai_messages.processing_metadata and FORWARDED TO THE MODEL PROVIDER, so
# forwarding that message verbatim re-opens exactly the leak the generic
# rescued_error_result fallback (IMP-5ed95e651b80) was built to close.
#
# THE FIX: every tool routes `rescue ActiveRecord::RecordNotFound => e`
# through Ai::Tools::BaseTool#not_found_result(e), which authors the message
# from e.model/e.id (set by Rails on every real finder raise, regardless of
# scope depth) rather than forwarding the exception's own text.
#
# WHAT THIS FLAGS: a `rescue` line, anchored to the start of the line (a
# comment or string literal merely MENTIONING the class never counts) and
# naming ActiveRecord::RecordNotFound anywhere in its class list (`::`-
# prefixed or not, and anywhere the list spans MULTIPLE lines — a rescue
# line ending in `,`, once a trailing comment is stripped, joins following
# lines up to and including the one with `=>` before the class-list search
# runs; review round 3 found five real sites in this codebase using that
# multi-line-list style for a DIFFERENT exception, confirming the shape is
# common enough to matter), whose body — up to the next `rescue`/`ensure`/
# `end` line indented at or below the rescue line itself, so an inner
# `if...end` can't close the scan early — references the caught variable's
# `.message` / `.to_s` / `.full_message` / `.inspect` / `.detailed_message`,
# or bare-interpolates the variable (`#{e}`). A line that mentions "logger"
# is skipped UNLESS it also calls one of this codebase's own error/not-found
# result builders, or returns a literal `{ success: false, error: ... }`
# hash directly (e.g. `Rails.logger.info(...); return
# error_result(e.message)`, or `...; return { success: false, error:
# e.message }`, both still flag — only a line that is PURELY logging is
# exempt). The analysis lives in check-tool-not-found-leak.rb (invoked
# below) rather than hand-rolled awk regex: this repo's default `awk` is
# mawk, which silently no-ops on `\s`/`\w`/`\b` and turns a "match nothing"
# bug into a false green (found the hard way — see
# check_tool_not_found_leak_spec.rb's fixture-based regression coverage).
# Ruby gives real word-boundary regex with no such trap.
#
# NOT FLAGGED (by design — a residual gap, not a bug):
#   - a bare `rescue ActiveRecord::RecordNotFound` with no captured variable,
#     including one that reads the implicit `$!` instead of a named
#     variable (`rescue ActiveRecord::RecordNotFound; error_result($!.message)`);
#   - a RESCUE MODIFIER (`expr rescue expr`, e.g. `v = foo rescue
#     error_result($!.message)`) — it names no class at all (a modifier
#     rescue always catches StandardError implicitly), so it is reachable
#     only via `$!`, same as the point above;
#   - a one-line `begin; ...; rescue ActiveRecord::RecordNotFound => e; ...;
#     end` compound statement — the anchor requires `rescue` to be the
#     FIRST token after leading whitespace, and here `begin` is;
#   - a hand-authored literal message, or `rescued_error_result(e)` /
#     `not_found_result(e)` with no raw-message read (both safe by
#     construction);
#   - a heredoc body inside the clause that happens to contain a line
#     reading exactly `end` — closes the clause's scan early, hiding
#     anything after it in the same rescue body;
#   - a DIFFERENT exception class's own rescue clause (StandardError
#     catch-alls are explicitly out of scope — IMP-f6f80b585b19 review item
#     8, filed as a separate follow-up).
#
# SCOPE: every *.rb under services/ai/tools, recursively (including
# concerns/), core + every extension (including private, when checked out).
#
# EXIT CODES
#   0  no hits
#   1  one or more hits (regression — a RecordNotFound rescue forwards its message)
#
# Advisory-friendly: pass --warn to always exit 0 (report-only mode).
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

WARN_ONLY=0
[ "${1:-}" = "--warn" ] && WARN_ONLY=1

# Scan every *.rb under a services/ai/tools tree, core + extensions (public
# and private, when the private ones are checked out locally).
# TOOL_LEAK_SCAN_DIRS overrides the search roots for isolated fixture tests
# (space-separated list, no glob needed), mirroring check-account-scoping.sh's
# ACCOUNT_SCOPING_DIR, and doubles as the seam for scanning a tree that is NOT
# checked out under this repo at all (e.g. a private extension's own
# standalone checkout, or a temp copy with a not-yet-landed patch applied) —
# point it at that path directly. Left unset, the default globs
# are expanded by the shell (unquoted, on purpose) so each matching
# extension directory is its own arg.
if [ -n "${TOOL_LEAK_SCAN_DIRS:-}" ]; then
  read -r -a SCAN_DIRS <<< "${TOOL_LEAK_SCAN_DIRS}"
else
  SCAN_DIRS=(server/app/services/ai/tools extensions/*/server/app/services/ai/tools extensions/private/*/server/app/services/ai/tools)
fi
# Fail CLOSED, not open, when the CORE default tree is missing or empty — a
# renamed/moved directory or a broken checkout would otherwise silently
# report "no leaks" from an empty file list, hiding every real hit that
# would otherwise fire. Checked independently of the extension globs below
# (which legitimately resolve to nothing on a core-only install) and skipped
# entirely when TOOL_LEAK_SCAN_DIRS overrides the scan roots — an explicit
# override (isolated fixture tests) is trusted as-is; an empty result there
# is the caller's own deliberate scope.
if [ -z "${TOOL_LEAK_SCAN_DIRS:-}" ]; then
  core_count=$(find server/app/services/ai/tools -iname "*.rb" 2>/dev/null | wc -l)
  if [ "${core_count:-0}" -eq 0 ]; then
    echo "check-tool-not-found-leak.sh: found ZERO *.rb files under" \
         "server/app/services/ai/tools — refusing to report a false" \
         "all-clear. Is the tree missing or moved?" >&2
    [ "$WARN_ONLY" -eq 1 ] && exit 0
    exit 1
  fi
fi

mapfile -t TOOL_FILES < <(
  find "${SCAN_DIRS[@]}" -iname "*.rb" 2>/dev/null | sort -u
)

[ "${#TOOL_FILES[@]}" -eq 0 ] && exit 0

output="$(ruby "${SCRIPT_DIR}/check-tool-not-found-leak.rb" "${TOOL_FILES[@]}")"
status=$?

if [ -n "$output" ]; then
  echo "$output"
fi

if [ "$status" -ne 0 ]; then
  [ "$WARN_ONLY" -eq 1 ] && exit 0
  exit 1
fi

exit 0
