# frozen_string_literal: true

class RemoveAppSystemTables < ActiveRecord::Migration[8.0]
  def up
    # Remove legacy app-related columns from app_subscriptions
    remove_column :app_subscriptions, :app_id, :uuid if column_exists?(:app_subscriptions, :app_id)
    remove_column :app_subscriptions, :app_plan_id, :uuid if column_exists?(:app_subscriptions, :app_plan_id)

    # Rename table to marketplace_subscriptions for clarity
    if table_exists?(:app_subscriptions) && !table_exists?(:marketplace_subscriptions)
      rename_table :app_subscriptions, :marketplace_subscriptions
    end

    # Drop orphaned app-related tables (if they exist)
    tables_to_drop = %w[
      apps
      app_plans
      app_features
      app_reviews
      app_analytics
      app_endpoints
      app_webhooks
      app_webhook_deliveries
      app_endpoint_calls
      marketplace_categories
      marketplace_listings
      review_aggregation_cache
    ]

    tables_to_drop.each do |table|
      if table_exists?(table)
        execute("DROP TABLE IF EXISTS #{table} CASCADE")
      end
    end
  end

  def down
    # Rename table back if it was renamed
    if table_exists?(:marketplace_subscriptions) && !table_exists?(:app_subscriptions)
      rename_table :marketplace_subscriptions, :app_subscriptions
    end

    # Add back columns
    if table_exists?(:app_subscriptions)
      add_column :app_subscriptions, :app_id, :uuid unless column_exists?(:app_subscriptions, :app_id)
      add_column :app_subscriptions, :app_plan_id, :uuid unless column_exists?(:app_subscriptions, :app_plan_id)
    end
  end
end
