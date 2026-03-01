# frozen_string_literal: true

# CostTrackable concern for models that track execution costs
# Provides cost accumulation and display methods for AI operations.
#
# Required columns:
#   - cost (decimal)
#
# Example usage:
#   class MyExecution < ApplicationRecord
#     include CostTrackable
#   end
#
module CostTrackable
  extend ActiveSupport::Concern

  included do
    validates :cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

    scope :with_cost, -> { where("cost > 0") }
    scope :by_cost, -> { order(cost: :desc) }
    scope :free_executions, -> { where("cost = 0 OR cost IS NULL") }
  end

  # Add cost to this execution
  #
  # @param amount [Numeric] Amount to add
  # @return [Boolean] Whether the update succeeded
  def add_cost(amount)
    return false unless amount.is_a?(Numeric) && amount.positive?

    current = cost || 0
    update!(cost: current + amount)
  end

  # Subtract cost from this execution (for refunds/corrections)
  #
  # @param amount [Numeric] Amount to subtract
  # @return [Boolean] Whether the update succeeded
  def subtract_cost(amount)
    return false unless amount.is_a?(Numeric) && amount.positive?

    current = cost || 0
    new_cost = [ current - amount, 0 ].max
    update!(cost: new_cost)
  end

  # Reset cost to zero
  #
  # @return [Boolean] Whether the update succeeded
  def reset_cost!
    update!(cost: 0)
  end

  # Format cost for display
  #
  # @param precision [Integer] Decimal places (default: 6)
  # @return [String] Formatted cost string
  def formatted_cost(precision: 6)
    return "$0.00" unless cost&.positive?

    format("$%.#{precision}f", cost)
  end

  # Format cost in a shorter format for UI display
  #
  # @return [String] Short formatted cost string
  def short_formatted_cost
    return "$0" unless cost&.positive?

    if cost < 0.01
      format("$%.4f", cost)
    elsif cost < 1
      format("$%.2f", cost)
    else
      format("$%.2f", cost)
    end
  end

  # Check if execution has any cost
  #
  # @return [Boolean]
  def has_cost?
    cost.present? && cost.positive?
  end

  # Cost breakdown by category (override in including model for detailed breakdown)
  #
  # @return [Hash] Cost breakdown
  def cost_breakdown
    { total: cost || 0 }
  end

  # Calculate cost per token (for AI operations with token tracking)
  #
  # @param input_tokens [Integer] Number of input tokens
  # @param output_tokens [Integer] Number of output tokens
  # @return [Hash] Cost per token metrics
  def cost_per_token(input_tokens: nil, output_tokens: nil)
    return {} unless cost&.positive?

    result = {}

    if input_tokens&.positive?
      result[:input_cost_per_1k] = (cost / input_tokens * 1000).round(6)
    end

    if output_tokens&.positive?
      result[:output_cost_per_1k] = (cost / output_tokens * 1000).round(6)
    end

    total_tokens = (input_tokens || 0) + (output_tokens || 0)
    if total_tokens.positive?
      result[:total_cost_per_1k] = (cost / total_tokens * 1000).round(6)
    end

    result
  end
end
