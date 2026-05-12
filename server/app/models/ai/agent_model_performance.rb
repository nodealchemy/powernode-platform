# frozen_string_literal: true

module Ai
  # Rolling per-(account, provider, model, agent_type) counters used by
  # Ai::AgentModelSelector to bias future model selection toward models
  # that have historically completed agent runs successfully.
  #
  # Written by Ai::AgentExecution#after_update when an execution
  # transitions to completed or failed.
  class AgentModelPerformance < ApplicationRecord
    self.table_name = "ai_agent_model_performances"

    belongs_to :account
    belongs_to :provider, class_name: "Ai::Provider", foreign_key: "ai_provider_id"

    validates :model,      presence: true, length: { maximum: 120 }
    validates :agent_type, presence: true, length: { maximum: 50 }

    MIN_SAMPLE_FOR_SIGNAL = 5

    def success_rate
      return nil if total_runs < MIN_SAMPLE_FOR_SIGNAL

      successful_runs.to_f / total_runs
    end

    def avg_cost_usd
      return 0.0 if total_runs.zero?

      total_cost_usd.to_f / total_runs
    end

    def avg_duration_ms
      return 0 if total_runs.zero?

      total_duration_ms / total_runs
    end

    # Idempotent counter accumulation. Two concerns:
    #   1. Two workers completing executions concurrently for the same
    #      (account, provider, model, agent_type) tuple must not lose
    #      counter increments. Plain `rec.total_runs += 1; rec.save!`
    #      would race because the read+increment isn't atomic.
    #   2. The first run for a tuple is an insert; a sibling worker can
    #      win the insert and ours fails with RecordNotUnique.
    #
    # Solution: first ensure the row exists (with an insert-and-retry on
    # RecordNotUnique), then use UPDATE ... SET total_runs = total_runs + 1
    # via #update_counters which compiles to a single atomic SQL statement.
    def self.record!(account_id:, provider_id:, model:, agent_type:, success:, cost_usd: 0, duration_ms: 0, tokens: 0)
      return if account_id.blank? || provider_id.blank? || model.blank? || agent_type.blank?

      model_str      = model.to_s.truncate(120, omission: "")
      agent_type_str = agent_type.to_s.truncate(50, omission: "")
      lookup = { account_id: account_id, ai_provider_id: provider_id, model: model_str, agent_type: agent_type_str }

      rec = find_by(lookup) || begin
        create!(lookup)
      rescue ActiveRecord::RecordNotUnique
        find_by(lookup)
      end
      return nil unless rec

      # Atomic counter increment — translates to `UPDATE ... SET col = col + ?`
      # in a single SQL statement, safe under concurrent writers.
      update_counters(rec.id,
                      total_runs:        1,
                      successful_runs:   success ? 1 : 0,
                      failed_runs:       success ? 0 : 1,
                      total_cost_usd:    cost_usd.to_f,
                      total_duration_ms: duration_ms.to_i,
                      total_tokens:      tokens.to_i)
      where(id: rec.id).update_all(last_run_at: Time.current)

      rec.reload
    end
  end
end
