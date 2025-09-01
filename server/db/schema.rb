# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_08_30_014905) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "account_delegations", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "account_id", limit: 36, null: false
    t.string "delegated_user_id", limit: 36, null: false
    t.string "delegated_by_id", limit: 36, null: false
    t.string "role_id", limit: 36
    t.string "status", limit: 20, default: "active", null: false
    t.datetime "expires_at", null: false
    t.datetime "revoked_at"
    t.string "revoked_by", limit: 36
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "delegated_user_id"], name: "index_account_delegations_on_account_id_and_delegated_user_id", unique: true
    t.index ["account_id"], name: "index_account_delegations_on_account_id"
    t.index ["delegated_by_id"], name: "index_account_delegations_on_delegated_by_id"
    t.index ["delegated_user_id"], name: "index_account_delegations_on_delegated_user_id"
    t.index ["expires_at"], name: "index_account_delegations_on_expires_at"
    t.index ["role_id"], name: "index_account_delegations_on_role_id"
    t.index ["status"], name: "index_account_delegations_on_status"
  end

  create_table "accounts", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.string "subdomain", limit: 30
    t.string "status", limit: 20, default: "active", null: false
    t.string "stripe_customer_id", limit: 50
    t.string "paypal_customer_id", limit: 50
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "billing_email"
    t.string "tax_id"
    t.json "settings", default: {}
    t.index ["paypal_customer_id"], name: "index_accounts_on_paypal_customer_id", unique: true, where: "(paypal_customer_id IS NOT NULL)"
    t.index ["status"], name: "index_accounts_on_status"
    t.index ["stripe_customer_id"], name: "index_accounts_on_stripe_customer_id", unique: true, where: "(stripe_customer_id IS NOT NULL)"
    t.index ["subdomain"], name: "index_accounts_on_subdomain", unique: true, where: "((subdomain IS NOT NULL) AND ((subdomain)::text <> ''::text))"
  end

  create_table "admin_settings", id: :string, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "key", null: false
    t.text "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_admin_settings_on_key", unique: true
  end

  create_table "api_key_usages", id: :string, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "api_key_id", null: false
    t.string "endpoint", limit: 500, null: false
    t.string "http_method", limit: 10, null: false
    t.integer "status_code", null: false
    t.integer "request_count", default: 1, null: false
    t.string "ip_address", limit: 45
    t.text "user_agent"
    t.json "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["api_key_id", "created_at"], name: "index_api_key_usages_on_api_key_id_and_created_at"
    t.index ["api_key_id"], name: "index_api_key_usages_on_api_key_id"
    t.index ["created_at"], name: "index_api_key_usages_on_created_at"
    t.index ["endpoint"], name: "index_api_key_usages_on_endpoint"
    t.index ["http_method"], name: "index_api_key_usages_on_http_method"
    t.index ["ip_address"], name: "index_api_key_usages_on_ip_address"
    t.index ["status_code", "created_at"], name: "index_api_key_usages_on_status_code_and_created_at"
    t.index ["status_code"], name: "index_api_key_usages_on_status_code"
  end

  create_table "api_keys", id: :string, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.text "description"
    t.string "key_hash", limit: 64, null: false
    t.string "key_prefix", limit: 20, null: false
    t.string "key_suffix", limit: 10, null: false
    t.string "status", limit: 20, default: "active", null: false
    t.json "scopes"
    t.datetime "expires_at", precision: nil
    t.datetime "last_used_at", precision: nil
    t.integer "usage_count", default: 0, null: false
    t.integer "rate_limit_per_hour"
    t.integer "rate_limit_per_day"
    t.json "allowed_ips"
    t.json "metadata"
    t.string "created_by_id"
    t.string "account_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_api_keys_on_account_id"
    t.index ["created_by_id"], name: "index_api_keys_on_created_by_id"
    t.index ["expires_at"], name: "index_api_keys_on_expires_at"
    t.index ["key_hash"], name: "index_api_keys_on_key_hash", unique: true
    t.index ["last_used_at"], name: "index_api_keys_on_last_used_at"
    t.index ["status", "expires_at"], name: "index_api_keys_on_status_and_expires_at"
    t.index ["status"], name: "index_api_keys_on_status"
    t.index ["usage_count"], name: "index_api_keys_on_usage_count"
  end

  create_table "app_analytics", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "app_id", limit: 36, null: false
    t.string "metric_name", limit: 100, null: false
    t.decimal "metric_value", precision: 15, scale: 2
    t.datetime "recorded_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }
    t.jsonb "metadata", default: {}
    t.index ["app_id"], name: "index_app_analytics_on_app_id"
    t.index ["metric_name"], name: "index_app_analytics_on_metric_name"
    t.index ["recorded_at"], name: "index_app_analytics_on_recorded_at"
  end

  create_table "app_endpoint_calls", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "app_endpoint_id", limit: 36, null: false
    t.string "account_id", limit: 36
    t.string "request_id", limit: 100
    t.integer "status_code"
    t.integer "response_time_ms"
    t.bigint "request_size_bytes"
    t.bigint "response_size_bytes"
    t.string "user_agent", limit: 500
    t.string "ip_address", limit: 45
    t.jsonb "request_headers", default: {}
    t.jsonb "response_headers", default: {}
    t.text "error_message"
    t.datetime "called_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }
    t.index ["account_id"], name: "index_app_endpoint_calls_on_account_id"
    t.index ["app_endpoint_id"], name: "index_app_endpoint_calls_on_app_endpoint_id"
    t.index ["called_at"], name: "index_app_endpoint_calls_on_called_at"
    t.index ["request_id"], name: "index_app_endpoint_calls_on_request_id"
    t.index ["status_code"], name: "index_app_endpoint_calls_on_status_code"
    t.check_constraint "response_time_ms >= 0", name: "valid_response_time"
    t.check_constraint "status_code >= 100 AND status_code <= 599", name: "valid_status_code"
  end

  create_table "app_endpoints", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "app_id", limit: 36, null: false
    t.string "name", limit: 255, null: false
    t.string "slug", limit: 255, null: false
    t.text "description"
    t.string "http_method", limit: 10, null: false
    t.string "path", limit: 500, null: false
    t.text "request_schema"
    t.text "response_schema"
    t.jsonb "headers", default: {}
    t.jsonb "parameters", default: {}
    t.jsonb "authentication", default: {}
    t.jsonb "rate_limits", default: {}
    t.boolean "requires_auth", default: true
    t.boolean "is_public", default: false
    t.boolean "is_active", default: true
    t.string "version", limit: 20, default: "v1"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_id", "http_method", "path"], name: "index_app_endpoints_on_app_id_and_http_method_and_path", unique: true
    t.index ["app_id", "slug"], name: "index_app_endpoints_on_app_id_and_slug", unique: true
    t.index ["app_id"], name: "index_app_endpoints_on_app_id"
    t.index ["http_method"], name: "index_app_endpoints_on_http_method"
    t.index ["is_active"], name: "index_app_endpoints_on_is_active"
    t.index ["is_public"], name: "index_app_endpoints_on_is_public"
    t.index ["version"], name: "index_app_endpoints_on_version"
    t.check_constraint "http_method::text = ANY (ARRAY['GET'::character varying::text, 'POST'::character varying::text, 'PUT'::character varying::text, 'PATCH'::character varying::text, 'DELETE'::character varying::text, 'HEAD'::character varying::text, 'OPTIONS'::character varying::text])", name: "valid_http_method"
  end

  create_table "app_features", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "app_id", limit: 36, null: false
    t.string "name", limit: 255, null: false
    t.string "slug", limit: 255, null: false
    t.text "description"
    t.string "feature_type", limit: 50
    t.boolean "default_enabled", default: false
    t.jsonb "configuration", default: {}
    t.jsonb "dependencies", default: []
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_id", "slug"], name: "index_app_features_on_app_id_and_slug", unique: true
    t.index ["app_id"], name: "index_app_features_on_app_id"
    t.index ["feature_type"], name: "index_app_features_on_feature_type"
  end

  create_table "app_plans", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "app_id", limit: 36, null: false
    t.string "name", limit: 255, null: false
    t.string "slug", limit: 255, null: false
    t.text "description"
    t.integer "price_cents", default: 0
    t.string "billing_interval", limit: 20, default: "monthly"
    t.boolean "is_public", default: true
    t.boolean "is_active", default: true
    t.jsonb "features", default: []
    t.jsonb "permissions", default: []
    t.jsonb "limits", default: {}
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_id", "slug"], name: "index_app_plans_on_app_id_and_slug", unique: true
    t.index ["app_id"], name: "index_app_plans_on_app_id"
    t.index ["is_active"], name: "index_app_plans_on_is_active"
    t.index ["is_public"], name: "index_app_plans_on_is_public"
    t.check_constraint "billing_interval::text = ANY (ARRAY['monthly'::character varying::text, 'yearly'::character varying::text, 'one_time'::character varying::text])", name: "valid_billing_interval"
  end

  create_table "app_reviews", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "app_id", limit: 36, null: false
    t.string "account_id", limit: 36, null: false
    t.integer "rating", null: false
    t.string "title", limit: 255
    t.text "content"
    t.integer "helpful_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_app_reviews_on_account_id"
    t.index ["app_id", "account_id"], name: "index_app_reviews_on_app_id_and_account_id", unique: true
    t.index ["app_id"], name: "index_app_reviews_on_app_id"
    t.index ["created_at"], name: "index_app_reviews_on_created_at"
    t.index ["rating"], name: "index_app_reviews_on_rating"
    t.check_constraint "rating >= 1 AND rating <= 5", name: "rating_range"
  end

  create_table "app_subscriptions", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "account_id", limit: 36, null: false
    t.string "app_id", limit: 36, null: false
    t.string "app_plan_id", limit: 36, null: false
    t.string "status", limit: 50, default: "active"
    t.datetime "subscribed_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }
    t.datetime "cancelled_at", precision: nil
    t.datetime "next_billing_at", precision: nil
    t.jsonb "configuration", default: {}
    t.jsonb "usage_metrics", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "app_id"], name: "index_app_subscriptions_on_account_id_and_app_id", unique: true
    t.index ["account_id"], name: "index_app_subscriptions_on_account_id"
    t.index ["app_id"], name: "index_app_subscriptions_on_app_id"
    t.index ["app_plan_id"], name: "index_app_subscriptions_on_app_plan_id"
    t.index ["next_billing_at"], name: "index_app_subscriptions_on_next_billing_at"
    t.index ["status"], name: "index_app_subscriptions_on_status"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'paused'::character varying::text, 'cancelled'::character varying::text, 'expired'::character varying::text])", name: "valid_subscription_status"
  end

  create_table "app_webhook_deliveries", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "app_webhook_id", limit: 36, null: false
    t.string "delivery_id", limit: 100
    t.string "event_id", limit: 100
    t.string "status", limit: 20, default: "pending"
    t.integer "status_code"
    t.integer "response_time_ms"
    t.integer "attempt_number", default: 1
    t.text "request_body"
    t.text "response_body"
    t.jsonb "request_headers", default: {}
    t.jsonb "response_headers", default: {}
    t.text "error_message"
    t.datetime "delivered_at", precision: nil
    t.datetime "next_retry_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_webhook_id"], name: "index_app_webhook_deliveries_on_app_webhook_id"
    t.index ["delivered_at"], name: "index_app_webhook_deliveries_on_delivered_at"
    t.index ["delivery_id"], name: "index_app_webhook_deliveries_on_delivery_id", unique: true
    t.index ["event_id"], name: "index_app_webhook_deliveries_on_event_id"
    t.index ["next_retry_at"], name: "index_app_webhook_deliveries_on_next_retry_at"
    t.index ["status"], name: "index_app_webhook_deliveries_on_status"
    t.check_constraint "attempt_number > 0", name: "valid_attempt_number"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'delivered'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text])", name: "valid_delivery_status"
  end

  create_table "app_webhooks", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "app_id", limit: 36, null: false
    t.string "name", limit: 255, null: false
    t.string "slug", limit: 255, null: false
    t.text "description"
    t.string "event_type", limit: 100, null: false
    t.string "url", limit: 1000, null: false
    t.string "http_method", limit: 10, default: "POST"
    t.jsonb "headers", default: {}
    t.jsonb "payload_template", default: {}
    t.jsonb "authentication", default: {}
    t.jsonb "retry_config", default: {}
    t.boolean "is_active", default: true
    t.string "secret_token", limit: 255
    t.integer "timeout_seconds", default: 30
    t.integer "max_retries", default: 3
    t.string "content_type", limit: 100, default: "application/json"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_id", "event_type"], name: "index_app_webhooks_on_app_id_and_event_type"
    t.index ["app_id", "slug"], name: "index_app_webhooks_on_app_id_and_slug", unique: true
    t.index ["app_id"], name: "index_app_webhooks_on_app_id"
    t.index ["event_type"], name: "index_app_webhooks_on_event_type"
    t.index ["is_active"], name: "index_app_webhooks_on_is_active"
    t.check_constraint "http_method::text = ANY (ARRAY['POST'::character varying::text, 'PUT'::character varying::text, 'PATCH'::character varying::text])", name: "valid_webhook_http_method"
    t.check_constraint "max_retries >= 0 AND max_retries <= 10", name: "valid_max_retries"
    t.check_constraint "timeout_seconds > 0 AND timeout_seconds <= 300", name: "valid_timeout_seconds"
  end

  create_table "apps", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "account_id", limit: 36, null: false
    t.string "name", limit: 255, null: false
    t.string "slug", limit: 255, null: false
    t.text "description"
    t.text "long_description"
    t.string "category", limit: 100
    t.string "version", limit: 50, default: "1.0.0"
    t.string "status", limit: 50, default: "draft"
    t.jsonb "metadata", default: {}
    t.jsonb "configuration", default: {}
    t.datetime "published_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "short_description"
    t.string "icon"
    t.jsonb "tags", default: []
    t.string "homepage_url"
    t.string "documentation_url"
    t.string "support_url"
    t.string "repository_url"
    t.string "license"
    t.string "privacy_policy_url"
    t.string "terms_of_service_url"
    t.index ["account_id"], name: "index_apps_on_account_id"
    t.index ["category"], name: "index_apps_on_category"
    t.index ["published_at"], name: "index_apps_on_published_at"
    t.index ["slug"], name: "index_apps_on_slug", unique: true
    t.index ["status"], name: "index_apps_on_status"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'review'::character varying::text, 'published'::character varying::text, 'inactive'::character varying::text])", name: "valid_app_status"
  end

  create_table "audit_logs", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "user_id", limit: 36
    t.string "account_id", limit: 36, null: false
    t.string "action", limit: 50, null: false
    t.string "resource_type", limit: 100, null: false
    t.string "resource_id", limit: 36, null: false
    t.string "source", limit: 20, default: "web", null: false
    t.string "ip_address", limit: 45
    t.string "user_agent", limit: 500
    t.datetime "created_at", null: false
    t.json "old_values"
    t.json "new_values"
    t.json "metadata", default: {}
    t.index ["account_id"], name: "index_audit_logs_on_account_id"
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["resource_id"], name: "index_audit_logs_on_resource_id"
    t.index ["resource_type", "resource_id"], name: "index_audit_logs_on_resource_type_and_resource_id"
    t.index ["resource_type"], name: "index_audit_logs_on_resource_type"
    t.index ["source"], name: "index_audit_logs_on_source"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "background_jobs", id: { type: :string, limit: 36, default: -> { "(gen_random_uuid())::character varying" } }, force: :cascade do |t|
    t.string "job_id", limit: 50, null: false
    t.string "job_type", limit: 100, null: false
    t.string "status", limit: 20, default: "pending", null: false
    t.json "parameters"
    t.json "result"
    t.text "error_message"
    t.json "error_details"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_background_jobs_on_created_at"
    t.index ["job_id"], name: "index_background_jobs_on_job_id", unique: true
    t.index ["job_type", "status"], name: "index_background_jobs_on_job_type_and_status"
    t.index ["job_type"], name: "index_background_jobs_on_job_type"
    t.index ["status"], name: "index_background_jobs_on_status"
  end

  create_table "blacklisted_tokens", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "user_id", limit: 36, null: false
    t.string "token", null: false
    t.string "reason", default: "logout"
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["expires_at"], name: "index_blacklisted_tokens_on_expires_at"
    t.index ["token"], name: "index_blacklisted_tokens_on_token", unique: true
    t.index ["user_id"], name: "index_blacklisted_tokens_on_user_id"
  end

  create_table "database_backups", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "filename", null: false
    t.string "backup_type", null: false
    t.string "status", default: "pending", null: false
    t.text "description"
    t.text "file_path"
    t.bigint "file_size"
    t.integer "duration_seconds"
    t.text "error_message"
    t.datetime "started_at", precision: nil
    t.datetime "completed_at", precision: nil
    t.string "user_id", limit: 36, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["backup_type"], name: "index_database_backups_on_backup_type"
    t.index ["created_at"], name: "index_database_backups_on_created_at"
    t.index ["status"], name: "index_database_backups_on_status"
    t.index ["user_id"], name: "index_database_backups_on_user_id"
  end

  create_table "database_restores", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "database_backup_id", limit: 36, null: false
    t.string "status", default: "pending", null: false
    t.integer "duration_seconds"
    t.text "error_message"
    t.datetime "started_at", precision: nil
    t.datetime "completed_at", precision: nil
    t.string "user_id", limit: 36, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_database_restores_on_created_at"
    t.index ["database_backup_id"], name: "index_database_restores_on_database_backup_id"
    t.index ["status"], name: "index_database_restores_on_status"
    t.index ["user_id"], name: "index_database_restores_on_user_id"
  end

  create_table "delegation_permissions", id: :string, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "account_delegation_id", null: false
    t.string "permission_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_delegation_id", "permission_id"], name: "idx_unique_delegation_permission", unique: true
    t.index ["account_delegation_id"], name: "index_delegation_permissions_on_account_delegation_id"
    t.index ["permission_id"], name: "index_delegation_permissions_on_permission_id"
  end

  create_table "email_deliveries", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "recipient_email", null: false
    t.string "subject", null: false
    t.string "email_type", limit: 50, null: false
    t.string "account_id", limit: 36
    t.string "user_id", limit: 36
    t.string "template", limit: 100
    t.text "template_data"
    t.string "status", limit: 30, default: "pending", null: false
    t.string "message_id", limit: 255
    t.datetime "sent_at", precision: nil
    t.datetime "failed_at", precision: nil
    t.text "error_message"
    t.integer "retry_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_email_deliveries_on_account_id"
    t.index ["created_at"], name: "index_email_deliveries_on_created_at"
    t.index ["email_type", "status"], name: "index_email_deliveries_on_email_type_and_status"
    t.index ["email_type"], name: "index_email_deliveries_on_email_type"
    t.index ["recipient_email"], name: "index_email_deliveries_on_recipient_email"
    t.index ["status", "created_at"], name: "index_email_deliveries_on_status_and_created_at"
    t.index ["status"], name: "index_email_deliveries_on_status"
    t.index ["user_id"], name: "index_email_deliveries_on_user_id"
  end

  create_table "gateway_configurations", id: :string, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "provider", null: false
    t.string "key_name", null: false
    t.text "encrypted_value", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "key_name"], name: "index_gateway_configurations_on_provider_and_key_name", unique: true
    t.index ["provider"], name: "index_gateway_configurations_on_provider"
  end

  create_table "gateway_connection_jobs", id: :string, force: :cascade do |t|
    t.string "gateway", null: false
    t.string "status", default: "pending", null: false
    t.json "config_data"
    t.json "result"
    t.datetime "completed_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_gateway_connection_jobs_on_created_at"
    t.index ["gateway"], name: "index_gateway_connection_jobs_on_gateway"
    t.index ["status"], name: "index_gateway_connection_jobs_on_status"
  end

  create_table "impersonation_sessions", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "impersonator_id", limit: 36, null: false
    t.string "impersonated_user_id", limit: 36, null: false
    t.string "account_id", limit: 36, null: false
    t.string "session_token", null: false
    t.string "reason", limit: 500
    t.datetime "started_at", precision: nil, null: false
    t.datetime "ended_at", precision: nil
    t.string "ip_address", limit: 45
    t.string "user_agent", limit: 500
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "active"], name: "index_impersonation_sessions_on_account_id_and_active"
    t.index ["impersonated_user_id", "active"], name: "idx_on_impersonated_user_id_active_e88ee0e6a0"
    t.index ["impersonator_id", "active"], name: "index_impersonation_sessions_on_impersonator_id_and_active"
    t.index ["session_token"], name: "index_impersonation_sessions_on_session_token", unique: true
    t.index ["started_at"], name: "index_impersonation_sessions_on_started_at"
    t.check_constraint "impersonator_id::text <> impersonated_user_id::text", name: "prevent_self_impersonation"
  end

  create_table "invitations", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "account_id", limit: 36, null: false
    t.string "inviter_id", limit: 36, null: false
    t.string "email", limit: 255, null: false
    t.string "first_name", limit: 50
    t.string "last_name", limit: 50
    t.string "token", limit: 255, null: false
    t.string "status", limit: 20, default: "pending", null: false
    t.datetime "expires_at", null: false
    t.datetime "accepted_at"
    t.datetime "revoked_at"
    t.text "message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "role_names", default: ["member"]
    t.index ["account_id"], name: "index_invitations_on_account_id"
    t.index ["email"], name: "index_invitations_on_email"
    t.index ["expires_at"], name: "index_invitations_on_expires_at"
    t.index ["inviter_id"], name: "index_invitations_on_inviter_id"
    t.index ["role_names"], name: "index_invitations_on_role_names", using: :gin
    t.index ["status"], name: "index_invitations_on_status"
    t.index ["token"], name: "index_invitations_on_token", unique: true
  end

  create_table "invoice_line_items", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "invoice_id", limit: 36, null: false
    t.string "description", limit: 500, null: false
    t.integer "quantity", default: 1, null: false
    t.bigint "unit_price_cents", default: 0, null: false
    t.bigint "total_cents", default: 0, null: false
    t.string "line_type", limit: 30, default: "subscription", null: false
    t.date "period_start"
    t.date "period_end"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "metadata", default: {}
    t.index ["invoice_id"], name: "index_invoice_line_items_on_invoice_id"
    t.index ["line_type"], name: "index_invoice_line_items_on_line_type"
    t.index ["period_end"], name: "index_invoice_line_items_on_period_end"
    t.index ["period_start"], name: "index_invoice_line_items_on_period_start"
  end

  create_table "invoices", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "subscription_id", limit: 36, null: false
    t.string "invoice_number", limit: 50, null: false
    t.bigint "subtotal_cents", default: 0, null: false
    t.bigint "tax_cents", default: 0, null: false
    t.bigint "total_cents", default: 0, null: false
    t.string "currency", limit: 3, default: "USD", null: false
    t.string "status", limit: 30, default: "draft", null: false
    t.decimal "tax_rate", precision: 5, scale: 4, default: "0.0", null: false
    t.datetime "due_date"
    t.datetime "paid_at"
    t.text "notes"
    t.string "stripe_invoice_id", limit: 100
    t.string "paypal_invoice_id", limit: 100
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "metadata", default: {}
    t.index ["due_date"], name: "index_invoices_on_due_date"
    t.index ["invoice_number"], name: "index_invoices_on_invoice_number", unique: true
    t.index ["paid_at"], name: "index_invoices_on_paid_at"
    t.index ["paypal_invoice_id"], name: "index_invoices_on_paypal_invoice_id", unique: true, where: "(paypal_invoice_id IS NOT NULL)"
    t.index ["status"], name: "index_invoices_on_status"
    t.index ["stripe_invoice_id"], name: "index_invoices_on_stripe_invoice_id", unique: true, where: "(stripe_invoice_id IS NOT NULL)"
    t.index ["subscription_id"], name: "index_invoices_on_subscription_id"
  end

  create_table "knowledge_base_article_tags", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "article_id", limit: 36, null: false
    t.string "tag_id", limit: 36, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["article_id", "tag_id"], name: "index_knowledge_base_article_tags_on_article_id_and_tag_id", unique: true
    t.index ["tag_id"], name: "index_knowledge_base_article_tags_on_tag_id"
  end

  create_table "knowledge_base_article_views", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "article_id", limit: 36, null: false
    t.string "user_id", limit: 36
    t.string "session_id"
    t.string "ip_address"
    t.string "user_agent"
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["article_id", "created_at"], name: "idx_on_article_id_created_at_45a5b082d8"
    t.index ["article_id"], name: "index_knowledge_base_article_views_on_article_id"
    t.index ["created_at"], name: "index_knowledge_base_article_views_on_created_at"
    t.index ["session_id"], name: "index_knowledge_base_article_views_on_session_id"
    t.index ["user_id"], name: "index_knowledge_base_article_views_on_user_id"
  end

  create_table "knowledge_base_articles", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "title", null: false
    t.string "slug", null: false
    t.text "content", null: false
    t.text "excerpt"
    t.string "category_id", limit: 36, null: false
    t.string "author_id", limit: 36, null: false
    t.string "status", default: "draft", null: false
    t.boolean "is_public", default: true
    t.boolean "is_featured", default: false
    t.integer "sort_order", default: 0
    t.integer "views_count", default: 0
    t.integer "likes_count", default: 0
    t.json "metadata", default: {}
    t.tsvector "search_vector"
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_knowledge_base_articles_on_author_id"
    t.index ["category_id", "sort_order"], name: "index_knowledge_base_articles_on_category_id_and_sort_order"
    t.index ["category_id"], name: "index_knowledge_base_articles_on_category_id"
    t.index ["is_featured"], name: "index_knowledge_base_articles_on_is_featured"
    t.index ["is_public"], name: "index_knowledge_base_articles_on_is_public"
    t.index ["published_at"], name: "index_knowledge_base_articles_on_published_at"
    t.index ["search_vector"], name: "index_knowledge_base_articles_on_search_vector", using: :gin
    t.index ["slug"], name: "index_knowledge_base_articles_on_slug", unique: true
    t.index ["status", "is_public", "published_at"], name: "idx_on_status_is_public_published_at_09e0b0fd64"
    t.index ["status"], name: "index_knowledge_base_articles_on_status"
  end

  create_table "knowledge_base_attachments", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "article_id", limit: 36, null: false
    t.string "filename", null: false
    t.string "content_type", null: false
    t.bigint "file_size", null: false
    t.string "storage_key", null: false
    t.text "description"
    t.integer "download_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["article_id"], name: "index_knowledge_base_attachments_on_article_id"
    t.index ["storage_key"], name: "index_knowledge_base_attachments_on_storage_key", unique: true
  end

  create_table "knowledge_base_categories", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.string "parent_id", limit: 36
    t.integer "sort_order", default: 0
    t.boolean "is_public", default: true
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["is_public"], name: "index_knowledge_base_categories_on_is_public"
    t.index ["parent_id", "sort_order"], name: "index_knowledge_base_categories_on_parent_id_and_sort_order"
    t.index ["parent_id"], name: "index_knowledge_base_categories_on_parent_id"
    t.index ["slug"], name: "index_knowledge_base_categories_on_slug", unique: true
  end

  create_table "knowledge_base_comments", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "article_id", limit: 36, null: false
    t.string "user_id", limit: 36, null: false
    t.text "content", null: false
    t.string "status", default: "pending", null: false
    t.string "parent_id", limit: 36
    t.integer "likes_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["article_id", "status", "created_at"], name: "idx_on_article_id_status_created_at_fae9a172b7"
    t.index ["article_id"], name: "index_knowledge_base_comments_on_article_id"
    t.index ["parent_id"], name: "index_knowledge_base_comments_on_parent_id"
    t.index ["status"], name: "index_knowledge_base_comments_on_status"
    t.index ["user_id"], name: "index_knowledge_base_comments_on_user_id"
  end

  create_table "knowledge_base_tags", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.string "color", default: "#3B82F6"
    t.integer "usage_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_knowledge_base_tags_on_name"
    t.index ["slug"], name: "index_knowledge_base_tags_on_slug", unique: true
  end

  create_table "knowledge_base_workflows", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "article_id", limit: 36, null: false
    t.string "user_id", limit: 36, null: false
    t.string "workflow_type", null: false
    t.string "status", default: "pending", null: false
    t.text "notes"
    t.datetime "due_date"
    t.json "workflow_data", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["article_id"], name: "index_knowledge_base_workflows_on_article_id"
    t.index ["due_date"], name: "index_knowledge_base_workflows_on_due_date"
    t.index ["status", "due_date"], name: "index_knowledge_base_workflows_on_status_and_due_date"
    t.index ["status"], name: "index_knowledge_base_workflows_on_status"
    t.index ["user_id"], name: "index_knowledge_base_workflows_on_user_id"
    t.index ["workflow_type"], name: "index_knowledge_base_workflows_on_workflow_type"
  end

  create_table "marketplace_categories", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "name", limit: 255, null: false
    t.string "slug", limit: 255, null: false
    t.text "description"
    t.string "icon", limit: 100
    t.integer "sort_order", default: 0
    t.boolean "is_active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["is_active"], name: "index_marketplace_categories_on_is_active"
    t.index ["slug"], name: "index_marketplace_categories_on_slug", unique: true
    t.index ["sort_order"], name: "index_marketplace_categories_on_sort_order"
  end

  create_table "marketplace_listings", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "app_id", limit: 36, null: false
    t.string "title", limit: 255, null: false
    t.string "short_description", limit: 500
    t.text "long_description"
    t.string "category", limit: 100
    t.jsonb "tags", default: []
    t.jsonb "screenshots", default: []
    t.string "documentation_url", limit: 500
    t.string "support_url", limit: 500
    t.string "homepage_url", limit: 500
    t.boolean "featured", default: false
    t.string "review_status", limit: 50, default: "pending"
    t.text "review_notes"
    t.datetime "published_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_id"], name: "index_marketplace_listings_on_app_id", unique: true
    t.index ["category"], name: "index_marketplace_listings_on_category"
    t.index ["featured"], name: "index_marketplace_listings_on_featured"
    t.index ["published_at"], name: "index_marketplace_listings_on_published_at"
    t.index ["review_status"], name: "index_marketplace_listings_on_review_status"
    t.check_constraint "review_status::text = ANY (ARRAY['pending'::character varying::text, 'approved'::character varying::text, 'rejected'::character varying::text])", name: "valid_review_status"
  end

  create_table "missing_payment_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "provider", null: false
    t.string "provider_payment_id", null: false
    t.integer "amount_cents", null: false
    t.string "currency", default: "USD", null: false
    t.string "status", default: "pending_creation", null: false
    t.string "associated_payment_id", limit: 36
    t.datetime "discovered_at"
    t.datetime "created_at_timestamp"
    t.datetime "ignored_at"
    t.json "investigation_notes"
    t.text "resolution_notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["associated_payment_id"], name: "index_missing_payment_logs_on_associated_payment_id"
    t.index ["discovered_at"], name: "index_missing_payment_logs_on_discovered_at"
    t.index ["provider", "provider_payment_id"], name: "index_missing_payment_logs_on_provider_and_provider_payment_id", unique: true
    t.index ["status"], name: "index_missing_payment_logs_on_status"
  end

  create_table "pages", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "title", limit: 200, null: false
    t.string "slug", limit: 150, null: false
    t.text "content", null: false
    t.string "meta_description", limit: 300
    t.text "meta_keywords"
    t.string "status", limit: 20, default: "draft", null: false
    t.string "author_id", limit: 36, null: false
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_pages_on_author_id"
    t.index ["created_at"], name: "index_pages_on_created_at"
    t.index ["published_at"], name: "index_pages_on_published_at"
    t.index ["slug"], name: "index_pages_on_slug", unique: true
    t.index ["status", "author_id"], name: "index_pages_on_status_and_author_id"
    t.index ["status", "published_at"], name: "index_pages_on_status_and_published_at", where: "((status)::text = 'published'::text)"
    t.index ["status"], name: "index_pages_on_status"
  end

  create_table "password_histories", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "user_id", limit: 36, null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.index ["created_at"], name: "index_password_histories_on_created_at"
    t.index ["user_id"], name: "index_password_histories_on_user_id"
  end

  create_table "payment_methods", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "account_id", limit: 36, null: false
    t.string "user_id", limit: 36, null: false
    t.string "provider", limit: 20, null: false
    t.string "external_id", limit: 100, null: false
    t.string "payment_type", limit: 30, null: false
    t.string "last_four", limit: 4
    t.string "brand", limit: 50
    t.integer "exp_month"
    t.integer "exp_year"
    t.string "holder_name", limit: 100
    t.boolean "is_default", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "metadata", default: {}
    t.index ["account_id"], name: "index_payment_methods_on_account_id"
    t.index ["external_id"], name: "index_payment_methods_on_external_id"
    t.index ["is_default"], name: "index_payment_methods_on_is_default"
    t.index ["payment_type"], name: "index_payment_methods_on_payment_type"
    t.index ["provider"], name: "index_payment_methods_on_provider"
    t.index ["user_id"], name: "index_payment_methods_on_user_id"
  end

  create_table "payments", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "invoice_id", limit: 36, null: false
    t.bigint "amount_cents", null: false
    t.string "currency", limit: 3, default: "USD", null: false
    t.string "payment_method", limit: 50, null: false
    t.string "status", limit: 30, default: "pending", null: false
    t.bigint "gateway_fee_cents", default: 0
    t.bigint "net_amount_cents"
    t.datetime "processed_at"
    t.datetime "failed_at"
    t.text "failure_reason"
    t.text "gateway_response"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "paypal_payment_id"
    t.string "paypal_transaction_id"
    t.string "paypal_payer_id"
    t.json "metadata", default: {}
    t.index ["failed_at"], name: "index_payments_on_failed_at"
    t.index ["invoice_id"], name: "index_payments_on_invoice_id"
    t.index ["payment_method"], name: "index_payments_on_payment_method"
    t.index ["paypal_payment_id"], name: "index_payments_on_paypal_payment_id"
    t.index ["paypal_transaction_id"], name: "index_payments_on_paypal_transaction_id"
    t.index ["processed_at"], name: "index_payments_on_processed_at"
    t.index ["status"], name: "index_payments_on_status"
  end

  create_table "permissions", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.string "category", limit: 20, null: false
    t.string "resource", limit: 50, null: false
    t.string "action", limit: 50, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_permissions_on_category"
    t.index ["name"], name: "index_permissions_on_name", unique: true
    t.index ["resource", "action"], name: "index_permissions_on_resource_and_action"
    t.check_constraint "category::text = ANY (ARRAY['resource'::character varying::text, 'admin'::character varying::text, 'system'::character varying::text])", name: "check_permission_category"
  end

  create_table "plans", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.string "description", limit: 500
    t.bigint "price_cents", default: 0, null: false
    t.string "currency", limit: 3, default: "USD", null: false
    t.string "billing_cycle", limit: 20, null: false
    t.string "status", limit: 20, default: "active", null: false
    t.integer "trial_days", default: 0, null: false
    t.boolean "is_public", default: true, null: false
    t.string "stripe_price_id", limit: 100
    t.string "paypal_plan_id", limit: 100
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "has_annual_discount", default: false, null: false
    t.decimal "annual_discount_percent", precision: 5, scale: 2, default: "0.0"
    t.boolean "has_volume_discount", default: false, null: false
    t.boolean "has_promotional_discount", default: false, null: false
    t.decimal "promotional_discount_percent", precision: 5, scale: 2, default: "0.0"
    t.datetime "promotional_discount_start"
    t.datetime "promotional_discount_end"
    t.string "promotional_discount_code", limit: 50
    t.json "features", default: {}
    t.json "limits", default: {}
    t.json "metadata", default: {}
    t.json "default_roles", default: []
    t.json "volume_discount_tiers", default: []
    t.text "required_roles", comment: "JSON array of role names that are required for users on this plan"
    t.index ["billing_cycle"], name: "index_plans_on_billing_cycle"
    t.index ["currency"], name: "index_plans_on_currency"
    t.index ["has_annual_discount"], name: "index_plans_on_has_annual_discount"
    t.index ["has_promotional_discount"], name: "index_plans_on_has_promotional_discount"
    t.index ["has_volume_discount"], name: "index_plans_on_has_volume_discount"
    t.index ["is_public"], name: "index_plans_on_is_public"
    t.index ["paypal_plan_id"], name: "index_plans_on_paypal_plan_id", unique: true, where: "(paypal_plan_id IS NOT NULL)"
    t.index ["promotional_discount_code"], name: "index_plans_on_promotional_discount_code", unique: true, where: "(promotional_discount_code IS NOT NULL)"
    t.index ["promotional_discount_start", "promotional_discount_end"], name: "idx_on_promotional_discount_start_promotional_disco_717c03b924"
    t.index ["status"], name: "index_plans_on_status"
    t.index ["stripe_price_id"], name: "index_plans_on_stripe_price_id", unique: true, where: "(stripe_price_id IS NOT NULL)"
  end

  create_table "reconciliation_flags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "flag_type", null: false
    t.string "provider", null: false
    t.string "local_payment_id", limit: 36
    t.string "external_id"
    t.string "status", default: "pending", null: false
    t.boolean "requires_manual_review", default: false
    t.json "metadata"
    t.text "notes"
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_reconciliation_flags_on_external_id"
    t.index ["flag_type"], name: "index_reconciliation_flags_on_flag_type"
    t.index ["local_payment_id"], name: "index_reconciliation_flags_on_local_payment_id"
    t.index ["provider"], name: "index_reconciliation_flags_on_provider"
    t.index ["requires_manual_review"], name: "index_reconciliation_flags_on_requires_manual_review"
    t.index ["status"], name: "index_reconciliation_flags_on_status"
  end

  create_table "reconciliation_investigations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "investigation_type", null: false
    t.string "local_payment_id", limit: 36
    t.string "provider_payment_id"
    t.integer "local_amount", null: false
    t.integer "provider_amount", null: false
    t.integer "amount_difference", null: false
    t.string "status", default: "pending", null: false
    t.boolean "requires_investigation", default: false
    t.json "findings"
    t.json "corrective_actions"
    t.string "resolution_type"
    t.integer "amount_corrected"
    t.datetime "investigation_started_at"
    t.datetime "resolved_at"
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["amount_difference"], name: "index_reconciliation_investigations_on_amount_difference"
    t.index ["investigation_type"], name: "index_reconciliation_investigations_on_investigation_type"
    t.index ["local_payment_id"], name: "index_reconciliation_investigations_on_local_payment_id"
    t.index ["provider_payment_id"], name: "index_reconciliation_investigations_on_provider_payment_id"
    t.index ["requires_investigation"], name: "index_reconciliation_investigations_on_requires_investigation"
    t.index ["status"], name: "index_reconciliation_investigations_on_status"
  end

  create_table "reconciliation_reports", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.date "reconciliation_date", null: false
    t.string "reconciliation_type", null: false
    t.datetime "date_range_start", null: false
    t.datetime "date_range_end", null: false
    t.integer "discrepancies_count", default: 0, null: false
    t.integer "high_severity_count", default: 0, null: false
    t.integer "medium_severity_count", default: 0, null: false
    t.json "summary"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["date_range_start", "date_range_end"], name: "idx_on_date_range_start_date_range_end_c2c7b5c20c"
    t.index ["discrepancies_count"], name: "index_reconciliation_reports_on_discrepancies_count"
    t.index ["reconciliation_date"], name: "index_reconciliation_reports_on_reconciliation_date"
    t.index ["reconciliation_type"], name: "index_reconciliation_reports_on_reconciliation_type"
  end

  create_table "report_requests", id: :string, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "account_id", null: false
    t.string "user_id", null: false
    t.string "name", null: false
    t.string "report_type", null: false
    t.string "format", null: false
    t.string "status", default: "pending", null: false
    t.jsonb "parameters"
    t.string "file_url"
    t.string "file_path"
    t.integer "file_size"
    t.string "content_type"
    t.text "error_message"
    t.datetime "completed_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_report_requests_on_account_id_and_status"
    t.index ["account_id"], name: "index_report_requests_on_account_id"
    t.index ["created_at"], name: "index_report_requests_on_created_at"
    t.index ["report_type"], name: "index_report_requests_on_report_type"
    t.index ["status"], name: "index_report_requests_on_status"
    t.index ["user_id"], name: "index_report_requests_on_user_id"
  end

  create_table "revenue_snapshots", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "account_id", limit: 36
    t.date "snapshot_date", null: false
    t.bigint "mrr_cents", default: 0, null: false
    t.bigint "arr_cents", default: 0, null: false
    t.integer "active_subscriptions", default: 0, null: false
    t.integer "new_subscriptions", default: 0, null: false
    t.integer "churned_subscriptions", default: 0, null: false
    t.integer "upgraded_subscriptions", default: 0, null: false
    t.integer "downgraded_subscriptions", default: 0, null: false
    t.string "currency", limit: 3, default: "USD", null: false
    t.datetime "created_at", null: false
    t.json "metadata", default: {}
    t.index ["account_id", "snapshot_date"], name: "index_revenue_snapshots_on_account_id_and_snapshot_date", unique: true, where: "(account_id IS NOT NULL)"
    t.index ["account_id"], name: "index_revenue_snapshots_on_account_id"
    t.index ["currency"], name: "index_revenue_snapshots_on_currency"
    t.index ["snapshot_date"], name: "index_revenue_snapshots_on_global_snapshot_date", unique: true, where: "(account_id IS NULL)"
    t.index ["snapshot_date"], name: "index_revenue_snapshots_on_snapshot_date"
  end

  create_table "role_permissions", id: false, force: :cascade do |t|
    t.string "role_id", limit: 36, null: false
    t.string "permission_id", limit: 36, null: false
    t.datetime "created_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["permission_id"], name: "index_role_permissions_on_permission_id"
    t.index ["role_id", "permission_id"], name: "index_role_permissions_on_role_id_and_permission_id", unique: true
  end

  create_table "roles", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "name", limit: 50, null: false
    t.string "display_name", limit: 100, null: false
    t.text "description"
    t.string "role_type", limit: 20, null: false
    t.boolean "is_system", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "immutable", default: false, null: false
    t.index ["is_system"], name: "index_roles_on_is_system"
    t.index ["name"], name: "index_roles_on_name", unique: true
    t.index ["role_type"], name: "index_roles_on_role_type"
    t.check_constraint "role_type::text = ANY (ARRAY['user'::character varying::text, 'admin'::character varying::text, 'system'::character varying::text])", name: "check_role_type"
  end

  create_table "scheduled_reports", id: :string, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "report_type", null: false
    t.string "frequency", null: false
    t.text "recipients"
    t.string "format", default: "pdf"
    t.string "account_id"
    t.string "user_id", null: false
    t.datetime "next_run_at"
    t.datetime "last_run_at"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "active"], name: "index_scheduled_reports_on_account_id_and_active"
    t.index ["account_id"], name: "index_scheduled_reports_on_account_id"
    t.index ["next_run_at", "active"], name: "index_scheduled_reports_on_next_run_at_and_active"
    t.index ["user_id"], name: "index_scheduled_reports_on_user_id"
  end

  create_table "scheduled_tasks", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "name", null: false
    t.string "description"
    t.string "task_type", null: false
    t.string "cron_schedule", null: false
    t.boolean "enabled", default: true
    t.text "command"
    t.json "parameters"
    t.string "user_id", limit: 36, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["enabled"], name: "index_scheduled_tasks_on_enabled"
    t.index ["name"], name: "index_scheduled_tasks_on_name", unique: true
    t.index ["task_type"], name: "index_scheduled_tasks_on_task_type"
    t.index ["user_id"], name: "index_scheduled_tasks_on_user_id"
  end

  create_table "site_settings", id: :string, force: :cascade do |t|
    t.string "key", null: false
    t.text "value"
    t.text "description"
    t.string "setting_type", null: false
    t.boolean "is_public", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["is_public"], name: "index_site_settings_on_is_public"
    t.index ["key"], name: "index_site_settings_on_key", unique: true
    t.index ["setting_type"], name: "index_site_settings_on_setting_type"
  end

  create_table "subscriptions", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "account_id", limit: 36, null: false
    t.string "plan_id", limit: 36, null: false
    t.integer "quantity", default: 1, null: false
    t.string "status", limit: 30, default: "trialing", null: false
    t.datetime "current_period_start"
    t.datetime "current_period_end"
    t.datetime "trial_start"
    t.datetime "trial_end"
    t.datetime "canceled_at"
    t.datetime "ended_at"
    t.string "stripe_subscription_id", limit: 100
    t.string "paypal_subscription_id", limit: 100
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "paypal_agreement_id"
    t.string "paypal_plan_id"
    t.json "metadata", default: {}
    t.index ["account_id"], name: "index_subscriptions_on_account_id", unique: true
    t.index ["current_period_end"], name: "index_subscriptions_on_current_period_end"
    t.index ["paypal_agreement_id"], name: "index_subscriptions_on_paypal_agreement_id"
    t.index ["paypal_plan_id"], name: "index_subscriptions_on_paypal_plan_id"
    t.index ["paypal_subscription_id"], name: "index_subscriptions_on_paypal_subscription_id", unique: true, where: "(paypal_subscription_id IS NOT NULL)"
    t.index ["plan_id"], name: "index_subscriptions_on_plan_id"
    t.index ["status"], name: "index_subscriptions_on_status"
    t.index ["stripe_subscription_id"], name: "index_subscriptions_on_stripe_subscription_id", unique: true, where: "(stripe_subscription_id IS NOT NULL)"
    t.index ["trial_end"], name: "index_subscriptions_on_trial_end"
  end

  create_table "system_health_checks", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "check_type", null: false
    t.string "overall_status", null: false
    t.json "health_data", null: false
    t.integer "response_time_ms"
    t.datetime "checked_at", precision: nil, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["check_type"], name: "index_system_health_checks_on_check_type"
    t.index ["checked_at"], name: "index_system_health_checks_on_checked_at"
    t.index ["overall_status"], name: "index_system_health_checks_on_overall_status"
  end

  create_table "system_operations", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "operation_type", null: false
    t.string "status", null: false
    t.json "parameters"
    t.json "result"
    t.text "error_message"
    t.datetime "started_at", precision: nil
    t.datetime "completed_at", precision: nil
    t.string "user_id", limit: 36, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["operation_type"], name: "index_system_operations_on_operation_type"
    t.index ["started_at"], name: "index_system_operations_on_started_at"
    t.index ["status"], name: "index_system_operations_on_status"
    t.index ["user_id"], name: "index_system_operations_on_user_id"
  end

  create_table "task_executions", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "scheduled_task_id", limit: 36, null: false
    t.string "status", default: "pending", null: false
    t.string "triggered_by", default: "scheduled", null: false
    t.text "output"
    t.text "error_message"
    t.datetime "started_at", precision: nil
    t.datetime "completed_at", precision: nil
    t.string "user_id", limit: 36
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_task_executions_on_created_at"
    t.index ["scheduled_task_id"], name: "index_task_executions_on_scheduled_task_id"
    t.index ["status"], name: "index_task_executions_on_status"
    t.index ["triggered_by"], name: "index_task_executions_on_triggered_by"
    t.index ["user_id"], name: "index_task_executions_on_user_id"
  end

  create_table "user_roles", id: false, force: :cascade do |t|
    t.string "user_id", limit: 36, null: false
    t.string "role_id", limit: 36, null: false
    t.string "granted_by", limit: 36
    t.datetime "granted_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["granted_by"], name: "index_user_roles_on_granted_by"
    t.index ["role_id"], name: "index_user_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_user_roles_on_user_id_and_role_id", unique: true
    t.index ["user_id"], name: "index_user_roles_on_user_id"
  end

  create_table "users", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "account_id", limit: 36, null: false
    t.string "email", limit: 255, null: false
    t.string "password_digest", null: false
    t.string "first_name", limit: 50, null: false
    t.string "last_name", limit: 50, null: false
    t.string "status", limit: 20, default: "active", null: false
    t.boolean "email_verified", default: false, null: false
    t.datetime "email_verified_at"
    t.string "email_verification_token", limit: 255
    t.datetime "email_verification_token_expires_at"
    t.integer "failed_login_attempts", default: 0, null: false
    t.datetime "locked_until"
    t.datetime "password_changed_at"
    t.datetime "last_login_at"
    t.string "last_login_ip", limit: 45
    t.string "reset_token_digest"
    t.datetime "reset_token_expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "preferences"
    t.text "notification_preferences"
    t.boolean "two_factor_enabled", default: false, null: false
    t.string "two_factor_secret"
    t.text "backup_codes"
    t.datetime "two_factor_backup_codes_generated_at"
    t.datetime "two_factor_enabled_at"
    t.datetime "email_verification_sent_at"
    t.index ["account_id"], name: "index_users_on_account_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["email_verification_token"], name: "index_users_on_email_verification_token", unique: true, where: "(email_verification_token IS NOT NULL)"
    t.index ["reset_token_digest"], name: "index_users_on_reset_token_digest", unique: true, where: "(reset_token_digest IS NOT NULL)"
    t.index ["status"], name: "index_users_on_status"
    t.index ["two_factor_enabled"], name: "index_users_on_two_factor_enabled"
  end

  create_table "webhook_deliveries", id: :string, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "webhook_endpoint_id", null: false
    t.string "event_type", limit: 100, null: false
    t.string "status", limit: 30, default: "pending", null: false
    t.json "payload"
    t.integer "http_status"
    t.integer "response_time_ms"
    t.text "response_body"
    t.json "response_headers"
    t.integer "attempt_count", default: 0, null: false
    t.datetime "next_retry_at", precision: nil
    t.datetime "completed_at", precision: nil
    t.text "error_message"
    t.json "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["completed_at"], name: "index_webhook_deliveries_on_completed_at"
    t.index ["created_at"], name: "index_webhook_deliveries_on_created_at"
    t.index ["event_type"], name: "index_webhook_deliveries_on_event_type"
    t.index ["next_retry_at"], name: "index_webhook_deliveries_on_next_retry_at"
    t.index ["status", "next_retry_at"], name: "index_webhook_deliveries_on_status_and_next_retry_at"
    t.index ["status"], name: "index_webhook_deliveries_on_status"
    t.index ["webhook_endpoint_id"], name: "index_webhook_deliveries_on_webhook_endpoint_id"
  end

  create_table "webhook_endpoints", id: :string, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "url", limit: 2000, null: false
    t.string "description", limit: 500
    t.string "status", limit: 20, default: "active", null: false
    t.text "secret_token"
    t.string "content_type", limit: 100, default: "application/json", null: false
    t.integer "timeout_seconds", default: 30, null: false
    t.integer "retry_limit", default: 3, null: false
    t.string "retry_backoff", limit: 20, default: "exponential", null: false
    t.json "event_types"
    t.integer "success_count", default: 0, null: false
    t.integer "failure_count", default: 0, null: false
    t.datetime "last_delivery_at", precision: nil
    t.json "metadata"
    t.string "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_webhook_endpoints_on_created_by_id"
    t.index ["last_delivery_at"], name: "index_webhook_endpoints_on_last_delivery_at"
    t.index ["status"], name: "index_webhook_endpoints_on_status"
    t.index ["url"], name: "index_webhook_endpoints_on_url"
  end

  create_table "webhook_events", id: { type: :string, limit: 36, default: -> { "gen_random_uuid()" } }, force: :cascade do |t|
    t.string "account_id", limit: 36
    t.string "provider", limit: 20, null: false
    t.string "event_type", limit: 100, null: false
    t.string "external_id", limit: 100, null: false
    t.text "payload", null: false
    t.string "status", limit: 20, default: "pending", null: false
    t.datetime "processed_at"
    t.text "error_message"
    t.integer "retry_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["account_id"], name: "index_webhook_events_on_account_id"
    t.index ["created_at"], name: "index_webhook_events_on_created_at"
    t.index ["event_type"], name: "index_webhook_events_on_event_type"
    t.index ["external_id"], name: "index_webhook_events_on_external_id"
    t.index ["provider", "external_id"], name: "index_webhook_events_on_provider_and_external_id", unique: true
    t.index ["provider"], name: "index_webhook_events_on_provider"
    t.index ["status"], name: "index_webhook_events_on_status"
  end

  create_table "worker_activities", id: :string, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "worker_id", null: false
    t.string "action", limit: 100
    t.json "details"
    t.datetime "performed_at"
    t.string "ip_address"
    t.text "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_worker_activities_on_action"
    t.index ["performed_at"], name: "index_worker_activities_on_performed_at"
    t.index ["worker_id", "performed_at"], name: "index_worker_activities_on_worker_id_and_performed_at"
    t.index ["worker_id"], name: "index_worker_activities_on_worker_id"
  end

  create_table "worker_roles", id: false, force: :cascade do |t|
    t.string "worker_id", limit: 36, null: false
    t.string "role_id", limit: 36, null: false
    t.datetime "granted_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["role_id"], name: "index_worker_roles_on_role_id"
    t.index ["worker_id", "role_id"], name: "index_worker_roles_on_worker_id_and_role_id", unique: true
    t.index ["worker_id"], name: "index_worker_roles_on_worker_id"
  end

  create_table "workers", id: :string, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.string "token", null: false
    t.string "status", default: "active", null: false
    t.string "account_id"
    t.datetime "last_seen_at"
    t.integer "request_count", default: 0
    t.datetime "token_regenerated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "permissions", default: []
    t.index ["account_id"], name: "index_workers_on_account_id"
    t.index ["last_seen_at"], name: "index_workers_on_last_seen_at"
    t.index ["permissions"], name: "index_workers_on_permissions", using: :gin
    t.index ["status"], name: "index_workers_on_status"
    t.index ["token"], name: "index_workers_on_token", unique: true
  end

  add_foreign_key "account_delegations", "accounts"
  add_foreign_key "account_delegations", "users", column: "delegated_by_id"
  add_foreign_key "account_delegations", "users", column: "delegated_user_id"
  add_foreign_key "api_key_usages", "api_keys"
  add_foreign_key "api_keys", "accounts"
  add_foreign_key "api_keys", "users", column: "created_by_id"
  add_foreign_key "app_analytics", "apps", on_delete: :cascade
  add_foreign_key "app_endpoint_calls", "accounts"
  add_foreign_key "app_endpoint_calls", "app_endpoints", on_delete: :cascade
  add_foreign_key "app_endpoints", "apps", on_delete: :cascade
  add_foreign_key "app_features", "apps", on_delete: :cascade
  add_foreign_key "app_plans", "apps", on_delete: :cascade
  add_foreign_key "app_reviews", "accounts"
  add_foreign_key "app_reviews", "apps", on_delete: :cascade
  add_foreign_key "app_subscriptions", "accounts"
  add_foreign_key "app_subscriptions", "app_plans"
  add_foreign_key "app_subscriptions", "apps"
  add_foreign_key "app_webhook_deliveries", "app_webhooks", on_delete: :cascade
  add_foreign_key "app_webhooks", "apps", on_delete: :cascade
  add_foreign_key "apps", "accounts"
  add_foreign_key "audit_logs", "accounts"
  add_foreign_key "audit_logs", "users", on_delete: :nullify
  add_foreign_key "blacklisted_tokens", "users"
  add_foreign_key "database_backups", "users"
  add_foreign_key "database_restores", "database_backups"
  add_foreign_key "database_restores", "users"
  add_foreign_key "delegation_permissions", "account_delegations"
  add_foreign_key "email_deliveries", "accounts"
  add_foreign_key "email_deliveries", "users"
  add_foreign_key "impersonation_sessions", "accounts"
  add_foreign_key "impersonation_sessions", "users", column: "impersonated_user_id"
  add_foreign_key "impersonation_sessions", "users", column: "impersonator_id"
  add_foreign_key "invitations", "accounts"
  add_foreign_key "invitations", "users", column: "inviter_id"
  add_foreign_key "invoice_line_items", "invoices"
  add_foreign_key "invoices", "subscriptions"
  add_foreign_key "knowledge_base_article_tags", "knowledge_base_articles", column: "article_id", on_delete: :cascade
  add_foreign_key "knowledge_base_article_tags", "knowledge_base_tags", column: "tag_id", on_delete: :cascade
  add_foreign_key "knowledge_base_article_views", "knowledge_base_articles", column: "article_id", on_delete: :cascade
  add_foreign_key "knowledge_base_article_views", "users", on_delete: :cascade
  add_foreign_key "knowledge_base_articles", "knowledge_base_categories", column: "category_id", on_delete: :cascade
  add_foreign_key "knowledge_base_articles", "users", column: "author_id", on_delete: :cascade
  add_foreign_key "knowledge_base_attachments", "knowledge_base_articles", column: "article_id", on_delete: :cascade
  add_foreign_key "knowledge_base_categories", "knowledge_base_categories", column: "parent_id", on_delete: :cascade
  add_foreign_key "knowledge_base_comments", "knowledge_base_articles", column: "article_id", on_delete: :cascade
  add_foreign_key "knowledge_base_comments", "knowledge_base_comments", column: "parent_id", on_delete: :cascade
  add_foreign_key "knowledge_base_comments", "users", on_delete: :cascade
  add_foreign_key "knowledge_base_workflows", "knowledge_base_articles", column: "article_id", on_delete: :cascade
  add_foreign_key "knowledge_base_workflows", "users", on_delete: :cascade
  add_foreign_key "marketplace_listings", "apps", on_delete: :cascade
  add_foreign_key "missing_payment_logs", "payments", column: "associated_payment_id"
  add_foreign_key "pages", "users", column: "author_id"
  add_foreign_key "password_histories", "users"
  add_foreign_key "payment_methods", "accounts"
  add_foreign_key "payment_methods", "users"
  add_foreign_key "payments", "invoices"
  add_foreign_key "reconciliation_flags", "payments", column: "local_payment_id"
  add_foreign_key "reconciliation_investigations", "payments", column: "local_payment_id"
  add_foreign_key "report_requests", "accounts"
  add_foreign_key "report_requests", "users"
  add_foreign_key "revenue_snapshots", "accounts", on_delete: :cascade
  add_foreign_key "role_permissions", "permissions"
  add_foreign_key "role_permissions", "roles"
  add_foreign_key "scheduled_reports", "accounts"
  add_foreign_key "scheduled_reports", "users"
  add_foreign_key "scheduled_tasks", "users"
  add_foreign_key "subscriptions", "accounts"
  add_foreign_key "subscriptions", "plans"
  add_foreign_key "system_operations", "users"
  add_foreign_key "task_executions", "scheduled_tasks"
  add_foreign_key "task_executions", "users"
  add_foreign_key "user_roles", "roles"
  add_foreign_key "user_roles", "users"
  add_foreign_key "user_roles", "users", column: "granted_by"
  add_foreign_key "users", "accounts"
  add_foreign_key "webhook_deliveries", "webhook_endpoints"
  add_foreign_key "webhook_endpoints", "users", column: "created_by_id"
  add_foreign_key "webhook_events", "accounts", on_delete: :nullify
  add_foreign_key "worker_activities", "workers"
  add_foreign_key "worker_roles", "roles"
  add_foreign_key "worker_roles", "workers"
  add_foreign_key "workers", "accounts"
end
