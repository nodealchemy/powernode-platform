class AddMissingColumnsForApiKeysAndWebhooks < ActiveRecord::Migration[8.0]
  def change
    # Add missing columns to api_keys table
    add_column :api_keys, :key_prefix, :string, limit: 20
    add_column :api_keys, :key_suffix, :string, limit: 20
    add_column :api_keys, :scopes, :jsonb, default: []
    add_column :api_keys, :allowed_ips, :jsonb, default: []
    add_column :api_keys, :usage_count, :integer, default: 0
    add_column :api_keys, :rate_limit_per_hour, :integer
    add_column :api_keys, :rate_limit_per_day, :integer
    add_column :api_keys, :metadata, :jsonb, default: {}

    # Add missing columns to workers table
    add_reference :workers, :account, null: true, foreign_key: true, type: :uuid

    # Add missing columns to webhook_endpoints table
    add_reference :webhook_endpoints, :created_by, null: true, foreign_key: { to_table: :users }, type: :uuid
    add_column :webhook_endpoints, :content_type, :string, limit: 100, default: 'application/json'
    add_column :webhook_endpoints, :description, :string, limit: 500
    add_column :webhook_endpoints, :retry_limit, :integer, default: 3
    add_column :webhook_endpoints, :retry_backoff, :string, limit: 20, default: 'exponential'
    add_column :webhook_endpoints, :success_count, :integer, default: 0
    add_column :webhook_endpoints, :failure_count, :integer, default: 0
    add_column :webhook_endpoints, :last_delivery_at, :timestamp
    add_column :webhook_endpoints, :metadata, :jsonb, default: {}

    # Add indexes for performance
    add_index :api_keys, :key_prefix
    add_index :api_keys, :key_suffix
    add_index :api_keys, :usage_count
    add_index :api_keys, :scopes, using: :gin
    add_index :api_keys, :allowed_ips, using: :gin
    
    add_index :webhook_endpoints, :content_type
    add_index :webhook_endpoints, :success_count
    add_index :webhook_endpoints, :failure_count
    add_index :webhook_endpoints, :last_delivery_at

    # Add check constraints for data integrity
    add_check_constraint :api_keys, "usage_count >= 0", name: 'valid_api_key_usage_count_v2'
    add_check_constraint :api_keys, "rate_limit_per_hour IS NULL OR rate_limit_per_hour > 0", name: 'valid_api_key_hourly_limit_v2'
    add_check_constraint :api_keys, "rate_limit_per_day IS NULL OR rate_limit_per_day > 0", name: 'valid_api_key_daily_limit_v2'
    
    add_check_constraint :webhook_endpoints, "retry_limit >= 0 AND retry_limit <= 10", name: 'valid_webhook_retry_limit_v2'
    add_check_constraint :webhook_endpoints, "success_count >= 0", name: 'valid_webhook_success_count_v2'
    add_check_constraint :webhook_endpoints, "failure_count >= 0", name: 'valid_webhook_failure_count_v2'
    add_check_constraint :webhook_endpoints, "content_type IN ('application/json', 'application/x-www-form-urlencoded')", name: 'valid_webhook_content_type_v2'
    add_check_constraint :webhook_endpoints, "retry_backoff IN ('linear', 'exponential')", name: 'valid_webhook_retry_backoff_v2'
  end
end
