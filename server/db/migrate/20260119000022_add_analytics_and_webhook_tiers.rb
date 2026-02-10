# frozen_string_literal: true

# Webhook Tiers - Core webhook rate limiting and delivery stats
#
# Enterprise analytics tiers are in
# enterprise/server/db/migrate/20260119000022_add_enterprise_analytics_tiers.rb
#
class AddAnalyticsAndWebhookTiers < ActiveRecord::Migration[8.0]
  def change
    # Webhook tier - per endpoint
    add_column :webhook_endpoints, :tier, :string, null: false, default: "free"
    add_column :webhook_endpoints, :daily_limit, :integer, null: false, default: 100
    add_column :webhook_endpoints, :daily_count, :integer, null: false, default: 0
    add_column :webhook_endpoints, :daily_count_reset_at, :datetime
    add_column :webhook_endpoints, :signature_secret, :string

    add_index :webhook_endpoints, :tier

    # Webhook delivery stats
    create_table :webhook_delivery_stats, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { "gen_random_uuid()" }
      t.references :webhook_endpoint, type: :uuid, null: false, foreign_key: true

      # Period
      t.date :stat_date, null: false

      # Counts
      t.integer :total_deliveries, null: false, default: 0
      t.integer :successful_deliveries, null: false, default: 0
      t.integer :failed_deliveries, null: false, default: 0
      t.integer :retried_deliveries, null: false, default: 0

      # Latency (in milliseconds)
      t.integer :avg_latency_ms
      t.integer :min_latency_ms
      t.integer :max_latency_ms
      t.integer :p95_latency_ms

      # Error breakdown (JSONB)
      t.jsonb :error_counts, default: {}

      t.timestamps
    end

    add_index :webhook_delivery_stats, [ :webhook_endpoint_id, :stat_date ], unique: true, name: "idx_webhook_stats_endpoint_date"
    add_index :webhook_delivery_stats, :stat_date

    # Add CHECK constraint for webhook tiers
    execute <<-SQL
      ALTER TABLE webhook_endpoints
      ADD CONSTRAINT check_webhook_tier
      CHECK (tier IN ('free', 'pro', 'enterprise'));
    SQL
  end
end
