# frozen_string_literal: true

class Ai::CostOptimizationService
  include ActiveModel::Model
  include ActiveModel::Attributes

  # Include extracted modules
  include CostOptimization::Initialization
  include CostOptimization::CostAnalysis
  include CostOptimization::ProviderOptimization
  include CostOptimization::UsagePatterns
  include CostOptimization::BudgetManagement
  include CostOptimization::CostTracking
  include CostOptimization::Recommendations

  class OptimizationError < StandardError; end

  # Returns the cheapest active provider for an account, preferring those
  # with the lowest priority order (highest priority). Falls back to any active provider.
  def self.cheapest_provider(account)
    Ai::Provider.where(account: account, is_active: true)
                .order(priority_order: :asc)
                .first
  end

  def initialize(account:, time_range: 30.days)
    @account = account
    @time_range = time_range
    @start_date = time_range.ago
    @end_date = Time.current
    @logger = Rails.logger
    @provider_costs = load_provider_costs
    @usage_tracker = initialize_usage_tracker
    @cost_trackers = {}
  end
end
