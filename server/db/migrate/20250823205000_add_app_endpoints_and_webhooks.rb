# frozen_string_literal: true

class AddAppEndpointsAndWebhooks < ActiveRecord::Migration[8.0]
  def change
    # Create app_endpoints table
    create_table :app_endpoints, id: false do |t|
      t.string :id, limit: 36, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :app, null: false, foreign_key: { on_delete: :cascade }, type: :string, limit: 36
      t.string :name, null: false, limit: 255
      t.string :slug, null: false, limit: 255
      t.text :description
      t.string :http_method, null: false, limit: 10
      t.string :path, null: false, limit: 500
      t.text :request_schema
      t.text :response_schema
      t.jsonb :headers, default: {}
      t.jsonb :parameters, default: {}
      t.jsonb :authentication, default: {}
      t.jsonb :rate_limits, default: {}
      t.boolean :requires_auth, default: true
      t.boolean :is_public, default: false
      t.boolean :is_active, default: true
      t.string :version, limit: 20, default: 'v1'
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index [:app_id, :slug], unique: true
      t.index [:app_id, :http_method, :path], unique: true
      t.index :http_method
      t.index :is_public
      t.index :is_active
      t.index :version
    end

    # Create app_webhooks table
    create_table :app_webhooks, id: false do |t|
      t.string :id, limit: 36, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :app, null: false, foreign_key: { on_delete: :cascade }, type: :string, limit: 36
      t.string :name, null: false, limit: 255
      t.string :slug, null: false, limit: 255
      t.text :description
      t.string :event_type, null: false, limit: 100
      t.string :url, null: false, limit: 1000
      t.string :http_method, limit: 10, default: 'POST'
      t.jsonb :headers, default: {}
      t.jsonb :payload_template, default: {}
      t.jsonb :authentication, default: {}
      t.jsonb :retry_config, default: {}
      t.boolean :is_active, default: true
      t.string :secret_token, limit: 255
      t.integer :timeout_seconds, default: 30
      t.integer :max_retries, default: 3
      t.string :content_type, limit: 100, default: 'application/json'
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      t.index [:app_id, :slug], unique: true
      t.index [:app_id, :event_type]
      t.index :event_type
      t.index :is_active
    end

    # Create app_endpoint_calls table for analytics
    create_table :app_endpoint_calls, id: false do |t|
      t.string :id, limit: 36, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :app_endpoint, null: false, foreign_key: { on_delete: :cascade }, type: :string, limit: 36
      t.references :account, null: true, foreign_key: true, type: :string, limit: 36
      t.string :request_id, limit: 100
      t.integer :status_code
      t.integer :response_time_ms
      t.bigint :request_size_bytes
      t.bigint :response_size_bytes
      t.string :user_agent, limit: 500
      t.string :ip_address, limit: 45
      t.jsonb :request_headers, default: {}
      t.jsonb :response_headers, default: {}
      t.text :error_message
      t.timestamp :called_at, default: -> { 'CURRENT_TIMESTAMP' }

      t.index :status_code
      t.index :called_at
      t.index :request_id
    end

    # Create app_webhook_deliveries table for tracking
    create_table :app_webhook_deliveries, id: false do |t|
      t.string :id, limit: 36, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :app_webhook, null: false, foreign_key: { on_delete: :cascade }, type: :string, limit: 36
      t.string :delivery_id, limit: 100
      t.string :event_id, limit: 100
      t.string :status, limit: 20, default: 'pending'
      t.integer :status_code
      t.integer :response_time_ms
      t.integer :attempt_number, default: 1
      t.text :request_body
      t.text :response_body
      t.jsonb :request_headers, default: {}
      t.jsonb :response_headers, default: {}
      t.text :error_message
      t.timestamp :delivered_at
      t.timestamp :next_retry_at
      t.timestamps null: false

      t.index :delivery_id, unique: true
      t.index :event_id
      t.index :status
      t.index :delivered_at
      t.index :next_retry_at
    end

    # Add check constraints
    add_check_constraint :app_endpoints, "http_method IN ('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS')", name: 'valid_http_method'
    add_check_constraint :app_webhooks, "http_method IN ('POST', 'PUT', 'PATCH')", name: 'valid_webhook_http_method'
    add_check_constraint :app_webhooks, "timeout_seconds > 0 AND timeout_seconds <= 300", name: 'valid_timeout_seconds'
    add_check_constraint :app_webhooks, "max_retries >= 0 AND max_retries <= 10", name: 'valid_max_retries'
    add_check_constraint :app_endpoint_calls, "status_code >= 100 AND status_code <= 599", name: 'valid_status_code'
    add_check_constraint :app_endpoint_calls, "response_time_ms >= 0", name: 'valid_response_time'
    add_check_constraint :app_webhook_deliveries, "status IN ('pending', 'delivered', 'failed', 'cancelled')", name: 'valid_delivery_status'
    add_check_constraint :app_webhook_deliveries, "attempt_number > 0", name: 'valid_attempt_number'
  end
end