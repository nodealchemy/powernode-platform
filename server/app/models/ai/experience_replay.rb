# frozen_string_literal: true

module Ai
  class ExperienceReplay < ApplicationRecord
    self.table_name = "ai_experience_replays"

    has_neighbors :embedding

    # ==========================================
    # Constants
    # ==========================================
    STATUSES = %w[active archived expired].freeze

    # Selection ranking weights
    QUALITY_WEIGHT = 0.4
    EFFECTIVENESS_WEIGHT = 0.3
    RECENCY_WEIGHT = 0.3

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id"
    belongs_to :source_execution, class_name: "Ai::AgentExecution", foreign_key: "source_execution_id", optional: true
    belongs_to :source_trajectory, class_name: "Ai::Trajectory", foreign_key: "source_trajectory_id", optional: true

    # ==========================================
    # Validations
    # ==========================================
    validates :compressed_example, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :quality_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
    validates :effectiveness_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

    # ==========================================
    # Scopes
    # ==========================================
    scope :active, -> { where(status: "active") }
    scope :for_agent, ->(agent_id) { where(ai_agent_id: agent_id) }
    scope :for_account, ->(account_id) { where(account_id: account_id) }
    scope :by_quality, -> { order(quality_score: :desc) }
    scope :few_shot, -> { active.where("quality_score >= ?", 0.6) }
    scope :recent, -> { order(created_at: :desc) }
    scope :with_embedding, -> { where.not(embedding: nil) }

    # ==========================================
    # Class Methods
    # ==========================================
    def self.semantic_search(query_embedding, account_id:, agent_id: nil, threshold: 0.5, limit: 20)
      return [] if query_embedding.blank?

      scope = active.where(account_id: account_id)
      scope = scope.for_agent(agent_id) if agent_id
      scope
        .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
        .limit(limit)
        .to_a
        .select { |e| e.neighbor_distance <= 1.0 - threshold }
    end

    # ==========================================
    # Instance Methods
    # ==========================================
    def ranking_score
      recency_factor = [1.0 - ((Time.current - created_at) / 30.days).to_f, 0.0].max
      (quality_score * QUALITY_WEIGHT) +
        (effectiveness_score * EFFECTIVENESS_WEIGHT) +
        (recency_factor * RECENCY_WEIGHT)
    end

    def record_injection_outcome!(successful:)
      increment!(:injection_count)
      if successful
        increment!(:positive_outcome_count)
      else
        increment!(:negative_outcome_count)
      end
      update!(last_injected_at: Time.current)
      recalculate_effectiveness!
    end

    private

    def recalculate_effectiveness!
      return unless injection_count >= 3

      score = positive_outcome_count.to_f / injection_count
      update!(effectiveness_score: score.round(4))
    end
  end
end
