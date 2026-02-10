# frozen_string_literal: true

# Credit Usage Rate Model - Pricing rates for AI operations
#
# Defines credit consumption rates for different operation types.
#
module Ai
  class CreditUsageRate < ApplicationRecord
    self.table_name = "ai_credit_usage_rates"

    # Validations
    validates :operation_type, presence: true
    validates :effective_from, presence: true

    # Scopes
    scope :active, -> { where(is_active: true) }
    scope :for_operation, ->(type) { where(operation_type: type) }
    scope :for_provider, ->(provider) { where(provider_type: provider) }
    scope :for_model, ->(model) { where(model_name: model) }
    scope :currently_effective, -> {
      now = Time.current
      where("effective_from <= ?", now)
        .where("effective_until IS NULL OR effective_until >= ?", now)
    }

    # Class methods
    def self.find_active_rate(operation_type:, provider_type: nil, model_name: nil)
      scope = active.currently_effective.for_operation(operation_type)
      scope = scope.for_provider(provider_type) if provider_type.present?
      scope = scope.for_model(model_name) if model_name.present?

      # Try to find most specific match first
      rate = scope.first

      # Fall back to less specific matches
      if rate.nil? && model_name.present?
        rate = active.currently_effective
          .for_operation(operation_type)
          .for_provider(provider_type)
          .where(model_name: nil)
          .first
      end

      if rate.nil? && provider_type.present?
        rate = active.currently_effective
          .for_operation(operation_type)
          .where(provider_type: nil, model_name: nil)
          .first
      end

      rate
    end

    # Instance methods
    def summary
      {
        id: id,
        operation_type: operation_type,
        provider_type: provider_type,
        model_name: model_name,
        credits_per_1k_input_tokens: credits_per_1k_input_tokens&.to_f,
        credits_per_1k_output_tokens: credits_per_1k_output_tokens&.to_f,
        credits_per_request: credits_per_request&.to_f,
        credits_per_minute: credits_per_minute&.to_f,
        credits_per_gb_storage: credits_per_gb_storage&.to_f,
        base_credits: base_credits&.to_f,
        is_active: is_active,
        effective_from: effective_from,
        effective_until: effective_until
      }
    end
  end
end
