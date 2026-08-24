#!/usr/bin/env bash
# declared-but-unconsumed.sh — catch INERT declarations at merge time.
# =============================================================================
# THE FAILURE MODE THIS EXISTS FOR
#
# This codebase's dominant defect class is not the broken mechanism; it is the
# mechanism that exists, passes review, and never fires. Month-scale examples,
# all found by investigation rather than by any test:
#
#   - the content-addressed build skip: shipped, default-ON, never once fired
#     (four stacked defects, each hiding the next)
#   - SystemTaskReaperJob: scoped on a field no row has ever had, reported
#     "0 reaped, success" hourly for five weeks while 34 tasks piled up
#   - the whole worker-scoped task-dispatch chain: never ran in production
#   - `partial` set by ten executors and read by no consumer
#   - HeartbeatPayload fields whose doc-comments name a consumer that does not
#     read them
#
# Each was caught one at a time, by a person looking. The class regenerates
# because nothing structurally prevents shipping a declaration with no other
# end. This check is that structure, for the cheap mechanical half: a symbol
# DECLARED in a registry with no reference anywhere else is inert by
# construction, and that is greppable.
#
# WHY A RATCHET, NOT A CLEAN GATE
#
# The debt predates the check. Turning it on as a clean gate would fail the
# build for everyone on day one, so the known-unconsumed set is listed below
# and the check fails only on symbols NOT in that list. The list is a debt
# ledger, not an exemption: entries should be removed by deleting the dead
# declaration or building its producer, never by adding to it casually.
#
# HONEST LIMIT — READ BEFORE TRUSTING A RESULT
#
# Core mode has no private extensions on disk (extensions/private/* is absent
# in a public clone). A type produced ONLY by a private extension is therefore
# indistinguishable here from one produced by nobody. Several ledger entries
# below are almost certainly in that category (billing/subscription/payment
# shapes belong to the business extension). They are recorded as UNCLASSIFIED
# rather than guessed: this script cannot tell, and pretending otherwise would
# be the same prose-contract mistake it exists to catch.
#
# Usage: bash scripts/checks/declared-but-unconsumed.sh [--list]
#   (no args) prints the COUNT of unconsumed symbols missing from the ledger
#   --list    prints those symbols, one per line, for a human to triage
#
# Exit status is always 0; pattern-validation.sh judges the count.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODE="${1:-count}"

# ── Debt ledger ──────────────────────────────────────────────────────────────
# Symbols declared but referenced nowhere else in the OPEN tree, as of
# 2026-08-24. Each needs a producer built, or the declaration deleted.
#
# UNCLASSIFIED-PRIVATE: plausibly produced by extensions/private/* (absent in
# core mode) — cannot be verified from a public clone, must not be deleted on
# this evidence alone.
LEDGER_NOTIFICATION_TYPES="
billing_reminder
subscription_update
payment_failed
usage_warning
"
# GENUINELY UNPRODUCED in the open tree — these are the real debt. The
# autonomy_approval_* pair is filed as offer 01a03057-df98: approvers are told
# a gate opened and never that it closed.
LEDGER_NOTIFICATION_TYPES="$LEDGER_NOTIFICATION_TYPES
system_alert
feature_announcement
invitation_received
team_update
export_ready
workflow_complete
account_update
agent_goal_achieved
agent_improvement_applied
autonomy_approval_completed
autonomy_approval_rejected
"

# ── Detector ─────────────────────────────────────────────────────────────────
# Search every tree that could hold a producer. A symbol referenced ONLY at its
# own declaration site has no other end.
search_paths() {
  for p in server/app worker/app frontend/src \
           extensions/system/server/app extensions/system/worker/app \
           extensions/system/frontend/src \
           extensions/marketing/server/app extensions/supply-chain/server/app; do
    [ -d "$ROOT/$p" ] && printf '%s\n' "$ROOT/$p"
  done
}

in_ledger() { printf '%s\n' "$2" | grep -qxF "$1"; }

unconsumed_notification_types() {
  local decl="$ROOT/server/app/models/notification.rb"
  [ -f "$decl" ] || return 0
  local types
  types=$(sed -n '/^  TYPES = %w\[/,/^  \]/p' "$decl" \
          | grep -oE '^\s{4}[a-z][a-z0-9_]*' | tr -d ' ')
  local paths; paths=$(search_paths)
  [ -n "$paths" ] || return 0
  for t in $types; do
    # -F fixed-string, quoted form only: a bare word would match prose.
    local hits
    hits=$(grep -rF "\"$t\"" --include=*.rb --include=*.ts --include=*.tsx \
             $paths 2>/dev/null | grep -vF "app/models/notification.rb" | wc -l)
    if [ "$hits" -eq 0 ] && ! in_ledger "$t" "$LEDGER_NOTIFICATION_TYPES"; then
      printf 'Notification::TYPES %s\n' "$t"
    fi
  done
}

findings=$(unconsumed_notification_types)

if [ "$MODE" = "--list" ]; then
  [ -n "$findings" ] && printf '%s\n' "$findings"
  exit 0
fi
[ -z "$findings" ] && echo 0 || printf '%s\n' "$findings" | wc -l
exit 0
