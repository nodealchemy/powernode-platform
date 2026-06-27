# frozen_string_literal: true

module Ai
  # A point-in-time snapshot of a Campaign's progress (task counts + completion %, per-loop
  # breakdown, improvement metrics) for the dashboard ledger and trend.
  class ProgressEntry < ApplicationRecord
    belongs_to :campaign, class_name: "Ai::Campaign", foreign_key: "campaign_id"

    validates :recorded_at, presence: true

    scope :chronological, -> { order(recorded_at: :asc) }
    scope :latest_first, -> { order(recorded_at: :desc) }

    def summary
      {
        recorded_at: recorded_at, total_tasks: total_tasks, completed_tasks: completed_tasks,
        failed_tasks: failed_tasks, blocked_tasks: blocked_tasks, completion_pct: completion_pct,
        per_loop_summary: per_loop_summary, improvement_metrics: improvement_metrics
      }
    end
  end
end
