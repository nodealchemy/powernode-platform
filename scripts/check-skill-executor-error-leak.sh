#!/bin/bash
#
# check-skill-executor-error-leak.sh — skill executor error-message leak guard
# =============================================================================
# IMP-8552945f2672. System::Ai::Skills::BaseSkillExecutor#execute's shared
# rescue arm used to be `failure(e.message)` — #perform is subclass-authored,
# unaudited code (67 direct subclasses) that can raise ANYTHING, and this
# result reaches the model provider via system_ingress_tool.rb#run_executor /
# sdwan_tool.rb#run_skill_executor, which forward it verbatim. Fixed by
# routing every rescue arm in this class hierarchy through
# BaseSkillExecutor#safe_error_text / #safe_failure, which forwards a
# message only when the raiser explicitly opted in (Ai::Tools::BaseTool::
# CallerFacingError — the SAME distinction IMP-5ed95e651b80 /
# IMP-f6f80b585b19 established for MCP tools). Every other class gets text
# the helper AUTHORS (a static string, or for RecordNotFound / RecordInvalid
# a message built from the model/attribute names), never its #message; the
# raw cause is recorded server-side (log + audit event) instead.
#
# WHAT THIS FLAGS: a `rescue` clause (any class, anchored to the start of the
# line so a comment/string mention never counts, and joining a multi-line
# class list the same way check-tool-not-found-leak.rb does) whose body
# builds a DIRECT caller-facing return — `failure(...)` or any `failure_*(...)`
# sibling (e.g. `failure_with_partial`), or a bare
# `{ success: ..., error: ... }` hash literal — from the caught variable's
# `.message` / `.to_s` / `.full_message` / `.inspect` / `.detailed_message`,
# or bare-interpolates it, WITHOUT routing through #safe_error_text /
# #safe_failure. Only the helper call itself is treated as safe — the rest of
# the same line is still scanned, so `failure("#{safe_error_text(e)}
# (#{e.message})")` is flagged. A line mentioning "logger" is skipped
# (server-side logging, not the caller-facing return).
#
# SUPPRESSING A SPECIFIC, REVIEWED SITE: a trailing `# skill-error-ok:
# <reason>` on the flagged line — mirrors check-account-scoping.sh's
# `# scoping-ok:`. Use ONLY when every raise site reaching that rescue was
# individually read and confirmed hand-authored, caller-owned text (e.g.
# docker_provision_executor.rb's MissingSdwanPeerError rescue: its one raise
# site names only the account's own node_instance id, but the exception
# class is shared with a DIFFERENT superclass elsewhere so it cannot be
# class-whitelisted in safe_error_text without side effects there). Never
# use it to silence an exception class with any unaudited raise site.
#
# NOT FLAGGED — A KNOWN, SEPARATE, LARGER GAP, not a bug in this guard:
#   `errors << { resource:, id:, error: e.message }` / `failures << { step:,
#   error: e.message }` — an ARRAY PUSH for SkillCompositionRunner rollback/
#   compensation bookkeeping, not a direct return. Found ~60 more sites
#   across ~25 executor files during the IMP-8552945f2672 audit, NOT fixed
#   in that pass (rollback/compensation code; a hasty blanket edit risks a
#   correctness regression worse than the leak it would close, and the
#   surface is large enough to warrant its own dedicated review). This guard
#   deliberately does not attempt them. The follow-up that fixes those sites
#   and extends this guard is filed as dev-improve offer
#   01a0d71d-dfc3-70d6-a472-f02f61c05506. A future guard extension covering this shape
#   needs to tell a bookkeeping array from a returned hash structurally, not
#   just textually.
#
# SCOPE: services/system/ai/skills, core + every extension with the same
# base-executor pattern (only extensions/system has one today).
#
# EXIT CODES
#   0  no hits
#   1  one or more hits
#
# Advisory-friendly: pass --warn to always exit 0 (report-only mode).
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

WARN_ONLY=0
[ "${1:-}" = "--warn" ] && WARN_ONLY=1

# SKILL_LEAK_SCAN_DIRS overrides the search roots for isolated fixture tests,
# mirroring check-tool-not-found-leak.sh's TOOL_LEAK_SCAN_DIRS.
if [ -n "${SKILL_LEAK_SCAN_DIRS:-}" ]; then
  read -r -a SCAN_DIRS <<< "${SKILL_LEAK_SCAN_DIRS}"
else
  SCAN_DIRS=(extensions/*/server/app/services/*/ai/skills)
fi
mapfile -t SKILL_FILES < <(
  find "${SCAN_DIRS[@]}" -iname "*.rb" 2>/dev/null | sort -u
)

# Fail CLOSED when there is nothing to scan: a submodule that was never
# initialised, a moved skills directory or a bad SKILL_LEAK_SCAN_DIRS would
# otherwise report "no leaks" from an empty file list and hide every real
# hit. Same stance as check-tool-not-found-leak.sh for the core tree.
if [ "${#SKILL_FILES[@]}" -eq 0 ]; then
  echo "check-skill-executor-error-leak.sh: found ZERO *.rb skill executor files under" \
       "${SCAN_DIRS[*]} — refusing to report a false all-clear." \
       "Is extensions/system checked out?" >&2
  [ "$WARN_ONLY" -eq 1 ] && exit 0
  exit 1
fi

output="$(ruby "${SCRIPT_DIR}/check-skill-executor-error-leak.rb" "${SKILL_FILES[@]}")"
status=$?

if [ -n "$output" ]; then
  echo "$output"
fi

if [ "$status" -ne 0 ]; then
  [ "$WARN_ONLY" -eq 1 ] && exit 0
  exit 1
fi

exit 0
