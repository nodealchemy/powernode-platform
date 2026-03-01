# frozen_string_literal: true

module Ai
  class CostAttribution < ApplicationRecord
    include Auditable

    # model_name is a reserved ActiveRecord method, so we need custom handling
    # Use read_attribute/write_attribute directly to bypass the accessor issue
    class << self
      # Override to allow model_name column
      def dangerous_attribute_method?(method_name)
        return false if method_name.to_s == "model_name"
        super
      end
    end

    # Define model_name reader before ActiveRecord can raise an error
    silence_warnings do
      define_method(:model_name) do
        read_attribute(:model_name)
      end

      define_method(:model_name=) do |value|
        write_attribute(:model_name, value)
      end
    end

    # ==========================================================================
    # CONSTANTS
    # ==========================================================================

    SOURCE_TYPES = %w[workflow agent provider team execution].freeze
    COST_CATEGORIES = %w[ai_inference ai_training embedding storage compute api_calls bandwidth other].freeze

    # ==========================================================================
    # ASSOCIATIONS
    # ==========================================================================

    belongs_to :account
    belongs_to :roi_metric, class_name: "Ai::RoiMetric", foreign_key: "roi_metric_id", optional: true
    belongs_to :provider, class_name: "Ai::Provider", foreign_key: "provider_id", optional: true

    # ==========================================================================
    # VALIDATIONS
    # ==========================================================================

    validates :source_type, presence: true, inclusion: { in: SOURCE_TYPES }
    validates :cost_category, presence: true, inclusion: { in: COST_CATEGORIES }
    validates :amount_usd, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :attribution_date, presence: true
    validates :currency, presence: true

    # ==========================================================================
    # SCOPES
    # ==========================================================================

    scope :for_account, ->(account) { where(account: account) }
    scope :for_date, ->(date) { where(attribution_date: date) }
    scope :for_date_range, ->(start_date, end_date) { where(attribution_date: start_date..end_date) }
    scope :by_category, ->(category) { where(cost_category: category) }
    scope :by_source_type, ->(type) { where(source_type: type) }
    scope :for_source, ->(type, id) { where(source_type: type, source_id: id) }
    scope :for_provider, ->(provider) { where(provider: provider) }
    scope :recent, ->(days = 30) { where("attribution_date >= ?", days.days.ago.to_date) }
    scope :ai_costs, -> { where(cost_category: %w[ai_inference ai_training embedding]) }
    scope :infrastructure_costs, -> { where(cost_category: %w[storage compute bandwidth]) }

    # ==========================================================================
    # CALLBACKS
    # ==========================================================================

    before_validation :set_defaults

    # ==========================================================================
    # INSTANCE METHODS
    # ==========================================================================

    # Get the source resource
    def source
      return nil unless source_type.present? && source_id.present?

      case source_type
      when "workflow"
        Ai::Workflow.find_by(id: source_id)
      when "agent"
        Ai::Agent.find_by(id: source_id)
      when "provider"
        Ai::Provider.find_by(id: source_id)
      when "execution"
        Ai::AgentExecution.find_by(id: source_id)
      else
        nil
      end
    end

    # Calculate cost per token if applicable
    def calculate_cost_per_token
      return nil unless tokens_used.present? && tokens_used > 0

      (amount_usd / tokens_used).round(10)
    end

    # Get attribution summary
    def summary
      {
        id: id,
        source: {
          type: source_type,
          id: source_id,
          name: source_name || source&.try(:name)
        },
        cost: {
          amount: amount_usd,
          currency: currency,
          category: cost_category,
          per_token: calculate_cost_per_token
        },
        usage: {
          tokens: tokens_used,
          api_calls: api_calls,
          compute_minutes: compute_minutes,
          storage_gb: storage_gb
        },
        provider: {
          id: provider_id,
          name: provider&.name,
          model: model_name
        },
        date: attribution_date
      }
    end

    # Class method: Get cost breakdown by category for a period
    def self.cost_breakdown_by_category(account, start_date:, end_date:)
      for_account(account)
        .for_date_range(start_date, end_date)
        .group(:cost_category)
        .sum(:amount_usd)
        .transform_keys(&:to_sym)
    end

    # Class method: Get cost breakdown by source type
    def self.cost_breakdown_by_source_type(account, start_date:, end_date:)
      for_account(account)
        .for_date_range(start_date, end_date)
        .group(:source_type)
        .sum(:amount_usd)
        .transform_keys(&:to_sym)
    end

    # Class method: Get cost breakdown by provider
    def self.cost_breakdown_by_provider(account, start_date:, end_date:)
      results = for_account(account)
                  .for_date_range(start_date, end_date)
                  .joins(:provider)
                  .group("ai_providers.id", "ai_providers.name")
                  .sum(:amount_usd)

      results.map do |(provider_id, provider_name), amount|
        { provider_id: provider_id, provider_name: provider_name, amount_usd: amount }
      end
    end

    # Class method: Get daily cost trend
    def self.daily_cost_trend(account, days: 30)
      for_account(account)
        .for_date_range(days.days.ago.to_date, Date.current)
        .group(:attribution_date)
        .sum(:amount_usd)
        .sort_by { |date, _| date }
        .map { |date, amount| { date: date, amount_usd: amount } }
    end

    # Class method: Get top cost sources
    def self.top_cost_sources(account, limit: 10, start_date: 30.days.ago.to_date, end_date: Date.current)
      for_account(account)
        .for_date_range(start_date, end_date)
        .group(:source_type, :source_id, :source_name)
        .sum(:amount_usd)
        .sort_by { |_, amount| -amount }
        .first(limit)
        .map do |(source_type, source_id, source_name), amount|
          {
            source_type: source_type,
            source_id: source_id,
            source_name: source_name,
            amount_usd: amount
          }
        end
    end

    # Class method: Create attribution from agent execution
    def self.from_agent_execution(execution)
      return nil unless execution.cost_usd.present? && execution.cost_usd > 0

      create!(
        account: execution.agent.account,
        source_type: "execution",
        source_id: execution.id,
        source_name: execution.agent.name,
        cost_category: "ai_inference",
        amount_usd: execution.cost_usd,
        tokens_used: execution.tokens_used,
        api_calls: 1,
        provider: execution.agent.provider,
        model_name: execution.model_used,
        cost_per_token: execution.tokens_used.present? && execution.tokens_used > 0 ?
                          (execution.cost_usd / execution.tokens_used) : nil,
        attribution_date: execution.created_at.to_date
      )
    end

    # Class method: Aggregate attributions into ROI metrics
    def self.aggregate_to_roi_metrics(account, date: Date.current)
      attributions = for_account(account).for_date(date)
      return if attributions.empty?

      # Find or create ROI metric for the day
      roi_metric = Ai::RoiMetric.find_or_initialize_by(
        account: account,
        metric_type: "account_total",
        period_type: "daily",
        period_date: date
      )

      # Calculate totals from attributions
      ai_costs = attributions.ai_costs.sum(:amount_usd)
      infra_costs = attributions.infrastructure_costs.sum(:amount_usd)
      total_tokens = attributions.sum(:tokens_used)
      total_api_calls = attributions.sum(:api_calls)

      roi_metric.assign_attributes(
        ai_cost_usd: ai_costs,
        infrastructure_cost_usd: infra_costs,
        metadata: roi_metric.metadata.merge(
          "total_tokens" => total_tokens,
          "total_api_calls" => total_api_calls,
          "attribution_count" => attributions.count
        )
      )

      # Link attributions to the ROI metric
      attributions.update_all(roi_metric_id: roi_metric.id) if roi_metric.persisted?

      roi_metric.save!
      roi_metric
    end

    private

    def set_defaults
      self.currency ||= "USD"
      self.metadata ||= {}
      self.attribution_date ||= Date.current
    end
  end
end
