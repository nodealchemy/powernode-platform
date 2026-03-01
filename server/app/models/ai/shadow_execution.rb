# frozen_string_literal: true

module Ai
  class ShadowExecution < ApplicationRecord
    self.table_name = "ai_shadow_executions"

    belongs_to :account
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "agent_id"

    validates :action_type, presence: true
    validates :agreement_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

    scope :for_agent, ->(agent_id) { where(agent_id: agent_id) }
    scope :agreed, -> { where(agreed: true) }
    scope :disagreed, -> { where(agreed: false) }
    scope :recent, -> { order(created_at: :desc) }

    attribute :shadow_input, :json, default: -> { {} }
    attribute :shadow_output, :json, default: -> { {} }
    attribute :reference_output, :json, default: -> { {} }
  end
end
