# frozen_string_literal: true
class CoreBaseline < ActiveRecord::Migration[8.1]
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

  create_table "account_git_webhook_configs", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "branch_filter"
    t.string "branch_filter_type", default: "none"
    t.string "content_type", default: "application/json", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.jsonb "custom_headers", default: {}, null: false
    t.text "description"
    t.jsonb "event_types", default: [], null: false
    t.integer "failure_count", default: 0, null: false
    t.boolean "is_active", default: true, null: false
    t.datetime "last_delivery_at"
    t.string "name", null: false
    t.string "retry_backoff", default: "exponential", null: false
    t.integer "retry_limit", default: 3, null: false
    t.string "secret_key", null: false
    t.string "signature_secret"
    t.string "status", default: "active", null: false
    t.integer "success_count", default: 0, null: false
    t.integer "timeout_seconds", default: 30, null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["created_by_id"]
    t.check_constraint "branch_filter_type::text = ANY (ARRAY['none'::character varying::text, 'exact'::character varying::text, 'wildcard'::character varying::text, 'regex'::character varying::text])", name: "account_git_webhook_configs_branch_filter_type_check"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text])", name: "account_git_webhook_configs_status_check"
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

  create_table "admin_settings", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "category", limit: 100
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "is_encrypted", default: false
    t.boolean "is_public", default: false
    t.string "key", limit: 255, null: false
    t.string "setting_type", limit: 50, default: "string"
    t.integer "sort_order", default: 0
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["category"]
    t.index ["is_public"]
    t.index ["key"], unique: true
    t.index ["setting_type"]
    t.index ["sort_order"]
    t.check_constraint "setting_type::text = ANY (ARRAY['string'::character varying::text, 'text'::character varying::text, 'integer'::character varying::text, 'boolean'::character varying::text, 'json'::character varying::text, 'array'::character varying::text])", name: "valid_admin_setting_type"
  end

  create_table "ai_a2a_task_events", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "ai_a2a_task_id", null: false
    t.string "artifact_id"
    t.string "artifact_mime_type"
    t.string "artifact_name"
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.string "event_id"
    t.string "event_type", null: false
    t.text "message"
    t.string "new_status"
    t.string "previous_status"
    t.integer "progress_current"
    t.string "progress_message"
    t.integer "progress_total"
    t.datetime "updated_at", null: false
    t.index ["ai_a2a_task_id", "created_at"]
    t.index ["ai_a2a_task_id"]
    t.index ["event_id"]
    t.index ["event_type"]
    t.check_constraint "event_type::text = ANY (ARRAY['status_change'::character varying::text, 'artifact_added'::character varying::text, 'message'::character varying::text, 'progress'::character varying::text, 'error'::character varying::text, 'cancelled'::character varying::text])", name: "ai_a2a_task_events_type_check"
  end

  create_table "ai_a2a_tasks", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "artifacts", default: [], null: false
    t.uuid "chat_message_id"
    t.uuid "chat_session_id"
    t.uuid "community_agent_id"
    t.datetime "completed_at"
    t.uuid "container_instance_id"
    t.decimal "cost", precision: 12, scale: 6, default: "0.0"
    t.datetime "created_at", null: false
    t.jsonb "dag_dependencies", default: []
    t.jsonb "dag_dependents", default: []
    t.uuid "dag_execution_id"
    t.string "dag_node_id"
    t.integer "duration_ms"
    t.string "error_code"
    t.jsonb "error_details", default: {}
    t.text "error_message"
    t.integer "execution_order"
    t.jsonb "external_authentication", default: {}
    t.string "external_endpoint_url"
    t.uuid "federation_partner_id"
    t.string "federation_task_id"
    t.uuid "from_agent_card_id"
    t.uuid "from_agent_id"
    t.jsonb "history", default: [], null: false
    t.jsonb "input", default: {}, null: false
    t.boolean "is_external", default: false, null: false
    t.integer "max_retries", default: 3, null: false
    t.jsonb "message", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "output", default: {}, null: false
    t.uuid "parent_task_id"
    t.jsonb "push_notification_config", default: {}
    t.integer "retry_count", default: 0, null: false
    t.integer "sequence_number"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.string "task_id", null: false
    t.uuid "to_agent_card_id"
    t.uuid "to_agent_id"
    t.integer "tokens_used", default: 0
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["created_at"]
    t.index ["dag_execution_id", "execution_order"], name: "index_ai_a2a_tasks_on_dag_execution_id_and_execution_order", where: "(dag_execution_id IS NOT NULL)"
    t.index ["dag_execution_id"], name: "index_ai_a2a_tasks_on_dag_execution_id", where: "(dag_execution_id IS NOT NULL)"
    t.index ["federation_task_id"], name: "index_ai_a2a_tasks_on_federation_task_id", where: "(federation_task_id IS NOT NULL)"
    t.index ["from_agent_card_id"]
    t.index ["from_agent_id", "status"]
    t.index ["from_agent_id"]
    t.index ["is_external"]
    t.index ["parent_task_id"]
    t.index ["task_id"], unique: true
    t.index ["to_agent_card_id"]
    t.index ["to_agent_id", "status"]
    t.index ["to_agent_id"]
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'active'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text, 'input_required'::character varying::text])", name: "ai_a2a_tasks_status_check"
  end

  create_table "ai_ab_tests", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.text "description"
    t.datetime "ended_at"
    t.string "name", null: false
    t.jsonb "results", default: {}
    t.datetime "started_at"
    t.float "statistical_significance"
    t.string "status", default: "draft", null: false
    t.jsonb "success_metrics", default: []
    t.uuid "target_id", null: false
    t.string "target_type", null: false
    t.string "test_id", null: false
    t.integer "total_conversions", default: 0
    t.integer "total_impressions", default: 0
    t.jsonb "traffic_allocation", default: {}
    t.datetime "updated_at", null: false
    t.jsonb "variants", default: []
    t.string "winning_variant"
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["created_by_id"]
    t.index ["target_type", "target_id"]
    t.index ["test_id"], unique: true
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'running'::character varying::text, 'paused'::character varying::text, 'completed'::character varying::text, 'cancelled'::character varying::text])", name: "check_ab_test_status"
    t.check_constraint "target_type::text = ANY (ARRAY['workflow'::character varying::text, 'agent'::character varying::text, 'prompt'::character varying::text, 'model'::character varying::text, 'provider'::character varying::text])", name: "check_ab_target_type"
  end

  create_table "ai_agent_budgets", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "agent_id", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "USD"
    t.jsonb "metadata", default: {}
    t.uuid "parent_budget_id"
    t.datetime "period_end"
    t.datetime "period_start"
    t.string "period_type"
    t.integer "reserved_cents", default: 0
    t.integer "spent_cents", default: 0
    t.integer "total_budget_cents", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["agent_id"]
  end

  create_table "ai_agent_cards", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_agent_id"
    t.jsonb "authentication", default: {}, null: false
    t.decimal "avg_response_time_ms", precision: 10, scale: 2
    t.jsonb "capabilities", default: {}, null: false
    t.string "card_version", default: "1.0.0", null: false
    t.boolean "chat_gateway_enabled", default: false
    t.boolean "community_published", default: false
    t.boolean "container_execution", default: false
    t.datetime "created_at", null: false
    t.jsonb "default_input_modes", default: ["application/json"], null: false
    t.jsonb "default_output_modes", default: ["application/json"], null: false
    t.datetime "deprecated_at"
    t.text "description"
    t.text "documentation_url"
    t.string "endpoint_url"
    t.integer "failure_count", default: 0, null: false
    t.boolean "federation_enabled", default: false
    t.string "name", null: false
    t.string "protocol_version", default: "0.3", null: false
    t.string "provider_name"
    t.string "provider_url"
    t.datetime "published_at"
    t.string "status", default: "active", null: false
    t.integer "success_count", default: 0, null: false
    t.jsonb "tags", default: [], null: false
    t.integer "task_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "visibility", default: "private", null: false
    t.index ["account_id", "name"], unique: true
    t.index ["account_id"]
    t.index ["ai_agent_id"]
    t.index ["capabilities"], name: "index_ai_agent_cards_on_capabilities", using: :gin
    t.index ["protocol_version"]
    t.index ["status"]
    t.index ["tags"], name: "index_ai_agent_cards_on_tags", using: :gin
    t.index ["visibility"]
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'deprecated'::character varying::text])", name: "ai_agent_cards_status_check"
    t.check_constraint "visibility::text = ANY (ARRAY['private'::character varying::text, 'internal'::character varying::text, 'public'::character varying::text])", name: "ai_agent_cards_visibility_check"
  end

  create_table "ai_agent_connections", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.string "connection_type"
    t.datetime "created_at", null: false
    t.string "discovered_by"
    t.jsonb "metadata", default: {}
    t.uuid "source_id"
    t.string "source_type"
    t.string "status", default: "active"
    t.float "strength", default: 1.0
    t.uuid "target_id"
    t.string "target_type"
    t.datetime "updated_at", null: false
    t.index ["account_id", "connection_type"]
    t.index ["account_id"]
    t.index ["source_type", "source_id"]
    t.index ["target_type", "target_id"]
  end

  create_table "ai_agent_escalations", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "acknowledged_at"
    t.uuid "ai_agent_id", null: false
    t.jsonb "context", default: {}
    t.datetime "created_at", null: false
    t.integer "current_level", default: 0, null: false
    t.uuid "escalated_to_user_id"
    t.jsonb "escalation_chain", default: []
    t.string "escalation_type", null: false
    t.datetime "next_escalation_at"
    t.datetime "resolved_at"
    t.string "severity", default: "medium", null: false
    t.string "status", default: "open", null: false
    t.integer "timeout_hours"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["ai_agent_id"]
    t.index ["escalated_to_user_id"]
    t.index ["next_escalation_at"], name: "idx_ai_agent_escalations_due", where: "((status)::text = ANY (ARRAY[('open'::character varying)::text, ('acknowledged'::character varying)::text, ('in_progress'::character varying)::text]))"
    t.index ["severity"]
    t.index ["status"]
  end

  create_table "ai_agent_executions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_agent_id", null: false
    t.uuid "ai_provider_id", null: false
    t.datetime "completed_at", precision: nil
    t.decimal "cost_usd", precision: 10, scale: 4, default: "0.0"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.jsonb "error_details", default: {}
    t.text "error_message"
    t.jsonb "execution_context", default: {}
    t.string "execution_id", limit: 100, null: false
    t.jsonb "input_parameters", default: {}, null: false
    t.jsonb "output_data", default: {}
    t.uuid "parent_execution_id"
    t.jsonb "performance_metrics", default: {}
    t.datetime "started_at", precision: nil
    t.string "status", default: "pending", null: false
    t.integer "tokens_used", default: 0
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.integer "webhook_attempts", default: 0
    t.jsonb "webhook_data", default: {}
    t.datetime "webhook_last_attempt_at", precision: nil
    t.string "webhook_status"
    t.string "webhook_url"
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["ai_agent_id", "status"]
    t.index ["ai_agent_id"]
    t.index ["ai_provider_id"]
    t.index ["completed_at"]
    t.index ["execution_id"], unique: true
    t.index ["parent_execution_id"]
    t.index ["started_at"]
    t.index ["status"]
    t.index ["user_id"]
    t.index ["webhook_status"]
  end

  create_table "ai_agent_feedbacks", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_agent_id", null: false
    t.boolean "applied_to_trust", default: false, null: false
    t.text "comment"
    t.uuid "context_id"
    t.string "context_type"
    t.datetime "created_at", null: false
    t.string "feedback_type", null: false
    t.integer "rating", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["account_id"]
    t.index ["ai_agent_id", "applied_to_trust"]
    t.index ["ai_agent_id"]
    t.index ["context_type", "context_id"]
    t.index ["feedback_type"]
    t.index ["user_id"]
  end

  create_table "ai_agent_goals", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_agent_id", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.string "created_by_type"
    t.datetime "deadline"
    t.text "description"
    t.string "goal_type", null: false
    t.jsonb "metadata", default: {}
    t.uuid "parent_goal_id"
    t.integer "priority", default: 3, null: false
    t.decimal "progress", precision: 3, scale: 2, default: "0.0"
    t.string "status", default: "pending", null: false
    t.jsonb "success_criteria", default: {}
    t.string "title", limit: 255, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "goal_type"]
    t.index ["account_id"]
    t.index ["ai_agent_id", "status", "priority"]
    t.index ["ai_agent_id", "status"]
    t.index ["ai_agent_id"]
    t.index ["created_by_type", "created_by_id"]
    t.index ["parent_goal_id"]
  end

  create_table "ai_agent_identities", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "agent_id", null: false
    t.string "agent_uri"
    t.string "algorithm", default: "ed25519", null: false
    t.jsonb "attestation_claims", default: {}
    t.jsonb "capabilities", default: []
    t.datetime "created_at", null: false
    t.text "encrypted_private_key", null: false
    t.datetime "expires_at"
    t.string "key_fingerprint", null: false
    t.text "public_key", null: false
    t.string "revocation_reason"
    t.datetime "revoked_at"
    t.datetime "rotated_at"
    t.datetime "rotation_overlap_until"
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["agent_id", "status"]
    t.index ["agent_id"]
    t.index ["key_fingerprint"], unique: true
    t.index ["status"]
  end

  create_table "ai_agent_installations", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "agent_template_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "custom_config", default: {}
    t.integer "executions_count", default: 0
    t.uuid "installed_agent_id"
    t.uuid "installed_by_id"
    t.string "installed_version"
    t.datetime "last_updated_at"
    t.datetime "last_used_at"
    t.datetime "license_expires_at"
    t.string "license_type", default: "standard", null: false
    t.string "status", default: "active", null: false
    t.decimal "total_cost_usd", precision: 10, scale: 4, default: "0.0"
    t.datetime "updated_at", null: false
    t.jsonb "usage_stats", default: {}
    t.index ["account_id", "agent_template_id"], unique: true
    t.index ["account_id"]
    t.index ["agent_template_id"]
    t.index ["installed_agent_id"]
    t.index ["installed_by_id"]
    t.index ["license_expires_at"]
    t.index ["status"]
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'paused'::character varying::text, 'expired'::character varying::text, 'cancelled'::character varying::text, 'pending_update'::character varying::text])", name: "check_installation_status"
  end

  create_table "ai_agent_lineages", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "child_agent_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}
    t.uuid "parent_agent_id", null: false
    t.string "spawn_reason"
    t.datetime "spawned_at"
    t.datetime "terminated_at"
    t.string "termination_reason"
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["child_agent_id"]
    t.index ["parent_agent_id"]
  end

  create_table "ai_agent_model_performances", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "agent_type", limit: 50, null: false
    t.uuid "ai_provider_id", null: false
    t.datetime "created_at", null: false
    t.integer "failed_runs", default: 0, null: false
    t.datetime "last_run_at"
    t.string "model", limit: 120, null: false
    t.integer "successful_runs", default: 0, null: false
    t.decimal "total_cost_usd", precision: 14, scale: 6, default: "0.0", null: false
    t.bigint "total_duration_ms", default: 0, null: false
    t.integer "total_runs", default: 0, null: false
    t.bigint "total_tokens", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "ai_provider_id", "model", "agent_type"], unique: true
    t.index ["account_id"]
    t.index ["ai_provider_id"]
  end

  create_table "ai_agent_observations", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_agent_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}
    t.datetime "expires_at"
    t.uuid "goal_id"
    t.string "observation_type", null: false
    t.boolean "processed", default: false, null: false
    t.boolean "requires_action", default: false, null: false
    t.string "sensor_type", null: false
    t.string "severity", default: "info", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "severity"]
    t.index ["account_id"]
    t.index ["ai_agent_id", "processed"]
    t.index ["ai_agent_id", "sensor_type"]
    t.index ["ai_agent_id"]
    t.index ["expires_at"], name: "index_ai_agent_observations_on_expires_at", where: "(expires_at IS NOT NULL)"
    t.index ["goal_id"]
  end

  create_table "ai_agent_privilege_policies", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.boolean "active", default: true, null: false
    t.uuid "agent_id"
    t.jsonb "allowed_actions", default: []
    t.jsonb "allowed_resources", default: []
    t.jsonb "allowed_tools", default: []
    t.jsonb "communication_rules", default: {}
    t.datetime "created_at", null: false
    t.jsonb "denied_actions", default: []
    t.jsonb "denied_resources", default: []
    t.jsonb "denied_tools", default: []
    t.jsonb "escalation_rules", default: {}
    t.string "policy_name", null: false
    t.string "policy_type", default: "custom", null: false
    t.integer "priority", default: 0
    t.string "trust_tier"
    t.datetime "updated_at", null: false
    t.index ["account_id", "policy_name"], unique: true
    t.index ["account_id"]
    t.index ["agent_id"]
    t.index ["policy_type"]
    t.index ["trust_tier"]
  end

  create_table "ai_agent_proposals", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_agent_id", null: false
    t.uuid "conversation_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "impact_assessment", default: {}
    t.string "priority", default: "medium", null: false
    t.string "proposal_type", null: false
    t.jsonb "proposed_changes", default: {}
    t.text "rationale"
    t.datetime "review_deadline"
    t.datetime "reviewed_at"
    t.uuid "reviewed_by_id"
    t.string "status", default: "pending_review", null: false
    t.uuid "target_user_id"
    t.string "title", limit: 255, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["ai_agent_id"]
    t.index ["conversation_id"]
    t.index ["proposal_type"]
    t.index ["review_deadline"], name: "index_ai_agent_proposals_on_review_deadline", where: "((status)::text = 'pending_review'::text)"
    t.index ["reviewed_by_id"]
    t.index ["status"]
    t.index ["target_user_id"]
  end

  create_table "ai_agent_reviews", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "agent_template_id", null: false
    t.jsonb "cons", default: []
    t.text "content"
    t.datetime "created_at", null: false
    t.integer "helpful_count", default: 0
    t.uuid "installation_id"
    t.boolean "is_verified_purchase", default: false, null: false
    t.jsonb "metadata", default: {}
    t.jsonb "pros", default: []
    t.integer "rating", null: false
    t.integer "report_count", default: 0
    t.string "status", default: "published", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.datetime "verified_at"
    t.index ["account_id"]
    t.index ["agent_template_id", "account_id"], unique: true
    t.index ["agent_template_id", "status", "rating"]
    t.index ["agent_template_id"]
    t.index ["installation_id"]
    t.index ["status"]
    t.index ["user_id"]
    t.check_constraint "rating >= 1 AND rating <= 5", name: "check_review_rating"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'published'::character varying::text, 'hidden'::character varying::text, 'flagged'::character varying::text, 'removed'::character varying::text])", name: "check_review_status"
  end

  create_table "ai_agent_short_term_memories", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.integer "access_count", default: 0
    t.uuid "account_id", null: false
    t.uuid "agent_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "last_accessed_at"
    t.datetime "last_event_processed_at"
    t.string "memory_key", null: false
    t.string "memory_type", default: "general"
    t.jsonb "memory_value", null: false
    t.string "session_id", null: false
    t.integer "ttl_seconds", default: 3600
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["agent_id", "session_id", "memory_key"], unique: true
    t.index ["agent_id"]
    t.index ["expires_at"]
    t.index ["last_event_processed_at"]
  end

  create_table "ai_agent_skills", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "ai_agent_id", null: false
    t.uuid "ai_skill_id", null: false
    t.datetime "created_at", null: false
    t.boolean "is_active", default: true, null: false
    t.integer "priority", default: 0
    t.datetime "updated_at", null: false
    t.index ["ai_agent_id", "ai_skill_id"], unique: true
    t.index ["ai_agent_id"]
    t.index ["ai_skill_id"]
  end

  create_table "ai_agent_team_members", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "ai_agent_id", null: false, comment: "Agent assigned to this team role"
    t.uuid "ai_agent_team_id", null: false, comment: "Team this member belongs to"
    t.jsonb "capabilities", default: [], null: false, comment: "Specific capabilities this member provides to the team"
    t.datetime "created_at", null: false
    t.boolean "is_dynamic", default: false, null: false
    t.boolean "is_lead", default: false, null: false, comment: "Whether this member leads/coordinates the team"
    t.jsonb "member_config", default: {}, null: false, comment: "Member-specific configuration (retry_count, timeout, etc.)"
    t.integer "priority_order", default: 0, null: false, comment: "Execution priority (0 = highest, for sequential teams)"
    t.datetime "recruited_at"
    t.datetime "released_at"
    t.string "role", null: false, comment: "Role in team: manager, researcher, writer, reviewer, executor"
    t.datetime "updated_at", null: false
    t.index ["ai_agent_id"]
    t.index ["ai_agent_team_id", "ai_agent_id"], unique: true
    t.index ["ai_agent_team_id", "is_lead"]
    t.index ["ai_agent_team_id", "priority_order"]
    t.index ["ai_agent_team_id"]
  end

  create_table "ai_agent_teams", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false, comment: "Account that owns this team"
    t.string "communication_pattern", default: "hub_spoke"
    t.string "coordination_strategy", default: "manager_worker", null: false, comment: "Coordination pattern: manager_worker, peer_to_peer, hybrid"
    t.datetime "created_at", null: false
    t.text "description", comment: "Team purpose and capabilities description"
    t.jsonb "escalation_policy", default: {}
    t.text "goal_description", comment: "High-level goal the team works toward"
    t.jsonb "human_checkpoint_config", default: {}
    t.integer "max_parallel_tasks", default: 3
    t.string "name", null: false, comment: "Team name (e.g., \"Content Generation Crew\", \"Research Team\")"
    t.string "parallel_mode", default: "standard"
    t.jsonb "review_config", default: {}
    t.jsonb "shared_memory_config", default: {}
    t.jsonb "skill_graph_config", default: {}
    t.string "status", default: "active", null: false, comment: "Team status: active, inactive, archived"
    t.integer "task_timeout_seconds", default: 300
    t.jsonb "team_config", default: {}, null: false, comment: "Team-specific configuration (max_iterations, timeout, etc.)"
    t.string "team_topology", default: "hierarchical"
    t.string "team_type", default: "hierarchical", null: false, comment: "Team coordination type: hierarchical, mesh, sequential, parallel"
    t.uuid "template_id"
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["team_topology"]
    t.index ["team_type"]
    t.index ["template_id"]
    t.check_constraint "communication_pattern::text = ANY (ARRAY['hub_spoke'::character varying::text, 'peer_to_peer'::character varying::text, 'broadcast'::character varying::text, 'sequential'::character varying::text, 'event_driven'::character varying::text])", name: "check_communication_pattern"
    t.check_constraint "coordination_strategy::text = ANY (ARRAY['manager_led'::character varying::text, 'consensus'::character varying::text, 'auction'::character varying::text, 'round_robin'::character varying::text, 'priority_based'::character varying::text])", name: "check_coordination_strategy"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'archived'::character varying::text])", name: "ai_agent_teams_status_check"
    t.check_constraint "team_topology::text = ANY (ARRAY['hierarchical'::character varying::text, 'flat'::character varying::text, 'mesh'::character varying::text, 'pipeline'::character varying::text, 'hybrid'::character varying::text])", name: "check_team_topology_enum"
    t.check_constraint "team_type::text = ANY (ARRAY['hierarchical'::character varying::text, 'mesh'::character varying::text, 'sequential'::character varying::text, 'parallel'::character varying::text, 'workspace'::character varying::text])", name: "ai_agent_teams_team_type_check"
  end

  create_table "ai_agent_templates", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.integer "active_installations", default: 0
    t.jsonb "agent_config", default: {}
    t.float "average_rating"
    t.string "category"
    t.text "changelog"
    t.datetime "created_at", null: false
    t.jsonb "default_settings", default: {}
    t.text "description"
    t.datetime "featured_at"
    t.jsonb "features", default: []
    t.integer "installation_count", default: 0
    t.boolean "is_featured", default: false, null: false
    t.boolean "is_verified", default: false, null: false
    t.datetime "last_updated_at"
    t.jsonb "limitations", default: []
    t.text "long_description"
    t.decimal "monthly_price_usd", precision: 10, scale: 2
    t.string "name", null: false
    t.decimal "price_usd", precision: 10, scale: 2
    t.string "pricing_type", default: "free", null: false
    t.datetime "published_at"
    t.uuid "publisher_id", null: false
    t.jsonb "required_credentials", default: []
    t.jsonb "required_tools", default: []
    t.integer "review_count", default: 0
    t.jsonb "sample_prompts", default: []
    t.jsonb "screenshots", default: []
    t.text "setup_instructions"
    t.string "slug", null: false
    t.uuid "source_agent_id"
    t.string "status", default: "draft", null: false
    t.jsonb "supported_providers", default: []
    t.jsonb "tags", default: []
    t.datetime "updated_at", null: false
    t.string "version", default: "1.0.0", null: false
    t.string "vertical"
    t.string "visibility", default: "private", null: false
    t.index ["average_rating", "installation_count"]
    t.index ["category"]
    t.index ["is_featured"]
    t.index ["pricing_type"]
    t.index ["publisher_id"]
    t.index ["slug"], unique: true
    t.index ["source_agent_id"]
    t.index ["status", "visibility"]
    t.index ["vertical"]
    t.check_constraint "pricing_type::text = ANY (ARRAY['free'::character varying::text, 'one_time'::character varying::text, 'subscription'::character varying::text, 'usage_based'::character varying::text, 'freemium'::character varying::text])", name: "check_pricing_type"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'pending_review'::character varying::text, 'published'::character varying::text, 'rejected'::character varying::text, 'archived'::character varying::text, 'suspended'::character varying::text])", name: "check_template_status"
    t.check_constraint "visibility::text = ANY (ARRAY['private'::text, 'unlisted'::text, 'public'::text, 'business'::text])", name: "check_template_visibility"
  end

  create_table "ai_agent_trust_scores", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "agent_id", null: false
    t.decimal "cost_efficiency", precision: 5, scale: 4, default: "0.5"
    t.datetime "created_at", null: false
    t.integer "evaluation_count", default: 0
    t.jsonb "evaluation_history", default: []
    t.datetime "last_evaluated_at"
    t.decimal "overall_score", precision: 5, scale: 4, default: "0.5"
    t.decimal "quality", precision: 5, scale: 4, default: "0.5"
    t.decimal "reliability", precision: 5, scale: 4, default: "0.5"
    t.decimal "safety", precision: 5, scale: 4, default: "1.0"
    t.decimal "speed", precision: 5, scale: 4, default: "0.5"
    t.string "tier", default: "supervised"
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["agent_id"], unique: true
  end

  create_table "ai_agents", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "agent_type", limit: 50, null: false
    t.uuid "ai_provider_id", null: false
    t.jsonb "autonomy_config", default: {}
    t.jsonb "conversation_profile", default: {}, null: false
    t.datetime "created_at", null: false
    t.uuid "creator_id", null: false
    t.text "description"
    t.jsonb "execution_stats", default: {}
    t.jsonb "governance_scope", default: {}
    t.boolean "is_concierge", default: false, null: false
    t.boolean "is_governance", default: false, null: false
    t.boolean "is_public", default: false
    t.datetime "last_executed_at", precision: nil
    t.integer "max_spawn_depth", default: 3
    t.jsonb "mcp_input_schema", default: {}, null: false, comment: "JSON Schema for validating agent input parameters"
    t.jsonb "mcp_metadata", default: {}, null: false, comment: "Additional MCP-specific metadata"
    t.jsonb "mcp_output_schema", default: {}, null: false, comment: "JSON Schema for validating agent output"
    t.datetime "mcp_registered_at", precision: nil
    t.jsonb "mcp_tool_manifest", default: {}, null: false, comment: "Complete MCP tool manifest for agent registration"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", limit: 255, null: false
    t.uuid "parent_agent_id"
    t.string "slug", limit: 150, null: false
    t.string "status", default: "active", null: false
    t.string "termination_policy", default: "graceful"
    t.string "trust_level", default: "supervised"
    t.datetime "updated_at", null: false
    t.string "version", limit: 20, default: "1.0.0", null: false
    t.index ["account_id", "is_concierge"], name: "idx_ai_agents_concierge", where: "(is_concierge = true)"
    t.index ["account_id", "name"]
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["agent_type"]
    t.index ["ai_provider_id"]
    t.index ["creator_id"]
    t.index ["is_governance"], name: "idx_ai_agents_governance", where: "(is_governance = true)"
    t.index ["is_public"]
    t.index ["last_executed_at"]
    t.index ["mcp_registered_at"]
    t.index ["mcp_tool_manifest"], name: "index_ai_agents_on_mcp_tool_manifest", using: :gin
    t.index ["parent_agent_id"]
    t.index ["slug"], unique: true
    t.index ["status"]
  end

  create_table "ai_agui_events", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.jsonb "delta", default: {}
    t.string "event_type", null: false
    t.string "message_id"
    t.jsonb "metadata", default: {}
    t.string "role"
    t.string "run_id"
    t.integer "sequence_number", null: false
    t.uuid "session_id", null: false
    t.string "step_id"
    t.string "tool_call_id"
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["event_type"]
    t.index ["session_id", "sequence_number"], unique: true
    t.index ["session_id"]
  end

  create_table "ai_agui_sessions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "agent_id"
    t.jsonb "capabilities", default: {}
    t.datetime "completed_at"
    t.jsonb "context", default: []
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "last_event_at"
    t.jsonb "messages", default: []
    t.string "parent_run_id"
    t.string "run_id"
    t.integer "sequence_number", default: 0, null: false
    t.datetime "started_at"
    t.jsonb "state", default: {}
    t.string "status", default: "idle", null: false
    t.string "thread_id", null: false
    t.jsonb "tools", default: []
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["account_id"]
    t.index ["expires_at"]
    t.index ["status"]
    t.index ["thread_id"]
    t.index ["user_id"]
  end

  create_table "ai_approval_chains", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.text "description"
    t.boolean "is_sequential", default: true, null: false
    t.string "name", null: false
    t.string "status", default: "active", null: false
    t.jsonb "steps", default: []
    t.string "timeout_action", default: "reject"
    t.integer "timeout_hours"
    t.jsonb "trigger_conditions", default: {}
    t.string "trigger_type", null: false
    t.datetime "updated_at", null: false
    t.integer "usage_count", default: 0
    t.index ["account_id", "name"], unique: true
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["created_by_id"]
    t.index ["trigger_type"]
    t.check_constraint "trigger_type::text = ANY (ARRAY['workflow_deploy'::character varying::text, 'agent_deploy'::character varying::text, 'high_cost'::character varying::text, 'sensitive_data'::character varying::text, 'model_change'::character varying::text, 'policy_override'::character varying::text, 'manual'::character varying::text, 'autonomy_action'::character varying::text])", name: "check_chain_trigger_type"
  end

  create_table "ai_approval_decisions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "approval_request_id", null: false
    t.uuid "approver_id", null: false
    t.text "comments"
    t.jsonb "conditions", default: {}
    t.datetime "created_at", null: false
    t.string "decision", null: false
    t.integer "step_number", null: false
    t.datetime "updated_at", null: false
    t.index ["approval_request_id", "step_number"]
    t.index ["approval_request_id"]
    t.index ["approver_id", "created_at"]
    t.index ["approver_id"]
    t.check_constraint "decision::text = ANY (ARRAY['approved'::character varying::text, 'rejected'::character varying::text, 'delegated'::character varying::text, 'abstained'::character varying::text])", name: "check_decision_type"
  end

  create_table "ai_approval_requests", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "approval_chain_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "current_step", default: 0
    t.text "description"
    t.datetime "expires_at"
    t.jsonb "request_data", default: {}
    t.string "request_id", null: false
    t.uuid "requested_by_id"
    t.uuid "source_id"
    t.string "source_type"
    t.string "status", default: "pending", null: false
    t.jsonb "step_statuses", default: []
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["approval_chain_id", "created_at"]
    t.index ["approval_chain_id"]
    t.index ["expires_at"]
    t.index ["request_id"], unique: true
    t.index ["requested_by_id"]
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'approved'::character varying::text, 'rejected'::character varying::text, 'expired'::character varying::text, 'cancelled'::character varying::text])", name: "check_request_status"
  end

  create_table "ai_behavioral_fingerprints", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "agent_id", null: false
    t.integer "anomaly_count", default: 0, null: false
    t.float "baseline_mean", default: 0.0, null: false
    t.float "baseline_stddev", default: 1.0, null: false
    t.datetime "created_at", null: false
    t.float "deviation_threshold", default: 2.0, null: false
    t.datetime "last_observation_at"
    t.string "metric_name", null: false
    t.integer "observation_count", default: 0, null: false
    t.jsonb "recent_observations", default: [], null: false
    t.integer "rolling_window_days", default: 7, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "agent_id"]
    t.index ["account_id"]
    t.index ["agent_id", "metric_name"], unique: true
    t.index ["agent_id"]
  end

  create_table "ai_budget_transactions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_agent_budget_id", null: false
    t.uuid "ai_agent_execution_id"
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "running_balance_cents", null: false
    t.string "transaction_type", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["ai_agent_budget_id"]
    t.index ["ai_agent_execution_id"]
    t.index ["created_at"]
    t.index ["transaction_type"]
  end

  create_table "ai_circuit_breakers", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "action_type", null: false
    t.uuid "agent_id", null: false
    t.integer "cooldown_seconds", default: 300, null: false
    t.datetime "created_at", null: false
    t.integer "failure_count", default: 0, null: false
    t.integer "failure_threshold", default: 5, null: false
    t.datetime "half_opened_at"
    t.jsonb "history", default: [], null: false
    t.datetime "last_failure_at"
    t.datetime "last_success_at"
    t.datetime "opened_at"
    t.string "state", default: "closed", null: false
    t.integer "success_count", default: 0, null: false
    t.integer "success_threshold", default: 3, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "state"]
    t.index ["account_id"]
    t.index ["agent_id", "action_type"], unique: true
    t.index ["agent_id"]
    t.check_constraint "state::text = ANY (ARRAY['closed'::character varying::text, 'open'::character varying::text, 'half_open'::character varying::text])", name: "check_circuit_breaker_state"
  end

  create_table "ai_code_factory_evidence_manifests", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "artifacts", default: []
    t.jsonb "assertions", default: []
    t.datetime "captured_at"
    t.datetime "created_at", null: false
    t.string "manifest_type", null: false
    t.jsonb "metadata", default: {}
    t.uuid "review_state_id", null: false
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.jsonb "verification_result", default: {}
    t.datetime "verified_at"
    t.index ["account_id"]
    t.index ["review_state_id"]
  end

  create_table "ai_code_factory_harness_gaps", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.string "incident_id", null: false
    t.string "incident_source", null: false
    t.jsonb "metadata", default: {}
    t.text "resolution_notes"
    t.datetime "resolved_at"
    t.uuid "risk_contract_id"
    t.string "severity", default: "medium"
    t.datetime "sla_deadline"
    t.boolean "sla_met"
    t.string "status", default: "open"
    t.boolean "test_case_added", default: false
    t.string "test_case_reference"
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["incident_id"]
    t.index ["risk_contract_id"]
  end

  create_table "ai_code_factory_review_states", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.boolean "all_checks_passed", default: false
    t.integer "bot_threads_resolved", default: 0
    t.jsonb "completed_checks", default: []
    t.datetime "created_at", null: false
    t.integer "critical_findings_count", default: 0
    t.boolean "evidence_verified", default: false
    t.string "head_sha", null: false
    t.jsonb "metadata", default: {}
    t.uuid "mission_id"
    t.integer "pr_number", null: false
    t.integer "remediation_attempts", default: 0
    t.uuid "repository_id"
    t.jsonb "required_checks", default: []
    t.integer "review_findings_count", default: 0
    t.datetime "reviewed_at"
    t.uuid "risk_contract_id", null: false
    t.string "risk_tier"
    t.string "stale_reason"
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["mission_id"]
    t.index ["repository_id", "pr_number", "head_sha"], unique: true
    t.index ["repository_id"]
    t.index ["risk_contract_id"]
  end

  create_table "ai_code_factory_risk_contracts", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "activated_at"
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.jsonb "docs_drift_rules", default: {}
    t.jsonb "evidence_requirements", default: {}
    t.jsonb "merge_policy", default: {}
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.jsonb "preflight_config", default: {}
    t.jsonb "remediation_config", default: {}
    t.uuid "repository_id"
    t.jsonb "risk_tiers", default: []
    t.string "status", default: "draft"
    t.datetime "updated_at", null: false
    t.integer "version", default: 1
    t.index ["account_id", "repository_id", "status"]
    t.index ["account_id"]
    t.index ["created_by_id"]
    t.index ["repository_id"]
  end

  create_table "ai_code_review_comments", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.uuid "agent_id"
    t.string "category"
    t.string "comment_type"
    t.text "content"
    t.datetime "created_at", null: false
    t.string "file_path"
    t.integer "line_end"
    t.integer "line_start"
    t.jsonb "metadata", default: {}
    t.boolean "resolved", default: false
    t.string "severity"
    t.text "suggested_fix"
    t.uuid "task_review_id"
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["agent_id"]
    t.index ["task_review_id", "file_path"]
    t.index ["task_review_id"]
  end

  create_table "ai_code_reviews", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "base_branch"
    t.string "commit_sha"
    t.datetime "completed_at"
    t.decimal "cost_usd", precision: 10, scale: 4, default: "0.0"
    t.datetime "created_at", null: false
    t.integer "critical_issues", default: 0
    t.jsonb "file_analyses", default: []
    t.integer "files_reviewed", default: 0
    t.string "head_branch"
    t.jsonb "issues", default: []
    t.integer "issues_found", default: 0
    t.integer "lines_added", default: 0
    t.integer "lines_removed", default: 0
    t.string "overall_rating"
    t.uuid "pipeline_execution_id"
    t.string "pull_request_number"
    t.jsonb "quality_metrics", default: {}
    t.uuid "repository_id"
    t.string "review_id", null: false
    t.jsonb "security_findings", default: []
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.jsonb "suggestions", default: []
    t.integer "suggestions_count", default: 0
    t.text "summary"
    t.integer "tokens_used", default: 0
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"]
    t.index ["account_id"]
    t.index ["pipeline_execution_id"]
    t.index ["repository_id", "pull_request_number"]
    t.index ["review_id"], unique: true
    t.index ["status"]
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'analyzing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'partial'::character varying::text])", name: "check_review_status"
  end

  create_table "ai_collusion_indicators", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "agent_cluster", default: []
    t.decimal "correlation_score", precision: 5, scale: 4, default: "0.0"
    t.datetime "created_at", null: false
    t.jsonb "evidence_summary", default: {}
    t.string "indicator_type", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "indicator_type"]
    t.index ["account_id"]
  end

  create_table "ai_compliance_audit_entries", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "action_type", null: false
    t.jsonb "after_state", default: {}
    t.jsonb "before_state", default: {}
    t.jsonb "context", default: {}
    t.datetime "created_at", null: false
    t.text "description"
    t.string "entry_id", null: false
    t.string "ip_address"
    t.datetime "occurred_at", null: false
    t.string "outcome", null: false
    t.uuid "resource_id"
    t.string "resource_type", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.uuid "user_id"
    t.index ["account_id", "occurred_at"]
    t.index ["account_id"]
    t.index ["action_type"]
    t.index ["entry_id"], unique: true
    t.index ["outcome"]
    t.index ["resource_type", "resource_id"]
    t.index ["user_id"]
    t.check_constraint "outcome::text = ANY (ARRAY['success'::character varying::text, 'failure'::character varying::text, 'blocked'::character varying::text, 'warning'::character varying::text])", name: "check_audit_outcome"
  end

  create_table "ai_compliance_policies", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "actions", default: {}
    t.datetime "activated_at"
    t.jsonb "applies_to", default: {}
    t.string "category"
    t.jsonb "conditions", default: {}
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.text "description"
    t.string "enforcement_level", default: "warn", null: false
    t.jsonb "exceptions", default: []
    t.boolean "is_required", default: false, null: false
    t.boolean "is_system", default: false, null: false
    t.datetime "last_triggered_at"
    t.string "name", null: false
    t.string "policy_type", null: false
    t.integer "priority", default: 0
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.integer "violation_count", default: 0
    t.index ["account_id", "name"], unique: true
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["created_by_id"]
    t.index ["enforcement_level"]
    t.index ["is_system"]
    t.index ["policy_type"]
    t.check_constraint "enforcement_level::text = ANY (ARRAY['log'::character varying::text, 'warn'::character varying::text, 'block'::character varying::text, 'require_approval'::character varying::text])", name: "check_enforcement_level"
    t.check_constraint "policy_type::text = ANY (ARRAY['data_access'::character varying::text, 'model_usage'::character varying::text, 'output_filter'::character varying::text, 'rate_limit'::character varying::text, 'cost_limit'::character varying::text, 'approval_required'::character varying::text, 'retention'::character varying::text, 'audit'::character varying::text, 'custom'::character varying::text])", name: "check_policy_type"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'active'::character varying::text, 'disabled'::character varying::text, 'archived'::character varying::text])", name: "check_policy_status"
  end

  create_table "ai_compliance_reports", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "file_path"
    t.bigint "file_size_bytes"
    t.string "format", default: "pdf", null: false
    t.datetime "generated_at"
    t.uuid "generated_by_id"
    t.datetime "period_end"
    t.datetime "period_start"
    t.jsonb "report_config", default: {}
    t.string "report_id", null: false
    t.string "report_type", null: false
    t.string "status", default: "generating", null: false
    t.jsonb "summary_data", default: {}
    t.datetime "updated_at", null: false
    t.index ["account_id", "report_type"]
    t.index ["account_id"]
    t.index ["generated_at"]
    t.index ["generated_by_id"]
    t.index ["report_id"], unique: true
    t.index ["status"]
    t.check_constraint "report_type::text = ANY (ARRAY['soc2'::character varying::text, 'hipaa'::character varying::text, 'gdpr'::character varying::text, 'pci_dss'::character varying::text, 'iso27001'::character varying::text, 'custom'::character varying::text, 'audit_summary'::character varying::text, 'violation_summary'::character varying::text, 'data_inventory'::character varying::text])", name: "check_report_type"
    t.check_constraint "status::text = ANY (ARRAY['generating'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'expired'::character varying::text])", name: "check_report_status"
  end

  create_table "ai_compound_learnings", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.integer "access_count", default: 0, null: false
    t.uuid "account_id", null: false
    t.uuid "ai_agent_team_id"
    t.jsonb "applicable_domains", default: []
    t.string "category", null: false
    t.decimal "confidence_score", precision: 5, scale: 4, default: "0.5", null: false
    t.text "content", null: false
    t.text "contradiction_note"
    t.datetime "contradiction_resolved_at"
    t.datetime "created_at", null: false
    t.decimal "decay_rate", precision: 5, scale: 4, default: "0.003"
    t.datetime "disproven_at"
    t.uuid "disproven_by_id"
    t.decimal "effectiveness_score", precision: 5, scale: 4
    t.vector "embedding", limit: 1536
    t.datetime "expires_at"
    t.string "extraction_method"
    t.uuid "git_repository_id"
    t.decimal "importance_score", precision: 5, scale: 4, default: "0.5", null: false
    t.integer "injection_count", default: 0, null: false
    t.datetime "last_event_processed_at"
    t.datetime "last_injected_at"
    t.jsonb "metadata", default: {}
    t.integer "negative_outcome_count", default: 0, null: false
    t.integer "positive_outcome_count", default: 0, null: false
    t.datetime "promoted_at"
    t.string "scope", default: "team", null: false
    t.uuid "source_agent_id"
    t.uuid "source_execution_id"
    t.boolean "source_execution_successful"
    t.string "status", default: "active", null: false
    t.uuid "superseded_by_id"
    t.jsonb "tags", default: [], null: false
    t.string "title", limit: 255
    t.datetime "updated_at", null: false
    t.datetime "verified_at"
    t.uuid "verified_by_id"
    t.index ["account_id", "category"]
    t.index ["account_id", "scope"]
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["ai_agent_team_id", "category"]
    t.index ["ai_agent_team_id"]
    t.index ["applicable_domains"], name: "index_ai_compound_learnings_on_applicable_domains", using: :gin
    t.index ["effectiveness_score"]
    t.index ["embedding"], name: "idx_compound_learnings_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["git_repository_id"]
    t.index ["importance_score"]
    t.index ["last_event_processed_at"]
    t.index ["source_agent_id"]
    t.index ["source_execution_id"]
    t.index ["superseded_by_id"]
    t.index ["tags"], name: "index_ai_compound_learnings_on_tags", using: :gin
  end

  create_table "ai_context_access_logs", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "access_type"
    t.uuid "account_id", null: false
    t.string "action", null: false
    t.uuid "ai_agent_id"
    t.uuid "ai_context_entry_id"
    t.uuid "ai_persistent_context_id", null: false
    t.jsonb "changes_summary", default: {}
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "ip_address"
    t.jsonb "metadata", default: {}
    t.jsonb "new_value"
    t.jsonb "previous_value"
    t.string "request_id"
    t.boolean "success", default: true
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.uuid "user_id"
    t.index ["access_type"]
    t.index ["account_id", "created_at"]
    t.index ["account_id"]
    t.index ["action"]
    t.index ["ai_agent_id"]
    t.index ["ai_context_entry_id"]
    t.index ["ai_persistent_context_id", "action"]
    t.index ["ai_persistent_context_id"]
    t.index ["success"]
    t.index ["user_id"]
  end

  create_table "ai_context_entries", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.integer "access_count", default: 0
    t.uuid "ai_agent_id"
    t.uuid "ai_persistent_context_id", null: false
    t.datetime "archived_at"
    t.decimal "confidence_score", precision: 5, scale: 4, default: "1.0"
    t.jsonb "content", default: {}, null: false
    t.text "content_text"
    t.jsonb "context_tags", default: [], null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_user_id"
    t.decimal "decay_rate", precision: 5, scale: 4, default: "0.0"
    t.vector "embedding", limit: 1536
    t.string "entry_key", null: false
    t.string "entry_type"
    t.datetime "expires_at"
    t.decimal "importance_score", precision: 5, scale: 4, default: "0.5"
    t.datetime "last_accessed_at"
    t.datetime "last_relevance_update"
    t.string "memory_type", default: "factual"
    t.jsonb "metadata", default: {}
    t.boolean "outcome_success"
    t.uuid "previous_version_id"
    t.decimal "relevance_decay_rate", precision: 5, scale: 4, default: "0.0"
    t.string "source_id"
    t.string "source_type"
    t.jsonb "task_context", default: {}
    t.datetime "updated_at", null: false
    t.integer "version", default: 1
    t.index ["ai_agent_id"]
    t.index ["ai_persistent_context_id", "entry_key"], name: "idx_entries_context_key_active", unique: true, where: "(archived_at IS NULL)"
    t.index ["ai_persistent_context_id"]
    t.index ["archived_at"]
    t.index ["confidence_score"]
    t.index ["context_tags"], name: "index_ai_context_entries_on_context_tags", using: :gin
    t.index ["created_by_user_id"]
    t.index ["embedding"], name: "idx_context_entries_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["entry_type"]
    t.index ["expires_at"]
    t.index ["importance_score"]
    t.index ["memory_type"]
    t.index ["outcome_success"]
    t.index ["previous_version_id"]
    t.index ["source_type"]
    t.check_constraint "memory_type::text = ANY (ARRAY['factual'::character varying::text, 'experiential'::character varying::text, 'working'::character varying::text])", name: "ai_context_entries_memory_type_check"
  end

  create_table "ai_conversations", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "agent_team_id"
    t.uuid "ai_agent_id"
    t.uuid "ai_provider_id", null: false
    t.jsonb "conversation_context", default: {}
    t.string "conversation_id", limit: 100, null: false
    t.string "conversation_type", default: "agent", null: false
    t.datetime "created_at", null: false
    t.boolean "is_collaborative", default: false
    t.datetime "last_activity_at", precision: nil
    t.integer "message_count", default: 0
    t.jsonb "metadata", default: {}
    t.jsonb "participants", default: []
    t.datetime "pinned_at"
    t.string "status", default: "active", null: false
    t.text "summary"
    t.jsonb "tags", default: [], null: false
    t.string "title", limit: 255
    t.decimal "total_cost", precision: 10, scale: 4, default: "0.0"
    t.integer "total_tokens", default: 0
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.string "websocket_channel"
    t.uuid "websocket_session_id"
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["agent_team_id", "conversation_type"], name: "index_ai_conversations_on_team_type", where: "((conversation_type)::text = 'team'::text)"
    t.index ["agent_team_id"]
    t.index ["ai_agent_id"]
    t.index ["ai_provider_id"]
    t.index ["conversation_id"], unique: true
    t.index ["last_activity_at"]
    t.index ["participants"], name: "index_ai_conversations_on_participants", using: :gin
    t.index ["pinned_at"], name: "index_ai_conversations_on_pinned_at", where: "(pinned_at IS NOT NULL)"
    t.index ["status"]
    t.index ["tags"], name: "index_ai_conversations_on_tags", using: :gin
    t.index ["user_id", "status"]
    t.index ["user_id"]
    t.index ["websocket_channel"]
    t.index ["websocket_session_id"]
  end

  create_table "ai_cost_attributions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.decimal "amount_usd", precision: 12, scale: 6, null: false
    t.integer "api_calls"
    t.date "attribution_date", null: false
    t.integer "compute_minutes"
    t.string "cost_category", null: false
    t.decimal "cost_per_token", precision: 12, scale: 10
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "model_name"
    t.uuid "provider_id"
    t.uuid "roi_metric_id"
    t.uuid "source_id"
    t.string "source_name"
    t.string "source_type", null: false
    t.decimal "storage_gb", precision: 10, scale: 4
    t.integer "tokens_used"
    t.datetime "updated_at", null: false
    t.index ["account_id", "attribution_date"]
    t.index ["account_id"]
    t.index ["attribution_date"]
    t.index ["cost_category", "attribution_date"]
    t.index ["provider_id"]
    t.index ["roi_metric_id"]
    t.index ["source_type", "source_id"]
    t.check_constraint "cost_category::text = ANY (ARRAY['ai_inference'::character varying::text, 'ai_training'::character varying::text, 'embedding'::character varying::text, 'storage'::character varying::text, 'compute'::character varying::text, 'api_calls'::character varying::text, 'bandwidth'::character varying::text, 'other'::character varying::text])", name: "check_cost_category"
  end

  create_table "ai_cost_optimization_logs", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.decimal "actual_savings_usd", precision: 12, scale: 4
    t.jsonb "after_state", default: {}, null: false
    t.date "analysis_period_end"
    t.date "analysis_period_start"
    t.datetime "applied_at"
    t.jsonb "before_state", default: {}, null: false
    t.datetime "created_at", null: false
    t.decimal "current_cost_usd", precision: 12, scale: 4
    t.text "description"
    t.datetime "identified_at"
    t.string "optimization_type", null: false
    t.decimal "optimized_cost_usd", precision: 12, scale: 4
    t.decimal "potential_savings_usd", precision: 12, scale: 4
    t.jsonb "recommendation", default: {}, null: false
    t.uuid "resource_id"
    t.string "resource_type"
    t.decimal "savings_percentage", precision: 5, scale: 2
    t.string "status", default: "identified", null: false
    t.datetime "updated_at", null: false
    t.datetime "validated_at"
    t.index ["account_id", "optimization_type"]
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["created_at"]
    t.index ["resource_type", "resource_id"]
    t.check_constraint "optimization_type::text = ANY (ARRAY['provider_switch'::character varying::text, 'model_downgrade'::character varying::text, 'caching'::character varying::text, 'batching'::character varying::text, 'rate_optimization'::character varying::text, 'usage_reduction'::character varying::text])", name: "check_optimization_type"
    t.check_constraint "status::text = ANY (ARRAY['identified'::character varying::text, 'analyzing'::character varying::text, 'recommended'::character varying::text, 'applied'::character varying::text, 'validated'::character varying::text, 'rejected'::character varying::text, 'expired'::character varying::text])", name: "check_optimization_status"
  end

  create_table "ai_dag_executions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "checkpoint_data", default: {}
    t.datetime "completed_at"
    t.integer "completed_nodes", default: 0
    t.datetime "created_at", null: false
    t.jsonb "dag_definition", default: {}
    t.integer "duration_ms"
    t.text "error_message"
    t.jsonb "execution_plan", default: []
    t.integer "failed_nodes", default: 0
    t.jsonb "final_outputs", default: {}
    t.datetime "last_checkpoint_at"
    t.string "name"
    t.jsonb "node_states", default: {}
    t.boolean "resumable", default: true
    t.integer "running_nodes", default: 0
    t.jsonb "shared_context", default: {}
    t.datetime "started_at"
    t.string "status", default: "pending"
    t.integer "total_nodes", default: 0
    t.uuid "triggered_by_id"
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["status"]
    t.index ["triggered_by_id"]
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text])", name: "ai_dag_executions_status_check"
  end

  create_table "ai_data_classifications", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "classification_level", null: false
    t.uuid "classified_by_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "detection_count", default: 0
    t.jsonb "detection_patterns", default: []
    t.jsonb "handling_requirements", default: {}
    t.boolean "is_system", default: false, null: false
    t.string "name", null: false
    t.boolean "requires_audit", default: true, null: false
    t.boolean "requires_encryption", default: false, null: false
    t.boolean "requires_masking", default: false, null: false
    t.jsonb "retention_policy", default: {}
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], unique: true
    t.index ["account_id"]
    t.index ["classification_level"]
    t.index ["classified_by_id"]
    t.index ["is_system"]
    t.check_constraint "classification_level::text = ANY (ARRAY['public'::character varying::text, 'internal'::character varying::text, 'confidential'::character varying::text, 'restricted'::character varying::text, 'pii'::character varying::text, 'phi'::character varying::text, 'pci'::character varying::text])", name: "check_classification_level"
  end

  create_table "ai_data_connectors", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "connection_config", default: {}
    t.string "connector_type", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.integer "documents_synced", default: 0
    t.uuid "knowledge_base_id", null: false
    t.datetime "last_sync_at"
    t.jsonb "last_sync_result", default: {}
    t.string "name", null: false
    t.datetime "next_sync_at"
    t.string "status", default: "active", null: false
    t.jsonb "sync_config", default: {}
    t.integer "sync_errors", default: 0
    t.string "sync_frequency"
    t.datetime "updated_at", null: false
    t.index ["account_id", "connector_type"]
    t.index ["account_id"]
    t.index ["created_by_id"]
    t.index ["knowledge_base_id", "status"]
    t.index ["knowledge_base_id"]
    t.index ["next_sync_at"]
    t.check_constraint "connector_type::text = ANY (ARRAY['notion'::character varying::text, 'confluence'::character varying::text, 'google_drive'::character varying::text, 'dropbox'::character varying::text, 'github'::character varying::text, 's3'::character varying::text, 'database'::character varying::text, 'api'::character varying::text, 'web_scraper'::character varying::text])", name: "check_connector_type"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'paused'::character varying::text, 'error'::character varying::text, 'disconnected'::character varying::text])", name: "check_connector_status"
  end

  create_table "ai_data_detections", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "action_taken", default: "logged", null: false
    t.uuid "classification_id", null: false
    t.float "confidence_score"
    t.datetime "created_at", null: false
    t.string "detection_id", null: false
    t.jsonb "detection_metadata", default: {}
    t.string "field_path"
    t.text "masked_snippet"
    t.text "original_snippet"
    t.uuid "source_id", null: false
    t.string "source_type", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"]
    t.index ["account_id"]
    t.index ["action_taken"]
    t.index ["classification_id", "created_at"]
    t.index ["classification_id"]
    t.index ["detection_id"], unique: true
    t.index ["source_type"]
    t.check_constraint "action_taken::text = ANY (ARRAY['logged'::character varying::text, 'masked'::character varying::text, 'blocked'::character varying::text, 'encrypted'::character varying::text, 'flagged'::character varying::text])", name: "check_detection_action"
  end

  create_table "ai_data_source_config_versions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_data_source_id", null: false
    t.datetime "created_at", null: false
    t.string "created_by_type", limit: 20, default: "manual", null: false
    t.jsonb "manifest", default: {}, null: false
    t.string "note", limit: 500
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.index ["account_id"]
    t.index ["ai_data_source_id", "version"], unique: true
  end

  create_table "ai_data_source_credentials", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_data_source_id", null: false
    t.integer "consecutive_failures", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "encrypted_api_key"
    t.string "encrypted_api_secret"
    t.datetime "expires_at", precision: nil
    t.integer "failure_count", default: 0, null: false
    t.boolean "is_active", default: true, null: false
    t.boolean "is_default", default: false, null: false
    t.string "last_error", limit: 1000
    t.datetime "last_test_at", precision: nil
    t.string "last_test_status", limit: 20
    t.datetime "last_used_at", precision: nil
    t.datetime "migrated_to_vault_at"
    t.string "name", limit: 255, null: false
    t.jsonb "rate_limits", default: {}, null: false
    t.integer "success_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.jsonb "usage_stats", default: {}, null: false
    t.string "vault_path"
    t.index ["account_id", "ai_data_source_id", "is_default"], name: "index_ai_data_source_credentials_unique_default", unique: true, where: "(is_default = true)"
    t.index ["account_id", "ai_data_source_id"]
    t.index ["account_id"]
    t.index ["ai_data_source_id"]
    t.index ["consecutive_failures"]
    t.index ["is_active"]
  end

  create_table "ai_data_source_endpoints", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "ai_data_source_id", null: false
    t.jsonb "body_template", default: {}, null: false
    t.integer "cache_ttl_seconds"
    t.string "change_detection", limit: 50
    t.jsonb "contract", default: {}
    t.datetime "created_at", null: false
    t.string "etag", limit: 500
    t.string "expected_content_type", limit: 255
    t.string "http_method", limit: 10, default: "GET", null: false
    t.jsonb "incremental", default: {}
    t.string "last_modified", limit: 255
    t.jsonb "metadata", default: {}, null: false
    t.boolean "monitorable", default: false, null: false
    t.string "name", limit: 255, null: false
    t.string "owner", limit: 255
    t.jsonb "pagination", default: {}
    t.string "path_template", limit: 1000
    t.boolean "quality_checks_enabled", default: false, null: false
    t.boolean "quarantine_on_failure", default: false, null: false
    t.jsonb "query_template", default: {}, null: false
    t.string "response_format", limit: 50
    t.jsonb "response_mapping", default: {}, null: false
    t.jsonb "response_schema", default: {}, null: false
    t.integer "sla_max_age_seconds"
    t.string "slug", limit: 100, null: false
    t.integer "stale_if_error_seconds"
    t.integer "stale_while_revalidate_seconds"
    t.boolean "track_schema", default: false, null: false
    t.jsonb "transforms", default: {}
    t.datetime "updated_at", null: false
    t.index ["ai_data_source_id", "slug"], unique: true
    t.index ["ai_data_source_id"]
  end

  create_table "ai_data_source_expectations", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "ai_data_source_endpoint_id", null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.boolean "is_active", default: true, null: false
    t.string "name", limit: 255, null: false
    t.string "rule_type", limit: 50, null: false
    t.string "severity", limit: 20, default: "warn", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_data_source_endpoint_id"]
  end

  create_table "ai_data_source_queries", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.decimal "actual_cost_usd", precision: 12, scale: 6
    t.uuid "ai_data_source_endpoint_id"
    t.uuid "ai_data_source_id", null: false
    t.bigint "bytes_in"
    t.bigint "bytes_out"
    t.boolean "cached", default: false, null: false
    t.string "correlation_id", limit: 255
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.text "error"
    t.decimal "estimated_cost_usd", precision: 12, scale: 6
    t.integer "http_status"
    t.boolean "masking_applied", default: false, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "params_hash", limit: 128
    t.string "policy_decision", limit: 50
    t.string "principal", limit: 255
    t.string "purpose", limit: 255
    t.boolean "quality_passed"
    t.decimal "quality_score", precision: 5, scale: 4
    t.boolean "quarantined", default: false, null: false
    t.string "redacted_url", limit: 2000
    t.boolean "redaction_applied", default: false, null: false
    t.uuid "requesting_agent_id"
    t.string "response_sha256", limit: 64
    t.integer "rows_returned"
    t.string "schema_drift", limit: 20
    t.boolean "schema_valid"
    t.string "served_stage", limit: 50
    t.string "status", limit: 50
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["ai_data_source_endpoint_id"]
    t.index ["ai_data_source_id", "created_at"]
  end

  create_table "ai_data_source_schema_versions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "ai_data_source_endpoint_id", null: false
    t.string "checksum", limit: 64
    t.string "classification", limit: 20, default: "initial", null: false
    t.datetime "created_at", null: false
    t.jsonb "diff", default: {}, null: false
    t.jsonb "schema", default: {}, null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.index ["ai_data_source_endpoint_id", "version"], unique: true
  end

  create_table "ai_data_source_subscriptions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "ai_agent_id"
    t.uuid "ai_data_source_endpoint_id", null: false
    t.uuid "ai_data_source_id", null: false
    t.integer "consecutive_failures", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "last_checksum", limit: 128
    t.string "last_etag", limit: 500
    t.datetime "last_polled_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "next_poll_at"
    t.jsonb "params", default: {}, null: false
    t.string "poll_frequency", limit: 50
    t.string "status", limit: 50, default: "active", null: false
    t.string "sync_cursor", limit: 500
    t.datetime "updated_at", null: false
    t.index ["ai_agent_id"]
    t.index ["ai_data_source_endpoint_id"]
    t.index ["ai_data_source_id"]
    t.index ["status", "next_poll_at"]
  end

  create_table "ai_data_sources", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "api_base_url", limit: 500
    t.jsonb "auth_config", default: {}
    t.string "auth_scheme", default: "none", null: false
    t.jsonb "capabilities", default: [], null: false
    t.string "category", limit: 100
    t.jsonb "configuration", default: {}, null: false
    t.integer "crawl_delay_seconds"
    t.datetime "created_at", null: false
    t.jsonb "default_parameters", default: {}, null: false
    t.text "description"
    t.string "documentation_url", limit: 500
    t.decimal "effectiveness_score", precision: 5, scale: 4, default: "0.5"
    t.string "health_status", limit: 20, default: "unknown"
    t.boolean "is_active", default: true, null: false
    t.datetime "last_health_check_at", precision: nil
    t.datetime "last_used_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", limit: 255, null: false
    t.integer "negative_usage_count", default: 0, null: false
    t.integer "positive_usage_count", default: 0, null: false
    t.integer "priority_order", default: 1000, null: false
    t.string "protocol", default: "rest", null: false
    t.jsonb "rate_limits", default: {}, null: false
    t.boolean "requires_auth", default: false, null: false
    t.boolean "respect_robots", default: false, null: false
    t.string "slug", limit: 100, null: false
    t.string "source_type", limit: 50, null: false
    t.datetime "updated_at", null: false
    t.integer "usage_count", default: 0, null: false
    t.index ["account_id", "slug"], unique: true
    t.index ["account_id"]
    t.index ["capabilities"], name: "index_ai_data_sources_on_capabilities", using: :gin
    t.index ["category"], name: "index_ai_data_sources_on_category", where: "(category IS NOT NULL)"
    t.index ["is_active"]
    t.index ["priority_order"]
    t.index ["source_type", "is_active"]
    t.index ["source_type"]
  end

  create_table "ai_deferred_operations", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "action_category", null: false
    t.uuid "ai_agent_id"
    t.uuid "approval_request_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.text "error_message"
    t.datetime "executed_at"
    t.string "executor_class", null: false
    t.jsonb "params", default: {}, null: false
    t.uuid "requested_by_id"
    t.jsonb "result", default: {}, null: false
    t.uuid "source_id"
    t.string "source_type"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["action_category"]
    t.index ["ai_agent_id"]
    t.index ["approval_request_id"]
    t.index ["executor_class"]
    t.index ["requested_by_id"]
    t.index ["source_type", "source_id"]
  end

  create_table "ai_delegation_policies", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "agent_id", null: false
    t.jsonb "allowed_delegate_types", default: [], null: false
    t.float "budget_delegation_pct", default: 0.5, null: false
    t.datetime "created_at", null: false
    t.jsonb "delegatable_actions", default: [], null: false
    t.string "inheritance_policy", default: "conservative", null: false
    t.integer "max_depth", default: 3, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "agent_id"]
    t.index ["account_id"]
    t.index ["agent_id"], unique: true
    t.check_constraint "inheritance_policy::text = ANY (ARRAY['conservative'::character varying::text, 'moderate'::character varying::text, 'permissive'::character varying::text])", name: "check_delegation_inheritance_policy"
  end

  create_table "ai_deployment_risks", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "approval_request_id"
    t.datetime "assessed_at"
    t.uuid "assessed_by_id"
    t.string "assessment_id", null: false
    t.jsonb "change_analysis", default: {}
    t.datetime "created_at", null: false
    t.string "decision"
    t.datetime "decision_at"
    t.text "decision_rationale"
    t.string "deployment_type", null: false
    t.jsonb "impact_analysis", default: {}
    t.jsonb "mitigations", default: []
    t.uuid "pipeline_execution_id"
    t.jsonb "recommendations", default: []
    t.boolean "requires_approval", default: false, null: false
    t.jsonb "risk_factors", default: []
    t.string "risk_level", null: false
    t.integer "risk_score"
    t.string "status", default: "pending", null: false
    t.text "summary"
    t.string "target_environment", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"]
    t.index ["account_id"]
    t.index ["assessed_by_id"]
    t.index ["assessment_id"], unique: true
    t.index ["pipeline_execution_id"]
    t.index ["risk_level"]
    t.index ["status"]
    t.index ["target_environment"]
    t.check_constraint "decision IS NULL OR (decision::text = ANY (ARRAY['proceed'::character varying::text, 'proceed_with_caution'::character varying::text, 'delay'::character varying::text, 'abort'::character varying::text]))", name: "check_risk_decision"
    t.check_constraint "risk_level::text = ANY (ARRAY['low'::character varying::text, 'medium'::character varying::text, 'high'::character varying::text, 'critical'::character varying::text])", name: "check_risk_level"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'assessed'::character varying::text, 'approved'::character varying::text, 'rejected'::character varying::text, 'overridden'::character varying::text])", name: "check_risk_status"
  end

  create_table "ai_devops_template_installations", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "custom_config", default: {}
    t.uuid "devops_template_id", null: false
    t.integer "execution_count", default: 0
    t.integer "failure_count", default: 0
    t.uuid "installed_by_id"
    t.string "installed_version"
    t.datetime "last_executed_at"
    t.string "status", default: "active", null: false
    t.integer "success_count", default: 0
    t.datetime "updated_at", null: false
    t.jsonb "variable_values", default: {}
    t.index ["account_id", "devops_template_id"], unique: true
    t.index ["account_id"]
    t.index ["devops_template_id"]
    t.index ["installed_by_id"]
    t.index ["status"]
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'paused'::character varying::text, 'disabled'::character varying::text, 'pending_update'::character varying::text])", name: "check_devops_installation_status"
  end

  create_table "ai_devops_templates", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.float "average_rating"
    t.string "category", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.text "description"
    t.jsonb "input_schema", default: {}
    t.integer "installation_count", default: 0
    t.jsonb "integrations_required", default: []
    t.boolean "is_featured", default: false, null: false
    t.boolean "is_system", default: false, null: false
    t.string "name", null: false
    t.jsonb "output_schema", default: {}
    t.decimal "price_usd", precision: 10, scale: 2
    t.datetime "published_at"
    t.integer "review_count", default: 0
    t.jsonb "secrets_required", default: []
    t.string "slug", null: false
    t.string "status", default: "draft", null: false
    t.jsonb "tags", default: []
    t.string "template_type", null: false
    t.jsonb "trigger_config", default: {}
    t.datetime "updated_at", null: false
    t.text "usage_guide"
    t.jsonb "variables", default: []
    t.string "version", default: "1.0.0", null: false
    t.string "visibility", default: "private", null: false
    t.jsonb "workflow_definition", default: {}
    t.index ["account_id"]
    t.index ["category"]
    t.index ["created_by_id"]
    t.index ["is_featured"]
    t.index ["is_system"]
    t.index ["slug"], unique: true
    t.index ["status", "visibility"]
    t.index ["template_type"]
    t.check_constraint "category::text = ANY (ARRAY['code_quality'::character varying::text, 'deployment'::character varying::text, 'documentation'::character varying::text, 'testing'::character varying::text, 'security'::character varying::text, 'monitoring'::character varying::text, 'release'::character varying::text, 'custom'::character varying::text])", name: "check_devops_category"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'pending_review'::character varying::text, 'published'::character varying::text, 'archived'::character varying::text, 'deprecated'::character varying::text])", name: "check_devops_status"
    t.check_constraint "template_type::text = ANY (ARRAY['code_review'::character varying::text, 'security_scan'::character varying::text, 'test_generation'::character varying::text, 'deployment_validation'::character varying::text, 'release_notes'::character varying::text, 'changelog'::character varying::text, 'api_docs'::character varying::text, 'coverage_analysis'::character varying::text, 'performance_check'::character varying::text, 'custom'::character varying::text])", name: "check_devops_template_type"
    t.check_constraint "visibility::text = ANY (ARRAY['private'::character varying::text, 'team'::character varying::text, 'public'::character varying::text, 'marketplace'::character varying::text])", name: "check_devops_visibility"
  end

  create_table "ai_discovery_results", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.integer "agents_found", default: 0
    t.datetime "completed_at"
    t.integer "connections_found", default: 0
    t.datetime "created_at", null: false
    t.jsonb "discovered_agents", default: []
    t.jsonb "discovered_connections", default: []
    t.jsonb "discovered_tools", default: []
    t.text "error_message"
    t.jsonb "recommendations", default: []
    t.string "scan_id"
    t.string "scan_type"
    t.datetime "started_at"
    t.string "status", default: "pending"
    t.integer "tools_found", default: 0
    t.datetime "updated_at", null: false
    t.index ["account_id", "scan_type"]
    t.index ["account_id"]
    t.index ["scan_id"], unique: true
  end

  create_table "ai_document_chunks", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.uuid "document_id", null: false
    t.datetime "embedded_at"
    t.vector "embedding", limit: 1536
    t.string "embedding_model"
    t.integer "end_offset"
    t.uuid "knowledge_base_id", null: false
    t.jsonb "metadata", default: {}
    t.float "relevance_score"
    t.integer "sequence_number", null: false
    t.integer "start_offset"
    t.integer "token_count"
    t.datetime "updated_at", null: false
    t.index ["document_id", "sequence_number"], unique: true
    t.index ["document_id"]
    t.index ["embedding"], name: "idx_document_chunks_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["knowledge_base_id", "created_at"]
    t.index ["knowledge_base_id"]
  end

  create_table "ai_documents", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "checksum"
    t.integer "chunk_count", default: 0
    t.text "content"
    t.bigint "content_size_bytes"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.jsonb "extraction_config", default: {}
    t.uuid "knowledge_base_id", null: false
    t.datetime "last_refreshed_at"
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.datetime "processed_at"
    t.jsonb "processing_errors", default: []
    t.string "source_type", null: false
    t.string "source_url"
    t.string "status", default: "pending", null: false
    t.bigint "token_count", default: 0
    t.datetime "updated_at", null: false
    t.uuid "uploaded_by_id"
    t.index ["checksum"]
    t.index ["knowledge_base_id", "name"]
    t.index ["knowledge_base_id", "status"]
    t.index ["knowledge_base_id"]
    t.index ["source_type"]
    t.index ["uploaded_by_id"]
    t.check_constraint "source_type::text = ANY (ARRAY['upload'::character varying::text, 'url'::character varying::text, 'api'::character varying::text, 'database'::character varying::text, 'cloud_storage'::character varying::text, 'git'::character varying::text])", name: "check_document_source_type"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'indexed'::character varying::text, 'failed'::character varying::text, 'archived'::character varying::text])", name: "check_document_status"
  end

  create_table "ai_encrypted_messages", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.text "aad"
    t.uuid "account_id", null: false
    t.binary "auth_tag", null: false
    t.binary "ciphertext", null: false
    t.datetime "created_at", null: false
    t.text "ephemeral_public_key"
    t.uuid "from_agent_id", null: false
    t.binary "nonce", null: false
    t.integer "sequence_number", null: false
    t.string "session_id"
    t.text "signature"
    t.string "status", default: "delivered"
    t.uuid "task_id"
    t.uuid "to_agent_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["from_agent_id"]
    t.index ["session_id", "sequence_number"], unique: true
    t.index ["session_id"]
    t.index ["to_agent_id"]
  end

  create_table "ai_evaluation_results", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "agent_id", null: false
    t.datetime "created_at", null: false
    t.string "evaluator_model", null: false
    t.uuid "execution_id", null: false
    t.text "feedback"
    t.jsonb "scores", default: {}
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["agent_id", "created_at"]
    t.index ["agent_id"]
    t.index ["execution_id"]
  end

  create_table "ai_execution_events", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.decimal "cost_usd", precision: 10, scale: 6
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "error_class"
    t.text "error_message"
    t.string "event_type", null: false
    t.jsonb "metadata", default: {}
    t.uuid "source_id", null: false
    t.string "source_type", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"]
    t.index ["account_id"]
    t.index ["created_at"]
    t.index ["event_type", "status"]
    t.index ["source_type", "source_id"]
  end

  create_table "ai_execution_trace_spans", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "completed_at"
    t.decimal "cost", precision: 10, scale: 6, default: "0.0"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.text "error"
    t.jsonb "events", default: []
    t.uuid "execution_trace_id", null: false
    t.jsonb "input_data"
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.jsonb "output_data"
    t.string "parent_span_id"
    t.string "span_id", null: false
    t.string "span_type", null: false
    t.datetime "started_at"
    t.string "status", default: "running", null: false
    t.jsonb "tokens", default: {}
    t.datetime "updated_at", null: false
    t.index ["execution_trace_id", "span_type"]
    t.index ["execution_trace_id", "started_at"]
    t.index ["execution_trace_id", "status"]
    t.index ["execution_trace_id"]
    t.index ["parent_span_id"]
    t.index ["span_id"], unique: true
  end

  create_table "ai_execution_traces", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.text "error"
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.jsonb "output"
    t.string "root_span_id"
    t.datetime "started_at"
    t.string "status", default: "running", null: false
    t.decimal "total_cost", precision: 10, scale: 6, default: "0.0"
    t.integer "total_tokens", default: 0
    t.string "trace_id", null: false
    t.string "trace_type", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "started_at"]
    t.index ["account_id", "status"]
    t.index ["account_id", "trace_type"]
    t.index ["account_id"]
    t.index ["root_span_id"]
    t.index ["trace_id"], unique: true
  end

  create_table "ai_experience_replays", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_agent_id", null: false
    t.text "compressed_example", null: false
    t.datetime "created_at", null: false
    t.decimal "effectiveness_score", precision: 5, scale: 4, default: "0.5", null: false
    t.vector "embedding", limit: 1536
    t.integer "injection_count", default: 0, null: false
    t.datetime "last_injected_at"
    t.jsonb "metadata", default: {}
    t.integer "negative_outcome_count", default: 0, null: false
    t.integer "positive_outcome_count", default: 0, null: false
    t.decimal "quality_score", precision: 5, scale: 4, default: "0.5", null: false
    t.uuid "source_execution_id"
    t.uuid "source_trajectory_id"
    t.string "status", default: "active", null: false
    t.jsonb "tags", default: []
    t.text "task_description"
    t.string "task_type", limit: 100
    t.integer "token_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "ai_agent_id"]
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["ai_agent_id"]
    t.index ["effectiveness_score"]
    t.index ["embedding"], name: "idx_experience_replays_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["quality_score"]
    t.index ["source_execution_id"]
    t.index ["source_trajectory_id"]
    t.index ["tags"], name: "index_ai_experience_replays_on_tags", using: :gin
  end

  create_table "ai_file_locks", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.datetime "acquired_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "file_path", null: false
    t.string "lock_type", default: "exclusive", null: false
    t.datetime "updated_at", null: false
    t.uuid "worktree_id"
    t.uuid "worktree_session_id"
    t.index ["account_id"]
    t.index ["worktree_id"]
    t.index ["worktree_session_id", "file_path"], unique: true
    t.index ["worktree_session_id"]
  end

  create_table "ai_goal_plan_steps", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.jsonb "dependencies", default: []
    t.string "description"
    t.decimal "estimated_cost_usd", precision: 10, scale: 4
    t.integer "estimated_duration_minutes"
    t.jsonb "execution_config", default: {}
    t.jsonb "metadata", default: {}, null: false
    t.uuid "plan_id", null: false
    t.uuid "ralph_task_id"
    t.text "result_summary"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.integer "step_number", null: false
    t.string "step_type", null: false
    t.uuid "sub_goal_id"
    t.datetime "updated_at", null: false
    t.index ["plan_id", "status"]
    t.index ["plan_id", "step_number"], unique: true
    t.index ["plan_id"]
    t.index ["ralph_task_id"]
    t.index ["sub_goal_id"]
  end

  create_table "ai_goal_plans", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_agent_id", null: false
    t.datetime "approved_at"
    t.uuid "approved_by_id"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.decimal "estimated_cost_usd", precision: 10, scale: 4
    t.integer "estimated_duration_minutes"
    t.uuid "goal_id", null: false
    t.jsonb "plan_data", default: {}
    t.jsonb "risk_assessment", default: {}
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.jsonb "validation_result", default: {}
    t.integer "version", default: 1, null: false
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["ai_agent_id"]
    t.index ["approved_by_id"]
    t.index ["goal_id", "version"], unique: true
    t.index ["goal_id"]
  end

  create_table "ai_governance_reports", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.boolean "auto_remediated", default: false, null: false
    t.decimal "confidence_score", precision: 5, scale: 4, default: "0.5"
    t.datetime "created_at", null: false
    t.jsonb "evidence", default: {}
    t.uuid "monitor_agent_id"
    t.jsonb "recommended_actions", default: []
    t.string "report_type", null: false
    t.string "severity", default: "info", null: false
    t.string "status", default: "open", null: false
    t.uuid "subject_agent_id"
    t.uuid "subject_team_id"
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["monitor_agent_id"]
    t.index ["report_type"]
    t.index ["subject_agent_id", "status"]
    t.index ["subject_agent_id"]
    t.index ["subject_team_id"]
  end

  create_table "ai_guardrail_configs", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_agent_id"
    t.boolean "allow_agent_creation", default: false
    t.boolean "allow_cross_team_ops", default: false
    t.string "autonomy_level", default: "supervised"
    t.boolean "block_on_failure", default: false, null: false
    t.jsonb "branch_protection_config", default: {}
    t.boolean "branch_protection_enabled", default: false
    t.jsonb "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.jsonb "input_rails", default: [], null: false
    t.boolean "is_active", default: true, null: false
    t.integer "max_agents_per_team", default: 20
    t.integer "max_input_tokens", default: 100000
    t.integer "max_output_tokens", default: 50000
    t.boolean "merge_approval_required", default: true
    t.string "name", null: false
    t.jsonb "output_rails", default: [], null: false
    t.decimal "pii_sensitivity", precision: 3, scale: 2, default: "0.8"
    t.jsonb "protected_branches", default: ["main", "master", "develop"]
    t.boolean "require_human_approval", default: true
    t.boolean "require_worktree_for_repos", default: true
    t.jsonb "resource_limits", default: {}
    t.jsonb "retrieval_rails", default: [], null: false
    t.integer "total_blocks", default: 0, null: false
    t.integer "total_checks", default: 0, null: false
    t.decimal "toxicity_threshold", precision: 3, scale: 2, default: "0.7"
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], unique: true
    t.index ["account_id"]
    t.index ["ai_agent_id"]
  end

  create_table "ai_hybrid_search_results", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.string "fusion_method", default: "rrf"
    t.jsonb "graph_results", default: []
    t.decimal "graph_score", precision: 5, scale: 4
    t.jsonb "keyword_results", default: []
    t.decimal "keyword_score", precision: 5, scale: 4
    t.jsonb "merged_results", default: []
    t.jsonb "metadata", default: {}
    t.text "query_text", null: false
    t.string "rerank_model"
    t.boolean "reranked", default: false
    t.integer "result_count", default: 0
    t.string "search_mode", null: false
    t.integer "total_latency_ms"
    t.jsonb "vector_results", default: []
    t.decimal "vector_score", precision: 5, scale: 4
    t.index ["account_id"]
    t.index ["created_at"]
    t.index ["search_mode"]
    t.check_constraint "search_mode::text = ANY (ARRAY['vector'::character varying::text, 'keyword'::character varying::text, 'hybrid'::character varying::text, 'graph'::character varying::text])", name: "check_ai_hybrid_search_mode"
  end

  create_table "ai_improvement_recommendations", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "applied_at"
    t.uuid "approved_by_id"
    t.decimal "confidence_score", precision: 5, scale: 4, null: false
    t.datetime "created_at", null: false
    t.jsonb "current_config", default: {}
    t.jsonb "evidence", default: {}
    t.string "recommendation_type", null: false
    t.jsonb "recommended_config", default: {}
    t.string "status", default: "pending", null: false
    t.uuid "target_id", null: false
    t.string "target_type", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["approved_by_id"]
    t.index ["recommendation_type"]
    t.index ["status"]
    t.index ["target_type", "target_id"]
  end

  create_table "ai_intervention_policies", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "action_category", null: false
    t.uuid "ai_agent_id"
    t.uuid "approval_chain_id"
    t.jsonb "conditions", default: {}
    t.datetime "created_at", null: false
    t.boolean "is_active", default: true, null: false
    t.string "policy", null: false
    t.jsonb "preferred_channels", default: []
    t.integer "priority", default: 0, null: false
    t.string "scope", default: "global", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["account_id", "action_category"]
    t.index ["account_id", "scope"]
    t.index ["account_id", "user_id", "ai_agent_id"]
    t.index ["account_id"]
    t.index ["ai_agent_id"]
    t.index ["approval_chain_id"]
    t.index ["user_id"]
  end

  create_table "ai_kill_switch_events", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.jsonb "metadata", default: {}
    t.text "reason"
    t.uuid "triggered_by_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"]
    t.index ["account_id", "event_type"]
    t.index ["account_id"]
    t.index ["triggered_by_id"]
  end

  create_table "ai_knowledge_bases", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.integer "chunk_count", default: 0
    t.integer "chunk_overlap", default: 200
    t.integer "chunk_size", default: 1000
    t.string "chunking_strategy", default: "recursive", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.string "description"
    t.integer "document_count", default: 0
    t.integer "embedding_dimensions", default: 1536
    t.string "embedding_model", default: "text-embedding-3-small", null: false
    t.string "embedding_provider", default: "openai", null: false
    t.uuid "git_repository_id"
    t.boolean "is_public", default: false, null: false
    t.datetime "last_indexed_at"
    t.datetime "last_queried_at"
    t.jsonb "metadata_schema", default: {}
    t.string "name", null: false
    t.jsonb "settings", default: {}
    t.string "status", default: "active", null: false
    t.bigint "storage_bytes", default: 0
    t.bigint "total_tokens", default: 0
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], unique: true
    t.index ["account_id"]
    t.index ["created_by_id"]
    t.index ["git_repository_id"]
    t.index ["is_public"]
    t.index ["status"]
    t.check_constraint "chunking_strategy::text = ANY (ARRAY['recursive'::character varying::text, 'semantic'::character varying::text, 'fixed'::character varying::text, 'sentence'::character varying::text, 'paragraph'::character varying::text, 'custom'::character varying::text])", name: "check_kb_chunking_strategy"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'indexing'::character varying::text, 'paused'::character varying::text, 'archived'::character varying::text, 'error'::character varying::text])", name: "check_kb_status"
  end

  create_table "ai_knowledge_graph_edges", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.boolean "bidirectional", default: false
    t.decimal "confidence", precision: 5, scale: 4, default: "1.0"
    t.datetime "created_at", null: false
    t.string "label"
    t.jsonb "metadata", default: {}
    t.jsonb "properties", default: {}
    t.string "relation_type", null: false
    t.uuid "source_document_id"
    t.uuid "source_node_id", null: false
    t.string "status", default: "active"
    t.uuid "target_node_id", null: false
    t.datetime "updated_at", null: false
    t.decimal "weight", precision: 5, scale: 4, default: "1.0"
    t.index ["account_id"]
    t.index ["relation_type"]
    t.index ["source_node_id", "target_node_id", "relation_type"], name: "index_ai_kg_edges_unique_active", unique: true, where: "((status)::text = 'active'::text)"
    t.index ["source_node_id"]
    t.index ["target_node_id"]
  end

  create_table "ai_knowledge_graph_nodes", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_data_source_id"
    t.uuid "ai_skill_id"
    t.decimal "confidence", precision: 5, scale: 4, default: "1.0"
    t.datetime "created_at", null: false
    t.decimal "decay_rate", precision: 5, scale: 4, default: "0.001"
    t.text "description"
    t.vector "embedding", limit: 1536
    t.string "entity_type"
    t.uuid "knowledge_base_id"
    t.datetime "last_event_processed_at"
    t.datetime "last_quality_recalc_at"
    t.datetime "last_seen_at"
    t.integer "mention_count", default: 1
    t.uuid "merged_into_id"
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.string "node_type", null: false
    t.ltree "path"
    t.jsonb "properties", default: {}
    t.decimal "quality_score", precision: 5, scale: 4
    t.uuid "source_document_id"
    t.string "status", default: "active"
    t.datetime "updated_at", null: false
    t.index ["account_id", "ai_skill_id"], name: "idx_kg_nodes_unique_active_skill", unique: true, where: "((ai_skill_id IS NOT NULL) AND ((status)::text = 'active'::text))"
    t.index ["account_id", "entity_type", "knowledge_base_id"], name: "idx_kg_nodes_code_entities", where: "(((node_type)::text = 'code_entity'::text) AND ((status)::text = 'active'::text))"
    t.index ["account_id", "name", "node_type"], name: "index_ai_kg_nodes_unique_active", unique: true, where: "((status)::text = 'active'::text)"
    t.index ["account_id"]
    t.index ["ai_data_source_id"], name: "index_ai_kg_nodes_on_ai_data_source_id", where: "(ai_data_source_id IS NOT NULL)"
    t.index ["embedding"], name: "index_ai_knowledge_graph_nodes_on_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["entity_type"]
    t.index ["knowledge_base_id"]
    t.index ["last_event_processed_at"]
    t.index ["metadata"], name: "idx_kg_nodes_code_metadata", where: "((node_type)::text = 'code_entity'::text)", using: :gin
    t.index ["name"]
    t.index ["node_type"]
    t.index ["path"], name: "index_ai_knowledge_graph_nodes_on_path", using: :gist
    t.index ["status"]
    t.check_constraint "node_type::text = ANY (ARRAY['entity'::character varying::text, 'concept'::character varying::text, 'relation'::character varying::text, 'attribute'::character varying::text, 'code_entity'::character varying::text])", name: "check_ai_kg_node_type"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'merged'::character varying::text, 'archived'::character varying::text])", name: "check_ai_kg_node_status"
  end

  create_table "ai_mcp_app_instances", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.jsonb "input_data", default: {}
    t.uuid "mcp_app_id", null: false
    t.jsonb "output_data", default: {}
    t.uuid "session_id"
    t.datetime "started_at"
    t.jsonb "state", default: {}
    t.string "status", default: "created", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["mcp_app_id"]
    t.index ["session_id"]
  end

  create_table "ai_mcp_apps", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "app_type", default: "custom", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.jsonb "csp_policy", default: {}
    t.text "description"
    t.text "html_content"
    t.jsonb "input_schema", default: {}
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.jsonb "output_schema", default: {}
    t.jsonb "sandbox_config", default: {}
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.string "version", default: "1.0.0"
    t.index ["account_id", "name"], unique: true
    t.index ["account_id"]
  end

  create_table "ai_memory_pools", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "access_control", default: {}
    t.uuid "account_id"
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}
    t.integer "data_size_bytes", default: 0
    t.datetime "expires_at"
    t.datetime "last_accessed_at"
    t.jsonb "metadata", default: {}
    t.string "name"
    t.uuid "owner_agent_id"
    t.boolean "persist_across_executions", default: false
    t.string "pool_id"
    t.string "pool_type"
    t.jsonb "retention_policy", default: {}
    t.string "scope"
    t.uuid "task_execution_id"
    t.uuid "team_id"
    t.datetime "updated_at", null: false
    t.integer "version", default: 1
    t.index ["account_id", "scope"]
    t.index ["account_id"]
    t.index ["owner_agent_id"]
    t.index ["pool_id"], unique: true
    t.index ["task_execution_id"]
    t.index ["team_id"]
  end

  create_table "ai_merge_operations", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "completed_at"
    t.text "conflict_details"
    t.jsonb "conflict_files", default: [], null: false
    t.string "conflict_resolution"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "error_code"
    t.text "error_message"
    t.boolean "has_conflicts", default: false, null: false
    t.string "merge_commit_sha"
    t.integer "merge_order"
    t.jsonb "metadata", default: {}, null: false
    t.string "pull_request_id"
    t.string "pull_request_status"
    t.string "pull_request_url"
    t.string "rollback_commit_sha"
    t.boolean "rolled_back", default: false, null: false
    t.datetime "rolled_back_at"
    t.string "source_branch", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.string "strategy", default: "merge", null: false
    t.string "target_branch", null: false
    t.datetime "updated_at", null: false
    t.uuid "worktree_id", null: false
    t.uuid "worktree_session_id", null: false
    t.index ["account_id"]
    t.index ["status"]
    t.index ["worktree_id"]
    t.index ["worktree_session_id"]
  end

  create_table "ai_messages", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "ai_agent_id"
    t.uuid "ai_conversation_id", null: false
    t.jsonb "attachments", default: []
    t.text "content", null: false
    t.jsonb "content_metadata", default: {}
    t.decimal "cost_usd", precision: 8, scale: 4, default: "0.0"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.jsonb "edit_history", default: []
    t.datetime "edited_at", precision: nil
    t.text "error_message"
    t.boolean "is_edited", default: false
    t.string "message_id", limit: 100, null: false
    t.string "message_type", limit: 50, default: "text"
    t.uuid "parent_message_id"
    t.datetime "processed_at", precision: nil
    t.jsonb "processing_metadata", default: {}
    t.string "role", limit: 20, null: false
    t.tsvector "search_vector"
    t.integer "sequence_number"
    t.string "status", limit: 20, default: "sent"
    t.integer "token_count", default: 0
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["ai_agent_id"]
    t.index ["ai_conversation_id", "role"]
    t.index ["ai_conversation_id", "sequence_number"]
    t.index ["ai_conversation_id"]
    t.index ["attachments"], name: "index_ai_messages_on_attachments", using: :gin
    t.index ["deleted_at"], name: "index_ai_messages_on_deleted_at", where: "(deleted_at IS NOT NULL)"
    t.index ["edit_history"], name: "index_ai_messages_on_edit_history", using: :gin
    t.index ["message_id"], unique: true
    t.index ["message_type"]
    t.index ["parent_message_id"]
    t.index ["processed_at"]
    t.index ["role"]
    t.index ["search_vector"], name: "index_ai_messages_on_search_vector", using: :gin
    t.index ["sequence_number"]
    t.index ["status"]
    t.index ["user_id"]
  end

  create_table "ai_mission_approvals", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.text "comment"
    t.datetime "created_at", null: false
    t.string "decision", null: false
    t.string "gate", null: false
    t.jsonb "metadata", default: {}
    t.uuid "mission_id", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["account_id"]
    t.index ["mission_id", "gate"]
    t.index ["mission_id"]
    t.index ["user_id"]
  end

  create_table "ai_mission_templates", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.jsonb "approval_gates", default: []
    t.datetime "created_at", null: false
    t.jsonb "default_configuration", default: {}
    t.text "description"
    t.boolean "is_default", default: false
    t.string "mission_type", null: false
    t.string "name", null: false
    t.jsonb "phases", default: []
    t.jsonb "rejection_mappings", default: {}
    t.jsonb "skill_compositions", default: {}
    t.string "status", default: "active"
    t.string "template_type", default: "account", null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 1
    t.index ["account_id", "template_type"]
    t.index ["account_id"]
    t.index ["is_default"], name: "index_ai_mission_templates_on_is_default", where: "(is_default = true)"
    t.index ["mission_type", "status"]
  end

  create_table "ai_missions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "analysis_result", default: {}
    t.string "base_branch", default: "main"
    t.string "branch_name"
    t.datetime "completed_at"
    t.jsonb "configuration", default: {}
    t.uuid "conversation_id"
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.string "current_phase"
    t.jsonb "custom_phases"
    t.uuid "delegation_id"
    t.string "deployed_container_id"
    t.integer "deployed_port"
    t.string "deployed_url"
    t.text "description"
    t.integer "duration_ms"
    t.jsonb "error_details", default: {}
    t.text "error_message"
    t.jsonb "feature_suggestions", default: []
    t.jsonb "metadata", default: {}
    t.uuid "mission_template_id"
    t.string "mission_type", null: false
    t.string "name", null: false
    t.text "objective"
    t.jsonb "phase_config", default: {}
    t.jsonb "phase_history", default: []
    t.integer "pr_number"
    t.string "pr_url"
    t.jsonb "prd_json", default: {}
    t.uuid "ralph_loop_id"
    t.uuid "repository_id"
    t.jsonb "review_result", default: {}
    t.uuid "review_state_id"
    t.uuid "risk_contract_id"
    t.jsonb "selected_feature", default: {}
    t.datetime "started_at"
    t.string "status", default: "draft", null: false
    t.uuid "team_id"
    t.jsonb "test_result", default: {}
    t.datetime "updated_at", null: false
    t.index ["account_id", "mission_type"]
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["conversation_id"]
    t.index ["created_by_id"]
    t.index ["delegation_id"]
    t.index ["deployed_port"], name: "index_ai_missions_on_deployed_port", unique: true, where: "(((status)::text = 'active'::text) AND (deployed_port IS NOT NULL))"
    t.index ["mission_template_id"]
    t.index ["ralph_loop_id"]
    t.index ["repository_id"]
    t.index ["review_state_id"]
    t.index ["risk_contract_id"]
    t.index ["team_id"]
  end

  create_table "ai_mock_responses", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.string "endpoint"
    t.string "error_message"
    t.float "error_rate", default: 0.0
    t.string "error_type"
    t.integer "hit_count", default: 0
    t.boolean "is_active", default: true, null: false
    t.datetime "last_hit_at"
    t.integer "latency_ms", default: 100
    t.jsonb "match_criteria", default: {}
    t.string "match_type", default: "exact", null: false
    t.string "model_name"
    t.string "name", null: false
    t.integer "priority", default: 0
    t.string "provider_type", null: false
    t.jsonb "response_data", default: {}
    t.uuid "sandbox_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["created_by_id"]
    t.index ["match_type"]
    t.index ["sandbox_id", "is_active", "priority"]
    t.index ["sandbox_id", "provider_type"]
    t.index ["sandbox_id"]
    t.check_constraint "match_type::text = ANY (ARRAY['exact'::character varying::text, 'contains'::character varying::text, 'regex'::character varying::text, 'semantic'::character varying::text, 'always'::character varying::text])", name: "check_mock_match_type"
  end

  create_table "ai_model_pricings", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.decimal "cached_input_per_1k", precision: 12, scale: 8, default: "0.0"
    t.datetime "created_at", null: false
    t.decimal "input_per_1k", precision: 12, scale: 8, null: false
    t.datetime "last_synced_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "model_id", null: false
    t.decimal "output_per_1k", precision: 12, scale: 8, null: false
    t.string "provider_type", null: false
    t.string "source", null: false
    t.string "tier"
    t.datetime "updated_at", null: false
    t.index ["model_id", "provider_type"], unique: true
    t.index ["provider_type"]
    t.index ["source"]
  end

  create_table "ai_model_routing_rules", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "conditions", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "is_active", default: true, null: false
    t.datetime "last_matched_at"
    t.decimal "max_cost_per_1k_tokens", precision: 10, scale: 6
    t.decimal "max_latency_ms", precision: 10, scale: 2
    t.decimal "min_quality_score", precision: 5, scale: 4
    t.string "name", null: false
    t.integer "priority", default: 100, null: false
    t.string "rule_type", default: "capability_based", null: false
    t.jsonb "target", default: {}, null: false
    t.integer "times_failed", default: 0, null: false
    t.integer "times_matched", default: 0, null: false
    t.integer "times_succeeded", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "is_active", "priority"]
    t.index ["account_id", "rule_type"]
    t.index ["account_id"]
    t.index ["conditions"], name: "index_ai_model_routing_rules_on_conditions", using: :gin
    t.check_constraint "rule_type::text = ANY (ARRAY['capability_based'::character varying::text, 'cost_based'::character varying::text, 'latency_based'::character varying::text, 'quality_based'::character varying::text, 'custom'::character varying::text, 'ml_optimized'::character varying::text])", name: "check_routing_rule_type"
  end

  create_table "ai_performance_benchmarks", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "baseline_metrics", default: {}
    t.string "benchmark_id", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.text "description"
    t.datetime "last_run_at"
    t.jsonb "latest_results", default: {}
    t.float "latest_score"
    t.string "name", null: false
    t.integer "run_count", default: 0
    t.integer "sample_size", default: 100
    t.uuid "sandbox_id"
    t.string "status", default: "active", null: false
    t.uuid "target_agent_id"
    t.jsonb "test_config", default: {}
    t.jsonb "thresholds", default: {}
    t.string "trend"
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["benchmark_id"], unique: true
    t.index ["created_by_id"]
    t.index ["sandbox_id"]
    t.index ["target_agent_id"]
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'paused'::character varying::text, 'archived'::character varying::text])", name: "check_benchmark_status"
  end

  create_table "ai_persistent_contexts", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "access_control", default: {}
    t.integer "access_count", default: 0
    t.uuid "account_id", null: false
    t.uuid "ai_agent_id"
    t.datetime "archived_at"
    t.jsonb "context_data", default: {}
    t.string "context_id", null: false
    t.string "context_type", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_user_id"
    t.integer "data_size_bytes", default: 0
    t.text "description"
    t.integer "entry_count", default: 0
    t.datetime "expires_at"
    t.datetime "last_accessed_at"
    t.datetime "last_modified_at"
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.jsonb "retention_policy", default: {}
    t.string "scope", null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 1
    t.index ["account_id", "ai_agent_id"]
    t.index ["account_id", "context_type"]
    t.index ["account_id"]
    t.index ["ai_agent_id"]
    t.index ["archived_at"]
    t.index ["context_id"], unique: true
    t.index ["context_type"]
    t.index ["created_by_user_id"]
    t.index ["expires_at"]
    t.index ["scope"]
  end

  create_table "ai_pipeline_executions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "ai_analysis", default: {}
    t.string "branch"
    t.string "commit_sha"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.uuid "devops_installation_id"
    t.integer "duration_ms"
    t.string "execution_id", null: false
    t.jsonb "input_data", default: {}
    t.jsonb "metrics", default: {}
    t.jsonb "output_data", default: {}
    t.string "pipeline_type", null: false
    t.string "pull_request_number"
    t.uuid "repository_id"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.string "trigger_event"
    t.string "trigger_source"
    t.uuid "triggered_by_id"
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["devops_installation_id"]
    t.index ["execution_id"], unique: true
    t.index ["pipeline_type"]
    t.index ["repository_id", "created_at"]
    t.index ["trigger_source"]
    t.index ["triggered_by_id"]
    t.check_constraint "pipeline_type::text = ANY (ARRAY['pr_review'::character varying::text, 'commit_analysis'::character varying::text, 'deployment'::character varying::text, 'release'::character varying::text, 'scheduled'::character varying::text, 'manual'::character varying::text])", name: "check_pipeline_type"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text, 'timeout'::character varying::text])", name: "check_pipeline_status"
  end

  create_table "ai_policy_violations", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "acknowledged_at"
    t.text "context"
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.datetime "detected_at", null: false
    t.uuid "detected_by_id"
    t.datetime "escalated_at"
    t.uuid "policy_id", null: false
    t.jsonb "remediation_steps", default: []
    t.string "resolution_action"
    t.text "resolution_notes"
    t.datetime "resolved_at"
    t.uuid "resolved_by_id"
    t.string "severity", null: false
    t.uuid "source_id"
    t.string "source_type"
    t.string "status", default: "open", null: false
    t.datetime "updated_at", null: false
    t.jsonb "violation_data", default: {}
    t.string "violation_id", null: false
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["detected_by_id"]
    t.index ["policy_id", "created_at"]
    t.index ["policy_id"]
    t.index ["resolved_by_id"]
    t.index ["severity"]
    t.index ["source_type"]
    t.index ["violation_id"], unique: true
    t.check_constraint "severity::text = ANY (ARRAY['low'::character varying::text, 'medium'::character varying::text, 'high'::character varying::text, 'critical'::character varying::text])", name: "check_violation_severity"
    t.check_constraint "status::text = ANY (ARRAY['open'::character varying::text, 'acknowledged'::character varying::text, 'investigating'::character varying::text, 'resolved'::character varying::text, 'dismissed'::character varying::text, 'escalated'::character varying::text])", name: "check_violation_status"
  end

  create_table "ai_pressure_fields", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.integer "address_count", default: 0, null: false
    t.string "artifact_ref", null: false
    t.string "artifact_type"
    t.datetime "created_at", null: false
    t.decimal "decay_rate", precision: 5, scale: 4, default: "0.02", null: false
    t.jsonb "dimensions", default: {}
    t.string "field_type", null: false
    t.datetime "last_addressed_at"
    t.uuid "last_addressed_by_id"
    t.datetime "last_measured_at"
    t.decimal "pressure_value", precision: 5, scale: 4, default: "0.0", null: false
    t.decimal "threshold", precision: 5, scale: 4, default: "0.5", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "field_type", "artifact_ref"], unique: true
    t.index ["account_id", "field_type"]
    t.index ["account_id"]
    t.index ["pressure_value"]
  end

  create_table "ai_provider_credentials", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "access_scopes", default: []
    t.uuid "account_id", null: false
    t.uuid "ai_provider_id", null: false
    t.integer "consecutive_failures", default: 0
    t.datetime "created_at", null: false
    t.text "encrypted_credentials"
    t.string "encryption_key_id", limit: 50
    t.datetime "expires_at", precision: nil
    t.integer "failure_count", default: 0, null: false
    t.boolean "is_active", default: true
    t.boolean "is_default", default: false
    t.string "last_error"
    t.datetime "last_test_at"
    t.string "last_test_status"
    t.datetime "last_used_at", precision: nil
    t.datetime "migrated_to_vault_at"
    t.string "name", limit: 255, null: false
    t.jsonb "rate_limits", default: {}
    t.integer "success_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.jsonb "usage_stats", default: {}
    t.string "vault_path"
    t.index ["account_id", "ai_provider_id", "is_default"], name: "index_ai_provider_credentials_unique_default", unique: true, where: "(is_default = true)"
    t.index ["account_id", "ai_provider_id"]
    t.index ["account_id", "is_default"]
    t.index ["account_id"]
    t.index ["ai_provider_id"]
    t.index ["consecutive_failures"]
    t.index ["expires_at"]
    t.index ["is_active"]
    t.index ["last_test_status"]
    t.index ["last_used_at"]
    t.index ["vault_path"], name: "index_ai_provider_credentials_on_vault_path", unique: true, where: "(vault_path IS NOT NULL)"
  end

  create_table "ai_provider_metrics", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.decimal "avg_cost_per_request", precision: 12, scale: 8
    t.decimal "avg_latency_ms", precision: 10, scale: 2
    t.decimal "cache_write_cost_per_1k", precision: 12, scale: 8
    t.decimal "cached_input_cost_per_1k", precision: 12, scale: 8
    t.string "circuit_state"
    t.integer "consecutive_failures", default: 0, null: false
    t.decimal "cost_per_1k_tokens", precision: 12, scale: 8
    t.datetime "created_at", null: false
    t.jsonb "error_breakdown", default: {}, null: false
    t.decimal "error_rate", precision: 5, scale: 4
    t.integer "failure_count", default: 0, null: false
    t.string "granularity", default: "minute", null: false
    t.decimal "max_latency_ms", precision: 10, scale: 2
    t.decimal "min_latency_ms", precision: 10, scale: 2
    t.jsonb "model_breakdown", default: {}, null: false
    t.string "model_tier"
    t.decimal "p50_latency_ms", precision: 10, scale: 2
    t.decimal "p95_latency_ms", precision: 10, scale: 2
    t.decimal "p99_latency_ms", precision: 10, scale: 2
    t.uuid "provider_id", null: false
    t.integer "rate_limit_count", default: 0, null: false
    t.datetime "recorded_at", null: false
    t.integer "request_count", default: 0, null: false
    t.integer "success_count", default: 0, null: false
    t.decimal "success_rate", precision: 5, scale: 4
    t.integer "timeout_count", default: 0, null: false
    t.decimal "total_cost_usd", precision: 12, scale: 6, default: "0.0", null: false
    t.bigint "total_input_tokens", default: 0, null: false
    t.bigint "total_output_tokens", default: 0, null: false
    t.bigint "total_tokens", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "recorded_at"]
    t.index ["account_id"]
    t.index ["granularity", "recorded_at"]
    t.index ["provider_id", "recorded_at"]
    t.index ["provider_id"]
    t.index ["recorded_at"]
    t.check_constraint "granularity::text = ANY (ARRAY['minute'::character varying::text, 'hour'::character varying::text, 'day'::character varying::text, 'week'::character varying::text, 'month'::character varying::text])", name: "check_metric_granularity"
  end

  create_table "ai_providers", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.string "api_base_url", limit: 500
    t.string "api_endpoint", limit: 500
    t.jsonb "capabilities", default: [], null: false
    t.jsonb "configuration_schema", default: {}, null: false
    t.datetime "created_at", null: false
    t.jsonb "default_parameters", default: {}
    t.text "description"
    t.string "documentation_url", limit: 500
    t.boolean "is_active", default: true
    t.jsonb "metadata", default: {}
    t.string "name", limit: 100, null: false
    t.jsonb "pricing_info", default: {}
    t.integer "priority_order", default: 1000
    t.string "provider_identifier", limit: 255
    t.string "provider_type", limit: 50
    t.jsonb "rate_limits", default: {}
    t.boolean "requires_auth", default: true
    t.string "slug", limit: 50, null: false
    t.string "status_url", limit: 500
    t.jsonb "supported_models", default: [], null: false
    t.boolean "supports_code_execution", default: false
    t.boolean "supports_functions", default: false
    t.boolean "supports_streaming", default: false
    t.boolean "supports_vision", default: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "provider_identifier"], unique: true
    t.index ["account_id"]
    t.index ["capabilities"], name: "index_ai_providers_on_capabilities", using: :gin
    t.index ["is_active"]
    t.index ["name"]
    t.index ["priority_order"]
    t.index ["provider_type", "is_active"]
    t.index ["provider_type"]
    t.index ["slug", "account_id"], unique: true
    t.index ["supported_models"], name: "index_ai_providers_on_supported_models", using: :gin
  end

  create_table "ai_provisioning_code_deployments", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "branch", default: "main", null: false
    t.string "commit_sha"
    t.datetime "created_at", null: false
    t.datetime "deployed_at"
    t.text "last_error"
    t.uuid "mission_id", null: false
    t.uuid "node_instance_id", null: false
    t.string "public_url"
    t.string "repo_url", null: false
    t.string "start_command"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["mission_id"]
    t.index ["node_instance_id"]
  end

  create_table "ai_quarantine_records", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "agent_id", null: false
    t.uuid "approved_by_id"
    t.integer "cooldown_minutes", default: 60
    t.datetime "created_at", null: false
    t.uuid "escalated_from_id"
    t.jsonb "forensic_snapshot", default: {}
    t.jsonb "previous_capabilities", default: {}
    t.text "restoration_notes"
    t.datetime "restored_at"
    t.jsonb "restrictions_applied", default: {}
    t.datetime "scheduled_restore_at"
    t.string "severity", null: false
    t.string "status", default: "active", null: false
    t.string "trigger_reason", null: false
    t.string "trigger_source"
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["agent_id"]
    t.index ["scheduled_restore_at"]
    t.index ["severity"]
    t.index ["status"]
  end

  create_table "ai_rag_queries", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "agent_execution_id"
    t.float "avg_similarity_score"
    t.integer "chunks_retrieved", default: 0
    t.datetime "created_at", null: false
    t.boolean "enable_reranking", default: false
    t.jsonb "filters", default: {}
    t.integer "graph_depth", default: 2
    t.uuid "knowledge_base_id", null: false
    t.jsonb "metadata", default: {}
    t.uuid "mission_id"
    t.vector "query_embedding", limit: 1536
    t.float "query_latency_ms"
    t.text "query_text", null: false
    t.string "retrieval_strategy", default: "similarity"
    t.jsonb "retrieved_chunks", default: []
    t.string "search_mode", default: "vector"
    t.float "similarity_threshold", default: 0.7
    t.string "status", default: "completed", null: false
    t.integer "tokens_used", default: 0
    t.integer "top_k", default: 5
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["account_id", "created_at"]
    t.index ["account_id"]
    t.index ["knowledge_base_id", "created_at"]
    t.index ["knowledge_base_id"]
    t.index ["mission_id"]
    t.index ["query_embedding"], name: "idx_rag_queries_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["status"]
    t.index ["user_id"]
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "check_rag_query_status"
  end

  create_table "ai_ralph_iterations", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.text "ai_output"
    t.text "ai_prompt"
    t.jsonb "ai_response_metadata", default: {}
    t.jsonb "check_results", default: {}
    t.boolean "checks_passed"
    t.datetime "completed_at"
    t.decimal "cost", precision: 10, scale: 6, default: "0.0"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "error_code"
    t.jsonb "error_details", default: {}
    t.text "error_message"
    t.string "git_branch"
    t.string "git_commit_sha"
    t.integer "iteration_number", null: false
    t.text "learning_extracted"
    t.uuid "ralph_loop_id", null: false
    t.uuid "ralph_task_id"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.integer "tokens_input", default: 0
    t.integer "tokens_output", default: 0
    t.datetime "updated_at", null: false
    t.index ["git_commit_sha"], name: "index_ai_ralph_iterations_on_git_commit_sha", where: "(git_commit_sha IS NOT NULL)"
    t.index ["ralph_loop_id", "iteration_number"], unique: true
    t.index ["ralph_loop_id"]
    t.index ["ralph_task_id"]
    t.index ["status"]
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'skipped'::character varying::text])", name: "ai_ralph_iterations_status_check"
  end

  create_table "ai_ralph_loops", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "ai_tool"
    t.string "branch", default: "main"
    t.boolean "code_factory_mode", default: false
    t.datetime "completed_at"
    t.integer "completed_tasks", default: 0
    t.jsonb "configuration", default: {}
    t.uuid "container_instance_id"
    t.datetime "created_at", null: false
    t.integer "current_iteration", default: 0
    t.integer "daily_iteration_count", default: 0
    t.date "daily_iteration_reset_at"
    t.uuid "default_agent_id"
    t.text "description"
    t.integer "duration_ms"
    t.jsonb "duty_cycle_config", default: {}
    t.string "error_code"
    t.jsonb "error_details", default: {}
    t.text "error_message"
    t.integer "failed_tasks", default: 0
    t.datetime "last_scheduled_at"
    t.jsonb "learnings", default: []
    t.integer "max_iterations", default: 100
    t.uuid "mission_id"
    t.string "name", null: false
    t.datetime "next_scheduled_at"
    t.jsonb "prd_json", default: {}
    t.text "progress_text"
    t.string "repository_url"
    t.uuid "risk_contract_id"
    t.jsonb "schedule_config", default: {}
    t.boolean "schedule_paused", default: false
    t.datetime "schedule_paused_at"
    t.string "schedule_paused_reason"
    t.string "scheduling_mode", default: "manual"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.integer "total_tasks", default: 0
    t.datetime "updated_at", null: false
    t.string "webhook_token"
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["ai_tool"]
    t.index ["created_at"]
    t.index ["default_agent_id"]
    t.index ["mission_id"]
    t.index ["next_scheduled_at"]
    t.index ["risk_contract_id"]
    t.index ["schedule_paused", "next_scheduled_at"]
    t.index ["scheduling_mode"]
    t.index ["status"]
    t.index ["webhook_token"], name: "index_ai_ralph_loops_on_webhook_token", unique: true, where: "(webhook_token IS NOT NULL)"
    t.check_constraint "ai_tool::text = ANY (ARRAY['amp'::character varying::text, 'claude_code'::character varying::text, 'ollama'::character varying::text])", name: "ai_ralph_loops_ai_tool_check"
    t.check_constraint "scheduling_mode::text = ANY (ARRAY['manual'::character varying::text, 'scheduled'::character varying::text, 'continuous'::character varying::text, 'event_triggered'::character varying::text, 'autonomous'::character varying::text])", name: "ai_ralph_loops_scheduling_mode_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'paused'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text])", name: "ai_ralph_loops_status_check"
  end

  create_table "ai_ralph_tasks", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.text "acceptance_criteria"
    t.string "capability_match_strategy", default: "all"
    t.integer "completed_in_iteration"
    t.datetime "created_at", null: false
    t.jsonb "delegation_config", default: {}
    t.jsonb "dependencies", default: []
    t.text "description"
    t.string "error_code"
    t.text "error_message"
    t.integer "execution_attempts", default: 0
    t.string "execution_type", default: "agent"
    t.uuid "executor_id"
    t.string "executor_type"
    t.datetime "iteration_completed_at"
    t.uuid "last_executor_id"
    t.string "last_executor_type"
    t.jsonb "metadata", default: {}
    t.integer "position"
    t.integer "priority", default: 0
    t.uuid "ralph_loop_id", null: false
    t.boolean "repeating", default: false, null: false
    t.jsonb "required_capabilities", default: []
    t.string "revert_reason"
    t.datetime "reverted_at"
    t.string "status", default: "pending", null: false
    t.string "task_key", null: false
    t.datetime "updated_at", null: false
    t.index ["capability_match_strategy"]
    t.index ["execution_type"]
    t.index ["executor_type", "executor_id"]
    t.index ["last_executor_type", "last_executor_id"]
    t.index ["priority"]
    t.index ["ralph_loop_id", "task_key"], unique: true
    t.index ["ralph_loop_id"]
    t.index ["required_capabilities"], name: "index_ai_ralph_tasks_on_required_capabilities", using: :gin
    t.index ["reverted_at"]
    t.index ["status"]
    t.check_constraint "capability_match_strategy::text = ANY (ARRAY['all'::character varying::text, 'any'::character varying::text, 'weighted'::character varying::text])", name: "ai_ralph_tasks_capability_match_strategy_check"
    t.check_constraint "execution_type::text = ANY (ARRAY['agent'::character varying::text, 'workflow'::character varying::text, 'pipeline'::character varying::text, 'a2a_task'::character varying::text, 'container'::character varying::text, 'human'::character varying::text, 'community'::character varying::text])", name: "ai_ralph_tasks_execution_type_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'in_progress'::character varying::text, 'passed'::character varying::text, 'failed'::character varying::text, 'blocked'::character varying::text, 'skipped'::character varying::text])", name: "ai_ralph_tasks_status_check"
  end

  create_table "ai_recorded_interactions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.decimal "cost_usd", precision: 10, scale: 4, default: "0.0"
    t.datetime "created_at", null: false
    t.string "interaction_type", null: false
    t.integer "latency_ms"
    t.jsonb "metadata", default: {}
    t.string "model_name"
    t.string "provider_type"
    t.datetime "recorded_at"
    t.string "recording_id", null: false
    t.jsonb "request_data", default: {}
    t.jsonb "response_data", default: {}
    t.uuid "sandbox_id", null: false
    t.integer "sequence_number"
    t.integer "tokens_input", default: 0
    t.integer "tokens_output", default: 0
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["interaction_type"]
    t.index ["recording_id"], unique: true
    t.index ["sandbox_id", "recorded_at"]
    t.index ["sandbox_id"]
    t.check_constraint "interaction_type::text = ANY (ARRAY['llm_request'::character varying::text, 'tool_call'::character varying::text, 'api_call'::character varying::text, 'workflow_step'::character varying::text, 'agent_action'::character varying::text])", name: "check_interaction_type"
  end

  create_table "ai_remediation_logs", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "action_config", default: {}
    t.string "action_type", null: false
    t.jsonb "after_state", default: {}
    t.jsonb "before_state", default: {}
    t.datetime "created_at", null: false
    t.datetime "executed_at", null: false
    t.string "result", null: false
    t.text "result_message"
    t.string "trigger_event", null: false
    t.string "trigger_source", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "executed_at"]
    t.index ["account_id"]
    t.index ["action_type"]
    t.index ["result"]
  end

  create_table "ai_roi_metrics", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.decimal "accuracy_rate", precision: 5, scale: 4
    t.decimal "ai_cost_usd", precision: 12, scale: 4, default: "0.0", null: false
    t.uuid "attributable_id"
    t.string "attributable_type"
    t.decimal "baseline_cost_usd", precision: 12, scale: 4
    t.decimal "baseline_time_hours", precision: 10, scale: 2
    t.decimal "cost_per_task_usd", precision: 12, scale: 6
    t.datetime "created_at", null: false
    t.decimal "customer_satisfaction_score", precision: 3, scale: 2
    t.decimal "efficiency_gain_percentage", precision: 10, scale: 2
    t.decimal "error_reduction_value_usd", precision: 12, scale: 4, default: "0.0", null: false
    t.integer "errors_prevented", default: 0, null: false
    t.decimal "infrastructure_cost_usd", precision: 12, scale: 4, default: "0.0", null: false
    t.integer "manual_interventions", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "metric_type", null: false
    t.decimal "net_benefit_usd", precision: 12, scale: 4
    t.date "period_date", null: false
    t.string "period_type", default: "daily", null: false
    t.decimal "roi_percentage", precision: 10, scale: 2
    t.integer "tasks_automated", default: 0, null: false
    t.integer "tasks_completed", default: 0, null: false
    t.decimal "throughput_value_usd", precision: 12, scale: 4, default: "0.0", null: false
    t.decimal "time_saved_hours", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "time_saved_value_usd", precision: 12, scale: 4, default: "0.0", null: false
    t.decimal "total_cost_usd", precision: 12, scale: 4, default: "0.0", null: false
    t.decimal "total_value_usd", precision: 12, scale: 4, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.decimal "value_per_task_usd", precision: 12, scale: 6
    t.index ["account_id", "metric_type", "period_date"]
    t.index ["account_id", "period_type", "period_date"]
    t.index ["account_id"]
    t.index ["attributable_type", "attributable_id"]
    t.index ["period_date"]
    t.check_constraint "metric_type::text = ANY (ARRAY['workflow'::character varying::text, 'agent'::character varying::text, 'provider'::character varying::text, 'team'::character varying::text, 'account_total'::character varying::text, 'department'::character varying::text])", name: "check_roi_metric_type"
    t.check_constraint "period_type::text = ANY (ARRAY['daily'::character varying::text, 'weekly'::character varying::text, 'monthly'::character varying::text, 'quarterly'::character varying::text, 'yearly'::character varying::text])", name: "check_roi_period_type"
  end

  create_table "ai_role_profiles", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.jsonb "communication_style", default: {}
    t.datetime "created_at", null: false
    t.jsonb "delegation_rules", default: {}
    t.text "description"
    t.jsonb "escalation_rules", default: {}
    t.jsonb "expected_output_schema", default: {}
    t.boolean "is_system", default: false, null: false
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.jsonb "quality_checks", default: []
    t.jsonb "review_criteria", default: []
    t.string "role_type", null: false
    t.string "slug", null: false
    t.text "system_prompt_template"
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["is_system"]
    t.index ["slug"], unique: true
  end

  create_table "ai_routing_decisions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.decimal "actual_cost_usd", precision: 12, scale: 8
    t.integer "actual_latency_ms"
    t.integer "actual_tokens_used"
    t.uuid "agent_execution_id"
    t.decimal "alternative_cost_usd", precision: 12, scale: 8
    t.integer "cached_tokens", default: 0
    t.jsonb "candidates_evaluated", default: [], null: false
    t.uuid "complexity_assessment_id"
    t.datetime "created_at", null: false
    t.string "decision_reason"
    t.decimal "estimated_cost_usd", precision: 12, scale: 8
    t.integer "estimated_tokens"
    t.string "model_tier"
    t.string "outcome"
    t.decimal "quality_score", precision: 5, scale: 4
    t.jsonb "request_metadata", default: {}, null: false
    t.string "request_type", null: false
    t.uuid "routing_rule_id"
    t.decimal "savings_usd", precision: 12, scale: 8
    t.jsonb "scoring_breakdown", default: {}, null: false
    t.uuid "selected_provider_id"
    t.string "strategy_used", null: false
    t.datetime "updated_at", null: false
    t.boolean "was_cached", default: false
    t.boolean "was_compressed", default: false
    t.index ["account_id", "created_at"]
    t.index ["account_id"]
    t.index ["agent_execution_id"]
    t.index ["complexity_assessment_id"]
    t.index ["created_at"]
    t.index ["outcome"]
    t.index ["routing_rule_id"]
    t.index ["selected_provider_id", "created_at"]
    t.index ["selected_provider_id"]
    t.index ["strategy_used", "outcome"]
  end

  create_table "ai_runner_dispatches", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "dispatched_at"
    t.integer "duration_ms"
    t.uuid "git_repository_id"
    t.uuid "git_runner_id"
    t.jsonb "input_params", default: {}
    t.text "logs"
    t.uuid "mission_id"
    t.jsonb "output_result", default: {}
    t.jsonb "runner_labels", default: []
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.string "workflow_run_id"
    t.string "workflow_url"
    t.uuid "worktree_id"
    t.uuid "worktree_session_id"
    t.index ["account_id"]
    t.index ["git_repository_id"]
    t.index ["git_runner_id"]
    t.index ["mission_id"]
    t.index ["worktree_id"]
    t.index ["worktree_session_id"]
  end

  create_table "ai_sandboxes", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "configuration", default: {}
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.text "description"
    t.jsonb "environment_variables", default: {}
    t.datetime "expires_at"
    t.boolean "is_isolated", default: true, null: false
    t.datetime "last_used_at"
    t.jsonb "mock_providers", default: {}
    t.string "name", null: false
    t.boolean "recording_enabled", default: false, null: false
    t.jsonb "resource_limits", default: {}
    t.string "sandbox_type", default: "standard", null: false
    t.string "status", default: "inactive", null: false
    t.integer "test_runs_count", default: 0
    t.integer "total_executions", default: 0
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], unique: true
    t.index ["account_id"]
    t.index ["created_by_id"]
    t.index ["expires_at"]
    t.index ["sandbox_type"]
    t.index ["status"]
    t.check_constraint "sandbox_type::text = ANY (ARRAY['standard'::character varying::text, 'isolated'::character varying::text, 'production_mirror'::character varying::text, 'performance'::character varying::text, 'security'::character varying::text])", name: "check_sandbox_type"
    t.check_constraint "status::text = ANY (ARRAY['inactive'::character varying::text, 'active'::character varying::text, 'paused'::character varying::text, 'expired'::character varying::text, 'deleted'::character varying::text])", name: "check_sandbox_status"
  end

  create_table "ai_scheduled_messages", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "conversation_id", null: false
    t.datetime "created_at", null: false
    t.integer "daily_iteration_count", default: 0, null: false
    t.date "daily_iteration_reset_at"
    t.integer "execution_count", default: 0, null: false
    t.datetime "last_executed_at"
    t.datetime "last_scheduled_at"
    t.integer "max_executions"
    t.text "message_template", null: false
    t.datetime "next_scheduled_at"
    t.jsonb "schedule_config", default: {}, null: false
    t.boolean "schedule_paused", default: false, null: false
    t.datetime "schedule_paused_at"
    t.string "schedule_paused_reason"
    t.string "scheduling_mode", null: false
    t.string "status", default: "active", null: false
    t.jsonb "template_variables", default: {}, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["conversation_id"]
    t.index ["status", "next_scheduled_at"]
    t.index ["user_id"]
  end

  create_table "ai_security_audit_trails", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "action", null: false
    t.uuid "agent_id"
    t.string "asi_reference"
    t.jsonb "context", default: {}
    t.datetime "created_at", null: false
    t.string "csa_pillar"
    t.jsonb "details", default: {}
    t.inet "ip_address"
    t.string "outcome", null: false
    t.decimal "risk_score", precision: 5, scale: 4
    t.string "severity"
    t.string "source_service"
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["account_id"]
    t.index ["action"]
    t.index ["agent_id"]
    t.index ["asi_reference"]
    t.index ["created_at"]
    t.index ["outcome"]
    t.index ["severity"]
  end

  create_table "ai_self_challenges", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_skill_id"
    t.string "challenge_id", null: false
    t.text "challenge_prompt"
    t.uuid "challenger_agent_id", null: false
    t.datetime "created_at", null: false
    t.string "difficulty", default: "medium", null: false
    t.text "execution_result"
    t.uuid "executor_agent_id"
    t.jsonb "expected_criteria", default: {}
    t.decimal "quality_score", precision: 5, scale: 4
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.jsonb "validation_result", default: {}
    t.uuid "validator_agent_id"
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["ai_skill_id"]
    t.index ["challenge_id"], unique: true
    t.index ["challenger_agent_id", "status"]
    t.index ["challenger_agent_id"]
    t.index ["executor_agent_id"]
    t.index ["validator_agent_id"]
  end

  create_table "ai_shadow_executions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "action_type", null: false
    t.uuid "agent_id", null: false
    t.boolean "agreed", default: false, null: false
    t.float "agreement_score", default: 0.0, null: false
    t.datetime "created_at", null: false
    t.jsonb "reference_output", default: {}
    t.jsonb "shadow_input", default: {}, null: false
    t.jsonb "shadow_output", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "agent_id", "created_at"]
    t.index ["account_id"]
    t.index ["agent_id", "agreed"]
    t.index ["agent_id"]
  end

  create_table "ai_shared_knowledges", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "access_level", default: "team"
    t.uuid "account_id", null: false
    t.text "content", null: false
    t.string "content_type", default: "text"
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.vector "embedding", limit: 1536
    t.uuid "git_repository_id"
    t.string "integrity_hash"
    t.datetime "last_event_processed_at"
    t.datetime "last_quality_recalc_at"
    t.datetime "last_used_at"
    t.jsonb "provenance", default: {}
    t.decimal "quality_score", precision: 5, scale: 4
    t.integer "rating_count", default: 0, null: false
    t.integer "rating_sum", default: 0, null: false
    t.uuid "source_id"
    t.string "source_type"
    t.string "tags", default: [], array: true
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "usage_count", default: 0
    t.index ["access_level"]
    t.index ["account_id"]
    t.index ["created_by_id"]
    t.index ["embedding"], name: "index_ai_shared_knowledges_on_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["git_repository_id"]
    t.index ["last_event_processed_at"]
    t.index ["source_type", "source_id"]
    t.index ["tags"], name: "index_ai_shared_knowledges_on_tags", using: :gin
  end

  create_table "ai_skill_compositions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "component_skill_id", null: false
    t.uuid "composite_skill_id", null: false
    t.string "composition_type", default: "sequential", null: false
    t.jsonb "condition", default: {}
    t.datetime "created_at", null: false
    t.integer "execution_order", null: false
    t.jsonb "input_mapping", default: {}
    t.jsonb "output_mapping", default: {}
    t.datetime "updated_at", null: false
    t.index ["component_skill_id"]
    t.index ["composite_skill_id", "execution_order"], unique: true
    t.index ["composite_skill_id"]
  end

  create_table "ai_skill_conflicts", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.boolean "auto_resolvable", default: false
    t.string "conflict_type", null: false
    t.datetime "created_at", null: false
    t.datetime "detected_at"
    t.uuid "edge_id"
    t.uuid "node_a_id"
    t.uuid "node_b_id"
    t.float "priority_score"
    t.jsonb "resolution_details", default: {}
    t.string "resolution_strategy"
    t.datetime "resolved_at"
    t.uuid "resolved_by_id"
    t.string "severity", null: false
    t.float "similarity_score"
    t.uuid "skill_a_id", null: false
    t.uuid "skill_b_id"
    t.string "status", default: "detected", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["skill_a_id", "skill_b_id", "conflict_type"], name: "idx_skill_conflicts_unique_active", unique: true, where: "((status)::text <> ALL (ARRAY[('resolved'::character varying)::text, ('dismissed'::character varying)::text]))"
    t.index ["skill_a_id"]
    t.index ["skill_b_id"]
  end

  create_table "ai_skill_proposals", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.boolean "auto_approved", default: false
    t.string "category"
    t.jsonb "commands", default: []
    t.float "confidence_score", default: 0.0
    t.datetime "created_at", null: false
    t.uuid "created_skill_id"
    t.text "description"
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.jsonb "overlap_analysis", default: {}
    t.uuid "parent_proposal_id"
    t.datetime "proposed_at"
    t.uuid "proposed_by_agent_id"
    t.uuid "proposed_by_user_id"
    t.text "rejection_reason"
    t.jsonb "research_report", default: {}
    t.datetime "reviewed_at"
    t.uuid "reviewed_by_id"
    t.string "slug"
    t.string "status", default: "draft", null: false
    t.jsonb "suggested_dependencies", default: []
    t.text "system_prompt"
    t.jsonb "tags", default: []
    t.string "trust_tier_at_proposal"
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "idx_skill_proposals_unique_active_name", unique: true, where: "((status)::text <> ALL (ARRAY[('rejected'::character varying)::text, ('created'::character varying)::text]))"
    t.index ["account_id"]
    t.index ["parent_proposal_id"]
    t.index ["proposed_by_agent_id"]
    t.index ["proposed_by_user_id"]
  end

  create_table "ai_skill_recipe_runs", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_agent_id"
    t.uuid "ai_skill_id", null: false
    t.datetime "created_at", null: false
    t.boolean "dry_run", default: false, null: false
    t.text "error_message"
    t.string "failed_step_id"
    t.datetime "finished_at"
    t.jsonb "inputs", default: {}, null: false
    t.jsonb "outputs", default: {}, null: false
    t.string "pending_step_id"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.jsonb "steps_log", default: [], null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["ai_skill_id", "created_at"]
    t.index ["status"]
    t.index ["user_id", "created_at"]
  end

  create_table "ai_skill_usage_records", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_agent_id"
    t.uuid "ai_skill_id", null: false
    t.float "confidence_delta"
    t.text "context_summary"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.uuid "execution_id"
    t.string "execution_type"
    t.jsonb "metadata", default: {}
    t.string "outcome", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["ai_agent_id", "created_at"]
    t.index ["ai_skill_id", "outcome"]
    t.index ["created_at"]
  end

  create_table "ai_skill_versions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.float "ab_traffic_pct", default: 0.0
    t.uuid "account_id", null: false
    t.uuid "ai_skill_id", null: false
    t.text "change_reason"
    t.string "change_type", default: "manual"
    t.jsonb "commands", default: []
    t.datetime "created_at", null: false
    t.uuid "created_by_agent_id"
    t.uuid "created_by_user_id"
    t.float "effectiveness_score", default: 0.5
    t.integer "failure_count", default: 0
    t.boolean "is_ab_variant", default: false
    t.boolean "is_active", default: false
    t.jsonb "metadata", default: {}
    t.integer "success_count", default: 0
    t.text "system_prompt"
    t.jsonb "tags", default: []
    t.datetime "updated_at", null: false
    t.integer "usage_count", default: 0
    t.string "version", null: false
    t.index ["account_id"]
    t.index ["ai_skill_id", "version"], unique: true
    t.index ["ai_skill_id"]
    t.index ["created_by_agent_id"]
    t.index ["created_by_user_id"]
  end

  create_table "ai_skills", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.jsonb "activation_rules", default: {}
    t.uuid "ai_knowledge_base_id"
    t.string "category", null: false
    t.jsonb "commands", default: []
    t.datetime "created_at", null: false
    t.text "description"
    t.decimal "effectiveness_score", precision: 5, scale: 4, default: "0.5"
    t.boolean "is_composite", default: false, null: false
    t.boolean "is_enabled", default: true, null: false
    t.boolean "is_system", default: false, null: false
    t.datetime "last_optimized_at"
    t.datetime "last_used_at"
    t.jsonb "lifecycle_metadata", default: {}
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.integer "negative_usage_count", default: 0
    t.uuid "parent_skill_id"
    t.integer "positive_usage_count", default: 0
    t.string "slug", null: false
    t.string "status", default: "active"
    t.text "system_prompt"
    t.jsonb "tags", default: []
    t.datetime "updated_at", null: false
    t.integer "usage_count", default: 0, null: false
    t.string "version", default: "1.0.0"
    t.index ["account_id"]
    t.index ["ai_knowledge_base_id"]
    t.index ["category"]
    t.index ["is_system"]
    t.index ["parent_skill_id"]
    t.index ["slug"], unique: true
    t.index ["status"]
    t.index ["tags"], name: "index_ai_skills_on_tags", using: :gin
  end

  create_table "ai_skills_mcp_servers", id: false, force: :cascade do |t|
    t.uuid "ai_skill_id", null: false
    t.uuid "mcp_server_id", null: false
    t.index ["ai_skill_id", "mcp_server_id"], unique: true
    t.index ["mcp_server_id"]
  end

  create_table "ai_stigmergic_signals", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.decimal "decay_rate", precision: 5, scale: 4, default: "0.05", null: false
    t.uuid "emitter_agent_id"
    t.datetime "expires_at"
    t.uuid "memory_pool_id"
    t.jsonb "payload", default: {}
    t.integer "perceive_count", default: 0, null: false
    t.integer "reinforce_count", default: 0, null: false
    t.jsonb "reinforcements", default: []
    t.string "signal_key", null: false
    t.string "signal_type", null: false
    t.decimal "strength", precision: 5, scale: 4, default: "1.0", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "signal_key"]
    t.index ["account_id", "signal_type"]
    t.index ["account_id"]
    t.index ["emitter_agent_id"]
    t.index ["expires_at"], name: "index_ai_stigmergic_signals_on_expires_at", where: "(expires_at IS NOT NULL)"
    t.index ["memory_pool_id"]
    t.index ["strength"]
  end

  create_table "ai_task_complexity_assessments", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "actual_tier_used"
    t.string "classifier_version", null: false
    t.string "complexity_level", null: false
    t.decimal "complexity_score", precision: 5, scale: 4, null: false
    t.jsonb "complexity_signals", default: {}
    t.integer "conversation_depth", default: 0
    t.datetime "created_at", null: false
    t.integer "input_token_count", default: 0
    t.string "recommended_tier", null: false
    t.uuid "routing_decision_id"
    t.string "task_type", null: false
    t.integer "tool_count", default: 0
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["complexity_level"]
    t.index ["recommended_tier"]
    t.index ["routing_decision_id"]
    t.index ["task_type"]
    t.check_constraint "complexity_level::text = ANY (ARRAY['trivial'::character varying::text, 'simple'::character varying::text, 'moderate'::character varying::text, 'complex'::character varying::text, 'expert'::character varying::text])", name: "chk_ai_task_complexity_level"
    t.check_constraint "recommended_tier::text = ANY (ARRAY['economy'::character varying::text, 'standard'::character varying::text, 'premium'::character varying::text])", name: "chk_ai_task_recommended_tier"
  end

  create_table "ai_task_reviews", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.text "approval_notes"
    t.jsonb "code_suggestions", default: {}
    t.string "commit_sha"
    t.jsonb "completeness_checks", default: {}
    t.datetime "created_at", null: false
    t.jsonb "diff_analysis", default: {}
    t.jsonb "file_comments", default: {}
    t.jsonb "findings", default: []
    t.jsonb "metadata", default: {}
    t.integer "pull_request_number"
    t.float "quality_score"
    t.text "rejection_reason"
    t.string "repository_url"
    t.integer "review_duration_ms"
    t.string "review_id", null: false
    t.string "review_mode", default: "blocking", null: false
    t.uuid "reviewer_agent_id"
    t.uuid "reviewer_role_id"
    t.integer "revision_count", default: 0
    t.string "status", default: "pending", null: false
    t.uuid "team_task_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["review_id"], unique: true
    t.index ["reviewer_agent_id"]
    t.index ["reviewer_role_id"]
    t.index ["team_task_id", "status"]
    t.index ["team_task_id"]
  end

  create_table "ai_team_channels", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "agent_team_id", null: false
    t.string "channel_type", default: "broadcast", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "is_persistent", default: true, null: false
    t.integer "message_retention_hours"
    t.jsonb "message_schema", default: {}
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.jsonb "participant_roles", default: []
    t.jsonb "routing_rules", default: {}
    t.datetime "updated_at", null: false
    t.index ["agent_team_id", "name"], unique: true
    t.index ["agent_team_id"]
    t.index ["channel_type"]
    t.check_constraint "channel_type::text = ANY (ARRAY['broadcast'::character varying::text, 'direct'::character varying::text, 'topic'::character varying::text, 'task'::character varying::text, 'escalation'::character varying::text])", name: "check_channel_type"
  end

  create_table "ai_team_executions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "agent_team_id", null: false
    t.uuid "ai_conversation_id"
    t.datetime "approval_decided_at"
    t.uuid "approval_decided_by_id"
    t.string "approval_decision"
    t.text "approval_feedback"
    t.datetime "completed_at"
    t.string "control_signal"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "execution_id", null: false
    t.jsonb "input_context", default: {}
    t.integer "messages_exchanged", default: 0
    t.jsonb "metadata", default: {}
    t.uuid "mission_id"
    t.text "objective"
    t.jsonb "output_result", default: {}
    t.datetime "paused_at"
    t.jsonb "performance_metrics", default: {}
    t.jsonb "redirect_instructions", default: {}
    t.integer "resume_count", default: 0
    t.jsonb "shared_memory", default: {}
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.integer "tasks_completed", default: 0
    t.integer "tasks_failed", default: 0
    t.integer "tasks_total", default: 0
    t.string "termination_reason"
    t.decimal "total_cost_usd", precision: 10, scale: 4, default: "0.0"
    t.integer "total_tokens_used", default: 0
    t.uuid "triggered_by_id"
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["agent_team_id", "created_at"]
    t.index ["agent_team_id"]
    t.index ["ai_conversation_id"]
    t.index ["control_signal"]
    t.index ["execution_id"], unique: true
    t.index ["mission_id"]
    t.index ["started_at"]
    t.index ["triggered_by_id"]
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'paused'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text, 'timeout'::character varying::text, 'awaiting_approval'::character varying::text])", name: "check_team_execution_status"
  end

  create_table "ai_team_messages", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "attachments", default: []
    t.uuid "channel_id"
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.uuid "from_role_id"
    t.uuid "in_reply_to_id"
    t.string "message_type", default: "task_update", null: false
    t.jsonb "metadata", default: {}
    t.string "priority", default: "normal"
    t.datetime "read_at"
    t.boolean "requires_response", default: false, null: false
    t.datetime "responded_at"
    t.integer "sequence_number"
    t.jsonb "structured_content", default: {}
    t.uuid "task_id"
    t.uuid "team_execution_id"
    t.uuid "to_role_id"
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["channel_id", "created_at"]
    t.index ["channel_id"]
    t.index ["from_role_id", "created_at"]
    t.index ["from_role_id"]
    t.index ["in_reply_to_id"]
    t.index ["message_type"]
    t.index ["team_execution_id", "sequence_number"]
    t.index ["team_execution_id"]
    t.index ["to_role_id"]
    t.index ["user_id"]
    t.check_constraint "message_type::text = ANY (ARRAY['task_assignment'::character varying::text, 'task_update'::character varying::text, 'task_result'::character varying::text, 'work_plan'::character varying::text, 'synthesis'::character varying::text, 'question'::character varying::text, 'answer'::character varying::text, 'escalation'::character varying::text, 'coordination'::character varying::text, 'broadcast'::character varying::text, 'human_input'::character varying::text])", name: "check_team_message_type"
  end

  create_table "ai_team_restructure_events", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_agent_id"
    t.uuid "ai_agent_team_id", null: false
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.jsonb "metrics_snapshot", default: {}
    t.jsonb "new_state", default: {}
    t.jsonb "previous_state", default: {}
    t.jsonb "rationale", default: {}
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["ai_agent_id"]
    t.index ["ai_agent_team_id", "event_type"]
    t.index ["ai_agent_team_id"]
  end

  create_table "ai_team_roles", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "agent_team_id", null: false
    t.uuid "ai_agent_id"
    t.boolean "can_delegate", default: false, null: false
    t.boolean "can_escalate", default: true, null: false
    t.jsonb "capabilities", default: []
    t.jsonb "constraints", default: []
    t.jsonb "context_access", default: {}
    t.datetime "created_at", null: false
    t.text "goals"
    t.integer "max_concurrent_tasks", default: 1
    t.jsonb "metadata", default: {}
    t.integer "priority_order", default: 0
    t.text "responsibilities"
    t.text "role_description"
    t.string "role_name", null: false
    t.string "role_type", default: "worker", null: false
    t.jsonb "tools_allowed", default: []
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["agent_team_id", "priority_order"]
    t.index ["agent_team_id", "role_name"], unique: true
    t.index ["agent_team_id"]
    t.index ["ai_agent_id"]
    t.index ["role_type"]
    t.check_constraint "role_type::text = ANY (ARRAY['manager'::character varying::text, 'coordinator'::character varying::text, 'worker'::character varying::text, 'specialist'::character varying::text, 'reviewer'::character varying::text, 'validator'::character varying::text])", name: "check_team_role_type"
  end

  create_table "ai_team_tasks", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "assigned_agent_id"
    t.datetime "assigned_at"
    t.uuid "assigned_role_id"
    t.datetime "completed_at"
    t.decimal "cost_usd", precision: 10, scale: 4, default: "0.0"
    t.datetime "created_at", null: false
    t.uuid "delegated_from_task_id"
    t.text "description", null: false
    t.integer "duration_ms"
    t.text "expected_output"
    t.string "failure_reason"
    t.jsonb "input_data", default: {}
    t.integer "max_retries", default: 3
    t.jsonb "metadata", default: {}
    t.jsonb "output_data", default: {}
    t.uuid "parent_task_id"
    t.integer "priority", default: 5
    t.integer "retry_count", default: 0
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.string "task_id", null: false
    t.string "task_type", default: "execution", null: false
    t.uuid "team_execution_id", null: false
    t.integer "tokens_used", default: 0
    t.jsonb "tools_used", default: []
    t.datetime "updated_at", null: false
    t.index ["assigned_agent_id"]
    t.index ["assigned_role_id", "status"]
    t.index ["assigned_role_id"]
    t.index ["parent_task_id"]
    t.index ["priority"]
    t.index ["task_id"], unique: true
    t.index ["team_execution_id", "status"]
    t.index ["team_execution_id"]
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'assigned'::character varying::text, 'in_progress'::character varying::text, 'waiting'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text, 'delegated'::character varying::text])", name: "check_team_task_status"
    t.check_constraint "task_type::text = ANY (ARRAY['execution'::character varying::text, 'review'::character varying::text, 'validation'::character varying::text, 'coordination'::character varying::text, 'escalation'::character varying::text, 'human_input'::character varying::text])", name: "check_team_task_type"
  end

  create_table "ai_team_templates", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.float "average_rating"
    t.string "category"
    t.jsonb "channel_definitions", default: []
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.jsonb "default_config", default: {}
    t.text "description"
    t.boolean "is_public", default: false, null: false
    t.boolean "is_system", default: false, null: false
    t.string "name", null: false
    t.datetime "published_at"
    t.jsonb "role_definitions", default: []
    t.string "slug", null: false
    t.jsonb "tags", default: []
    t.string "team_topology", default: "hierarchical", null: false
    t.datetime "updated_at", null: false
    t.integer "usage_count", default: 0
    t.jsonb "workflow_pattern", default: {}
    t.index ["account_id"]
    t.index ["created_by_id"]
    t.index ["is_public", "category"]
    t.index ["is_system"]
    t.index ["slug"], unique: true
    t.index ["team_topology"]
    t.check_constraint "team_topology::text = ANY (ARRAY['hierarchical'::character varying::text, 'flat'::character varying::text, 'mesh'::character varying::text, 'pipeline'::character varying::text, 'hybrid'::character varying::text])", name: "check_team_topology"
  end

  create_table "ai_telemetry_events", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "agent_id", null: false
    t.string "correlation_id", null: false
    t.datetime "created_at", null: false
    t.string "event_category", null: false
    t.jsonb "event_data", default: {}, null: false
    t.string "event_type", null: false
    t.string "outcome"
    t.uuid "parent_event_id"
    t.integer "sequence_number", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"]
    t.index ["account_id"]
    t.index ["agent_id", "event_category", "created_at"]
    t.index ["agent_id"]
    t.index ["correlation_id"]
    t.index ["parent_event_id"]
  end

  create_table "ai_template_usage_metrics", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.integer "active_installations", default: 0, null: false
    t.uuid "agent_template_id", null: false
    t.decimal "average_rating", precision: 3, scale: 2
    t.decimal "conversion_rate", precision: 5, scale: 2
    t.datetime "created_at", null: false
    t.decimal "gross_revenue", precision: 15, scale: 2, default: "0.0", null: false
    t.date "metric_date", null: false
    t.integer "new_installations", default: 0, null: false
    t.integer "new_reviews", default: 0, null: false
    t.integer "page_views", default: 0, null: false
    t.decimal "platform_commission", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "publisher_revenue", precision: 15, scale: 2, default: "0.0", null: false
    t.integer "total_executions", default: 0, null: false
    t.integer "total_installations", default: 0, null: false
    t.integer "total_reviews", default: 0, null: false
    t.integer "uninstallations", default: 0, null: false
    t.integer "unique_visitors", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["agent_template_id", "metric_date"], unique: true
    t.index ["agent_template_id"]
    t.index ["metric_date"]
  end

  create_table "ai_test_results", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "actual_output", default: {}
    t.jsonb "assertion_results", default: []
    t.datetime "completed_at"
    t.decimal "cost_usd", precision: 10, scale: 4, default: "0.0"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.jsonb "error_details", default: {}
    t.jsonb "input_used", default: {}
    t.jsonb "logs", default: []
    t.jsonb "metrics", default: {}
    t.string "result_id", null: false
    t.integer "retry_attempt", default: 0
    t.uuid "scenario_id", null: false
    t.datetime "started_at"
    t.string "status", null: false
    t.uuid "test_run_id", null: false
    t.integer "tokens_used", default: 0
    t.datetime "updated_at", null: false
    t.index ["result_id"], unique: true
    t.index ["scenario_id", "created_at"]
    t.index ["scenario_id"]
    t.index ["test_run_id", "status"]
    t.index ["test_run_id"]
    t.check_constraint "status::text = ANY (ARRAY['passed'::character varying::text, 'failed'::character varying::text, 'skipped'::character varying::text, 'error'::character varying::text, 'timeout'::character varying::text])", name: "check_test_result_status"
  end

  create_table "ai_test_runs", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.jsonb "environment", default: {}
    t.integer "failed_assertions", default: 0
    t.integer "failed_scenarios", default: 0
    t.integer "passed_assertions", default: 0
    t.integer "passed_scenarios", default: 0
    t.string "run_id", null: false
    t.string "run_type", default: "manual", null: false
    t.uuid "sandbox_id", null: false
    t.jsonb "scenario_ids", default: []
    t.integer "skipped_scenarios", default: 0
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.jsonb "summary", default: {}
    t.integer "total_assertions", default: 0
    t.integer "total_scenarios", default: 0
    t.uuid "triggered_by_id"
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["run_id"], unique: true
    t.index ["run_type"]
    t.index ["sandbox_id", "created_at"]
    t.index ["sandbox_id"]
    t.index ["triggered_by_id"]
    t.check_constraint "run_type::text = ANY (ARRAY['manual'::character varying::text, 'scheduled'::character varying::text, 'ci_triggered'::character varying::text, 'regression'::character varying::text, 'smoke'::character varying::text])", name: "check_test_run_type"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text, 'timeout'::character varying::text])", name: "check_test_run_status"
  end

  create_table "ai_test_scenarios", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "assertions", default: []
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.text "description"
    t.jsonb "expected_output", default: {}
    t.integer "fail_count", default: 0
    t.jsonb "input_data", default: {}
    t.datetime "last_run_at"
    t.integer "max_retries", default: 3
    t.jsonb "mock_responses", default: []
    t.string "name", null: false
    t.integer "pass_count", default: 0
    t.float "pass_rate"
    t.integer "retry_count", default: 0
    t.integer "run_count", default: 0
    t.uuid "sandbox_id", null: false
    t.string "scenario_type", null: false
    t.jsonb "setup_steps", default: []
    t.string "status", default: "draft", null: false
    t.jsonb "tags", default: []
    t.uuid "target_agent_id"
    t.jsonb "teardown_steps", default: []
    t.integer "timeout_seconds", default: 300
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["created_by_id"]
    t.index ["sandbox_id", "name"], unique: true
    t.index ["sandbox_id"]
    t.index ["scenario_type"]
    t.index ["target_agent_id"]
    t.check_constraint "scenario_type::text = ANY (ARRAY['unit'::character varying::text, 'integration'::character varying::text, 'regression'::character varying::text, 'performance'::character varying::text, 'security'::character varying::text, 'chaos'::character varying::text, 'custom'::character varying::text])", name: "check_scenario_type"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'active'::character varying::text, 'disabled'::character varying::text, 'archived'::character varying::text])", name: "check_scenario_status"
  end

  create_table "ai_trajectories", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.integer "access_count", default: 0
    t.uuid "account_id", null: false
    t.uuid "ai_agent_id"
    t.integer "chapter_count", default: 0
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}
    t.jsonb "outcome_summary", default: {}
    t.float "quality_score"
    t.string "status", default: "building", null: false
    t.text "summary"
    t.jsonb "tags", default: []
    t.uuid "team_execution_id"
    t.string "title", null: false
    t.string "trajectory_id", null: false
    t.string "trajectory_type", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["ai_agent_id"]
    t.index ["status"]
    t.index ["tags"], name: "index_ai_trajectories_on_tags", using: :gin
    t.index ["team_execution_id"]
    t.index ["trajectory_id"], unique: true
  end

  create_table "ai_trajectory_chapters", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "artifacts", default: []
    t.integer "chapter_number", null: false
    t.string "chapter_type", null: false
    t.text "content", null: false
    t.jsonb "context_references", default: []
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.jsonb "key_decisions", default: []
    t.jsonb "metadata", default: {}
    t.text "reasoning"
    t.string "title", null: false
    t.uuid "trajectory_id", null: false
    t.datetime "updated_at", null: false
    t.index ["chapter_type"]
    t.index ["trajectory_id", "chapter_number"], unique: true
    t.index ["trajectory_id"]
  end

  create_table "ai_worktree_sessions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.boolean "auto_cleanup", default: true, null: false
    t.string "base_branch", default: "main", null: false
    t.datetime "completed_at"
    t.integer "completed_worktrees", default: 0, null: false
    t.jsonb "configuration", default: {}, null: false
    t.jsonb "conflict_matrix", default: {}
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "error_code"
    t.jsonb "error_details", default: {}, null: false
    t.text "error_message"
    t.string "execution_mode", default: "complementary"
    t.integer "failed_worktrees", default: 0, null: false
    t.uuid "initiated_by_id"
    t.string "integration_branch"
    t.integer "max_duration_seconds"
    t.integer "max_parallel", default: 4, null: false
    t.jsonb "merge_config", default: {}, null: false
    t.string "merge_strategy", default: "sequential", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "repository_path", null: false
    t.uuid "source_id"
    t.string "source_type"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.integer "total_worktrees", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["initiated_by_id"]
    t.index ["source_type", "source_id"]
    t.index ["status"]
  end

  create_table "ai_worktrees", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_agent_id"
    t.uuid "assignee_id"
    t.string "assignee_type"
    t.string "base_commit_sha"
    t.string "branch_name", null: false
    t.integer "commit_count", default: 0, null: false
    t.datetime "completed_at"
    t.jsonb "copied_config_files", default: [], null: false
    t.datetime "created_at", null: false
    t.bigint "disk_usage_bytes"
    t.integer "duration_ms"
    t.string "error_code"
    t.text "error_message"
    t.integer "estimated_cost_cents", default: 0
    t.integer "files_changed", default: 0, null: false
    t.string "head_commit_sha"
    t.string "health_message"
    t.boolean "healthy", default: true, null: false
    t.datetime "last_health_check_at"
    t.integer "lines_added", default: 0, null: false
    t.integer "lines_removed", default: 0, null: false
    t.string "lock_reason"
    t.boolean "locked", default: false, null: false
    t.datetime "locked_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "ready_at"
    t.string "status", default: "pending", null: false
    t.string "test_status"
    t.datetime "timeout_at"
    t.integer "tokens_used", default: 0
    t.datetime "updated_at", null: false
    t.string "worktree_path", null: false
    t.uuid "worktree_session_id", null: false
    t.index ["account_id"]
    t.index ["ai_agent_id"]
    t.index ["assignee_type", "assignee_id"]
    t.index ["branch_name"], unique: true
    t.index ["status"]
    t.index ["worktree_path"], unique: true
    t.index ["worktree_session_id"]
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

  create_table "audit_logs", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "action", limit: 100, null: false
    t.datetime "chain_verified_at"
    t.datetime "created_at", null: false
    t.string "integrity_hash"
    t.string "ip_address", limit: 45
    t.jsonb "metadata", default: {}
    t.jsonb "new_values", default: {}
    t.jsonb "old_values", default: {}
    t.string "previous_hash"
    t.string "request_id", limit: 50
    t.string "resource_id", limit: 36
    t.string "resource_type", limit: 100, null: false
    t.string "risk_level", default: "low", null: false
    t.bigint "sequence_number"
    t.string "severity", default: "medium", null: false
    t.string "source", limit: 20, default: "web", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent", limit: 1000
    t.uuid "user_id"
    t.index ["account_id", "created_at"]
    t.index ["account_id"]
    t.index ["action"]
    t.index ["chain_verified_at"]
    t.index ["created_at"]
    t.index ["integrity_hash"], name: "index_audit_logs_on_integrity_hash", unique: true, where: "(integrity_hash IS NOT NULL)"
    t.index ["request_id"]
    t.index ["resource_type", "resource_id"]
    t.index ["risk_level"]
    t.index ["sequence_number"], name: "index_audit_logs_on_sequence_number", unique: true, where: "(sequence_number IS NOT NULL)"
    t.index ["severity"]
    t.index ["user_id"]
  end

  create_table "background_jobs", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "arguments", default: {}
    t.integer "attempts", default: 0
    t.text "backtrace"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "failed_at"
    t.datetime "finished_at"
    t.string "job_id", null: false
    t.string "job_type", null: false
    t.integer "max_attempts", default: 25
    t.integer "priority", default: 0
    t.datetime "scheduled_at"
    t.datetime "started_at"
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.index ["created_at"]
    t.index ["job_id"], unique: true
    t.index ["job_type", "status"]
    t.index ["job_type"]
    t.index ["scheduled_at"]
    t.index ["status"]
    t.check_constraint "attempts >= 0 AND max_attempts > 0", name: "valid_job_attempts"
    t.check_constraint "priority >= 0", name: "valid_job_priority"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text, 'retrying'::character varying::text])", name: "valid_job_status"
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

  create_table "chat_blacklists", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "block_type", default: "temporary"
    t.uuid "blocked_by_id"
    t.uuid "channel_id"
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.jsonb "metadata", default: {}
    t.string "platform_user_id", null: false
    t.string "reason"
    t.datetime "updated_at", null: false
    t.index ["account_id", "platform_user_id"]
    t.index ["account_id"]
    t.index ["blocked_by_id"]
    t.index ["channel_id", "platform_user_id"], name: "index_chat_blacklists_on_channel_id_and_platform_user_id", unique: true, where: "(channel_id IS NOT NULL)"
    t.index ["channel_id"]
    t.index ["expires_at"], name: "index_chat_blacklists_on_expires_at", where: "(expires_at IS NOT NULL)"
    t.check_constraint "block_type::text = ANY (ARRAY['temporary'::character varying::text, 'permanent'::character varying::text])", name: "chat_blacklists_type_check"
  end

  create_table "chat_channels", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_team_channel_id"
    t.string "bridge_direction", default: "bidirectional"
    t.boolean "bridge_enabled", default: false
    t.jsonb "configuration", default: {}
    t.datetime "connected_at"
    t.datetime "created_at", null: false
    t.uuid "default_agent_id"
    t.text "last_error"
    t.datetime "last_error_at"
    t.datetime "last_message_at"
    t.integer "message_count", default: 0
    t.string "name", null: false
    t.string "platform", null: false
    t.integer "rate_limit_per_minute", default: 60
    t.integer "session_count", default: 0
    t.string "status", default: "disconnected"
    t.datetime "updated_at", null: false
    t.string "vault_path"
    t.string "webhook_token", null: false
    t.index ["account_id", "platform", "name"], unique: true
    t.index ["account_id"]
    t.index ["ai_team_channel_id"]
    t.index ["default_agent_id"]
    t.index ["platform"]
    t.index ["status"]
    t.index ["webhook_token"], unique: true
    t.check_constraint "platform::text = ANY (ARRAY['whatsapp'::character varying::text, 'telegram'::character varying::text, 'discord'::character varying::text, 'slack'::character varying::text, 'mattermost'::character varying::text])", name: "chat_channels_platform_check"
    t.check_constraint "status::text = ANY (ARRAY['connected'::character varying::text, 'disconnected'::character varying::text, 'connecting'::character varying::text, 'error'::character varying::text])", name: "chat_channels_status_check"
  end

  create_table "chat_message_attachments", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "attachment_type", null: false
    t.datetime "created_at", null: false
    t.uuid "file_object_id"
    t.bigint "file_size"
    t.string "filename"
    t.boolean "malware_detected", default: false
    t.uuid "message_id", null: false
    t.jsonb "metadata", default: {}
    t.string "mime_type"
    t.string "platform_file_id"
    t.datetime "scanned_at"
    t.boolean "scanned_for_malware", default: false
    t.string "storage_url"
    t.text "transcription"
    t.datetime "updated_at", null: false
    t.index ["attachment_type"]
    t.index ["file_object_id"]
    t.index ["message_id"]
    t.index ["platform_file_id"]
    t.check_constraint "attachment_type::text = ANY (ARRAY['image'::character varying::text, 'audio'::character varying::text, 'video'::character varying::text, 'document'::character varying::text])", name: "chat_attachments_type_check"
  end

  create_table "chat_messages", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "ai_message_id"
    t.text "content"
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.string "delivery_status", default: "pending"
    t.string "direction", null: false
    t.string "message_type", default: "text"
    t.string "platform_message_id"
    t.jsonb "platform_metadata", default: {}
    t.datetime "read_at"
    t.text "sanitized_content"
    t.datetime "sent_at"
    t.uuid "session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_message_id"]
    t.index ["delivery_status"]
    t.index ["direction"]
    t.index ["message_type"]
    t.index ["platform_message_id"]
    t.index ["session_id", "created_at"]
    t.index ["session_id"]
    t.check_constraint "delivery_status::text = ANY (ARRAY['pending'::character varying::text, 'sent'::character varying::text, 'delivered'::character varying::text, 'read'::character varying::text, 'failed'::character varying::text])", name: "chat_messages_delivery_status_check"
    t.check_constraint "direction::text = ANY (ARRAY['inbound'::character varying::text, 'outbound'::character varying::text])", name: "chat_messages_direction_check"
    t.check_constraint "message_type::text = ANY (ARRAY['text'::character varying::text, 'image'::character varying::text, 'audio'::character varying::text, 'video'::character varying::text, 'document'::character varying::text, 'location'::character varying::text, 'sticker'::character varying::text])", name: "chat_messages_type_check"
  end

  create_table "chat_sessions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.integer "agent_handoff_count", default: 0
    t.uuid "ai_conversation_id"
    t.uuid "assigned_agent_id"
    t.uuid "channel_id", null: false
    t.datetime "closed_at"
    t.jsonb "context_window", default: {}
    t.datetime "created_at", null: false
    t.datetime "last_activity_at"
    t.integer "message_count", default: 0
    t.string "platform_user_id", null: false
    t.string "platform_username"
    t.string "status", default: "active"
    t.datetime "updated_at", null: false
    t.jsonb "user_metadata", default: {}
    t.index ["ai_conversation_id"]
    t.index ["assigned_agent_id"]
    t.index ["channel_id", "platform_user_id"], unique: true
    t.index ["channel_id"]
    t.index ["last_activity_at"]
    t.index ["platform_user_id"]
    t.index ["status"]
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'idle'::character varying::text, 'closed'::character varying::text, 'blocked'::character varying::text])", name: "chat_sessions_status_check"
  end

  create_table "circuit_breaker_events", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "circuit_breaker_id", null: false
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.text "error_message"
    t.string "event_type", null: false
    t.integer "failure_count"
    t.string "new_state"
    t.string "old_state"
    t.datetime "updated_at", null: false
    t.index ["circuit_breaker_id", "created_at"]
    t.index ["circuit_breaker_id"]
    t.index ["event_type"]
  end

  create_table "circuit_breakers", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "configuration", default: {}
    t.datetime "created_at", null: false
    t.integer "failure_count", default: 0
    t.integer "failure_threshold", default: 5, null: false
    t.datetime "half_opened_at"
    t.datetime "last_failure_at"
    t.datetime "last_success_at"
    t.jsonb "metrics", default: {}
    t.string "name", null: false
    t.datetime "opened_at"
    t.string "provider"
    t.integer "reset_timeout_seconds", default: 60
    t.string "service", null: false
    t.string "state", default: "closed", null: false
    t.integer "success_count", default: 0
    t.integer "success_threshold", default: 2, null: false
    t.integer "timeout_seconds", default: 30
    t.datetime "updated_at", null: false
    t.index ["name", "service"], unique: true
    t.index ["service", "state"]
    t.index ["state"]
  end

  create_table "community_agent_ratings", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "a2a_task_id"
    t.uuid "account_id", null: false
    t.uuid "community_agent_id", null: false
    t.datetime "created_at", null: false
    t.datetime "edited_at"
    t.boolean "hidden", default: false
    t.text "moderation_reason"
    t.integer "rating", null: false
    t.jsonb "rating_dimensions", default: {}
    t.text "review"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.boolean "verified_usage", default: false
    t.index ["a2a_task_id"]
    t.index ["account_id"]
    t.index ["community_agent_id", "account_id"], unique: true
    t.index ["community_agent_id"]
    t.index ["rating"]
    t.index ["user_id"]
    t.index ["verified_usage"]
    t.check_constraint "rating >= 1 AND rating <= 5", name: "community_ratings_range_check"
  end

  create_table "community_agent_reports", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "community_agent_id", null: false
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.jsonb "evidence", default: {}
    t.string "report_type", null: false
    t.uuid "reported_by_account_id", null: false
    t.uuid "reported_by_user_id", null: false
    t.text "resolution_notes"
    t.datetime "resolved_at"
    t.uuid "resolved_by_id"
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.index ["community_agent_id", "status"]
    t.index ["community_agent_id"]
    t.index ["report_type"]
    t.index ["reported_by_account_id"]
    t.index ["reported_by_user_id"]
    t.index ["resolved_by_id"]
    t.index ["status"]
    t.check_constraint "report_type::text = ANY (ARRAY['malicious'::character varying::text, 'spam'::character varying::text, 'inappropriate'::character varying::text, 'copyright'::character varying::text, 'other'::character varying::text])", name: "community_reports_type_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'investigating'::character varying::text, 'resolved'::character varying::text, 'dismissed'::character varying::text])", name: "community_reports_status_check"
  end

  create_table "community_agents", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "agent_card_id"
    t.uuid "agent_id", null: false
    t.jsonb "authentication", default: {}
    t.decimal "avg_rating", precision: 3, scale: 2, default: "0.0"
    t.decimal "avg_response_time_ms", precision: 10, scale: 2
    t.jsonb "capabilities", default: {}
    t.string "category"
    t.text "changelog"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "endpoint_url"
    t.integer "failure_count", default: 0
    t.boolean "federated", default: false
    t.string "federation_key"
    t.datetime "last_updated_at"
    t.text "long_description"
    t.string "name", null: false
    t.uuid "owner_account_id", null: false
    t.string "protocol_version", default: "0.3"
    t.datetime "published_at"
    t.uuid "published_by_id"
    t.integer "rating_count", default: 0
    t.decimal "reputation_score", precision: 5, scale: 2, default: "0.0"
    t.string "slug", null: false
    t.string "status", default: "pending"
    t.integer "subscriber_count", default: 0
    t.integer "success_count", default: 0
    t.jsonb "tags", default: []
    t.integer "task_count", default: 0
    t.datetime "updated_at", null: false
    t.boolean "verified", default: false
    t.datetime "verified_at"
    t.uuid "verified_by_id"
    t.string "version", default: "1.0.0"
    t.string "visibility", default: "public"
    t.index ["agent_card_id"]
    t.index ["agent_id"]
    t.index ["category"]
    t.index ["federation_key"], name: "index_community_agents_on_federation_key", unique: true, where: "(federation_key IS NOT NULL)"
    t.index ["owner_account_id"]
    t.index ["published_by_id"]
    t.index ["reputation_score"]
    t.index ["slug"], unique: true
    t.index ["status"]
    t.index ["tags"], name: "index_community_agents_on_tags", using: :gin
    t.index ["task_count"]
    t.index ["verified"]
    t.index ["verified_by_id"]
    t.index ["visibility"]
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'active'::character varying::text, 'suspended'::character varying::text, 'deprecated'::character varying::text])", name: "community_agents_status_check"
    t.check_constraint "visibility::text = ANY (ARRAY['public'::character varying::text, 'unlisted'::character varying::text, 'private'::character varying::text])", name: "community_agents_visibility_check"
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

  create_table "data_retention_policies", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.string "action", default: "delete", null: false
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.string "data_type", null: false
    t.text "description"
    t.datetime "last_enforced_at"
    t.string "legal_basis"
    t.jsonb "metadata", default: {}
    t.integer "records_processed_count", default: 0
    t.integer "retention_days", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "data_type"], unique: true
    t.index ["account_id"]
    t.index ["active"]
    t.index ["data_type"]
  end

  create_table "database_backups", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "backup_type", limit: 50, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.text "description"
    t.integer "duration_seconds"
    t.text "error_message"
    t.string "file_path", limit: 1000
    t.integer "file_size_bytes"
    t.jsonb "metadata", default: {}
    t.datetime "started_at", null: false
    t.string "status", limit: 50, default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["backup_type"]
    t.index ["created_by_id"]
    t.index ["started_at"]
    t.index ["status"]
    t.check_constraint "backup_type::text = ANY (ARRAY['full'::character varying::text, 'incremental'::character varying::text, 'manual'::character varying::text])", name: "valid_backup_type"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "valid_backup_status"
  end

  create_table "database_restores", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.uuid "database_backup_id", null: false
    t.text "description"
    t.integer "duration_seconds"
    t.text "error_message"
    t.uuid "initiated_by_id", null: false
    t.jsonb "metadata", default: {}
    t.datetime "started_at", null: false
    t.string "status", limit: 50, default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["database_backup_id"]
    t.index ["initiated_by_id"]
    t.index ["started_at"]
    t.index ["status"]
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "valid_restore_status"
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

  create_table "devops_ai_configs", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "config_type", limit: 50, null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.text "description"
    t.decimal "frequency_penalty", precision: 3, scale: 2, default: "0.0"
    t.boolean "is_active", default: true, null: false
    t.boolean "is_default", default: false, null: false
    t.datetime "last_used_at"
    t.integer "max_tokens", default: 4096
    t.jsonb "metadata", default: {}, null: false
    t.string "model", limit: 100, null: false
    t.string "name", limit: 255, null: false
    t.decimal "presence_penalty", precision: 3, scale: 2, default: "0.0"
    t.string "provider", limit: 50, null: false
    t.jsonb "rate_limits", default: {}, null: false
    t.jsonb "settings", default: {}, null: false
    t.string "status", limit: 20, default: "active", null: false
    t.jsonb "system_prompt", default: {}, null: false
    t.decimal "temperature", precision: 3, scale: 2, default: "0.7"
    t.integer "timeout_seconds", default: 30
    t.decimal "top_p", precision: 3, scale: 2, default: "1.0"
    t.integer "total_requests", default: 0, null: false
    t.integer "total_tokens", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "config_type"]
    t.index ["account_id", "is_default"], name: "index_devops_ai_configs_on_account_id_and_is_default", where: "(is_default = true)"
    t.index ["account_id", "name"], unique: true
    t.index ["account_id"]
    t.index ["created_by_id"]
    t.index ["provider"]
    t.index ["status"]
    t.check_constraint "config_type::text = ANY (ARRAY['chat'::character varying::text, 'completion'::character varying::text, 'embedding'::character varying::text, 'code_review'::character varying::text, 'code_generation'::character varying::text, 'custom'::character varying::text])", name: "check_devops_ai_config_type"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'archived'::character varying::text])", name: "check_devops_ai_config_status"
  end

  create_table "devops_container_image_builds", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.text "build_log"
    t.datetime "completed_at"
    t.uuid "container_template_id", null: false
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "git_sha"
    t.string "gitea_workflow_run_id"
    t.string "image_tag"
    t.datetime "started_at"
    t.string "status", default: "pending"
    t.string "trigger_type", null: false
    t.uuid "triggered_by_build_id"
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["container_template_id"]
    t.index ["triggered_by_build_id"]
  end

  create_table "devops_container_instances", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "a2a_task_id"
    t.uuid "account_id", null: false
    t.jsonb "artifacts", default: []
    t.datetime "completed_at"
    t.float "cpu_used_millicores"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.jsonb "environment_variables", default: {}
    t.text "error_message"
    t.string "execution_id", null: false
    t.string "exit_code"
    t.string "gitea_job_id"
    t.string "gitea_workflow_run_id"
    t.string "image_name", null: false
    t.string "image_tag", default: "latest"
    t.jsonb "input_parameters", default: {}
    t.text "logs"
    t.integer "mcp_bridge_port"
    t.integer "memory_used_mb"
    t.integer "network_bytes_in"
    t.integer "network_bytes_out"
    t.uuid "oauth_application_id"
    t.jsonb "output_data", default: {}
    t.datetime "queued_at"
    t.jsonb "runner_labels", default: []
    t.string "runner_name"
    t.boolean "sandbox_enabled", default: true
    t.boolean "sandbox_mode", default: false
    t.jsonb "security_violations", default: []
    t.datetime "started_at"
    t.string "status", default: "pending"
    t.jsonb "storage_mounts", default: []
    t.bigint "storage_used_bytes"
    t.uuid "template_id"
    t.integer "timeout_seconds"
    t.uuid "triggered_by_id"
    t.string "trust_level"
    t.datetime "updated_at", null: false
    t.string "vault_token_id"
    t.index ["a2a_task_id"]
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["created_at"]
    t.index ["execution_id"], unique: true
    t.index ["gitea_workflow_run_id"]
    t.index ["oauth_application_id"]
    t.index ["sandbox_mode"]
    t.index ["status"]
    t.index ["template_id"]
    t.index ["triggered_by_id"]
    t.index ["trust_level"]
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'provisioning'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text, 'timeout'::character varying::text])", name: "mcp_instances_status_check"
  end

  create_table "devops_container_templates", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.jsonb "allowed_egress_domains", default: []
    t.boolean "auto_update", default: true
    t.string "category"
    t.jsonb "command_args", default: []
    t.integer "cpu_millicores", default: 500
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.text "description"
    t.string "entrypoint"
    t.jsonb "environment_variables", default: {}
    t.integer "execution_count", default: 0
    t.integer "failure_count", default: 0
    t.boolean "featured", default: false
    t.string "gitea_repo_full_name"
    t.string "image_name", null: false
    t.string "image_tag", default: "latest"
    t.jsonb "input_schema", default: {}
    t.jsonb "labels", default: {}
    t.string "last_build_sha"
    t.datetime "last_built_at"
    t.datetime "last_used_at"
    t.integer "max_retries", default: 3
    t.jsonb "mcp_bridge_config", default: {}
    t.integer "memory_mb", default: 512
    t.string "name", null: false
    t.boolean "network_access", default: false
    t.jsonb "output_schema", default: {}
    t.uuid "parent_template_id"
    t.boolean "privileged", default: false
    t.boolean "read_only_root", default: true
    t.string "registry_url"
    t.jsonb "resource_limits", default: {}
    t.boolean "sandbox_mode", default: true
    t.jsonb "security_options", default: {}
    t.string "slug", null: false
    t.string "status", default: "active"
    t.jsonb "storage_mounts", default: []
    t.integer "success_count", default: 0
    t.integer "timeout_seconds", default: 3600
    t.string "trust_level_required"
    t.datetime "updated_at", null: false
    t.jsonb "vault_secret_paths", default: []
    t.string "visibility", default: "private"
    t.string "webhook_secret"
    t.index ["account_id", "name"], name: "index_devops_container_templates_on_account_id_and_name", unique: true, where: "(account_id IS NOT NULL)"
    t.index ["account_id"]
    t.index ["category"]
    t.index ["created_by_id"]
    t.index ["gitea_repo_full_name"], unique: true
    t.index ["parent_template_id"]
    t.index ["slug"], unique: true
    t.index ["status"]
    t.index ["visibility"]
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'deprecated'::character varying::text, 'archived'::character varying::text])", name: "mcp_templates_status_check"
    t.check_constraint "visibility::text = ANY (ARRAY['private'::character varying::text, 'account'::character varying::text, 'public'::character varying::text])", name: "mcp_templates_visibility_check"
  end

  create_table "devops_docker_activities", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "activity_type", null: false
    t.datetime "completed_at"
    t.uuid "container_id"
    t.datetime "created_at", null: false
    t.uuid "docker_host_id", null: false
    t.integer "duration_ms"
    t.uuid "image_id"
    t.jsonb "params", default: {}
    t.jsonb "result", default: {}
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.string "trigger_source"
    t.uuid "triggered_by_id"
    t.datetime "updated_at", null: false
    t.index ["activity_type"]
    t.index ["container_id"]
    t.index ["created_at"]
    t.index ["docker_host_id"]
    t.index ["image_id"]
    t.index ["status"]
    t.index ["triggered_by_id"]
    t.check_constraint "activity_type::text = ANY (ARRAY['create'::character varying::text, 'start'::character varying::text, 'stop'::character varying::text, 'restart'::character varying::text, 'remove'::character varying::text, 'pull'::character varying::text, 'image_remove'::character varying::text, 'image_tag'::character varying::text])", name: "chk_docker_activities_type"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "chk_docker_activities_status"
  end

  create_table "devops_docker_containers", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.text "command"
    t.datetime "created_at", null: false
    t.string "docker_container_id", null: false
    t.uuid "docker_host_id", null: false
    t.jsonb "environment", default: []
    t.datetime "finished_at"
    t.string "image", null: false
    t.string "image_id"
    t.jsonb "labels", default: {}
    t.datetime "last_seen_at"
    t.jsonb "mounts", default: []
    t.string "name", null: false
    t.jsonb "networks", default: {}
    t.jsonb "ports", default: []
    t.integer "restart_count", default: 0
    t.string "restart_policy"
    t.bigint "size_rw"
    t.datetime "started_at"
    t.string "state", default: "created", null: false
    t.string "status_text"
    t.datetime "updated_at", null: false
    t.index ["docker_host_id", "docker_container_id"], unique: true
    t.index ["docker_host_id"]
    t.index ["state"]
    t.check_constraint "state::text = ANY (ARRAY['created'::character varying::text, 'running'::character varying::text, 'paused'::character varying::text, 'restarting'::character varying::text, 'exited'::character varying::text, 'removing'::character varying::text, 'dead'::character varying::text])", name: "chk_docker_containers_state"
  end

  create_table "devops_docker_events", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.boolean "acknowledged", default: false
    t.datetime "acknowledged_at"
    t.uuid "acknowledged_by_id"
    t.datetime "created_at", null: false
    t.uuid "docker_host_id", null: false
    t.string "event_type", null: false
    t.text "message", null: false
    t.jsonb "metadata", default: {}
    t.string "severity", default: "info", null: false
    t.string "source_id"
    t.string "source_name"
    t.string "source_type", null: false
    t.datetime "updated_at", null: false
    t.index ["acknowledged"]
    t.index ["acknowledged_by_id"]
    t.index ["created_at"]
    t.index ["docker_host_id"]
    t.index ["severity"]
    t.check_constraint "severity::text = ANY (ARRAY['info'::character varying::text, 'warning'::character varying::text, 'error'::character varying::text, 'critical'::character varying::text])", name: "chk_docker_events_severity"
    t.check_constraint "source_type::text = ANY (ARRAY['host'::character varying::text, 'container'::character varying::text, 'image'::character varying::text, 'network'::character varying::text, 'volume'::character varying::text])", name: "chk_docker_events_source_type"
  end

  create_table "devops_docker_hosts", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "api_endpoint", null: false
    t.string "api_version", default: "v1.45"
    t.string "architecture"
    t.boolean "auto_sync", default: true
    t.integer "consecutive_failures", default: 0
    t.integer "container_count", default: 0
    t.integer "cpu_count"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "docker_version"
    t.text "encrypted_tls_credentials"
    t.string "encryption_key_id"
    t.string "environment", default: "development", null: false
    t.integer "image_count", default: 0
    t.string "kernel_version"
    t.datetime "last_synced_at"
    t.bigint "memory_bytes"
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.uuid "node_instance_id"
    t.string "os_type"
    t.string "provisioning_state", default: "external", null: false
    t.string "slug", null: false
    t.string "status", default: "pending", null: false
    t.bigint "storage_bytes"
    t.integer "sync_interval_seconds", default: 60
    t.boolean "tls_verify", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], unique: true
    t.index ["account_id"]
    t.index ["environment"]
    t.index ["node_instance_id"], name: "idx_devops_docker_hosts_node_instance_unique", unique: true, where: "(node_instance_id IS NOT NULL)"
    t.index ["slug"], unique: true
    t.index ["status"]
    t.check_constraint "environment::text = ANY (ARRAY['staging'::character varying::text, 'production'::character varying::text, 'development'::character varying::text, 'custom'::character varying::text])", name: "chk_docker_hosts_environment"
    t.check_constraint "provisioning_state::text = 'external'::text AND node_instance_id IS NULL OR provisioning_state::text = 'managed'::text AND node_instance_id IS NOT NULL", name: "devops_docker_hosts_provisioning_state_consistency"
    t.check_constraint "provisioning_state::text = ANY (ARRAY['external'::character varying::text, 'managed'::character varying::text])", name: "devops_docker_hosts_provisioning_state_enum"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'connected'::character varying::text, 'disconnected'::character varying::text, 'error'::character varying::text, 'maintenance'::character varying::text])", name: "chk_docker_hosts_status"
  end

  create_table "devops_docker_images", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "architecture"
    t.integer "container_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "docker_created_at"
    t.uuid "docker_host_id", null: false
    t.string "docker_image_id", null: false
    t.jsonb "labels", default: {}
    t.datetime "last_seen_at"
    t.string "os"
    t.jsonb "repo_digests", default: []
    t.jsonb "repo_tags", default: []
    t.bigint "size_bytes"
    t.datetime "updated_at", null: false
    t.bigint "virtual_size"
    t.index ["docker_host_id", "docker_image_id"], unique: true
    t.index ["docker_host_id"]
  end

  create_table "devops_integration_credentials", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.integer "consecutive_failures", default: 0
    t.datetime "created_at", null: false
    t.uuid "created_by_user_id"
    t.string "credential_type", null: false
    t.text "encrypted_credentials"
    t.text "encrypted_refresh_token"
    t.string "encryption_key_id", null: false
    t.datetime "expires_at"
    t.boolean "is_active", default: true
    t.text "last_error"
    t.datetime "last_used_at"
    t.datetime "last_validated_at"
    t.jsonb "metadata", default: {}
    t.datetime "migrated_to_vault_at"
    t.string "name", null: false
    t.datetime "rotated_at"
    t.uuid "rotated_from_id"
    t.jsonb "scopes", default: []
    t.datetime "token_expires_at"
    t.datetime "updated_at", null: false
    t.string "validation_status"
    t.string "vault_path"
    t.index ["account_id", "credential_type"]
    t.index ["account_id", "name"], unique: true
    t.index ["account_id"]
    t.index ["created_by_user_id"]
    t.index ["credential_type"]
    t.index ["expires_at"]
    t.index ["is_active"]
    t.index ["vault_path"], name: "index_devops_integration_credentials_on_vault_path", unique: true, where: "(vault_path IS NOT NULL)"
  end

  create_table "devops_integration_executions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.integer "attempt_number", default: 1
    t.datetime "completed_at"
    t.decimal "cost_estimate", precision: 10, scale: 6
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.jsonb "error_details", default: {}
    t.string "execution_id", null: false
    t.jsonb "input_data", default: {}
    t.uuid "integration_instance_id", null: false
    t.integer "max_attempts", default: 3
    t.datetime "next_retry_at"
    t.jsonb "output_data", default: {}
    t.uuid "parent_execution_id"
    t.jsonb "resource_usage", default: {}
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.jsonb "trigger_metadata", default: {}
    t.string "trigger_source"
    t.string "trigger_type"
    t.uuid "triggered_by_user_id"
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"]
    t.index ["account_id"]
    t.index ["execution_id"], unique: true
    t.index ["integration_instance_id", "status"]
    t.index ["integration_instance_id"]
    t.index ["parent_execution_id"]
    t.index ["status"]
    t.index ["trigger_type"]
    t.index ["triggered_by_user_id"]
  end

  create_table "devops_integration_instances", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.decimal "average_duration_ms", precision: 10, scale: 2
    t.jsonb "configuration", default: {}
    t.integer "consecutive_failures", default: 0
    t.datetime "created_at", null: false
    t.uuid "created_by_user_id"
    t.text "description"
    t.integer "execution_count", default: 0
    t.integer "failure_count", default: 0
    t.jsonb "health_metrics", default: {}
    t.string "health_status"
    t.uuid "integration_credential_id"
    t.uuid "integration_template_id", null: false
    t.text "last_error"
    t.datetime "last_executed_at"
    t.datetime "last_failure_at"
    t.datetime "last_health_check_at"
    t.datetime "last_success_at"
    t.string "name", null: false
    t.jsonb "runtime_state", default: {}
    t.string "slug", null: false
    t.string "status", default: "pending"
    t.integer "success_count", default: 0
    t.datetime "updated_at", null: false
    t.index ["account_id", "slug"], unique: true
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["created_by_user_id"]
    t.index ["health_status"]
    t.index ["integration_credential_id"]
    t.index ["integration_template_id"]
    t.index ["status"]
  end

  create_table "devops_integration_templates", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.jsonb "capabilities", default: []
    t.string "category"
    t.jsonb "configuration_schema", default: {}
    t.datetime "created_at", null: false
    t.jsonb "credential_requirements", default: {}
    t.jsonb "default_configuration", default: {}
    t.text "description"
    t.string "documentation_url"
    t.string "icon_url"
    t.jsonb "input_schema", default: {}
    t.integer "install_count", default: 0
    t.string "integration_type", null: false
    t.boolean "is_active", default: true
    t.boolean "is_featured", default: false
    t.boolean "is_public", default: false
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.jsonb "output_schema", default: {}
    t.string "slug", null: false
    t.jsonb "supported_providers", default: []
    t.datetime "updated_at", null: false
    t.integer "usage_count", default: 0
    t.string "version", default: "1.0.0"
    t.index ["account_id"]
    t.index ["category"]
    t.index ["integration_type"]
    t.index ["is_active"]
    t.index ["is_featured"]
    t.index ["is_public", "is_active"]
    t.index ["is_public"]
    t.index ["slug"], unique: true
  end

  create_table "devops_kubernetes_clusters", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "api_endpoint", null: false
    t.boolean "auto_sync", default: true, null: false
    t.string "cni_plugin", default: "flannel", null: false, comment: "OVS+OVN dual-profile CNI selector — see Devops::KubernetesCluster::CNI_PLUGINS"
    t.integer "consecutive_failures", default: 0, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.text "encrypted_agent_token"
    t.text "encrypted_kubeconfig"
    t.text "encrypted_server_token"
    t.string "encryption_key_id"
    t.string "environment", default: "development", null: false
    t.string "flavor", default: "k3s", null: false
    t.string "k8s_version"
    t.datetime "last_synced_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.integer "node_count", default: 0, null: false
    t.integer "pod_count", default: 0, null: false
    t.string "slug", null: false
    t.string "status", default: "pending", null: false
    t.integer "sync_interval_seconds", default: 60, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], unique: true
    t.index ["account_id"]
    t.index ["cni_plugin"]
    t.index ["environment"]
    t.index ["flavor"]
    t.index ["slug"], unique: true
    t.index ["status"]
    t.check_constraint "cni_plugin::text = ANY (ARRAY['flannel'::character varying::text, 'ovn_kubernetes'::character varying::text])", name: "chk_kubernetes_clusters_cni_plugin"
    t.check_constraint "environment::text = ANY (ARRAY['staging'::character varying::text, 'production'::character varying::text, 'development'::character varying::text, 'custom'::character varying::text])", name: "chk_kubernetes_clusters_environment"
    t.check_constraint "flavor::text = ANY (ARRAY['k3s'::character varying::text, 'kubeadm'::character varying::text])", name: "chk_kubernetes_clusters_flavor"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'bootstrapping'::character varying::text, 'active'::character varying::text, 'degraded'::character varying::text, 'disconnected'::character varying::text, 'error'::character varying::text])", name: "chk_kubernetes_clusters_status"
  end

  create_table "devops_kubernetes_nodes", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "k8s_version"
    t.uuid "kubernetes_cluster_id", null: false
    t.datetime "last_heartbeat_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.uuid "node_instance_id", null: false
    t.string "role", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["kubernetes_cluster_id", "name"], unique: true
    t.index ["kubernetes_cluster_id"]
    t.index ["node_instance_id"], unique: true
    t.index ["role"]
    t.index ["status"]
    t.check_constraint "role::text = ANY (ARRAY['server'::character varying::text, 'agent'::character varying::text, 'control_plane'::character varying::text, 'worker'::character varying::text])", name: "chk_kubernetes_nodes_role"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'joining'::character varying::text, 'active'::character varying::text, 'not_ready'::character varying::text, 'disconnected'::character varying::text, 'error'::character varying::text])", name: "chk_kubernetes_nodes_status"
  end

  create_table "devops_pipeline_repositories", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "devops_pipeline_id", null: false
    t.uuid "git_repository_id", null: false
    t.jsonb "overrides", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["devops_pipeline_id", "git_repository_id"], unique: true
    t.index ["devops_pipeline_id"]
    t.index ["git_repository_id"]
  end

  create_table "devops_pipeline_runs", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "artifacts", default: [], null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.uuid "devops_pipeline_id", null: false
    t.integer "duration_seconds"
    t.text "error_message"
    t.string "external_run_id"
    t.string "external_run_url"
    t.jsonb "outputs", default: {}, null: false
    t.string "run_number", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.jsonb "trigger_context", default: {}, null: false
    t.string "trigger_type", null: false
    t.uuid "triggered_by_id"
    t.datetime "updated_at", null: false
    t.index ["devops_pipeline_id", "run_number"], unique: true
    t.index ["devops_pipeline_id", "status"]
    t.index ["devops_pipeline_id"]
    t.index ["external_run_id"]
    t.index ["triggered_by_id"]
  end

  create_table "devops_pipeline_steps", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "approval_settings", default: {}, null: false, comment: "Approval config: {\"timeout_hours\": 24, \"notification_recipients\": [], \"require_comment\": false}"
    t.text "condition"
    t.jsonb "configuration", default: {}, null: false
    t.boolean "continue_on_error", default: false, null: false
    t.datetime "created_at", null: false
    t.uuid "devops_pipeline_id", null: false
    t.jsonb "inputs", default: {}, null: false
    t.boolean "is_active", default: true, null: false
    t.string "name", null: false
    t.jsonb "outputs", default: [], null: false
    t.integer "position", default: 0, null: false
    t.boolean "requires_approval", default: false, null: false, comment: "When true, step execution pauses and sends notifications for manual approval"
    t.uuid "shared_prompt_template_id"
    t.string "step_type", null: false
    t.datetime "updated_at", null: false
    t.index ["devops_pipeline_id", "name"], unique: true
    t.index ["devops_pipeline_id", "position"]
    t.index ["devops_pipeline_id"]
    t.index ["shared_prompt_template_id"]
  end

  create_table "devops_pipeline_templates", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "category"
    t.datetime "created_at", null: false
    t.uuid "created_by_user_id"
    t.jsonb "default_variables", default: {}
    t.text "description"
    t.string "difficulty_level", default: "intermediate"
    t.string "icon_url"
    t.integer "install_count", default: 0
    t.boolean "is_featured", default: false
    t.boolean "is_public", default: false
    t.boolean "is_system", default: false
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.jsonb "pipeline_definition", default: {}
    t.datetime "published_at"
    t.decimal "rating", precision: 3, scale: 2, default: "0.0"
    t.integer "rating_count", default: 0
    t.string "slug", null: false
    t.uuid "source_pipeline_id"
    t.string "status", default: "draft"
    t.jsonb "tags", default: []
    t.integer "timeout_minutes", default: 30
    t.jsonb "triggers", default: {}
    t.datetime "updated_at", null: false
    t.integer "usage_count", default: 0
    t.string "version", default: "1.0.0", null: false
    t.index ["account_id"]
    t.index ["category"]
    t.index ["created_by_user_id"]
    t.index ["is_featured"]
    t.index ["is_public"]
    t.index ["slug"], unique: true
    t.index ["source_pipeline_id"]
    t.index ["status"]
  end

  create_table "devops_pipelines", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_provider_id"
    t.boolean "allow_concurrent", default: false, null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.text "description"
    t.uuid "devops_provider_id"
    t.jsonb "environment", default: {}, null: false
    t.jsonb "features", default: {}, null: false
    t.boolean "is_active", default: true, null: false
    t.boolean "is_system", default: false, null: false
    t.string "name", null: false
    t.jsonb "notification_recipients", default: [], null: false, comment: "Array of notification recipients: [{\"type\": \"email\"|\"user_id\", \"value\": \"...\"}]"
    t.jsonb "notification_settings", default: {}, null: false, comment: "Notification preferences: {\"on_approval_required\": true, \"on_completion\": false, \"on_failure\": true}"
    t.string "pipeline_type", null: false
    t.string "runner_labels", default: ["ubuntu-latest"], array: true
    t.jsonb "secret_refs", default: [], null: false
    t.string "slug", null: false
    t.jsonb "steps", default: [], null: false
    t.integer "timeout_minutes", default: 60
    t.jsonb "triggers", default: {}, null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.index ["account_id", "is_active"]
    t.index ["account_id", "pipeline_type"]
    t.index ["account_id", "slug"], unique: true
    t.index ["account_id"]
    t.index ["ai_provider_id"]
    t.index ["created_by_id"]
    t.index ["devops_provider_id"]
  end

  create_table "devops_port_allocations", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "allocatable_id", null: false
    t.string "allocatable_type", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "host_identifier", null: false
    t.integer "port", null: false
    t.string "protocol", default: "tcp", null: false
    t.string "purpose"
    t.datetime "released_at"
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["allocatable_type", "allocatable_id"]
    t.index ["host_identifier", "port", "protocol"], name: "idx_port_allocations_unique_active", unique: true, where: "((status)::text = 'active'::text)"
    t.index ["status"]
  end

  create_table "devops_providers", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "api_version", default: "v1"
    t.string "base_url", null: false
    t.jsonb "capabilities", default: [], null: false
    t.jsonb "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.string "credential_key"
    t.string "health_status"
    t.boolean "is_active", default: true, null: false
    t.boolean "is_default", default: false, null: false
    t.datetime "last_health_check_at"
    t.string "name", null: false
    t.string "provider_type", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "is_default"], name: "index_devops_providers_on_account_id_and_is_default", where: "(is_default = true)"
    t.index ["account_id", "name"], unique: true
    t.index ["account_id"]
    t.index ["created_by_id"]
  end

  create_table "devops_resource_quotas", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.boolean "allow_network_access", default: false
    t.boolean "allow_overage", default: false
    t.jsonb "allowed_egress_domains", default: []
    t.integer "containers_used_this_hour", default: 0
    t.integer "containers_used_today", default: 0
    t.datetime "created_at", null: false
    t.integer "current_running_containers", default: 0
    t.integer "max_concurrent_containers", default: 5
    t.integer "max_containers_per_day", default: 500
    t.integer "max_containers_per_hour", default: 50
    t.integer "max_cpu_millicores", default: 500
    t.integer "max_execution_time_seconds", default: 3600
    t.integer "max_memory_mb", default: 512
    t.bigint "max_storage_bytes", default: 1073741824
    t.decimal "overage_rate_per_container", precision: 10, scale: 4
    t.datetime "updated_at", null: false
    t.datetime "usage_reset_at"
    t.index ["account_id"], unique: true
  end

  create_table "devops_schedules", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.string "cron_expression", null: false
    t.uuid "devops_pipeline_id", null: false
    t.jsonb "inputs", default: {}, null: false
    t.boolean "is_active", default: true, null: false
    t.datetime "last_run_at"
    t.string "name", null: false
    t.datetime "next_run_at"
    t.string "timezone", default: "UTC"
    t.datetime "updated_at", null: false
    t.index ["created_by_id"]
    t.index ["devops_pipeline_id", "is_active"]
    t.index ["devops_pipeline_id"]
    t.index ["next_run_at"], name: "index_devops_schedules_on_next_run_at", where: "(is_active = true)"
  end

  create_table "devops_secret_references", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.text "description"
    t.datetime "expires_at"
    t.datetime "last_accessed_at"
    t.datetime "last_rotated_at"
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.string "secret_type", null: false
    t.datetime "updated_at", null: false
    t.string "vault_key"
    t.string "vault_path", null: false
    t.index ["account_id", "name"], unique: true
    t.index ["account_id"]
    t.index ["created_by_id"]
    t.index ["expires_at"], name: "index_devops_secret_references_on_expires_at", where: "(expires_at IS NOT NULL)"
    t.index ["secret_type"]
    t.index ["vault_path"]
    t.check_constraint "secret_type::text = ANY (ARRAY['ai_provider'::character varying::text, 'mcp_server'::character varying::text, 'chat_channel'::character varying::text, 'git_credential'::character varying::text, 'custom'::character varying::text])", name: "mcp_secrets_type_check"
  end

  create_table "devops_step_approval_tokens", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "email_sent_at"
    t.datetime "expires_at", null: false
    t.string "recipient_email", null: false
    t.uuid "recipient_user_id"
    t.datetime "responded_at"
    t.uuid "responded_by_id"
    t.text "response_comment"
    t.string "status", default: "pending", null: false
    t.uuid "step_execution_id", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["recipient_user_id"]
    t.index ["responded_by_id"]
    t.index ["status", "expires_at"], name: "idx_approval_tokens_pending_expiry", where: "((status)::text = 'pending'::text)"
    t.index ["step_execution_id", "status"]
    t.index ["step_execution_id"]
    t.index ["token_digest"], unique: true
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'approved'::character varying::text, 'rejected'::character varying::text, 'expired'::character varying::text])", name: "ci_cd_step_approval_tokens_status_check"
  end

  create_table "devops_step_executions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.uuid "devops_pipeline_run_id", null: false
    t.uuid "devops_pipeline_step_id", null: false
    t.integer "duration_seconds"
    t.text "error_message"
    t.text "logs"
    t.jsonb "outputs", default: {}, null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["devops_pipeline_run_id", "devops_pipeline_step_id"], unique: true
    t.index ["devops_pipeline_run_id"]
    t.index ["devops_pipeline_step_id"]
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'waiting_approval'::character varying::text, 'success'::character varying::text, 'failure'::character varying::text, 'skipped'::character varying::text])", name: "ci_cd_step_executions_status_check"
  end

  create_table "devops_swarm_clusters", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "api_endpoint", null: false
    t.string "api_version", default: "v1.45"
    t.boolean "auto_sync", default: true
    t.integer "consecutive_failures", default: 0
    t.datetime "created_at", null: false
    t.text "description"
    t.text "encrypted_tls_credentials"
    t.string "encryption_key_id"
    t.string "environment", default: "development", null: false
    t.datetime "last_synced_at"
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.integer "node_count", default: 0
    t.integer "service_count", default: 0
    t.string "slug", null: false
    t.string "status", default: "pending", null: false
    t.string "swarm_id"
    t.integer "sync_interval_seconds", default: 60
    t.boolean "tls_verify", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], unique: true
    t.index ["account_id"]
    t.index ["environment"]
    t.index ["slug"], unique: true
    t.index ["status"]
    t.check_constraint "environment::text = ANY (ARRAY['staging'::character varying::text, 'production'::character varying::text, 'development'::character varying::text, 'custom'::character varying::text])", name: "swarm_clusters_environment_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'connected'::character varying::text, 'disconnected'::character varying::text, 'error'::character varying::text, 'maintenance'::character varying::text])", name: "swarm_clusters_status_check"
  end

  create_table "devops_swarm_deployments", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "cluster_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "deployment_type", null: false
    t.jsonb "desired_state", default: {}
    t.integer "duration_ms"
    t.string "git_sha"
    t.jsonb "previous_state", default: {}
    t.jsonb "result", default: {}
    t.uuid "service_id"
    t.uuid "stack_id"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.string "trigger_source"
    t.uuid "triggered_by_id"
    t.datetime "updated_at", null: false
    t.index ["cluster_id"]
    t.index ["created_at"]
    t.index ["deployment_type"]
    t.index ["service_id"]
    t.index ["stack_id"]
    t.index ["status"]
    t.index ["triggered_by_id"]
    t.check_constraint "deployment_type::text = ANY (ARRAY['deploy'::character varying::text, 'update'::character varying::text, 'scale'::character varying::text, 'rollback'::character varying::text, 'remove'::character varying::text, 'stack_deploy'::character varying::text, 'stack_remove'::character varying::text])", name: "swarm_deployments_type_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text])", name: "swarm_deployments_status_check"
  end

  create_table "devops_swarm_events", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.boolean "acknowledged", default: false
    t.datetime "acknowledged_at"
    t.uuid "acknowledged_by_id"
    t.uuid "cluster_id", null: false
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.text "message", null: false
    t.jsonb "metadata", default: {}
    t.string "severity", default: "info", null: false
    t.string "source_id"
    t.string "source_name"
    t.string "source_type", null: false
    t.datetime "updated_at", null: false
    t.index ["acknowledged"]
    t.index ["acknowledged_by_id"]
    t.index ["cluster_id"]
    t.index ["created_at"]
    t.index ["event_type"]
    t.index ["severity"]
    t.check_constraint "severity::text = ANY (ARRAY['info'::character varying::text, 'warning'::character varying::text, 'error'::character varying::text, 'critical'::character varying::text])", name: "swarm_events_severity_check"
    t.check_constraint "source_type::text = ANY (ARRAY['node'::character varying::text, 'service'::character varying::text, 'task'::character varying::text, 'cluster'::character varying::text, 'stack'::character varying::text])", name: "swarm_events_source_type_check"
  end

  create_table "devops_swarm_nodes", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "architecture"
    t.string "availability", default: "active", null: false
    t.uuid "cluster_id", null: false
    t.integer "cpu_count"
    t.datetime "created_at", null: false
    t.string "docker_node_id", null: false
    t.string "engine_version"
    t.string "hostname", null: false
    t.string "ip_address"
    t.jsonb "labels", default: {}
    t.datetime "last_seen_at"
    t.string "manager_status"
    t.bigint "memory_bytes"
    t.string "os"
    t.string "role", default: "worker", null: false
    t.string "status", default: "ready", null: false
    t.datetime "updated_at", null: false
    t.index ["cluster_id", "docker_node_id"], unique: true
    t.index ["cluster_id"]
    t.index ["role"]
    t.index ["status"]
    t.check_constraint "availability::text = ANY (ARRAY['active'::character varying::text, 'pause'::character varying::text, 'drain'::character varying::text])", name: "swarm_nodes_availability_check"
    t.check_constraint "role::text = ANY (ARRAY['manager'::character varying::text, 'worker'::character varying::text])", name: "swarm_nodes_role_check"
    t.check_constraint "status::text = ANY (ARRAY['ready'::character varying::text, 'down'::character varying::text, 'disconnected'::character varying::text, 'unknown'::character varying::text])", name: "swarm_nodes_status_check"
  end

  create_table "devops_swarm_services", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "cluster_id", null: false
    t.jsonb "constraints", default: []
    t.datetime "created_at", null: false
    t.integer "desired_replicas", default: 1
    t.string "docker_service_id", null: false
    t.jsonb "environment", default: []
    t.string "image", null: false
    t.jsonb "labels", default: {}
    t.string "mode", default: "replicated", null: false
    t.jsonb "ports", default: []
    t.jsonb "resource_limits", default: {}
    t.jsonb "resource_reservations", default: {}
    t.jsonb "rollback_config", default: {}
    t.integer "running_replicas", default: 0
    t.string "service_name", null: false
    t.uuid "stack_id"
    t.jsonb "update_config", default: {}
    t.datetime "updated_at", null: false
    t.bigint "version"
    t.index ["cluster_id", "docker_service_id"], unique: true
    t.index ["cluster_id"]
    t.index ["service_name"]
    t.index ["stack_id"]
    t.check_constraint "mode::text = ANY (ARRAY['replicated'::character varying::text, 'global'::character varying::text])", name: "swarm_services_mode_check"
  end

  create_table "devops_swarm_stacks", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "cluster_id", null: false
    t.text "compose_file"
    t.jsonb "compose_variables", default: {}
    t.datetime "created_at", null: false
    t.integer "deploy_count", default: 0
    t.datetime "last_deployed_at"
    t.string "name", null: false
    t.integer "service_count", default: 0
    t.string "slug", null: false
    t.string "source", default: "platform", null: false
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.index ["cluster_id", "name"], unique: true
    t.index ["cluster_id"]
    t.index ["slug"]
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'deploying'::character varying::text, 'deployed'::character varying::text, 'failed'::character varying::text, 'removing'::character varying::text, 'removed'::character varying::text])", name: "swarm_stacks_status_check"
  end

  create_table "email_deliveries", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.text "body_html"
    t.text "body_text"
    t.string "bounce_reason"
    t.datetime "bounced_at"
    t.datetime "clicked_at"
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.string "email_type", null: false
    t.text "error_message"
    t.string "external_id"
    t.jsonb "metadata", default: {}
    t.datetime "opened_at"
    t.string "recipient_email", null: false
    t.integer "retry_count", default: 0
    t.string "sender_email"
    t.datetime "sent_at"
    t.string "status", default: "pending"
    t.string "subject", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["email_type"]
    t.index ["external_id"], name: "idx_email_deliveries_on_external_id_unique", unique: true, where: "(external_id IS NOT NULL)"
    t.index ["recipient_email"]
    t.index ["sent_at"]
    t.index ["status"]
    t.index ["user_id"]
    t.check_constraint "email_type::text = ANY (ARRAY['welcome'::character varying::text, 'verification'::character varying::text, 'password_reset'::character varying::text, 'invitation'::character varying::text, 'notification'::character varying::text, 'marketing'::character varying::text, 'transactional'::character varying::text])", name: "valid_email_type"
    t.check_constraint "retry_count >= 0", name: "valid_email_retry_count"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'sent'::character varying::text, 'delivered'::character varying::text, 'bounced'::character varying::text, 'failed'::character varying::text, 'opened'::character varying::text, 'clicked'::character varying::text])", name: "valid_email_status"
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

  create_table "file_object_tags", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.uuid "file_object_id", null: false
    t.uuid "file_tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["file_object_id", "file_tag_id"], unique: true
    t.index ["file_object_id"]
    t.index ["file_tag_id"]
  end

  create_table "file_objects", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "access_permissions", default: {}
    t.uuid "account_id", null: false
    t.uuid "attachable_id"
    t.string "attachable_type"
    t.string "category"
    t.string "checksum_md5"
    t.string "checksum_sha256"
    t.string "content_type", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.uuid "deleted_by_id"
    t.jsonb "dimensions", default: {}
    t.integer "download_count", default: 0, null: false
    t.jsonb "exif_data", default: {}
    t.datetime "expires_at"
    t.bigint "file_size", null: false
    t.uuid "file_storage_id", null: false
    t.string "file_type"
    t.string "filename", null: false
    t.boolean "is_latest_version", default: true, null: false
    t.datetime "last_accessed_at"
    t.jsonb "metadata", default: {}, null: false
    t.uuid "parent_file_id"
    t.jsonb "processing_metadata", default: {}
    t.string "processing_status", default: "pending"
    t.string "storage_key", null: false
    t.datetime "updated_at", null: false
    t.uuid "uploaded_by_id", null: false
    t.integer "version", default: 1, null: false
    t.string "visibility", default: "private", null: false
    t.index ["account_id", "category"]
    t.index ["account_id", "created_at"]
    t.index ["account_id", "file_type"]
    t.index ["account_id", "filename"]
    t.index ["account_id", "is_latest_version"]
    t.index ["account_id", "visibility"]
    t.index ["account_id"]
    t.index ["attachable_type", "attachable_id"]
    t.index ["checksum_sha256"]
    t.index ["deleted_at"]
    t.index ["deleted_by_id"]
    t.index ["expires_at"], name: "index_file_objects_on_expires_at", where: "(expires_at IS NOT NULL)"
    t.index ["file_storage_id", "storage_key"], unique: true
    t.index ["file_storage_id"]
    t.index ["metadata"], name: "index_file_objects_on_metadata", using: :gin
    t.index ["parent_file_id"]
    t.index ["processing_status"]
    t.index ["uploaded_by_id"]
    t.check_constraint "category IS NULL OR (category::text = ANY (ARRAY['user_upload'::character varying::text, 'workflow_output'::character varying::text, 'ai_generated'::character varying::text, 'temp'::character varying::text, 'system'::character varying::text, 'import'::character varying::text, 'page_content'::character varying::text, 'sbom_export'::character varying::text, 'attestation_proof'::character varying::text, 'supply_chain_scan_report'::character varying::text, 'vendor_compliance'::character varying::text, 'vendor_assessment'::character varying::text, 'vendor_certificate'::character varying::text, 'disk_image'::character varying::text]))", name: "file_objects_category_check"
    t.check_constraint "file_type::text = ANY (ARRAY['image'::character varying::text, 'document'::character varying::text, 'video'::character varying::text, 'audio'::character varying::text, 'archive'::character varying::text, 'code'::character varying::text, 'data'::character varying::text, 'other'::character varying::text])", name: "file_objects_file_type_check"
    t.check_constraint "processing_status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "file_objects_processing_status_check"
    t.check_constraint "visibility::text = ANY (ARRAY['private'::character varying::text, 'public'::character varying::text, 'shared'::character varying::text, 'internal'::character varying::text])", name: "file_objects_visibility_check"
  end

  create_table "file_processing_jobs", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.jsonb "error_details", default: {}
    t.uuid "file_object_id", null: false
    t.jsonb "job_parameters", default: {}
    t.string "job_type", null: false
    t.integer "max_retries", default: 3, null: false
    t.jsonb "metadata", default: {}
    t.string "output_storage_key"
    t.integer "priority", default: 50, null: false
    t.jsonb "result_data", default: {}
    t.integer "retry_count", default: 0, null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["created_at"]
    t.index ["file_object_id"]
    t.index ["job_type"]
    t.index ["priority"]
    t.index ["status"]
    t.check_constraint "job_type::text = ANY (ARRAY['thumbnail'::character varying::text, 'resize'::character varying::text, 'convert'::character varying::text, 'scan'::character varying::text, 'ocr'::character varying::text, 'metadata_extract'::character varying::text, 'compress'::character varying::text, 'watermark'::character varying::text, 'transform'::character varying::text])", name: "file_processing_jobs_job_type_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text])", name: "file_processing_jobs_status_check"
  end

  create_table "file_shares", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "access_level", default: "view", null: false
    t.jsonb "access_log", default: []
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.integer "download_count", default: 0, null: false
    t.datetime "expires_at"
    t.uuid "file_object_id", null: false
    t.datetime "last_accessed_at"
    t.integer "max_downloads"
    t.jsonb "metadata", default: {}
    t.string "password_digest"
    t.jsonb "recipients", default: []
    t.string "share_token", null: false
    t.string "share_type", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["created_at"]
    t.index ["created_by_id"]
    t.index ["expires_at"], name: "index_file_shares_on_expires_at", where: "(expires_at IS NOT NULL)"
    t.index ["file_object_id"]
    t.index ["share_token"], unique: true
    t.index ["status"]
    t.check_constraint "access_level::text = ANY (ARRAY['view'::character varying::text, 'download'::character varying::text, 'edit'::character varying::text, 'admin'::character varying::text])", name: "file_shares_access_level_check"
    t.check_constraint "share_type::text = ANY (ARRAY['public_link'::character varying::text, 'email'::character varying::text, 'user'::character varying::text, 'api'::character varying::text])", name: "file_shares_share_type_check"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'expired'::character varying::text, 'revoked'::character varying::text, 'pending'::character varying::text])", name: "file_shares_status_check"
  end

  create_table "file_storages", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "capabilities", default: {}, null: false
    t.jsonb "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.jsonb "default_mount_options", default: {}, null: false
    t.string "deployment_shape", default: "self_hosted", null: false
    t.string "encryption_mode", default: "none", null: false
    t.bigint "files_count", default: 0, null: false
    t.jsonb "health_details", default: {}
    t.string "health_status"
    t.boolean "is_default"
    t.datetime "last_health_check_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.boolean "node_mount_capable", default: false, null: false
    t.integer "priority", default: 100, null: false
    t.string "provider_type", null: false
    t.bigint "quota_bytes"
    t.boolean "requires_node_credentials", default: false, null: false
    t.string "status", default: "active", null: false
    t.bigint "total_size_bytes", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], unique: true
    t.index ["account_id", "provider_type"]
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["configuration"], name: "index_file_storages_on_configuration", using: :gin
    t.index ["health_status"]
    t.index ["node_mount_capable"], name: "index_file_storages_node_mount_capable_true", where: "(node_mount_capable = true)"
    t.index ["priority"]
    t.check_constraint "deployment_shape::text = ANY (ARRAY['self_hosted'::character varying::text, 'gateway_proxy'::character varying::text])", name: "file_storages_deployment_shape_check"
    t.check_constraint "encryption_mode::text = ANY (ARRAY['none'::character varying::text, 'fscrypt'::character varying::text, 'luks'::character varying::text, 'client_side_aes'::character varying::text])", name: "file_storages_encryption_mode_check"
    t.check_constraint "provider_type::text = ANY (ARRAY['local'::character varying::text, 's3'::character varying::text, 'gcs'::character varying::text, 'azure'::character varying::text, 'nfs'::character varying::text, 'smb'::character varying::text, 'ftp'::character varying::text, 'webdav'::character varying::text, 'custom'::character varying::text])", name: "file_storages_provider_type_check"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'maintenance'::character varying::text, 'failed'::character varying::text])", name: "file_storages_status_check"
  end

  create_table "file_tags", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "color"
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "files_count", default: 0, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], unique: true
    t.index ["account_id"]
  end

  create_table "file_versions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "change_description"
    t.jsonb "change_metadata", default: {}
    t.string "checksum_sha256"
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.datetime "deleted_at"
    t.uuid "file_object_id", null: false
    t.bigint "file_size", null: false
    t.jsonb "metadata", default: {}
    t.string "storage_key", null: false
    t.datetime "updated_at", null: false
    t.integer "version_number", null: false
    t.index ["account_id", "created_at"]
    t.index ["account_id"]
    t.index ["created_by_id"]
    t.index ["deleted_at"]
    t.index ["file_object_id", "version_number"], unique: true
    t.index ["file_object_id"]
    t.index ["storage_key"]
  end

  create_table "flipper_features", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], unique: true
  end

  create_table "flipper_gates", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "feature_key", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["feature_key", "key", "value"], unique: true
  end

  create_table "git_pipeline_approvals", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "environment"
    t.datetime "expires_at"
    t.string "gate_name", null: false
    t.uuid "git_pipeline_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.uuid "requested_by_id"
    t.jsonb "required_approvers", default: [], null: false
    t.datetime "responded_at"
    t.uuid "responded_by_id"
    t.text "response_comment"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"]
    t.index ["expires_at"]
    t.index ["git_pipeline_id", "gate_name"], unique: true
    t.index ["git_pipeline_id"]
    t.index ["requested_by_id"]
    t.index ["responded_by_id"]
    t.index ["status"]
  end

  create_table "git_pipeline_jobs", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "completed_at", precision: nil
    t.string "conclusion", limit: 30
    t.datetime "created_at", null: false
    t.integer "duration_seconds"
    t.string "external_id", limit: 255, null: false
    t.uuid "git_pipeline_id", null: false
    t.text "logs_content"
    t.text "logs_url"
    t.jsonb "metadata", default: {}
    t.string "name", limit: 255, null: false
    t.jsonb "outputs", default: {}
    t.string "runner_id", limit: 255
    t.string "runner_name", limit: 255
    t.string "runner_os", limit: 50
    t.datetime "started_at", precision: nil
    t.string "status", limit: 30, null: false
    t.integer "step_number"
    t.jsonb "steps", default: []
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"]
    t.index ["account_id"]
    t.index ["conclusion"]
    t.index ["git_pipeline_id", "external_id"], unique: true
    t.index ["git_pipeline_id"]
    t.index ["runner_name"]
    t.index ["status"]
  end

  create_table "git_pipeline_schedules", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.integer "consecutive_failures", default: 0, null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.string "cron_expression", null: false
    t.string "description"
    t.integer "failure_count", default: 0, null: false
    t.uuid "git_repository_id", null: false
    t.jsonb "inputs", default: {}, null: false
    t.boolean "is_active", default: true, null: false
    t.uuid "last_pipeline_id"
    t.datetime "last_run_at"
    t.string "last_run_status"
    t.string "name", null: false
    t.datetime "next_run_at"
    t.string "ref", null: false
    t.integer "run_count", default: 0, null: false
    t.integer "success_count", default: 0, null: false
    t.string "timezone", default: "UTC", null: false
    t.datetime "updated_at", null: false
    t.string "workflow_file"
    t.index ["account_id"]
    t.index ["created_by_id"]
    t.index ["git_repository_id", "name"], unique: true
    t.index ["git_repository_id"]
    t.index ["is_active"]
    t.index ["last_pipeline_id"]
    t.index ["next_run_at"]
  end

  create_table "git_pipelines", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "actor_id", limit: 255
    t.string "actor_username", limit: 255
    t.datetime "completed_at", precision: nil
    t.integer "completed_jobs", default: 0
    t.string "conclusion", limit: 30
    t.datetime "created_at", null: false
    t.integer "duration_seconds"
    t.string "external_id", limit: 255, null: false
    t.integer "failed_jobs", default: 0
    t.uuid "git_repository_id", null: false
    t.string "head_sha", limit: 64
    t.string "logs_url", limit: 500
    t.jsonb "metadata", default: {}
    t.string "name", limit: 255, null: false
    t.string "ref", limit: 500
    t.integer "run_attempt", default: 1
    t.integer "run_number"
    t.string "sha", limit: 64
    t.datetime "started_at", precision: nil
    t.string "status", limit: 30, null: false
    t.integer "total_jobs", default: 0
    t.string "trigger_event", limit: 50
    t.datetime "updated_at", null: false
    t.string "web_url", limit: 500
    t.jsonb "workflow_config", default: {}
    t.index ["account_id", "created_at"]
    t.index ["account_id"]
    t.index ["conclusion"]
    t.index ["created_at"]
    t.index ["git_repository_id", "external_id"], unique: true
    t.index ["git_repository_id"]
    t.index ["sha"]
    t.index ["status"]
    t.index ["trigger_event"]
  end

  create_table "git_provider_credentials", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "auth_type", limit: 30, null: false
    t.integer "consecutive_failures", default: 0
    t.datetime "created_at", null: false
    t.text "encrypted_credentials", null: false
    t.string "encryption_key_id", limit: 50
    t.datetime "expires_at", precision: nil
    t.string "external_avatar_url", limit: 500
    t.string "external_user_id", limit: 255
    t.string "external_username", limit: 255
    t.integer "failure_count", default: 0
    t.uuid "git_provider_id", null: false
    t.boolean "is_active", default: true
    t.boolean "is_default", default: false
    t.string "last_error", limit: 1000
    t.datetime "last_test_at", precision: nil
    t.string "last_test_status", limit: 30
    t.datetime "last_used_at", precision: nil
    t.jsonb "metadata", default: {}
    t.string "name", limit: 255, null: false
    t.jsonb "scopes", default: []
    t.integer "success_count", default: 0
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["account_id", "git_provider_id", "is_default"], name: "idx_git_creds_unique_default", unique: true, where: "(is_default = true)"
    t.index ["account_id", "git_provider_id"]
    t.index ["account_id", "is_default"]
    t.index ["account_id"]
    t.index ["auth_type"]
    t.index ["consecutive_failures"]
    t.index ["git_provider_id"]
    t.index ["is_active"]
    t.index ["user_id"]
  end

  create_table "git_providers", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "api_base_url", limit: 500
    t.jsonb "capabilities", default: [], null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "devops_config", default: {}
    t.boolean "is_active", default: true
    t.jsonb "metadata", default: {}
    t.string "name", limit: 100, null: false
    t.jsonb "oauth_config", default: {}
    t.integer "priority_order", default: 1000
    t.string "provider_type", limit: 30, null: false
    t.string "slug", limit: 50, null: false
    t.boolean "supports_devops", default: false
    t.boolean "supports_oauth", default: true
    t.boolean "supports_pat", default: true
    t.boolean "supports_webhooks", default: true
    t.datetime "updated_at", null: false
    t.string "web_base_url", limit: 500
    t.jsonb "webhook_config", default: {}
    t.index ["account_id"]
    t.index ["capabilities"], name: "index_git_providers_on_capabilities", using: :gin
    t.index ["is_active"]
    t.index ["priority_order"]
    t.index ["provider_type"]
    t.index ["slug"], unique: true
  end

  create_table "git_repositories", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "branch_filter", comment: "Branch filter pattern for webhooks"
    t.string "branch_filter_type", default: "none", comment: "Filter type: none, exact, wildcard, regex"
    t.string "clone_url", limit: 500
    t.datetime "created_at", null: false
    t.string "default_branch", limit: 255, default: "main"
    t.text "description"
    t.uuid "devops_provider_id"
    t.string "external_id", limit: 255, null: false
    t.integer "forks_count", default: 0
    t.string "full_name", limit: 500, null: false
    t.uuid "git_provider_credential_id"
    t.boolean "has_issues", default: true
    t.boolean "has_pull_requests", default: true
    t.boolean "has_wiki", default: false
    t.boolean "is_active", default: true, null: false
    t.boolean "is_archived", default: false
    t.boolean "is_fork", default: false
    t.boolean "is_private", default: false
    t.jsonb "languages", default: {}
    t.datetime "last_commit_at", precision: nil
    t.datetime "last_synced_at", precision: nil
    t.jsonb "metadata", default: {}
    t.string "name", limit: 255, null: false
    t.integer "open_issues_count", default: 0
    t.integer "open_prs_count", default: 0
    t.string "origin", default: "git", null: false
    t.string "owner", limit: 255, null: false
    t.datetime "provider_created_at", precision: nil
    t.datetime "provider_updated_at", precision: nil
    t.string "ssh_url", limit: 500
    t.integer "stars_count", default: 0
    t.jsonb "sync_settings", default: {}
    t.jsonb "topics", default: []
    t.datetime "updated_at", null: false
    t.string "web_url", limit: 500
    t.boolean "webhook_configured", default: false
    t.string "webhook_id", limit: 255
    t.string "webhook_secret", limit: 255
    t.index ["account_id", "devops_provider_id"], name: "idx_git_repos_account_devops_provider", where: "(devops_provider_id IS NOT NULL)"
    t.index ["account_id", "full_name"], unique: true
    t.index ["account_id"]
    t.index ["external_id"]
    t.index ["git_provider_credential_id"]
    t.index ["is_active"]
    t.index ["is_private"]
    t.index ["last_synced_at"]
    t.index ["origin"]
    t.index ["owner"]
    t.index ["topics"], name: "index_git_repositories_on_topics", using: :gin
    t.index ["webhook_configured"]
    t.check_constraint "branch_filter_type::text = ANY (ARRAY['none'::character varying::text, 'exact'::character varying::text, 'wildcard'::character varying::text, 'regex'::character varying::text])", name: "git_repositories_branch_filter_type_check"
  end

  create_table "git_runners", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "architecture"
    t.boolean "busy", default: false, null: false
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.integer "failed_jobs", default: 0, null: false
    t.uuid "git_provider_credential_id", null: false
    t.uuid "git_repository_id"
    t.jsonb "labels", default: [], null: false
    t.datetime "last_seen_at", precision: nil
    t.string "name", null: false
    t.string "os"
    t.string "runner_scope", default: "repository", null: false
    t.string "status", default: "offline", null: false
    t.integer "successful_jobs", default: 0, null: false
    t.integer "total_jobs_run", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "version"
    t.index ["account_id"]
    t.index ["busy"]
    t.index ["git_provider_credential_id", "external_id"], unique: true
    t.index ["git_provider_credential_id"]
    t.index ["git_repository_id"]
    t.index ["last_seen_at"]
    t.index ["runner_scope"]
    t.index ["status"]
  end

  create_table "git_webhook_events", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "action", limit: 50
    t.datetime "created_at", null: false
    t.string "delivery_id", limit: 255
    t.text "error_message"
    t.string "event_type", limit: 100, null: false
    t.uuid "git_provider_id", null: false
    t.uuid "git_repository_id"
    t.jsonb "headers", default: {}
    t.jsonb "metadata", default: {}
    t.jsonb "payload", null: false
    t.datetime "processed_at", precision: nil
    t.jsonb "processing_result", default: {}
    t.string "ref", limit: 500
    t.integer "retry_count", default: 0
    t.string "sender_id", limit: 255
    t.string "sender_username", limit: 255
    t.string "sha", limit: 64
    t.string "status", limit: 30, default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"]
    t.index ["account_id"]
    t.index ["created_at"]
    t.index ["delivery_id"]
    t.index ["event_type"]
    t.index ["git_provider_id"]
    t.index ["git_repository_id", "event_type"]
    t.index ["git_repository_id"]
    t.index ["status", "retry_count"]
    t.index ["status"]
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

  create_table "knowledge_base_article_tags", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "article_id", null: false
    t.datetime "created_at", null: false
    t.uuid "tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["article_id", "tag_id"], unique: true
    t.index ["tag_id"]
  end

  create_table "knowledge_base_article_views", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "article_id", null: false
    t.datetime "created_at", null: false
    t.string "ip_address", limit: 45
    t.jsonb "metadata", default: {}
    t.boolean "read_to_end", default: false
    t.integer "reading_time_seconds"
    t.string "referrer", limit: 1000
    t.string "session_id", limit: 255
    t.datetime "updated_at", null: false
    t.string "user_agent", limit: 1000
    t.uuid "user_id"
    t.datetime "viewed_at", null: false
    t.index ["article_id", "viewed_at"]
    t.index ["read_to_end"]
    t.index ["session_id"]
    t.index ["user_id"]
    t.index ["viewed_at"]
    t.check_constraint "reading_time_seconds IS NULL OR reading_time_seconds >= 0", name: "valid_kb_reading_time_seconds"
  end

  create_table "knowledge_base_articles", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "author_id", null: false
    t.uuid "category_id", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.text "excerpt"
    t.integer "helpful_count", default: 0
    t.decimal "helpfulness_score", precision: 5, scale: 2, default: "0.0"
    t.boolean "is_featured", default: false
    t.boolean "is_public", default: true
    t.uuid "last_edited_by_id"
    t.datetime "last_reviewed_at"
    t.integer "likes_count", default: 0
    t.text "meta_description"
    t.string "meta_title", limit: 255
    t.jsonb "metadata", default: {}
    t.integer "not_helpful_count", default: 0
    t.datetime "published_at"
    t.integer "reading_time_minutes"
    t.tsvector "search_vector"
    t.string "slug", limit: 255, null: false
    t.integer "sort_order", default: 0
    t.string "status", limit: 50, default: "draft"
    t.string "title", limit: 255, null: false
    t.datetime "updated_at", null: false
    t.integer "view_count", default: 0
    t.integer "views_count", default: 0
    t.index ["author_id"]
    t.index ["category_id"]
    t.index ["helpfulness_score"]
    t.index ["is_featured"]
    t.index ["is_public"]
    t.index ["last_edited_by_id"]
    t.index ["published_at"]
    t.index ["search_vector"], name: "idx_knowledge_base_articles_on_search_vector", using: :gin
    t.index ["slug"], unique: true
    t.index ["status"]
    t.index ["view_count"]
    t.check_constraint "helpful_count >= 0 AND not_helpful_count >= 0", name: "valid_kb_helpful_counts"
    t.check_constraint "helpfulness_score >= 0::numeric AND helpfulness_score <= 100::numeric", name: "valid_kb_helpfulness_score"
    t.check_constraint "reading_time_minutes IS NULL OR reading_time_minutes > 0", name: "valid_kb_reading_time"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'review'::character varying::text, 'published'::character varying::text, 'archived'::character varying::text])", name: "valid_kb_article_status"
    t.check_constraint "view_count >= 0", name: "valid_kb_view_count"
  end

  create_table "knowledge_base_attachments", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "article_id", null: false
    t.string "content_type", limit: 100
    t.datetime "created_at", null: false
    t.integer "download_count", default: 0
    t.string "file_path", limit: 1000
    t.bigint "file_size"
    t.string "filename", limit: 255, null: false
    t.jsonb "metadata", default: {}
    t.datetime "updated_at", null: false
    t.uuid "uploaded_by_id", null: false
    t.index ["article_id"]
    t.index ["download_count"]
    t.index ["filename"]
    t.index ["uploaded_by_id"]
    t.check_constraint "download_count >= 0", name: "valid_kb_download_count"
    t.check_constraint "file_size > 0", name: "valid_kb_attachment_size"
  end

  create_table "knowledge_base_categories", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "icon", limit: 100
    t.boolean "is_active", default: true
    t.boolean "is_public", default: true
    t.jsonb "metadata", default: {}
    t.string "name", limit: 255, null: false
    t.uuid "parent_id"
    t.string "slug", limit: 255, null: false
    t.integer "sort_order", default: 0
    t.datetime "updated_at", null: false
    t.index ["is_active"]
    t.index ["is_public"]
    t.index ["parent_id"]
    t.index ["slug"], unique: true
    t.index ["sort_order"]
  end

  create_table "knowledge_base_comments", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "article_id", null: false
    t.uuid "author_id", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.integer "helpful_count", default: 0
    t.boolean "is_helpful_vote", default: false
    t.jsonb "metadata", default: {}
    t.uuid "parent_id"
    t.string "status", limit: 50, default: "pending"
    t.datetime "updated_at", null: false
    t.index ["article_id", "status"]
    t.index ["author_id"]
    t.index ["created_at"]
    t.index ["is_helpful_vote"]
    t.index ["parent_id"]
    t.index ["status"]
    t.check_constraint "helpful_count >= 0", name: "valid_kb_comment_helpful_count"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'approved'::character varying::text, 'rejected'::character varying::text, 'spam'::character varying::text])", name: "valid_kb_comment_status"
  end

  create_table "knowledge_base_tags", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "color", limit: 7, default: "#6B7280"
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "is_active", default: true
    t.string "name", limit: 100, null: false
    t.string "slug", limit: 100, null: false
    t.datetime "updated_at", null: false
    t.integer "usage_count", default: 0
    t.index ["is_active"]
    t.index ["name"], unique: true
    t.index ["slug"], unique: true
    t.index ["usage_count"]
    t.check_constraint "color::text ~ '^#[0-9A-Fa-f]{6}$'::text", name: "valid_kb_tag_color"
    t.check_constraint "usage_count >= 0", name: "valid_kb_tag_usage_count"
  end

  create_table "knowledge_base_workflows", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "action", limit: 100, null: false
    t.uuid "article_id", null: false
    t.text "comment"
    t.datetime "created_at", null: false
    t.string "from_status", limit: 50
    t.jsonb "metadata", default: {}
    t.string "to_status", limit: 50
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["action"]
    t.index ["article_id", "created_at"]
    t.index ["created_at"]
    t.index ["from_status"]
    t.index ["to_status"]
    t.index ["user_id"]
    t.check_constraint "action::text = ANY (ARRAY['create'::character varying::text, 'edit'::character varying::text, 'publish'::character varying::text, 'unpublish'::character varying::text, 'archive'::character varying::text, 'delete'::character varying::text, 'review'::character varying::text])", name: "valid_kb_workflow_action"
  end

  create_table "mcp_servers", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "args", default: []
    t.string "auth_type", default: "none", null: false
    t.jsonb "capabilities", default: {}
    t.string "command"
    t.string "connection_type", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "env", default: {}
    t.datetime "last_health_check"
    t.datetime "migrated_to_vault_at"
    t.string "name", null: false
    t.text "oauth_access_token_encrypted"
    t.string "oauth_authorization_url"
    t.string "oauth_client_id"
    t.text "oauth_client_secret_encrypted"
    t.text "oauth_error"
    t.datetime "oauth_last_refreshed_at"
    t.string "oauth_pkce_code_verifier"
    t.string "oauth_provider"
    t.text "oauth_refresh_token_encrypted"
    t.string "oauth_scopes"
    t.string "oauth_state"
    t.datetime "oauth_token_expires_at"
    t.string "oauth_token_type", default: "Bearer"
    t.string "oauth_token_url"
    t.string "status", default: "disconnected", null: false
    t.datetime "updated_at", null: false
    t.string "vault_path"
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["auth_type"]
    t.index ["oauth_state"], name: "index_mcp_servers_on_oauth_state", unique: true, where: "(oauth_state IS NOT NULL)"
    t.index ["oauth_token_expires_at"]
    t.index ["status"]
    t.index ["vault_path"], name: "index_mcp_servers_on_vault_path", unique: true, where: "(vault_path IS NOT NULL)"
  end

  create_table "mcp_sessions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_agent_id"
    t.jsonb "client_info", default: {}
    t.datetime "created_at", null: false
    t.string "display_name", limit: 255
    t.datetime "expires_at"
    t.string "ip_address"
    t.datetime "last_activity_at"
    t.jsonb "metadata", default: {}
    t.uuid "oauth_application_id"
    t.string "protocol_version"
    t.datetime "revoked_at"
    t.string "session_token", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.uuid "user_id", null: false
    t.index ["account_id", "status"]
    t.index ["account_id"]
    t.index ["ai_agent_id"]
    t.index ["expires_at"]
    t.index ["oauth_application_id"]
    t.index ["session_token"], unique: true
    t.index ["user_id", "status"]
    t.index ["user_id"]
  end

  create_table "mcp_tool_executions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.text "error_message"
    t.integer "execution_time_ms"
    t.uuid "mcp_tool_id", null: false
    t.jsonb "parameters", default: {}
    t.jsonb "result", default: {}
    t.datetime "started_at"
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["mcp_tool_id", "created_at"]
    t.index ["mcp_tool_id"]
    t.index ["user_id", "created_at"]
    t.index ["user_id"]
  end

  create_table "mcp_tools", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "allowed_scopes", default: {}, null: false, comment: "Allowed operation scopes (file_access, network, data, system, ai)"
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.jsonb "input_schema", default: {}, null: false
    t.uuid "mcp_server_id", null: false
    t.string "name", null: false
    t.string "permission_level", default: "public", null: false, comment: "Permission level: public, account, admin"
    t.jsonb "required_permissions", default: [], null: false, comment: "Array of permission strings required to execute this tool"
    t.datetime "updated_at", null: false
    t.index ["mcp_server_id", "name"]
    t.index ["mcp_server_id"]
    t.index ["permission_level"]
    t.check_constraint "permission_level::text = ANY (ARRAY['public'::character varying::text, 'account'::character varying::text, 'admin'::character varying::text])", name: "mcp_tools_permission_level_check"
  end

  create_table "notifications", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "action_label"
    t.string "action_url"
    t.string "category", default: "general"
    t.datetime "created_at", null: false
    t.datetime "dismissed_at"
    t.datetime "expires_at"
    t.string "icon"
    t.text "message", null: false
    t.json "metadata", default: {}
    t.string "notification_type", null: false
    t.integer "priority", default: 0
    t.datetime "read_at"
    t.string "severity", default: "info", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["account_id", "created_at"]
    t.index ["account_id"]
    t.index ["category"]
    t.index ["expires_at"]
    t.index ["notification_type"]
    t.index ["priority"]
    t.index ["user_id", "created_at"]
    t.index ["user_id", "read_at"]
    t.index ["user_id"]
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

  create_table "pages", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "author_id", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.integer "estimated_read_time"
    t.text "excerpt"
    t.boolean "is_public", default: false
    t.text "meta_description"
    t.text "meta_keywords"
    t.string "meta_title", limit: 255
    t.jsonb "metadata", default: {}
    t.datetime "published_at"
    t.text "rendered_content"
    t.text "seo_description"
    t.string "seo_title", limit: 255
    t.string "slug", limit: 255, null: false
    t.string "status", limit: 50, default: "draft"
    t.string "title", limit: 255, null: false
    t.datetime "updated_at", null: false
    t.integer "word_count"
    t.index ["account_id"]
    t.index ["author_id"]
    t.index ["is_public"]
    t.index ["published_at"]
    t.index ["slug"], unique: true
    t.index ["status"]
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'published'::character varying::text, 'archived'::character varying::text])", name: "valid_page_status"
  end

  create_table "password_histories", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "password_digest", null: false
    t.uuid "user_id", null: false
    t.index ["created_at"]
    t.index ["user_id"]
  end

  create_table "report_requests", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "completed_at"
    t.string "content_type", limit: 100
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "expires_at"
    t.string "file_path", limit: 1000
    t.integer "file_size"
    t.integer "file_size_bytes"
    t.string "file_url"
    t.string "format", limit: 20, default: "pdf"
    t.string "name", limit: 255
    t.jsonb "parameters", default: {}
    t.string "report_type", limit: 100, null: false
    t.datetime "requested_at", null: false
    t.uuid "requested_by_id", null: false
    t.string "status", limit: 50, default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "report_type"]
    t.index ["account_id"]
    t.index ["expires_at"]
    t.index ["requested_at"]
    t.index ["requested_by_id"]
    t.index ["status"]
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'generating'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'expired'::character varying::text, 'cancelled'::character varying::text])", name: "valid_report_request_status"
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

  create_table "scheduled_reports", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.string "format", limit: 20, default: "pdf", null: false
    t.string "frequency", limit: 50, null: false
    t.boolean "is_active", default: true
    t.datetime "last_run_at"
    t.string "last_status", limit: 50
    t.string "name", limit: 255, null: false
    t.datetime "next_run_at"
    t.jsonb "parameters", default: {}
    t.jsonb "recipients", default: []
    t.string "report_type", limit: 100, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "report_type"]
    t.index ["account_id"]
    t.index ["created_by_id"]
    t.index ["frequency"]
    t.index ["is_active"]
    t.index ["next_run_at"]
    t.check_constraint "frequency::text = ANY (ARRAY['daily'::character varying::text, 'weekly'::character varying::text, 'monthly'::character varying::text, 'quarterly'::character varying::text, 'yearly'::character varying::text])", name: "valid_report_frequency"
  end

  create_table "scheduled_tasks", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "cron_expression", limit: 100
    t.integer "failure_count", default: 0
    t.integer "interval_seconds"
    t.boolean "is_active", default: true
    t.text "last_error_message"
    t.datetime "last_run_at"
    t.string "last_status", limit: 50
    t.string "name", limit: 255, null: false
    t.datetime "next_run_at"
    t.jsonb "parameters", default: {}
    t.integer "success_count", default: 0
    t.string "task_type", limit: 100, null: false
    t.datetime "updated_at", null: false
    t.index ["is_active"]
    t.index ["last_run_at"]
    t.index ["name"], unique: true
    t.index ["next_run_at"]
    t.index ["task_type"]
  end

  create_table "security_secrets", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "scope", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["account_id", "scope", "key"], unique: true
    t.index ["account_id"]
  end

  create_table "shared_prompt_templates", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "category", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.text "description"
    t.string "domain", default: "general", null: false
    t.boolean "is_active", default: true, null: false
    t.boolean "is_system", default: false, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.uuid "parent_template_id"
    t.decimal "rating", precision: 3, scale: 2, default: "0.0"
    t.integer "rating_count", default: 0
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.jsonb "variables", default: [], null: false
    t.integer "version", default: 1, null: false
    t.index ["account_id", "category"]
    t.index ["account_id", "domain"]
    t.index ["account_id", "slug"], unique: true
    t.index ["is_active"]
    t.index ["is_system"]
    t.index ["parent_template_id"]
  end

  create_table "site_settings", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "category", limit: 100
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "is_public", default: true
    t.string "key", limit: 255, null: false
    t.string "setting_type", limit: 50, default: "string"
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["category"]
    t.index ["is_public"]
    t.index ["key"], unique: true
    t.index ["setting_type"]
    t.check_constraint "setting_type::text = ANY (ARRAY['string'::character varying::text, 'text'::character varying::text, 'integer'::character varying::text, 'boolean'::character varying::text, 'json'::character varying::text, 'array'::character varying::text])", name: "valid_site_setting_type"
  end

  create_table "task_executions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.text "error_message"
    t.text "log_output"
    t.jsonb "result", default: {}
    t.uuid "scheduled_task_id", null: false
    t.datetime "started_at", null: false
    t.string "status", limit: 50, null: false
    t.datetime "updated_at", null: false
    t.index ["scheduled_task_id", "started_at"]
    t.index ["scheduled_task_id"]
    t.index ["started_at"]
    t.index ["status"]
    t.check_constraint "status::text = ANY (ARRAY['running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'timeout'::character varying::text])", name: "valid_execution_status"
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

  create_table "validation_rules", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.boolean "auto_fixable", default: false
    t.string "category", null: false
    t.jsonb "configuration", default: {}
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled", default: true
    t.string "name", null: false
    t.string "severity", default: "warning", null: false
    t.datetime "updated_at", null: false
    t.index ["category", "enabled"]
    t.index ["severity"]
  end

  create_table "webhook_deliveries", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.integer "attempt_number", default: 1
    t.datetime "attempted_at"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "next_retry_at"
    t.jsonb "request_headers", default: {}
    t.text "response_body"
    t.jsonb "response_headers", default: {}
    t.integer "response_status"
    t.integer "response_time_ms", comment: "Response time in milliseconds"
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.uuid "webhook_endpoint_id", null: false
    t.uuid "webhook_event_id", null: false
    t.index ["attempted_at"]
    t.index ["next_retry_at"]
    t.index ["status"]
    t.index ["webhook_endpoint_id"]
    t.index ["webhook_event_id"]
    t.check_constraint "attempt_number > 0", name: "valid_webhook_attempt_number"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'success'::character varying::text, 'failed'::character varying::text, 'timeout'::character varying::text])", name: "valid_webhook_delivery_status"
  end

  create_table "webhook_delivery_stats", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.integer "avg_latency_ms"
    t.datetime "created_at", null: false
    t.jsonb "error_counts", default: {}
    t.integer "failed_deliveries", default: 0, null: false
    t.integer "max_latency_ms"
    t.integer "min_latency_ms"
    t.integer "p95_latency_ms"
    t.integer "retried_deliveries", default: 0, null: false
    t.date "stat_date", null: false
    t.integer "successful_deliveries", default: 0, null: false
    t.integer "total_deliveries", default: 0, null: false
    t.datetime "updated_at", null: false
    t.uuid "webhook_endpoint_id", null: false
    t.index ["stat_date"]
    t.index ["webhook_endpoint_id", "stat_date"], unique: true
    t.index ["webhook_endpoint_id"]
  end

  create_table "webhook_endpoints", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.integer "circuit_break_threshold", default: 5, null: false, comment: "Number of consecutive failures before circuit break"
    t.datetime "circuit_broken_at"
    t.datetime "circuit_cooldown_until"
    t.integer "consecutive_failures", default: 0, null: false
    t.string "content_type", limit: 100, default: "application/json", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.jsonb "custom_headers", default: {}, null: false
    t.integer "daily_count", default: 0, null: false
    t.datetime "daily_count_reset_at"
    t.integer "daily_limit", default: 100, null: false
    t.string "description", limit: 500
    t.jsonb "event_types", default: []
    t.integer "failure_count", default: 0, null: false
    t.jsonb "headers", default: {}
    t.boolean "is_active", default: true
    t.datetime "last_delivery_at", precision: nil
    t.integer "max_retries", default: 3
    t.jsonb "metadata", default: {}
    t.string "payload_detail_level", default: "full", null: false, comment: "full, minimal, or ids_only"
    t.string "retry_backoff", limit: 20, default: "exponential", null: false
    t.integer "retry_limit", default: 3, null: false
    t.string "secret_key"
    t.string "signature_secret"
    t.string "status", limit: 20, default: "active", null: false
    t.integer "success_count", default: 0, null: false
    t.string "tier", default: "free", null: false
    t.integer "timeout_seconds", default: 30, null: false
    t.datetime "updated_at", null: false
    t.string "url", limit: 1000, null: false
    t.index ["account_id"]
    t.index ["circuit_broken_at"], name: "index_webhook_endpoints_on_circuit_broken", where: "(circuit_broken_at IS NOT NULL)"
    t.index ["content_type"]
    t.index ["created_by_id"]
    t.index ["failure_count"]
    t.index ["is_active"]
    t.index ["last_delivery_at"]
    t.index ["status", "is_active"]
    t.index ["success_count"]
    t.index ["tier"]
    t.check_constraint "content_type::text = ANY (ARRAY['application/json'::character varying::text, 'application/x-www-form-urlencoded'::character varying::text])", name: "valid_webhook_content_type"
    t.check_constraint "failure_count >= 0", name: "valid_webhook_failure_count"
    t.check_constraint "payload_detail_level::text = ANY (ARRAY['full'::character varying::text, 'minimal'::character varying::text, 'ids_only'::character varying::text])", name: "webhook_endpoints_payload_detail_level_check"
    t.check_constraint "retry_backoff::text = ANY (ARRAY['linear'::character varying::text, 'exponential'::character varying::text])", name: "valid_webhook_retry_backoff"
    t.check_constraint "retry_limit >= 0 AND retry_limit <= 10", name: "valid_webhook_retry_limit"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'suspended'::character varying::text])", name: "valid_webhook_status"
    t.check_constraint "success_count >= 0", name: "valid_webhook_success_count"
    t.check_constraint "tier::text = ANY (ARRAY['free'::text, 'pro'::text, 'business'::text])", name: "check_webhook_tier"
    t.check_constraint "timeout_seconds > 0 AND timeout_seconds <= 300", name: "valid_webhook_timeout"
  end

  create_table "webhook_events", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "event_id", null: false
    t.string "event_type", null: false
    t.string "external_id", null: false
    t.text "metadata"
    t.datetime "occurred_at", null: false
    t.jsonb "payload", default: {}
    t.uuid "payment_id"
    t.datetime "processed_at"
    t.string "provider", null: false
    t.integer "retry_count", default: 0, null: false
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.index ["account_id", "event_type"]
    t.index ["account_id"]
    t.index ["event_id"], unique: true
    t.index ["external_id"], unique: true
    t.index ["occurred_at"]
    t.index ["payment_id"]
    t.index ["provider"]
    t.index ["retry_count"]
    t.index ["status"]
    t.check_constraint "provider::text = ANY (ARRAY['stripe'::character varying::text, 'paypal'::character varying::text])", name: "valid_webhook_provider"
    t.check_constraint "retry_count >= 0 AND retry_count <= 10", name: "valid_webhook_retry_count"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'processed'::character varying::text, 'failed'::character varying::text, 'skipped'::character varying::text])", name: "valid_webhook_event_status"
  end

  create_table "worker_activities", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "activity_type", limit: 100, null: false
    t.datetime "created_at", null: false
    t.jsonb "details", default: {}
    t.datetime "occurred_at", null: false
    t.string "status", limit: 50
    t.datetime "updated_at", null: false
    t.uuid "worker_id", null: false
    t.index ["activity_type"]
    t.index ["occurred_at"]
    t.index ["worker_id", "occurred_at"]
    t.index ["worker_id"]
  end

  create_table "worker_roles", id: false, force: :cascade do |t|
    t.datetime "granted_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.uuid "role_id", null: false
    t.uuid "worker_id", null: false
    t.index ["role_id"]
    t.index ["worker_id", "role_id"], unique: true
    t.index ["worker_id"]
  end

  create_table "workers", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.jsonb "capabilities", default: {}, null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "is_system", default: false, null: false
    t.datetime "last_seen_at"
    t.string "name", null: false
    t.uuid "node_instance_id"
    t.jsonb "permissions", default: []
    t.string "status", default: "active"
    t.string "token_digest"
    t.datetime "updated_at", null: false
    t.string "worker_type", default: "background", null: false
    t.index ["account_id"]
    t.index ["capabilities"], name: "index_workers_on_capabilities", using: :gin
    t.index ["is_system"], name: "index_workers_on_is_system_unique", unique: true, where: "(is_system = true)"
    t.index ["name"], unique: true
    t.index ["node_instance_id"], name: "index_workers_on_node_instance_id", unique: true, where: "(node_instance_id IS NOT NULL)"
    t.index ["permissions"], name: "index_workers_on_permissions", using: :gin
    t.index ["status"]
    t.index ["worker_type"]
    t.check_constraint "worker_type::text = ANY (ARRAY['background'::character varying::text, 'infrastructure'::character varying::text])", name: "workers_worker_type_check"
  end

    add_foreign_key "account_delegations", "accounts", column: "account_id"
    add_foreign_key "account_delegations", "roles", column: "role_id"
    add_foreign_key "account_delegations", "users", column: "delegated_by_id"
    add_foreign_key "account_delegations", "users", column: "delegated_user_id"
    add_foreign_key "account_delegations", "users", column: "revoked_by_id"
    add_foreign_key "account_git_webhook_configs", "accounts", column: "account_id"
    add_foreign_key "account_git_webhook_configs", "users", column: "created_by_id"
    add_foreign_key "account_terminations", "accounts", column: "account_id"
    add_foreign_key "account_terminations", "data_export_requests", column: "data_export_request_id"
    add_foreign_key "account_terminations", "users", column: "cancelled_by_id"
    add_foreign_key "account_terminations", "users", column: "processed_by_id"
    add_foreign_key "account_terminations", "users", column: "requested_by_id"
    add_foreign_key "ai_a2a_task_events", "ai_a2a_tasks", column: "ai_a2a_task_id"
    add_foreign_key "ai_a2a_tasks", "accounts", column: "account_id"
    add_foreign_key "ai_a2a_tasks", "ai_a2a_tasks", column: "parent_task_id"
    add_foreign_key "ai_a2a_tasks", "ai_agent_cards", column: "from_agent_card_id"
    add_foreign_key "ai_a2a_tasks", "ai_agent_cards", column: "to_agent_card_id"
    add_foreign_key "ai_a2a_tasks", "ai_agents", column: "from_agent_id"
    add_foreign_key "ai_a2a_tasks", "ai_agents", column: "to_agent_id"
    add_foreign_key "ai_a2a_tasks", "chat_messages", column: "chat_message_id", on_delete: :nullify
    add_foreign_key "ai_a2a_tasks", "chat_sessions", column: "chat_session_id", on_delete: :nullify
    add_foreign_key "ai_a2a_tasks", "community_agents", column: "community_agent_id", on_delete: :nullify
    add_foreign_key "ai_a2a_tasks", "devops_container_instances", column: "container_instance_id"
    add_foreign_key "ai_a2a_tasks", "federation_partners", column: "federation_partner_id", on_delete: :nullify
    add_foreign_key "ai_ab_tests", "accounts", column: "account_id"
    add_foreign_key "ai_ab_tests", "users", column: "created_by_id"
    add_foreign_key "ai_agent_budgets", "accounts", column: "account_id"
    add_foreign_key "ai_agent_budgets", "ai_agent_budgets", column: "parent_budget_id", on_delete: :nullify
    add_foreign_key "ai_agent_budgets", "ai_agents", column: "agent_id"
    add_foreign_key "ai_agent_cards", "accounts", column: "account_id"
    add_foreign_key "ai_agent_cards", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_agent_connections", "accounts", column: "account_id"
    add_foreign_key "ai_agent_escalations", "accounts", column: "account_id"
    add_foreign_key "ai_agent_escalations", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_agent_escalations", "users", column: "escalated_to_user_id"
    add_foreign_key "ai_agent_executions", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "ai_agent_executions", "ai_agent_executions", column: "parent_execution_id", on_delete: :nullify
    add_foreign_key "ai_agent_executions", "ai_agents", column: "ai_agent_id", on_delete: :cascade
    add_foreign_key "ai_agent_executions", "ai_providers", column: "ai_provider_id", on_delete: :restrict
    add_foreign_key "ai_agent_executions", "users", column: "user_id", on_delete: :restrict
    add_foreign_key "ai_agent_feedbacks", "accounts", column: "account_id"
    add_foreign_key "ai_agent_feedbacks", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_agent_feedbacks", "users", column: "user_id"
    add_foreign_key "ai_agent_goals", "accounts", column: "account_id"
    add_foreign_key "ai_agent_goals", "ai_agent_goals", column: "parent_goal_id"
    add_foreign_key "ai_agent_goals", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_agent_identities", "accounts", column: "account_id"
    add_foreign_key "ai_agent_installations", "accounts", column: "account_id"
    add_foreign_key "ai_agent_installations", "ai_agent_templates", column: "agent_template_id"
    add_foreign_key "ai_agent_installations", "ai_agents", column: "installed_agent_id"
    add_foreign_key "ai_agent_installations", "users", column: "installed_by_id"
    add_foreign_key "ai_agent_lineages", "accounts", column: "account_id"
    add_foreign_key "ai_agent_lineages", "ai_agents", column: "child_agent_id"
    add_foreign_key "ai_agent_lineages", "ai_agents", column: "parent_agent_id"
    add_foreign_key "ai_agent_model_performances", "accounts", column: "account_id"
    add_foreign_key "ai_agent_model_performances", "ai_providers", column: "ai_provider_id"
    add_foreign_key "ai_agent_observations", "accounts", column: "account_id"
    add_foreign_key "ai_agent_observations", "ai_agent_goals", column: "goal_id"
    add_foreign_key "ai_agent_observations", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_agent_privilege_policies", "accounts", column: "account_id"
    add_foreign_key "ai_agent_proposals", "accounts", column: "account_id"
    add_foreign_key "ai_agent_proposals", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_agent_proposals", "ai_conversations", column: "conversation_id"
    add_foreign_key "ai_agent_proposals", "users", column: "reviewed_by_id"
    add_foreign_key "ai_agent_proposals", "users", column: "target_user_id"
    add_foreign_key "ai_agent_reviews", "accounts", column: "account_id"
    add_foreign_key "ai_agent_reviews", "ai_agent_installations", column: "installation_id"
    add_foreign_key "ai_agent_reviews", "ai_agent_templates", column: "agent_template_id"
    add_foreign_key "ai_agent_reviews", "users", column: "user_id"
    add_foreign_key "ai_agent_short_term_memories", "accounts", column: "account_id"
    add_foreign_key "ai_agent_short_term_memories", "ai_agents", column: "agent_id"
    add_foreign_key "ai_agent_skills", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_agent_skills", "ai_skills", column: "ai_skill_id"
    add_foreign_key "ai_agent_team_members", "ai_agent_teams", column: "ai_agent_team_id"
    add_foreign_key "ai_agent_team_members", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_agent_teams", "accounts", column: "account_id"
    add_foreign_key "ai_agent_templates", "ai_agents", column: "source_agent_id"
    add_foreign_key "ai_agent_trust_scores", "accounts", column: "account_id"
    add_foreign_key "ai_agent_trust_scores", "ai_agents", column: "agent_id"
    add_foreign_key "ai_agents", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "ai_agents", "ai_providers", column: "ai_provider_id"
    add_foreign_key "ai_agents", "users", column: "creator_id", on_delete: :restrict
    add_foreign_key "ai_agui_events", "accounts", column: "account_id"
    add_foreign_key "ai_agui_events", "ai_agui_sessions", column: "session_id"
    add_foreign_key "ai_agui_sessions", "accounts", column: "account_id"
    add_foreign_key "ai_agui_sessions", "users", column: "user_id"
    add_foreign_key "ai_approval_chains", "accounts", column: "account_id"
    add_foreign_key "ai_approval_chains", "users", column: "created_by_id"
    add_foreign_key "ai_approval_decisions", "ai_approval_requests", column: "approval_request_id"
    add_foreign_key "ai_approval_decisions", "users", column: "approver_id"
    add_foreign_key "ai_approval_requests", "accounts", column: "account_id"
    add_foreign_key "ai_approval_requests", "ai_approval_chains", column: "approval_chain_id"
    add_foreign_key "ai_approval_requests", "users", column: "requested_by_id"
    add_foreign_key "ai_behavioral_fingerprints", "accounts", column: "account_id"
    add_foreign_key "ai_behavioral_fingerprints", "ai_agents", column: "agent_id"
    add_foreign_key "ai_budget_transactions", "accounts", column: "account_id"
    add_foreign_key "ai_budget_transactions", "ai_agent_budgets", column: "ai_agent_budget_id"
    add_foreign_key "ai_budget_transactions", "ai_agent_executions", column: "ai_agent_execution_id"
    add_foreign_key "ai_circuit_breakers", "accounts", column: "account_id"
    add_foreign_key "ai_circuit_breakers", "ai_agents", column: "agent_id"
    add_foreign_key "ai_code_factory_evidence_manifests", "accounts", column: "account_id"
    add_foreign_key "ai_code_factory_evidence_manifests", "ai_code_factory_review_states", column: "review_state_id"
    add_foreign_key "ai_code_factory_harness_gaps", "accounts", column: "account_id"
    add_foreign_key "ai_code_factory_harness_gaps", "ai_code_factory_risk_contracts", column: "risk_contract_id"
    add_foreign_key "ai_code_factory_review_states", "accounts", column: "account_id"
    add_foreign_key "ai_code_factory_review_states", "ai_code_factory_risk_contracts", column: "risk_contract_id"
    add_foreign_key "ai_code_factory_review_states", "ai_missions", column: "mission_id"
    add_foreign_key "ai_code_factory_review_states", "git_repositories", column: "repository_id"
    add_foreign_key "ai_code_factory_risk_contracts", "accounts", column: "account_id"
    add_foreign_key "ai_code_factory_risk_contracts", "git_repositories", column: "repository_id"
    add_foreign_key "ai_code_factory_risk_contracts", "users", column: "created_by_id"
    add_foreign_key "ai_code_review_comments", "accounts", column: "account_id"
    add_foreign_key "ai_code_review_comments", "ai_agents", column: "agent_id"
    add_foreign_key "ai_code_review_comments", "ai_task_reviews", column: "task_review_id"
    add_foreign_key "ai_code_reviews", "accounts", column: "account_id"
    add_foreign_key "ai_code_reviews", "ai_pipeline_executions", column: "pipeline_execution_id"
    add_foreign_key "ai_collusion_indicators", "accounts", column: "account_id"
    add_foreign_key "ai_compliance_audit_entries", "accounts", column: "account_id"
    add_foreign_key "ai_compliance_audit_entries", "users", column: "user_id"
    add_foreign_key "ai_compliance_policies", "accounts", column: "account_id"
    add_foreign_key "ai_compliance_policies", "users", column: "created_by_id"
    add_foreign_key "ai_compliance_reports", "accounts", column: "account_id"
    add_foreign_key "ai_compliance_reports", "users", column: "generated_by_id"
    add_foreign_key "ai_compound_learnings", "accounts", column: "account_id"
    add_foreign_key "ai_compound_learnings", "ai_agent_teams", column: "ai_agent_team_id"
    add_foreign_key "ai_compound_learnings", "ai_agents", column: "source_agent_id"
    add_foreign_key "ai_compound_learnings", "ai_compound_learnings", column: "superseded_by_id"
    add_foreign_key "ai_compound_learnings", "ai_team_executions", column: "source_execution_id"
    add_foreign_key "ai_compound_learnings", "git_repositories", column: "git_repository_id", on_delete: :nullify
    add_foreign_key "ai_context_access_logs", "accounts", column: "account_id"
    add_foreign_key "ai_context_access_logs", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_context_access_logs", "ai_context_entries", column: "ai_context_entry_id"
    add_foreign_key "ai_context_access_logs", "ai_persistent_contexts", column: "ai_persistent_context_id"
    add_foreign_key "ai_context_access_logs", "users", column: "user_id"
    add_foreign_key "ai_context_entries", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_context_entries", "ai_persistent_contexts", column: "ai_persistent_context_id"
    add_foreign_key "ai_context_entries", "users", column: "created_by_user_id"
    add_foreign_key "ai_conversations", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "ai_conversations", "ai_agent_teams", column: "agent_team_id"
    add_foreign_key "ai_conversations", "ai_agents", column: "ai_agent_id", on_delete: :nullify
    add_foreign_key "ai_conversations", "ai_providers", column: "ai_provider_id", on_delete: :restrict
    add_foreign_key "ai_conversations", "users", column: "user_id", on_delete: :restrict
    add_foreign_key "ai_cost_attributions", "accounts", column: "account_id"
    add_foreign_key "ai_cost_attributions", "ai_providers", column: "provider_id"
    add_foreign_key "ai_cost_attributions", "ai_roi_metrics", column: "roi_metric_id"
    add_foreign_key "ai_cost_optimization_logs", "accounts", column: "account_id"
    add_foreign_key "ai_dag_executions", "accounts", column: "account_id"
    add_foreign_key "ai_dag_executions", "users", column: "triggered_by_id"
    add_foreign_key "ai_data_classifications", "accounts", column: "account_id"
    add_foreign_key "ai_data_classifications", "users", column: "classified_by_id"
    add_foreign_key "ai_data_connectors", "accounts", column: "account_id"
    add_foreign_key "ai_data_connectors", "ai_knowledge_bases", column: "knowledge_base_id"
    add_foreign_key "ai_data_connectors", "users", column: "created_by_id"
    add_foreign_key "ai_data_detections", "accounts", column: "account_id"
    add_foreign_key "ai_data_detections", "ai_data_classifications", column: "classification_id"
    add_foreign_key "ai_data_source_config_versions", "accounts", column: "account_id"
    add_foreign_key "ai_data_source_config_versions", "ai_data_sources", column: "ai_data_source_id"
    add_foreign_key "ai_data_source_credentials", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "ai_data_source_credentials", "ai_data_sources", column: "ai_data_source_id", on_delete: :cascade
    add_foreign_key "ai_data_source_endpoints", "ai_data_sources", column: "ai_data_source_id"
    add_foreign_key "ai_data_source_expectations", "ai_data_source_endpoints", column: "ai_data_source_endpoint_id"
    add_foreign_key "ai_data_source_queries", "ai_data_source_endpoints", column: "ai_data_source_endpoint_id"
    add_foreign_key "ai_data_source_queries", "ai_data_sources", column: "ai_data_source_id"
    add_foreign_key "ai_data_source_schema_versions", "ai_data_source_endpoints", column: "ai_data_source_endpoint_id"
    add_foreign_key "ai_data_source_subscriptions", "ai_data_source_endpoints", column: "ai_data_source_endpoint_id"
    add_foreign_key "ai_data_source_subscriptions", "ai_data_sources", column: "ai_data_source_id"
    add_foreign_key "ai_data_sources", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "ai_deferred_operations", "accounts", column: "account_id"
    add_foreign_key "ai_deferred_operations", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_deferred_operations", "ai_approval_requests", column: "approval_request_id"
    add_foreign_key "ai_deferred_operations", "users", column: "requested_by_id"
    add_foreign_key "ai_delegation_policies", "accounts", column: "account_id"
    add_foreign_key "ai_delegation_policies", "ai_agents", column: "agent_id"
    add_foreign_key "ai_deployment_risks", "accounts", column: "account_id"
    add_foreign_key "ai_deployment_risks", "ai_pipeline_executions", column: "pipeline_execution_id"
    add_foreign_key "ai_deployment_risks", "users", column: "assessed_by_id"
    add_foreign_key "ai_devops_template_installations", "accounts", column: "account_id"
    add_foreign_key "ai_devops_template_installations", "ai_devops_templates", column: "devops_template_id"
    add_foreign_key "ai_devops_template_installations", "users", column: "installed_by_id"
    add_foreign_key "ai_devops_templates", "accounts", column: "account_id"
    add_foreign_key "ai_devops_templates", "users", column: "created_by_id"
    add_foreign_key "ai_discovery_results", "accounts", column: "account_id"
    add_foreign_key "ai_document_chunks", "ai_documents", column: "document_id"
    add_foreign_key "ai_document_chunks", "ai_knowledge_bases", column: "knowledge_base_id"
    add_foreign_key "ai_documents", "ai_knowledge_bases", column: "knowledge_base_id"
    add_foreign_key "ai_documents", "users", column: "uploaded_by_id"
    add_foreign_key "ai_encrypted_messages", "accounts", column: "account_id"
    add_foreign_key "ai_evaluation_results", "accounts", column: "account_id"
    add_foreign_key "ai_evaluation_results", "ai_agents", column: "agent_id"
    add_foreign_key "ai_execution_events", "accounts", column: "account_id"
    add_foreign_key "ai_execution_trace_spans", "ai_execution_traces", column: "execution_trace_id"
    add_foreign_key "ai_execution_traces", "accounts", column: "account_id"
    add_foreign_key "ai_experience_replays", "accounts", column: "account_id"
    add_foreign_key "ai_experience_replays", "ai_agent_executions", column: "source_execution_id"
    add_foreign_key "ai_experience_replays", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_experience_replays", "ai_trajectories", column: "source_trajectory_id"
    add_foreign_key "ai_file_locks", "accounts", column: "account_id"
    add_foreign_key "ai_file_locks", "ai_worktree_sessions", column: "worktree_session_id"
    add_foreign_key "ai_file_locks", "ai_worktrees", column: "worktree_id"
    add_foreign_key "ai_goal_plan_steps", "ai_agent_goals", column: "sub_goal_id"
    add_foreign_key "ai_goal_plan_steps", "ai_goal_plans", column: "plan_id"
    add_foreign_key "ai_goal_plan_steps", "ai_ralph_tasks", column: "ralph_task_id"
    add_foreign_key "ai_goal_plans", "accounts", column: "account_id"
    add_foreign_key "ai_goal_plans", "ai_agent_goals", column: "goal_id"
    add_foreign_key "ai_goal_plans", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_goal_plans", "users", column: "approved_by_id"
    add_foreign_key "ai_governance_reports", "accounts", column: "account_id"
    add_foreign_key "ai_governance_reports", "ai_agent_teams", column: "subject_team_id"
    add_foreign_key "ai_governance_reports", "ai_agents", column: "monitor_agent_id"
    add_foreign_key "ai_governance_reports", "ai_agents", column: "subject_agent_id"
    add_foreign_key "ai_guardrail_configs", "accounts", column: "account_id"
    add_foreign_key "ai_guardrail_configs", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_hybrid_search_results", "accounts", column: "account_id"
    add_foreign_key "ai_improvement_recommendations", "accounts", column: "account_id"
    add_foreign_key "ai_improvement_recommendations", "users", column: "approved_by_id"
    add_foreign_key "ai_intervention_policies", "accounts", column: "account_id"
    add_foreign_key "ai_intervention_policies", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_intervention_policies", "ai_approval_chains", column: "approval_chain_id"
    add_foreign_key "ai_intervention_policies", "users", column: "user_id"
    add_foreign_key "ai_kill_switch_events", "accounts", column: "account_id"
    add_foreign_key "ai_kill_switch_events", "users", column: "triggered_by_id"
    add_foreign_key "ai_knowledge_bases", "accounts", column: "account_id"
    add_foreign_key "ai_knowledge_bases", "git_repositories", column: "git_repository_id"
    add_foreign_key "ai_knowledge_bases", "users", column: "created_by_id"
    add_foreign_key "ai_knowledge_graph_edges", "accounts", column: "account_id"
    add_foreign_key "ai_knowledge_graph_edges", "ai_documents", column: "source_document_id"
    add_foreign_key "ai_knowledge_graph_edges", "ai_knowledge_graph_nodes", column: "source_node_id"
    add_foreign_key "ai_knowledge_graph_edges", "ai_knowledge_graph_nodes", column: "target_node_id"
    add_foreign_key "ai_knowledge_graph_nodes", "accounts", column: "account_id"
    add_foreign_key "ai_knowledge_graph_nodes", "ai_documents", column: "source_document_id"
    add_foreign_key "ai_knowledge_graph_nodes", "ai_knowledge_bases", column: "knowledge_base_id"
    add_foreign_key "ai_knowledge_graph_nodes", "ai_knowledge_graph_nodes", column: "merged_into_id"
    add_foreign_key "ai_knowledge_graph_nodes", "ai_skills", column: "ai_skill_id"
    add_foreign_key "ai_mcp_app_instances", "accounts", column: "account_id"
    add_foreign_key "ai_mcp_app_instances", "ai_agui_sessions", column: "session_id"
    add_foreign_key "ai_mcp_app_instances", "ai_mcp_apps", column: "mcp_app_id"
    add_foreign_key "ai_mcp_apps", "accounts", column: "account_id"
    add_foreign_key "ai_memory_pools", "accounts", column: "account_id"
    add_foreign_key "ai_merge_operations", "accounts", column: "account_id"
    add_foreign_key "ai_merge_operations", "ai_worktree_sessions", column: "worktree_session_id"
    add_foreign_key "ai_merge_operations", "ai_worktrees", column: "worktree_id"
    add_foreign_key "ai_messages", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_messages", "ai_conversations", column: "ai_conversation_id", on_delete: :cascade
    add_foreign_key "ai_messages", "ai_messages", column: "parent_message_id", on_delete: :nullify
    add_foreign_key "ai_messages", "users", column: "user_id", on_delete: :nullify
    add_foreign_key "ai_mission_approvals", "ai_missions", column: "mission_id"
    add_foreign_key "ai_missions", "ai_agent_teams", column: "team_id"
    add_foreign_key "ai_missions", "ai_code_factory_review_states", column: "review_state_id"
    add_foreign_key "ai_missions", "ai_code_factory_risk_contracts", column: "risk_contract_id"
    add_foreign_key "ai_missions", "ai_conversations", column: "conversation_id"
    add_foreign_key "ai_missions", "ai_mission_templates", column: "mission_template_id"
    add_foreign_key "ai_missions", "ai_ralph_loops", column: "ralph_loop_id", on_delete: :nullify
    add_foreign_key "ai_missions", "git_repositories", column: "repository_id"
    add_foreign_key "ai_missions", "users", column: "created_by_id"
    add_foreign_key "ai_mock_responses", "accounts", column: "account_id"
    add_foreign_key "ai_mock_responses", "ai_sandboxes", column: "sandbox_id"
    add_foreign_key "ai_mock_responses", "users", column: "created_by_id"
    add_foreign_key "ai_model_routing_rules", "accounts", column: "account_id"
    add_foreign_key "ai_performance_benchmarks", "accounts", column: "account_id"
    add_foreign_key "ai_performance_benchmarks", "ai_agents", column: "target_agent_id"
    add_foreign_key "ai_performance_benchmarks", "ai_sandboxes", column: "sandbox_id"
    add_foreign_key "ai_performance_benchmarks", "users", column: "created_by_id"
    add_foreign_key "ai_persistent_contexts", "accounts", column: "account_id"
    add_foreign_key "ai_persistent_contexts", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_persistent_contexts", "users", column: "created_by_user_id"
    add_foreign_key "ai_pipeline_executions", "accounts", column: "account_id"
    add_foreign_key "ai_pipeline_executions", "ai_devops_template_installations", column: "devops_installation_id"
    add_foreign_key "ai_pipeline_executions", "users", column: "triggered_by_id"
    add_foreign_key "ai_policy_violations", "accounts", column: "account_id"
    add_foreign_key "ai_policy_violations", "ai_compliance_policies", column: "policy_id"
    add_foreign_key "ai_policy_violations", "users", column: "detected_by_id"
    add_foreign_key "ai_policy_violations", "users", column: "resolved_by_id"
    add_foreign_key "ai_pressure_fields", "accounts", column: "account_id"
    add_foreign_key "ai_provider_credentials", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "ai_provider_credentials", "ai_providers", column: "ai_provider_id", on_delete: :cascade
    add_foreign_key "ai_provider_metrics", "accounts", column: "account_id"
    add_foreign_key "ai_provider_metrics", "ai_providers", column: "provider_id"
    add_foreign_key "ai_providers", "accounts", column: "account_id"
    add_foreign_key "ai_provisioning_code_deployments", "ai_missions", column: "mission_id"
    add_foreign_key "ai_quarantine_records", "accounts", column: "account_id"
    add_foreign_key "ai_rag_queries", "accounts", column: "account_id"
    add_foreign_key "ai_rag_queries", "ai_knowledge_bases", column: "knowledge_base_id"
    add_foreign_key "ai_rag_queries", "ai_missions", column: "mission_id"
    add_foreign_key "ai_rag_queries", "users", column: "user_id"
    add_foreign_key "ai_ralph_iterations", "ai_ralph_loops", column: "ralph_loop_id"
    add_foreign_key "ai_ralph_iterations", "ai_ralph_tasks", column: "ralph_task_id"
    add_foreign_key "ai_ralph_loops", "accounts", column: "account_id"
    add_foreign_key "ai_ralph_loops", "ai_agents", column: "default_agent_id", on_delete: :nullify
    add_foreign_key "ai_ralph_loops", "ai_code_factory_risk_contracts", column: "risk_contract_id"
    add_foreign_key "ai_ralph_loops", "ai_missions", column: "mission_id", on_delete: :nullify
    add_foreign_key "ai_ralph_loops", "devops_container_instances", column: "container_instance_id"
    add_foreign_key "ai_ralph_tasks", "ai_ralph_loops", column: "ralph_loop_id"
    add_foreign_key "ai_recorded_interactions", "accounts", column: "account_id"
    add_foreign_key "ai_recorded_interactions", "ai_sandboxes", column: "sandbox_id"
    add_foreign_key "ai_remediation_logs", "accounts", column: "account_id"
    add_foreign_key "ai_roi_metrics", "accounts", column: "account_id"
    add_foreign_key "ai_role_profiles", "accounts", column: "account_id"
    add_foreign_key "ai_routing_decisions", "accounts", column: "account_id"
    add_foreign_key "ai_routing_decisions", "ai_agent_executions", column: "agent_execution_id"
    add_foreign_key "ai_routing_decisions", "ai_model_routing_rules", column: "routing_rule_id"
    add_foreign_key "ai_routing_decisions", "ai_providers", column: "selected_provider_id"
    add_foreign_key "ai_routing_decisions", "ai_task_complexity_assessments", column: "complexity_assessment_id"
    add_foreign_key "ai_runner_dispatches", "ai_missions", column: "mission_id"
    add_foreign_key "ai_runner_dispatches", "ai_worktree_sessions", column: "worktree_session_id"
    add_foreign_key "ai_runner_dispatches", "ai_worktrees", column: "worktree_id"
    add_foreign_key "ai_runner_dispatches", "git_repositories", column: "git_repository_id"
    add_foreign_key "ai_runner_dispatches", "git_runners", column: "git_runner_id"
    add_foreign_key "ai_sandboxes", "accounts", column: "account_id"
    add_foreign_key "ai_sandboxes", "users", column: "created_by_id"
    add_foreign_key "ai_scheduled_messages", "accounts", column: "account_id"
    add_foreign_key "ai_scheduled_messages", "ai_conversations", column: "conversation_id"
    add_foreign_key "ai_scheduled_messages", "users", column: "user_id"
    add_foreign_key "ai_security_audit_trails", "accounts", column: "account_id"
    add_foreign_key "ai_self_challenges", "accounts", column: "account_id"
    add_foreign_key "ai_self_challenges", "ai_agents", column: "challenger_agent_id"
    add_foreign_key "ai_self_challenges", "ai_agents", column: "executor_agent_id"
    add_foreign_key "ai_self_challenges", "ai_agents", column: "validator_agent_id"
    add_foreign_key "ai_self_challenges", "ai_skills", column: "ai_skill_id"
    add_foreign_key "ai_shadow_executions", "accounts", column: "account_id"
    add_foreign_key "ai_shadow_executions", "ai_agents", column: "agent_id"
    add_foreign_key "ai_shared_knowledges", "accounts", column: "account_id"
    add_foreign_key "ai_shared_knowledges", "git_repositories", column: "git_repository_id", on_delete: :nullify
    add_foreign_key "ai_shared_knowledges", "users", column: "created_by_id"
    add_foreign_key "ai_skill_compositions", "ai_skills", column: "component_skill_id"
    add_foreign_key "ai_skill_compositions", "ai_skills", column: "composite_skill_id"
    add_foreign_key "ai_skill_conflicts", "accounts", column: "account_id"
    add_foreign_key "ai_skill_conflicts", "ai_skills", column: "skill_a_id"
    add_foreign_key "ai_skill_conflicts", "ai_skills", column: "skill_b_id"
    add_foreign_key "ai_skill_conflicts", "users", column: "resolved_by_id"
    add_foreign_key "ai_skill_proposals", "accounts", column: "account_id"
    add_foreign_key "ai_skill_proposals", "ai_agents", column: "proposed_by_agent_id"
    add_foreign_key "ai_skill_proposals", "ai_skill_proposals", column: "parent_proposal_id"
    add_foreign_key "ai_skill_proposals", "ai_skills", column: "created_skill_id"
    add_foreign_key "ai_skill_proposals", "users", column: "proposed_by_user_id"
    add_foreign_key "ai_skill_proposals", "users", column: "reviewed_by_id"
    add_foreign_key "ai_skill_recipe_runs", "accounts", column: "account_id"
    add_foreign_key "ai_skill_recipe_runs", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_skill_recipe_runs", "ai_skills", column: "ai_skill_id"
    add_foreign_key "ai_skill_recipe_runs", "users", column: "user_id"
    add_foreign_key "ai_skill_usage_records", "accounts", column: "account_id"
    add_foreign_key "ai_skill_usage_records", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_skill_usage_records", "ai_skills", column: "ai_skill_id"
    add_foreign_key "ai_skill_versions", "accounts", column: "account_id"
    add_foreign_key "ai_skill_versions", "ai_agents", column: "created_by_agent_id"
    add_foreign_key "ai_skill_versions", "ai_skills", column: "ai_skill_id"
    add_foreign_key "ai_skill_versions", "users", column: "created_by_user_id"
    add_foreign_key "ai_skills", "accounts", column: "account_id"
    add_foreign_key "ai_skills", "ai_knowledge_bases", column: "ai_knowledge_base_id"
    add_foreign_key "ai_skills", "ai_skills", column: "parent_skill_id"
    add_foreign_key "ai_skills_mcp_servers", "ai_skills", column: "ai_skill_id"
    add_foreign_key "ai_skills_mcp_servers", "mcp_servers", column: "mcp_server_id"
    add_foreign_key "ai_stigmergic_signals", "accounts", column: "account_id"
    add_foreign_key "ai_stigmergic_signals", "ai_agents", column: "emitter_agent_id"
    add_foreign_key "ai_stigmergic_signals", "ai_memory_pools", column: "memory_pool_id"
    add_foreign_key "ai_task_complexity_assessments", "accounts", column: "account_id"
    add_foreign_key "ai_task_complexity_assessments", "ai_routing_decisions", column: "routing_decision_id"
    add_foreign_key "ai_task_reviews", "accounts", column: "account_id"
    add_foreign_key "ai_task_reviews", "ai_agents", column: "reviewer_agent_id"
    add_foreign_key "ai_task_reviews", "ai_team_roles", column: "reviewer_role_id"
    add_foreign_key "ai_task_reviews", "ai_team_tasks", column: "team_task_id"
    add_foreign_key "ai_team_channels", "ai_agent_teams", column: "agent_team_id"
    add_foreign_key "ai_team_executions", "accounts", column: "account_id"
    add_foreign_key "ai_team_executions", "ai_agent_teams", column: "agent_team_id"
    add_foreign_key "ai_team_executions", "ai_conversations", column: "ai_conversation_id"
    add_foreign_key "ai_team_executions", "ai_missions", column: "mission_id"
    add_foreign_key "ai_team_executions", "users", column: "approval_decided_by_id"
    add_foreign_key "ai_team_executions", "users", column: "triggered_by_id"
    add_foreign_key "ai_team_messages", "ai_team_channels", column: "channel_id"
    add_foreign_key "ai_team_messages", "ai_team_executions", column: "team_execution_id"
    add_foreign_key "ai_team_messages", "ai_team_roles", column: "from_role_id"
    add_foreign_key "ai_team_messages", "ai_team_roles", column: "to_role_id"
    add_foreign_key "ai_team_messages", "users", column: "user_id"
    add_foreign_key "ai_team_restructure_events", "accounts", column: "account_id"
    add_foreign_key "ai_team_restructure_events", "ai_agent_teams", column: "ai_agent_team_id"
    add_foreign_key "ai_team_restructure_events", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_team_roles", "accounts", column: "account_id"
    add_foreign_key "ai_team_roles", "ai_agent_teams", column: "agent_team_id"
    add_foreign_key "ai_team_roles", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_team_tasks", "ai_agents", column: "assigned_agent_id"
    add_foreign_key "ai_team_tasks", "ai_team_executions", column: "team_execution_id"
    add_foreign_key "ai_team_tasks", "ai_team_roles", column: "assigned_role_id"
    add_foreign_key "ai_team_templates", "accounts", column: "account_id"
    add_foreign_key "ai_team_templates", "users", column: "created_by_id"
    add_foreign_key "ai_telemetry_events", "accounts", column: "account_id"
    add_foreign_key "ai_telemetry_events", "ai_agents", column: "agent_id"
    add_foreign_key "ai_template_usage_metrics", "ai_agent_templates", column: "agent_template_id"
    add_foreign_key "ai_test_results", "ai_test_runs", column: "test_run_id"
    add_foreign_key "ai_test_results", "ai_test_scenarios", column: "scenario_id"
    add_foreign_key "ai_test_runs", "accounts", column: "account_id"
    add_foreign_key "ai_test_runs", "ai_sandboxes", column: "sandbox_id"
    add_foreign_key "ai_test_runs", "users", column: "triggered_by_id"
    add_foreign_key "ai_test_scenarios", "accounts", column: "account_id"
    add_foreign_key "ai_test_scenarios", "ai_agents", column: "target_agent_id"
    add_foreign_key "ai_test_scenarios", "ai_sandboxes", column: "sandbox_id"
    add_foreign_key "ai_test_scenarios", "users", column: "created_by_id"
    add_foreign_key "ai_trajectories", "accounts", column: "account_id"
    add_foreign_key "ai_trajectories", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_trajectory_chapters", "ai_trajectories", column: "trajectory_id"
    add_foreign_key "ai_worktree_sessions", "accounts", column: "account_id"
    add_foreign_key "ai_worktree_sessions", "users", column: "initiated_by_id"
    add_foreign_key "ai_worktrees", "accounts", column: "account_id"
    add_foreign_key "ai_worktrees", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_worktrees", "ai_worktree_sessions", column: "worktree_session_id"
    add_foreign_key "api_key_usages", "api_keys", column: "api_key_id"
    add_foreign_key "api_keys", "accounts", column: "account_id"
    add_foreign_key "api_keys", "users", column: "created_by_id"
    add_foreign_key "audit_logs", "accounts", column: "account_id"
    add_foreign_key "audit_logs", "users", column: "user_id", on_delete: :nullify
    add_foreign_key "blacklisted_tokens", "users", column: "user_id"
    add_foreign_key "chat_blacklists", "accounts", column: "account_id"
    add_foreign_key "chat_blacklists", "chat_channels", column: "channel_id"
    add_foreign_key "chat_blacklists", "users", column: "blocked_by_id"
    add_foreign_key "chat_channels", "accounts", column: "account_id"
    add_foreign_key "chat_channels", "ai_agents", column: "default_agent_id"
    add_foreign_key "chat_channels", "ai_team_channels", column: "ai_team_channel_id"
    add_foreign_key "chat_message_attachments", "chat_messages", column: "message_id"
    add_foreign_key "chat_message_attachments", "file_objects", column: "file_object_id"
    add_foreign_key "chat_messages", "ai_messages", column: "ai_message_id"
    add_foreign_key "chat_messages", "chat_sessions", column: "session_id"
    add_foreign_key "chat_sessions", "ai_agents", column: "assigned_agent_id"
    add_foreign_key "chat_sessions", "ai_conversations", column: "ai_conversation_id"
    add_foreign_key "chat_sessions", "chat_channels", column: "channel_id"
    add_foreign_key "circuit_breaker_events", "circuit_breakers", column: "circuit_breaker_id"
    add_foreign_key "community_agent_ratings", "accounts", column: "account_id"
    add_foreign_key "community_agent_ratings", "ai_a2a_tasks", column: "a2a_task_id"
    add_foreign_key "community_agent_ratings", "community_agents", column: "community_agent_id"
    add_foreign_key "community_agent_ratings", "users", column: "user_id"
    add_foreign_key "community_agent_reports", "accounts", column: "reported_by_account_id"
    add_foreign_key "community_agent_reports", "community_agents", column: "community_agent_id"
    add_foreign_key "community_agent_reports", "users", column: "reported_by_user_id"
    add_foreign_key "community_agent_reports", "users", column: "resolved_by_id"
    add_foreign_key "community_agents", "accounts", column: "owner_account_id"
    add_foreign_key "community_agents", "ai_agent_cards", column: "agent_card_id"
    add_foreign_key "community_agents", "ai_agents", column: "agent_id"
    add_foreign_key "community_agents", "users", column: "published_by_id"
    add_foreign_key "community_agents", "users", column: "verified_by_id"
    add_foreign_key "data_deletion_requests", "accounts", column: "account_id"
    add_foreign_key "data_deletion_requests", "users", column: "processed_by_id"
    add_foreign_key "data_deletion_requests", "users", column: "requested_by_id"
    add_foreign_key "data_deletion_requests", "users", column: "user_id"
    add_foreign_key "data_export_requests", "accounts", column: "account_id"
    add_foreign_key "data_export_requests", "users", column: "requested_by_id"
    add_foreign_key "data_export_requests", "users", column: "user_id"
    add_foreign_key "data_retention_policies", "accounts", column: "account_id"
    add_foreign_key "database_backups", "users", column: "created_by_id"
    add_foreign_key "database_restores", "database_backups", column: "database_backup_id"
    add_foreign_key "database_restores", "users", column: "initiated_by_id"
    add_foreign_key "delegation_permissions", "account_delegations", column: "account_delegation_id"
    add_foreign_key "devops_ai_configs", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "devops_ai_configs", "users", column: "created_by_id", on_delete: :nullify
    add_foreign_key "devops_container_image_builds", "accounts", column: "account_id"
    add_foreign_key "devops_container_image_builds", "devops_container_image_builds", column: "triggered_by_build_id"
    add_foreign_key "devops_container_image_builds", "devops_container_templates", column: "container_template_id"
    add_foreign_key "devops_container_instances", "accounts", column: "account_id"
    add_foreign_key "devops_container_instances", "ai_a2a_tasks", column: "a2a_task_id"
    add_foreign_key "devops_container_instances", "devops_container_templates", column: "template_id"
    add_foreign_key "devops_container_instances", "oauth_applications", column: "oauth_application_id"
    add_foreign_key "devops_container_instances", "users", column: "triggered_by_id"
    add_foreign_key "devops_container_templates", "accounts", column: "account_id"
    add_foreign_key "devops_container_templates", "devops_container_templates", column: "parent_template_id"
    add_foreign_key "devops_container_templates", "users", column: "created_by_id"
    add_foreign_key "devops_docker_activities", "devops_docker_containers", column: "container_id"
    add_foreign_key "devops_docker_activities", "devops_docker_hosts", column: "docker_host_id"
    add_foreign_key "devops_docker_activities", "devops_docker_images", column: "image_id"
    add_foreign_key "devops_docker_activities", "users", column: "triggered_by_id"
    add_foreign_key "devops_docker_containers", "devops_docker_hosts", column: "docker_host_id"
    add_foreign_key "devops_docker_events", "devops_docker_hosts", column: "docker_host_id"
    add_foreign_key "devops_docker_events", "users", column: "acknowledged_by_id"
    add_foreign_key "devops_docker_hosts", "accounts", column: "account_id"
    add_foreign_key "devops_docker_images", "devops_docker_hosts", column: "docker_host_id"
    add_foreign_key "devops_integration_credentials", "accounts", column: "account_id"
    add_foreign_key "devops_integration_credentials", "users", column: "created_by_user_id"
    add_foreign_key "devops_integration_executions", "accounts", column: "account_id"
    add_foreign_key "devops_integration_executions", "devops_integration_instances", column: "integration_instance_id"
    add_foreign_key "devops_integration_executions", "users", column: "triggered_by_user_id"
    add_foreign_key "devops_integration_instances", "accounts", column: "account_id"
    add_foreign_key "devops_integration_instances", "devops_integration_credentials", column: "integration_credential_id"
    add_foreign_key "devops_integration_instances", "devops_integration_templates", column: "integration_template_id"
    add_foreign_key "devops_integration_instances", "users", column: "created_by_user_id"
    add_foreign_key "devops_kubernetes_clusters", "accounts", column: "account_id"
    add_foreign_key "devops_kubernetes_nodes", "devops_kubernetes_clusters", column: "kubernetes_cluster_id", on_delete: :cascade
    add_foreign_key "devops_pipeline_repositories", "devops_pipelines", column: "devops_pipeline_id", on_delete: :cascade
    add_foreign_key "devops_pipeline_repositories", "git_repositories", column: "git_repository_id", on_delete: :cascade
    add_foreign_key "devops_pipeline_runs", "devops_pipelines", column: "devops_pipeline_id", on_delete: :cascade
    add_foreign_key "devops_pipeline_runs", "users", column: "triggered_by_id", on_delete: :nullify
    add_foreign_key "devops_pipeline_steps", "devops_pipelines", column: "devops_pipeline_id", on_delete: :cascade
    add_foreign_key "devops_pipeline_steps", "shared_prompt_templates", column: "shared_prompt_template_id", on_delete: :nullify
    add_foreign_key "devops_pipelines", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "devops_pipelines", "ai_providers", column: "ai_provider_id", on_delete: :nullify
    add_foreign_key "devops_pipelines", "devops_providers", column: "devops_provider_id", on_delete: :restrict
    add_foreign_key "devops_pipelines", "users", column: "created_by_id", on_delete: :nullify
    add_foreign_key "devops_port_allocations", "accounts", column: "account_id"
    add_foreign_key "devops_providers", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "devops_providers", "users", column: "created_by_id", on_delete: :nullify
    add_foreign_key "devops_resource_quotas", "accounts", column: "account_id"
    add_foreign_key "devops_schedules", "devops_pipelines", column: "devops_pipeline_id", on_delete: :cascade
    add_foreign_key "devops_schedules", "users", column: "created_by_id", on_delete: :nullify
    add_foreign_key "devops_secret_references", "accounts", column: "account_id"
    add_foreign_key "devops_secret_references", "users", column: "created_by_id"
    add_foreign_key "devops_step_approval_tokens", "devops_step_executions", column: "step_execution_id"
    add_foreign_key "devops_step_approval_tokens", "users", column: "recipient_user_id"
    add_foreign_key "devops_step_approval_tokens", "users", column: "responded_by_id"
    add_foreign_key "devops_step_executions", "devops_pipeline_runs", column: "devops_pipeline_run_id", on_delete: :cascade
    add_foreign_key "devops_step_executions", "devops_pipeline_steps", column: "devops_pipeline_step_id", on_delete: :cascade
    add_foreign_key "devops_swarm_clusters", "accounts", column: "account_id"
    add_foreign_key "devops_swarm_deployments", "devops_swarm_clusters", column: "cluster_id"
    add_foreign_key "devops_swarm_deployments", "devops_swarm_services", column: "service_id"
    add_foreign_key "devops_swarm_deployments", "devops_swarm_stacks", column: "stack_id"
    add_foreign_key "devops_swarm_deployments", "users", column: "triggered_by_id"
    add_foreign_key "devops_swarm_events", "devops_swarm_clusters", column: "cluster_id"
    add_foreign_key "devops_swarm_events", "users", column: "acknowledged_by_id"
    add_foreign_key "devops_swarm_nodes", "devops_swarm_clusters", column: "cluster_id"
    add_foreign_key "devops_swarm_services", "devops_swarm_clusters", column: "cluster_id"
    add_foreign_key "devops_swarm_services", "devops_swarm_stacks", column: "stack_id"
    add_foreign_key "devops_swarm_stacks", "devops_swarm_clusters", column: "cluster_id"
    add_foreign_key "email_deliveries", "users", column: "user_id"
    add_foreign_key "external_agents", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "external_agents", "users", column: "created_by_id", on_delete: :nullify
    add_foreign_key "federation_partners", "accounts", column: "account_id"
    add_foreign_key "federation_partners", "users", column: "approved_by_id"
    add_foreign_key "federation_partners", "users", column: "created_by_id"
    add_foreign_key "file_object_tags", "accounts", column: "account_id"
    add_foreign_key "file_object_tags", "file_objects", column: "file_object_id"
    add_foreign_key "file_object_tags", "file_tags", column: "file_tag_id"
    add_foreign_key "file_objects", "accounts", column: "account_id"
    add_foreign_key "file_objects", "file_storages", column: "file_storage_id"
    add_foreign_key "file_objects", "users", column: "deleted_by_id"
    add_foreign_key "file_objects", "users", column: "uploaded_by_id"
    add_foreign_key "file_processing_jobs", "accounts", column: "account_id"
    add_foreign_key "file_processing_jobs", "file_objects", column: "file_object_id"
    add_foreign_key "file_shares", "accounts", column: "account_id"
    add_foreign_key "file_shares", "file_objects", column: "file_object_id"
    add_foreign_key "file_shares", "users", column: "created_by_id"
    add_foreign_key "file_storages", "accounts", column: "account_id"
    add_foreign_key "file_tags", "accounts", column: "account_id"
    add_foreign_key "file_versions", "accounts", column: "account_id"
    add_foreign_key "file_versions", "file_objects", column: "file_object_id"
    add_foreign_key "file_versions", "users", column: "created_by_id"
    add_foreign_key "git_pipeline_approvals", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "git_pipeline_approvals", "git_pipelines", column: "git_pipeline_id", on_delete: :cascade
    add_foreign_key "git_pipeline_approvals", "users", column: "requested_by_id", on_delete: :nullify
    add_foreign_key "git_pipeline_approvals", "users", column: "responded_by_id", on_delete: :nullify
    add_foreign_key "git_pipeline_jobs", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "git_pipeline_jobs", "git_pipelines", column: "git_pipeline_id", on_delete: :cascade
    add_foreign_key "git_pipeline_schedules", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "git_pipeline_schedules", "git_pipelines", column: "last_pipeline_id", on_delete: :nullify
    add_foreign_key "git_pipeline_schedules", "git_repositories", column: "git_repository_id", on_delete: :cascade
    add_foreign_key "git_pipeline_schedules", "users", column: "created_by_id", on_delete: :nullify
    add_foreign_key "git_pipelines", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "git_pipelines", "git_repositories", column: "git_repository_id", on_delete: :cascade
    add_foreign_key "git_provider_credentials", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "git_provider_credentials", "git_providers", column: "git_provider_id", on_delete: :cascade
    add_foreign_key "git_provider_credentials", "users", column: "user_id", on_delete: :nullify
    add_foreign_key "git_providers", "accounts", column: "account_id"
    add_foreign_key "git_repositories", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "git_repositories", "devops_providers", column: "devops_provider_id", on_delete: :nullify
    add_foreign_key "git_repositories", "git_provider_credentials", column: "git_provider_credential_id", on_delete: :cascade
    add_foreign_key "git_runners", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "git_runners", "git_provider_credentials", column: "git_provider_credential_id", on_delete: :cascade
    add_foreign_key "git_runners", "git_repositories", column: "git_repository_id", on_delete: :cascade
    add_foreign_key "git_webhook_events", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "git_webhook_events", "git_providers", column: "git_provider_id", on_delete: :cascade
    add_foreign_key "git_webhook_events", "git_repositories", column: "git_repository_id", on_delete: :cascade
    add_foreign_key "impersonation_sessions", "users", column: "impersonated_user_id"
    add_foreign_key "impersonation_sessions", "users", column: "impersonator_id"
    add_foreign_key "invitations", "accounts", column: "account_id"
    add_foreign_key "invitations", "users", column: "inviter_id"
    add_foreign_key "jwt_blacklists", "users", column: "user_id", on_delete: :nullify
    add_foreign_key "knowledge_base_article_views", "users", column: "user_id"
    add_foreign_key "knowledge_base_articles", "knowledge_base_categories", column: "category_id", on_delete: :cascade
    add_foreign_key "knowledge_base_articles", "users", column: "author_id"
    add_foreign_key "knowledge_base_articles", "users", column: "last_edited_by_id"
    add_foreign_key "knowledge_base_attachments", "users", column: "uploaded_by_id"
    add_foreign_key "knowledge_base_categories", "knowledge_base_categories", column: "parent_id"
    add_foreign_key "knowledge_base_comments", "knowledge_base_comments", column: "parent_id"
    add_foreign_key "knowledge_base_comments", "users", column: "author_id"
    add_foreign_key "knowledge_base_workflows", "users", column: "user_id"
    add_foreign_key "mcp_servers", "accounts", column: "account_id"
    add_foreign_key "mcp_sessions", "accounts", column: "account_id"
    add_foreign_key "mcp_sessions", "ai_agents", column: "ai_agent_id"
    add_foreign_key "mcp_sessions", "oauth_applications", column: "oauth_application_id"
    add_foreign_key "mcp_sessions", "users", column: "user_id"
    add_foreign_key "mcp_tool_executions", "mcp_tools", column: "mcp_tool_id"
    add_foreign_key "mcp_tool_executions", "users", column: "user_id"
    add_foreign_key "mcp_tools", "mcp_servers", column: "mcp_server_id"
    add_foreign_key "notifications", "accounts", column: "account_id"
    add_foreign_key "notifications", "users", column: "user_id"
    add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
    add_foreign_key "oauth_access_grants", "users", column: "resource_owner_id", on_delete: :cascade
    add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
    add_foreign_key "oauth_access_tokens", "users", column: "resource_owner_id", on_delete: :cascade
    add_foreign_key "pages", "accounts", column: "account_id"
    add_foreign_key "pages", "users", column: "author_id"
    add_foreign_key "password_histories", "users", column: "user_id"
    add_foreign_key "report_requests", "accounts", column: "account_id"
    add_foreign_key "report_requests", "users", column: "requested_by_id"
    add_foreign_key "role_permissions", "roles", column: "role_id"
    add_foreign_key "roles", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "scheduled_reports", "accounts", column: "account_id"
    add_foreign_key "scheduled_reports", "users", column: "created_by_id"
    add_foreign_key "security_secrets", "accounts", column: "account_id"
    add_foreign_key "shared_prompt_templates", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "shared_prompt_templates", "shared_prompt_templates", column: "parent_template_id", on_delete: :nullify
    add_foreign_key "shared_prompt_templates", "users", column: "created_by_id", on_delete: :nullify
    add_foreign_key "task_executions", "scheduled_tasks", column: "scheduled_task_id"
    add_foreign_key "terms_acceptances", "accounts", column: "account_id"
    add_foreign_key "terms_acceptances", "users", column: "user_id"
    add_foreign_key "user_consents", "accounts", column: "account_id"
    add_foreign_key "user_consents", "users", column: "user_id"
    add_foreign_key "user_roles", "roles", column: "role_id"
    add_foreign_key "user_roles", "users", column: "granted_by_id"
    add_foreign_key "user_roles", "users", column: "user_id"
    add_foreign_key "user_tokens", "users", column: "user_id"
    add_foreign_key "users", "accounts", column: "account_id"
    add_foreign_key "webhook_deliveries", "webhook_endpoints", column: "webhook_endpoint_id"
    add_foreign_key "webhook_deliveries", "webhook_events", column: "webhook_event_id"
    add_foreign_key "webhook_delivery_stats", "webhook_endpoints", column: "webhook_endpoint_id"
    add_foreign_key "webhook_endpoints", "accounts", column: "account_id"
    add_foreign_key "webhook_endpoints", "users", column: "created_by_id"
    add_foreign_key "webhook_events", "accounts", column: "account_id"
    add_foreign_key "worker_activities", "workers", column: "worker_id"
    add_foreign_key "worker_roles", "roles", column: "role_id"
    add_foreign_key "worker_roles", "workers", column: "worker_id"
    add_foreign_key "workers", "accounts", column: "account_id"
  end
end
