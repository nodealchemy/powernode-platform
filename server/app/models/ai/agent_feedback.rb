# frozen_string_literal: true

module Ai
  class AgentFeedback < ApplicationRecord
    self.table_name = "ai_agent_feedbacks"

    FEEDBACK_TYPES = %w[execution_quality proposal_quality communication_quality].freeze
    TRUST_THRESHOLD = 20 # Number of feedbacks before applying to trust

    # Associations
    belongs_to :account
    belongs_to :user
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id"

    # Validations
    validates :feedback_type, presence: true, inclusion: { in: FEEDBACK_TYPES }
    validates :rating, presence: true, inclusion: { in: 1..5 }

    # Scopes
    scope :unapplied, -> { where(applied_to_trust: false) }
    scope :for_agent, ->(agent_id) { where(ai_agent_id: agent_id) }
    scope :recent, -> { order(created_at: :desc) }

    # Polymorphic context (execution, proposal, escalation)
    def context
      return nil unless context_type.present? && context_id.present?

      context_type.constantize.find_by(id: context_id)
    rescue NameError
      nil
    end
  end
end
