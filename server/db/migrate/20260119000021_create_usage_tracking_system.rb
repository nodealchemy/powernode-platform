# frozen_string_literal: true

class CreateUsageTrackingSystem < ActiveRecord::Migration[8.0]
  def change
    # Usage meters - define what to track
    create_table :usage_meters, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { "gen_random_uuid()" }

      # Meter definition
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :unit_name, null: false, default: "units"

      # Billing configuration
      t.string :aggregation_type, null: false, default: "sum" # sum, max, count, last
      t.string :billing_model, null: false, default: "tiered" # tiered, volume, package, flat
      t.boolean :is_billable, null: false, default: true

      # Reset configuration
      t.string :reset_period, null: false, default: "monthly" # never, daily, weekly, monthly, yearly

      # Status
      t.boolean :is_active, null: false, default: true

      # Pricing tiers (JSONB for flexibility)
      t.jsonb :pricing_tiers, default: []

      t.timestamps
    end

    add_index :usage_meters, :slug, unique: true
    add_index :usage_meters, :is_active

    # Usage events - raw event storage
    create_table :usage_events, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { "gen_random_uuid()" }
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :usage_meter, type: :uuid, null: false, foreign_key: true

      # Event data
      t.string :event_id, null: false # Idempotency key
      t.decimal :quantity, precision: 15, scale: 4, null: false, default: 1.0
      t.datetime :timestamp, null: false

      # Context
      t.references :user, type: :uuid, foreign_key: true
      t.string :source # api, webhook, system
      t.jsonb :properties, default: {}
      t.jsonb :metadata, default: {}

      # Processing status
      t.boolean :is_processed, null: false, default: false
      t.datetime :processed_at

      t.timestamps
    end

    add_index :usage_events, [:account_id, :event_id], unique: true
    add_index :usage_events, [:account_id, :usage_meter_id]
    add_index :usage_events, [:account_id, :timestamp]
    add_index :usage_events, :timestamp
    add_index :usage_events, :is_processed

    # Usage summaries - aggregated usage per period
    create_table :usage_summaries, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { "gen_random_uuid()" }
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :usage_meter, type: :uuid, null: false, foreign_key: true
      t.references :subscription, type: :uuid, foreign_key: true

      # Period
      t.date :period_start, null: false
      t.date :period_end, null: false

      # Aggregated values
      t.decimal :total_quantity, precision: 15, scale: 4, null: false, default: 0.0
      t.decimal :billable_quantity, precision: 15, scale: 4, null: false, default: 0.0
      t.integer :event_count, null: false, default: 0

      # Quota tracking
      t.decimal :quota_limit, precision: 15, scale: 4
      t.decimal :quota_used, precision: 15, scale: 4, null: false, default: 0.0
      t.boolean :quota_exceeded, null: false, default: false

      # Billing
      t.decimal :calculated_amount, precision: 15, scale: 2, null: false, default: 0.0
      t.boolean :is_billed, null: false, default: false
      t.references :invoice, type: :uuid, foreign_key: true

      t.timestamps
    end

    add_index :usage_summaries, [:account_id, :usage_meter_id, :period_start], unique: true, name: "idx_usage_summaries_unique_period"
    add_index :usage_summaries, [:account_id, :period_start]
    add_index :usage_summaries, :is_billed

    # Usage quotas - per-account limits
    create_table :usage_quotas, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { "gen_random_uuid()" }
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :usage_meter, type: :uuid, null: false, foreign_key: true
      t.references :plan, type: :uuid, foreign_key: true

      # Quota settings
      t.decimal :soft_limit, precision: 15, scale: 4
      t.decimal :hard_limit, precision: 15, scale: 4
      t.boolean :allow_overage, null: false, default: true
      t.decimal :overage_rate, precision: 15, scale: 4 # Cost per unit over limit

      # Alerts
      t.integer :warning_threshold_percent, default: 80
      t.integer :critical_threshold_percent, default: 95
      t.boolean :notify_on_warning, null: false, default: true
      t.boolean :notify_on_exceeded, null: false, default: true

      # Current period tracking
      t.decimal :current_usage, precision: 15, scale: 4, null: false, default: 0.0
      t.datetime :current_period_start
      t.datetime :current_period_end

      t.timestamps
    end

    add_index :usage_quotas, [:account_id, :usage_meter_id], unique: true

    # Add CHECK constraints
    execute <<-SQL
      ALTER TABLE usage_meters
      ADD CONSTRAINT check_aggregation_type
      CHECK (aggregation_type IN ('sum', 'max', 'count', 'last', 'average'));

      ALTER TABLE usage_meters
      ADD CONSTRAINT check_billing_model
      CHECK (billing_model IN ('tiered', 'volume', 'package', 'flat', 'per_unit'));

      ALTER TABLE usage_meters
      ADD CONSTRAINT check_reset_period
      CHECK (reset_period IN ('never', 'daily', 'weekly', 'monthly', 'yearly', 'billing_period'));

      ALTER TABLE usage_events
      ADD CONSTRAINT check_usage_event_source
      CHECK (source IS NULL OR source IN ('api', 'webhook', 'system', 'import', 'internal'));
    SQL
  end
end
