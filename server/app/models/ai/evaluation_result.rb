# frozen_string_literal: true

module Ai
  class EvaluationResult < ApplicationRecord
    belongs_to :account
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "agent_id"
    # LearningController#evaluation_results joins(:execution); the column and FK
    # existed but the association was never declared, so the join raised
    # ActiveRecord::ConfigurationError (500). optional: true — execution_id
    # presence is already validated below; we only need the reflection for the
    # join, not a new write-time existence check.
    belongs_to :execution, class_name: "Ai::AgentExecution", foreign_key: "execution_id", optional: true

    validates :execution_id, presence: true
    validates :evaluator_model, presence: true
    validates :scores, presence: true

    scope :for_agent, ->(agent_id) { where(agent_id: agent_id) }
    scope :recent, ->(limit = 50) { order(created_at: :desc).limit(limit) }
    scope :in_time_range, ->(from, to = Time.current) { where(created_at: from..to) }

    def correctness_score
      scores&.dig("correctness")
    end

    def completeness_score
      scores&.dig("completeness")
    end

    def helpfulness_score
      scores&.dig("helpfulness")
    end

    def safety_score
      scores&.dig("safety")
    end

    def average_score
      values = [correctness_score, completeness_score, helpfulness_score, safety_score].compact
      return nil if values.empty?

      (values.sum.to_f / values.size).round(2)
    end
  end
end
