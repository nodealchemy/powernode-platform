# frozen_string_literal: true

module Ai
  class ModelRoutingRule < ApplicationRecord
    include Auditable

    # ==========================================================================
    # CONSTANTS
    # ==========================================================================

    RULE_TYPES = %w[capability_based cost_based latency_based quality_based custom ml_optimized].freeze
    STRATEGIES = %w[round_robin weighted cost_optimized latency_optimized quality_optimized hybrid].freeze

    # ==========================================================================
    # ASSOCIATIONS
    # ==========================================================================

    belongs_to :account
    has_many :routing_decisions, class_name: "Ai::RoutingDecision", foreign_key: :routing_rule_id, dependent: :nullify

    # ==========================================================================
    # VALIDATIONS
    # ==========================================================================

    validates :name, presence: true, length: { maximum: 255 }
    validates :rule_type, presence: true, inclusion: { in: RULE_TYPES }
    validates :priority, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 1000 }
    validates :conditions, presence: true
    validates :target, presence: true
    validate :validate_conditions_structure
    validate :validate_target_structure

    # ==========================================================================
    # SCOPES
    # ==========================================================================

    scope :active, -> { where(is_active: true) }
    scope :inactive, -> { where(is_active: false) }
    scope :by_priority, -> { order(priority: :asc) }
    scope :by_type, ->(type) { where(rule_type: type) }
    scope :for_account, ->(account) { where(account: account) }
    scope :recently_matched, -> { where.not(last_matched_at: nil).order(last_matched_at: :desc) }
    scope :high_success_rate, -> { where("times_succeeded > 0 AND (times_succeeded::float / NULLIF(times_matched, 0)) > 0.9") }

    # ==========================================================================
    # CALLBACKS
    # ==========================================================================

    before_validation :set_defaults

    # ==========================================================================
    # INSTANCE METHODS
    # ==========================================================================

    # Check if this rule matches the given request context
    def matches?(request_context)
      return false unless is_active?

      # Check capability requirements
      if conditions["capabilities"].present?
        required_capabilities = Array(conditions["capabilities"])
        request_capabilities = Array(request_context[:capabilities])
        return false unless (required_capabilities - request_capabilities).empty?
      end

      # Check cost threshold
      if conditions["max_cost_per_token"].present? && request_context[:estimated_cost_per_token].present?
        return false if request_context[:estimated_cost_per_token] > conditions["max_cost_per_token"].to_f
      end

      # Check latency threshold
      if conditions["max_latency_ms"].present? && request_context[:expected_latency_ms].present?
        return false if request_context[:expected_latency_ms] > conditions["max_latency_ms"].to_f
      end

      # Check quality threshold
      if conditions["min_quality_score"].present? && request_context[:quality_score].present?
        return false if request_context[:quality_score] < conditions["min_quality_score"].to_f
      end

      # Check token range
      if conditions["min_tokens"].present? && request_context[:estimated_tokens].present?
        return false if request_context[:estimated_tokens] < conditions["min_tokens"].to_i
      end

      if conditions["max_tokens"].present? && request_context[:estimated_tokens].present?
        return false if request_context[:estimated_tokens] > conditions["max_tokens"].to_i
      end

      # Check request type
      if conditions["request_types"].present?
        return false unless Array(conditions["request_types"]).include?(request_context[:request_type])
      end

      # Check model patterns
      if conditions["model_patterns"].present?
        patterns = Array(conditions["model_patterns"])
        model_name = request_context[:model_name].to_s
        return false unless patterns.any? { |p| model_name.match?(Regexp.new(p, Regexp::IGNORECASE)) }
      end

      true
    end

    # Get target providers for this rule
    def target_provider_ids
      Array(target["provider_ids"]).compact
    end

    # Get target strategy
    def routing_strategy
      target["strategy"] || "cost_optimized"
    end

    # Get target model names
    def target_model_names
      Array(target["model_names"]).compact
    end

    # Record a match
    def record_match!(succeeded:)
      attrs = {
        times_matched: times_matched + 1,
        last_matched_at: Time.current
      }

      if succeeded
        attrs[:times_succeeded] = times_succeeded + 1
      else
        attrs[:times_failed] = times_failed + 1
      end

      update!(attrs)
    end

    # Calculate success rate
    def success_rate
      return 0.0 if times_matched.zero?

      (times_succeeded.to_f / times_matched * 100).round(2)
    end

    # Check if rule is performing well
    def performing_well?
      return true if times_matched < 10 # Not enough data

      success_rate >= 85.0
    end

    # Get rule summary
    def summary
      {
        id: id,
        name: name,
        rule_type: rule_type,
        priority: priority,
        is_active: is_active,
        conditions_summary: conditions_summary,
        target_summary: target_summary,
        stats: {
          times_matched: times_matched,
          success_rate: success_rate,
          last_matched_at: last_matched_at
        }
      }
    end

    private

    def set_defaults
      self.conditions ||= {}
      self.target ||= { "strategy" => "cost_optimized" }
    end

    def validate_conditions_structure
      return if conditions.blank?

      unless conditions.is_a?(Hash)
        errors.add(:conditions, "must be a hash")
        return
      end

      # Validate capability list if present
      if conditions["capabilities"].present?
        unless conditions["capabilities"].is_a?(Array)
          errors.add(:conditions, "capabilities must be an array")
        end
      end

      # Validate numeric thresholds
      %w[max_cost_per_token min_quality_score max_latency_ms].each do |threshold|
        if conditions[threshold].present?
          unless conditions[threshold].is_a?(Numeric) || conditions[threshold].to_s.match?(/\A[\d.]+\z/)
            errors.add(:conditions, "#{threshold} must be a number")
          end
        end
      end
    end

    def validate_target_structure
      return if target.blank?

      unless target.is_a?(Hash)
        errors.add(:target, "must be a hash")
        return
      end

      # Validate strategy if present
      if target["strategy"].present?
        unless STRATEGIES.include?(target["strategy"])
          errors.add(:target, "strategy must be one of: #{STRATEGIES.join(', ')}")
        end
      end

      # Validate provider_ids if present
      if target["provider_ids"].present?
        unless target["provider_ids"].is_a?(Array)
          errors.add(:target, "provider_ids must be an array")
        end
      end
    end

    def conditions_summary
      parts = []
      parts << "capabilities: #{conditions['capabilities'].join(', ')}" if conditions["capabilities"].present?
      parts << "max_cost: $#{conditions['max_cost_per_token']}/token" if conditions["max_cost_per_token"].present?
      parts << "max_latency: #{conditions['max_latency_ms']}ms" if conditions["max_latency_ms"].present?
      parts << "min_quality: #{conditions['min_quality_score']}" if conditions["min_quality_score"].present?
      parts.join("; ")
    end

    def target_summary
      parts = []
      parts << "strategy: #{routing_strategy}"
      parts << "providers: #{target_provider_ids.count}" if target_provider_ids.any?
      parts << "models: #{target_model_names.join(', ')}" if target_model_names.any?
      parts.join("; ")
    end
  end
end
