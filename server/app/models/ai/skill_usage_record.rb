# frozen_string_literal: true

module Ai
  class SkillUsageRecord < ApplicationRecord
    self.table_name = "ai_skill_usage_records"

    # ==========================================
    # Constants
    # ==========================================
    OUTCOMES = %w[success failure partial].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account
    belongs_to :ai_skill, class_name: "Ai::Skill", foreign_key: "ai_skill_id"
    belongs_to :ai_agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id", optional: true

    # ==========================================
    # Validations
    # ==========================================
    validates :outcome, presence: true, inclusion: { in: OUTCOMES }

    # ==========================================
    # Scopes
    # ==========================================
    scope :successful, -> { where(outcome: "success") }
    scope :failed, -> { where(outcome: "failure") }
    scope :for_skill, ->(skill_id) { where(ai_skill_id: skill_id) }
    scope :for_agent, ->(agent_id) { where(ai_agent_id: agent_id) }
    scope :recent, ->(limit = 50) { order(created_at: :desc).limit(limit) }
  end
end
