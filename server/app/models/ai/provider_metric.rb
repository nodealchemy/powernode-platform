# frozen_string_literal: true

module Ai
  class ProviderMetric < ApplicationRecord
    include Auditable

    # ==========================================================================
    # CONSTANTS
    # ==========================================================================

    GRANULARITIES = %w[minute hour day week month].freeze
    CIRCUIT_STATES = %w[closed open half_open].freeze

    # ==========================================================================
    # ASSOCIATIONS
    # ==========================================================================

    belongs_to :account
    belongs_to :provider, class_name: "Ai::Provider"

    # ==========================================================================
    # VALIDATIONS
    # ==========================================================================

    validates :recorded_at, presence: true
    validates :granularity, presence: true, inclusion: { in: GRANULARITIES }
    validates :request_count, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :success_count, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :failure_count, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :total_tokens, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :total_cost_usd, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validate :validate_counts_consistency

    # ==========================================================================
    # SCOPES
    # ==========================================================================

    scope :for_account, ->(account) { where(account: account) }
    scope :for_provider, ->(provider) { where(provider: provider) }
    scope :by_granularity, ->(granularity) { where(granularity: granularity) }
    scope :minute_metrics, -> { where(granularity: "minute") }
    scope :hourly_metrics, -> { where(granularity: "hour") }
    scope :daily_metrics, -> { where(granularity: "day") }
    scope :in_time_range, ->(start_time, end_time) { where(recorded_at: start_time..end_time) }
    scope :recent, ->(duration = 1.hour) { where("recorded_at >= ?", duration.ago) }
    scope :with_errors, -> { where("failure_count > 0") }
    scope :with_rate_limits, -> { where("rate_limit_count > 0") }
    scope :ordered_by_time, -> { order(recorded_at: :desc) }

    # ==========================================================================
    # CALLBACKS
    # ==========================================================================

    before_validation :set_defaults
    before_save :calculate_derived_metrics

    # ==========================================================================
    # INSTANCE METHODS
    # ==========================================================================

    # Calculate success rate
    def calculate_success_rate
      return 100.0 if request_count.zero?

      (success_count.to_f / request_count * 100).round(4)
    end

    # Calculate error rate
    def calculate_error_rate
      return 0.0 if request_count.zero?

      (failure_count.to_f / request_count * 100).round(4)
    end

    # Calculate average cost per request
    def calculate_avg_cost_per_request
      return 0.0 if request_count.zero?

      (total_cost_usd / request_count).round(8)
    end

    # Calculate cost per 1K tokens
    def calculate_cost_per_1k_tokens
      return 0.0 if total_tokens.zero?

      (total_cost_usd / (total_tokens / 1000.0)).round(8)
    end

    # Check if provider is healthy based on metrics
    def healthy?
      return true if request_count.zero?

      success_rate >= 95.0 && consecutive_failures <= 2
    end

    # Check if provider is degraded
    def degraded?
      return false if request_count.zero?

      success_rate.between?(80.0, 95.0) || consecutive_failures.between?(3, 5)
    end

    # Check if provider is unhealthy
    def unhealthy?
      return false if request_count.zero?

      success_rate < 80.0 || consecutive_failures > 5
    end

    # Get health status
    def health_status
      return "unknown" if request_count.zero?
      return "unhealthy" if unhealthy?
      return "degraded" if degraded?

      "healthy"
    end

    # Get metric summary
    def summary
      {
        id: id,
        provider: {
          id: provider_id,
          name: provider&.name
        },
        time: {
          recorded_at: recorded_at,
          granularity: granularity
        },
        requests: {
          total: request_count,
          success: success_count,
          failure: failure_count,
          timeout: timeout_count,
          rate_limited: rate_limit_count
        },
        latency: {
          avg_ms: avg_latency_ms,
          min_ms: min_latency_ms,
          max_ms: max_latency_ms,
          p50_ms: p50_latency_ms,
          p95_ms: p95_latency_ms,
          p99_ms: p99_latency_ms
        },
        tokens: {
          input: total_input_tokens,
          output: total_output_tokens,
          total: total_tokens
        },
        cost: {
          total_usd: total_cost_usd,
          avg_per_request: avg_cost_per_request,
          per_1k_tokens: cost_per_1k_tokens
        },
        rates: {
          success_rate: success_rate,
          error_rate: error_rate
        },
        circuit: {
          state: circuit_state,
          consecutive_failures: consecutive_failures
        },
        health_status: health_status
      }
    end

    # Class method: Record metrics for a provider
    def self.record_metrics(provider:, account:, metrics_data:, granularity: "minute")
      recorded_at = Time.current.beginning_of_minute

      # Find or create metric for this time bucket
      metric = find_or_initialize_by(
        provider: provider,
        account: account,
        granularity: granularity,
        recorded_at: recorded_at
      )

      # Merge in the new metrics
      metric.request_count += metrics_data[:requests] || 0
      metric.success_count += metrics_data[:successes] || 0
      metric.failure_count += metrics_data[:failures] || 0
      metric.timeout_count += metrics_data[:timeouts] || 0
      metric.rate_limit_count += metrics_data[:rate_limits] || 0

      metric.total_input_tokens += metrics_data[:input_tokens] || 0
      metric.total_output_tokens += metrics_data[:output_tokens] || 0
      metric.total_tokens += (metrics_data[:input_tokens] || 0) + (metrics_data[:output_tokens] || 0)

      metric.total_cost_usd += metrics_data[:cost_usd] || 0

      # Update latency stats if provided
      if metrics_data[:latency_ms].present?
        metric.update_latency_stats(metrics_data[:latency_ms])
      end

      # Update circuit state if provided
      if metrics_data[:circuit_state].present?
        metric.circuit_state = metrics_data[:circuit_state]
      end

      if metrics_data[:consecutive_failures].present?
        metric.consecutive_failures = metrics_data[:consecutive_failures]
      end

      # Update error breakdown
      if metrics_data[:error_type].present?
        metric.error_breakdown[metrics_data[:error_type]] ||= 0
        metric.error_breakdown[metrics_data[:error_type]] += 1
      end

      # Update model breakdown
      if metrics_data[:model_name].present?
        metric.model_breakdown[metrics_data[:model_name]] ||= { requests: 0, tokens: 0, cost: 0 }
        metric.model_breakdown[metrics_data[:model_name]]["requests"] += 1
        metric.model_breakdown[metrics_data[:model_name]]["tokens"] += (metrics_data[:input_tokens] || 0) + (metrics_data[:output_tokens] || 0)
        metric.model_breakdown[metrics_data[:model_name]]["cost"] += metrics_data[:cost_usd] || 0
      end

      metric.save!
      metric
    end

    # Update latency statistics
    def update_latency_stats(latency_ms)
      # Simple implementation - for production, use proper percentile calculation
      self.min_latency_ms = [ min_latency_ms, latency_ms ].compact.min
      self.max_latency_ms = [ max_latency_ms, latency_ms ].compact.max

      # Running average for avg_latency_ms
      if avg_latency_ms.nil? || request_count.zero?
        self.avg_latency_ms = latency_ms
      else
        # Incremental mean calculation
        self.avg_latency_ms = ((avg_latency_ms * (request_count - 1)) + latency_ms) / request_count
      end

      # Simplified percentile estimates (in production, use proper algorithms)
      self.p50_latency_ms ||= latency_ms
      self.p95_latency_ms ||= latency_ms
      self.p99_latency_ms ||= latency_ms
    end

    # Class method: Aggregate minute metrics to hourly
    def self.aggregate_to_hourly(provider:, account:, hour:)
      minute_metrics = for_provider(provider)
                         .for_account(account)
                         .minute_metrics
                         .in_time_range(hour.beginning_of_hour, hour.end_of_hour)

      return nil if minute_metrics.empty?

      create!(
        provider: provider,
        account: account,
        granularity: "hour",
        recorded_at: hour.beginning_of_hour,
        request_count: minute_metrics.sum(:request_count),
        success_count: minute_metrics.sum(:success_count),
        failure_count: minute_metrics.sum(:failure_count),
        timeout_count: minute_metrics.sum(:timeout_count),
        rate_limit_count: minute_metrics.sum(:rate_limit_count),
        total_input_tokens: minute_metrics.sum(:total_input_tokens),
        total_output_tokens: minute_metrics.sum(:total_output_tokens),
        total_tokens: minute_metrics.sum(:total_tokens),
        total_cost_usd: minute_metrics.sum(:total_cost_usd),
        avg_latency_ms: minute_metrics.average(:avg_latency_ms),
        min_latency_ms: minute_metrics.minimum(:min_latency_ms),
        max_latency_ms: minute_metrics.maximum(:max_latency_ms),
        p50_latency_ms: minute_metrics.average(:p50_latency_ms),
        p95_latency_ms: minute_metrics.maximum(:p95_latency_ms),
        p99_latency_ms: minute_metrics.maximum(:p99_latency_ms),
        error_breakdown: aggregate_breakdowns(minute_metrics, :error_breakdown),
        model_breakdown: aggregate_breakdowns(minute_metrics, :model_breakdown)
      )
    end

    # Class method: Get provider comparison
    def self.provider_comparison(account, time_range: 1.hour)
      account.ai_providers.map do |provider|
        metrics = for_provider(provider)
                    .for_account(account)
                    .recent(time_range)

        {
          provider_id: provider.id,
          provider_name: provider.name,
          request_count: metrics.sum(:request_count),
          success_rate: calculate_aggregate_success_rate(metrics),
          avg_latency_ms: metrics.average(:avg_latency_ms)&.to_f&.round(2),
          total_cost_usd: metrics.sum(:total_cost_usd).to_f.round(4),
          total_tokens: metrics.sum(:total_tokens),
          health_status: determine_aggregate_health(metrics)
        }
      end
    end

    private

    def set_defaults
      self.request_count ||= 0
      self.success_count ||= 0
      self.failure_count ||= 0
      self.timeout_count ||= 0
      self.rate_limit_count ||= 0
      self.total_input_tokens ||= 0
      self.total_output_tokens ||= 0
      self.total_tokens ||= 0
      self.total_cost_usd ||= 0
      self.consecutive_failures ||= 0
      self.error_breakdown ||= {}
      self.model_breakdown ||= {}
    end

    def calculate_derived_metrics
      self.success_rate = calculate_success_rate
      self.error_rate = calculate_error_rate
      self.avg_cost_per_request = calculate_avg_cost_per_request
      self.cost_per_1k_tokens = calculate_cost_per_1k_tokens
    end

    def validate_counts_consistency
      return unless request_count.present? && success_count.present? && failure_count.present?

      if success_count + failure_count > request_count
        errors.add(:base, "Success and failure counts cannot exceed total request count")
      end
    end

    def self.aggregate_breakdowns(metrics, field)
      metrics.pluck(field).each_with_object({}) do |breakdown, result|
        next unless breakdown.is_a?(Hash)

        breakdown.each do |key, value|
          if value.is_a?(Numeric)
            result[key] ||= 0
            result[key] += value
          elsif value.is_a?(Hash)
            result[key] ||= {}
            value.each do |k, v|
              result[key][k] ||= 0
              result[key][k] += v if v.is_a?(Numeric)
            end
          end
        end
      end
    end

    def self.calculate_aggregate_success_rate(metrics)
      total_requests = metrics.sum(:request_count)
      return 100.0 if total_requests.zero?

      total_successes = metrics.sum(:success_count)
      (total_successes.to_f / total_requests * 100).round(2)
    end

    def self.determine_aggregate_health(metrics)
      return "unknown" if metrics.empty?

      latest = metrics.ordered_by_time.first
      latest&.health_status || "unknown"
    end
  end
end
