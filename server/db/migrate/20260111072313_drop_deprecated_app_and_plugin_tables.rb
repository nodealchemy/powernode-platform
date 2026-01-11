# frozen_string_literal: true

class DropDeprecatedAppAndPluginTables < ActiveRecord::Migration[8.0]
  def up
    # Remove foreign keys from tables that will remain (marketplace_listings, review_aggregation_cache)
    remove_foreign_key :marketplace_listings, :apps if foreign_key_exists?(:marketplace_listings, :apps)
    remove_foreign_key :review_aggregation_cache, :apps if foreign_key_exists?(:review_aggregation_cache, :apps)

    # Remove the app_id column from tables that will remain (since apps table is being dropped)
    remove_column :marketplace_listings, :app_id if column_exists?(:marketplace_listings, :app_id)
    remove_column :review_aggregation_cache, :app_id if column_exists?(:review_aggregation_cache, :app_id)

    # Drop deprecated tables using CASCADE to handle all foreign key dependencies
    deprecated_tables = %w[
      review_notification_deliveries
      review_helpfulness_votes
      review_media_attachments
      review_moderation_actions
      review_notifications
      review_responses
      app_endpoint_calls
      app_webhook_deliveries
      app_endpoints
      app_webhooks
      app_features
      app_subscriptions
      app_plans
      app_reviews
      apps
      plugin_dependencies
      plugin_reviews
      plugin_installations
      plugin_marketplaces
      ai_workflow_template_installations
      devops_pipeline_template_installations
    ]

    deprecated_tables.each do |table|
      if table_exists?(table)
        execute("DROP TABLE IF EXISTS #{table} CASCADE")
        say "Dropped table: #{table}"
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "This migration removes deprecated App and Plugin system tables. These systems have been superseded by the Marketplace and cannot be restored."
  end
end
