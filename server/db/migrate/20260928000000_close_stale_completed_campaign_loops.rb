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
class CloseStaleCompletedCampaignLoops < ActiveRecord::Migration[8.1]
  # Table-only models: no Ai::RalphLoop/Ai::Campaign/Ai::RalphTask callbacks,
  # validations, or state-machine concerns run.
  class CampaignRow < ActiveRecord::Base
    self.table_name = "ai_campaigns"
  end

  class RalphLoopRow < ActiveRecord::Base
    self.table_name = "ai_ralph_loops"
  end

  class RalphTaskRow < ActiveRecord::Base
    self.table_name = "ai_ralph_tasks"
  end

  CLEAN_STATUSES = %w[passed skipped].freeze

  def up
    CampaignRow.reset_column_information
    RalphLoopRow.reset_column_information
    RalphTaskRow.reset_column_information

    completed_campaign_ids = CampaignRow.where(status: "completed").select(:id)
    stale_loops = RalphLoopRow.where(status: "running", campaign_id: completed_campaign_ids)

    say "IMP-3e36e30d5c72: found #{stale_loops.count} running loop(s) under a completed campaign"

    stale_loops.find_each do |loop_row|
      tasks = RalphTaskRow.where(ralph_loop_id: loop_row.id)
      task_statuses = tasks.pluck(:status)
      clean = task_statuses.all? { |s| CLEAN_STATUSES.include?(s) }
      has_repeating = tasks.where(repeating: true).exists?

      configuration = loop_row.configuration || {}
      if clean && !has_repeating
        new_status = "completed"
        configuration = configuration.merge("final_result" => { "reason" => "backfill_imp_3e36e30d5c72" })
      elsif clean && has_repeating
        new_status = "cancelled"
        configuration = configuration.merge(
          "cancellation_reason" =>
            "campaign stopped: backfill (IMP-3e36e30d5c72 — campaign completed while this loop was still " \
            "running, and it could not be completed because it has a repeating task)"
        )
      else
        new_status = "cancelled"
        configuration = configuration.merge(
          "cancellation_reason" =>
            "campaign stopped: backfill (IMP-3e36e30d5c72 — campaign completed while this loop was still " \
            "running)"
        )
      end

      say "IMP-3e36e30d5c72: loop #{loop_row.id} (#{loop_row.name.inspect}, campaign #{loop_row.campaign_id}) " \
          "-> #{new_status} (tasks: #{task_statuses.tally}#{' — has a repeating task' if has_repeating})"

      now = Time.current
      attrs = { status: new_status, completed_at: now, updated_at: now, configuration: configuration,
                total_tasks: task_statuses.size,
                completed_tasks: task_statuses.count { |s| s == "passed" },
                failed_tasks: task_statuses.count { |s| s == "failed" } }
      # Matches RalphLoop#calculate_duration exactly (before_save, only when started_at
      # is present) — a `running` row should always have one (set by #start!), but this
      # guards a legacy/manually-inserted row the same way the real callback would.
      attrs[:duration_ms] = ((now - loop_row.started_at) * 1000).to_i if loop_row.started_at.present?

      loop_row.update_columns(attrs)
    end
  end

  # Which pre-existing "running" rows this touched, and what each one's tasks looked
  # like at backfill time, cannot be reconstructed afterward — same irreversibility
  # shape as 20260919140000_backfill_mcp_server_allow_network.rb.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
