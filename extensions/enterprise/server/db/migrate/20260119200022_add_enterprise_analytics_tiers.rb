# frozen_string_literal: true

# Enterprise Analytics Tiers - Tiered analytics configuration and account tier tracking
#
# Depends on core migration 20260119000022_add_analytics_and_webhook_tiers.rb
# which handles webhook tier columns and delivery stats
#
class AddEnterpriseAnalyticsTiers < ActiveRecord::Migration[8.0]
  def change
    # Analytics tier - per account
    add_column :accounts, :analytics_tier, :string, null: false, default: "free"
    add_index :accounts, :analytics_tier

    # Analytics tier configuration
    create_table :analytics_tiers, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { "gen_random_uuid()" }
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.decimal :monthly_price, precision: 10, scale: 2, null: false, default: 0.0
      t.integer :sort_order, null: false, default: 0
      t.boolean :is_active, null: false, default: true

      # Feature limits
      t.integer :retention_days, null: false, default: 30
      t.integer :cohort_months, null: false, default: 3
      t.boolean :csv_export, null: false, default: false
      t.boolean :api_access, null: false, default: false
      t.boolean :forecasting, null: false, default: false
      t.boolean :custom_reports, null: false, default: false
      t.integer :api_calls_per_day, null: false, default: 0

      # Additional features (JSONB for flexibility)
      t.jsonb :features, default: {}

      t.timestamps
    end

    add_index :analytics_tiers, :slug, unique: true
    add_index :analytics_tiers, :is_active

    # Add CHECK constraint for analytics tiers
    execute <<-SQL
      ALTER TABLE accounts
      ADD CONSTRAINT check_analytics_tier
      CHECK (analytics_tier IN ('free', 'starter', 'pro', 'enterprise'));
    SQL

    # Seed default analytics tiers
    reversible do |dir|
      dir.up do
        execute <<-SQL
          INSERT INTO analytics_tiers (id, name, slug, description, monthly_price, sort_order, retention_days, cohort_months, csv_export, api_access, forecasting, custom_reports, api_calls_per_day, created_at, updated_at)
          VALUES
            (gen_random_uuid(), 'Free', 'free', 'Basic analytics with limited history', 0, 0, 30, 0, false, false, false, false, 0, NOW(), NOW()),
            (gen_random_uuid(), 'Starter', 'starter', 'Extended history and basic exports', 29, 1, 90, 3, true, false, false, false, 0, NOW(), NOW()),
            (gen_random_uuid(), 'Pro', 'pro', 'Full analytics suite with API access', 99, 2, 365, 12, true, true, true, false, 1000, NOW(), NOW()),
            (gen_random_uuid(), 'Enterprise', 'enterprise', 'Unlimited analytics with custom reports', 299, 3, -1, -1, true, true, true, true, 10000, NOW(), NOW());
        SQL
      end
    end
  end
end
