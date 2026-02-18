# frozen_string_literal: true

# Outcome Definition Model - Define what constitutes a billable outcome
#
# Defines billable outcomes with success criteria, pricing, and SLA configuration.
#
module Ai
  class OutcomeDefinition < ApplicationRecord
    self.table_name = "ai_outcome_definitions"

    # Associations
    belongs_to :account
    has_many :billing_records, class_name: "Ai::OutcomeBillingRecord", dependent: :restrict_with_error
    has_many :sla_contracts, class_name: "Ai::SlaContract", dependent: :nullify

    # Validations
    validates :name, presence: true, length: { maximum: 100 }
    validates :outcome_type, presence: true, inclusion: {
      in: %w[task_completion quality_threshold classification extraction generation conversation workflow custom]
    }
    validates :validation_method, presence: true, inclusion: {
      in: %w[automatic human_review hybrid api_callback]
    }
    validates :base_price_usd, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :quality_threshold, numericality: {
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 1
    }, allow_nil: true
    validates :sla_target_percentage, numericality: {
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    }, allow_nil: true

    # Scopes
    scope :active, -> { where(is_active: true) }
    scope :for_account, ->(account) { where(account: account) }
    scope :by_type, ->(type) { where(outcome_type: type) }
    scope :system_definitions, -> { where(is_system: true) }
    scope :with_sla, -> { where(sla_enabled: true) }
    scope :currently_valid, -> {
      now = Time.current
      where("effective_from IS NULL OR effective_from <= ?", now)
        .where("effective_until IS NULL OR effective_until >= ?", now)
    }

    # Instance methods
    def calculate_price(tokens_used: 0, duration_minutes: 0)
      total = base_price_usd || 0

      if price_per_token && tokens_used.positive?
        total += price_per_token * tokens_used
      end

      if price_per_minute && duration_minutes.positive?
        total += price_per_minute * duration_minutes
      end

      # Apply min/max constraints
      total = min_charge_usd if min_charge_usd && total < min_charge_usd
      total = max_charge_usd if max_charge_usd && total > max_charge_usd

      total.round(4)
    end

    def apply_volume_discount(base_price, volume_count)
      return base_price if volume_tiers.blank?

      discount_percentage = 0
      volume_tiers.each do |tier|
        if volume_count >= tier["min_volume"]
          discount_percentage = tier["discount_percentage"]
        end
      end

      (base_price * (1 - discount_percentage / 100)).round(4)
    end

    def evaluate_success(result)
      return true if success_criteria.blank?

      criteria = success_criteria.with_indifferent_access

      # Check quality threshold
      if criteria[:quality_score] && result[:quality_score]
        return false if result[:quality_score] < criteria[:quality_score]
      end

      # Check completion status
      if criteria[:status]
        return false unless criteria[:status].include?(result[:status])
      end

      # Check required fields
      if criteria[:required_fields]
        criteria[:required_fields].each do |field|
          return false if result[field].blank?
        end
      end

      true
    end

    def currently_valid?
      now = Time.current
      (effective_from.nil? || effective_from <= now) &&
        (effective_until.nil? || effective_until >= now)
    end

    def billable?
      is_active? && currently_valid?
    end

    def summary
      {
        id: id,
        name: name,
        description: description,
        outcome_type: outcome_type,
        category: category,
        validation_method: validation_method,
        pricing: {
          base_price_usd: base_price_usd.to_f,
          price_per_token: price_per_token&.to_f,
          price_per_minute: price_per_minute&.to_f,
          min_charge_usd: min_charge_usd&.to_f,
          max_charge_usd: max_charge_usd&.to_f
        },
        sla: {
          enabled: sla_enabled,
          target_percentage: sla_target_percentage&.to_f,
          credit_percentage: sla_credit_percentage&.to_f
        },
        is_active: is_active,
        is_system: is_system,
        free_tier_count: free_tier_count,
        created_at: created_at
      }
    end
  end
end
