# frozen_string_literal: true

# IMP-3e36e30d5c72, redo of 20260928000000 after IMP-3e36e30d5c72's own duration_ms
# widening (20260928010000 widens ai_ralph_loops.duration_ms to bigint). The original
# migration is now a documented no-op (see that file) — it is stamped as applied on
# prod (ops-hub, 2026-09-28 ~05:20 UTC, applied via schema_migrations INSERT, NOT by
# actually running its body) precisely because running it crash-looped Rails: a
# multi-week-old loop's `(now - started_at) * 1000` overflowed the (then int4)
# duration_ms column. The backfill itself never happened on prod — the 7 stale
# loops identified there are still "running". This migration is IDENTICAL to
# 20260928000000's `up` in every particular — same rule, same logging, same
# table-only model pattern, same reasoning (see that file's header comment for the
# full rationale, not repeated here) — under a LATER version, running against a
# column that is now wide enough to hold the value.
#
# Table-only models are declared again, independently, rather than reused from the
# other migration file — a migration must not depend on another migration file's
# classes (each migration must run correctly standing alone, at any point in the
# future, independent of whether adjacent migration files still exist in the tree
# in any particular form).
class CloseStaleCompletedCampaignLoopsRedo < ActiveRecord::Migration[8.1]
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

    say "IMP-3e36e30d5c72 (redo): found #{stale_loops.count} running loop(s) under a completed campaign"

    stale_loops.find_each do |loop_row|
      tasks = RalphTaskRow.where(ralph_loop_id: loop_row.id)
      task_statuses = tasks.pluck(:status)
      clean = task_statuses.all? { |s| CLEAN_STATUSES.include?(s) }
      has_repeating = tasks.where(repeating: true).exists?

      # A non-Hash jsonb value (scalar/array) must not raise inside a boot-time migration.
      configuration = loop_row.configuration.is_a?(Hash) ? loop_row.configuration : {}
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

      say "IMP-3e36e30d5c72 (redo): loop #{loop_row.id} (#{loop_row.name.inspect}, campaign " \
          "#{loop_row.campaign_id}) -> #{new_status} " \
          "(tasks: #{task_statuses.tally}#{' — has a repeating task' if has_repeating})"

      now = Time.current
      attrs = { status: new_status, completed_at: now, updated_at: now, configuration: configuration,
                total_tasks: task_statuses.size,
                completed_tasks: task_statuses.count { |s| s == "passed" },
                failed_tasks: task_statuses.count { |s| s == "failed" } }
      # Matches RalphLoop#calculate_duration exactly (before_save, only when started_at
      # is present). duration_ms is bigint as of 20260928010000, so a multi-week (or
      # multi-year) started_at no longer overflows here.
      attrs[:duration_ms] = ((now - loop_row.started_at) * 1000).to_i if loop_row.started_at.present?

      loop_row.update_columns(attrs)
    end
  end

  # Same irreversibility as 20260928000000 — which pre-existing "running" rows this
  # touched, and what each one's tasks looked like at backfill time, cannot be
  # reconstructed afterward.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
