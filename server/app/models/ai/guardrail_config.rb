# frozen_string_literal: true

module Ai
  class GuardrailConfig < ApplicationRecord
    self.table_name = "ai_guardrail_configs"

    belongs_to :account
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id", optional: true

    validates :name, presence: true, uniqueness: { scope: :account_id }
    validates :toxicity_threshold, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true
    validates :pii_sensitivity, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true
    validates :max_input_tokens, numericality: { greater_than: 0 }, allow_nil: true
    validates :max_output_tokens, numericality: { greater_than: 0 }, allow_nil: true

    scope :active, -> { where(is_active: true) }
    scope :for_agent, ->(agent_id) { where(ai_agent_id: agent_id) }
    scope :global, -> { where(ai_agent_id: nil) }

    def record_check!(blocked:)
      increment!(:total_checks)
      increment!(:total_blocks) if blocked
    end

    def block_rate
      return 0 if total_checks.zero?

      (total_blocks.to_f / total_checks * 100).round(1)
    end

    def effective_config
      {
        input_rails: input_rails,
        output_rails: output_rails,
        retrieval_rails: retrieval_rails,
        max_input_tokens: max_input_tokens,
        max_output_tokens: max_output_tokens,
        toxicity_threshold: toxicity_threshold,
        pii_sensitivity: pii_sensitivity,
        block_on_failure: block_on_failure
      }.merge(configuration.symbolize_keys)
    end
  end
end
