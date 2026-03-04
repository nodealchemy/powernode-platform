# frozen_string_literal: true

module Ai
  class SelfChallenge < ApplicationRecord
    self.table_name = "ai_self_challenges"

    STATUSES = %w[pending generating executing validating completed failed abandoned].freeze
    DIFFICULTIES = %w[easy medium hard expert].freeze

    belongs_to :account
    belongs_to :challenger_agent, class_name: "Ai::Agent", foreign_key: "challenger_agent_id"
    belongs_to :executor_agent, class_name: "Ai::Agent", foreign_key: "executor_agent_id", optional: true
    belongs_to :validator_agent, class_name: "Ai::Agent", foreign_key: "validator_agent_id", optional: true
    belongs_to :skill, class_name: "Ai::Skill", foreign_key: "ai_skill_id", optional: true

    validates :challenge_id, presence: true, uniqueness: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :difficulty, presence: true, inclusion: { in: DIFFICULTIES }

    attribute :expected_criteria, :json, default: -> { {} }
    attribute :validation_result, :json, default: -> { {} }

    before_validation :generate_challenge_id, on: :create

    scope :active, -> { where(status: %w[pending generating executing validating]) }
    scope :completed, -> { where(status: "completed") }
    scope :for_agent, ->(agent_id) { where(challenger_agent_id: agent_id) }
    scope :for_skill, ->(skill_id) { where(ai_skill_id: skill_id) }
    scope :recent, -> { order(created_at: :desc) }

    def passed?
      status == "completed" && quality_score.to_f >= 0.7
    end

    private

    def generate_challenge_id
      self.challenge_id ||= "challenge_#{SecureRandom.hex(8)}"
    end
  end
end
