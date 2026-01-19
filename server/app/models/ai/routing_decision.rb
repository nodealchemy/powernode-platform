# frozen_string_literal: true

module Ai
  class RoutingDecision < ApplicationRecord
    include Auditable

    # ==========================================================================
    # CONSTANTS
    # ==========================================================================

    STRATEGIES = %w[round_robin weighted cost_optimized latency_optimized quality_optimized hybrid ml_based fallback].freeze
    OUTCOMES = %w[succeeded failed timeout fallback rate_limited error].freeze

    # ==========================================================================
    # ASSOCIATIONS
    # ==========================================================================

    belongs_to :account
    belongs_to :routing_rule, class_name: "Ai::ModelRoutingRule", optional: true
    belongs_to :selected_provider, class_name: "Ai::Provider", optional: true
    belongs_to :workflow_run, class_name: "Ai::WorkflowRun", optional: true
    belongs_to :agent_execution, class_name: "Ai::AgentExecution", optional: true

    # ==========================================================================
    # VALIDATIONS
    # ==========================================================================

    validates :request_type, presence: true
    validates :strategy_used, presence: true, inclusion: { in: STRATEGIES }
    validates :outcome, inclusion: { in: OUTCOMES }, allow_nil: true
    validate :validate_request_metadata
    validate :validate_candidates_evaluated

    # ==========================================================================
    # SCOPES
    # ==========================================================================

    scope :successful, -> { where(outcome: "succeeded") }
    scope :failed, -> { where(outcome: %w[failed timeout error]) }
    scope :with_savings, -> { where("savings_usd > 0") }
    scope :recent, ->(period = 24.hours) { where("created_at >= ?", period.ago) }
    scope :for_account, ->(account) { where(account: account) }
    scope :for_provider, ->(provider) { where(selected_provider: provider) }
    scope :by_strategy, ->(strategy) { where(strategy_used: strategy) }

    # ==========================================================================
    # CALLBACKS
    # ==========================================================================

    before_validation :set_defaults
    after_create :update_routing_rule_stats

    # ==========================================================================
    # INSTANCE METHODS
    # ==========================================================================

    # Record the outcome of this routing decision
    def record_outcome!(outcome:, cost_usd: nil, latency_ms: nil, tokens_used: nil, quality_score: nil)
      attrs = { outcome: outcome }
      attrs[:actual_cost_usd] = cost_usd if cost_usd.present?
      attrs[:actual_latency_ms] = latency_ms if latency_ms.present?
      attrs[:actual_tokens_used] = tokens_used if tokens_used.present?
      attrs[:quality_score] = quality_score if quality_score.present?

      # Calculate savings if we have cost data
      if cost_usd.present? && alternative_cost_usd.present?
        attrs[:savings_usd] = alternative_cost_usd - cost_usd
      end

      update!(attrs)

      # Update routing rule stats
      routing_rule&.record_match!(succeeded: outcome == "succeeded")
    end

    # Check if decision was cost-effective
    def cost_effective?
      return nil unless savings_usd.present?

      savings_usd > 0
    end

    # Get decision summary
    def summary
      {
        id: id,
        request_type: request_type,
        strategy: strategy_used,
        provider: selected_provider&.name,
        outcome: outcome,
        cost: {
          estimated: estimated_cost_usd,
          actual: actual_cost_usd,
          savings: savings_usd
        },
        performance: {
          latency_ms: actual_latency_ms,
          tokens_used: actual_tokens_used,
          quality_score: quality_score
        },
        created_at: created_at
      }
    end

    # Get candidates that were evaluated
    def evaluated_candidates
      return [] unless candidates_evaluated.is_a?(Array)

      candidates_evaluated.map do |candidate|
        {
          provider_id: candidate["provider_id"],
          provider_name: candidate["provider_name"],
          score: candidate["score"],
          cost_estimate: candidate["cost_estimate"],
          latency_estimate: candidate["latency_estimate"],
          selected: candidate["selected"] == true
        }
      end
    end

    # Class method: Calculate aggregate stats for a period
    def self.stats_for_period(account:, period: 24.hours)
      decisions = for_account(account).recent(period)

      total = decisions.count
      successful = decisions.successful.count
      total_savings = decisions.with_savings.sum(:savings_usd)

      strategies = decisions.group(:strategy_used).count
      outcomes = decisions.group(:outcome).count

      {
        total_decisions: total,
        successful_decisions: successful,
        success_rate: total > 0 ? (successful.to_f / total * 100).round(2) : 0,
        total_savings_usd: total_savings.to_f.round(4),
        avg_savings_per_decision: total > 0 ? (total_savings.to_f / total).round(6) : 0,
        strategies: strategies,
        outcomes: outcomes,
        avg_latency_ms: decisions.where.not(actual_latency_ms: nil).average(:actual_latency_ms)&.to_f&.round(2),
        avg_cost_usd: decisions.where.not(actual_cost_usd: nil).average(:actual_cost_usd)&.to_f&.round(6)
      }
    end

    private

    def set_defaults
      self.request_metadata ||= {}
      self.candidates_evaluated ||= []
      self.scoring_breakdown ||= {}
    end

    def validate_request_metadata
      return if request_metadata.blank?

      unless request_metadata.is_a?(Hash)
        errors.add(:request_metadata, "must be a hash")
      end
    end

    def validate_candidates_evaluated
      return if candidates_evaluated.blank?

      unless candidates_evaluated.is_a?(Array)
        errors.add(:candidates_evaluated, "must be an array")
      end
    end

    def update_routing_rule_stats
      # Stats are updated when outcome is recorded
    end
  end
end
