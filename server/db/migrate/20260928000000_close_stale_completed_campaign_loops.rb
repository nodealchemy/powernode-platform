# frozen_string_literal: true

# IMP-3e36e30d5c72. Ai::DevLoop::CampaignDriver#stop never transitioned the
# LOOP — only the campaign — so every campaign that was ever stopped left its
# ralph_loops stuck at status="running" forever (the iteration-drain path is
# the only OTHER caller of RalphLoop#complete!, and the API only ever exposed
# #cancel). That code path is fixed separately; this is the one-time backfill
# for the loops it already stranded: any loop still "running" whose OWNING
# CAMPAIGN already reads "completed" is exactly the pre-fix symptom.
#
# RULE (same as CampaignDriver#close_loop_for_campaign_stop!, reimplemented
# independently — see below for why): every task passed or skipped means the
# loop's work genuinely finished, so it becomes "completed"; anything else
# (pending/in_progress/blocked/failed left over) means real work was cut
# short, so it becomes "cancelled" — its tasks are left exactly as they are,
# visible and untouched, this migration never writes ai_ralph_tasks.
#
# NOT SHARED CODE WITH CampaignDriver, DELIBERATELY. A migration's model
# classes are table-only (see AgentRow in
# 20260927120000_exclude_pipeline_workers_from_claude_export.rb for the
# established pattern) precisely so a migration that already ran keeps
# working even after the app model it once resembled is refactored or
# deleted — calling Ai::RalphLoop#complete!/#cancel!, or even a shared
# decision-only helper defined in app code, would make this frozen migration
# load-bearing on code that is free to change out from under it. So the rule
# is duplicated at the raw-column-write level, kept in sync by wording (each
# side's comment names the other) and by each side's own spec — not by
# sharing a method.
#
# complete!'s OWN repeating-task guard (state_machine.rb: `ralph_tasks.where(repeating:
# true).exists?`) does not raise — it logs a warning and returns early, leaving the row
# exactly as non-terminal as before the call. A naive port of "call complete!" here would
# reproduce the very bug this migration exists to fix for that one case. The operator's
# direction is that EVERY running loop this migration touches ends terminal — a clean
# loop with a repeating task is CANCELLED instead, with a reason that names the repeating
# task, and logged; there is no third "left running" outcome.
#
# DELIBERATELY SKIPPED, to stay a narrow, mechanical data fix rather than a live state
# transition: extract_compound_learnings (RalphLoop#complete!'s embedding-generating side
# effect) — appropriate for a live loop finishing in real time, not for a bulk backfill of
# already-stale historical rows during a deploy.
#
# WHY update_columns HERE STILL MATCHES A REAL update! (unlike the naive minimal-columns
# version this migration shipped with initially): update! would fire RalphLoop's own
# after_save callbacks — update_task_counts (total_tasks/completed_tasks/failed_tasks,
# recomputed from ralph_tasks on any status change) and, via a before_save, calculate_duration
# (duration_ms, only when started_at is present) — and those columns would otherwise go
# stale on every row this backfill touches, forever, since nothing else recomputes them.
# This migration computes the SAME values with the SAME formulas (read out of ralph_loop.rb,
# not guessed) and writes them in the same update_columns call, rather than pull in the
# app model to get them from its callbacks.
#
# SUPERSEDED — NOW A NO-OP. IMP-3e36e30d5c72 (incident, 2026-09-28 ~05:07-05:21 UTC): the
# `up` body above (kept, unrun, for the record) writes
# `(now - loop_row.started_at) * 1000).to_i` into ai_ralph_loops.duration_ms. On prod, every
# stale loop this migration selects is weeks old, so that write is ~2.24e9 — out of range
# for the (then int4) duration_ms column: `ActiveModel::RangeError: ... is out of range for
# ActiveModel::Type::Integer with limit 4 bytes`. rails-start runs pending migrations on
# every boot, so this crash-looped ops-hub Rails for ~14 minutes until this version was
# stamped into schema_migrations directly (NOT by actually running this body) to restore
# service. Because it is stamped as applied on prod, this file must stay in the tree
# (deleting it would desync a prod DB that already has this version recorded) and its
# version must never be reused — but its body must NEVER run again, on prod (already
# stamped, so `up` won't be invoked there) OR on a fresh database (where it WOULD be
# invoked, and would hit the exact same overflow, since duration_ms is still int4 at this
# migration's own version — the widening happens later, in 20260928010000).
#
# The backfill this migration was meant to perform still needs to happen — it does, redone
# byte-for-byte identically, in 20260928020000_close_stale_completed_campaign_loops_redo.rb,
# under a version that runs AFTER duration_ms has been widened to bigint. This migration's
# `up` is replaced with nothing at all: no table-only models, no query, no writes.
class CloseStaleCompletedCampaignLoops < ActiveRecord::Migration[8.1]
  def up
    say "IMP-3e36e30d5c72: no-op (superseded by 20260928020000 after the duration_ms " \
        "bigint widening in 20260928010000 — see this file's header comment)."
  end

  def down
    # No-op forward, no-op back.
  end
end
