# frozen_string_literal: true

class IdentityAuthBaseline < ActiveRecord::Migration[8.1]
  def change
  # These are extensions that must be enabled in order to support this database
  enable_extension "ltree"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"
  enable_extension "pgcrypto"
  enable_extension "vector"

  create_table "account_delegations", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.uuid "delegated_by_id", null: false
    t.uuid "delegated_user_id", null: false
    t.datetime "expires_at"
    t.text "notes"
    t.datetime "revoked_at"
    t.uuid "revoked_by_id"
    t.uuid "role_id"
    t.string "status", default: "active"
    t.datetime "updated_at", null: false
    t.index ["account_id", "delegated_user_id"], unique: true
    t.index ["account_id"]
    t.index ["delegated_by_id"]
    t.index ["delegated_user_id"]
    t.index ["expires_at"]
    t.index ["revoked_by_id"]
    t.index ["role_id"]
    t.index ["status"]
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'revoked'::character varying::text])", name: "valid_delegation_status"
  end

  create_table "account_terminations", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.text "cancellation_reason"
    t.datetime "cancelled_at"
    t.uuid "cancelled_by_id"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.uuid "data_export_request_id"
    t.boolean "data_export_requested", default: false
    t.text "feedback"
    t.boolean "feedback_submitted", default: false
    t.datetime "grace_period_ends_at", null: false
    t.jsonb "metadata", default: {}
    t.uuid "processed_by_id"
    t.datetime "processing_started_at"
    t.text "reason"
    t.datetime "requested_at", null: false
    t.uuid "requested_by_id"
    t.string "status", default: "pending", null: false
    t.jsonb "termination_log", default: []
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["cancelled_by_id"]
    t.index ["data_export_request_id"]
    t.index ["grace_period_ends_at"]
    t.index ["processed_by_id"]
    t.index ["requested_by_id"]
    t.index ["status"]
  end

  create_table "accounts", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.boolean "ai_suspended", default: false, null: false
    t.datetime "ai_suspended_at"
    t.string "analytics_tier", default: "free", null: false
    t.string "billing_email"
    t.datetime "created_at", null: false
    t.string "encryption_key_vault_path"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", limit: 100, null: false
    t.string "paypal_customer_id", limit: 50
    t.text "publisher_bio"
    t.string "publisher_display_name"
    t.string "publisher_logo_url"
    t.string "publisher_website"
    t.jsonb "settings", default: {}
    t.string "status", limit: 20, default: "active", null: false
    t.string "stripe_customer_id", limit: 50
    t.string "subdomain", limit: 30
    t.string "tax_id"
    t.datetime "transit_key_rotated_at", comment: "When the account was last re-wrapped to a new transit key version."
    t.string "transit_key_version", comment: "Vault transit key version (e.g. 'v1', 'v2') currently wrapping this account's encryption key. Null = pre-rotation backfill needed."
    t.datetime "updated_at", null: false
    t.index ["ai_suspended"], name: "index_accounts_on_ai_suspended", where: "(ai_suspended = true)"
    t.index ["analytics_tier"]
    t.index ["encryption_key_vault_path"], name: "index_accounts_on_encryption_key_vault_path", unique: true, where: "(encryption_key_vault_path IS NOT NULL)"
    t.index ["paypal_customer_id"], name: "index_accounts_on_paypal_customer_id", unique: true, where: "(paypal_customer_id IS NOT NULL)"
    t.index ["status"]
    t.index ["stripe_customer_id"], name: "index_accounts_on_stripe_customer_id", unique: true, where: "(stripe_customer_id IS NOT NULL)"
    t.index ["subdomain"], name: "index_accounts_on_subdomain", unique: true, where: "((subdomain IS NOT NULL) AND ((subdomain)::text <> ''::text))"
    t.index ["transit_key_version"], name: "index_accounts_on_transit_key_version", where: "(transit_key_version IS NOT NULL)"
    t.check_constraint "analytics_tier::text = ANY (ARRAY['free'::text, 'starter'::text, 'pro'::text, 'business'::text])", name: "check_analytics_tier"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'cancelled'::character varying::text, 'suspended'::character varying::text])", name: "valid_account_status"
  end

  create_table "api_key_usages", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "api_key_id", null: false
    t.datetime "created_at", null: false
    t.string "endpoint", limit: 500, null: false
    t.string "ip_address", limit: 45
    t.string "method", limit: 10, null: false
    t.integer "request_count", default: 1, null: false
    t.jsonb "request_params", default: {}
    t.integer "response_status", null: false
    t.integer "response_time_ms"
    t.datetime "updated_at", null: false
    t.datetime "used_at", null: false
    t.string "user_agent", limit: 1000
    t.index ["api_key_id", "used_at"]
    t.index ["api_key_id"]
    t.index ["endpoint"]
    t.index ["response_status"]
    t.index ["used_at"]
  end

  create_table "api_keys", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "allowed_ips", default: []
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.datetime "expires_at"
    t.boolean "is_active", default: true
    t.string "key_digest", null: false
    t.string "key_prefix", limit: 20
    t.string "key_suffix", limit: 20
    t.datetime "last_used_at"
    t.string "last_used_ip", limit: 45
    t.jsonb "metadata", default: {}
    t.string "name", limit: 255, null: false
    t.jsonb "permissions", default: []
    t.string "prefix", limit: 20, null: false
    t.integer "rate_limit_per_day"
    t.integer "rate_limit_per_hour"
    t.jsonb "rate_limits", default: {}
    t.jsonb "scopes", default: []
    t.datetime "updated_at", null: false
    t.integer "usage_count", default: 0
    t.index ["account_id"]
    t.index ["allowed_ips"], name: "idx_api_keys_on_allowed_ips", using: :gin
    t.index ["created_by_id"]
    t.index ["expires_at"]
    t.index ["is_active"]
    t.index ["key_digest"], unique: true
    t.index ["key_prefix"]
    t.index ["key_suffix"]
    t.index ["permissions"], name: "idx_api_keys_on_permissions", using: :gin
    t.index ["prefix"], unique: true
    t.index ["scopes"], name: "idx_api_keys_on_scopes", using: :gin
    t.index ["usage_count"]
    t.check_constraint "rate_limit_per_day IS NULL OR rate_limit_per_day > 0", name: "valid_api_key_daily_limit"
    t.check_constraint "rate_limit_per_hour IS NULL OR rate_limit_per_hour > 0", name: "valid_api_key_hourly_limit"
    t.check_constraint "usage_count >= 0", name: "valid_api_key_usage_count"
  end

  create_table "blacklisted_tokens", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "reason", default: "logout"
    t.string "token", null: false
    t.uuid "user_id", null: false
    t.index ["expires_at"]
    t.index ["token"], unique: true
    t.index ["user_id"]
  end

  create_table "data_deletion_requests", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "approved_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.jsonb "data_types_to_delete", default: []
    t.jsonb "data_types_to_retain", default: []
    t.jsonb "deletion_log", default: []
    t.string "deletion_type", default: "full", null: false
    t.text "error_message"
    t.datetime "grace_period_ends_at"
    t.boolean "grace_period_extended", default: false
    t.jsonb "metadata", default: {}
    t.uuid "processed_by_id"
    t.datetime "processing_started_at"
    t.text "reason"
    t.text "rejection_reason"
    t.uuid "requested_by_id"
    t.jsonb "retention_log", default: []
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["account_id"]
    t.index ["deletion_type"]
    t.index ["grace_period_ends_at"]
    t.index ["processed_by_id"]
    t.index ["requested_by_id"]
    t.index ["status"]
    t.index ["user_id"]
  end

  create_table "data_export_requests", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "download_token"
    t.datetime "download_token_expires_at"
    t.datetime "downloaded_at"
    t.text "error_message"
    t.jsonb "exclude_data_types", default: []
    t.datetime "expires_at"
    t.string "export_type", default: "full"
    t.string "file_path"
    t.integer "file_size_bytes"
    t.string "format", default: "json", null: false
    t.jsonb "include_data_types", default: []
    t.jsonb "metadata", default: {}
    t.datetime "processing_started_at"
    t.uuid "requested_by_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["account_id"]
    t.index ["download_token"], name: "index_data_export_requests_on_download_token", unique: true, where: "(download_token IS NOT NULL)"
    t.index ["expires_at"]
    t.index ["requested_by_id"]
    t.index ["status"]
    t.index ["user_id"]
  end

  create_table "delegation_permissions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_delegation_id", null: false
    t.datetime "created_at", null: false
    t.string "permission_name", limit: 100, null: false
    t.datetime "updated_at", null: false
    t.index ["account_delegation_id", "permission_name"], unique: true, name: "idx_on_account_delegation_id_permission_name"
    t.index ["account_delegation_id"]
    t.index ["permission_name"]
  end

  create_table "external_agents", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "agent_card_url", null: false
    t.string "auth_token_encrypted"
    t.jsonb "authentication", default: {}
    t.decimal "avg_response_time_ms", precision: 10, scale: 2
    t.jsonb "cached_card", default: {}
    t.jsonb "capabilities", default: {}
    t.datetime "card_cached_at"
    t.string "card_version"
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.text "description"
    t.integer "failure_count", default: 0
    t.jsonb "health_details", default: {}
    t.string "health_status"
    t.datetime "last_health_check"
    t.jsonb "metadata", default: {}
    t.string "name", limit: 255, null: false
    t.jsonb "skills", default: []
    t.string "slug", limit: 150
    t.string "status", default: "active", null: false
    t.integer "success_count", default: 0
    t.integer "task_count", default: 0
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], unique: true
    t.index ["account_id"]
    t.index ["agent_card_url"]
    t.index ["capabilities"], name: "index_external_agents_on_capabilities", using: :gin
    t.index ["created_by_id"]
    t.index ["skills"], name: "index_external_agents_on_skills", using: :gin
    t.index ["slug"], name: "index_external_agents_on_slug", unique: true, where: "(slug IS NOT NULL)"
    t.index ["status"]
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'error'::character varying::text, 'unreachable'::character varying::text])", name: "external_agents_status_check"
  end

  create_table "federation_partners", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.integer "agent_count", default: 0
    t.jsonb "allowed_capabilities", default: []
    t.datetime "approved_at"
    t.uuid "approved_by_id"
    t.boolean "auto_approve_agents", default: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.string "endpoint_url", null: false
    t.string "federation_token_hash"
    t.datetime "last_request_at"
    t.datetime "last_sync_at"
    t.integer "max_requests_per_hour", default: 1000
    t.string "name", null: false
    t.string "organization_id", null: false
    t.text "public_key"
    t.integer "request_count", default: 0
    t.string "status", default: "pending"
    t.jsonb "tls_config", default: {}
    t.integer "trust_level", default: 1
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["approved_by_id"]
    t.index ["created_by_id"]
    t.index ["organization_id"], unique: true
    t.index ["status"]
    t.index ["trust_level"]
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'active'::character varying::text, 'suspended'::character varying::text, 'revoked'::character varying::text])", name: "federation_partners_status_check"
    t.check_constraint "trust_level >= 1 AND trust_level <= 5", name: "federation_partners_trust_check"
  end

  create_table "impersonation_sessions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "ended_at"
    t.uuid "impersonated_user_id", null: false
    t.uuid "impersonator_id", null: false
    t.string "ip_address"
    t.string "reason"
    t.string "session_token", null: false
    t.datetime "started_at", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["ended_at"]
    t.index ["impersonated_user_id"]
    t.index ["impersonator_id"]
    t.index ["session_token"], unique: true
    t.index ["started_at"]
  end

  create_table "invitations", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "accepted_at"
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "expires_at"
    t.string "first_name"
    t.uuid "inviter_id", null: false
    t.string "last_name"
    t.jsonb "role_names", default: ["member"]
    t.string "status", default: "pending"
    t.string "token", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["email", "account_id"], unique: true
    t.index ["expires_at"]
    t.index ["inviter_id"]
    t.index ["role_names"], name: "index_invitations_on_role_names", using: :gin
    t.index ["status"]
    t.index ["token_digest"], unique: true
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'accepted'::character varying::text, 'expired'::character varying::text, 'cancelled'::character varying::text])", name: "valid_invitation_status"
  end

  create_table "jwt_blacklists", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "jti", limit: 100, null: false
    t.text "metadata"
    t.string "reason", limit: 100
    t.datetime "updated_at", null: false
    t.boolean "user_blacklist", default: false, null: false
    t.uuid "user_id"
    t.index ["expires_at"]
    t.index ["jti", "expires_at"]
    t.index ["jti"], unique: true
    t.index ["user_id", "user_blacklist"]
  end

  create_table "oauth_access_grants", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "application_id", null: false
    t.string "code_challenge"
    t.string "code_challenge_method"
    t.datetime "created_at", null: false
    t.integer "expires_in", null: false
    t.text "redirect_uri", null: false
    t.uuid "resource_owner_id", null: false
    t.datetime "revoked_at"
    t.string "scopes", default: "", null: false
    t.string "token", null: false
    t.index ["application_id"]
    t.index ["resource_owner_id"]
    t.index ["token"], unique: true
  end

  create_table "oauth_access_tokens", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "application_id"
    t.datetime "created_at", null: false
    t.inet "created_from_ip"
    t.integer "expires_in"
    t.string "previous_refresh_token", default: "", null: false
    t.string "refresh_token"
    t.uuid "resource_owner_id"
    t.datetime "revoked_at"
    t.string "scopes"
    t.string "token", null: false
    t.string "user_agent"
    t.index ["application_id", "created_at"]
    t.index ["application_id"]
    t.index ["refresh_token"], unique: true
    t.index ["resource_owner_id"]
    t.index ["revoked_at"]
    t.index ["token"], unique: true
  end

  create_table "oauth_applications", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.boolean "confidential", default: true, null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.boolean "machine_client", default: false, null: false
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.uuid "owner_id"
    t.string "owner_type"
    t.string "rate_limit_tier", default: "standard"
    t.text "redirect_uri"
    t.string "scopes", default: "", null: false
    t.string "secret", null: false
    t.string "status", default: "active", null: false
    t.boolean "trusted", default: false, null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"]
    t.index ["owner_type", "owner_id"]
    t.index ["status"]
    t.index ["trusted"]
    t.index ["uid"], unique: true
  end

  create_table "password_histories", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "password_digest", null: false
    t.uuid "user_id", null: false
    t.index ["created_at"]
    t.index ["user_id"]
  end

  create_table "role_permissions", id: false, force: :cascade do |t|
    t.datetime "granted_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "permission_name", limit: 100, null: false
    t.uuid "role_id", null: false
    t.index ["permission_name"]
    t.index ["role_id", "permission_name"], unique: true
    t.index ["role_id"]
  end

  create_table "roles", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "display_name", limit: 100
    t.boolean "immutable", default: false, null: false
    t.boolean "is_system", default: false, null: false
    t.string "name", limit: 100, null: false
    t.string "role_type", limit: 20
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], unique: true, where: "(account_id IS NOT NULL)"
    t.index ["account_id"]
    t.index ["name"], unique: true, where: "(account_id IS NULL)", name: "index_roles_on_name_global"
  end

  create_table "terms_acceptances", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "accepted_at", null: false
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.string "document_hash"
    t.string "document_type", null: false
    t.string "document_version", null: false
    t.string "ip_address"
    t.jsonb "metadata", default: {}
    t.datetime "superseded_at"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.uuid "user_id", null: false
    t.index ["account_id"]
    t.index ["document_type"]
    t.index ["document_version"]
    t.index ["user_id", "document_type", "document_version"], unique: true
    t.index ["user_id", "document_type"]
    t.index ["user_id"]
  end

  create_table "user_consents", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "collection_method", null: false
    t.text "consent_text"
    t.string "consent_type", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.boolean "granted", default: false, null: false
    t.datetime "granted_at"
    t.string "ip_address"
    t.jsonb "metadata", default: {}
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.uuid "user_id", null: false
    t.string "version"
    t.datetime "withdrawn_at"
    t.index ["account_id", "consent_type"]
    t.index ["account_id"]
    t.index ["consent_type"]
    t.index ["expires_at"]
    t.index ["granted"]
    t.index ["user_id", "consent_type"]
    t.index ["user_id"]
  end

  create_table "user_roles", id: false, force: :cascade do |t|
    t.datetime "granted_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.uuid "granted_by_id"
    t.uuid "role_id", null: false
    t.uuid "user_id", null: false
    t.index ["granted_by_id"]
    t.index ["role_id"]
    t.index ["user_id", "role_id"], unique: true
    t.index ["user_id"]
  end

  create_table "user_tokens", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.inet "last_used_ip"
    t.jsonb "metadata", default: {}
    t.string "name", limit: 100
    t.text "permissions"
    t.boolean "revoked", default: false
    t.datetime "revoked_at"
    t.string "revoked_reason", limit: 100
    t.string "scopes", limit: 500
    t.string "token_digest", limit: 128, null: false
    t.string "token_type", limit: 20, default: "access", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent", limit: 500
    t.uuid "user_id", null: false
    t.index ["created_at"]
    t.index ["expires_at"]
    t.index ["last_used_at"]
    t.index ["revoked"]
    t.index ["token_digest"], unique: true
    t.index ["token_type"]
    t.index ["user_id", "token_type"]
    t.index ["user_id"]
    t.check_constraint "expires_at > created_at", name: "valid_expiration"
    t.check_constraint "length(token_digest::text) >= 32", name: "valid_token_digest_length"
    t.check_constraint "token_type::text = ANY (ARRAY['access'::character varying::text, 'refresh'::character varying::text, 'api_key'::character varying::text, '2fa'::character varying::text, 'impersonation'::character varying::text, 'mcp'::character varying::text])", name: "valid_token_type"
  end

  create_table "users", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "authorized_keys", default: [], null: false
    t.text "backup_codes"
    t.datetime "created_at", null: false
    t.string "email", limit: 255, null: false
    t.datetime "email_verification_sent_at"
    t.string "email_verification_token", limit: 255
    t.datetime "email_verification_token_expires_at"
    t.boolean "email_verified", default: false, null: false
    t.datetime "email_verified_at"
    t.integer "failed_login_attempts", default: 0, null: false
    t.datetime "last_login_at"
    t.string "last_login_ip", limit: 45
    t.datetime "locked_until"
    t.string "name", default: "", null: false
    t.text "notification_preferences"
    t.datetime "password_changed_at"
    t.string "password_digest", null: false
    t.text "preferences"
    t.string "reset_token_digest"
    t.datetime "reset_token_expires_at"
    t.string "status", limit: 20, default: "active", null: false
    t.datetime "two_factor_backup_codes_generated_at"
    t.boolean "two_factor_enabled", default: false, null: false
    t.datetime "two_factor_enabled_at"
    t.string "two_factor_secret"
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["email"], unique: true
    t.index ["email_verification_token"], name: "index_users_on_email_verification_token", unique: true, where: "(email_verification_token IS NOT NULL)"
    t.index ["reset_token_digest"], name: "index_users_on_reset_token_digest", unique: true, where: "(reset_token_digest IS NOT NULL)"
    t.index ["status"]
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'suspended'::character varying::text, 'pending_verification'::character varying::text])", name: "valid_user_status"
  end

    add_foreign_key "account_delegations", "accounts", column: "account_id"
    add_foreign_key "account_delegations", "roles", column: "role_id"
    add_foreign_key "account_delegations", "users", column: "delegated_by_id"
    add_foreign_key "account_delegations", "users", column: "delegated_user_id"
    add_foreign_key "account_delegations", "users", column: "revoked_by_id"
    add_foreign_key "account_terminations", "accounts", column: "account_id"
    add_foreign_key "account_terminations", "data_export_requests", column: "data_export_request_id"
    add_foreign_key "account_terminations", "users", column: "cancelled_by_id"
    add_foreign_key "account_terminations", "users", column: "processed_by_id"
    add_foreign_key "account_terminations", "users", column: "requested_by_id"
    add_foreign_key "api_key_usages", "api_keys", column: "api_key_id"
    add_foreign_key "api_keys", "accounts", column: "account_id"
    add_foreign_key "api_keys", "users", column: "created_by_id"
    add_foreign_key "blacklisted_tokens", "users", column: "user_id"
    add_foreign_key "data_deletion_requests", "accounts", column: "account_id"
    add_foreign_key "data_deletion_requests", "users", column: "processed_by_id"
    add_foreign_key "data_deletion_requests", "users", column: "requested_by_id"
    add_foreign_key "data_deletion_requests", "users", column: "user_id"
    add_foreign_key "data_export_requests", "accounts", column: "account_id"
    add_foreign_key "data_export_requests", "users", column: "requested_by_id"
    add_foreign_key "data_export_requests", "users", column: "user_id"
    add_foreign_key "delegation_permissions", "account_delegations", column: "account_delegation_id"
    add_foreign_key "external_agents", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "external_agents", "users", column: "created_by_id", on_delete: :nullify
    add_foreign_key "federation_partners", "accounts", column: "account_id"
    add_foreign_key "federation_partners", "users", column: "approved_by_id"
    add_foreign_key "federation_partners", "users", column: "created_by_id"
    add_foreign_key "impersonation_sessions", "users", column: "impersonated_user_id"
    add_foreign_key "impersonation_sessions", "users", column: "impersonator_id"
    add_foreign_key "invitations", "accounts", column: "account_id"
    add_foreign_key "invitations", "users", column: "inviter_id"
    add_foreign_key "jwt_blacklists", "users", column: "user_id", on_delete: :nullify
    add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
    add_foreign_key "oauth_access_grants", "users", column: "resource_owner_id", on_delete: :cascade
    add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
    add_foreign_key "oauth_access_tokens", "users", column: "resource_owner_id", on_delete: :cascade
    add_foreign_key "password_histories", "users", column: "user_id"
    add_foreign_key "role_permissions", "roles", column: "role_id"
    add_foreign_key "roles", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "terms_acceptances", "accounts", column: "account_id"
    add_foreign_key "terms_acceptances", "users", column: "user_id"
    add_foreign_key "user_consents", "accounts", column: "account_id"
    add_foreign_key "user_consents", "users", column: "user_id"
    add_foreign_key "user_roles", "roles", column: "role_id"
    add_foreign_key "user_roles", "users", column: "granted_by_id"
    add_foreign_key "user_roles", "users", column: "user_id"
    add_foreign_key "user_tokens", "users", column: "user_id"
    add_foreign_key "users", "accounts", column: "account_id"
  end
end
