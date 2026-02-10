# frozen_string_literal: true

module Ai
  class AgentTrustScore < ApplicationRecord
    self.table_name = "ai_agent_trust_scores"

    # ==========================================
    # Constants
    # ==========================================
    TIERS = %w[supervised monitored trusted autonomous].freeze
    TIER_THRESHOLDS = {
      "supervised" => 0.0,
      "monitored" => 0.4,
      "trusted" => 0.7,
      "autonomous" => 0.9
    }.freeze
    DIMENSIONS = %w[reliability cost_efficiency safety quality speed].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "agent_id"

    # ==========================================
    # Validations
    # ==========================================
    validates :agent_id, uniqueness: true
    validates :tier, inclusion: { in: TIERS }
    validates :reliability, :cost_efficiency, :safety, :quality, :speed, :overall_score,
              numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

    # ==========================================
    # Scopes
    # ==========================================
    scope :by_tier, ->(tier) { where(tier: tier) }
    scope :above_threshold, ->(score) { where("overall_score >= ?", score) }
    scope :recently_evaluated, -> { where("last_evaluated_at > ?", 24.hours.ago) }
    scope :needs_evaluation, -> { where("last_evaluated_at IS NULL OR last_evaluated_at < ?", 24.hours.ago) }

    # ==========================================
    # Methods
    # ==========================================

    # Recalculate overall score from dimensions
    def recalculate!
      weights = { reliability: 0.25, cost_efficiency: 0.15, safety: 0.30, quality: 0.20, speed: 0.10 }

      self.overall_score = weights.sum { |dim, weight| (send(dim) || 0.5) * weight }
      self.tier = calculate_tier
      self.last_evaluated_at = Time.current
      self.evaluation_count = (evaluation_count || 0) + 1

      # Append to evaluation history (keep last 50)
      history = (evaluation_history || []).last(49)
      history << {
        score: overall_score.round(4),
        tier: tier,
        dimensions: DIMENSIONS.each_with_object({}) { |d, h| h[d] = send(d)&.round(4) },
        evaluated_at: Time.current.iso8601
      }
      self.evaluation_history = history

      save!
    end

    # Check if agent can be promoted to the next tier
    def promotable?
      next_tier = TIERS[TIERS.index(tier) + 1]
      return false unless next_tier

      overall_score >= TIER_THRESHOLDS[next_tier]
    end

    # Check if agent should be demoted
    def demotable?
      return false if tier == "supervised"

      overall_score < TIER_THRESHOLDS[tier]
    end

    # Instantly demote to supervised (for critical violations)
    def emergency_demote!(reason: "critical_violation")
      update!(
        tier: "supervised",
        safety: [safety - 0.3, 0.0].max,
        evaluation_history: (evaluation_history || []) + [{
          type: "emergency_demotion",
          reason: reason,
          previous_tier: tier,
          evaluated_at: Time.current.iso8601
        }]
      )
      recalculate!
    end

    private

    def calculate_tier
      TIERS.reverse.find { |t| overall_score >= TIER_THRESHOLDS[t] } || "supervised"
    end
  end
end
