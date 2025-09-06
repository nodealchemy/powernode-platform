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

ActiveRecord::Schema[8.0].define(version: 2025_09_06_054625) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "account_delegations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "delegated_user_id", null: false
    t.uuid "delegated_by_id", null: false
    t.uuid "role_id"
    t.string "status", default: "active"
    t.datetime "expires_at"
    t.datetime "revoked_at"
    t.uuid "revoked_by_id"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "delegated_user_id"], name: "index_account_delegations_unique", unique: true
    t.index ["account_id"], name: "index_account_delegations_on_account_id"
    t.index ["delegated_by_id"], name: "index_account_delegations_on_delegated_by"
    t.index ["delegated_by_id"], name: "index_account_delegations_on_delegated_by_id"
    t.index ["delegated_user_id"], name: "index_account_delegations_on_delegated_user"
    t.index ["delegated_user_id"], name: "index_account_delegations_on_delegated_user_id"
    t.index ["expires_at"], name: "index_account_delegations_on_expires_at"
    t.index ["revoked_by_id"], name: "index_account_delegations_on_revoked_by_id"
    t.index ["role_id"], name: "index_account_delegations_on_role"
    t.index ["role_id"], name: "index_account_delegations_on_role_id"
    t.index ["status"], name: "index_account_delegations_on_status"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'expired'::character varying::text])", name: "valid_delegation_status"
  end

  create_table "accounts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.string "subdomain", limit: 30
    t.string "status", limit: 20, default: "active", null: false
    t.string "stripe_customer_id", limit: 50
    t.string "paypal_customer_id", limit: 50
    t.string "billing_email"
    t.string "tax_id"
    t.jsonb "settings", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["paypal_customer_id"], name: "index_accounts_on_paypal_customer_id", unique: true, where: "(paypal_customer_id IS NOT NULL)"
    t.index ["status"], name: "index_accounts_on_status"
    t.index ["stripe_customer_id"], name: "index_accounts_on_stripe_customer_id", unique: true, where: "(stripe_customer_id IS NOT NULL)"
    t.index ["subdomain"], name: "index_accounts_on_subdomain", unique: true, where: "((subdomain IS NOT NULL) AND ((subdomain)::text <> ''::text))"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'cancelled'::character varying::text, 'suspended'::character varying::text])", name: "valid_account_status"
  end

  create_table "admin_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "key", limit: 255, null: false
    t.text "value"
    t.string "setting_type", limit: 50, default: "string"
    t.text "description"
    t.boolean "is_public", default: false
    t.boolean "is_encrypted", default: false
    t.string "category", limit: 100
    t.integer "sort_order", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "idx_admin_settings_on_category"
    t.index ["is_public"], name: "idx_admin_settings_on_is_public"
    t.index ["key"], name: "idx_admin_settings_on_key_unique", unique: true
    t.index ["setting_type"], name: "idx_admin_settings_on_setting_type"
    t.index ["sort_order"], name: "idx_admin_settings_on_sort_order"
    t.check_constraint "setting_type::text = ANY (ARRAY['string'::character varying::text, 'text'::character varying::text, 'integer'::character varying::text, 'boolean'::character varying::text, 'json'::character varying::text, 'array'::character varying::text])", name: "valid_admin_setting_type"
  end

  create_table "api_key_usages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "api_key_id", null: false
    t.string "endpoint", limit: 500, null: false
    t.string "method", limit: 10, null: false
    t.integer "response_status", null: false
    t.integer "response_time_ms"
    t.string "ip_address", limit: 45
    t.string "user_agent", limit: 1000
    t.jsonb "request_params", default: {}
    t.datetime "used_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["api_key_id", "used_at"], name: "idx_api_key_usages_on_api_key_used_at"
    t.index ["api_key_id"], name: "index_api_key_usages_on_api_key_id"
    t.index ["endpoint"], name: "idx_api_key_usages_on_endpoint"
    t.index ["response_status"], name: "idx_api_key_usages_on_response_status"
    t.index ["used_at"], name: "idx_api_key_usages_on_used_at"
  end

  create_table "api_keys", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "created_by_id"
    t.string "name", limit: 255, null: false
    t.string "key_digest", null: false
    t.string "prefix", limit: 20, null: false
    t.jsonb "permissions", default: []
    t.jsonb "rate_limits", default: {}
    t.boolean "is_active", default: true
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.string "last_used_ip", limit: 45
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "key_prefix", limit: 20
    t.string "key_suffix", limit: 20
    t.jsonb "scopes", default: []
    t.jsonb "allowed_ips", default: []
    t.integer "usage_count", default: 0
    t.integer "rate_limit_per_hour"
    t.integer "rate_limit_per_day"
    t.jsonb "metadata", default: {}
    t.index ["account_id"], name: "idx_api_keys_on_account_id"
    t.index ["account_id"], name: "index_api_keys_on_account_id"
    t.index ["allowed_ips"], name: "index_api_keys_on_allowed_ips", using: :gin
    t.index ["created_by_id"], name: "index_api_keys_on_created_by_id"
    t.index ["expires_at"], name: "idx_api_keys_on_expires_at"
    t.index ["is_active"], name: "idx_api_keys_on_is_active"
    t.index ["key_digest"], name: "idx_api_keys_on_key_digest_unique", unique: true
    t.index ["key_prefix"], name: "index_api_keys_on_key_prefix"
    t.index ["key_suffix"], name: "index_api_keys_on_key_suffix"
    t.index ["permissions"], name: "idx_api_keys_on_permissions", using: :gin
    t.index ["prefix"], name: "idx_api_keys_on_prefix_unique", unique: true
    t.index ["scopes"], name: "index_api_keys_on_scopes", using: :gin
    t.index ["usage_count"], name: "index_api_keys_on_usage_count"
    t.check_constraint "rate_limit_per_day IS NULL OR rate_limit_per_day > 0", name: "valid_api_key_daily_limit_v2"
    t.check_constraint "rate_limit_per_hour IS NULL OR rate_limit_per_hour > 0", name: "valid_api_key_hourly_limit_v2"
    t.check_constraint "usage_count >= 0", name: "valid_api_key_usage_count_v2"
  end

  create_table "app_analytics", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "app_id", null: false
    t.string "metric_name", limit: 100, null: false
    t.decimal "metric_value", precision: 15, scale: 2
    t.datetime "recorded_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }
    t.jsonb "dimensions", default: {}
    t.jsonb "metadata", default: {}
    t.index ["app_id", "metric_name", "recorded_at"], name: "idx_app_analytics_on_app_metric_recorded_at"
    t.index ["app_id"], name: "index_app_analytics_on_app_id"
    t.index ["metric_name"], name: "idx_app_analytics_on_metric_name"
    t.index ["recorded_at"], name: "idx_app_analytics_on_recorded_at"
  end

  create_table "app_endpoint_calls", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "app_endpoint_id", null: false
    t.uuid "account_id"
    t.string "request_id", limit: 100
    t.integer "status_code"
    t.integer "response_time_ms"
    t.bigint "request_size_bytes"
    t.bigint "response_size_bytes"
    t.text "error_message"
    t.datetime "called_at", null: false
    t.string "ip_address", limit: 45
    t.string "user_agent", limit: 500
    t.jsonb "request_headers", default: {}
    t.jsonb "response_headers", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "idx_app_endpoint_calls_on_account_id"
    t.index ["account_id"], name: "index_app_endpoint_calls_on_account_id"
    t.index ["app_endpoint_id"], name: "idx_app_endpoint_calls_on_app_endpoint_id"
    t.index ["app_endpoint_id"], name: "index_app_endpoint_calls_on_app_endpoint_id"
    t.index ["called_at"], name: "idx_app_endpoint_calls_on_called_at"
    t.index ["status_code"], name: "idx_app_endpoint_calls_on_status_code"
    t.check_constraint "response_time_ms >= 0", name: "valid_endpoint_response_time"
    t.check_constraint "status_code >= 100 AND status_code <= 599", name: "valid_endpoint_status_code"
  end

  create_table "app_endpoints", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "app_id", null: false
    t.string "name", limit: 255, null: false
    t.string "slug", limit: 255, null: false
    t.text "description"
    t.string "http_method", limit: 10, null: false
    t.string "path", limit: 500, null: false
    t.boolean "is_public", default: false
    t.boolean "is_active", default: true
    t.string "version", limit: 20, default: "v1"
    t.jsonb "parameters", default: {}
    t.jsonb "response_schema", default: {}
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_id", "http_method", "path"], name: "index_app_endpoints_unique", unique: true
    t.index ["app_id", "slug"], name: "idx_app_endpoints_on_app_slug_unique", unique: true
    t.index ["app_id"], name: "idx_app_endpoints_on_app_id"
    t.index ["app_id"], name: "index_app_endpoints_on_app_id"
    t.index ["http_method"], name: "idx_app_endpoints_on_http_method"
    t.index ["is_active"], name: "idx_app_endpoints_on_is_active"
    t.index ["is_public"], name: "idx_app_endpoints_on_is_public"
    t.index ["version"], name: "idx_app_endpoints_on_version"
    t.check_constraint "http_method::text = ANY (ARRAY['GET'::character varying::text, 'POST'::character varying::text, 'PUT'::character varying::text, 'PATCH'::character varying::text, 'DELETE'::character varying::text, 'HEAD'::character varying::text, 'OPTIONS'::character varying::text])", name: "valid_endpoint_http_method"
  end

  create_table "app_features", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "app_id", null: false
    t.string "name", limit: 255, null: false
    t.string "slug", limit: 255, null: false
    t.text "description"
    t.string "feature_type", limit: 50
    t.boolean "default_enabled", default: false
    t.jsonb "configuration", default: {}
    t.jsonb "dependencies", default: []
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_id", "slug"], name: "idx_app_features_on_app_slug_unique", unique: true
    t.index ["app_id"], name: "index_app_features_on_app_id"
    t.index ["feature_type"], name: "idx_app_features_on_feature_type"
  end

  create_table "app_plans", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "app_id", null: false
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
    t.index ["app_id", "slug"], name: "idx_app_plans_on_app_slug_unique", unique: true
    t.index ["app_id"], name: "index_app_plans_on_app_id"
    t.index ["is_active"], name: "idx_app_plans_on_is_active"
    t.index ["is_public"], name: "idx_app_plans_on_is_public"
    t.check_constraint "billing_interval::text = ANY (ARRAY['monthly'::character varying::text, 'yearly'::character varying::text, 'one_time'::character varying::text])", name: "valid_app_billing_interval"
    t.check_constraint "price_cents >= 0", name: "valid_app_plan_price"
  end

  create_table "app_reviews", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "app_id", null: false
    t.uuid "account_id", null: false
    t.integer "rating", null: false
    t.string "title", limit: 255
    t.text "content"
    t.integer "helpful_count", default: 0
    t.string "version_reviewed", limit: 50
    t.string "platform", limit: 50
    t.string "reviewer_name", limit: 100
    t.boolean "is_verified", default: false
    t.string "status", limit: 50, default: "published"
    t.text "moderation_notes"
    t.datetime "reviewed_at"
    t.datetime "published_at"
    t.integer "usability_rating"
    t.integer "features_rating"
    t.integer "support_rating"
    t.integer "value_rating"
    t.decimal "quality_score", precision: 5, scale: 2
    t.text "sentiment_analysis"
    t.jsonb "tags", default: []
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_app_reviews_on_account_id"
    t.index ["app_id", "account_id"], name: "idx_app_reviews_on_app_account_unique", unique: true
    t.index ["app_id"], name: "index_app_reviews_on_app_id"
    t.index ["created_at"], name: "idx_app_reviews_on_created_at"
    t.index ["helpful_count"], name: "idx_app_reviews_on_helpful_count"
    t.index ["is_verified"], name: "idx_app_reviews_on_is_verified"
    t.index ["published_at"], name: "idx_app_reviews_on_published_at"
    t.index ["quality_score"], name: "idx_app_reviews_on_quality_score"
    t.index ["rating"], name: "idx_app_reviews_on_rating"
    t.index ["status"], name: "idx_app_reviews_on_status"
    t.check_constraint "features_rating IS NULL OR features_rating >= 1 AND features_rating <= 5", name: "valid_features_rating"
    t.check_constraint "quality_score IS NULL OR quality_score >= 0::numeric AND quality_score <= 100::numeric", name: "valid_quality_score"
    t.check_constraint "rating >= 1 AND rating <= 5", name: "valid_overall_rating"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'published'::character varying::text, 'hidden'::character varying::text, 'flagged'::character varying::text, 'removed'::character varying::text])", name: "valid_review_status"
    t.check_constraint "support_rating IS NULL OR support_rating >= 1 AND support_rating <= 5", name: "valid_support_rating"
    t.check_constraint "usability_rating IS NULL OR usability_rating >= 1 AND usability_rating <= 5", name: "valid_usability_rating"
    t.check_constraint "value_rating IS NULL OR value_rating >= 1 AND value_rating <= 5", name: "valid_value_rating"
  end

  create_table "app_subscriptions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "app_id", null: false
    t.uuid "app_plan_id", null: false
    t.string "status", limit: 50, default: "active"
    t.datetime "subscribed_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }
    t.datetime "cancelled_at", precision: nil
    t.datetime "next_billing_at", precision: nil
    t.jsonb "configuration", default: {}
    t.jsonb "usage_metrics", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "app_id"], name: "idx_app_subscriptions_on_account_app_unique", unique: true
    t.index ["account_id"], name: "index_app_subscriptions_on_account_id"
    t.index ["app_id"], name: "index_app_subscriptions_on_app_id"
    t.index ["app_plan_id"], name: "index_app_subscriptions_on_app_plan_id"
    t.index ["next_billing_at"], name: "idx_app_subscriptions_on_next_billing_at"
    t.index ["status"], name: "idx_app_subscriptions_on_status"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'paused'::character varying::text, 'cancelled'::character varying::text, 'expired'::character varying::text])", name: "valid_app_subscription_status"
  end

  create_table "app_webhook_deliveries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "app_webhook_id", null: false
    t.string "event_id", null: false
    t.string "status", default: "pending", null: false
    t.integer "attempt_number", default: 1
    t.integer "response_status"
    t.text "response_body"
    t.text "error_message"
    t.datetime "attempted_at"
    t.datetime "next_retry_at"
    t.jsonb "payload", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_webhook_id"], name: "idx_app_webhook_deliveries_on_app_webhook_id"
    t.index ["app_webhook_id"], name: "index_app_webhook_deliveries_on_app_webhook_id"
    t.index ["attempted_at"], name: "idx_app_webhook_deliveries_on_attempted_at"
    t.index ["event_id"], name: "idx_app_webhook_deliveries_on_event_id"
    t.index ["next_retry_at"], name: "idx_app_webhook_deliveries_on_next_retry_at"
    t.index ["status"], name: "idx_app_webhook_deliveries_on_status"
    t.check_constraint "attempt_number > 0", name: "valid_webhook_attempt_number"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'delivered'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text])", name: "valid_webhook_delivery_status"
  end

  create_table "app_webhooks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "app_id", null: false
    t.string "name", limit: 255, null: false
    t.string "slug", limit: 255, null: false
    t.text "description"
    t.string "event_type", limit: 100, null: false
    t.string "url", limit: 500, null: false
    t.string "http_method", limit: 10, default: "POST", null: false
    t.boolean "is_active", default: true
    t.integer "timeout_seconds", default: 30
    t.integer "max_retries", default: 3
    t.string "content_type", limit: 100, default: "application/json"
    t.jsonb "headers", default: {}
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_id", "event_type"], name: "idx_app_webhooks_on_app_event_type"
    t.index ["app_id", "slug"], name: "idx_app_webhooks_on_app_slug_unique", unique: true
    t.index ["app_id"], name: "idx_app_webhooks_on_app_id"
    t.index ["app_id"], name: "index_app_webhooks_on_app_id"
    t.index ["event_type"], name: "idx_app_webhooks_on_event_type"
    t.index ["is_active"], name: "idx_app_webhooks_on_is_active"
    t.check_constraint "http_method::text = ANY (ARRAY['POST'::character varying::text, 'PUT'::character varying::text, 'PATCH'::character varying::text])", name: "valid_webhook_http_method"
    t.check_constraint "max_retries >= 0 AND max_retries <= 10", name: "valid_webhook_retries"
    t.check_constraint "timeout_seconds > 0 AND timeout_seconds <= 300", name: "valid_webhook_timeout"
  end

  create_table "apps", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "name", limit: 255, null: false
    t.string "slug", limit: 255, null: false
    t.text "description"
    t.text "long_description"
    t.text "short_description"
    t.string "category", limit: 100
    t.string "version", limit: 50, default: "1.0.0"
    t.string "status", limit: 50, default: "draft"
    t.string "icon"
    t.jsonb "tags", default: []
    t.string "homepage_url"
    t.string "documentation_url"
    t.string "support_url"
    t.string "repository_url"
    t.string "license"
    t.string "privacy_policy_url"
    t.string "terms_of_service_url"
    t.jsonb "metadata", default: {}
    t.jsonb "configuration", default: {}
    t.datetime "published_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_apps_on_account_id"
    t.index ["category"], name: "idx_apps_on_category"
    t.index ["published_at"], name: "idx_apps_on_published_at"
    t.index ["slug"], name: "idx_apps_on_slug_unique", unique: true
    t.index ["status"], name: "idx_apps_on_status"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'review'::character varying::text, 'published'::character varying::text, 'inactive'::character varying::text])", name: "valid_app_status"
  end

  create_table "audit_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "user_id"
    t.string "action", limit: 100, null: false
    t.string "resource_type", limit: 100, null: false
    t.string "resource_id", limit: 36
    t.string "source", limit: 20, default: "web", null: false
    t.jsonb "old_values", default: {}
    t.jsonb "new_values", default: {}
    t.jsonb "metadata", default: {}
    t.string "ip_address", limit: 45
    t.string "user_agent", limit: 1000
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"], name: "idx_audit_logs_on_account_created_at"
    t.index ["account_id"], name: "index_audit_logs_on_account_id"
    t.index ["action"], name: "idx_audit_logs_on_action"
    t.index ["created_at"], name: "idx_audit_logs_on_created_at"
    t.index ["resource_type", "resource_id"], name: "idx_audit_logs_on_resource_type_id"
    t.index ["user_id"], name: "idx_audit_logs_on_user_id"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "background_jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "job_id", null: false
    t.string "job_type", null: false
    t.string "status", default: "pending"
    t.integer "priority", default: 0
    t.integer "attempts", default: 0
    t.integer "max_attempts", default: 25
    t.jsonb "arguments", default: {}
    t.text "error_message"
    t.text "backtrace"
    t.datetime "scheduled_at"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "failed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "idx_background_jobs_on_created_at"
    t.index ["job_id"], name: "idx_background_jobs_on_job_id_unique", unique: true
    t.index ["job_type", "status"], name: "idx_background_jobs_on_job_type_status"
    t.index ["job_type"], name: "idx_background_jobs_on_job_type"
    t.index ["scheduled_at"], name: "idx_background_jobs_on_scheduled_at"
    t.index ["status"], name: "idx_background_jobs_on_status"
    t.check_constraint "attempts >= 0 AND max_attempts > 0", name: "valid_job_attempts"
    t.check_constraint "priority >= 0", name: "valid_job_priority"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text, 'retrying'::character varying::text])", name: "valid_job_status"
  end

  create_table "blacklisted_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "token", null: false
    t.string "reason", default: "logout"
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["expires_at"], name: "index_blacklisted_tokens_on_expires_at"
    t.index ["token"], name: "index_blacklisted_tokens_on_token", unique: true
    t.index ["user_id"], name: "index_blacklisted_tokens_on_user_id"
  end

  create_table "database_backups", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "created_by_id", null: false
    t.string "backup_type", limit: 50, null: false
    t.string "status", limit: 50, default: "pending", null: false
    t.string "file_path", limit: 1000
    t.integer "file_size_bytes"
    t.text "description"
    t.datetime "started_at", null: false
    t.datetime "completed_at"
    t.integer "duration_seconds"
    t.text "error_message"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["backup_type"], name: "idx_database_backups_on_backup_type"
    t.index ["created_by_id"], name: "idx_database_backups_on_created_by_id"
    t.index ["created_by_id"], name: "index_database_backups_on_created_by_id"
    t.index ["started_at"], name: "idx_database_backups_on_started_at"
    t.index ["status"], name: "idx_database_backups_on_status"
    t.check_constraint "backup_type::text = ANY (ARRAY['full'::character varying::text, 'incremental'::character varying::text, 'manual'::character varying::text])", name: "valid_backup_type"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "valid_backup_status"
  end

  create_table "database_restores", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "database_backup_id", null: false
    t.uuid "initiated_by_id", null: false
    t.string "status", limit: 50, default: "pending", null: false
    t.text "description"
    t.datetime "started_at", null: false
    t.datetime "completed_at"
    t.integer "duration_seconds"
    t.text "error_message"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["database_backup_id"], name: "idx_database_restores_on_database_backup_id"
    t.index ["database_backup_id"], name: "index_database_restores_on_database_backup_id"
    t.index ["initiated_by_id"], name: "idx_database_restores_on_initiated_by_id"
    t.index ["initiated_by_id"], name: "index_database_restores_on_initiated_by_id"
    t.index ["started_at"], name: "idx_database_restores_on_started_at"
    t.index ["status"], name: "idx_database_restores_on_status"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "valid_restore_status"
  end

  create_table "delegation_permissions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_delegation_id", null: false
    t.uuid "permission_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_delegation_id", "permission_id"], name: "index_delegation_permissions_unique", unique: true
    t.index ["account_delegation_id"], name: "index_delegation_permissions_on_account_delegation_id"
    t.index ["permission_id"], name: "index_delegation_permissions_on_permission"
    t.index ["permission_id"], name: "index_delegation_permissions_on_permission_id"
  end

  create_table "email_deliveries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id"
    t.string "recipient_email", null: false
    t.string "sender_email"
    t.string "subject", null: false
    t.text "body_text"
    t.text "body_html"
    t.string "email_type", null: false
    t.string "status", default: "pending"
    t.string "external_id"
    t.text "error_message"
    t.datetime "sent_at"
    t.datetime "delivered_at"
    t.datetime "opened_at"
    t.datetime "clicked_at"
    t.datetime "bounced_at"
    t.string "bounce_reason"
    t.integer "retry_count", default: 0
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_type"], name: "idx_email_deliveries_on_email_type"
    t.index ["external_id"], name: "idx_email_deliveries_on_external_id_unique", unique: true, where: "(external_id IS NOT NULL)"
    t.index ["recipient_email"], name: "idx_email_deliveries_on_recipient_email"
    t.index ["sent_at"], name: "idx_email_deliveries_on_sent_at"
    t.index ["status"], name: "idx_email_deliveries_on_status"
    t.index ["user_id"], name: "index_email_deliveries_on_user_id"
    t.check_constraint "email_type::text = ANY (ARRAY['welcome'::character varying::text, 'verification'::character varying::text, 'password_reset'::character varying::text, 'invitation'::character varying::text, 'notification'::character varying::text, 'marketing'::character varying::text, 'transactional'::character varying::text])", name: "valid_email_type"
    t.check_constraint "retry_count >= 0", name: "valid_email_retry_count"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'sent'::character varying::text, 'delivered'::character varying::text, 'bounced'::character varying::text, 'failed'::character varying::text, 'opened'::character varying::text, 'clicked'::character varying::text])", name: "valid_email_status"
  end

  create_table "gateway_configurations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "provider", limit: 50, null: false
    t.string "key_name", limit: 100, null: false
    t.text "encrypted_value", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "key_name"], name: "idx_gateway_configurations_on_provider_key_unique", unique: true
    t.index ["provider"], name: "idx_gateway_configurations_on_provider"
  end

  create_table "gateway_connection_jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "gateway", null: false
    t.string "operation", null: false
    t.string "status", default: "pending"
    t.jsonb "payload", default: {}
    t.jsonb "response", default: {}
    t.text "error_message"
    t.integer "retry_count", default: 0
    t.datetime "scheduled_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["gateway", "operation"], name: "idx_gateway_connection_jobs_on_gateway_operation"
    t.index ["scheduled_at"], name: "idx_gateway_connection_jobs_on_scheduled_at"
    t.index ["status"], name: "idx_gateway_connection_jobs_on_status"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "valid_gateway_job_status"
  end

  create_table "impersonation_sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "impersonator_id", null: false
    t.uuid "impersonated_user_id", null: false
    t.string "session_token", null: false
    t.string "reason"
    t.datetime "started_at", null: false
    t.datetime "ended_at"
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ended_at"], name: "index_impersonation_sessions_on_ended_at"
    t.index ["impersonated_user_id"], name: "index_impersonation_sessions_on_impersonated_user"
    t.index ["impersonated_user_id"], name: "index_impersonation_sessions_on_impersonated_user_id"
    t.index ["impersonator_id"], name: "index_impersonation_sessions_on_impersonator"
    t.index ["impersonator_id"], name: "index_impersonation_sessions_on_impersonator_id"
    t.index ["session_token"], name: "index_impersonation_sessions_on_session_token_unique", unique: true
    t.index ["started_at"], name: "index_impersonation_sessions_on_started_at"
  end

  create_table "invitations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "inviter_id", null: false
    t.string "email", null: false
    t.string "first_name"
    t.string "last_name"
    t.string "token", null: false
    t.string "token_digest", null: false
    t.jsonb "role_names", default: ["member"]
    t.string "status", default: "pending"
    t.datetime "expires_at"
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_invitations_on_account_id"
    t.index ["email", "account_id"], name: "index_invitations_on_email_account", unique: true
    t.index ["expires_at"], name: "index_invitations_on_expires_at"
    t.index ["inviter_id"], name: "index_invitations_on_inviter_id"
    t.index ["role_names"], name: "index_invitations_on_role_names", using: :gin
    t.index ["status"], name: "index_invitations_on_status"
    t.index ["token_digest"], name: "index_invitations_on_token_digest", unique: true
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'accepted'::character varying::text, 'expired'::character varying::text, 'cancelled'::character varying::text])", name: "valid_invitation_status"
  end

  create_table "invoice_line_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "invoice_id", null: false
    t.uuid "plan_id"
    t.string "description", null: false
    t.string "line_type", default: "subscription", null: false
    t.integer "quantity", default: 1, null: false
    t.integer "unit_amount_cents", null: false
    t.integer "total_amount_cents", null: false
    t.datetime "period_start"
    t.datetime "period_end"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invoice_id"], name: "idx_invoice_line_items_on_invoice_id"
    t.index ["invoice_id"], name: "index_invoice_line_items_on_invoice_id"
    t.index ["plan_id"], name: "idx_invoice_line_items_on_plan_id"
    t.index ["plan_id"], name: "index_invoice_line_items_on_plan_id"
  end

  create_table "invoices", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "subscription_id"
    t.string "invoice_number", null: false
    t.string "status", limit: 50, null: false
    t.integer "subtotal_cents", default: 0, null: false
    t.integer "tax_cents", default: 0, null: false
    t.decimal "tax_rate", precision: 5, scale: 4, default: "0.0"
    t.integer "total_cents", default: 0, null: false
    t.string "currency", limit: 3, default: "usd", null: false
    t.datetime "issued_at"
    t.datetime "due_at"
    t.datetime "paid_at"
    t.string "stripe_invoice_id", limit: 100
    t.string "paypal_invoice_id", limit: 100
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_invoices_on_account_id"
    t.index ["due_at"], name: "idx_invoices_on_due_at"
    t.index ["invoice_number"], name: "idx_invoices_on_invoice_number_unique", unique: true
    t.index ["issued_at"], name: "idx_invoices_on_issued_at"
    t.index ["paid_at"], name: "idx_invoices_on_paid_at"
    t.index ["paypal_invoice_id"], name: "idx_invoices_on_paypal_id_unique", unique: true, where: "(paypal_invoice_id IS NOT NULL)"
    t.index ["status"], name: "idx_invoices_on_status"
    t.index ["stripe_invoice_id"], name: "idx_invoices_on_stripe_id_unique", unique: true, where: "(stripe_invoice_id IS NOT NULL)"
    t.index ["subscription_id"], name: "index_invoices_on_subscription_id"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'open'::character varying::text, 'paid'::character varying::text, 'void'::character varying::text, 'uncollectible'::character varying::text])", name: "valid_invoice_status"
    t.check_constraint "subtotal_cents >= 0 AND tax_cents >= 0 AND total_cents >= 0", name: "valid_invoice_amounts"
    t.check_constraint "tax_rate >= 0::numeric AND tax_rate < 1::numeric", name: "valid_tax_rate"
  end

  create_table "knowledge_base_article_tags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "article_id", null: false
    t.uuid "tag_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["article_id", "tag_id"], name: "index_kb_article_tags_unique", unique: true
    t.index ["tag_id"], name: "idx_kb_article_tags_on_tag_id"
  end

  create_table "knowledge_base_article_views", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "article_id", null: false
    t.uuid "user_id"
    t.string "session_id", limit: 255
    t.string "ip_address", limit: 45
    t.string "user_agent", limit: 1000
    t.string "referrer", limit: 1000
    t.integer "reading_time_seconds"
    t.boolean "read_to_end", default: false
    t.jsonb "metadata", default: {}
    t.datetime "viewed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["article_id", "viewed_at"], name: "idx_kb_article_views_on_article_viewed_at"
    t.index ["read_to_end"], name: "idx_kb_article_views_on_read_to_end"
    t.index ["session_id"], name: "idx_kb_article_views_on_session_id"
    t.index ["user_id"], name: "idx_kb_article_views_on_user_id"
    t.index ["user_id"], name: "index_knowledge_base_article_views_on_user_id"
    t.index ["viewed_at"], name: "idx_kb_article_views_on_viewed_at"
    t.check_constraint "reading_time_seconds IS NULL OR reading_time_seconds >= 0", name: "valid_kb_reading_time_seconds"
  end

  create_table "knowledge_base_articles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "category_id", null: false
    t.uuid "author_id", null: false
    t.uuid "last_edited_by_id"
    t.string "title", limit: 255, null: false
    t.string "slug", limit: 255, null: false
    t.text "content", null: false
    t.text "excerpt"
    t.string "status", limit: 50, default: "draft"
    t.boolean "is_featured", default: false
    t.boolean "is_public", default: true
    t.integer "sort_order", default: 0
    t.integer "view_count", default: 0
    t.integer "views_count", default: 0
    t.integer "likes_count", default: 0
    t.integer "helpful_count", default: 0
    t.integer "not_helpful_count", default: 0
    t.decimal "helpfulness_score", precision: 5, scale: 2, default: "0.0"
    t.integer "reading_time_minutes"
    t.string "meta_title", limit: 255
    t.text "meta_description"
    t.datetime "published_at"
    t.datetime "last_reviewed_at"
    t.jsonb "metadata", default: {}
    t.tsvector "search_vector"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "idx_knowledge_base_articles_on_author_id"
    t.index ["author_id"], name: "index_knowledge_base_articles_on_author_id"
    t.index ["category_id"], name: "idx_knowledge_base_articles_on_category_id"
    t.index ["helpfulness_score"], name: "idx_knowledge_base_articles_on_helpfulness_score"
    t.index ["is_featured"], name: "idx_knowledge_base_articles_on_is_featured"
    t.index ["is_public"], name: "idx_knowledge_base_articles_on_is_public"
    t.index ["last_edited_by_id"], name: "index_knowledge_base_articles_on_last_edited_by_id"
    t.index ["published_at"], name: "idx_knowledge_base_articles_on_published_at"
    t.index ["search_vector"], name: "idx_knowledge_base_articles_on_search_vector", using: :gin
    t.index ["slug"], name: "idx_knowledge_base_articles_on_slug_unique", unique: true
    t.index ["status"], name: "idx_knowledge_base_articles_on_status"
    t.index ["view_count"], name: "idx_knowledge_base_articles_on_view_count"
    t.check_constraint "helpful_count >= 0 AND not_helpful_count >= 0", name: "valid_kb_helpful_counts"
    t.check_constraint "helpfulness_score >= 0::numeric AND helpfulness_score <= 100::numeric", name: "valid_kb_helpfulness_score"
    t.check_constraint "reading_time_minutes IS NULL OR reading_time_minutes > 0", name: "valid_kb_reading_time"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'review'::character varying::text, 'published'::character varying::text, 'archived'::character varying::text])", name: "valid_kb_article_status"
    t.check_constraint "view_count >= 0", name: "valid_kb_view_count"
  end

  create_table "knowledge_base_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "article_id", null: false
    t.string "filename", limit: 255, null: false
    t.string "file_path", limit: 1000
    t.string "content_type", limit: 100
    t.bigint "file_size"
    t.uuid "uploaded_by_id", null: false
    t.integer "download_count", default: 0
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["article_id"], name: "idx_kb_attachments_on_article_id"
    t.index ["download_count"], name: "idx_kb_attachments_on_download_count"
    t.index ["filename"], name: "idx_kb_attachments_on_filename"
    t.index ["uploaded_by_id"], name: "idx_kb_attachments_on_uploaded_by_id"
    t.index ["uploaded_by_id"], name: "index_knowledge_base_attachments_on_uploaded_by_id"
    t.check_constraint "download_count >= 0", name: "valid_kb_download_count"
    t.check_constraint "file_size > 0", name: "valid_kb_attachment_size"
  end

  create_table "knowledge_base_categories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", limit: 255, null: false
    t.string "slug", limit: 255, null: false
    t.text "description"
    t.uuid "parent_id"
    t.string "icon", limit: 100
    t.integer "sort_order", default: 0
    t.boolean "is_active", default: true
    t.boolean "is_public", default: true
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["is_active"], name: "idx_knowledge_base_categories_on_is_active"
    t.index ["is_public"], name: "idx_knowledge_base_categories_on_is_public"
    t.index ["parent_id"], name: "index_knowledge_base_categories_on_parent_id"
    t.index ["slug"], name: "idx_knowledge_base_categories_on_slug_unique", unique: true
    t.index ["sort_order"], name: "idx_knowledge_base_categories_on_sort_order"
  end

  create_table "knowledge_base_comments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "article_id", null: false
    t.uuid "author_id", null: false
    t.uuid "parent_id"
    t.text "content", null: false
    t.string "status", limit: 50, default: "published"
    t.boolean "is_helpful_vote", default: false
    t.integer "helpful_count", default: 0
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["article_id", "status"], name: "idx_kb_comments_on_article_status"
    t.index ["author_id"], name: "idx_kb_comments_on_author_id"
    t.index ["author_id"], name: "index_knowledge_base_comments_on_author_id"
    t.index ["created_at"], name: "idx_kb_comments_on_created_at"
    t.index ["is_helpful_vote"], name: "idx_kb_comments_on_is_helpful_vote"
    t.index ["parent_id"], name: "idx_kb_comments_on_parent_id"
    t.index ["parent_id"], name: "index_knowledge_base_comments_on_parent_id"
    t.index ["status"], name: "idx_kb_comments_on_status"
    t.check_constraint "helpful_count >= 0", name: "valid_kb_comment_helpful_count"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'published'::character varying::text, 'hidden'::character varying::text, 'spam'::character varying::text])", name: "valid_kb_comment_status"
  end

  create_table "knowledge_base_tags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.string "slug", limit: 100, null: false
    t.string "color", limit: 7, default: "#6B7280"
    t.text "description"
    t.boolean "is_active", default: true
    t.integer "usage_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["is_active"], name: "idx_knowledge_base_tags_on_is_active"
    t.index ["name"], name: "idx_knowledge_base_tags_on_name_unique", unique: true
    t.index ["slug"], name: "idx_knowledge_base_tags_on_slug_unique", unique: true
    t.index ["usage_count"], name: "idx_knowledge_base_tags_on_usage_count"
    t.check_constraint "color::text ~ '^#[0-9A-Fa-f]{6}$'::text", name: "valid_kb_tag_color"
    t.check_constraint "usage_count >= 0", name: "valid_kb_tag_usage_count"
  end

  create_table "knowledge_base_workflows", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "article_id", null: false
    t.uuid "user_id", null: false
    t.string "action", limit: 100, null: false
    t.string "from_status", limit: 50
    t.string "to_status", limit: 50
    t.text "comment"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "idx_kb_workflows_on_action"
    t.index ["article_id", "created_at"], name: "idx_kb_workflows_on_article_created_at"
    t.index ["created_at"], name: "idx_kb_workflows_on_created_at"
    t.index ["from_status"], name: "idx_kb_workflows_on_from_status"
    t.index ["to_status"], name: "idx_kb_workflows_on_to_status"
    t.index ["user_id"], name: "idx_kb_workflows_on_user_id"
    t.index ["user_id"], name: "index_knowledge_base_workflows_on_user_id"
    t.check_constraint "action::text = ANY (ARRAY['create'::character varying::text, 'edit'::character varying::text, 'publish'::character varying::text, 'unpublish'::character varying::text, 'archive'::character varying::text, 'delete'::character varying::text, 'review'::character varying::text])", name: "valid_kb_workflow_action"
  end

  create_table "marketplace_categories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", limit: 255, null: false
    t.string "slug", limit: 255, null: false
    t.text "description"
    t.string "icon", limit: 100
    t.integer "sort_order", default: 0
    t.boolean "is_active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["is_active"], name: "idx_marketplace_categories_on_is_active"
    t.index ["slug"], name: "idx_marketplace_categories_on_slug_unique", unique: true
    t.index ["sort_order"], name: "idx_marketplace_categories_on_sort_order"
  end

  create_table "marketplace_listings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "app_id", null: false
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
    t.index ["category"], name: "idx_marketplace_listings_on_category"
    t.index ["featured"], name: "idx_marketplace_listings_on_featured"
    t.index ["published_at"], name: "idx_marketplace_listings_on_published_at"
    t.index ["review_status"], name: "idx_marketplace_listings_on_review_status"
    t.check_constraint "review_status::text = ANY (ARRAY['pending'::character varying::text, 'approved'::character varying::text, 'rejected'::character varying::text])", name: "valid_listing_review_status"
  end

  create_table "missing_payment_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "gateway", null: false
    t.string "external_payment_id", null: false
    t.integer "amount_cents", null: false
    t.string "currency", default: "usd", null: false
    t.datetime "gateway_created_at"
    t.datetime "detected_at", null: false
    t.string "status", default: "pending"
    t.jsonb "gateway_data", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_missing_payment_logs_on_account_id"
    t.index ["detected_at"], name: "idx_missing_payment_logs_on_detected_at"
    t.index ["gateway", "external_payment_id"], name: "idx_missing_payment_logs_on_gateway_external_id_unique", unique: true
    t.index ["status"], name: "idx_missing_payment_logs_on_status"
    t.check_constraint "amount_cents > 0", name: "valid_missing_payment_amount"
  end

  create_table "pages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "author_id"
    t.string "title", limit: 255, null: false
    t.string "slug", limit: 255, null: false
    t.text "content"
    t.text "rendered_content"
    t.text "excerpt"
    t.string "status", limit: 50, default: "draft"
    t.boolean "is_public", default: false
    t.string "meta_title", limit: 255
    t.string "seo_title", limit: 255
    t.text "meta_description"
    t.text "seo_description"
    t.text "meta_keywords"
    t.integer "word_count"
    t.integer "estimated_read_time"
    t.jsonb "metadata", default: {}
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_pages_on_author_id"
    t.index ["is_public"], name: "idx_pages_on_is_public"
    t.index ["published_at"], name: "idx_pages_on_published_at"
    t.index ["slug"], name: "idx_pages_on_slug_unique", unique: true
    t.index ["status"], name: "idx_pages_on_status"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'published'::character varying::text, 'archived'::character varying::text])", name: "valid_page_status"
  end

  create_table "password_histories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.index ["created_at"], name: "index_password_histories_on_created_at"
    t.index ["user_id"], name: "index_password_histories_on_user_id"
  end

  create_table "payment_methods", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "gateway", limit: 50, null: false
    t.string "external_id", null: false
    t.string "payment_type", limit: 50, null: false
    t.string "last_four", limit: 4
    t.string "brand", limit: 50
    t.integer "exp_month"
    t.integer "exp_year"
    t.string "cardholder_name"
    t.boolean "is_default", default: false
    t.boolean "is_active", default: true
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "is_default"], name: "idx_payment_methods_on_account_default_unique", unique: true, where: "(is_default = true)"
    t.index ["account_id"], name: "index_payment_methods_on_account_id"
    t.index ["gateway", "external_id"], name: "idx_payment_methods_on_gateway_external_id_unique", unique: true
    t.index ["is_active"], name: "idx_payment_methods_on_is_active"
    t.check_constraint "gateway::text = ANY (ARRAY['stripe'::character varying::text, 'paypal'::character varying::text])", name: "valid_payment_gateway"
    t.check_constraint "payment_type::text = ANY (ARRAY['card'::character varying::text, 'bank'::character varying::text, 'paypal'::character varying::text, 'apple_pay'::character varying::text, 'google_pay'::character varying::text])", name: "valid_payment_type"
  end

  create_table "payments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "subscription_id"
    t.uuid "payment_method_id"
    t.integer "amount_cents", null: false
    t.string "currency", limit: 3, default: "usd", null: false
    t.string "status", limit: 50, null: false
    t.string "gateway", limit: 50, null: false
    t.string "external_id"
    t.string "transaction_type", limit: 50
    t.text "failure_reason"
    t.datetime "processed_at"
    t.jsonb "gateway_response", default: {}
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "invoice_id"
    t.datetime "failed_at"
    t.index ["account_id"], name: "index_payments_on_account_id"
    t.index ["gateway", "external_id"], name: "idx_payments_on_gateway_external_id_unique", unique: true, where: "(external_id IS NOT NULL)"
    t.index ["invoice_id"], name: "index_payments_on_invoice_id"
    t.index ["payment_method_id"], name: "index_payments_on_payment_method_id"
    t.index ["processed_at"], name: "idx_payments_on_processed_at"
    t.index ["status"], name: "idx_payments_on_status"
    t.index ["subscription_id"], name: "index_payments_on_subscription_id"
    t.index ["transaction_type"], name: "idx_payments_on_transaction_type"
    t.check_constraint "amount_cents >= 0", name: "valid_payment_amount"
    t.check_constraint "gateway::text = ANY (ARRAY['stripe'::character varying::text, 'paypal'::character varying::text])", name: "valid_payment_gateway"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'succeeded'::character varying::text, 'failed'::character varying::text, 'canceled'::character varying::text, 'refunded'::character varying::text, 'partially_refunded'::character varying::text])", name: "valid_payment_status"
  end

  create_table "permissions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.string "resource", limit: 100
    t.string "action", limit: 100
    t.string "category", limit: 50, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_permissions_on_category"
    t.index ["name"], name: "index_permissions_on_name", unique: true
    t.index ["resource", "action", "category"], name: "idx_permissions_on_resource_action_category_unique", unique: true
    t.check_constraint "category::text = ANY (ARRAY['resource'::character varying::text, 'admin'::character varying::text, 'system'::character varying::text])", name: "valid_permission_category"
  end

  create_table "plans", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.string "slug", limit: 100, null: false
    t.text "description"
    t.integer "price_cents", default: 0, null: false
    t.string "billing_interval", limit: 20, default: "monthly", null: false
    t.string "billing_cycle", limit: 20, default: "monthly", null: false
    t.string "status", limit: 20, default: "active", null: false
    t.integer "trial_period_days", default: 0
    t.integer "trial_days", default: 0
    t.decimal "annual_discount_percent", precision: 5, scale: 2, default: "0.0"
    t.decimal "promotional_discount_percent", precision: 5, scale: 2, default: "0.0"
    t.string "promotional_discount_code"
    t.datetime "promotional_discount_start"
    t.datetime "promotional_discount_end"
    t.boolean "is_active", default: true, null: false
    t.boolean "is_public", default: true, null: false
    t.jsonb "features", default: []
    t.jsonb "limits", default: {}
    t.jsonb "metadata", default: {}
    t.jsonb "default_roles", default: []
    t.jsonb "volume_discount_tiers", default: []
    t.boolean "has_annual_discount", default: false, null: false
    t.boolean "has_volume_discount", default: false, null: false
    t.boolean "has_promotional_discount", default: false, null: false
    t.string "paypal_plan_id"
    t.string "currency", limit: 3, default: "USD"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["billing_interval"], name: "idx_plans_on_billing_interval"
    t.index ["is_active"], name: "idx_plans_on_is_active"
    t.index ["is_public"], name: "idx_plans_on_is_public"
    t.index ["slug"], name: "idx_plans_on_slug_unique", unique: true
    t.check_constraint "billing_interval::text = ANY (ARRAY['monthly'::character varying::text, 'yearly'::character varying::text, 'one_time'::character varying::text])", name: "valid_billing_interval"
    t.check_constraint "price_cents >= 0", name: "valid_price"
  end

  create_table "reconciliation_flags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "reconciliation_report_id", null: false
    t.string "flag_type", null: false
    t.string "severity", default: "medium"
    t.string "transaction_id"
    t.text "description", null: false
    t.decimal "amount_cents", precision: 15, scale: 2
    t.string "status", default: "open"
    t.datetime "resolved_at"
    t.uuid "resolved_by_id"
    t.text "resolution_notes"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["flag_type"], name: "idx_reconciliation_flags_on_flag_type"
    t.index ["reconciliation_report_id"], name: "idx_reconciliation_flags_on_reconciliation_report_id"
    t.index ["reconciliation_report_id"], name: "index_reconciliation_flags_on_reconciliation_report_id"
    t.index ["resolved_at"], name: "idx_reconciliation_flags_on_resolved_at"
    t.index ["resolved_by_id"], name: "index_reconciliation_flags_on_resolved_by_id"
    t.index ["severity"], name: "idx_reconciliation_flags_on_severity"
    t.index ["status"], name: "idx_reconciliation_flags_on_status"
    t.check_constraint "flag_type::text = ANY (ARRAY['missing_payment'::character varying::text, 'duplicate_payment'::character varying::text, 'amount_mismatch'::character varying::text, 'status_mismatch'::character varying::text, 'unknown_transaction'::character varying::text])", name: "valid_flag_type"
    t.check_constraint "severity::text = ANY (ARRAY['low'::character varying::text, 'medium'::character varying::text, 'high'::character varying::text, 'critical'::character varying::text])", name: "valid_flag_severity"
    t.check_constraint "status::text = ANY (ARRAY['open'::character varying::text, 'investigating'::character varying::text, 'resolved'::character varying::text, 'dismissed'::character varying::text])", name: "valid_flag_status"
  end

  create_table "reconciliation_investigations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "reconciliation_flag_id", null: false
    t.uuid "investigator_id", null: false
    t.string "status", default: "open"
    t.text "notes"
    t.datetime "started_at", null: false
    t.datetime "completed_at"
    t.jsonb "findings", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["investigator_id"], name: "idx_reconciliation_investigations_on_investigator_id"
    t.index ["investigator_id"], name: "index_reconciliation_investigations_on_investigator_id"
    t.index ["reconciliation_flag_id"], name: "idx_reconciliation_investigations_on_reconciliation_flag_id"
    t.index ["reconciliation_flag_id"], name: "index_reconciliation_investigations_on_reconciliation_flag_id"
    t.index ["started_at"], name: "idx_reconciliation_investigations_on_started_at"
    t.index ["status"], name: "idx_reconciliation_investigations_on_status"
    t.check_constraint "status::text = ANY (ARRAY['open'::character varying::text, 'in_progress'::character varying::text, 'completed'::character varying::text, 'escalated'::character varying::text])", name: "valid_investigation_status"
  end

  create_table "reconciliation_reports", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "report_type", null: false
    t.string "reconciliation_type", null: false
    t.string "gateway", null: false
    t.date "report_date", null: false
    t.date "reconciliation_date", null: false
    t.date "date_range_start", null: false
    t.date "date_range_end", null: false
    t.string "status", default: "pending"
    t.integer "total_transactions", default: 0
    t.integer "matched_transactions", default: 0
    t.integer "unmatched_transactions", default: 0
    t.integer "discrepancies_found", default: 0
    t.integer "discrepancies_count", default: 0
    t.integer "high_severity_count", default: 0
    t.integer "medium_severity_count", default: 0
    t.decimal "total_amount_cents", precision: 15, scale: 2, default: "0.0"
    t.text "summary"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["gateway", "report_date", "report_type"], name: "idx_reconciliation_reports_on_gateway_date_type_unique", unique: true
    t.index ["report_date"], name: "idx_reconciliation_reports_on_report_date"
    t.index ["status"], name: "idx_reconciliation_reports_on_status"
    t.check_constraint "gateway::text = ANY (ARRAY['stripe'::character varying::text, 'paypal'::character varying::text])", name: "valid_reconciliation_gateway"
    t.check_constraint "report_type::text = ANY (ARRAY['daily'::character varying::text, 'weekly'::character varying::text, 'monthly'::character varying::text, 'manual'::character varying::text])", name: "valid_report_type"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "valid_reconciliation_status"
    t.check_constraint "total_transactions >= 0 AND matched_transactions >= 0 AND unmatched_transactions >= 0", name: "valid_transaction_counts"
  end

  create_table "report_requests", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "requested_by_id", null: false
    t.string "report_type", limit: 100, null: false
    t.string "status", limit: 50, default: "pending", null: false
    t.jsonb "parameters", default: {}
    t.string "file_path", limit: 1000
    t.integer "file_size_bytes"
    t.datetime "requested_at", null: false
    t.datetime "completed_at"
    t.datetime "expires_at"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "report_type"], name: "idx_report_requests_on_account_report_type"
    t.index ["account_id"], name: "index_report_requests_on_account_id"
    t.index ["expires_at"], name: "idx_report_requests_on_expires_at"
    t.index ["requested_at"], name: "idx_report_requests_on_requested_at"
    t.index ["requested_by_id"], name: "idx_report_requests_on_requested_by_id"
    t.index ["requested_by_id"], name: "index_report_requests_on_requested_by_id"
    t.index ["status"], name: "idx_report_requests_on_status"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'generating'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'expired'::character varying::text])", name: "valid_report_request_status"
  end

  create_table "revenue_snapshots", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.date "snapshot_date", null: false
    t.string "period_type", limit: 20, null: false
    t.integer "mrr_cents", default: 0
    t.integer "arr_cents", default: 0
    t.integer "total_revenue_cents", default: 0
    t.integer "new_revenue_cents", default: 0
    t.integer "churned_revenue_cents", default: 0
    t.integer "active_subscriptions", default: 0
    t.integer "new_subscriptions", default: 0
    t.integer "churned_subscriptions", default: 0
    t.integer "total_customers_count", default: 0
    t.integer "new_customers_count", default: 0
    t.integer "churned_customers_count", default: 0
    t.integer "arpu_cents", default: 0
    t.integer "ltv_cents", default: 0
    t.decimal "growth_rate_percentage", precision: 5, scale: 2, default: "0.0"
    t.decimal "customer_churn_rate_percentage", precision: 5, scale: 2, default: "0.0"
    t.decimal "revenue_churn_rate_percentage", precision: 5, scale: 2, default: "0.0"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "snapshot_date", "period_type"], name: "index_revenue_snapshots_unique", unique: true
    t.index ["account_id"], name: "index_revenue_snapshots_on_account_id"
    t.index ["period_type"], name: "idx_revenue_snapshots_on_period_type"
    t.index ["snapshot_date"], name: "idx_revenue_snapshots_on_snapshot_date"
    t.check_constraint "period_type::text = ANY (ARRAY['daily'::character varying::text, 'weekly'::character varying::text, 'monthly'::character varying::text, 'yearly'::character varying::text])", name: "valid_period_type"
  end

  create_table "review_aggregation_cache", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "app_id", null: false
    t.decimal "average_rating", precision: 3, scale: 2, default: "0.0"
    t.integer "total_reviews", default: 0
    t.integer "five_star_count", default: 0
    t.integer "four_star_count", default: 0
    t.integer "three_star_count", default: 0
    t.integer "two_star_count", default: 0
    t.integer "one_star_count", default: 0
    t.decimal "average_usability_rating", precision: 3, scale: 2
    t.decimal "average_features_rating", precision: 3, scale: 2
    t.decimal "average_support_rating", precision: 3, scale: 2
    t.decimal "average_value_rating", precision: 3, scale: 2
    t.integer "verified_reviews_count", default: 0
    t.decimal "average_quality_score", precision: 5, scale: 2
    t.integer "total_helpful_votes", default: 0
    t.integer "response_count", default: 0
    t.decimal "response_rate", precision: 5, scale: 2, default: "0.0"
    t.datetime "last_calculated_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_id"], name: "idx_review_aggregation_cache_on_app_id_unique", unique: true
    t.index ["app_id"], name: "index_review_aggregation_cache_on_app_id"
    t.index ["average_rating"], name: "idx_review_aggregation_cache_on_average_rating"
    t.index ["last_calculated_at"], name: "idx_review_aggregation_cache_on_last_calculated_at"
    t.index ["total_reviews"], name: "idx_review_aggregation_cache_on_total_reviews"
    t.check_constraint "average_rating >= 0::numeric AND average_rating <= 5::numeric", name: "valid_cached_average_rating"
    t.check_constraint "five_star_count >= 0 AND four_star_count >= 0 AND three_star_count >= 0 AND two_star_count >= 0 AND one_star_count >= 0", name: "valid_rating_counts"
    t.check_constraint "response_rate >= 0::numeric AND response_rate <= 100::numeric", name: "valid_response_rate"
    t.check_constraint "total_reviews >= 0", name: "valid_total_reviews"
  end

  create_table "review_helpfulness_votes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "app_review_id", null: false
    t.uuid "account_id", null: false
    t.boolean "is_helpful", null: false
    t.integer "weight", default: 1
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_review_helpfulness_votes_on_account_id"
    t.index ["app_review_id", "account_id"], name: "idx_review_helpfulness_votes_on_review_account_unique", unique: true
    t.index ["app_review_id"], name: "index_review_helpfulness_votes_on_app_review_id"
    t.index ["is_helpful"], name: "idx_review_helpfulness_votes_on_is_helpful"
    t.check_constraint "weight > 0", name: "valid_vote_weight"
  end

  create_table "review_media_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "app_review_id", null: false
    t.string "file_type", limit: 50, null: false
    t.string "file_url", limit: 1000, null: false
    t.string "file_name", limit: 255
    t.integer "file_size"
    t.string "caption", limit: 500
    t.integer "display_order", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_review_id", "display_order"], name: "idx_review_media_attachments_on_review_display_order"
    t.index ["app_review_id"], name: "index_review_media_attachments_on_app_review_id"
    t.index ["file_type"], name: "idx_review_media_attachments_on_file_type"
    t.check_constraint "display_order >= 0", name: "valid_display_order"
    t.check_constraint "file_size IS NULL OR file_size > 0", name: "valid_file_size"
    t.check_constraint "file_type::text = ANY (ARRAY['image'::character varying::text, 'video'::character varying::text, 'document'::character varying::text])", name: "valid_media_type"
  end

  create_table "review_moderation_actions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "app_review_id", null: false
    t.uuid "moderator_id", null: false
    t.string "action_type", limit: 50, null: false
    t.string "previous_status", limit: 50
    t.string "new_status", limit: 50
    t.text "reason"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action_type"], name: "idx_review_moderation_actions_on_action_type"
    t.index ["app_review_id"], name: "idx_review_moderation_actions_on_app_review_id"
    t.index ["app_review_id"], name: "index_review_moderation_actions_on_app_review_id"
    t.index ["created_at"], name: "idx_review_moderation_actions_on_created_at"
    t.index ["moderator_id"], name: "idx_review_moderation_actions_on_moderator_id"
    t.index ["moderator_id"], name: "index_review_moderation_actions_on_moderator_id"
    t.check_constraint "action_type::text = ANY (ARRAY['publish'::character varying::text, 'hide'::character varying::text, 'flag'::character varying::text, 'remove'::character varying::text, 'approve'::character varying::text, 'reject'::character varying::text, 'edit'::character varying::text])", name: "valid_moderation_action"
  end

  create_table "review_notification_deliveries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "review_notification_id", null: false
    t.string "delivery_channel", limit: 50, null: false
    t.string "status", limit: 20, default: "pending"
    t.datetime "attempted_at"
    t.datetime "delivered_at"
    t.text "response_data"
    t.text "error_message"
    t.integer "attempt_count", default: 0
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["attempted_at"], name: "idx_review_notification_deliveries_on_attempted_at"
    t.index ["delivered_at"], name: "idx_review_notification_deliveries_on_delivered_at"
    t.index ["delivery_channel"], name: "idx_review_notification_deliveries_on_delivery_channel"
    t.index ["review_notification_id"], name: "idx_review_notification_deliveries_on_review_notification_id"
    t.index ["review_notification_id"], name: "index_review_notification_deliveries_on_review_notification_id"
    t.index ["status"], name: "idx_review_notification_deliveries_on_status"
    t.check_constraint "attempt_count >= 0", name: "valid_delivery_attempt_count"
    t.check_constraint "delivery_channel::text = ANY (ARRAY['email'::character varying::text, 'sms'::character varying::text, 'push'::character varying::text, 'webhook'::character varying::text, 'slack'::character varying::text])", name: "valid_delivery_channel"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'delivered'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text])", name: "valid_delivery_status"
  end

  create_table "review_notifications", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "app_review_id", null: false
    t.uuid "recipient_id", null: false
    t.uuid "triggered_by_id"
    t.string "notification_type", limit: 100, null: false
    t.jsonb "delivery_channels", default: [], null: false
    t.string "priority", limit: 20, default: "normal"
    t.string "status", limit: 20, default: "pending"
    t.jsonb "template_data", default: {}, null: false
    t.datetime "scheduled_at"
    t.datetime "sent_at"
    t.integer "retry_count", default: 0
    t.text "failure_reason"
    t.jsonb "delivery_results", default: {}
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_review_id"], name: "idx_review_notifications_on_app_review_id"
    t.index ["app_review_id"], name: "index_review_notifications_on_app_review_id"
    t.index ["created_at"], name: "idx_review_notifications_on_created_at"
    t.index ["delivery_channels"], name: "idx_review_notifications_on_delivery_channels", using: :gin
    t.index ["notification_type"], name: "idx_review_notifications_on_notification_type"
    t.index ["priority"], name: "idx_review_notifications_on_priority"
    t.index ["recipient_id"], name: "idx_review_notifications_on_recipient_id"
    t.index ["recipient_id"], name: "index_review_notifications_on_recipient_id"
    t.index ["scheduled_at"], name: "idx_review_notifications_on_scheduled_at"
    t.index ["status"], name: "idx_review_notifications_on_status"
    t.index ["triggered_by_id"], name: "idx_review_notifications_on_triggered_by_id"
    t.index ["triggered_by_id"], name: "index_review_notifications_on_triggered_by_id"
    t.check_constraint "notification_type::text = ANY (ARRAY['new_review'::character varying::text, 'review_response'::character varying::text, 'review_flagged'::character varying::text, 'review_approved'::character varying::text, 'review_rejected'::character varying::text, 'review_milestone'::character varying::text, 'helpful_vote'::character varying::text, 'review_digest'::character varying::text, 'admin_alert'::character varying::text])", name: "valid_notification_type"
    t.check_constraint "priority::text = ANY (ARRAY['low'::character varying::text, 'normal'::character varying::text, 'high'::character varying::text, 'urgent'::character varying::text])", name: "valid_notification_priority"
    t.check_constraint "retry_count >= 0", name: "valid_retry_count"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'sent'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text])", name: "valid_notification_status"
  end

  create_table "review_responses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "app_review_id", null: false
    t.uuid "responder_id", null: false
    t.text "content", null: false
    t.string "status", limit: 50, default: "published"
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_review_id"], name: "idx_review_responses_on_app_review_id"
    t.index ["app_review_id"], name: "index_review_responses_on_app_review_id"
    t.index ["published_at"], name: "idx_review_responses_on_published_at"
    t.index ["responder_id"], name: "idx_review_responses_on_responder_id"
    t.index ["responder_id"], name: "index_review_responses_on_responder_id"
    t.index ["status"], name: "idx_review_responses_on_status"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'published'::character varying::text, 'hidden'::character varying::text, 'removed'::character varying::text])", name: "valid_response_status"
  end

  create_table "role_permissions", id: false, force: :cascade do |t|
    t.uuid "role_id", null: false
    t.uuid "permission_id", null: false
    t.datetime "granted_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["permission_id"], name: "index_role_permissions_on_permission_id"
    t.index ["permission_id"], name: "index_role_perms_on_permission"
    t.index ["role_id", "permission_id"], name: "index_role_perms_unique", unique: true
    t.index ["role_id"], name: "index_role_permissions_on_role_id"
  end

  create_table "roles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.string "display_name", limit: 100
    t.text "description"
    t.string "role_type", limit: 20
    t.boolean "is_system", default: false, null: false
    t.boolean "immutable", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_roles_on_name", unique: true
  end

  create_table "scheduled_reports", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "created_by_id", null: false
    t.string "name", limit: 255, null: false
    t.string "report_type", limit: 100, null: false
    t.string "frequency", limit: 50, null: false
    t.string "format", limit: 20, default: "pdf", null: false
    t.jsonb "parameters", default: {}
    t.jsonb "recipients", default: []
    t.boolean "is_active", default: true
    t.datetime "next_run_at"
    t.datetime "last_run_at"
    t.string "last_status", limit: 50
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "report_type"], name: "idx_scheduled_reports_on_account_report_type"
    t.index ["account_id"], name: "index_scheduled_reports_on_account_id"
    t.index ["created_by_id"], name: "index_scheduled_reports_on_created_by_id"
    t.index ["frequency"], name: "idx_scheduled_reports_on_frequency"
    t.index ["is_active"], name: "idx_scheduled_reports_on_is_active"
    t.index ["next_run_at"], name: "idx_scheduled_reports_on_next_run_at"
    t.check_constraint "frequency::text = ANY (ARRAY['daily'::character varying::text, 'weekly'::character varying::text, 'monthly'::character varying::text, 'quarterly'::character varying::text, 'yearly'::character varying::text])", name: "valid_report_frequency"
  end

  create_table "scheduled_tasks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", limit: 255, null: false
    t.string "task_type", limit: 100, null: false
    t.string "cron_expression", limit: 100
    t.integer "interval_seconds"
    t.boolean "is_active", default: true
    t.jsonb "parameters", default: {}
    t.datetime "next_run_at"
    t.datetime "last_run_at"
    t.string "last_status", limit: 50
    t.text "last_error_message"
    t.integer "success_count", default: 0
    t.integer "failure_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["is_active"], name: "idx_scheduled_tasks_on_is_active"
    t.index ["last_run_at"], name: "idx_scheduled_tasks_on_last_run_at"
    t.index ["name"], name: "idx_scheduled_tasks_on_name_unique", unique: true
    t.index ["next_run_at"], name: "idx_scheduled_tasks_on_next_run_at"
    t.index ["task_type"], name: "idx_scheduled_tasks_on_task_type"
  end

  create_table "site_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "key", limit: 255, null: false
    t.text "value"
    t.string "setting_type", limit: 50, default: "string"
    t.text "description"
    t.boolean "is_public", default: true
    t.string "category", limit: 100
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "idx_site_settings_on_category"
    t.index ["is_public"], name: "idx_site_settings_on_is_public"
    t.index ["key"], name: "idx_site_settings_on_key_unique", unique: true
    t.index ["setting_type"], name: "idx_site_settings_on_setting_type"
    t.check_constraint "setting_type::text = ANY (ARRAY['string'::character varying::text, 'text'::character varying::text, 'integer'::character varying::text, 'boolean'::character varying::text, 'json'::character varying::text, 'array'::character varying::text])", name: "valid_site_setting_type"
  end

  create_table "subscriptions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "plan_id", null: false
    t.integer "quantity", default: 1, null: false
    t.string "status", limit: 50, null: false
    t.datetime "current_period_start"
    t.datetime "current_period_end"
    t.datetime "trial_start"
    t.datetime "trial_end"
    t.datetime "canceled_at"
    t.datetime "ended_at"
    t.string "stripe_subscription_id", limit: 100
    t.string "paypal_subscription_id", limit: 100
    t.string "paypal_agreement_id"
    t.string "paypal_plan_id"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_subscriptions_on_account_id"
    t.index ["current_period_end"], name: "idx_subscriptions_on_current_period_end"
    t.index ["paypal_subscription_id"], name: "idx_subscriptions_on_paypal_id_unique", unique: true, where: "(paypal_subscription_id IS NOT NULL)"
    t.index ["plan_id"], name: "index_subscriptions_on_plan_id"
    t.index ["status"], name: "idx_subscriptions_on_status"
    t.index ["stripe_subscription_id"], name: "idx_subscriptions_on_stripe_id_unique", unique: true, where: "(stripe_subscription_id IS NOT NULL)"
    t.index ["trial_end"], name: "idx_subscriptions_on_trial_end"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'trialing'::character varying::text, 'past_due'::character varying::text, 'canceled'::character varying::text, 'unpaid'::character varying::text, 'incomplete'::character varying::text, 'incomplete_expired'::character varying::text, 'paused'::character varying::text])", name: "valid_subscription_status"
  end

  create_table "system_health_checks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "check_name", limit: 100, null: false
    t.string "status", limit: 50, null: false
    t.text "message"
    t.integer "response_time_ms"
    t.jsonb "details", default: {}
    t.datetime "checked_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["check_name", "checked_at"], name: "idx_system_health_checks_on_name_checked_at"
    t.index ["checked_at"], name: "idx_system_health_checks_on_checked_at"
    t.index ["status"], name: "idx_system_health_checks_on_status"
    t.check_constraint "status::text = ANY (ARRAY['healthy'::character varying::text, 'warning'::character varying::text, 'critical'::character varying::text, 'unknown'::character varying::text])", name: "valid_health_status"
  end

  create_table "system_operations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "initiated_by_id"
    t.string "operation_type", limit: 100, null: false
    t.string "status", limit: 50, default: "pending", null: false
    t.text "description"
    t.jsonb "parameters", default: {}
    t.jsonb "result", default: {}
    t.text "error_message"
    t.datetime "started_at", null: false
    t.datetime "completed_at"
    t.integer "duration_ms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["completed_at"], name: "idx_system_operations_on_completed_at"
    t.index ["initiated_by_id"], name: "idx_system_operations_on_initiated_by_id"
    t.index ["initiated_by_id"], name: "index_system_operations_on_initiated_by_id"
    t.index ["operation_type"], name: "idx_system_operations_on_operation_type"
    t.index ["started_at"], name: "idx_system_operations_on_started_at"
    t.index ["status"], name: "idx_system_operations_on_status"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text])", name: "valid_operation_status"
  end

  create_table "task_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "scheduled_task_id", null: false
    t.string "status", limit: 50, null: false
    t.datetime "started_at", null: false
    t.datetime "completed_at"
    t.integer "duration_ms"
    t.jsonb "result", default: {}
    t.text "error_message"
    t.text "log_output"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["scheduled_task_id", "started_at"], name: "idx_task_executions_on_scheduled_task_started_at"
    t.index ["scheduled_task_id"], name: "index_task_executions_on_scheduled_task_id"
    t.index ["started_at"], name: "idx_task_executions_on_started_at"
    t.index ["status"], name: "idx_task_executions_on_status"
    t.check_constraint "status::text = ANY (ARRAY['running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'timeout'::character varying::text])", name: "valid_execution_status"
  end

  create_table "user_roles", id: false, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.uuid "role_id", null: false
    t.uuid "granted_by_id"
    t.datetime "granted_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["granted_by_id"], name: "index_user_roles_on_granted_by"
    t.index ["granted_by_id"], name: "index_user_roles_on_granted_by_id"
    t.index ["role_id"], name: "index_user_roles_on_role"
    t.index ["role_id"], name: "index_user_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_user_roles_unique", unique: true
    t.index ["user_id"], name: "index_user_roles_on_user_id"
  end

  create_table "user_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "token_digest", limit: 128, null: false
    t.string "token_type", limit: 20, default: "access", null: false
    t.string "name", limit: 100
    t.text "permissions"
    t.string "scopes", limit: 500
    t.datetime "last_used_at"
    t.inet "last_used_ip"
    t.string "user_agent", limit: 500
    t.datetime "expires_at"
    t.boolean "revoked", default: false
    t.datetime "revoked_at"
    t.string "revoked_reason", limit: 100
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "idx_user_tokens_on_created_at"
    t.index ["expires_at"], name: "idx_user_tokens_on_expires_at"
    t.index ["last_used_at"], name: "idx_user_tokens_on_last_used_at"
    t.index ["revoked"], name: "idx_user_tokens_on_revoked"
    t.index ["token_digest"], name: "idx_user_tokens_on_token_digest_unique", unique: true
    t.index ["token_type"], name: "idx_user_tokens_on_token_type"
    t.index ["user_id", "token_type"], name: "idx_user_tokens_on_user_id_type"
    t.index ["user_id"], name: "idx_user_tokens_on_user_id"
    t.index ["user_id"], name: "index_user_tokens_on_user_id"
    t.check_constraint "expires_at > created_at", name: "valid_expiration"
    t.check_constraint "length(token_digest::text) >= 32", name: "valid_token_digest_length"
    t.check_constraint "token_type::text = ANY (ARRAY['access'::character varying::text, 'refresh'::character varying::text, 'api_key'::character varying::text, '2fa'::character varying::text, 'impersonation'::character varying::text])", name: "valid_token_type"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "email", limit: 255, null: false
    t.string "password_digest", null: false
    t.string "first_name", limit: 50, null: false
    t.string "last_name", limit: 50, null: false
    t.string "status", limit: 20, default: "active", null: false
    t.boolean "email_verified", default: false, null: false
    t.datetime "email_verified_at"
    t.string "email_verification_token", limit: 255
    t.datetime "email_verification_token_expires_at"
    t.datetime "email_verification_sent_at"
    t.integer "failed_login_attempts", default: 0, null: false
    t.datetime "locked_until"
    t.datetime "password_changed_at"
    t.datetime "last_login_at"
    t.string "last_login_ip", limit: 45
    t.string "reset_token_digest"
    t.datetime "reset_token_expires_at"
    t.text "preferences"
    t.text "notification_preferences"
    t.boolean "two_factor_enabled", default: false, null: false
    t.string "two_factor_secret"
    t.text "backup_codes"
    t.datetime "two_factor_backup_codes_generated_at"
    t.datetime "two_factor_enabled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_users_on_account_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["email_verification_token"], name: "index_users_on_email_verification_token", unique: true, where: "(email_verification_token IS NOT NULL)"
    t.index ["reset_token_digest"], name: "index_users_on_reset_token_digest", unique: true, where: "(reset_token_digest IS NOT NULL)"
    t.index ["status"], name: "index_users_on_status"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'suspended'::character varying::text, 'pending_verification'::character varying::text])", name: "valid_user_status"
  end

  create_table "webhook_deliveries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "webhook_endpoint_id", null: false
    t.uuid "webhook_event_id", null: false
    t.string "status", default: "pending"
    t.integer "attempt_number", default: 1
    t.integer "response_status"
    t.text "response_body"
    t.text "error_message"
    t.datetime "attempted_at"
    t.datetime "next_retry_at"
    t.jsonb "request_headers", default: {}
    t.jsonb "response_headers", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["attempted_at"], name: "idx_webhook_deliveries_on_attempted_at"
    t.index ["next_retry_at"], name: "idx_webhook_deliveries_on_next_retry_at"
    t.index ["status"], name: "idx_webhook_deliveries_on_status"
    t.index ["webhook_endpoint_id"], name: "idx_webhook_deliveries_on_webhook_endpoint_id"
    t.index ["webhook_endpoint_id"], name: "index_webhook_deliveries_on_webhook_endpoint_id"
    t.index ["webhook_event_id"], name: "idx_webhook_deliveries_on_webhook_event_id"
    t.index ["webhook_event_id"], name: "index_webhook_deliveries_on_webhook_event_id"
    t.check_constraint "attempt_number > 0", name: "valid_webhook_attempt_number"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'success'::character varying::text, 'failed'::character varying::text, 'timeout'::character varying::text])", name: "valid_webhook_delivery_status"
  end

  create_table "webhook_endpoints", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "url", limit: 1000, null: false
    t.string "secret_key"
    t.boolean "is_active", default: true
    t.string "status", limit: 20, default: "active", null: false
    t.jsonb "event_types", default: []
    t.jsonb "headers", default: {}
    t.integer "timeout_seconds", default: 30
    t.integer "max_retries", default: 3
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by_id"
    t.string "content_type", limit: 100, default: "application/json"
    t.string "description", limit: 500
    t.integer "retry_limit", default: 3
    t.string "retry_backoff", limit: 20, default: "exponential"
    t.integer "success_count", default: 0
    t.integer "failure_count", default: 0
    t.datetime "last_delivery_at", precision: nil
    t.jsonb "metadata", default: {}
    t.index ["account_id"], name: "idx_webhook_endpoints_on_account_id"
    t.index ["account_id"], name: "index_webhook_endpoints_on_account_id"
    t.index ["content_type"], name: "index_webhook_endpoints_on_content_type"
    t.index ["created_by_id"], name: "index_webhook_endpoints_on_created_by_id"
    t.index ["failure_count"], name: "index_webhook_endpoints_on_failure_count"
    t.index ["is_active"], name: "idx_webhook_endpoints_on_is_active"
    t.index ["last_delivery_at"], name: "index_webhook_endpoints_on_last_delivery_at"
    t.index ["success_count"], name: "index_webhook_endpoints_on_success_count"
    t.check_constraint "content_type::text = ANY (ARRAY['application/json'::character varying::text, 'application/x-www-form-urlencoded'::character varying::text])", name: "valid_webhook_content_type_v2"
    t.check_constraint "failure_count >= 0", name: "valid_webhook_failure_count_v2"
    t.check_constraint "max_retries >= 0 AND max_retries <= 10", name: "valid_webhook_max_retries"
    t.check_constraint "retry_backoff::text = ANY (ARRAY['linear'::character varying::text, 'exponential'::character varying::text])", name: "valid_webhook_retry_backoff_v2"
    t.check_constraint "retry_limit >= 0 AND retry_limit <= 10", name: "valid_webhook_retry_limit_v2"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'suspended'::character varying::text])", name: "valid_webhook_status"
    t.check_constraint "success_count >= 0", name: "valid_webhook_success_count_v2"
    t.check_constraint "timeout_seconds > 0 AND timeout_seconds <= 300", name: "valid_webhook_timeout"
  end

  create_table "webhook_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "event_type", null: false
    t.string "event_id", null: false
    t.jsonb "payload", default: {}
    t.datetime "occurred_at", null: false
    t.string "status", default: "pending"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "provider", null: false
    t.string "external_id", null: false
    t.integer "retry_count", default: 0, null: false
    t.text "error_message"
    t.text "metadata"
    t.datetime "processed_at"
    t.index ["account_id", "event_type"], name: "idx_webhook_events_on_account_event_type"
    t.index ["account_id"], name: "index_webhook_events_on_account_id"
    t.index ["event_id"], name: "idx_webhook_events_on_event_id_unique", unique: true
    t.index ["external_id"], name: "idx_webhook_events_on_external_id", unique: true
    t.index ["occurred_at"], name: "idx_webhook_events_on_occurred_at"
    t.index ["provider"], name: "idx_webhook_events_on_provider"
    t.index ["retry_count"], name: "idx_webhook_events_on_retry_count"
    t.index ["status"], name: "idx_webhook_events_on_status"
    t.check_constraint "provider::text = ANY (ARRAY['stripe'::character varying::text, 'paypal'::character varying::text])", name: "valid_webhook_provider"
    t.check_constraint "retry_count >= 0 AND retry_count <= 10", name: "valid_retry_count"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "valid_webhook_event_status"
  end

  create_table "worker_activities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "worker_id", null: false
    t.string "activity_type", limit: 100, null: false
    t.string "status", limit: 50
    t.jsonb "details", default: {}
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["activity_type"], name: "idx_worker_activities_on_activity_type"
    t.index ["occurred_at"], name: "idx_worker_activities_on_occurred_at"
    t.index ["worker_id", "occurred_at"], name: "idx_worker_activities_on_worker_occurred_at"
    t.index ["worker_id"], name: "index_worker_activities_on_worker_id"
  end

  create_table "worker_roles", id: false, force: :cascade do |t|
    t.uuid "worker_id", null: false
    t.uuid "role_id", null: false
    t.datetime "granted_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["role_id"], name: "index_worker_roles_on_role"
    t.index ["role_id"], name: "index_worker_roles_on_role_id"
    t.index ["worker_id", "role_id"], name: "index_worker_roles_unique", unique: true
    t.index ["worker_id"], name: "index_worker_roles_on_worker_id"
  end

  create_table "workers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.string "status", default: "active"
    t.string "token_digest"
    t.jsonb "permissions", default: []
    t.datetime "last_seen_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "account_id"
    t.index ["account_id"], name: "index_workers_on_account_id"
    t.index ["name"], name: "index_workers_on_name", unique: true
    t.index ["permissions"], name: "index_workers_on_permissions", using: :gin
    t.index ["status"], name: "index_workers_on_status"
  end

  add_foreign_key "account_delegations", "accounts"
  add_foreign_key "account_delegations", "roles"
  add_foreign_key "account_delegations", "users", column: "delegated_by_id"
  add_foreign_key "account_delegations", "users", column: "delegated_user_id"
  add_foreign_key "account_delegations", "users", column: "revoked_by_id"
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
  add_foreign_key "database_backups", "users", column: "created_by_id"
  add_foreign_key "database_restores", "database_backups"
  add_foreign_key "database_restores", "users", column: "initiated_by_id"
  add_foreign_key "delegation_permissions", "account_delegations"
  add_foreign_key "delegation_permissions", "permissions"
  add_foreign_key "email_deliveries", "users"
  add_foreign_key "impersonation_sessions", "users", column: "impersonated_user_id"
  add_foreign_key "impersonation_sessions", "users", column: "impersonator_id"
  add_foreign_key "invitations", "accounts"
  add_foreign_key "invitations", "users", column: "inviter_id"
  add_foreign_key "invoice_line_items", "invoices"
  add_foreign_key "invoice_line_items", "plans"
  add_foreign_key "invoices", "accounts"
  add_foreign_key "invoices", "subscriptions"
  add_foreign_key "knowledge_base_article_views", "users"
  add_foreign_key "knowledge_base_articles", "users", column: "author_id"
  add_foreign_key "knowledge_base_articles", "users", column: "last_edited_by_id"
  add_foreign_key "knowledge_base_attachments", "users", column: "uploaded_by_id"
  add_foreign_key "knowledge_base_categories", "knowledge_base_categories", column: "parent_id"
  add_foreign_key "knowledge_base_comments", "knowledge_base_comments", column: "parent_id"
  add_foreign_key "knowledge_base_comments", "users", column: "author_id"
  add_foreign_key "knowledge_base_workflows", "users"
  add_foreign_key "marketplace_listings", "apps", on_delete: :cascade
  add_foreign_key "missing_payment_logs", "accounts"
  add_foreign_key "pages", "users", column: "author_id"
  add_foreign_key "password_histories", "users"
  add_foreign_key "payment_methods", "accounts"
  add_foreign_key "payments", "accounts"
  add_foreign_key "payments", "invoices"
  add_foreign_key "payments", "payment_methods"
  add_foreign_key "payments", "subscriptions"
  add_foreign_key "reconciliation_flags", "reconciliation_reports"
  add_foreign_key "reconciliation_flags", "users", column: "resolved_by_id"
  add_foreign_key "reconciliation_investigations", "reconciliation_flags"
  add_foreign_key "reconciliation_investigations", "users", column: "investigator_id"
  add_foreign_key "report_requests", "accounts"
  add_foreign_key "report_requests", "users", column: "requested_by_id"
  add_foreign_key "revenue_snapshots", "accounts"
  add_foreign_key "review_aggregation_cache", "apps", on_delete: :cascade
  add_foreign_key "review_helpfulness_votes", "accounts"
  add_foreign_key "review_helpfulness_votes", "app_reviews", on_delete: :cascade
  add_foreign_key "review_media_attachments", "app_reviews", on_delete: :cascade
  add_foreign_key "review_moderation_actions", "app_reviews", on_delete: :cascade
  add_foreign_key "review_moderation_actions", "users", column: "moderator_id"
  add_foreign_key "review_notification_deliveries", "review_notifications"
  add_foreign_key "review_notifications", "accounts", column: "recipient_id"
  add_foreign_key "review_notifications", "accounts", column: "triggered_by_id"
  add_foreign_key "review_notifications", "app_reviews"
  add_foreign_key "review_responses", "app_reviews", on_delete: :cascade
  add_foreign_key "review_responses", "users", column: "responder_id"
  add_foreign_key "role_permissions", "permissions"
  add_foreign_key "role_permissions", "roles"
  add_foreign_key "scheduled_reports", "accounts"
  add_foreign_key "scheduled_reports", "users", column: "created_by_id"
  add_foreign_key "subscriptions", "accounts"
  add_foreign_key "subscriptions", "plans"
  add_foreign_key "system_operations", "users", column: "initiated_by_id"
  add_foreign_key "task_executions", "scheduled_tasks"
  add_foreign_key "user_roles", "roles"
  add_foreign_key "user_roles", "users"
  add_foreign_key "user_roles", "users", column: "granted_by_id"
  add_foreign_key "user_tokens", "users"
  add_foreign_key "users", "accounts"
  add_foreign_key "webhook_deliveries", "webhook_endpoints"
  add_foreign_key "webhook_deliveries", "webhook_events"
  add_foreign_key "webhook_endpoints", "accounts"
  add_foreign_key "webhook_endpoints", "users", column: "created_by_id"
  add_foreign_key "webhook_events", "accounts"
  add_foreign_key "worker_activities", "workers"
  add_foreign_key "worker_roles", "roles"
  add_foreign_key "worker_roles", "workers"
  add_foreign_key "workers", "accounts"
end
