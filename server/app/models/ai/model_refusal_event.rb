# frozen_string_literal: true

module Ai
  # Append-only record of a Fable/Mythos safety-classifier refusal (HTTP 200,
  # stop_reason "refusal") and its recovery outcome. Written on every refusal by
  # WorkerLlmClient#record_refusal!; read by Ai::ModelRefusalPromotionService to
  # decide when to pre-route an (agent_type, category) combo away from Fable.
  #
  # Unlike Ai::AgentModelPerformance (a rolling counter row per tuple), this is a
  # one-row-per-refusal EVENT log — promotion counts rows in a window.
  class ModelRefusalEvent < ApplicationRecord
    self.table_name = "ai_model_refusal_events"

    belongs_to :account
    belongs_to :provider, class_name: "Ai::Provider", foreign_key: "ai_provider_id"

    PHASES = %w[pre_output mid_stream].freeze

    validates :model,      presence: true, length: { maximum: 120 }
    validates :agent_type, presence: true, length: { maximum: 50 }
    validates :phase,      presence: true

    # Best-effort append. Returns the created record, or nil when the required
    # attribution (account/provider/model/agent_type) is missing or the insert
    # fails — a learning-log write must never break the LLM call.
    def self.record!(account_id:, provider_id:, model:, agent_type:, phase:,
                     category: nil, task_type: nil, tool_surface: nil,
                     reframed: false, fell_back: false, served_by_model: nil,
                     explanation: nil, agent_execution_id: nil)
      return nil if account_id.blank? || provider_id.blank? || model.blank? || agent_type.blank?

      create!(
        account_id: account_id,
        ai_provider_id: provider_id,
        model: model.to_s.truncate(120, omission: ""),
        agent_type: agent_type.to_s.truncate(50, omission: ""),
        phase: phase.to_s.presence || "pre_output",
        category: category.presence,
        task_type: task_type.presence,
        tool_surface: tool_surface.presence,
        reframed: !!reframed,
        fell_back: !!fell_back,
        served_by_model: served_by_model.presence,
        explanation: explanation.presence,
        agent_execution_id: agent_execution_id.presence
      )
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      Rails.logger.warn("[ModelRefusalEvent] record failed: #{e.message}")
      nil
    end
  end
end
