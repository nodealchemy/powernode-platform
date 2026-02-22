# frozen_string_literal: true

module Ai
  class CompoundLearning < ApplicationRecord
    self.table_name = "ai_compound_learnings"

    has_neighbors :embedding

    # ==========================================
    # Constants
    # ==========================================
    CATEGORIES = %w[pattern anti_pattern best_practice discovery fact failure_mode review_finding performance_insight].freeze
    SCOPES = %w[team global].freeze
    STATUSES = %w[active deprecated superseded verified disproven].freeze
    EXTRACTION_METHODS = %w[marker auto_success auto_failure review evaluation].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account
    belongs_to :ai_agent_team, class_name: "Ai::AgentTeam", foreign_key: "ai_agent_team_id", optional: true
    belongs_to :source_agent, class_name: "Ai::Agent", foreign_key: "source_agent_id", optional: true
    belongs_to :source_execution, class_name: "Ai::TeamExecution", foreign_key: "source_execution_id", optional: true
    belongs_to :superseded_by, class_name: "Ai::CompoundLearning", foreign_key: "superseded_by_id", optional: true
    belongs_to :verified_by, class_name: "User", foreign_key: "verified_by_id", optional: true
    belongs_to :disproven_by, class_name: "User", foreign_key: "disproven_by_id", optional: true

    has_many :superseding, class_name: "Ai::CompoundLearning", foreign_key: :superseded_by_id

    # ==========================================
    # Validations
    # ==========================================
    validates :category, presence: true, inclusion: { in: CATEGORIES }
    validates :scope, inclusion: { in: SCOPES }
    validates :status, inclusion: { in: STATUSES }
    validates :content, presence: true
    validates :importance_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
    validates :confidence_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

    # ==========================================
    # Scopes
    # ==========================================
    scope :active, -> { where(status: "active") }
    scope :for_team, ->(team_id) { where(ai_agent_team_id: team_id) }
    scope :for_account, ->(account_id) { where(account_id: account_id) }
    scope :global_scope, -> { where(scope: "global") }
    scope :team_scope, -> { where(scope: "team") }
    scope :by_category, ->(cat) { where(category: cat) }
    scope :high_importance, -> { where("importance_score >= ?", 0.7) }
    scope :verified, -> { where(status: "verified") }
    scope :disproven, -> { where(status: "disproven") }
    scope :with_tag, ->(tag) { where("tags @> ?", [tag].to_json) }
    scope :with_embedding, -> { where.not(embedding: nil) }
    scope :recent, -> { order(created_at: :desc) }
    scope :by_effectiveness, -> { order(effectiveness_score: :desc) }

    # ==========================================
    # Class Methods
    # ==========================================

    # Semantic search using neighbor gem's nearest_neighbors scope (cosine distance)
    def self.semantic_search(query_embedding, account_id:, threshold: 0.6, limit: 20)
      return [] if query_embedding.blank?

      where(account_id: account_id, status: %w[active verified])
        .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
        .limit(limit)
        .to_a
        .select { |e| e.neighbor_distance <= 1.0 - threshold }
    end

    # Find near-duplicates by embedding similarity
    def self.find_similar(embedding, account_id:, threshold: 0.92, limit: 5)
      return [] if embedding.blank?

      active.where(account_id: account_id)
        .nearest_neighbors(:embedding, embedding, distance: "cosine")
        .limit(limit)
        .to_a
        .select { |e| e.neighbor_distance <= 1.0 - threshold }
    end

    # ==========================================
    # Instance Methods
    # ==========================================

    # Blended importance that incorporates effectiveness feedback
    def effective_importance
      return importance_score if injection_count < 5

      smoothed = (positive_outcome_count + 2).to_f / (injection_count + 4)
      (importance_score * 0.3 + smoothed * 0.7).round(4)
    end

    def boost_importance!(amount = 0.05)
      new_score = [importance_score + amount, 1.0].min
      update!(importance_score: new_score)
    end

    def decay_importance!
      return if decay_rate.zero?

      days_since = ((Time.current - updated_at) / 1.day).to_i
      return if days_since < 1

      decayed = importance_score * ((1 - decay_rate) ** days_since)
      update!(importance_score: [decayed, 0.05].max)
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

    def record_access!
      increment!(:access_count)
    end

    def verify!(user:)
      update!(
        status: "verified",
        verified_at: Time.current,
        verified_by_id: user.id
      )
      boost_importance!(0.15)
      update!(confidence_score: [confidence_score + 0.1, 1.0].min)
    end

    def disprove!(user:, reason:)
      update!(
        status: "disproven",
        disproven_at: Time.current,
        disproven_by_id: user.id,
        contradiction_note: reason,
        importance_score: 0.05,
        confidence_score: 0.1
      )
    end

    def resolve_contradiction!(note:)
      update!(
        contradiction_resolved_at: Time.current,
        contradiction_note: note
      )
    end

    def supersede!(new_learning)
      update!(status: "superseded", superseded_by: new_learning)
    end

    def deprecate!
      update!(status: "deprecated")
    end

    def learning_summary
      {
        id: id,
        category: category,
        title: title,
        content: content,
        importance_score: importance_score,
        confidence_score: confidence_score,
        effectiveness_score: effectiveness_score,
        effective_importance: effective_importance,
        injection_count: injection_count,
        positive_outcome_count: positive_outcome_count,
        negative_outcome_count: negative_outcome_count,
        access_count: access_count,
        status: status,
        scope: scope,
        tags: tags,
        extraction_method: extraction_method,
        source_execution_successful: source_execution_successful,
        ai_agent_team_id: ai_agent_team_id,
        source_agent_id: source_agent_id,
        verified_at: verified_at&.iso8601,
        disproven_at: disproven_at&.iso8601,
        contradiction_note: contradiction_note,
        promoted_at: promoted_at&.iso8601,
        last_injected_at: last_injected_at&.iso8601,
        created_at: created_at&.iso8601,
        updated_at: updated_at&.iso8601
      }
    end

    private

    def recalculate_effectiveness!
      return unless injection_count >= 3

      score = positive_outcome_count.to_f / injection_count
      update!(effectiveness_score: score.round(4))
    end
  end
end
