# frozen_string_literal: true

namespace :ai do
  desc "IMP-a091565577cc: backfill Ai::ImprovementRecommendation#status to 'applied' for " \
       "approved offers whose promoted dev-improve RalphTask already passed, from before the " \
       "dev_complete_task -> apply! wiring existed. Idempotent — only touches status: 'approved'."
  task backfill_applied_improvements: :environment do
    total = 0
    Account.find_each do |account|
      recs = account.ai_improvement_recommendations
                    .approved
                    .where(recommendation_type: Ai::ImprovementRecommendation::CODE_QUALITY_TYPES)
      recs.find_each do |rec|
        task = Ai::RalphTask.joins(:ralph_loop)
                             .where(ai_ralph_loops: { account_id: account.id })
                             .where(status: "passed")
                             .where("ai_ralph_tasks.metadata->>'recommendation_id' = ?", rec.id)
                             .order(created_at: :desc)
                             .first
        next unless task

        rec.apply!(rec.approved_by)
        total += 1
        puts "[ai:backfill_applied_improvements] account=#{account.id} recommendation=#{rec.id} task=#{task.task_key} -> applied"
      end
    end
    puts "[ai:backfill_applied_improvements] done, #{total} recommendation(s) backfilled to applied"
  end
end
