# frozen_string_literal: true

module Ai
  class TaskComplexityAssessment < ApplicationRecord
    self.table_name = "ai_task_complexity_assessments"

    # ==========================================================================
    # CONSTANTS
    # ==========================================================================

    COMPLEXITY_LEVELS = %w[trivial simple moderate complex expert].freeze
    RECOMMENDED_TIERS = %w[economy standard premium].freeze

    # ==========================================================================
    # ASSOCIATIONS
    # ==========================================================================

    belongs_to :account
    belongs_to :routing_decision, class_name: "Ai::RoutingDecision", foreign_key: "routing_decision_id", optional: true

    # ==========================================================================
    # VALIDATIONS
    # ==========================================================================

    validates :task_type, presence: true
    validates :complexity_score, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
    validates :complexity_level, presence: true, inclusion: { in: COMPLEXITY_LEVELS }
    validates :recommended_tier, presence: true, inclusion: { in: RECOMMENDED_TIERS }
    validates :classifier_version, presence: true

    # ==========================================================================
    # SCOPES
    # ==========================================================================

    scope :for_account, ->(account) { where(account: account) }
    scope :for_task_type, ->(type) { where(task_type: type) }
    scope :for_level, ->(level) { where(complexity_level: level) }
    scope :for_tier, ->(tier) { where(recommended_tier: tier) }
    scope :recent, ->(period = 24.hours) { where("created_at >= ?", period.ago) }
    scope :with_routing, -> { where.not(routing_decision_id: nil) }

    # ==========================================================================
    # CALLBACKS
    # ==========================================================================

    before_validation :set_defaults

    # ==========================================================================
    # INSTANCE METHODS
    # ==========================================================================

    def summary
      {
        id: id,
        task_type: task_type,
        complexity: {
          score: complexity_score.to_f,
          level: complexity_level,
          signals: complexity_signals
        },
        routing: {
          recommended_tier: recommended_tier,
          actual_tier_used: actual_tier_used
        },
        tokens: {
          input_count: input_token_count,
          tool_count: tool_count,
          conversation_depth: conversation_depth
        },
        classifier_version: classifier_version,
        created_at: created_at
      }
    end

    def tier_match?
      actual_tier_used.present? && actual_tier_used == recommended_tier
    end

    # ==========================================================================
    # CLASS METHODS
    # ==========================================================================

    def self.tier_distribution(account, period: 30.days)
      for_account(account)
        .where("created_at >= ?", period.ago)
        .group(:recommended_tier)
        .count
    end

    def self.accuracy_stats(account, period: 30.days)
      assessments = for_account(account)
                      .where("created_at >= ?", period.ago)
                      .where.not(actual_tier_used: nil)

      total = assessments.count
      matched = assessments.where("actual_tier_used = recommended_tier").count

      {
        total_assessments: total,
        tier_matches: matched,
        accuracy_percentage: total > 0 ? (matched.to_f / total * 100).round(2) : 0
      }
    end

    private

    def set_defaults
      self.complexity_signals ||= {}
      self.input_token_count ||= 0
      self.tool_count ||= 0
      self.conversation_depth ||= 0
    end
  end
end
