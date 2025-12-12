# frozen_string_literal: true

class CreateMarketplaceInfrastructure < ActiveRecord::Migration[8.0]
  def change
    # Create marketplace_categories table
    create_table :marketplace_categories, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.string :name, null: false, limit: 255
      t.string :slug, null: false, limit: 255
      t.text :description
      t.string :icon, limit: 100
      t.integer :sort_order, default: 0
      t.boolean :is_active, default: true
      t.timestamps null: false

      t.index :slug, unique: true, name: 'idx_marketplace_categories_on_slug_unique'
      t.index :is_active, name: 'idx_marketplace_categories_on_is_active'
      t.index :sort_order, name: 'idx_marketplace_categories_on_sort_order'
    end

    # Create apps table - Core application registry
    create_table :apps, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false, limit: 255
      t.string :slug, null: false, limit: 255
      t.text :description
      t.text :long_description
      t.text :short_description
      t.string :category, limit: 100
      t.string :version, limit: 50, default: '1.0.0'
      t.string :status, limit: 50, default: 'draft'
      t.string :icon
      t.jsonb :tags, default: []
      t.string :homepage_url
      t.string :documentation_url
      t.string :support_url
      t.string :repository_url
      t.string :license
      t.string :privacy_policy_url
      t.string :terms_of_service_url
      t.jsonb :metadata, default: {}
      t.jsonb :configuration, default: {}
      t.timestamp :published_at
      t.timestamps null: false

      t.index :status, name: 'idx_apps_on_status'
      t.index :category, name: 'idx_apps_on_category'
      t.index :published_at, name: 'idx_apps_on_published_at'
      t.index :slug, unique: true, name: 'idx_apps_on_slug_unique'
    end

    # Create app_plans table
    create_table :app_plans, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :app, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.string :name, null: false, limit: 255
      t.string :slug, null: false, limit: 255
      t.text :description
      t.integer :price_cents, default: 0
      t.string :billing_interval, limit: 20, default: 'monthly'
      t.boolean :is_public, default: true
      t.boolean :is_active, default: true
      t.jsonb :features, default: []
      t.jsonb :permissions, default: []
      t.jsonb :limits, default: {}
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index [ :app_id, :slug ], unique: true, name: 'idx_app_plans_on_app_slug_unique'
      t.index :is_public, name: 'idx_app_plans_on_is_public'
      t.index :is_active, name: 'idx_app_plans_on_is_active'
    end

    # Create app_features table
    create_table :app_features, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :app, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.string :name, null: false, limit: 255
      t.string :slug, null: false, limit: 255
      t.text :description
      t.string :feature_type, limit: 50
      t.boolean :default_enabled, default: false
      t.jsonb :configuration, default: {}
      t.jsonb :dependencies, default: []
      t.timestamps null: false

      t.index [ :app_id, :slug ], unique: true, name: 'idx_app_features_on_app_slug_unique'
      t.index :feature_type, name: 'idx_app_features_on_feature_type'
    end

    # Create marketplace_listings table
    create_table :marketplace_listings, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :app, null: false, foreign_key: { on_delete: :cascade }, type: :uuid, index: { unique: true }
      t.string :title, null: false, limit: 255
      t.string :short_description, limit: 500
      t.text :long_description
      t.string :category, limit: 100
      t.jsonb :tags, default: []
      t.jsonb :screenshots, default: []
      t.string :documentation_url, limit: 500
      t.string :support_url, limit: 500
      t.string :homepage_url, limit: 500
      t.boolean :featured, default: false
      t.string :review_status, limit: 50, default: 'pending'
      t.text :review_notes
      t.timestamp :published_at
      t.timestamps null: false

      t.index :category, name: 'idx_marketplace_listings_on_category'
      t.index :review_status, name: 'idx_marketplace_listings_on_review_status'
      t.index :featured, name: 'idx_marketplace_listings_on_featured'
      t.index :published_at, name: 'idx_marketplace_listings_on_published_at'
    end

    # Create app_subscriptions table
    create_table :app_subscriptions, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :app, null: false, foreign_key: true, type: :uuid
      t.references :app_plan, null: false, foreign_key: true, type: :uuid
      t.string :status, limit: 50, default: 'active'
      t.timestamp :subscribed_at, default: -> { 'CURRENT_TIMESTAMP' }
      t.timestamp :cancelled_at
      t.timestamp :next_billing_at
      t.jsonb :configuration, default: {}
      t.jsonb :usage_metrics, default: {}
      t.timestamps null: false

      t.index [ :account_id, :app_id ], unique: true, name: 'idx_app_subscriptions_on_account_app_unique'
      t.index :status, name: 'idx_app_subscriptions_on_status'
      t.index :next_billing_at, name: 'idx_app_subscriptions_on_next_billing_at'
    end

    # Create app_endpoints table
    create_table :app_endpoints, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :app, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.string :name, null: false, limit: 255
      t.string :slug, null: false, limit: 255
      t.text :description
      t.string :http_method, null: false, limit: 10
      t.string :path, null: false, limit: 500
      t.boolean :is_public, default: false
      t.boolean :is_active, default: true
      t.string :version, limit: 20, default: 'v1'
      t.jsonb :parameters, default: {}
      t.jsonb :response_schema, default: {}
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index [ :app_id, :http_method, :path ], unique: true, name: 'index_app_endpoints_unique'
      t.index [ :app_id, :slug ], unique: true, name: 'idx_app_endpoints_on_app_slug_unique'
      t.index [ :app_id ], name: 'idx_app_endpoints_on_app_id'
      t.index [ :http_method ], name: 'idx_app_endpoints_on_http_method'
      t.index [ :is_public ], name: 'idx_app_endpoints_on_is_public'
      t.index [ :is_active ], name: 'idx_app_endpoints_on_is_active'
      t.index [ :version ], name: 'idx_app_endpoints_on_version'
    end

    # Create app_webhooks table
    create_table :app_webhooks, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :app, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.string :name, null: false, limit: 255
      t.string :slug, null: false, limit: 255
      t.text :description
      t.string :event_type, null: false, limit: 100
      t.string :url, null: false, limit: 500
      t.string :http_method, null: false, limit: 10, default: 'POST'
      t.boolean :is_active, default: true
      t.integer :timeout_seconds, default: 30
      t.integer :max_retries, default: 3
      t.string :content_type, limit: 100, default: 'application/json'
      t.jsonb :headers, default: {}
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index [ :app_id, :event_type ], name: 'idx_app_webhooks_on_app_event_type'
      t.index [ :app_id, :slug ], unique: true, name: 'idx_app_webhooks_on_app_slug_unique'
      t.index [ :app_id ], name: 'idx_app_webhooks_on_app_id'
      t.index [ :event_type ], name: 'idx_app_webhooks_on_event_type'
      t.index [ :is_active ], name: 'idx_app_webhooks_on_is_active'
    end

    # Create app_endpoint_calls table - API usage tracking
    create_table :app_endpoint_calls, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :app_endpoint, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.references :account, null: true, foreign_key: true, type: :uuid
      t.string :request_id, limit: 100
      t.integer :status_code
      t.integer :response_time_ms
      t.bigint :request_size_bytes
      t.bigint :response_size_bytes
      t.text :error_message
      t.datetime :called_at, null: false
      t.string :ip_address, limit: 45
      t.string :user_agent, limit: 500
      t.jsonb :request_headers, default: {}
      t.jsonb :response_headers, default: {}
      t.timestamps null: false

      t.index [ :app_endpoint_id ], name: 'idx_app_endpoint_calls_on_app_endpoint_id'
      t.index [ :account_id ], name: 'idx_app_endpoint_calls_on_account_id'
      t.index [ :called_at ], name: 'idx_app_endpoint_calls_on_called_at'
      t.index [ :status_code ], name: 'idx_app_endpoint_calls_on_status_code'
    end

    # Create app_webhook_deliveries table - Webhook delivery tracking
    create_table :app_webhook_deliveries, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :app_webhook, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.string :event_id, null: false
      t.string :status, null: false, default: 'pending'
      t.integer :attempt_number, default: 1
      t.integer :response_status
      t.text :response_body
      t.text :error_message
      t.datetime :attempted_at
      t.datetime :next_retry_at
      t.jsonb :payload, default: {}
      t.timestamps null: false

      t.index [ :app_webhook_id ], name: 'idx_app_webhook_deliveries_on_app_webhook_id'
      t.index [ :event_id ], name: 'idx_app_webhook_deliveries_on_event_id'
      t.index [ :status ], name: 'idx_app_webhook_deliveries_on_status'
      t.index [ :attempted_at ], name: 'idx_app_webhook_deliveries_on_attempted_at'
      t.index [ :next_retry_at ], name: 'idx_app_webhook_deliveries_on_next_retry_at'
    end

    # Create app_analytics table - App metrics and analytics
    create_table :app_analytics, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :app, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.string :metric_name, null: false, limit: 100
      t.decimal :metric_value, precision: 15, scale: 2
      t.timestamp :recorded_at, default: -> { 'CURRENT_TIMESTAMP' }
      t.jsonb :dimensions, default: {}
      t.jsonb :metadata, default: {}

      t.index [ :app_id, :metric_name, :recorded_at ], name: 'idx_app_analytics_on_app_metric_recorded_at'
      t.index [ :metric_name ], name: 'idx_app_analytics_on_metric_name'
      t.index [ :recorded_at ], name: 'idx_app_analytics_on_recorded_at'
    end

    # Add check constraints
    add_check_constraint :apps, "status IN ('draft', 'review', 'published', 'inactive')", name: 'valid_app_status'
    add_check_constraint :app_plans, "billing_interval IN ('monthly', 'yearly', 'one_time')", name: 'valid_app_billing_interval'
    add_check_constraint :app_plans, "price_cents >= 0", name: 'valid_app_plan_price'
    add_check_constraint :marketplace_listings, "review_status IN ('pending', 'approved', 'rejected')", name: 'valid_listing_review_status'
    add_check_constraint :app_subscriptions, "status IN ('active', 'paused', 'cancelled', 'expired')", name: 'valid_app_subscription_status'
    add_check_constraint :app_endpoints, "http_method IN ('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS')", name: 'valid_endpoint_http_method'
    add_check_constraint :app_webhooks, "http_method IN ('POST', 'PUT', 'PATCH')", name: 'valid_webhook_http_method'
    add_check_constraint :app_webhooks, "timeout_seconds > 0 AND timeout_seconds <= 300", name: 'valid_webhook_timeout'
    add_check_constraint :app_webhooks, "max_retries >= 0 AND max_retries <= 10", name: 'valid_webhook_retries'
    add_check_constraint :app_endpoint_calls, "status_code >= 100 AND status_code <= 599", name: 'valid_endpoint_status_code'
    add_check_constraint :app_endpoint_calls, "response_time_ms >= 0", name: 'valid_endpoint_response_time'
    add_check_constraint :app_webhook_deliveries, "status IN ('pending', 'delivered', 'failed', 'cancelled')", name: 'valid_webhook_delivery_status'
    add_check_constraint :app_webhook_deliveries, "attempt_number > 0", name: 'valid_webhook_attempt_number'
  end
end
