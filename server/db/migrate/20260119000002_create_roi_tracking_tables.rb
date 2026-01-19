# frozen_string_literal: true

class CreateRoiTrackingTables < ActiveRecord::Migration[8.0]
  def change
    # ROI Metrics - tracks return on investment for AI operations
    create_table :ai_roi_metrics, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.string :metric_type, null: false
      t.string :period_type, null: false, default: "daily"
      t.date :period_date, null: false

      # Resource attribution (polymorphic)
      t.string :attributable_type
      t.uuid :attributable_id

      # Cost metrics
      t.decimal :ai_cost_usd, precision: 12, scale: 4, null: false, default: 0
      t.decimal :infrastructure_cost_usd, precision: 12, scale: 4, null: false, default: 0
      t.decimal :total_cost_usd, precision: 12, scale: 4, null: false, default: 0

      # Value metrics
      t.decimal :time_saved_hours, precision: 10, scale: 2, null: false, default: 0
      t.decimal :time_saved_value_usd, precision: 12, scale: 4, null: false, default: 0
      t.decimal :error_reduction_value_usd, precision: 12, scale: 4, null: false, default: 0
      t.decimal :throughput_value_usd, precision: 12, scale: 4, null: false, default: 0
      t.decimal :total_value_usd, precision: 12, scale: 4, null: false, default: 0

      # ROI calculations
      t.decimal :roi_percentage, precision: 10, scale: 2
      t.decimal :net_benefit_usd, precision: 12, scale: 4
      t.decimal :cost_per_task_usd, precision: 12, scale: 6
      t.decimal :value_per_task_usd, precision: 12, scale: 6

      # Baseline comparison
      t.decimal :baseline_cost_usd, precision: 12, scale: 4
      t.decimal :baseline_time_hours, precision: 10, scale: 2
      t.decimal :efficiency_gain_percentage, precision: 10, scale: 2

      # Activity metrics
      t.integer :tasks_completed, null: false, default: 0
      t.integer :tasks_automated, null: false, default: 0
      t.integer :errors_prevented, null: false, default: 0
      t.integer :manual_interventions, null: false, default: 0

      # Quality metrics
      t.decimal :accuracy_rate, precision: 5, scale: 4
      t.decimal :customer_satisfaction_score, precision: 3, scale: 2

      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :ai_roi_metrics, [:account_id, :period_type, :period_date],
              name: "idx_roi_metrics_account_period"
    add_index :ai_roi_metrics, [:account_id, :metric_type, :period_date],
              name: "idx_roi_metrics_account_type_date"
    add_index :ai_roi_metrics, [:attributable_type, :attributable_id],
              name: "idx_roi_metrics_attributable"
    add_index :ai_roi_metrics, :period_date

    # Add check constraints
    execute <<-SQL
      ALTER TABLE ai_roi_metrics
      ADD CONSTRAINT check_roi_metric_type
      CHECK (metric_type IN ('workflow', 'agent', 'provider', 'team', 'account_total', 'department'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_roi_metrics
      ADD CONSTRAINT check_roi_period_type
      CHECK (period_type IN ('daily', 'weekly', 'monthly', 'quarterly', 'yearly'))
    SQL

    # Cost Attribution - detailed cost breakdown for ROI analysis
    create_table :ai_cost_attributions, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :roi_metric, foreign_key: { to_table: :ai_roi_metrics }, type: :uuid

      # Source attribution
      t.string :source_type, null: false
      t.uuid :source_id
      t.string :source_name

      # Cost breakdown
      t.string :cost_category, null: false
      t.decimal :amount_usd, precision: 12, scale: 6, null: false
      t.string :currency, null: false, default: "USD"

      # Context
      t.integer :tokens_used
      t.integer :api_calls
      t.integer :compute_minutes
      t.decimal :storage_gb, precision: 10, scale: 4

      # Provider details
      t.references :provider, foreign_key: { to_table: :ai_providers }, type: :uuid
      t.string :model_name
      t.decimal :cost_per_token, precision: 12, scale: 10

      t.date :attribution_date, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :ai_cost_attributions, [:account_id, :attribution_date],
              name: "idx_cost_attributions_account_date"
    add_index :ai_cost_attributions, [:source_type, :source_id],
              name: "idx_cost_attributions_source"
    add_index :ai_cost_attributions, [:cost_category, :attribution_date]
    add_index :ai_cost_attributions, :attribution_date

    # Add check constraint for cost categories
    execute <<-SQL
      ALTER TABLE ai_cost_attributions
      ADD CONSTRAINT check_cost_category
      CHECK (cost_category IN ('ai_inference', 'ai_training', 'embedding', 'storage', 'compute', 'api_calls', 'bandwidth', 'other'))
    SQL

    # Provider Metrics - time-series metrics for providers (AIOps)
    create_table :ai_provider_metrics, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :provider, null: false, foreign_key: { to_table: :ai_providers }, type: :uuid

      # Time bucketing
      t.datetime :recorded_at, null: false
      t.string :granularity, null: false, default: "minute"

      # Request metrics
      t.integer :request_count, null: false, default: 0
      t.integer :success_count, null: false, default: 0
      t.integer :failure_count, null: false, default: 0
      t.integer :timeout_count, null: false, default: 0
      t.integer :rate_limit_count, null: false, default: 0

      # Latency metrics (milliseconds)
      t.decimal :avg_latency_ms, precision: 10, scale: 2
      t.decimal :min_latency_ms, precision: 10, scale: 2
      t.decimal :max_latency_ms, precision: 10, scale: 2
      t.decimal :p50_latency_ms, precision: 10, scale: 2
      t.decimal :p95_latency_ms, precision: 10, scale: 2
      t.decimal :p99_latency_ms, precision: 10, scale: 2

      # Token metrics
      t.bigint :total_input_tokens, null: false, default: 0
      t.bigint :total_output_tokens, null: false, default: 0
      t.bigint :total_tokens, null: false, default: 0

      # Cost metrics
      t.decimal :total_cost_usd, precision: 12, scale: 6, null: false, default: 0
      t.decimal :avg_cost_per_request, precision: 12, scale: 8
      t.decimal :cost_per_1k_tokens, precision: 12, scale: 8

      # Quality metrics
      t.decimal :success_rate, precision: 5, scale: 4
      t.decimal :error_rate, precision: 5, scale: 4

      # Circuit breaker state
      t.string :circuit_state
      t.integer :consecutive_failures, null: false, default: 0

      t.jsonb :error_breakdown, null: false, default: {}
      t.jsonb :model_breakdown, null: false, default: {}
      t.timestamps
    end

    add_index :ai_provider_metrics, [:provider_id, :recorded_at],
              name: "idx_provider_metrics_provider_time"
    add_index :ai_provider_metrics, [:account_id, :recorded_at],
              name: "idx_provider_metrics_account_time"
    add_index :ai_provider_metrics, [:granularity, :recorded_at]
    add_index :ai_provider_metrics, :recorded_at

    # Add check constraint for granularity
    execute <<-SQL
      ALTER TABLE ai_provider_metrics
      ADD CONSTRAINT check_metric_granularity
      CHECK (granularity IN ('minute', 'hour', 'day', 'week', 'month'))
    SQL
  end
end
