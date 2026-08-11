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

ActiveRecord::Schema[8.1].define(version: 2026_08_11_140000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "ltree"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"
  enable_extension "pgcrypto"
  enable_extension "vector"

  # UUIDv7 primary-key default function (PG16 shim; native on PG18+ — self-skipping).
  unless select_value("SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'uuidv7')")
    execute("CREATE OR REPLACE FUNCTION uuidv7() RETURNS uuid AS $$ SELECT encode(set_bit(set_bit( overlay(uuid_send(gen_random_uuid()) placing substring(int8send((extract(epoch FROM clock_timestamp()) * 1000)::bigint) FROM 3) FROM 1 FOR 6), 52, 1), 53, 1), 'hex')::uuid; $$ LANGUAGE sql VOLATILE;")
  end

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
    t.index ["account_id", "delegated_user_id"], name: "index_account_delegations_on_account_id_and_delegated_user_id", unique: true
    t.index ["account_id"], name: "index_account_delegations_on_account_id"
    t.index ["delegated_by_id"], name: "index_account_delegations_on_delegated_by_id"
    t.index ["delegated_user_id"], name: "index_account_delegations_on_delegated_user_id"
    t.index ["expires_at"], name: "index_account_delegations_on_expires_at"
    t.index ["revoked_by_id"], name: "index_account_delegations_on_revoked_by_id"
    t.index ["role_id"], name: "index_account_delegations_on_role_id"
    t.index ["status"], name: "index_account_delegations_on_status"
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
    t.index ["account_id", "status"], name: "index_account_git_webhook_configs_on_account_id_and_status"
    t.index ["account_id"], name: "index_account_git_webhook_configs_on_account_id"
    t.index ["created_by_id"], name: "index_account_git_webhook_configs_on_created_by_id"
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
    t.index ["account_id"], name: "index_account_terminations_on_account_id"
    t.index ["cancelled_by_id"], name: "index_account_terminations_on_cancelled_by_id"
    t.index ["data_export_request_id"], name: "index_account_terminations_on_data_export_request_id"
    t.index ["grace_period_ends_at"], name: "index_account_terminations_on_grace_period_ends_at"
    t.index ["processed_by_id"], name: "index_account_terminations_on_processed_by_id"
    t.index ["requested_by_id"], name: "index_account_terminations_on_requested_by_id"
    t.index ["status"], name: "index_account_terminations_on_status"
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
    t.index ["analytics_tier"], name: "index_accounts_on_analytics_tier"
    t.index ["encryption_key_vault_path"], name: "index_accounts_on_encryption_key_vault_path", unique: true, where: "(encryption_key_vault_path IS NOT NULL)"
    t.index ["paypal_customer_id"], name: "index_accounts_on_paypal_customer_id", unique: true, where: "(paypal_customer_id IS NOT NULL)"
    t.index ["status"], name: "index_accounts_on_status"
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
    t.index ["category"], name: "index_admin_settings_on_category"
    t.index ["is_public"], name: "index_admin_settings_on_is_public"
    t.index ["key"], name: "index_admin_settings_on_key", unique: true
    t.index ["setting_type"], name: "index_admin_settings_on_setting_type"
    t.index ["sort_order"], name: "index_admin_settings_on_sort_order"
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
    t.index ["ai_a2a_task_id", "created_at"], name: "index_ai_a2a_task_events_on_ai_a2a_task_id_and_created_at"
    t.index ["ai_a2a_task_id"], name: "index_ai_a2a_task_events_on_ai_a2a_task_id"
    t.index ["event_id"], name: "index_ai_a2a_task_events_on_event_id"
    t.index ["event_type"], name: "index_ai_a2a_task_events_on_event_type"
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
    t.index ["account_id", "status"], name: "index_ai_a2a_tasks_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_a2a_tasks_on_account_id"
    t.index ["chat_message_id"], name: "index_ai_a2a_tasks_on_chat_message_id"
    t.index ["chat_session_id"], name: "index_ai_a2a_tasks_on_chat_session_id"
    t.index ["community_agent_id"], name: "index_ai_a2a_tasks_on_community_agent_id"
    t.index ["container_instance_id"], name: "index_ai_a2a_tasks_on_container_instance_id"
    t.index ["created_at"], name: "index_ai_a2a_tasks_on_created_at"
    t.index ["dag_execution_id", "execution_order"], name: "index_ai_a2a_tasks_on_dag_execution_id_and_execution_order", where: "(dag_execution_id IS NOT NULL)"
    t.index ["dag_execution_id"], name: "index_ai_a2a_tasks_on_dag_execution_id", where: "(dag_execution_id IS NOT NULL)"
    t.index ["federation_partner_id"], name: "index_ai_a2a_tasks_on_federation_partner_id"
    t.index ["federation_task_id"], name: "index_ai_a2a_tasks_on_federation_task_id", where: "(federation_task_id IS NOT NULL)"
    t.index ["from_agent_card_id"], name: "index_ai_a2a_tasks_on_from_agent_card_id"
    t.index ["from_agent_id", "status"], name: "index_ai_a2a_tasks_on_from_agent_id_and_status"
    t.index ["from_agent_id"], name: "index_ai_a2a_tasks_on_from_agent_id"
    t.index ["is_external"], name: "index_ai_a2a_tasks_on_is_external"
    t.index ["parent_task_id"], name: "index_ai_a2a_tasks_on_parent_task_id"
    t.index ["task_id"], name: "index_ai_a2a_tasks_on_task_id", unique: true
    t.index ["to_agent_card_id"], name: "index_ai_a2a_tasks_on_to_agent_card_id"
    t.index ["to_agent_id", "status"], name: "index_ai_a2a_tasks_on_to_agent_id_and_status"
    t.index ["to_agent_id"], name: "index_ai_a2a_tasks_on_to_agent_id"
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
    t.index ["account_id", "status"], name: "index_ai_ab_tests_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_ab_tests_on_account_id"
    t.index ["created_by_id"], name: "index_ai_ab_tests_on_created_by_id"
    t.index ["target_type", "target_id"], name: "index_ai_ab_tests_on_target_type_and_target_id"
    t.index ["test_id"], name: "index_ai_ab_tests_on_test_id", unique: true
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
    t.index ["account_id"], name: "index_ai_agent_budgets_on_account_id"
    t.index ["agent_id"], name: "index_ai_agent_budgets_on_agent_id"
    t.index ["parent_budget_id"], name: "index_ai_agent_budgets_on_parent_budget_id"
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
    t.index ["account_id", "name"], name: "index_ai_agent_cards_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_ai_agent_cards_on_account_id"
    t.index ["ai_agent_id"], name: "index_ai_agent_cards_on_ai_agent_id"
    t.index ["capabilities"], name: "index_ai_agent_cards_on_capabilities", using: :gin
    t.index ["protocol_version"], name: "index_ai_agent_cards_on_protocol_version"
    t.index ["status"], name: "index_ai_agent_cards_on_status"
    t.index ["tags"], name: "index_ai_agent_cards_on_tags", using: :gin
    t.index ["visibility"], name: "index_ai_agent_cards_on_visibility"
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
    t.index ["account_id", "connection_type"], name: "index_ai_agent_connections_on_account_id_and_connection_type"
    t.index ["account_id"], name: "index_ai_agent_connections_on_account_id"
    t.index ["source_type", "source_id"], name: "index_ai_agent_connections_on_source_type_and_source_id"
    t.index ["target_type", "target_id"], name: "index_ai_agent_connections_on_target_type_and_target_id"
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
    t.index ["account_id", "status"], name: "index_ai_agent_escalations_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_agent_escalations_on_account_id"
    t.index ["ai_agent_id"], name: "index_ai_agent_escalations_on_ai_agent_id"
    t.index ["escalated_to_user_id"], name: "index_ai_agent_escalations_on_escalated_to_user_id"
    t.index ["next_escalation_at"], name: "idx_ai_agent_escalations_due", where: "((status)::text = ANY (ARRAY[('open'::character varying)::text, ('acknowledged'::character varying)::text, ('in_progress'::character varying)::text]))"
    t.index ["severity"], name: "index_ai_agent_escalations_on_severity"
    t.index ["status"], name: "index_ai_agent_escalations_on_status"
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
    t.index ["account_id", "status"], name: "index_ai_agent_executions_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_agent_executions_on_account_id"
    t.index ["ai_agent_id", "status"], name: "index_ai_agent_executions_on_ai_agent_id_and_status"
    t.index ["ai_agent_id"], name: "index_ai_agent_executions_on_ai_agent_id"
    t.index ["ai_provider_id"], name: "index_ai_agent_executions_on_ai_provider_id"
    t.index ["completed_at"], name: "index_ai_agent_executions_on_completed_at"
    t.index ["execution_id"], name: "index_ai_agent_executions_on_execution_id", unique: true
    t.index ["parent_execution_id"], name: "index_ai_agent_executions_on_parent_execution_id"
    t.index ["started_at"], name: "index_ai_agent_executions_on_started_at"
    t.index ["status"], name: "index_ai_agent_executions_on_status"
    t.index ["user_id"], name: "index_ai_agent_executions_on_user_id"
    t.index ["webhook_status"], name: "index_ai_agent_executions_on_webhook_status"
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
    t.index ["account_id"], name: "index_ai_agent_feedbacks_on_account_id"
    t.index ["ai_agent_id", "applied_to_trust"], name: "index_ai_agent_feedbacks_on_ai_agent_id_and_applied_to_trust"
    t.index ["ai_agent_id"], name: "index_ai_agent_feedbacks_on_ai_agent_id"
    t.index ["context_type", "context_id"], name: "index_ai_agent_feedbacks_on_context_type_and_context_id"
    t.index ["feedback_type"], name: "index_ai_agent_feedbacks_on_feedback_type"
    t.index ["user_id"], name: "index_ai_agent_feedbacks_on_user_id"
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
    t.index ["account_id", "goal_type"], name: "index_ai_agent_goals_on_account_id_and_goal_type"
    t.index ["account_id"], name: "index_ai_agent_goals_on_account_id"
    t.index ["ai_agent_id", "status", "priority"], name: "index_ai_agent_goals_on_ai_agent_id_and_status_and_priority"
    t.index ["ai_agent_id", "status"], name: "index_ai_agent_goals_on_ai_agent_id_and_status"
    t.index ["ai_agent_id"], name: "index_ai_agent_goals_on_ai_agent_id"
    t.index ["created_by_type", "created_by_id"], name: "index_ai_agent_goals_on_created_by_type_and_created_by_id"
    t.index ["parent_goal_id"], name: "index_ai_agent_goals_on_parent_goal_id"
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
    t.index ["account_id"], name: "index_ai_agent_identities_on_account_id"
    t.index ["agent_id", "status"], name: "index_ai_agent_identities_on_agent_id_and_status"
    t.index ["agent_id"], name: "index_ai_agent_identities_on_agent_id"
    t.index ["key_fingerprint"], name: "index_ai_agent_identities_on_key_fingerprint", unique: true
    t.index ["status"], name: "index_ai_agent_identities_on_status"
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
    t.index ["account_id", "agent_template_id"], name: "idx_on_account_id_agent_template_id_dab9ad20b0", unique: true
    t.index ["account_id"], name: "index_ai_agent_installations_on_account_id"
    t.index ["agent_template_id"], name: "index_ai_agent_installations_on_agent_template_id"
    t.index ["installed_agent_id"], name: "index_ai_agent_installations_on_installed_agent_id"
    t.index ["installed_by_id"], name: "index_ai_agent_installations_on_installed_by_id"
    t.index ["license_expires_at"], name: "index_ai_agent_installations_on_license_expires_at"
    t.index ["status"], name: "index_ai_agent_installations_on_status"
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
    t.index ["account_id"], name: "index_ai_agent_lineages_on_account_id"
    t.index ["child_agent_id"], name: "index_ai_agent_lineages_on_child_agent_id"
    t.index ["parent_agent_id", "child_agent_id"], name: "index_ai_agent_lineages_on_parent_agent_id_and_child_agent_id", unique: true
    t.index ["parent_agent_id"], name: "index_ai_agent_lineages_on_parent_agent_id"
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
    t.index ["account_id", "ai_provider_id", "model", "agent_type"], name: "idx_on_account_id_ai_provider_id_model_agent_type_1a2c889554", unique: true
    t.index ["account_id"], name: "index_ai_agent_model_performances_on_account_id"
    t.index ["ai_provider_id"], name: "index_ai_agent_model_performances_on_ai_provider_id"
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
    t.index ["account_id", "severity"], name: "index_ai_agent_observations_on_account_id_and_severity"
    t.index ["account_id"], name: "index_ai_agent_observations_on_account_id"
    t.index ["ai_agent_id", "processed"], name: "index_ai_agent_observations_on_ai_agent_id_and_processed"
    t.index ["ai_agent_id", "sensor_type"], name: "index_ai_agent_observations_on_ai_agent_id_and_sensor_type"
    t.index ["ai_agent_id"], name: "index_ai_agent_observations_on_ai_agent_id"
    t.index ["expires_at"], name: "index_ai_agent_observations_on_expires_at", where: "(expires_at IS NOT NULL)"
    t.index ["goal_id"], name: "index_ai_agent_observations_on_goal_id"
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
    t.index ["account_id", "policy_name"], name: "idx_on_account_id_policy_name_3fe605a85f", unique: true
    t.index ["account_id"], name: "index_ai_agent_privilege_policies_on_account_id"
    t.index ["agent_id"], name: "index_ai_agent_privilege_policies_on_agent_id"
    t.index ["policy_type"], name: "index_ai_agent_privilege_policies_on_policy_type"
    t.index ["trust_tier"], name: "index_ai_agent_privilege_policies_on_trust_tier"
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
    t.index ["account_id", "status"], name: "index_ai_agent_proposals_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_agent_proposals_on_account_id"
    t.index ["ai_agent_id"], name: "index_ai_agent_proposals_on_ai_agent_id"
    t.index ["conversation_id"], name: "index_ai_agent_proposals_on_conversation_id"
    t.index ["proposal_type"], name: "index_ai_agent_proposals_on_proposal_type"
    t.index ["review_deadline"], name: "index_ai_agent_proposals_on_review_deadline", where: "((status)::text = 'pending_review'::text)"
    t.index ["reviewed_by_id"], name: "index_ai_agent_proposals_on_reviewed_by_id"
    t.index ["status"], name: "index_ai_agent_proposals_on_status"
    t.index ["target_user_id"], name: "index_ai_agent_proposals_on_target_user_id"
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
    t.index ["account_id"], name: "index_ai_agent_reviews_on_account_id"
    t.index ["agent_template_id", "account_id"], name: "index_ai_agent_reviews_on_agent_template_id_and_account_id", unique: true
    t.index ["agent_template_id", "status", "rating"], name: "idx_on_agent_template_id_status_rating_a158179e68"
    t.index ["agent_template_id"], name: "index_ai_agent_reviews_on_agent_template_id"
    t.index ["installation_id"], name: "index_ai_agent_reviews_on_installation_id"
    t.index ["status"], name: "index_ai_agent_reviews_on_status"
    t.index ["user_id"], name: "index_ai_agent_reviews_on_user_id"
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
    t.index ["account_id"], name: "index_ai_agent_short_term_memories_on_account_id"
    t.index ["agent_id", "session_id", "memory_key"], name: "idx_on_agent_id_session_id_memory_key_391116a084", unique: true
    t.index ["agent_id"], name: "index_ai_agent_short_term_memories_on_agent_id"
    t.index ["expires_at"], name: "index_ai_agent_short_term_memories_on_expires_at"
    t.index ["last_event_processed_at"], name: "index_ai_agent_short_term_memories_on_last_event_processed_at"
  end

  create_table "ai_agent_skills", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "ai_agent_id", null: false
    t.uuid "ai_skill_id", null: false
    t.datetime "created_at", null: false
    t.boolean "is_active", default: true, null: false
    t.integer "priority", default: 0
    t.datetime "updated_at", null: false
    t.index ["ai_agent_id", "ai_skill_id"], name: "index_ai_agent_skills_on_ai_agent_id_and_ai_skill_id", unique: true
    t.index ["ai_agent_id"], name: "index_ai_agent_skills_on_ai_agent_id"
    t.index ["ai_skill_id"], name: "index_ai_agent_skills_on_ai_skill_id"
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
    t.index ["ai_agent_id"], name: "index_ai_agent_team_members_on_ai_agent_id"
    t.index ["ai_agent_team_id", "ai_agent_id"], name: "idx_on_ai_agent_team_id_ai_agent_id_e9c710c86f", unique: true
    t.index ["ai_agent_team_id", "is_lead"], name: "index_ai_agent_team_members_on_ai_agent_team_id_and_is_lead"
    t.index ["ai_agent_team_id", "priority_order"], name: "idx_on_ai_agent_team_id_priority_order_d0e65ce3fe"
    t.index ["ai_agent_team_id"], name: "index_ai_agent_team_members_on_ai_agent_team_id"
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
    t.index ["account_id", "name"], name: "index_ai_agent_teams_on_account_id_and_name", unique: true
    t.index ["account_id", "status"], name: "index_ai_agent_teams_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_agent_teams_on_account_id"
    t.index ["team_topology"], name: "index_ai_agent_teams_on_team_topology"
    t.index ["team_type"], name: "index_ai_agent_teams_on_team_type"
    t.index ["template_id"], name: "index_ai_agent_teams_on_template_id"
    t.check_constraint "communication_pattern::text = ANY (ARRAY['hub_spoke'::character varying::text, 'peer_to_peer'::character varying::text, 'broadcast'::character varying::text, 'sequential'::character varying::text, 'event_driven'::character varying::text])", name: "check_communication_pattern"
    t.check_constraint "coordination_strategy::text = ANY (ARRAY['manager_led'::character varying::text, 'consensus'::character varying::text, 'auction'::character varying::text, 'round_robin'::character varying::text, 'priority_based'::character varying::text])", name: "check_coordination_strategy"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'archived'::character varying::text])", name: "ai_agent_teams_status_check"
    t.check_constraint "team_topology::text = ANY (ARRAY['hierarchical'::character varying::text, 'flat'::character varying::text, 'mesh'::character varying::text, 'pipeline'::character varying::text, 'hybrid'::character varying::text])", name: "check_team_topology_enum"
    t.check_constraint "team_type::text = ANY (ARRAY['hierarchical'::character varying::text, 'mesh'::character varying::text, 'sequential'::character varying::text, 'parallel'::character varying::text, 'workspace'::character varying::text])", name: "ai_agent_teams_team_type_check"
  end

  create_table "ai_agent_templates", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.integer "active_installations", default: 0
    t.jsonb "agent_config", default: {}
    t.float "average_rating"
    t.string "category"
    t.text "changelog"
    t.uuid "cloned_from_id"
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
    t.jsonb "model_requirements", default: {}, null: false
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
    t.string "source_key", limit: 255
    t.jsonb "source_snapshot", default: {}, null: false
    t.string "source_version"
    t.string "status", default: "draft", null: false
    t.jsonb "supported_providers", default: []
    t.jsonb "tags", default: []
    t.datetime "updated_at", null: false
    t.string "version", default: "1.0.0", null: false
    t.string "vertical"
    t.string "visibility", default: "private", null: false
    t.index ["account_id"], name: "index_ai_agent_templates_on_account_id"
    t.index ["average_rating", "installation_count"], name: "idx_on_average_rating_installation_count_b612451228"
    t.index ["category"], name: "index_ai_agent_templates_on_category"
    t.index ["cloned_from_id"], name: "index_ai_agent_templates_on_cloned_from_id"
    t.index ["is_featured"], name: "index_ai_agent_templates_on_is_featured"
    t.index ["pricing_type"], name: "index_ai_agent_templates_on_pricing_type"
    t.index ["publisher_id"], name: "index_ai_agent_templates_on_publisher_id"
    t.index ["slug"], name: "index_ai_agent_templates_on_slug", unique: true
    t.index ["source_agent_id"], name: "index_ai_agent_templates_on_source_agent_id"
    t.index ["source_key"], name: "index_ai_agent_templates_on_source_key"
    t.index ["status", "visibility"], name: "index_ai_agent_templates_on_status_and_visibility"
    t.index ["vertical"], name: "index_ai_agent_templates_on_vertical"
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
    t.index ["account_id"], name: "index_ai_agent_trust_scores_on_account_id"
    t.index ["agent_id"], name: "index_ai_agent_trust_scores_on_agent_id", unique: true
  end

  create_table "ai_agents", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.string "agent_type", limit: 50, null: false
    t.uuid "ai_provider_id", null: false
    t.jsonb "autonomy_config", default: {}
    t.uuid "cloned_from_id"
    t.jsonb "conversation_profile", default: {}, null: false
    t.datetime "created_at", null: false
    t.uuid "creator_id", null: false
    t.text "description"
    t.jsonb "execution_stats", default: {}
    t.jsonb "governance_scope", default: {}
    t.boolean "is_concierge", default: false, null: false
    t.boolean "is_governance", default: false, null: false
    t.boolean "is_public", default: false
    t.boolean "is_system", default: false, null: false
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
    t.string "source_key", limit: 255
    t.jsonb "source_snapshot", default: {}, null: false
    t.string "source_version"
    t.string "status", default: "active", null: false
    t.string "termination_policy", default: "graceful"
    t.string "trust_level", default: "supervised"
    t.datetime "updated_at", null: false
    t.string "version", limit: 20, default: "1.0.0", null: false
    t.index ["account_id", "is_concierge"], name: "idx_ai_agents_concierge", where: "(is_concierge = true)"
    t.index ["account_id", "name"], name: "index_ai_agents_on_account_id_and_name"
    t.index ["account_id", "slug"], name: "index_ai_agents_on_account_id_and_slug", unique: true, where: "(account_id IS NOT NULL)"
    t.index ["account_id", "status"], name: "index_ai_agents_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_agents_on_account_id"
    t.index ["agent_type"], name: "index_ai_agents_on_agent_type"
    t.index ["ai_provider_id"], name: "index_ai_agents_on_ai_provider_id"
    t.index ["cloned_from_id"], name: "index_ai_agents_on_cloned_from_id"
    t.index ["creator_id"], name: "index_ai_agents_on_creator_id"
    t.index ["is_governance"], name: "idx_ai_agents_governance", where: "(is_governance = true)"
    t.index ["is_public"], name: "index_ai_agents_on_is_public"
    t.index ["is_system"], name: "index_ai_agents_on_is_system"
    t.index ["last_executed_at"], name: "index_ai_agents_on_last_executed_at"
    t.index ["mcp_registered_at"], name: "index_ai_agents_on_mcp_registered_at"
    t.index ["mcp_tool_manifest"], name: "index_ai_agents_on_mcp_tool_manifest", using: :gin
    t.index ["parent_agent_id"], name: "index_ai_agents_on_parent_agent_id"
    t.index ["slug"], name: "index_ai_agents_on_slug_global", unique: true, where: "(account_id IS NULL)"
    t.index ["source_key"], name: "index_ai_agents_on_source_key"
    t.index ["status"], name: "index_ai_agents_on_status"
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
    t.index ["account_id"], name: "index_ai_agui_events_on_account_id"
    t.index ["event_type"], name: "index_ai_agui_events_on_event_type"
    t.index ["session_id", "sequence_number"], name: "index_ai_agui_events_on_session_id_and_sequence_number", unique: true
    t.index ["session_id"], name: "index_ai_agui_events_on_session_id"
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
    t.index ["account_id"], name: "index_ai_agui_sessions_on_account_id"
    t.index ["expires_at"], name: "index_ai_agui_sessions_on_expires_at"
    t.index ["status"], name: "index_ai_agui_sessions_on_status"
    t.index ["thread_id"], name: "index_ai_agui_sessions_on_thread_id"
    t.index ["user_id"], name: "index_ai_agui_sessions_on_user_id"
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
    t.index ["account_id", "name"], name: "index_ai_approval_chains_on_account_id_and_name", unique: true
    t.index ["account_id", "status"], name: "index_ai_approval_chains_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_approval_chains_on_account_id"
    t.index ["created_by_id"], name: "index_ai_approval_chains_on_created_by_id"
    t.index ["trigger_type"], name: "index_ai_approval_chains_on_trigger_type"
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
    t.index ["approval_request_id", "step_number"], name: "idx_on_approval_request_id_step_number_4d54accc2f"
    t.index ["approval_request_id"], name: "index_ai_approval_decisions_on_approval_request_id"
    t.index ["approver_id", "created_at"], name: "index_ai_approval_decisions_on_approver_id_and_created_at"
    t.index ["approver_id"], name: "index_ai_approval_decisions_on_approver_id"
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
    t.index ["account_id", "status"], name: "index_ai_approval_requests_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_approval_requests_on_account_id"
    t.index ["approval_chain_id", "created_at"], name: "index_ai_approval_requests_on_approval_chain_id_and_created_at"
    t.index ["approval_chain_id"], name: "index_ai_approval_requests_on_approval_chain_id"
    t.index ["expires_at"], name: "index_ai_approval_requests_on_expires_at"
    t.index ["request_id"], name: "index_ai_approval_requests_on_request_id", unique: true
    t.index ["requested_by_id"], name: "index_ai_approval_requests_on_requested_by_id"
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
    t.index ["account_id", "agent_id"], name: "index_ai_behavioral_fingerprints_on_account_id_and_agent_id"
    t.index ["account_id"], name: "index_ai_behavioral_fingerprints_on_account_id"
    t.index ["agent_id", "metric_name"], name: "index_ai_behavioral_fingerprints_on_agent_id_and_metric_name", unique: true
    t.index ["agent_id"], name: "index_ai_behavioral_fingerprints_on_agent_id"
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
    t.index ["account_id"], name: "index_ai_budget_transactions_on_account_id"
    t.index ["ai_agent_budget_id"], name: "index_ai_budget_transactions_on_ai_agent_budget_id"
    t.index ["ai_agent_execution_id"], name: "index_ai_budget_transactions_on_ai_agent_execution_id"
    t.index ["created_at"], name: "index_ai_budget_transactions_on_created_at"
    t.index ["transaction_type"], name: "index_ai_budget_transactions_on_transaction_type"
  end

  create_table "ai_campaign_decisions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "campaign_id", null: false
    t.datetime "created_at", null: false
    t.string "decision_type", null: false
    t.jsonb "metadata", default: {}, null: false
    t.uuid "ralph_task_id"
    t.text "rationale"
    t.string "title"
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["campaign_id", "created_at"], name: "index_ai_campaign_decisions_on_campaign_id_and_created_at"
    t.index ["ralph_task_id"], name: "index_ai_campaign_decisions_on_ralph_task_id"
    t.index ["user_id"], name: "index_ai_campaign_decisions_on_user_id"
  end

  create_table "ai_campaign_lands", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "base_sha"
    t.uuid "campaign_id"
    t.datetime "completed_at"
    t.jsonb "conflict_files", default: [], null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.uuid "merge_operation_id"
    t.string "merged_sha"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "parked_at"
    t.text "parked_reason"
    t.uuid "post_ci_pipeline_id"
    t.uuid "pre_ci_pipeline_id"
    t.integer "priority", default: 0, null: false
    t.datetime "queued_at"
    t.string "source_branch", null: false
    t.uuid "source_id"
    t.string "source_type"
    t.string "staged_sha"
    t.string "staging_branch"
    t.datetime "started_at"
    t.string "status", default: "pending_approval", null: false
    t.string "target_branch", default: "develop", null: false
    t.datetime "updated_at", null: false
    t.uuid "worktree_session_id"
    t.index ["account_id", "status"], name: "index_ai_campaign_lands_on_account_id_and_status"
    t.index ["campaign_id"], name: "index_ai_campaign_lands_on_campaign_id"
    t.index ["source_type", "source_id"], name: "index_ai_campaign_lands_on_source"
    t.index ["target_branch", "status"], name: "index_ai_campaign_lands_on_target_branch_and_status"
  end

  create_table "ai_campaign_proposals", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "decision_authority", default: "trusted", null: false
    t.jsonb "evidence", default: {}, null: false
    t.string "fingerprint", null: false
    t.text "objective", null: false
    t.text "rejection_reason"
    t.datetime "reviewed_at"
    t.uuid "reviewed_by_id"
    t.string "scope"
    t.string "source", default: "manual", null: false
    t.uuid "spawned_campaign_id"
    t.string "status", default: "proposed", null: false
    t.string "suggested_driver"
    t.string "suggested_workload", default: "improvement-campaign", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "fingerprint"], name: "index_ai_campaign_proposals_on_account_id_and_fingerprint", unique: true
    t.index ["account_id", "status"], name: "index_ai_campaign_proposals_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_campaign_proposals_on_account_id"
    t.index ["reviewed_by_id"], name: "index_ai_campaign_proposals_on_reviewed_by_id"
    t.index ["spawned_campaign_id"], name: "index_ai_campaign_proposals_on_spawned_campaign_id"
  end

  create_table "ai_campaigns", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.integer "blocked_tasks", default: 0, null: false
    t.datetime "completed_at"
    t.integer "completed_tasks", default: 0, null: false
    t.text "completion_summary"
    t.jsonb "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.string "decision_authority", default: "supervised", null: false
    t.text "description"
    t.datetime "driver_lease_expires_at"
    t.string "driver_lease_holder"
    t.integer "failed_tasks", default: 0, null: false
    t.datetime "last_activity_at"
    t.integer "loop_count", default: 0, null: false
    t.string "name", null: false
    t.integer "open_questions", default: 0, null: false
    t.datetime "paused_at"
    t.string "paused_reason"
    t.datetime "started_at"
    t.string "status", default: "created", null: false
    t.jsonb "stop_conditions", default: {}, null: false
    t.integer "total_tasks", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_ai_campaigns_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_campaigns_on_account_id"
    t.index ["created_by_id"], name: "index_ai_campaigns_on_created_by_id"
    t.index ["last_activity_at"], name: "index_ai_campaigns_on_last_activity_at"
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
    t.index ["account_id", "state"], name: "index_ai_circuit_breakers_on_account_id_and_state"
    t.index ["account_id"], name: "index_ai_circuit_breakers_on_account_id"
    t.index ["agent_id", "action_type"], name: "index_ai_circuit_breakers_on_agent_id_and_action_type", unique: true
    t.index ["agent_id"], name: "index_ai_circuit_breakers_on_agent_id"
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
    t.index ["account_id"], name: "index_ai_code_factory_evidence_manifests_on_account_id"
    t.index ["review_state_id"], name: "index_ai_code_factory_evidence_manifests_on_review_state_id"
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
    t.index ["account_id", "status"], name: "index_ai_code_factory_harness_gaps_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_code_factory_harness_gaps_on_account_id"
    t.index ["incident_id"], name: "index_ai_code_factory_harness_gaps_on_incident_id"
    t.index ["risk_contract_id"], name: "index_ai_code_factory_harness_gaps_on_risk_contract_id"
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
    t.index ["account_id", "status"], name: "index_ai_code_factory_review_states_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_code_factory_review_states_on_account_id"
    t.index ["mission_id"], name: "index_ai_code_factory_review_states_on_mission_id"
    t.index ["repository_id", "pr_number", "head_sha"], name: "idx_on_repository_id_pr_number_head_sha_22d0e46362", unique: true
    t.index ["repository_id"], name: "index_ai_code_factory_review_states_on_repository_id"
    t.index ["risk_contract_id"], name: "index_ai_code_factory_review_states_on_risk_contract_id"
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
    t.index ["account_id", "repository_id", "status"], name: "idx_on_account_id_repository_id_status_150fddd83c"
    t.index ["account_id"], name: "index_ai_code_factory_risk_contracts_on_account_id"
    t.index ["created_by_id"], name: "index_ai_code_factory_risk_contracts_on_created_by_id"
    t.index ["repository_id"], name: "index_ai_code_factory_risk_contracts_on_repository_id"
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
    t.index ["account_id"], name: "index_ai_code_review_comments_on_account_id"
    t.index ["agent_id"], name: "index_ai_code_review_comments_on_agent_id"
    t.index ["task_review_id", "file_path"], name: "index_ai_code_review_comments_on_task_review_id_and_file_path"
    t.index ["task_review_id"], name: "index_ai_code_review_comments_on_task_review_id"
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
    t.index ["account_id", "created_at"], name: "index_ai_code_reviews_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_ai_code_reviews_on_account_id"
    t.index ["pipeline_execution_id"], name: "index_ai_code_reviews_on_pipeline_execution_id"
    t.index ["repository_id", "pull_request_number"], name: "index_ai_code_reviews_on_repository_id_and_pull_request_number"
    t.index ["review_id"], name: "index_ai_code_reviews_on_review_id", unique: true
    t.index ["status"], name: "index_ai_code_reviews_on_status"
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
    t.index ["account_id", "indicator_type"], name: "index_ai_collusion_indicators_on_account_id_and_indicator_type"
    t.index ["account_id"], name: "index_ai_collusion_indicators_on_account_id"
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
    t.index ["account_id", "occurred_at"], name: "idx_on_account_id_occurred_at_34fa669db4"
    t.index ["account_id"], name: "index_ai_compliance_audit_entries_on_account_id"
    t.index ["action_type"], name: "index_ai_compliance_audit_entries_on_action_type"
    t.index ["entry_id"], name: "index_ai_compliance_audit_entries_on_entry_id", unique: true
    t.index ["outcome"], name: "index_ai_compliance_audit_entries_on_outcome"
    t.index ["resource_type", "resource_id"], name: "idx_on_resource_type_resource_id_58a603956a"
    t.index ["user_id"], name: "index_ai_compliance_audit_entries_on_user_id"
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
    t.index ["account_id", "name"], name: "index_ai_compliance_policies_on_account_id_and_name", unique: true
    t.index ["account_id", "status"], name: "index_ai_compliance_policies_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_compliance_policies_on_account_id"
    t.index ["created_by_id"], name: "index_ai_compliance_policies_on_created_by_id"
    t.index ["enforcement_level"], name: "index_ai_compliance_policies_on_enforcement_level"
    t.index ["is_system"], name: "index_ai_compliance_policies_on_is_system"
    t.index ["policy_type"], name: "index_ai_compliance_policies_on_policy_type"
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
    t.index ["account_id", "report_type"], name: "index_ai_compliance_reports_on_account_id_and_report_type"
    t.index ["account_id"], name: "index_ai_compliance_reports_on_account_id"
    t.index ["generated_at"], name: "index_ai_compliance_reports_on_generated_at"
    t.index ["generated_by_id"], name: "index_ai_compliance_reports_on_generated_by_id"
    t.index ["report_id"], name: "index_ai_compliance_reports_on_report_id", unique: true
    t.index ["status"], name: "index_ai_compliance_reports_on_status"
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
    t.index ["account_id", "category"], name: "index_ai_compound_learnings_on_account_id_and_category"
    t.index ["account_id", "scope"], name: "index_ai_compound_learnings_on_account_id_and_scope"
    t.index ["account_id", "status"], name: "index_ai_compound_learnings_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_compound_learnings_on_account_id"
    t.index ["ai_agent_team_id", "category"], name: "index_ai_compound_learnings_on_ai_agent_team_id_and_category"
    t.index ["ai_agent_team_id"], name: "index_ai_compound_learnings_on_ai_agent_team_id"
    t.index ["applicable_domains"], name: "index_ai_compound_learnings_on_applicable_domains", using: :gin
    t.index ["disproven_by_id"], name: "index_ai_compound_learnings_on_disproven_by_id"
    t.index ["effectiveness_score"], name: "index_ai_compound_learnings_on_effectiveness_score"
    t.index ["embedding"], name: "idx_compound_learnings_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["git_repository_id"], name: "index_ai_compound_learnings_on_git_repository_id"
    t.index ["importance_score"], name: "index_ai_compound_learnings_on_importance_score"
    t.index ["last_event_processed_at"], name: "index_ai_compound_learnings_on_last_event_processed_at"
    t.index ["source_agent_id"], name: "index_ai_compound_learnings_on_source_agent_id"
    t.index ["source_execution_id"], name: "index_ai_compound_learnings_on_source_execution_id"
    t.index ["superseded_by_id"], name: "index_ai_compound_learnings_on_superseded_by_id"
    t.index ["tags"], name: "index_ai_compound_learnings_on_tags", using: :gin
    t.index ["verified_by_id"], name: "index_ai_compound_learnings_on_verified_by_id"
  end

  create_table "ai_content_drafts", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_data_source_id", null: false
    t.uuid "ai_knowledge_base_id"
    t.jsonb "brand_voice", default: {}, null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.jsonb "metadata", default: {}, null: false
    t.uuid "requesting_agent_id"
    t.jsonb "segments", default: [], null: false
    t.string "source_type", null: false
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_ai_content_drafts_on_account_id"
    t.index ["ai_data_source_id"], name: "index_ai_content_drafts_on_ai_data_source_id"
    t.index ["ai_knowledge_base_id"], name: "index_ai_content_drafts_on_ai_knowledge_base_id"
    t.index ["requesting_agent_id"], name: "index_ai_content_drafts_on_requesting_agent_id"
    t.index ["status"], name: "index_ai_content_drafts_on_status"
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
    t.index ["access_type"], name: "index_ai_context_access_logs_on_access_type"
    t.index ["account_id", "created_at"], name: "index_ai_context_access_logs_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_ai_context_access_logs_on_account_id"
    t.index ["action"], name: "index_ai_context_access_logs_on_action"
    t.index ["ai_agent_id"], name: "index_ai_context_access_logs_on_ai_agent_id"
    t.index ["ai_context_entry_id"], name: "index_ai_context_access_logs_on_ai_context_entry_id"
    t.index ["ai_persistent_context_id", "action"], name: "idx_on_ai_persistent_context_id_action_34d9569536"
    t.index ["ai_persistent_context_id"], name: "index_ai_context_access_logs_on_ai_persistent_context_id"
    t.index ["success"], name: "index_ai_context_access_logs_on_success"
    t.index ["user_id"], name: "index_ai_context_access_logs_on_user_id"
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
    t.index ["ai_agent_id"], name: "index_ai_context_entries_on_ai_agent_id"
    t.index ["ai_persistent_context_id", "entry_key"], name: "idx_entries_context_key_active", unique: true, where: "(archived_at IS NULL)"
    t.index ["ai_persistent_context_id"], name: "index_ai_context_entries_on_ai_persistent_context_id"
    t.index ["archived_at"], name: "index_ai_context_entries_on_archived_at"
    t.index ["confidence_score"], name: "index_ai_context_entries_on_confidence_score"
    t.index ["context_tags"], name: "index_ai_context_entries_on_context_tags", using: :gin
    t.index ["created_by_user_id"], name: "index_ai_context_entries_on_created_by_user_id"
    t.index ["embedding"], name: "idx_context_entries_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["entry_type"], name: "index_ai_context_entries_on_entry_type"
    t.index ["expires_at"], name: "index_ai_context_entries_on_expires_at"
    t.index ["importance_score"], name: "index_ai_context_entries_on_importance_score"
    t.index ["memory_type"], name: "index_ai_context_entries_on_memory_type"
    t.index ["outcome_success"], name: "index_ai_context_entries_on_outcome_success"
    t.index ["previous_version_id"], name: "index_ai_context_entries_on_previous_version_id"
    t.index ["source_type"], name: "index_ai_context_entries_on_source_type"
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
    t.index ["account_id", "status"], name: "index_ai_conversations_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_conversations_on_account_id"
    t.index ["agent_team_id", "conversation_type"], name: "index_ai_conversations_on_team_type", where: "((conversation_type)::text = 'team'::text)"
    t.index ["agent_team_id"], name: "index_ai_conversations_on_agent_team_id"
    t.index ["ai_agent_id"], name: "index_ai_conversations_on_ai_agent_id"
    t.index ["ai_provider_id"], name: "index_ai_conversations_on_ai_provider_id"
    t.index ["conversation_id"], name: "index_ai_conversations_on_conversation_id", unique: true
    t.index ["last_activity_at"], name: "index_ai_conversations_on_last_activity_at"
    t.index ["participants"], name: "index_ai_conversations_on_participants", using: :gin
    t.index ["pinned_at"], name: "index_ai_conversations_on_pinned_at", where: "(pinned_at IS NOT NULL)"
    t.index ["status"], name: "index_ai_conversations_on_status"
    t.index ["tags"], name: "index_ai_conversations_on_tags", using: :gin
    t.index ["user_id", "status"], name: "index_ai_conversations_on_user_id_and_status"
    t.index ["user_id"], name: "index_ai_conversations_on_user_id"
    t.index ["websocket_channel"], name: "index_ai_conversations_on_websocket_channel"
    t.index ["websocket_session_id"], name: "index_ai_conversations_on_websocket_session_id"
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
    t.index ["account_id", "attribution_date"], name: "index_ai_cost_attributions_on_account_id_and_attribution_date"
    t.index ["account_id"], name: "index_ai_cost_attributions_on_account_id"
    t.index ["attribution_date"], name: "index_ai_cost_attributions_on_attribution_date"
    t.index ["cost_category", "attribution_date"], name: "idx_on_cost_category_attribution_date_66ad966491"
    t.index ["provider_id"], name: "index_ai_cost_attributions_on_provider_id"
    t.index ["roi_metric_id"], name: "index_ai_cost_attributions_on_roi_metric_id"
    t.index ["source_type", "source_id"], name: "index_ai_cost_attributions_on_source_type_and_source_id"
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
    t.index ["account_id", "optimization_type"], name: "idx_on_account_id_optimization_type_6c8d08f8d9"
    t.index ["account_id", "status"], name: "index_ai_cost_optimization_logs_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_cost_optimization_logs_on_account_id"
    t.index ["created_at"], name: "index_ai_cost_optimization_logs_on_created_at"
    t.index ["resource_type", "resource_id"], name: "idx_on_resource_type_resource_id_d5df61df92"
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
    t.index ["account_id", "status"], name: "index_ai_dag_executions_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_dag_executions_on_account_id"
    t.index ["status"], name: "index_ai_dag_executions_on_status"
    t.index ["triggered_by_id"], name: "index_ai_dag_executions_on_triggered_by_id"
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
    t.index ["account_id", "name"], name: "index_ai_data_classifications_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_ai_data_classifications_on_account_id"
    t.index ["classification_level"], name: "index_ai_data_classifications_on_classification_level"
    t.index ["classified_by_id"], name: "index_ai_data_classifications_on_classified_by_id"
    t.index ["is_system"], name: "index_ai_data_classifications_on_is_system"
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
    t.index ["account_id", "connector_type"], name: "index_ai_data_connectors_on_account_id_and_connector_type"
    t.index ["account_id"], name: "index_ai_data_connectors_on_account_id"
    t.index ["created_by_id"], name: "index_ai_data_connectors_on_created_by_id"
    t.index ["knowledge_base_id", "status"], name: "index_ai_data_connectors_on_knowledge_base_id_and_status"
    t.index ["knowledge_base_id"], name: "index_ai_data_connectors_on_knowledge_base_id"
    t.index ["next_sync_at"], name: "index_ai_data_connectors_on_next_sync_at"
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
    t.index ["account_id", "created_at"], name: "index_ai_data_detections_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_ai_data_detections_on_account_id"
    t.index ["action_taken"], name: "index_ai_data_detections_on_action_taken"
    t.index ["classification_id", "created_at"], name: "index_ai_data_detections_on_classification_id_and_created_at"
    t.index ["classification_id"], name: "index_ai_data_detections_on_classification_id"
    t.index ["detection_id"], name: "index_ai_data_detections_on_detection_id", unique: true
    t.index ["source_type"], name: "index_ai_data_detections_on_source_type"
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
    t.index ["account_id"], name: "index_ai_data_source_config_versions_on_account_id"
    t.index ["ai_data_source_id", "version"], name: "idx_on_ai_data_source_id_version_d26c50fe04", unique: true
  end

  create_table "ai_data_source_credentials", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "access_token_expires_at"
    t.uuid "account_id", null: false
    t.uuid "ai_data_source_id", null: false
    t.integer "consecutive_failures", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "encrypted_access_token"
    t.string "encrypted_api_key"
    t.string "encrypted_api_secret"
    t.string "encrypted_client_id"
    t.string "encrypted_client_secret"
    t.string "encrypted_refresh_token"
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
    t.jsonb "oauth_scopes", default: [], null: false
    t.jsonb "rate_limits", default: {}, null: false
    t.integer "success_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.jsonb "usage_stats", default: {}, null: false
    t.string "vault_path"
    t.index ["account_id", "ai_data_source_id", "is_default"], name: "index_ai_data_source_credentials_unique_default", unique: true, where: "(is_default = true)"
    t.index ["account_id", "ai_data_source_id"], name: "idx_on_account_id_ai_data_source_id_e1834b7823"
    t.index ["account_id"], name: "index_ai_data_source_credentials_on_account_id"
    t.index ["ai_data_source_id"], name: "index_ai_data_source_credentials_on_ai_data_source_id"
    t.index ["consecutive_failures"], name: "index_ai_data_source_credentials_on_consecutive_failures"
    t.index ["is_active"], name: "index_ai_data_source_credentials_on_is_active"
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
    t.index ["ai_data_source_id", "slug"], name: "index_ai_data_source_endpoints_on_ai_data_source_id_and_slug", unique: true
    t.index ["ai_data_source_id"], name: "index_ai_data_source_endpoints_on_ai_data_source_id"
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
    t.index ["ai_data_source_endpoint_id"], name: "idx_on_ai_data_source_endpoint_id_fd95c1bf72"
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
    t.index ["account_id"], name: "index_ai_data_source_queries_on_account_id"
    t.index ["ai_data_source_endpoint_id"], name: "index_ai_data_source_queries_on_ai_data_source_endpoint_id"
    t.index ["ai_data_source_id", "created_at"], name: "idx_on_ai_data_source_id_created_at_1034faf465"
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
    t.index ["ai_data_source_endpoint_id", "version"], name: "idx_on_ai_data_source_endpoint_id_version_4529ef42d1", unique: true
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
    t.index ["ai_agent_id"], name: "index_ai_data_source_subscriptions_on_ai_agent_id"
    t.index ["ai_data_source_endpoint_id"], name: "idx_on_ai_data_source_endpoint_id_e7e881bfa8"
    t.index ["ai_data_source_id"], name: "index_ai_data_source_subscriptions_on_ai_data_source_id"
    t.index ["status", "next_poll_at"], name: "index_ai_data_source_subscriptions_on_status_and_next_poll_at"
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
    t.index ["account_id", "slug"], name: "index_ai_data_sources_on_account_id_and_slug", unique: true
    t.index ["account_id"], name: "index_ai_data_sources_on_account_id"
    t.index ["capabilities"], name: "index_ai_data_sources_on_capabilities", using: :gin
    t.index ["category"], name: "index_ai_data_sources_on_category", where: "(category IS NOT NULL)"
    t.index ["is_active"], name: "index_ai_data_sources_on_is_active"
    t.index ["priority_order"], name: "index_ai_data_sources_on_priority_order"
    t.index ["source_type", "is_active"], name: "index_ai_data_sources_on_source_type_and_is_active"
    t.index ["source_type"], name: "index_ai_data_sources_on_source_type"
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
    t.index ["account_id", "status"], name: "index_ai_deferred_operations_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_deferred_operations_on_account_id"
    t.index ["action_category"], name: "index_ai_deferred_operations_on_action_category"
    t.index ["ai_agent_id"], name: "index_ai_deferred_operations_on_ai_agent_id"
    t.index ["approval_request_id"], name: "index_ai_deferred_operations_on_approval_request_id"
    t.index ["executor_class"], name: "index_ai_deferred_operations_on_executor_class"
    t.index ["requested_by_id"], name: "index_ai_deferred_operations_on_requested_by_id"
    t.index ["source_type", "source_id"], name: "index_ai_deferred_operations_on_source_type_and_source_id"
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
    t.index ["account_id", "agent_id"], name: "index_ai_delegation_policies_on_account_id_and_agent_id"
    t.index ["account_id"], name: "index_ai_delegation_policies_on_account_id"
    t.index ["agent_id"], name: "index_ai_delegation_policies_on_agent_id", unique: true
    t.check_constraint "inheritance_policy::text = ANY (ARRAY['conservative'::character varying::text, 'moderate'::character varying::text, 'permissive'::character varying::text])", name: "check_delegation_inheritance_policy"
  end

  create_table "ai_delivery_runs", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "base_ref"
    t.uuid "campaign_id"
    t.uuid "campaign_land_id"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.uuid "deploy_run_id"
    t.text "detail"
    t.boolean "dry_run", default: true, null: false
    t.string "environment", default: "production", null: false
    t.text "error_message"
    t.jsonb "metadata", default: {}, null: false
    t.string "ref"
    t.uuid "repository_id"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.jsonb "steps", default: [], null: false
    t.string "strategy", default: "direct", null: false
    t.string "target_kind", null: false
    t.uuid "triggered_by_id"
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_ai_delivery_runs_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_delivery_runs_on_account_id"
    t.index ["campaign_id"], name: "index_ai_delivery_runs_on_campaign_id"
    t.index ["campaign_land_id"], name: "index_ai_delivery_runs_on_campaign_land_id"
    t.index ["deploy_run_id"], name: "index_ai_delivery_runs_on_deploy_run_id"
    t.index ["repository_id"], name: "index_ai_delivery_runs_on_repository_id"
    t.index ["triggered_by_id"], name: "index_ai_delivery_runs_on_triggered_by_id"
  end

  create_table "ai_deploy_runs", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "base_ref"
    t.uuid "campaign_id"
    t.uuid "campaign_land_id"
    t.jsonb "commands", default: [], null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "detail"
    t.boolean "dry_run", default: true, null: false
    t.string "environment", default: "production", null: false
    t.text "error_message"
    t.jsonb "metadata", default: {}, null: false
    t.string "method_key", null: false
    t.string "ref"
    t.uuid "repository_id"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.string "target_kind", null: false
    t.uuid "triggered_by_id"
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_ai_deploy_runs_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_deploy_runs_on_account_id"
    t.index ["campaign_id"], name: "index_ai_deploy_runs_on_campaign_id"
    t.index ["campaign_land_id"], name: "index_ai_deploy_runs_on_campaign_land_id"
    t.index ["repository_id"], name: "index_ai_deploy_runs_on_repository_id"
    t.index ["triggered_by_id"], name: "index_ai_deploy_runs_on_triggered_by_id"
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
    t.index ["account_id", "created_at"], name: "index_ai_deployment_risks_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_ai_deployment_risks_on_account_id"
    t.index ["assessed_by_id"], name: "index_ai_deployment_risks_on_assessed_by_id"
    t.index ["assessment_id"], name: "index_ai_deployment_risks_on_assessment_id", unique: true
    t.index ["pipeline_execution_id"], name: "index_ai_deployment_risks_on_pipeline_execution_id"
    t.index ["risk_level"], name: "index_ai_deployment_risks_on_risk_level"
    t.index ["status"], name: "index_ai_deployment_risks_on_status"
    t.index ["target_environment"], name: "index_ai_deployment_risks_on_target_environment"
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
    t.index ["account_id", "devops_template_id"], name: "idx_on_account_id_devops_template_id_f8a47754c8", unique: true
    t.index ["account_id"], name: "index_ai_devops_template_installations_on_account_id"
    t.index ["devops_template_id"], name: "index_ai_devops_template_installations_on_devops_template_id"
    t.index ["installed_by_id"], name: "index_ai_devops_template_installations_on_installed_by_id"
    t.index ["status"], name: "index_ai_devops_template_installations_on_status"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'paused'::character varying::text, 'disabled'::character varying::text, 'pending_update'::character varying::text])", name: "check_devops_installation_status"
  end

  create_table "ai_devops_templates", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.float "average_rating"
    t.string "category", null: false
    t.uuid "cloned_from_id"
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.text "description"
    t.jsonb "input_schema", default: {}
    t.integer "installation_count", default: 0
    t.jsonb "integrations_required", default: []
    t.boolean "is_featured", default: false, null: false
    t.boolean "is_system", default: false, null: false
    t.jsonb "model_requirements", default: {}, null: false
    t.string "name", null: false
    t.jsonb "output_schema", default: {}
    t.decimal "price_usd", precision: 10, scale: 2
    t.datetime "published_at"
    t.integer "review_count", default: 0
    t.jsonb "secrets_required", default: []
    t.string "slug", null: false
    t.string "source_key", limit: 255
    t.jsonb "source_snapshot", default: {}, null: false
    t.string "source_version"
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
    t.index ["account_id", "slug"], name: "index_ai_devops_templates_on_account_id_and_slug", unique: true, where: "(account_id IS NOT NULL)"
    t.index ["account_id"], name: "index_ai_devops_templates_on_account_id"
    t.index ["category"], name: "index_ai_devops_templates_on_category"
    t.index ["cloned_from_id"], name: "index_ai_devops_templates_on_cloned_from_id"
    t.index ["created_by_id"], name: "index_ai_devops_templates_on_created_by_id"
    t.index ["is_featured"], name: "index_ai_devops_templates_on_is_featured"
    t.index ["is_system"], name: "index_ai_devops_templates_on_is_system"
    t.index ["slug"], name: "index_ai_devops_templates_on_slug_global", unique: true, where: "(account_id IS NULL)"
    t.index ["source_key"], name: "index_ai_devops_templates_on_source_key"
    t.index ["status", "visibility"], name: "index_ai_devops_templates_on_status_and_visibility"
    t.index ["template_type"], name: "index_ai_devops_templates_on_template_type"
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
    t.index ["account_id", "scan_type"], name: "index_ai_discovery_results_on_account_id_and_scan_type"
    t.index ["account_id"], name: "index_ai_discovery_results_on_account_id"
    t.index ["scan_id"], name: "index_ai_discovery_results_on_scan_id", unique: true
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
    t.index ["document_id", "sequence_number"], name: "index_ai_document_chunks_on_document_id_and_sequence_number", unique: true
    t.index ["document_id"], name: "index_ai_document_chunks_on_document_id"
    t.index ["embedding"], name: "idx_document_chunks_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["knowledge_base_id", "created_at"], name: "index_ai_document_chunks_on_knowledge_base_id_and_created_at"
    t.index ["knowledge_base_id"], name: "index_ai_document_chunks_on_knowledge_base_id"
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
    t.index ["checksum"], name: "index_ai_documents_on_checksum"
    t.index ["knowledge_base_id", "name"], name: "index_ai_documents_on_knowledge_base_id_and_name"
    t.index ["knowledge_base_id", "status"], name: "index_ai_documents_on_knowledge_base_id_and_status"
    t.index ["knowledge_base_id"], name: "index_ai_documents_on_knowledge_base_id"
    t.index ["source_type"], name: "index_ai_documents_on_source_type"
    t.index ["uploaded_by_id"], name: "index_ai_documents_on_uploaded_by_id"
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
    t.index ["account_id"], name: "index_ai_encrypted_messages_on_account_id"
    t.index ["from_agent_id"], name: "index_ai_encrypted_messages_on_from_agent_id"
    t.index ["session_id", "sequence_number"], name: "index_ai_encrypted_messages_on_session_id_and_sequence_number", unique: true
    t.index ["session_id"], name: "index_ai_encrypted_messages_on_session_id"
    t.index ["to_agent_id"], name: "index_ai_encrypted_messages_on_to_agent_id"
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
    t.index ["account_id"], name: "index_ai_evaluation_results_on_account_id"
    t.index ["agent_id", "created_at"], name: "index_ai_evaluation_results_on_agent_id_and_created_at"
    t.index ["agent_id"], name: "index_ai_evaluation_results_on_agent_id"
    t.index ["execution_id"], name: "index_ai_evaluation_results_on_execution_id"
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
    t.index ["account_id", "created_at"], name: "index_ai_execution_events_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_ai_execution_events_on_account_id"
    t.index ["created_at"], name: "index_ai_execution_events_on_created_at"
    t.index ["event_type", "status"], name: "index_ai_execution_events_on_event_type_and_status"
    t.index ["source_type", "source_id"], name: "index_ai_execution_events_on_source_type_and_source_id"
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
    t.index ["execution_trace_id", "span_type"], name: "idx_on_execution_trace_id_span_type_aefca8363e"
    t.index ["execution_trace_id", "started_at"], name: "idx_on_execution_trace_id_started_at_6b3179fd72"
    t.index ["execution_trace_id", "status"], name: "idx_on_execution_trace_id_status_cedcb0e2ef"
    t.index ["execution_trace_id"], name: "index_ai_execution_trace_spans_on_execution_trace_id"
    t.index ["parent_span_id"], name: "index_ai_execution_trace_spans_on_parent_span_id"
    t.index ["span_id"], name: "index_ai_execution_trace_spans_on_span_id", unique: true
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
    t.index ["account_id", "started_at"], name: "index_ai_execution_traces_on_account_id_and_started_at"
    t.index ["account_id", "status"], name: "index_ai_execution_traces_on_account_id_and_status"
    t.index ["account_id", "trace_type"], name: "index_ai_execution_traces_on_account_id_and_trace_type"
    t.index ["account_id"], name: "index_ai_execution_traces_on_account_id"
    t.index ["root_span_id"], name: "index_ai_execution_traces_on_root_span_id"
    t.index ["trace_id"], name: "index_ai_execution_traces_on_trace_id", unique: true
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
    t.index ["account_id", "ai_agent_id"], name: "index_ai_experience_replays_on_account_id_and_ai_agent_id"
    t.index ["account_id", "status"], name: "index_ai_experience_replays_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_experience_replays_on_account_id"
    t.index ["ai_agent_id"], name: "index_ai_experience_replays_on_ai_agent_id"
    t.index ["effectiveness_score"], name: "index_ai_experience_replays_on_effectiveness_score"
    t.index ["embedding"], name: "idx_experience_replays_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["quality_score"], name: "index_ai_experience_replays_on_quality_score"
    t.index ["source_execution_id"], name: "index_ai_experience_replays_on_source_execution_id"
    t.index ["source_trajectory_id"], name: "index_ai_experience_replays_on_source_trajectory_id"
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
    t.index ["account_id"], name: "index_ai_file_locks_on_account_id"
    t.index ["worktree_id"], name: "index_ai_file_locks_on_worktree_id"
    t.index ["worktree_session_id", "file_path"], name: "index_ai_file_locks_on_worktree_session_id_and_file_path", unique: true
    t.index ["worktree_session_id"], name: "index_ai_file_locks_on_worktree_session_id"
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
    t.index ["plan_id", "status"], name: "index_ai_goal_plan_steps_on_plan_id_and_status"
    t.index ["plan_id", "step_number"], name: "index_ai_goal_plan_steps_on_plan_id_and_step_number", unique: true
    t.index ["plan_id"], name: "index_ai_goal_plan_steps_on_plan_id"
    t.index ["ralph_task_id"], name: "index_ai_goal_plan_steps_on_ralph_task_id"
    t.index ["sub_goal_id"], name: "index_ai_goal_plan_steps_on_sub_goal_id"
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
    t.index ["account_id", "status"], name: "index_ai_goal_plans_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_goal_plans_on_account_id"
    t.index ["ai_agent_id"], name: "index_ai_goal_plans_on_ai_agent_id"
    t.index ["approved_by_id"], name: "index_ai_goal_plans_on_approved_by_id"
    t.index ["goal_id", "version"], name: "index_ai_goal_plans_on_goal_id_and_version", unique: true
    t.index ["goal_id"], name: "index_ai_goal_plans_on_goal_id"
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
    t.index ["account_id", "status"], name: "index_ai_governance_reports_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_governance_reports_on_account_id"
    t.index ["monitor_agent_id"], name: "index_ai_governance_reports_on_monitor_agent_id"
    t.index ["report_type"], name: "index_ai_governance_reports_on_report_type"
    t.index ["subject_agent_id", "status"], name: "index_ai_governance_reports_on_subject_agent_id_and_status"
    t.index ["subject_agent_id"], name: "index_ai_governance_reports_on_subject_agent_id"
    t.index ["subject_team_id"], name: "index_ai_governance_reports_on_subject_team_id"
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
    t.index ["account_id", "name"], name: "index_ai_guardrail_configs_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_ai_guardrail_configs_on_account_id"
    t.index ["ai_agent_id"], name: "index_ai_guardrail_configs_on_ai_agent_id"
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
    t.index ["account_id"], name: "index_ai_hybrid_search_results_on_account_id"
    t.index ["created_at"], name: "index_ai_hybrid_search_results_on_created_at"
    t.index ["search_mode"], name: "index_ai_hybrid_search_results_on_search_mode"
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
    t.index ["account_id"], name: "index_ai_improvement_recommendations_on_account_id"
    t.index ["approved_by_id"], name: "index_ai_improvement_recommendations_on_approved_by_id"
    t.index ["recommendation_type"], name: "index_ai_improvement_recommendations_on_recommendation_type"
    t.index ["status"], name: "index_ai_improvement_recommendations_on_status"
    t.index ["target_type", "target_id"], name: "idx_on_target_type_target_id_59157c52d1"
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
    t.index ["account_id", "action_category"], name: "idx_on_account_id_action_category_c721963d27"
    t.index ["account_id", "scope"], name: "index_ai_intervention_policies_on_account_id_and_scope"
    t.index ["account_id", "user_id", "ai_agent_id"], name: "idx_on_account_id_user_id_ai_agent_id_665c33bfd7"
    t.index ["account_id"], name: "index_ai_intervention_policies_on_account_id"
    t.index ["ai_agent_id"], name: "index_ai_intervention_policies_on_ai_agent_id"
    t.index ["approval_chain_id"], name: "index_ai_intervention_policies_on_approval_chain_id"
    t.index ["user_id"], name: "index_ai_intervention_policies_on_user_id"
  end

  create_table "ai_kill_switch_events", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.jsonb "metadata", default: {}
    t.text "reason"
    t.uuid "triggered_by_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"], name: "index_ai_kill_switch_events_on_account_id_and_created_at"
    t.index ["account_id", "event_type"], name: "index_ai_kill_switch_events_on_account_id_and_event_type"
    t.index ["account_id"], name: "index_ai_kill_switch_events_on_account_id"
    t.index ["triggered_by_id"], name: "index_ai_kill_switch_events_on_triggered_by_id"
  end

  create_table "ai_knowledge_bases", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.integer "chunk_count", default: 0
    t.integer "chunk_overlap", default: 200
    t.integer "chunk_size", default: 1000
    t.string "chunking_strategy", default: "recursive", null: false
    t.uuid "cloned_from_id"
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
    t.jsonb "model_requirements", default: {}, null: false
    t.string "name", null: false
    t.jsonb "settings", default: {}
    t.string "source_key", limit: 255
    t.jsonb "source_snapshot", default: {}, null: false
    t.string "source_version"
    t.string "status", default: "active", null: false
    t.bigint "storage_bytes", default: 0
    t.bigint "total_tokens", default: 0
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_ai_knowledge_bases_on_account_id_and_name", unique: true, where: "(account_id IS NOT NULL)"
    t.index ["account_id"], name: "index_ai_knowledge_bases_on_account_id"
    t.index ["cloned_from_id"], name: "index_ai_knowledge_bases_on_cloned_from_id"
    t.index ["created_by_id"], name: "index_ai_knowledge_bases_on_created_by_id"
    t.index ["git_repository_id"], name: "index_ai_knowledge_bases_on_git_repository_id"
    t.index ["is_public"], name: "index_ai_knowledge_bases_on_is_public"
    t.index ["name"], name: "index_ai_knowledge_bases_on_name_global", unique: true, where: "(account_id IS NULL)"
    t.index ["source_key"], name: "index_ai_knowledge_bases_on_source_key"
    t.index ["status"], name: "index_ai_knowledge_bases_on_status"
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
    t.index ["account_id"], name: "index_ai_knowledge_graph_edges_on_account_id"
    t.index ["relation_type"], name: "index_ai_knowledge_graph_edges_on_relation_type"
    t.index ["source_document_id"], name: "index_ai_knowledge_graph_edges_on_source_document_id"
    t.index ["source_node_id", "target_node_id", "relation_type"], name: "index_ai_kg_edges_unique_active", unique: true, where: "((status)::text = 'active'::text)"
    t.index ["source_node_id"], name: "index_ai_knowledge_graph_edges_on_source_node_id"
    t.index ["target_node_id"], name: "index_ai_knowledge_graph_edges_on_target_node_id"
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
    t.index ["account_id"], name: "index_ai_knowledge_graph_nodes_on_account_id"
    t.index ["ai_data_source_id"], name: "index_ai_kg_nodes_on_ai_data_source_id", where: "(ai_data_source_id IS NOT NULL)"
    t.index ["ai_skill_id"], name: "index_ai_knowledge_graph_nodes_on_ai_skill_id"
    t.index ["embedding"], name: "index_ai_knowledge_graph_nodes_on_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["entity_type"], name: "index_ai_knowledge_graph_nodes_on_entity_type"
    t.index ["knowledge_base_id"], name: "index_ai_knowledge_graph_nodes_on_knowledge_base_id"
    t.index ["last_event_processed_at"], name: "index_ai_knowledge_graph_nodes_on_last_event_processed_at"
    t.index ["merged_into_id"], name: "index_ai_knowledge_graph_nodes_on_merged_into_id"
    t.index ["metadata"], name: "idx_kg_nodes_code_metadata", where: "((node_type)::text = 'code_entity'::text)", using: :gin
    t.index ["name"], name: "index_ai_knowledge_graph_nodes_on_name"
    t.index ["node_type"], name: "index_ai_knowledge_graph_nodes_on_node_type"
    t.index ["path"], name: "index_ai_knowledge_graph_nodes_on_path", using: :gist
    t.index ["source_document_id"], name: "index_ai_knowledge_graph_nodes_on_source_document_id"
    t.index ["status"], name: "index_ai_knowledge_graph_nodes_on_status"
    t.check_constraint "node_type::text = ANY (ARRAY['entity'::character varying::text, 'concept'::character varying::text, 'relation'::character varying::text, 'attribute'::character varying::text, 'code_entity'::character varying::text, 'content'::character varying::text])", name: "check_ai_kg_node_type"
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
    t.index ["account_id"], name: "index_ai_mcp_app_instances_on_account_id"
    t.index ["mcp_app_id"], name: "index_ai_mcp_app_instances_on_mcp_app_id"
    t.index ["session_id"], name: "index_ai_mcp_app_instances_on_session_id"
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
    t.index ["account_id", "name"], name: "index_ai_mcp_apps_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_ai_mcp_apps_on_account_id"
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
    t.index ["account_id", "scope"], name: "index_ai_memory_pools_on_account_id_and_scope"
    t.index ["account_id"], name: "index_ai_memory_pools_on_account_id"
    t.index ["owner_agent_id"], name: "index_ai_memory_pools_on_owner_agent_id"
    t.index ["pool_id"], name: "index_ai_memory_pools_on_pool_id", unique: true
    t.index ["task_execution_id"], name: "index_ai_memory_pools_on_task_execution_id"
    t.index ["team_id"], name: "index_ai_memory_pools_on_team_id"
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
    t.index ["account_id"], name: "index_ai_merge_operations_on_account_id"
    t.index ["status"], name: "index_ai_merge_operations_on_status"
    t.index ["worktree_id"], name: "index_ai_merge_operations_on_worktree_id"
    t.index ["worktree_session_id"], name: "index_ai_merge_operations_on_worktree_session_id"
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
    t.index ["ai_agent_id"], name: "index_ai_messages_on_ai_agent_id"
    t.index ["ai_conversation_id", "role"], name: "index_ai_messages_on_ai_conversation_id_and_role"
    t.index ["ai_conversation_id", "sequence_number"], name: "index_ai_messages_on_ai_conversation_id_and_sequence_number"
    t.index ["ai_conversation_id"], name: "index_ai_messages_on_ai_conversation_id"
    t.index ["attachments"], name: "index_ai_messages_on_attachments", using: :gin
    t.index ["deleted_at"], name: "index_ai_messages_on_deleted_at", where: "(deleted_at IS NOT NULL)"
    t.index ["edit_history"], name: "index_ai_messages_on_edit_history", using: :gin
    t.index ["message_id"], name: "index_ai_messages_on_message_id", unique: true
    t.index ["message_type"], name: "index_ai_messages_on_message_type"
    t.index ["parent_message_id"], name: "index_ai_messages_on_parent_message_id"
    t.index ["processed_at"], name: "index_ai_messages_on_processed_at"
    t.index ["role"], name: "index_ai_messages_on_role"
    t.index ["search_vector"], name: "index_ai_messages_on_search_vector", using: :gin
    t.index ["sequence_number"], name: "index_ai_messages_on_sequence_number"
    t.index ["status"], name: "index_ai_messages_on_status"
    t.index ["user_id"], name: "index_ai_messages_on_user_id"
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
    t.index ["account_id"], name: "index_ai_mission_approvals_on_account_id"
    t.index ["mission_id", "gate"], name: "index_ai_mission_approvals_on_mission_id_and_gate"
    t.index ["mission_id"], name: "index_ai_mission_approvals_on_mission_id"
    t.index ["user_id"], name: "index_ai_mission_approvals_on_user_id"
  end

  create_table "ai_mission_templates", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.jsonb "approval_gates", default: []
    t.uuid "cloned_from_id"
    t.datetime "created_at", null: false
    t.jsonb "default_configuration", default: {}
    t.text "description"
    t.boolean "is_default", default: false
    t.string "mission_type", null: false
    t.jsonb "model_requirements", default: {}, null: false
    t.string "name", null: false
    t.jsonb "phases", default: []
    t.jsonb "rejection_mappings", default: {}
    t.jsonb "skill_compositions", default: {}
    t.string "source_key", limit: 255
    t.jsonb "source_snapshot", default: {}, null: false
    t.string "source_version"
    t.string "status", default: "active"
    t.string "template_type", default: "account", null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 1
    t.index ["account_id", "template_type"], name: "index_ai_mission_templates_on_account_id_and_template_type"
    t.index ["account_id"], name: "index_ai_mission_templates_on_account_id"
    t.index ["cloned_from_id"], name: "index_ai_mission_templates_on_cloned_from_id"
    t.index ["is_default"], name: "index_ai_mission_templates_on_is_default", where: "(is_default = true)"
    t.index ["mission_type", "status"], name: "index_ai_mission_templates_on_mission_type_and_status"
    t.index ["source_key"], name: "index_ai_mission_templates_on_source_key"
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
    t.index ["account_id", "mission_type"], name: "index_ai_missions_on_account_id_and_mission_type"
    t.index ["account_id", "status"], name: "index_ai_missions_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_missions_on_account_id"
    t.index ["conversation_id"], name: "index_ai_missions_on_conversation_id"
    t.index ["created_by_id"], name: "index_ai_missions_on_created_by_id"
    t.index ["delegation_id"], name: "index_ai_missions_on_delegation_id"
    t.index ["deployed_port"], name: "index_ai_missions_on_deployed_port", unique: true, where: "(((status)::text = 'active'::text) AND (deployed_port IS NOT NULL))"
    t.index ["mission_template_id"], name: "index_ai_missions_on_mission_template_id"
    t.index ["ralph_loop_id"], name: "index_ai_missions_on_ralph_loop_id"
    t.index ["repository_id"], name: "index_ai_missions_on_repository_id"
    t.index ["review_state_id"], name: "index_ai_missions_on_review_state_id"
    t.index ["risk_contract_id"], name: "index_ai_missions_on_risk_contract_id"
    t.index ["team_id"], name: "index_ai_missions_on_team_id"
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
    t.index ["account_id"], name: "index_ai_mock_responses_on_account_id"
    t.index ["created_by_id"], name: "index_ai_mock_responses_on_created_by_id"
    t.index ["match_type"], name: "index_ai_mock_responses_on_match_type"
    t.index ["sandbox_id", "is_active", "priority"], name: "idx_on_sandbox_id_is_active_priority_2b0c78d45f"
    t.index ["sandbox_id", "provider_type"], name: "index_ai_mock_responses_on_sandbox_id_and_provider_type"
    t.index ["sandbox_id"], name: "index_ai_mock_responses_on_sandbox_id"
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
    t.index ["model_id", "provider_type"], name: "index_ai_model_pricings_on_model_id_and_provider_type", unique: true
    t.index ["provider_type"], name: "index_ai_model_pricings_on_provider_type"
    t.index ["source"], name: "index_ai_model_pricings_on_source"
  end

  create_table "ai_model_refusal_events", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "agent_execution_id"
    t.string "agent_type", limit: 50, null: false
    t.uuid "ai_provider_id", null: false
    t.string "category"
    t.datetime "created_at", null: false
    t.text "explanation"
    t.boolean "fell_back", default: false, null: false
    t.string "model", limit: 120, null: false
    t.string "phase", null: false
    t.boolean "reframed", default: false, null: false
    t.string "served_by_model"
    t.string "task_type", limit: 120
    t.string "tool_surface", limit: 120
    t.datetime "updated_at", null: false
    t.index ["account_id", "agent_type", "tool_surface", "category"], name: "idx_refusal_events_promotion_key"
    t.index ["account_id", "model", "agent_type"], name: "idx_refusal_events_account_model_type"
    t.index ["created_at"], name: "index_ai_model_refusal_events_on_created_at"
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
    t.index ["account_id", "is_active", "priority"], name: "idx_on_account_id_is_active_priority_f8d15a4635"
    t.index ["account_id", "name"], name: "idx_ai_routing_rules_preroute_name_uniq", unique: true, where: "((name)::text ~~ 'fable-refusal-preroute:%'::text)"
    t.index ["account_id", "rule_type"], name: "index_ai_model_routing_rules_on_account_id_and_rule_type"
    t.index ["account_id"], name: "index_ai_model_routing_rules_on_account_id"
    t.index ["conditions"], name: "index_ai_model_routing_rules_on_conditions", using: :gin
    t.check_constraint "rule_type::text = ANY (ARRAY['capability_based'::character varying::text, 'cost_based'::character varying::text, 'latency_based'::character varying::text, 'quality_based'::character varying::text, 'custom'::character varying::text, 'ml_optimized'::character varying::text])", name: "check_routing_rule_type"
  end

  create_table "ai_parked_questions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.text "answer"
    t.datetime "answered_at"
    t.uuid "answered_by_id"
    t.uuid "campaign_id", null: false
    t.text "context"
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "question", null: false
    t.uuid "ralph_task_id"
    t.string "status", default: "open", null: false
    t.datetime "updated_at", null: false
    t.index ["answered_by_id"], name: "index_ai_parked_questions_on_answered_by_id"
    t.index ["campaign_id", "status"], name: "index_ai_parked_questions_on_campaign_id_and_status"
    t.index ["ralph_task_id"], name: "index_ai_parked_questions_on_ralph_task_id"
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
    t.index ["account_id", "status"], name: "index_ai_performance_benchmarks_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_performance_benchmarks_on_account_id"
    t.index ["benchmark_id"], name: "index_ai_performance_benchmarks_on_benchmark_id", unique: true
    t.index ["created_by_id"], name: "index_ai_performance_benchmarks_on_created_by_id"
    t.index ["sandbox_id"], name: "index_ai_performance_benchmarks_on_sandbox_id"
    t.index ["target_agent_id"], name: "index_ai_performance_benchmarks_on_target_agent_id"
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
    t.index ["account_id", "ai_agent_id"], name: "index_ai_persistent_contexts_on_account_id_and_ai_agent_id"
    t.index ["account_id", "context_type"], name: "index_ai_persistent_contexts_on_account_id_and_context_type"
    t.index ["account_id"], name: "index_ai_persistent_contexts_on_account_id"
    t.index ["ai_agent_id"], name: "index_ai_persistent_contexts_on_ai_agent_id"
    t.index ["archived_at"], name: "index_ai_persistent_contexts_on_archived_at"
    t.index ["context_id"], name: "index_ai_persistent_contexts_on_context_id", unique: true
    t.index ["context_type"], name: "index_ai_persistent_contexts_on_context_type"
    t.index ["created_by_user_id"], name: "index_ai_persistent_contexts_on_created_by_user_id"
    t.index ["expires_at"], name: "index_ai_persistent_contexts_on_expires_at"
    t.index ["scope"], name: "index_ai_persistent_contexts_on_scope"
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
    t.index ["account_id", "status"], name: "index_ai_pipeline_executions_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_pipeline_executions_on_account_id"
    t.index ["devops_installation_id"], name: "index_ai_pipeline_executions_on_devops_installation_id"
    t.index ["execution_id"], name: "index_ai_pipeline_executions_on_execution_id", unique: true
    t.index ["pipeline_type"], name: "index_ai_pipeline_executions_on_pipeline_type"
    t.index ["repository_id", "created_at"], name: "index_ai_pipeline_executions_on_repository_id_and_created_at"
    t.index ["trigger_source"], name: "index_ai_pipeline_executions_on_trigger_source"
    t.index ["triggered_by_id"], name: "index_ai_pipeline_executions_on_triggered_by_id"
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
    t.index ["account_id", "status"], name: "index_ai_policy_violations_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_policy_violations_on_account_id"
    t.index ["detected_by_id"], name: "index_ai_policy_violations_on_detected_by_id"
    t.index ["policy_id", "created_at"], name: "index_ai_policy_violations_on_policy_id_and_created_at"
    t.index ["policy_id"], name: "index_ai_policy_violations_on_policy_id"
    t.index ["resolved_by_id"], name: "index_ai_policy_violations_on_resolved_by_id"
    t.index ["severity"], name: "index_ai_policy_violations_on_severity"
    t.index ["source_type"], name: "index_ai_policy_violations_on_source_type"
    t.index ["violation_id"], name: "index_ai_policy_violations_on_violation_id", unique: true
    t.check_constraint "severity::text = ANY (ARRAY['low'::character varying::text, 'medium'::character varying::text, 'high'::character varying::text, 'critical'::character varying::text])", name: "check_violation_severity"
    t.check_constraint "status::text = ANY (ARRAY['open'::character varying::text, 'acknowledged'::character varying::text, 'investigating'::character varying::text, 'resolved'::character varying::text, 'dismissed'::character varying::text, 'escalated'::character varying::text])", name: "check_violation_status"
  end

  create_table "ai_post_engagement_snapshots", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_published_post_id", null: false
    t.datetime "captured_at", null: false
    t.datetime "created_at", null: false
    t.integer "impressions_count"
    t.integer "likes_count"
    t.jsonb "raw_metrics", default: {}, null: false
    t.integer "replies_count"
    t.integer "reposts_count"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_ai_post_engagement_snapshots_on_account_id"
    t.index ["ai_published_post_id", "captured_at"], name: "index_ai_post_engagement_snapshots_on_post_and_captured_at"
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
    t.index ["account_id", "field_type", "artifact_ref"], name: "idx_on_account_id_field_type_artifact_ref_e41472f033", unique: true
    t.index ["account_id", "field_type"], name: "index_ai_pressure_fields_on_account_id_and_field_type"
    t.index ["account_id"], name: "index_ai_pressure_fields_on_account_id"
    t.index ["pressure_value"], name: "index_ai_pressure_fields_on_pressure_value"
  end

  create_table "ai_progress_entries", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.integer "blocked_tasks", default: 0, null: false
    t.uuid "campaign_id", null: false
    t.integer "completed_tasks", default: 0, null: false
    t.decimal "completion_pct", precision: 5, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.integer "failed_tasks", default: 0, null: false
    t.jsonb "improvement_metrics", default: {}, null: false
    t.jsonb "per_loop_summary", default: {}, null: false
    t.datetime "recorded_at", null: false
    t.integer "total_tasks", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "recorded_at"], name: "index_ai_progress_entries_on_campaign_id_and_recorded_at"
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
    t.index ["account_id", "ai_provider_id"], name: "index_ai_provider_credentials_on_account_id_and_ai_provider_id"
    t.index ["account_id", "is_default"], name: "index_ai_provider_credentials_on_account_id_and_is_default"
    t.index ["account_id"], name: "index_ai_provider_credentials_on_account_id"
    t.index ["ai_provider_id"], name: "index_ai_provider_credentials_on_ai_provider_id"
    t.index ["consecutive_failures"], name: "index_ai_provider_credentials_on_consecutive_failures"
    t.index ["expires_at"], name: "index_ai_provider_credentials_on_expires_at"
    t.index ["is_active"], name: "index_ai_provider_credentials_on_is_active"
    t.index ["last_test_status"], name: "index_ai_provider_credentials_on_last_test_status"
    t.index ["last_used_at"], name: "index_ai_provider_credentials_on_last_used_at"
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
    t.index ["account_id", "recorded_at"], name: "index_ai_provider_metrics_on_account_id_and_recorded_at"
    t.index ["account_id"], name: "index_ai_provider_metrics_on_account_id"
    t.index ["granularity", "recorded_at"], name: "index_ai_provider_metrics_on_granularity_and_recorded_at"
    t.index ["provider_id", "recorded_at"], name: "index_ai_provider_metrics_on_provider_id_and_recorded_at"
    t.index ["provider_id"], name: "index_ai_provider_metrics_on_provider_id"
    t.index ["recorded_at"], name: "index_ai_provider_metrics_on_recorded_at"
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
    t.index ["account_id", "provider_identifier"], name: "index_ai_providers_on_account_id_and_provider_identifier", unique: true
    t.index ["account_id"], name: "index_ai_providers_on_account_id"
    t.index ["capabilities"], name: "index_ai_providers_on_capabilities", using: :gin
    t.index ["is_active"], name: "index_ai_providers_on_is_active"
    t.index ["name"], name: "index_ai_providers_on_name"
    t.index ["priority_order"], name: "index_ai_providers_on_priority_order"
    t.index ["provider_type", "is_active"], name: "index_ai_providers_on_provider_type_and_is_active"
    t.index ["provider_type"], name: "index_ai_providers_on_provider_type"
    t.index ["slug", "account_id"], name: "index_ai_providers_on_slug_and_account_id", unique: true
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
    t.index ["mission_id"], name: "index_ai_provisioning_code_deployments_on_mission_id"
    t.index ["node_instance_id"], name: "index_ai_provisioning_code_deployments_on_node_instance_id"
  end

  create_table "ai_published_posts", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_data_source_endpoint_id"
    t.uuid "ai_data_source_id", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "published_at", null: false
    t.uuid "requesting_agent_id"
    t.string "source_type", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_ai_published_posts_on_account_id"
    t.index ["ai_data_source_endpoint_id"], name: "index_ai_published_posts_on_ai_data_source_endpoint_id"
    t.index ["ai_data_source_id", "external_id"], name: "index_ai_published_posts_on_ai_data_source_id_and_external_id", unique: true
    t.index ["requesting_agent_id"], name: "index_ai_published_posts_on_requesting_agent_id"
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
    t.index ["account_id"], name: "index_ai_quarantine_records_on_account_id"
    t.index ["agent_id"], name: "index_ai_quarantine_records_on_agent_id"
    t.index ["scheduled_restore_at"], name: "index_ai_quarantine_records_on_scheduled_restore_at"
    t.index ["severity"], name: "index_ai_quarantine_records_on_severity"
    t.index ["status"], name: "index_ai_quarantine_records_on_status"
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
    t.index ["account_id", "created_at"], name: "index_ai_rag_queries_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_ai_rag_queries_on_account_id"
    t.index ["knowledge_base_id", "created_at"], name: "index_ai_rag_queries_on_knowledge_base_id_and_created_at"
    t.index ["knowledge_base_id"], name: "index_ai_rag_queries_on_knowledge_base_id"
    t.index ["mission_id"], name: "index_ai_rag_queries_on_mission_id"
    t.index ["query_embedding"], name: "idx_rag_queries_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["status"], name: "index_ai_rag_queries_on_status"
    t.index ["user_id"], name: "index_ai_rag_queries_on_user_id"
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
    t.index ["ralph_loop_id", "iteration_number"], name: "idx_on_ralph_loop_id_iteration_number_874a91c211", unique: true
    t.index ["ralph_loop_id"], name: "index_ai_ralph_iterations_on_ralph_loop_id"
    t.index ["ralph_task_id"], name: "index_ai_ralph_iterations_on_ralph_task_id"
    t.index ["status"], name: "index_ai_ralph_iterations_on_status"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'skipped'::character varying::text])", name: "ai_ralph_iterations_status_check"
  end

  create_table "ai_ralph_loops", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "ai_tool"
    t.string "branch", default: "main"
    t.uuid "campaign_id"
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
    t.string "driver_kind"
    t.jsonb "driver_target", default: {}, null: false
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
    t.index ["account_id", "status"], name: "index_ai_ralph_loops_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_ralph_loops_on_account_id"
    t.index ["ai_tool"], name: "index_ai_ralph_loops_on_ai_tool"
    t.index ["campaign_id"], name: "index_ai_ralph_loops_on_campaign_id"
    t.index ["container_instance_id"], name: "index_ai_ralph_loops_on_container_instance_id"
    t.index ["created_at"], name: "index_ai_ralph_loops_on_created_at"
    t.index ["default_agent_id"], name: "index_ai_ralph_loops_on_default_agent_id"
    t.index ["driver_kind"], name: "index_ai_ralph_loops_on_driver_kind"
    t.index ["mission_id"], name: "index_ai_ralph_loops_on_mission_id"
    t.index ["next_scheduled_at"], name: "index_ai_ralph_loops_on_next_scheduled_at"
    t.index ["risk_contract_id"], name: "index_ai_ralph_loops_on_risk_contract_id"
    t.index ["schedule_paused", "next_scheduled_at"], name: "index_ai_ralph_loops_on_schedule_paused_and_next_scheduled_at"
    t.index ["scheduling_mode"], name: "index_ai_ralph_loops_on_scheduling_mode"
    t.index ["status"], name: "index_ai_ralph_loops_on_status"
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
    t.index ["capability_match_strategy"], name: "index_ai_ralph_tasks_on_capability_match_strategy"
    t.index ["execution_type"], name: "index_ai_ralph_tasks_on_execution_type"
    t.index ["executor_type", "executor_id"], name: "index_ai_ralph_tasks_on_executor_type_and_executor_id"
    t.index ["last_executor_type", "last_executor_id"], name: "idx_on_last_executor_type_last_executor_id_3f0e1816e0"
    t.index ["priority"], name: "index_ai_ralph_tasks_on_priority"
    t.index ["ralph_loop_id", "task_key"], name: "index_ai_ralph_tasks_on_ralph_loop_id_and_task_key", unique: true
    t.index ["ralph_loop_id"], name: "index_ai_ralph_tasks_on_ralph_loop_id"
    t.index ["required_capabilities"], name: "index_ai_ralph_tasks_on_required_capabilities", using: :gin
    t.index ["reverted_at"], name: "index_ai_ralph_tasks_on_reverted_at"
    t.index ["status"], name: "index_ai_ralph_tasks_on_status"
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
    t.index ["account_id"], name: "index_ai_recorded_interactions_on_account_id"
    t.index ["interaction_type"], name: "index_ai_recorded_interactions_on_interaction_type"
    t.index ["recording_id"], name: "index_ai_recorded_interactions_on_recording_id", unique: true
    t.index ["sandbox_id", "recorded_at"], name: "index_ai_recorded_interactions_on_sandbox_id_and_recorded_at"
    t.index ["sandbox_id"], name: "index_ai_recorded_interactions_on_sandbox_id"
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
    t.index ["account_id", "executed_at"], name: "index_ai_remediation_logs_on_account_id_and_executed_at"
    t.index ["account_id"], name: "index_ai_remediation_logs_on_account_id"
    t.index ["action_type"], name: "index_ai_remediation_logs_on_action_type"
    t.index ["result"], name: "index_ai_remediation_logs_on_result"
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
    t.index ["account_id", "metric_type", "period_date"], name: "idx_on_account_id_metric_type_period_date_e3c0313b0a"
    t.index ["account_id", "period_type", "period_date"], name: "idx_on_account_id_period_type_period_date_0fe0645ee5"
    t.index ["account_id"], name: "index_ai_roi_metrics_on_account_id"
    t.index ["attributable_type", "attributable_id"], name: "index_ai_roi_metrics_on_attributable_type_and_attributable_id"
    t.index ["period_date"], name: "index_ai_roi_metrics_on_period_date"
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
    t.index ["account_id"], name: "index_ai_role_profiles_on_account_id"
    t.index ["is_system"], name: "index_ai_role_profiles_on_is_system"
    t.index ["slug"], name: "index_ai_role_profiles_on_slug", unique: true
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
    t.jsonb "rationale", default: {}, null: false
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
    t.index ["account_id", "created_at"], name: "index_ai_routing_decisions_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_ai_routing_decisions_on_account_id"
    t.index ["agent_execution_id"], name: "index_ai_routing_decisions_on_agent_execution_id"
    t.index ["complexity_assessment_id"], name: "index_ai_routing_decisions_on_complexity_assessment_id"
    t.index ["created_at"], name: "index_ai_routing_decisions_on_created_at"
    t.index ["outcome"], name: "index_ai_routing_decisions_on_outcome"
    t.index ["routing_rule_id"], name: "index_ai_routing_decisions_on_routing_rule_id"
    t.index ["selected_provider_id", "created_at"], name: "idx_on_selected_provider_id_created_at_483c9515ad"
    t.index ["selected_provider_id"], name: "index_ai_routing_decisions_on_selected_provider_id"
    t.index ["strategy_used", "outcome"], name: "index_ai_routing_decisions_on_strategy_used_and_outcome"
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
    t.index ["account_id"], name: "index_ai_runner_dispatches_on_account_id"
    t.index ["git_repository_id"], name: "index_ai_runner_dispatches_on_git_repository_id"
    t.index ["git_runner_id"], name: "index_ai_runner_dispatches_on_git_runner_id"
    t.index ["mission_id"], name: "index_ai_runner_dispatches_on_mission_id"
    t.index ["worktree_id"], name: "index_ai_runner_dispatches_on_worktree_id"
    t.index ["worktree_session_id"], name: "index_ai_runner_dispatches_on_worktree_session_id"
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
    t.index ["account_id", "name"], name: "index_ai_sandboxes_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_ai_sandboxes_on_account_id"
    t.index ["created_by_id"], name: "index_ai_sandboxes_on_created_by_id"
    t.index ["expires_at"], name: "index_ai_sandboxes_on_expires_at"
    t.index ["sandbox_type"], name: "index_ai_sandboxes_on_sandbox_type"
    t.index ["status"], name: "index_ai_sandboxes_on_status"
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
    t.index ["account_id", "status"], name: "index_ai_scheduled_messages_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_scheduled_messages_on_account_id"
    t.index ["conversation_id"], name: "index_ai_scheduled_messages_on_conversation_id"
    t.index ["status", "next_scheduled_at"], name: "index_ai_scheduled_messages_on_status_and_next_scheduled_at"
    t.index ["user_id"], name: "index_ai_scheduled_messages_on_user_id"
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
    t.index ["account_id"], name: "index_ai_security_audit_trails_on_account_id"
    t.index ["action"], name: "index_ai_security_audit_trails_on_action"
    t.index ["agent_id"], name: "index_ai_security_audit_trails_on_agent_id"
    t.index ["asi_reference"], name: "index_ai_security_audit_trails_on_asi_reference"
    t.index ["created_at"], name: "index_ai_security_audit_trails_on_created_at"
    t.index ["outcome"], name: "index_ai_security_audit_trails_on_outcome"
    t.index ["severity"], name: "index_ai_security_audit_trails_on_severity"
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
    t.index ["account_id", "status"], name: "index_ai_self_challenges_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_self_challenges_on_account_id"
    t.index ["ai_skill_id"], name: "index_ai_self_challenges_on_ai_skill_id"
    t.index ["challenge_id"], name: "index_ai_self_challenges_on_challenge_id", unique: true
    t.index ["challenger_agent_id", "status"], name: "index_ai_self_challenges_on_challenger_agent_id_and_status"
    t.index ["challenger_agent_id"], name: "index_ai_self_challenges_on_challenger_agent_id"
    t.index ["executor_agent_id"], name: "index_ai_self_challenges_on_executor_agent_id"
    t.index ["validator_agent_id"], name: "index_ai_self_challenges_on_validator_agent_id"
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
    t.index ["account_id", "agent_id", "created_at"], name: "idx_on_account_id_agent_id_created_at_9d9ea95c90"
    t.index ["account_id"], name: "index_ai_shadow_executions_on_account_id"
    t.index ["agent_id", "agreed"], name: "index_ai_shadow_executions_on_agent_id_and_agreed"
    t.index ["agent_id"], name: "index_ai_shadow_executions_on_agent_id"
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
    t.index ["access_level"], name: "index_ai_shared_knowledges_on_access_level"
    t.index ["account_id"], name: "index_ai_shared_knowledges_on_account_id"
    t.index ["created_by_id"], name: "index_ai_shared_knowledges_on_created_by_id"
    t.index ["embedding"], name: "index_ai_shared_knowledges_on_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["git_repository_id"], name: "index_ai_shared_knowledges_on_git_repository_id"
    t.index ["last_event_processed_at"], name: "index_ai_shared_knowledges_on_last_event_processed_at"
    t.index ["source_type", "source_id"], name: "index_ai_shared_knowledges_on_source_type_and_source_id"
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
    t.index ["component_skill_id"], name: "index_ai_skill_compositions_on_component_skill_id"
    t.index ["composite_skill_id", "execution_order"], name: "idx_on_composite_skill_id_execution_order_102d591b74", unique: true
    t.index ["composite_skill_id"], name: "index_ai_skill_compositions_on_composite_skill_id"
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
    t.index ["account_id"], name: "index_ai_skill_conflicts_on_account_id"
    t.index ["resolved_by_id"], name: "index_ai_skill_conflicts_on_resolved_by_id"
    t.index ["skill_a_id", "skill_b_id", "conflict_type"], name: "idx_skill_conflicts_unique_active", unique: true, where: "((status)::text <> ALL (ARRAY[('resolved'::character varying)::text, ('dismissed'::character varying)::text]))"
    t.index ["skill_a_id"], name: "index_ai_skill_conflicts_on_skill_a_id"
    t.index ["skill_b_id"], name: "index_ai_skill_conflicts_on_skill_b_id"
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
    t.index ["account_id"], name: "index_ai_skill_proposals_on_account_id"
    t.index ["created_skill_id"], name: "index_ai_skill_proposals_on_created_skill_id"
    t.index ["parent_proposal_id"], name: "index_ai_skill_proposals_on_parent_proposal_id"
    t.index ["proposed_by_agent_id"], name: "index_ai_skill_proposals_on_proposed_by_agent_id"
    t.index ["proposed_by_user_id"], name: "index_ai_skill_proposals_on_proposed_by_user_id"
    t.index ["reviewed_by_id"], name: "index_ai_skill_proposals_on_reviewed_by_id"
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
    t.index ["account_id", "status"], name: "index_ai_skill_recipe_runs_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_skill_recipe_runs_on_account_id"
    t.index ["ai_agent_id"], name: "index_ai_skill_recipe_runs_on_ai_agent_id"
    t.index ["ai_skill_id", "created_at"], name: "index_ai_skill_recipe_runs_on_ai_skill_id_and_created_at"
    t.index ["status"], name: "index_ai_skill_recipe_runs_on_status"
    t.index ["user_id", "created_at"], name: "index_ai_skill_recipe_runs_on_user_id_and_created_at"
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
    t.index ["account_id"], name: "index_ai_skill_usage_records_on_account_id"
    t.index ["ai_agent_id", "created_at"], name: "index_ai_skill_usage_records_on_ai_agent_id_and_created_at"
    t.index ["ai_skill_id", "outcome"], name: "index_ai_skill_usage_records_on_ai_skill_id_and_outcome"
    t.index ["created_at"], name: "index_ai_skill_usage_records_on_created_at"
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
    t.index ["account_id"], name: "index_ai_skill_versions_on_account_id"
    t.index ["ai_skill_id", "version"], name: "index_ai_skill_versions_on_ai_skill_id_and_version", unique: true
    t.index ["ai_skill_id"], name: "index_ai_skill_versions_on_ai_skill_id"
    t.index ["created_by_agent_id"], name: "index_ai_skill_versions_on_created_by_agent_id"
    t.index ["created_by_user_id"], name: "index_ai_skill_versions_on_created_by_user_id"
  end

  create_table "ai_skills", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.jsonb "activation_rules", default: {}
    t.uuid "ai_knowledge_base_id"
    t.string "category", null: false
    t.uuid "cloned_from_id"
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
    t.jsonb "model_requirements", default: {}, null: false
    t.string "name", null: false
    t.integer "negative_usage_count", default: 0
    t.uuid "parent_skill_id"
    t.integer "positive_usage_count", default: 0
    t.string "provenance", default: "internal", null: false
    t.string "slug", null: false
    t.string "source_key", limit: 255
    t.jsonb "source_snapshot", default: {}, null: false
    t.string "source_version"
    t.string "status", default: "active"
    t.text "system_prompt"
    t.jsonb "tags", default: []
    t.string "trust_level", default: "trusted", null: false
    t.datetime "updated_at", null: false
    t.integer "usage_count", default: 0, null: false
    t.string "version", default: "1.0.0"
    t.index ["account_id", "slug"], name: "index_ai_skills_on_account_id_and_slug", unique: true, where: "(account_id IS NOT NULL)"
    t.index ["account_id"], name: "index_ai_skills_on_account_id"
    t.index ["ai_knowledge_base_id"], name: "index_ai_skills_on_ai_knowledge_base_id"
    t.index ["category"], name: "index_ai_skills_on_category"
    t.index ["cloned_from_id"], name: "index_ai_skills_on_cloned_from_id"
    t.index ["is_system"], name: "index_ai_skills_on_is_system"
    t.index ["parent_skill_id"], name: "index_ai_skills_on_parent_skill_id"
    t.index ["provenance"], name: "index_ai_skills_on_provenance"
    t.index ["slug"], name: "index_ai_skills_on_slug_global", unique: true, where: "(account_id IS NULL)"
    t.index ["source_key"], name: "index_ai_skills_on_source_key"
    t.index ["status"], name: "index_ai_skills_on_status"
    t.index ["tags"], name: "index_ai_skills_on_tags", using: :gin
    t.index ["trust_level"], name: "index_ai_skills_on_trust_level"
  end

  create_table "ai_skills_mcp_servers", id: false, force: :cascade do |t|
    t.uuid "ai_skill_id", null: false
    t.uuid "mcp_server_id", null: false
    t.index ["ai_skill_id", "mcp_server_id"], name: "index_ai_skills_mcp_servers_on_ai_skill_id_and_mcp_server_id", unique: true
    t.index ["mcp_server_id"], name: "index_ai_skills_mcp_servers_on_mcp_server_id"
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
    t.index ["account_id", "signal_key"], name: "index_ai_stigmergic_signals_on_account_id_and_signal_key"
    t.index ["account_id", "signal_type"], name: "index_ai_stigmergic_signals_on_account_id_and_signal_type"
    t.index ["account_id"], name: "index_ai_stigmergic_signals_on_account_id"
    t.index ["emitter_agent_id"], name: "index_ai_stigmergic_signals_on_emitter_agent_id"
    t.index ["expires_at"], name: "index_ai_stigmergic_signals_on_expires_at", where: "(expires_at IS NOT NULL)"
    t.index ["memory_pool_id"], name: "index_ai_stigmergic_signals_on_memory_pool_id"
    t.index ["strength"], name: "index_ai_stigmergic_signals_on_strength"
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
    t.index ["account_id"], name: "index_ai_task_complexity_assessments_on_account_id"
    t.index ["complexity_level"], name: "index_ai_task_complexity_assessments_on_complexity_level"
    t.index ["recommended_tier"], name: "index_ai_task_complexity_assessments_on_recommended_tier"
    t.index ["routing_decision_id"], name: "index_ai_task_complexity_assessments_on_routing_decision_id"
    t.index ["task_type"], name: "index_ai_task_complexity_assessments_on_task_type"
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
    t.index ["account_id"], name: "index_ai_task_reviews_on_account_id"
    t.index ["review_id"], name: "index_ai_task_reviews_on_review_id", unique: true
    t.index ["reviewer_agent_id"], name: "index_ai_task_reviews_on_reviewer_agent_id"
    t.index ["reviewer_role_id"], name: "index_ai_task_reviews_on_reviewer_role_id"
    t.index ["team_task_id", "status"], name: "index_ai_task_reviews_on_team_task_id_and_status"
    t.index ["team_task_id"], name: "index_ai_task_reviews_on_team_task_id"
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
    t.index ["agent_team_id", "name"], name: "index_ai_team_channels_on_agent_team_id_and_name", unique: true
    t.index ["agent_team_id"], name: "index_ai_team_channels_on_agent_team_id"
    t.index ["channel_type"], name: "index_ai_team_channels_on_channel_type"
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
    t.index ["account_id", "status"], name: "index_ai_team_executions_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_team_executions_on_account_id"
    t.index ["agent_team_id", "created_at"], name: "index_ai_team_executions_on_agent_team_id_and_created_at"
    t.index ["agent_team_id"], name: "index_ai_team_executions_on_agent_team_id"
    t.index ["ai_conversation_id"], name: "index_ai_team_executions_on_ai_conversation_id"
    t.index ["approval_decided_by_id"], name: "index_ai_team_executions_on_approval_decided_by_id"
    t.index ["control_signal"], name: "index_ai_team_executions_on_control_signal"
    t.index ["execution_id"], name: "index_ai_team_executions_on_execution_id", unique: true
    t.index ["mission_id"], name: "index_ai_team_executions_on_mission_id"
    t.index ["started_at"], name: "index_ai_team_executions_on_started_at"
    t.index ["triggered_by_id"], name: "index_ai_team_executions_on_triggered_by_id"
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
    t.index ["channel_id", "created_at"], name: "index_ai_team_messages_on_channel_id_and_created_at"
    t.index ["channel_id"], name: "index_ai_team_messages_on_channel_id"
    t.index ["from_role_id", "created_at"], name: "index_ai_team_messages_on_from_role_id_and_created_at"
    t.index ["from_role_id"], name: "index_ai_team_messages_on_from_role_id"
    t.index ["in_reply_to_id"], name: "index_ai_team_messages_on_in_reply_to_id"
    t.index ["message_type"], name: "index_ai_team_messages_on_message_type"
    t.index ["team_execution_id", "sequence_number"], name: "idx_on_team_execution_id_sequence_number_beb97b4ae3"
    t.index ["team_execution_id"], name: "index_ai_team_messages_on_team_execution_id"
    t.index ["to_role_id"], name: "index_ai_team_messages_on_to_role_id"
    t.index ["user_id"], name: "index_ai_team_messages_on_user_id"
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
    t.index ["account_id"], name: "index_ai_team_restructure_events_on_account_id"
    t.index ["ai_agent_id"], name: "index_ai_team_restructure_events_on_ai_agent_id"
    t.index ["ai_agent_team_id", "event_type"], name: "idx_on_ai_agent_team_id_event_type_1d709fad3d"
    t.index ["ai_agent_team_id"], name: "index_ai_team_restructure_events_on_ai_agent_team_id"
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
    t.index ["account_id"], name: "index_ai_team_roles_on_account_id"
    t.index ["agent_team_id", "priority_order"], name: "index_ai_team_roles_on_agent_team_id_and_priority_order"
    t.index ["agent_team_id", "role_name"], name: "index_ai_team_roles_on_agent_team_id_and_role_name", unique: true
    t.index ["agent_team_id"], name: "index_ai_team_roles_on_agent_team_id"
    t.index ["ai_agent_id"], name: "index_ai_team_roles_on_ai_agent_id"
    t.index ["role_type"], name: "index_ai_team_roles_on_role_type"
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
    t.index ["assigned_agent_id"], name: "index_ai_team_tasks_on_assigned_agent_id"
    t.index ["assigned_role_id", "status"], name: "index_ai_team_tasks_on_assigned_role_id_and_status"
    t.index ["assigned_role_id"], name: "index_ai_team_tasks_on_assigned_role_id"
    t.index ["delegated_from_task_id"], name: "index_ai_team_tasks_on_delegated_from_task_id"
    t.index ["parent_task_id"], name: "index_ai_team_tasks_on_parent_task_id"
    t.index ["priority"], name: "index_ai_team_tasks_on_priority"
    t.index ["task_id"], name: "index_ai_team_tasks_on_task_id", unique: true
    t.index ["team_execution_id", "status"], name: "index_ai_team_tasks_on_team_execution_id_and_status"
    t.index ["team_execution_id"], name: "index_ai_team_tasks_on_team_execution_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'assigned'::character varying::text, 'in_progress'::character varying::text, 'waiting'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text, 'delegated'::character varying::text])", name: "check_team_task_status"
    t.check_constraint "task_type::text = ANY (ARRAY['execution'::character varying::text, 'review'::character varying::text, 'validation'::character varying::text, 'coordination'::character varying::text, 'escalation'::character varying::text, 'human_input'::character varying::text])", name: "check_team_task_type"
  end

  create_table "ai_team_templates", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.float "average_rating"
    t.string "category"
    t.jsonb "channel_definitions", default: []
    t.uuid "cloned_from_id"
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.jsonb "default_config", default: {}
    t.text "description"
    t.boolean "is_public", default: false, null: false
    t.boolean "is_system", default: false, null: false
    t.jsonb "model_requirements", default: {}, null: false
    t.string "name", null: false
    t.datetime "published_at"
    t.jsonb "role_definitions", default: []
    t.string "slug", null: false
    t.string "source_key", limit: 255
    t.jsonb "source_snapshot", default: {}, null: false
    t.string "source_version"
    t.jsonb "tags", default: []
    t.string "team_topology", default: "hierarchical", null: false
    t.datetime "updated_at", null: false
    t.integer "usage_count", default: 0
    t.jsonb "workflow_pattern", default: {}
    t.index ["account_id"], name: "index_ai_team_templates_on_account_id"
    t.index ["cloned_from_id"], name: "index_ai_team_templates_on_cloned_from_id"
    t.index ["created_by_id"], name: "index_ai_team_templates_on_created_by_id"
    t.index ["is_public", "category"], name: "index_ai_team_templates_on_is_public_and_category"
    t.index ["is_system"], name: "index_ai_team_templates_on_is_system"
    t.index ["slug"], name: "index_ai_team_templates_on_slug", unique: true
    t.index ["source_key"], name: "index_ai_team_templates_on_source_key"
    t.index ["team_topology"], name: "index_ai_team_templates_on_team_topology"
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
    t.index ["account_id", "created_at"], name: "index_ai_telemetry_events_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_ai_telemetry_events_on_account_id"
    t.index ["agent_id", "event_category", "created_at"], name: "idx_on_agent_id_event_category_created_at_f51a1c0e86"
    t.index ["agent_id"], name: "index_ai_telemetry_events_on_agent_id"
    t.index ["correlation_id"], name: "index_ai_telemetry_events_on_correlation_id"
    t.index ["parent_event_id"], name: "index_ai_telemetry_events_on_parent_event_id"
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
    t.index ["agent_template_id", "metric_date"], name: "idx_on_agent_template_id_metric_date_5d1afa7e41", unique: true
    t.index ["agent_template_id"], name: "index_ai_template_usage_metrics_on_agent_template_id"
    t.index ["metric_date"], name: "index_ai_template_usage_metrics_on_metric_date"
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
    t.index ["result_id"], name: "index_ai_test_results_on_result_id", unique: true
    t.index ["scenario_id", "created_at"], name: "index_ai_test_results_on_scenario_id_and_created_at"
    t.index ["scenario_id"], name: "index_ai_test_results_on_scenario_id"
    t.index ["test_run_id", "status"], name: "index_ai_test_results_on_test_run_id_and_status"
    t.index ["test_run_id"], name: "index_ai_test_results_on_test_run_id"
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
    t.index ["account_id", "status"], name: "index_ai_test_runs_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_test_runs_on_account_id"
    t.index ["run_id"], name: "index_ai_test_runs_on_run_id", unique: true
    t.index ["run_type"], name: "index_ai_test_runs_on_run_type"
    t.index ["sandbox_id", "created_at"], name: "index_ai_test_runs_on_sandbox_id_and_created_at"
    t.index ["sandbox_id"], name: "index_ai_test_runs_on_sandbox_id"
    t.index ["triggered_by_id"], name: "index_ai_test_runs_on_triggered_by_id"
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
    t.index ["account_id", "status"], name: "index_ai_test_scenarios_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_test_scenarios_on_account_id"
    t.index ["created_by_id"], name: "index_ai_test_scenarios_on_created_by_id"
    t.index ["sandbox_id", "name"], name: "index_ai_test_scenarios_on_sandbox_id_and_name", unique: true
    t.index ["sandbox_id"], name: "index_ai_test_scenarios_on_sandbox_id"
    t.index ["scenario_type"], name: "index_ai_test_scenarios_on_scenario_type"
    t.index ["target_agent_id"], name: "index_ai_test_scenarios_on_target_agent_id"
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
    t.index ["account_id"], name: "index_ai_trajectories_on_account_id"
    t.index ["ai_agent_id"], name: "index_ai_trajectories_on_ai_agent_id"
    t.index ["status"], name: "index_ai_trajectories_on_status"
    t.index ["tags"], name: "index_ai_trajectories_on_tags", using: :gin
    t.index ["team_execution_id"], name: "index_ai_trajectories_on_team_execution_id"
    t.index ["trajectory_id"], name: "index_ai_trajectories_on_trajectory_id", unique: true
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
    t.index ["chapter_type"], name: "index_ai_trajectory_chapters_on_chapter_type"
    t.index ["trajectory_id", "chapter_number"], name: "idx_on_trajectory_id_chapter_number_5ccafbb083", unique: true
    t.index ["trajectory_id"], name: "index_ai_trajectory_chapters_on_trajectory_id"
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
    t.index ["account_id"], name: "index_ai_worktree_sessions_on_account_id"
    t.index ["initiated_by_id"], name: "index_ai_worktree_sessions_on_initiated_by_id"
    t.index ["source_type", "source_id"], name: "index_ai_worktree_sessions_on_source_type_and_source_id"
    t.index ["status"], name: "index_ai_worktree_sessions_on_status"
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
    t.index ["account_id"], name: "index_ai_worktrees_on_account_id"
    t.index ["ai_agent_id"], name: "index_ai_worktrees_on_ai_agent_id"
    t.index ["assignee_type", "assignee_id"], name: "index_ai_worktrees_on_assignee_type_and_assignee_id"
    t.index ["branch_name"], name: "index_ai_worktrees_on_branch_name", unique: true
    t.index ["status"], name: "index_ai_worktrees_on_status"
    t.index ["worktree_path"], name: "index_ai_worktrees_on_worktree_path", unique: true
    t.index ["worktree_session_id"], name: "index_ai_worktrees_on_worktree_session_id"
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
    t.index ["api_key_id", "used_at"], name: "index_api_key_usages_on_api_key_id_and_used_at"
    t.index ["api_key_id"], name: "index_api_key_usages_on_api_key_id"
    t.index ["endpoint"], name: "index_api_key_usages_on_endpoint"
    t.index ["response_status"], name: "index_api_key_usages_on_response_status"
    t.index ["used_at"], name: "index_api_key_usages_on_used_at"
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
    t.index ["account_id"], name: "index_api_keys_on_account_id"
    t.index ["allowed_ips"], name: "idx_api_keys_on_allowed_ips", using: :gin
    t.index ["created_by_id"], name: "index_api_keys_on_created_by_id"
    t.index ["expires_at"], name: "index_api_keys_on_expires_at"
    t.index ["is_active"], name: "index_api_keys_on_is_active"
    t.index ["key_digest"], name: "index_api_keys_on_key_digest", unique: true
    t.index ["key_prefix"], name: "index_api_keys_on_key_prefix"
    t.index ["key_suffix"], name: "index_api_keys_on_key_suffix"
    t.index ["permissions"], name: "idx_api_keys_on_permissions", using: :gin
    t.index ["prefix"], name: "index_api_keys_on_prefix", unique: true
    t.index ["scopes"], name: "idx_api_keys_on_scopes", using: :gin
    t.index ["usage_count"], name: "index_api_keys_on_usage_count"
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
    t.index ["account_id", "created_at"], name: "index_audit_logs_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_audit_logs_on_account_id"
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["chain_verified_at"], name: "index_audit_logs_on_chain_verified_at"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["integrity_hash"], name: "index_audit_logs_on_integrity_hash", unique: true, where: "(integrity_hash IS NOT NULL)"
    t.index ["request_id"], name: "index_audit_logs_on_request_id"
    t.index ["resource_type", "resource_id"], name: "index_audit_logs_on_resource_type_and_resource_id"
    t.index ["risk_level"], name: "index_audit_logs_on_risk_level"
    t.index ["sequence_number"], name: "index_audit_logs_on_sequence_number", unique: true, where: "(sequence_number IS NOT NULL)"
    t.index ["severity"], name: "index_audit_logs_on_severity"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
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
    t.index ["created_at"], name: "index_background_jobs_on_created_at"
    t.index ["job_id"], name: "index_background_jobs_on_job_id", unique: true
    t.index ["job_type", "status"], name: "index_background_jobs_on_job_type_and_status"
    t.index ["job_type"], name: "index_background_jobs_on_job_type"
    t.index ["scheduled_at"], name: "index_background_jobs_on_scheduled_at"
    t.index ["status"], name: "index_background_jobs_on_status"
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
    t.index ["expires_at"], name: "index_blacklisted_tokens_on_expires_at"
    t.index ["token"], name: "index_blacklisted_tokens_on_token", unique: true
    t.index ["user_id"], name: "index_blacklisted_tokens_on_user_id"
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
    t.index ["account_id", "platform_user_id"], name: "index_chat_blacklists_on_account_id_and_platform_user_id"
    t.index ["account_id"], name: "index_chat_blacklists_on_account_id"
    t.index ["blocked_by_id"], name: "index_chat_blacklists_on_blocked_by_id"
    t.index ["channel_id", "platform_user_id"], name: "index_chat_blacklists_on_channel_id_and_platform_user_id", unique: true, where: "(channel_id IS NOT NULL)"
    t.index ["channel_id"], name: "index_chat_blacklists_on_channel_id"
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
    t.index ["account_id", "platform", "name"], name: "index_chat_channels_on_account_id_and_platform_and_name", unique: true
    t.index ["account_id"], name: "index_chat_channels_on_account_id"
    t.index ["ai_team_channel_id"], name: "index_chat_channels_on_ai_team_channel_id"
    t.index ["default_agent_id"], name: "index_chat_channels_on_default_agent_id"
    t.index ["platform"], name: "index_chat_channels_on_platform"
    t.index ["status"], name: "index_chat_channels_on_status"
    t.index ["webhook_token"], name: "index_chat_channels_on_webhook_token", unique: true
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
    t.index ["attachment_type"], name: "index_chat_message_attachments_on_attachment_type"
    t.index ["file_object_id"], name: "index_chat_message_attachments_on_file_object_id"
    t.index ["message_id"], name: "index_chat_message_attachments_on_message_id"
    t.index ["platform_file_id"], name: "index_chat_message_attachments_on_platform_file_id"
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
    t.index ["ai_message_id"], name: "index_chat_messages_on_ai_message_id"
    t.index ["delivery_status"], name: "index_chat_messages_on_delivery_status"
    t.index ["direction"], name: "index_chat_messages_on_direction"
    t.index ["message_type"], name: "index_chat_messages_on_message_type"
    t.index ["platform_message_id"], name: "index_chat_messages_on_platform_message_id"
    t.index ["session_id", "created_at"], name: "index_chat_messages_on_session_id_and_created_at"
    t.index ["session_id"], name: "index_chat_messages_on_session_id"
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
    t.index ["ai_conversation_id"], name: "index_chat_sessions_on_ai_conversation_id"
    t.index ["assigned_agent_id"], name: "index_chat_sessions_on_assigned_agent_id"
    t.index ["channel_id", "platform_user_id"], name: "index_chat_sessions_on_channel_id_and_platform_user_id", unique: true
    t.index ["channel_id"], name: "index_chat_sessions_on_channel_id"
    t.index ["last_activity_at"], name: "index_chat_sessions_on_last_activity_at"
    t.index ["platform_user_id"], name: "index_chat_sessions_on_platform_user_id"
    t.index ["status"], name: "index_chat_sessions_on_status"
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
    t.index ["circuit_breaker_id", "created_at"], name: "idx_on_circuit_breaker_id_created_at_017ec04aab"
    t.index ["circuit_breaker_id"], name: "index_circuit_breaker_events_on_circuit_breaker_id"
    t.index ["event_type"], name: "index_circuit_breaker_events_on_event_type"
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
    t.index ["name", "service"], name: "index_circuit_breakers_on_name_and_service", unique: true
    t.index ["service", "state"], name: "index_circuit_breakers_on_service_and_state"
    t.index ["state"], name: "index_circuit_breakers_on_state"
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
    t.index ["a2a_task_id"], name: "index_community_agent_ratings_on_a2a_task_id"
    t.index ["account_id"], name: "index_community_agent_ratings_on_account_id"
    t.index ["community_agent_id", "account_id"], name: "idx_on_community_agent_id_account_id_4b3dd061f2", unique: true
    t.index ["community_agent_id"], name: "index_community_agent_ratings_on_community_agent_id"
    t.index ["rating"], name: "index_community_agent_ratings_on_rating"
    t.index ["user_id"], name: "index_community_agent_ratings_on_user_id"
    t.index ["verified_usage"], name: "index_community_agent_ratings_on_verified_usage"
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
    t.index ["community_agent_id", "status"], name: "index_community_agent_reports_on_community_agent_id_and_status"
    t.index ["community_agent_id"], name: "index_community_agent_reports_on_community_agent_id"
    t.index ["report_type"], name: "index_community_agent_reports_on_report_type"
    t.index ["reported_by_account_id"], name: "index_community_agent_reports_on_reported_by_account_id"
    t.index ["reported_by_user_id"], name: "index_community_agent_reports_on_reported_by_user_id"
    t.index ["resolved_by_id"], name: "index_community_agent_reports_on_resolved_by_id"
    t.index ["status"], name: "index_community_agent_reports_on_status"
    t.check_constraint "report_type::text = ANY (ARRAY['malicious'::character varying::text, 'spam'::character varying::text, 'inappropriate'::character varying::text, 'copyright'::character varying::text, 'other'::character varying::text])", name: "community_reports_type_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'investigating'::character varying::text, 'resolved'::character varying::text, 'dismissed'::character varying::text])", name: "community_reports_status_check"
  end

  create_table "community_agents", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "agent_card_id"
    t.uuid "agent_id"
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
    t.jsonb "federation_metadata", default: {}, null: false
    t.uuid "federation_partner_id"
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
    t.index ["agent_card_id"], name: "index_community_agents_on_agent_card_id"
    t.index ["agent_id"], name: "index_community_agents_on_agent_id"
    t.index ["category"], name: "index_community_agents_on_category"
    t.index ["federation_key"], name: "index_community_agents_on_federation_key", unique: true, where: "(federation_key IS NOT NULL)"
    t.index ["federation_partner_id"], name: "index_community_agents_on_federation_partner_id"
    t.index ["owner_account_id"], name: "index_community_agents_on_owner_account_id"
    t.index ["published_by_id"], name: "index_community_agents_on_published_by_id"
    t.index ["reputation_score"], name: "index_community_agents_on_reputation_score"
    t.index ["slug"], name: "index_community_agents_on_slug", unique: true
    t.index ["status"], name: "index_community_agents_on_status"
    t.index ["tags"], name: "index_community_agents_on_tags", using: :gin
    t.index ["task_count"], name: "index_community_agents_on_task_count"
    t.index ["verified"], name: "index_community_agents_on_verified"
    t.index ["verified_by_id"], name: "index_community_agents_on_verified_by_id"
    t.index ["visibility"], name: "index_community_agents_on_visibility"
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
    t.index ["account_id"], name: "index_data_deletion_requests_on_account_id"
    t.index ["deletion_type"], name: "index_data_deletion_requests_on_deletion_type"
    t.index ["grace_period_ends_at"], name: "index_data_deletion_requests_on_grace_period_ends_at"
    t.index ["processed_by_id"], name: "index_data_deletion_requests_on_processed_by_id"
    t.index ["requested_by_id"], name: "index_data_deletion_requests_on_requested_by_id"
    t.index ["status"], name: "index_data_deletion_requests_on_status"
    t.index ["user_id"], name: "index_data_deletion_requests_on_user_id"
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
    t.index ["account_id"], name: "index_data_export_requests_on_account_id"
    t.index ["download_token"], name: "index_data_export_requests_on_download_token", unique: true, where: "(download_token IS NOT NULL)"
    t.index ["expires_at"], name: "index_data_export_requests_on_expires_at"
    t.index ["requested_by_id"], name: "index_data_export_requests_on_requested_by_id"
    t.index ["status"], name: "index_data_export_requests_on_status"
    t.index ["user_id"], name: "index_data_export_requests_on_user_id"
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
    t.index ["account_id", "data_type"], name: "index_data_retention_policies_on_account_id_and_data_type", unique: true
    t.index ["account_id"], name: "index_data_retention_policies_on_account_id"
    t.index ["active"], name: "index_data_retention_policies_on_active"
    t.index ["data_type"], name: "index_data_retention_policies_on_data_type"
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
    t.index ["backup_type"], name: "index_database_backups_on_backup_type"
    t.index ["created_by_id"], name: "index_database_backups_on_created_by_id"
    t.index ["started_at"], name: "index_database_backups_on_started_at"
    t.index ["status"], name: "index_database_backups_on_status"
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
    t.index ["database_backup_id"], name: "index_database_restores_on_database_backup_id"
    t.index ["initiated_by_id"], name: "index_database_restores_on_initiated_by_id"
    t.index ["started_at"], name: "index_database_restores_on_started_at"
    t.index ["status"], name: "index_database_restores_on_status"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "valid_restore_status"
  end

  create_table "delegation_permissions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_delegation_id", null: false
    t.datetime "created_at", null: false
    t.string "permission_name", limit: 100, null: false
    t.datetime "updated_at", null: false
    t.index ["account_delegation_id", "permission_name"], name: "idx_on_account_delegation_id_permission_name", unique: true
    t.index ["account_delegation_id"], name: "index_delegation_permissions_on_account_delegation_id"
    t.index ["permission_name"], name: "index_delegation_permissions_on_permission_name"
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
    t.index ["account_id", "config_type"], name: "index_devops_ai_configs_on_account_id_and_config_type"
    t.index ["account_id", "is_default"], name: "index_devops_ai_configs_on_account_id_and_is_default", where: "(is_default = true)"
    t.index ["account_id", "name"], name: "index_devops_ai_configs_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_devops_ai_configs_on_account_id"
    t.index ["created_by_id"], name: "index_devops_ai_configs_on_created_by_id"
    t.index ["provider"], name: "index_devops_ai_configs_on_provider"
    t.index ["status"], name: "index_devops_ai_configs_on_status"
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
    t.index ["account_id"], name: "index_devops_container_image_builds_on_account_id"
    t.index ["container_template_id"], name: "index_devops_container_image_builds_on_container_template_id"
    t.index ["triggered_by_build_id"], name: "index_devops_container_image_builds_on_triggered_by_build_id"
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
    t.index ["a2a_task_id"], name: "index_devops_container_instances_on_a2a_task_id"
    t.index ["account_id", "status"], name: "index_devops_container_instances_on_account_id_and_status"
    t.index ["account_id"], name: "index_devops_container_instances_on_account_id"
    t.index ["created_at"], name: "index_devops_container_instances_on_created_at"
    t.index ["execution_id"], name: "index_devops_container_instances_on_execution_id", unique: true
    t.index ["gitea_workflow_run_id"], name: "index_devops_container_instances_on_gitea_workflow_run_id"
    t.index ["oauth_application_id"], name: "index_devops_container_instances_on_oauth_application_id"
    t.index ["sandbox_mode"], name: "index_devops_container_instances_on_sandbox_mode"
    t.index ["status"], name: "index_devops_container_instances_on_status"
    t.index ["template_id"], name: "index_devops_container_instances_on_template_id"
    t.index ["triggered_by_id"], name: "index_devops_container_instances_on_triggered_by_id"
    t.index ["trust_level"], name: "index_devops_container_instances_on_trust_level"
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
    t.index ["account_id"], name: "index_devops_container_templates_on_account_id"
    t.index ["category"], name: "index_devops_container_templates_on_category"
    t.index ["created_by_id"], name: "index_devops_container_templates_on_created_by_id"
    t.index ["gitea_repo_full_name"], name: "index_devops_container_templates_on_gitea_repo_full_name", unique: true
    t.index ["parent_template_id"], name: "index_devops_container_templates_on_parent_template_id"
    t.index ["slug"], name: "index_devops_container_templates_on_slug", unique: true
    t.index ["status"], name: "index_devops_container_templates_on_status"
    t.index ["visibility"], name: "index_devops_container_templates_on_visibility"
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
    t.index ["activity_type"], name: "index_devops_docker_activities_on_activity_type"
    t.index ["container_id"], name: "index_devops_docker_activities_on_container_id"
    t.index ["created_at"], name: "index_devops_docker_activities_on_created_at"
    t.index ["docker_host_id"], name: "index_devops_docker_activities_on_docker_host_id"
    t.index ["image_id"], name: "index_devops_docker_activities_on_image_id"
    t.index ["status"], name: "index_devops_docker_activities_on_status"
    t.index ["triggered_by_id"], name: "index_devops_docker_activities_on_triggered_by_id"
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
    t.index ["docker_host_id", "docker_container_id"], name: "idx_on_docker_host_id_docker_container_id_dc6d6ec912", unique: true
    t.index ["docker_host_id"], name: "index_devops_docker_containers_on_docker_host_id"
    t.index ["state"], name: "index_devops_docker_containers_on_state"
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
    t.index ["acknowledged"], name: "index_devops_docker_events_on_acknowledged"
    t.index ["acknowledged_by_id"], name: "index_devops_docker_events_on_acknowledged_by_id"
    t.index ["created_at"], name: "index_devops_docker_events_on_created_at"
    t.index ["docker_host_id"], name: "index_devops_docker_events_on_docker_host_id"
    t.index ["severity"], name: "index_devops_docker_events_on_severity"
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
    t.index ["account_id", "name"], name: "index_devops_docker_hosts_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_devops_docker_hosts_on_account_id"
    t.index ["environment"], name: "index_devops_docker_hosts_on_environment"
    t.index ["node_instance_id"], name: "idx_devops_docker_hosts_node_instance_unique", unique: true, where: "(node_instance_id IS NOT NULL)"
    t.index ["slug"], name: "index_devops_docker_hosts_on_slug", unique: true
    t.index ["status"], name: "index_devops_docker_hosts_on_status"
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
    t.index ["docker_host_id", "docker_image_id"], name: "idx_on_docker_host_id_docker_image_id_387571d814", unique: true
    t.index ["docker_host_id"], name: "index_devops_docker_images_on_docker_host_id"
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
    t.index ["account_id", "credential_type"], name: "idx_on_account_id_credential_type_2d753fa9dc"
    t.index ["account_id", "name"], name: "index_devops_integration_credentials_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_devops_integration_credentials_on_account_id"
    t.index ["created_by_user_id"], name: "index_devops_integration_credentials_on_created_by_user_id"
    t.index ["credential_type"], name: "index_devops_integration_credentials_on_credential_type"
    t.index ["expires_at"], name: "index_devops_integration_credentials_on_expires_at"
    t.index ["is_active"], name: "index_devops_integration_credentials_on_is_active"
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
    t.index ["account_id", "created_at"], name: "idx_on_account_id_created_at_502b8265d8"
    t.index ["account_id"], name: "index_devops_integration_executions_on_account_id"
    t.index ["execution_id"], name: "index_devops_integration_executions_on_execution_id", unique: true
    t.index ["integration_instance_id", "status"], name: "idx_on_integration_instance_id_status_b83d64f62b"
    t.index ["integration_instance_id"], name: "index_devops_integration_executions_on_integration_instance_id"
    t.index ["parent_execution_id"], name: "index_devops_integration_executions_on_parent_execution_id"
    t.index ["status"], name: "index_devops_integration_executions_on_status"
    t.index ["trigger_type"], name: "index_devops_integration_executions_on_trigger_type"
    t.index ["triggered_by_user_id"], name: "index_devops_integration_executions_on_triggered_by_user_id"
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
    t.index ["account_id", "slug"], name: "index_devops_integration_instances_on_account_id_and_slug", unique: true
    t.index ["account_id", "status"], name: "index_devops_integration_instances_on_account_id_and_status"
    t.index ["account_id"], name: "index_devops_integration_instances_on_account_id"
    t.index ["created_by_user_id"], name: "index_devops_integration_instances_on_created_by_user_id"
    t.index ["health_status"], name: "index_devops_integration_instances_on_health_status"
    t.index ["integration_credential_id"], name: "idx_on_integration_credential_id_d627796068"
    t.index ["integration_template_id"], name: "index_devops_integration_instances_on_integration_template_id"
    t.index ["status"], name: "index_devops_integration_instances_on_status"
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
    t.index ["account_id"], name: "index_devops_integration_templates_on_account_id"
    t.index ["category"], name: "index_devops_integration_templates_on_category"
    t.index ["integration_type"], name: "index_devops_integration_templates_on_integration_type"
    t.index ["is_active"], name: "index_devops_integration_templates_on_is_active"
    t.index ["is_featured"], name: "index_devops_integration_templates_on_is_featured"
    t.index ["is_public", "is_active"], name: "index_devops_integration_templates_on_is_public_and_is_active"
    t.index ["is_public"], name: "index_devops_integration_templates_on_is_public"
    t.index ["slug"], name: "index_devops_integration_templates_on_slug", unique: true
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
    t.index ["account_id", "name"], name: "index_devops_kubernetes_clusters_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_devops_kubernetes_clusters_on_account_id"
    t.index ["cni_plugin"], name: "index_devops_kubernetes_clusters_on_cni_plugin"
    t.index ["environment"], name: "index_devops_kubernetes_clusters_on_environment"
    t.index ["flavor"], name: "index_devops_kubernetes_clusters_on_flavor"
    t.index ["slug"], name: "index_devops_kubernetes_clusters_on_slug", unique: true
    t.index ["status"], name: "index_devops_kubernetes_clusters_on_status"
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
    t.index ["kubernetes_cluster_id", "name"], name: "idx_on_kubernetes_cluster_id_name_1ff3c49bfa", unique: true
    t.index ["kubernetes_cluster_id"], name: "index_devops_kubernetes_nodes_on_kubernetes_cluster_id"
    t.index ["node_instance_id"], name: "index_devops_kubernetes_nodes_on_node_instance_id", unique: true
    t.index ["role"], name: "index_devops_kubernetes_nodes_on_role"
    t.index ["status"], name: "index_devops_kubernetes_nodes_on_status"
    t.check_constraint "role::text = ANY (ARRAY['server'::character varying::text, 'agent'::character varying::text, 'control_plane'::character varying::text, 'worker'::character varying::text])", name: "chk_kubernetes_nodes_role"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'joining'::character varying::text, 'active'::character varying::text, 'not_ready'::character varying::text, 'disconnected'::character varying::text, 'error'::character varying::text])", name: "chk_kubernetes_nodes_status"
  end

  create_table "devops_pipeline_repositories", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "devops_pipeline_id", null: false
    t.uuid "git_repository_id", null: false
    t.jsonb "overrides", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["devops_pipeline_id", "git_repository_id"], name: "idx_on_devops_pipeline_id_git_repository_id_3f5298c9af", unique: true
    t.index ["devops_pipeline_id"], name: "index_devops_pipeline_repositories_on_devops_pipeline_id"
    t.index ["git_repository_id"], name: "index_devops_pipeline_repositories_on_git_repository_id"
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
    t.index ["devops_pipeline_id", "run_number"], name: "idx_on_devops_pipeline_id_run_number_fa0f448054", unique: true
    t.index ["devops_pipeline_id", "status"], name: "index_devops_pipeline_runs_on_devops_pipeline_id_and_status"
    t.index ["devops_pipeline_id"], name: "index_devops_pipeline_runs_on_devops_pipeline_id"
    t.index ["external_run_id"], name: "index_devops_pipeline_runs_on_external_run_id"
    t.index ["triggered_by_id"], name: "index_devops_pipeline_runs_on_triggered_by_id"
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
    t.index ["devops_pipeline_id", "name"], name: "index_devops_pipeline_steps_on_devops_pipeline_id_and_name", unique: true
    t.index ["devops_pipeline_id", "position"], name: "index_devops_pipeline_steps_on_devops_pipeline_id_and_position"
    t.index ["devops_pipeline_id"], name: "index_devops_pipeline_steps_on_devops_pipeline_id"
    t.index ["shared_prompt_template_id"], name: "index_devops_pipeline_steps_on_shared_prompt_template_id"
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
    t.index ["account_id"], name: "index_devops_pipeline_templates_on_account_id"
    t.index ["category"], name: "index_devops_pipeline_templates_on_category"
    t.index ["created_by_user_id"], name: "index_devops_pipeline_templates_on_created_by_user_id"
    t.index ["is_featured"], name: "index_devops_pipeline_templates_on_is_featured"
    t.index ["is_public"], name: "index_devops_pipeline_templates_on_is_public"
    t.index ["slug"], name: "index_devops_pipeline_templates_on_slug", unique: true
    t.index ["source_pipeline_id"], name: "index_devops_pipeline_templates_on_source_pipeline_id"
    t.index ["status"], name: "index_devops_pipeline_templates_on_status"
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
    t.index ["account_id", "is_active"], name: "index_devops_pipelines_on_account_id_and_is_active"
    t.index ["account_id", "pipeline_type"], name: "index_devops_pipelines_on_account_id_and_pipeline_type"
    t.index ["account_id", "slug"], name: "index_devops_pipelines_on_account_id_and_slug", unique: true
    t.index ["account_id"], name: "index_devops_pipelines_on_account_id"
    t.index ["ai_provider_id"], name: "index_devops_pipelines_on_ai_provider_id"
    t.index ["created_by_id"], name: "index_devops_pipelines_on_created_by_id"
    t.index ["devops_provider_id"], name: "index_devops_pipelines_on_devops_provider_id"
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
    t.index ["account_id"], name: "index_devops_port_allocations_on_account_id"
    t.index ["allocatable_type", "allocatable_id"], name: "idx_on_allocatable_type_allocatable_id_c8c893a39c"
    t.index ["host_identifier", "port", "protocol"], name: "idx_port_allocations_unique_active", unique: true, where: "((status)::text = 'active'::text)"
    t.index ["status"], name: "index_devops_port_allocations_on_status"
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
    t.index ["account_id", "name"], name: "index_devops_providers_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_devops_providers_on_account_id"
    t.index ["created_by_id"], name: "index_devops_providers_on_created_by_id"
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
    t.index ["account_id"], name: "index_devops_resource_quotas_on_account_id", unique: true
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
    t.index ["created_by_id"], name: "index_devops_schedules_on_created_by_id"
    t.index ["devops_pipeline_id", "is_active"], name: "index_devops_schedules_on_devops_pipeline_id_and_is_active"
    t.index ["devops_pipeline_id"], name: "index_devops_schedules_on_devops_pipeline_id"
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
    t.index ["account_id", "name"], name: "index_devops_secret_references_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_devops_secret_references_on_account_id"
    t.index ["created_by_id"], name: "index_devops_secret_references_on_created_by_id"
    t.index ["expires_at"], name: "index_devops_secret_references_on_expires_at", where: "(expires_at IS NOT NULL)"
    t.index ["secret_type"], name: "index_devops_secret_references_on_secret_type"
    t.index ["vault_path"], name: "index_devops_secret_references_on_vault_path"
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
    t.index ["recipient_user_id"], name: "index_devops_step_approval_tokens_on_recipient_user_id"
    t.index ["responded_by_id"], name: "index_devops_step_approval_tokens_on_responded_by_id"
    t.index ["status", "expires_at"], name: "idx_approval_tokens_pending_expiry", where: "((status)::text = 'pending'::text)"
    t.index ["step_execution_id", "status"], name: "idx_on_step_execution_id_status_4ffebb904a"
    t.index ["step_execution_id"], name: "index_devops_step_approval_tokens_on_step_execution_id"
    t.index ["token_digest"], name: "index_devops_step_approval_tokens_on_token_digest", unique: true
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
    t.index ["devops_pipeline_run_id", "devops_pipeline_step_id"], name: "idx_on_devops_pipeline_run_id_devops_pipeline_step__ce454fe6dd", unique: true
    t.index ["devops_pipeline_run_id"], name: "index_devops_step_executions_on_devops_pipeline_run_id"
    t.index ["devops_pipeline_step_id"], name: "index_devops_step_executions_on_devops_pipeline_step_id"
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
    t.index ["account_id", "name"], name: "index_devops_swarm_clusters_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_devops_swarm_clusters_on_account_id"
    t.index ["environment"], name: "index_devops_swarm_clusters_on_environment"
    t.index ["slug"], name: "index_devops_swarm_clusters_on_slug", unique: true
    t.index ["status"], name: "index_devops_swarm_clusters_on_status"
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
    t.index ["cluster_id"], name: "index_devops_swarm_deployments_on_cluster_id"
    t.index ["created_at"], name: "index_devops_swarm_deployments_on_created_at"
    t.index ["deployment_type"], name: "index_devops_swarm_deployments_on_deployment_type"
    t.index ["service_id"], name: "index_devops_swarm_deployments_on_service_id"
    t.index ["stack_id"], name: "index_devops_swarm_deployments_on_stack_id"
    t.index ["status"], name: "index_devops_swarm_deployments_on_status"
    t.index ["triggered_by_id"], name: "index_devops_swarm_deployments_on_triggered_by_id"
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
    t.index ["acknowledged"], name: "index_devops_swarm_events_on_acknowledged"
    t.index ["acknowledged_by_id"], name: "index_devops_swarm_events_on_acknowledged_by_id"
    t.index ["cluster_id"], name: "index_devops_swarm_events_on_cluster_id"
    t.index ["created_at"], name: "index_devops_swarm_events_on_created_at"
    t.index ["event_type"], name: "index_devops_swarm_events_on_event_type"
    t.index ["severity"], name: "index_devops_swarm_events_on_severity"
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
    t.index ["cluster_id", "docker_node_id"], name: "index_devops_swarm_nodes_on_cluster_id_and_docker_node_id", unique: true
    t.index ["cluster_id"], name: "index_devops_swarm_nodes_on_cluster_id"
    t.index ["role"], name: "index_devops_swarm_nodes_on_role"
    t.index ["status"], name: "index_devops_swarm_nodes_on_status"
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
    t.index ["cluster_id", "docker_service_id"], name: "idx_on_cluster_id_docker_service_id_1f25f31d9c", unique: true
    t.index ["cluster_id"], name: "index_devops_swarm_services_on_cluster_id"
    t.index ["service_name"], name: "index_devops_swarm_services_on_service_name"
    t.index ["stack_id"], name: "index_devops_swarm_services_on_stack_id"
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
    t.index ["cluster_id", "name"], name: "index_devops_swarm_stacks_on_cluster_id_and_name", unique: true
    t.index ["cluster_id"], name: "index_devops_swarm_stacks_on_cluster_id"
    t.index ["slug"], name: "index_devops_swarm_stacks_on_slug"
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
    t.index ["email_type"], name: "index_email_deliveries_on_email_type"
    t.index ["external_id"], name: "idx_email_deliveries_on_external_id_unique", unique: true, where: "(external_id IS NOT NULL)"
    t.index ["recipient_email"], name: "index_email_deliveries_on_recipient_email"
    t.index ["sent_at"], name: "index_email_deliveries_on_sent_at"
    t.index ["status"], name: "index_email_deliveries_on_status"
    t.index ["user_id"], name: "index_email_deliveries_on_user_id"
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
    t.index ["account_id", "name"], name: "index_external_agents_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_external_agents_on_account_id"
    t.index ["agent_card_url"], name: "index_external_agents_on_agent_card_url"
    t.index ["capabilities"], name: "index_external_agents_on_capabilities", using: :gin
    t.index ["created_by_id"], name: "index_external_agents_on_created_by_id"
    t.index ["skills"], name: "index_external_agents_on_skills", using: :gin
    t.index ["slug"], name: "index_external_agents_on_slug", unique: true, where: "(slug IS NOT NULL)"
    t.index ["status"], name: "index_external_agents_on_status"
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
    t.string "outbound_token_encrypted"
    t.text "public_key"
    t.integer "request_count", default: 0
    t.string "status", default: "pending"
    t.jsonb "tls_config", default: {}
    t.integer "trust_level", default: 1
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_federation_partners_on_account_id_and_status"
    t.index ["account_id"], name: "index_federation_partners_on_account_id"
    t.index ["approved_by_id"], name: "index_federation_partners_on_approved_by_id"
    t.index ["created_by_id"], name: "index_federation_partners_on_created_by_id"
    t.index ["organization_id"], name: "index_federation_partners_on_organization_id", unique: true
    t.index ["status"], name: "index_federation_partners_on_status"
    t.index ["trust_level"], name: "index_federation_partners_on_trust_level"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'active'::character varying::text, 'suspended'::character varying::text, 'revoked'::character varying::text])", name: "federation_partners_status_check"
    t.check_constraint "trust_level >= 1 AND trust_level <= 5", name: "federation_partners_trust_check"
  end

  create_table "file_bundles", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "bundle_type", default: "mixed", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.uuid "mission_id"
    t.string "name", null: false
    t.uuid "primary_object_id"
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_file_bundles_on_account_id_and_status"
    t.index ["account_id"], name: "index_file_bundles_on_account_id"
    t.index ["created_by_id"], name: "index_file_bundles_on_created_by_id"
    t.index ["mission_id"], name: "index_file_bundles_on_mission_id"
    t.index ["primary_object_id"], name: "index_file_bundles_on_primary_object_id"
  end

  create_table "file_object_tags", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.uuid "file_object_id", null: false
    t.uuid "file_tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_file_object_tags_on_account_id"
    t.index ["file_object_id", "file_tag_id"], name: "index_file_object_tags_on_file_object_id_and_file_tag_id", unique: true
    t.index ["file_object_id"], name: "index_file_object_tags_on_file_object_id"
    t.index ["file_tag_id"], name: "index_file_object_tags_on_file_tag_id"
  end

  create_table "file_objects", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "access_permissions", default: {}
    t.uuid "account_id", null: false
    t.uuid "attachable_id"
    t.string "attachable_type"
    t.uuid "bundle_id"
    t.integer "bundle_position"
    t.string "bundle_role"
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
    t.index ["account_id", "category"], name: "index_file_objects_on_account_id_and_category"
    t.index ["account_id", "created_at"], name: "index_file_objects_on_account_id_and_created_at"
    t.index ["account_id", "file_type"], name: "index_file_objects_on_account_id_and_file_type"
    t.index ["account_id", "filename"], name: "index_file_objects_on_account_id_and_filename"
    t.index ["account_id", "is_latest_version"], name: "index_file_objects_on_account_id_and_is_latest_version"
    t.index ["account_id", "visibility"], name: "index_file_objects_on_account_id_and_visibility"
    t.index ["account_id"], name: "index_file_objects_on_account_id"
    t.index ["attachable_type", "attachable_id"], name: "index_file_objects_on_attachable_type_and_attachable_id"
    t.index ["bundle_id", "bundle_position"], name: "index_file_objects_on_bundle_id_and_bundle_position"
    t.index ["bundle_id"], name: "index_file_objects_on_bundle_id"
    t.index ["checksum_sha256"], name: "index_file_objects_on_checksum_sha256"
    t.index ["deleted_at"], name: "index_file_objects_on_deleted_at"
    t.index ["deleted_by_id"], name: "index_file_objects_on_deleted_by_id"
    t.index ["expires_at"], name: "index_file_objects_on_expires_at", where: "(expires_at IS NOT NULL)"
    t.index ["file_storage_id", "storage_key"], name: "index_file_objects_on_file_storage_id_and_storage_key", unique: true
    t.index ["file_storage_id"], name: "index_file_objects_on_file_storage_id"
    t.index ["metadata"], name: "index_file_objects_on_metadata", using: :gin
    t.index ["parent_file_id"], name: "index_file_objects_on_parent_file_id"
    t.index ["processing_status"], name: "index_file_objects_on_processing_status"
    t.index ["uploaded_by_id"], name: "index_file_objects_on_uploaded_by_id"
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
    t.index ["account_id"], name: "index_file_processing_jobs_on_account_id"
    t.index ["created_at"], name: "index_file_processing_jobs_on_created_at"
    t.index ["file_object_id"], name: "index_file_processing_jobs_on_file_object_id"
    t.index ["job_type"], name: "index_file_processing_jobs_on_job_type"
    t.index ["priority"], name: "index_file_processing_jobs_on_priority"
    t.index ["status"], name: "index_file_processing_jobs_on_status"
    t.check_constraint "job_type::text = ANY (ARRAY['thumbnail'::character varying::text, 'resize'::character varying::text, 'convert'::character varying::text, 'scan'::character varying::text, 'ocr'::character varying::text, 'metadata_extract'::character varying::text, 'compress'::character varying::text, 'watermark'::character varying::text, 'transform'::character varying::text, 'video_processing'::character varying::text, 'audio_processing'::character varying::text, 'video_stitching'::character varying::text, 'document_generation'::character varying::text])", name: "file_processing_jobs_job_type_check"
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
    t.index ["account_id"], name: "index_file_shares_on_account_id"
    t.index ["created_at"], name: "index_file_shares_on_created_at"
    t.index ["created_by_id"], name: "index_file_shares_on_created_by_id"
    t.index ["expires_at"], name: "index_file_shares_on_expires_at", where: "(expires_at IS NOT NULL)"
    t.index ["file_object_id"], name: "index_file_shares_on_file_object_id"
    t.index ["share_token"], name: "index_file_shares_on_share_token", unique: true
    t.index ["status"], name: "index_file_shares_on_status"
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
    t.index ["account_id", "name"], name: "index_file_storages_on_account_id_and_name", unique: true
    t.index ["account_id", "provider_type"], name: "index_file_storages_on_account_id_and_provider_type"
    t.index ["account_id", "status"], name: "index_file_storages_on_account_id_and_status"
    t.index ["account_id"], name: "index_file_storages_on_account_id"
    t.index ["configuration"], name: "index_file_storages_on_configuration", using: :gin
    t.index ["health_status"], name: "index_file_storages_on_health_status"
    t.index ["node_mount_capable"], name: "index_file_storages_node_mount_capable_true", where: "(node_mount_capable = true)"
    t.index ["priority"], name: "index_file_storages_on_priority"
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
    t.index ["account_id", "name"], name: "index_file_tags_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_file_tags_on_account_id"
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
    t.index ["account_id", "created_at"], name: "index_file_versions_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_file_versions_on_account_id"
    t.index ["created_by_id"], name: "index_file_versions_on_created_by_id"
    t.index ["deleted_at"], name: "index_file_versions_on_deleted_at"
    t.index ["file_object_id", "version_number"], name: "index_file_versions_on_file_object_id_and_version_number", unique: true
    t.index ["file_object_id"], name: "index_file_versions_on_file_object_id"
    t.index ["storage_key"], name: "index_file_versions_on_storage_key"
  end

  create_table "flipper_features", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_flipper_features_on_key", unique: true
  end

  create_table "flipper_gates", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "feature_key", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["feature_key", "key", "value"], name: "index_flipper_gates_on_feature_key_and_key_and_value", unique: true
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
    t.index ["account_id"], name: "index_git_pipeline_approvals_on_account_id"
    t.index ["expires_at"], name: "index_git_pipeline_approvals_on_expires_at"
    t.index ["git_pipeline_id", "gate_name"], name: "index_git_pipeline_approvals_on_git_pipeline_id_and_gate_name", unique: true
    t.index ["git_pipeline_id"], name: "index_git_pipeline_approvals_on_git_pipeline_id"
    t.index ["requested_by_id"], name: "index_git_pipeline_approvals_on_requested_by_id"
    t.index ["responded_by_id"], name: "index_git_pipeline_approvals_on_responded_by_id"
    t.index ["status"], name: "index_git_pipeline_approvals_on_status"
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
    t.index ["account_id", "created_at"], name: "index_git_pipeline_jobs_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_git_pipeline_jobs_on_account_id"
    t.index ["conclusion"], name: "index_git_pipeline_jobs_on_conclusion"
    t.index ["git_pipeline_id", "external_id"], name: "index_git_pipeline_jobs_on_git_pipeline_id_and_external_id", unique: true
    t.index ["git_pipeline_id"], name: "index_git_pipeline_jobs_on_git_pipeline_id"
    t.index ["runner_name"], name: "index_git_pipeline_jobs_on_runner_name"
    t.index ["status"], name: "index_git_pipeline_jobs_on_status"
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
    t.index ["account_id"], name: "index_git_pipeline_schedules_on_account_id"
    t.index ["created_by_id"], name: "index_git_pipeline_schedules_on_created_by_id"
    t.index ["git_repository_id", "name"], name: "index_git_pipeline_schedules_on_git_repository_id_and_name", unique: true
    t.index ["git_repository_id"], name: "index_git_pipeline_schedules_on_git_repository_id"
    t.index ["is_active"], name: "index_git_pipeline_schedules_on_is_active"
    t.index ["last_pipeline_id"], name: "index_git_pipeline_schedules_on_last_pipeline_id"
    t.index ["next_run_at"], name: "index_git_pipeline_schedules_on_next_run_at"
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
    t.index ["account_id", "created_at"], name: "index_git_pipelines_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_git_pipelines_on_account_id"
    t.index ["conclusion"], name: "index_git_pipelines_on_conclusion"
    t.index ["created_at"], name: "index_git_pipelines_on_created_at"
    t.index ["git_repository_id", "external_id"], name: "index_git_pipelines_on_git_repository_id_and_external_id", unique: true
    t.index ["git_repository_id"], name: "index_git_pipelines_on_git_repository_id"
    t.index ["sha"], name: "index_git_pipelines_on_sha"
    t.index ["status"], name: "index_git_pipelines_on_status"
    t.index ["trigger_event"], name: "index_git_pipelines_on_trigger_event"
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
    t.index ["account_id", "git_provider_id"], name: "idx_on_account_id_git_provider_id_d749eaa17b"
    t.index ["account_id", "is_default"], name: "index_git_provider_credentials_on_account_id_and_is_default"
    t.index ["account_id"], name: "index_git_provider_credentials_on_account_id"
    t.index ["auth_type"], name: "index_git_provider_credentials_on_auth_type"
    t.index ["consecutive_failures"], name: "index_git_provider_credentials_on_consecutive_failures"
    t.index ["git_provider_id"], name: "index_git_provider_credentials_on_git_provider_id"
    t.index ["is_active"], name: "index_git_provider_credentials_on_is_active"
    t.index ["user_id"], name: "index_git_provider_credentials_on_user_id"
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
    t.index ["account_id"], name: "index_git_providers_on_account_id"
    t.index ["capabilities"], name: "index_git_providers_on_capabilities", using: :gin
    t.index ["is_active"], name: "index_git_providers_on_is_active"
    t.index ["priority_order"], name: "index_git_providers_on_priority_order"
    t.index ["provider_type"], name: "index_git_providers_on_provider_type"
    t.index ["slug"], name: "index_git_providers_on_slug", unique: true
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
    t.index ["account_id", "full_name"], name: "index_git_repositories_on_account_id_and_full_name", unique: true
    t.index ["account_id"], name: "index_git_repositories_on_account_id"
    t.index ["devops_provider_id"], name: "index_git_repositories_on_devops_provider_id"
    t.index ["external_id"], name: "index_git_repositories_on_external_id"
    t.index ["git_provider_credential_id"], name: "index_git_repositories_on_git_provider_credential_id"
    t.index ["is_active"], name: "index_git_repositories_on_is_active"
    t.index ["is_private"], name: "index_git_repositories_on_is_private"
    t.index ["last_synced_at"], name: "index_git_repositories_on_last_synced_at"
    t.index ["origin"], name: "index_git_repositories_on_origin"
    t.index ["owner"], name: "index_git_repositories_on_owner"
    t.index ["topics"], name: "index_git_repositories_on_topics", using: :gin
    t.index ["webhook_configured"], name: "index_git_repositories_on_webhook_configured"
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
    t.index ["account_id"], name: "index_git_runners_on_account_id"
    t.index ["busy"], name: "index_git_runners_on_busy"
    t.index ["git_provider_credential_id", "external_id"], name: "idx_on_git_provider_credential_id_external_id_93f7c573c0", unique: true
    t.index ["git_provider_credential_id"], name: "index_git_runners_on_git_provider_credential_id"
    t.index ["git_repository_id"], name: "index_git_runners_on_git_repository_id"
    t.index ["last_seen_at"], name: "index_git_runners_on_last_seen_at"
    t.index ["runner_scope"], name: "index_git_runners_on_runner_scope"
    t.index ["status"], name: "index_git_runners_on_status"
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
    t.index ["account_id", "created_at"], name: "index_git_webhook_events_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_git_webhook_events_on_account_id"
    t.index ["created_at"], name: "index_git_webhook_events_on_created_at"
    t.index ["delivery_id"], name: "index_git_webhook_events_on_delivery_id"
    t.index ["event_type"], name: "index_git_webhook_events_on_event_type"
    t.index ["git_provider_id"], name: "index_git_webhook_events_on_git_provider_id"
    t.index ["git_repository_id", "event_type"], name: "index_git_webhook_events_on_git_repository_id_and_event_type"
    t.index ["git_repository_id"], name: "index_git_webhook_events_on_git_repository_id"
    t.index ["status", "retry_count"], name: "index_git_webhook_events_on_status_and_retry_count"
    t.index ["status"], name: "index_git_webhook_events_on_status"
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
    t.index ["ended_at"], name: "index_impersonation_sessions_on_ended_at"
    t.index ["impersonated_user_id"], name: "index_impersonation_sessions_on_impersonated_user_id"
    t.index ["impersonator_id"], name: "index_impersonation_sessions_on_impersonator_id"
    t.index ["session_token"], name: "index_impersonation_sessions_on_session_token", unique: true
    t.index ["started_at"], name: "index_impersonation_sessions_on_started_at"
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
    t.index ["account_id"], name: "index_invitations_on_account_id"
    t.index ["email", "account_id"], name: "index_invitations_on_email_and_account_id", unique: true
    t.index ["expires_at"], name: "index_invitations_on_expires_at"
    t.index ["inviter_id"], name: "index_invitations_on_inviter_id"
    t.index ["role_names"], name: "index_invitations_on_role_names", using: :gin
    t.index ["status"], name: "index_invitations_on_status"
    t.index ["token_digest"], name: "index_invitations_on_token_digest", unique: true
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
    t.index ["expires_at"], name: "index_jwt_blacklists_on_expires_at"
    t.index ["jti", "expires_at"], name: "index_jwt_blacklists_on_jti_and_expires_at"
    t.index ["jti"], name: "index_jwt_blacklists_on_jti", unique: true
    t.index ["user_id", "user_blacklist"], name: "index_jwt_blacklists_on_user_id_and_user_blacklist"
  end

  create_table "knowledge_base_article_tags", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "article_id", null: false
    t.datetime "created_at", null: false
    t.uuid "tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["article_id", "tag_id"], name: "index_knowledge_base_article_tags_on_article_id_and_tag_id", unique: true
    t.index ["tag_id"], name: "index_knowledge_base_article_tags_on_tag_id"
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
    t.index ["article_id", "viewed_at"], name: "index_knowledge_base_article_views_on_article_id_and_viewed_at"
    t.index ["read_to_end"], name: "index_knowledge_base_article_views_on_read_to_end"
    t.index ["session_id"], name: "index_knowledge_base_article_views_on_session_id"
    t.index ["user_id"], name: "index_knowledge_base_article_views_on_user_id"
    t.index ["viewed_at"], name: "index_knowledge_base_article_views_on_viewed_at"
    t.check_constraint "reading_time_seconds IS NULL OR reading_time_seconds >= 0", name: "valid_kb_reading_time_seconds"
  end

  create_table "knowledge_base_articles", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.uuid "author_id"
    t.uuid "category_id", null: false
    t.uuid "cloned_from_id"
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
    t.jsonb "model_requirements", default: {}, null: false
    t.integer "not_helpful_count", default: 0
    t.datetime "published_at"
    t.integer "reading_time_minutes"
    t.tsvector "search_vector"
    t.string "slug", limit: 255, null: false
    t.integer "sort_order", default: 0
    t.string "source_key", limit: 255
    t.jsonb "source_snapshot", default: {}, null: false
    t.string "source_version"
    t.string "status", limit: 50, default: "draft"
    t.string "title", limit: 255, null: false
    t.datetime "updated_at", null: false
    t.integer "view_count", default: 0
    t.integer "views_count", default: 0
    t.index ["account_id", "slug"], name: "index_knowledge_base_articles_on_account_id_and_slug", unique: true, where: "(account_id IS NOT NULL)"
    t.index ["account_id"], name: "index_knowledge_base_articles_on_account_id"
    t.index ["author_id"], name: "index_knowledge_base_articles_on_author_id"
    t.index ["category_id"], name: "index_knowledge_base_articles_on_category_id"
    t.index ["cloned_from_id"], name: "index_knowledge_base_articles_on_cloned_from_id"
    t.index ["helpfulness_score"], name: "index_knowledge_base_articles_on_helpfulness_score"
    t.index ["is_featured"], name: "index_knowledge_base_articles_on_is_featured"
    t.index ["is_public"], name: "index_knowledge_base_articles_on_is_public"
    t.index ["last_edited_by_id"], name: "index_knowledge_base_articles_on_last_edited_by_id"
    t.index ["published_at"], name: "index_knowledge_base_articles_on_published_at"
    t.index ["search_vector"], name: "idx_knowledge_base_articles_on_search_vector", using: :gin
    t.index ["slug"], name: "index_knowledge_base_articles_on_slug_global", unique: true, where: "(account_id IS NULL)"
    t.index ["source_key"], name: "index_knowledge_base_articles_on_source_key"
    t.index ["status"], name: "index_knowledge_base_articles_on_status"
    t.index ["view_count"], name: "index_knowledge_base_articles_on_view_count"
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
    t.index ["article_id"], name: "index_knowledge_base_attachments_on_article_id"
    t.index ["download_count"], name: "index_knowledge_base_attachments_on_download_count"
    t.index ["filename"], name: "index_knowledge_base_attachments_on_filename"
    t.index ["uploaded_by_id"], name: "index_knowledge_base_attachments_on_uploaded_by_id"
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
    t.index ["is_active"], name: "index_knowledge_base_categories_on_is_active"
    t.index ["is_public"], name: "index_knowledge_base_categories_on_is_public"
    t.index ["parent_id"], name: "index_knowledge_base_categories_on_parent_id"
    t.index ["slug"], name: "index_knowledge_base_categories_on_slug", unique: true
    t.index ["sort_order"], name: "index_knowledge_base_categories_on_sort_order"
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
    t.index ["article_id", "status"], name: "index_knowledge_base_comments_on_article_id_and_status"
    t.index ["author_id"], name: "index_knowledge_base_comments_on_author_id"
    t.index ["created_at"], name: "index_knowledge_base_comments_on_created_at"
    t.index ["is_helpful_vote"], name: "index_knowledge_base_comments_on_is_helpful_vote"
    t.index ["parent_id"], name: "index_knowledge_base_comments_on_parent_id"
    t.index ["status"], name: "index_knowledge_base_comments_on_status"
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
    t.index ["is_active"], name: "index_knowledge_base_tags_on_is_active"
    t.index ["name"], name: "index_knowledge_base_tags_on_name", unique: true
    t.index ["slug"], name: "index_knowledge_base_tags_on_slug", unique: true
    t.index ["usage_count"], name: "index_knowledge_base_tags_on_usage_count"
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
    t.index ["action"], name: "index_knowledge_base_workflows_on_action"
    t.index ["article_id", "created_at"], name: "index_knowledge_base_workflows_on_article_id_and_created_at"
    t.index ["created_at"], name: "index_knowledge_base_workflows_on_created_at"
    t.index ["from_status"], name: "index_knowledge_base_workflows_on_from_status"
    t.index ["to_status"], name: "index_knowledge_base_workflows_on_to_status"
    t.index ["user_id"], name: "index_knowledge_base_workflows_on_user_id"
    t.check_constraint "action::text = ANY (ARRAY['create'::character varying::text, 'edit'::character varying::text, 'publish'::character varying::text, 'unpublish'::character varying::text, 'archive'::character varying::text, 'review'::character varying::text])", name: "valid_kb_workflow_action"
  end

  create_table "marketing_campaign_contents", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.boolean "ai_generated", default: false
    t.datetime "approved_at"
    t.uuid "approved_by_id"
    t.text "body"
    t.uuid "campaign_id", null: false
    t.string "channel", null: false
    t.datetime "created_at", null: false
    t.string "cta_text"
    t.string "cta_url"
    t.jsonb "media_urls", default: []
    t.jsonb "platform_specific", default: {}
    t.string "preview_text"
    t.string "status", default: "draft"
    t.string "subject"
    t.datetime "updated_at", null: false
    t.string "variant_name", default: "default"
    t.index ["approved_by_id"], name: "index_marketing_campaign_contents_on_approved_by_id"
    t.index ["campaign_id", "channel", "variant_name"], name: "idx_on_campaign_id_channel_variant_name_f72ea82ea6", unique: true
    t.index ["campaign_id"], name: "index_marketing_campaign_contents_on_campaign_id"
    t.index ["channel"], name: "index_marketing_campaign_contents_on_channel"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'approved'::character varying::text, 'rejected'::character varying::text])", name: "marketing_contents_status_check"
  end

  create_table "marketing_campaign_email_lists", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "campaign_id", null: false
    t.datetime "created_at", null: false
    t.uuid "email_list_id", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "email_list_id"], name: "idx_on_campaign_id_email_list_id_536fad5477", unique: true
    t.index ["campaign_id"], name: "index_marketing_campaign_email_lists_on_campaign_id"
    t.index ["email_list_id"], name: "index_marketing_campaign_email_lists_on_email_list_id"
  end

  create_table "marketing_campaign_metrics", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.integer "bounces", default: 0
    t.uuid "campaign_id", null: false
    t.string "channel", null: false
    t.integer "clicks", default: 0
    t.integer "conversions", default: 0
    t.integer "cost_cents", default: 0
    t.datetime "created_at", null: false
    t.jsonb "custom_metrics", default: {}
    t.integer "deliveries", default: 0
    t.integer "engagements", default: 0
    t.integer "impressions", default: 0
    t.date "metric_date", null: false
    t.integer "opens", default: 0
    t.integer "reach", default: 0
    t.integer "revenue_cents", default: 0
    t.integer "sends", default: 0
    t.integer "unique_opens", default: 0
    t.integer "unsubscribes", default: 0
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "channel", "metric_date"], name: "idx_on_campaign_id_channel_metric_date_7ff1a9ee02", unique: true
    t.index ["campaign_id"], name: "index_marketing_campaign_metrics_on_campaign_id"
    t.index ["metric_date"], name: "index_marketing_campaign_metrics_on_metric_date"
  end

  create_table "marketing_campaigns", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.integer "budget_cents", default: 0
    t.string "campaign_type", null: false
    t.jsonb "channels", default: []
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.string "name", null: false
    t.datetime "paused_at"
    t.datetime "scheduled_at"
    t.jsonb "settings", default: {}
    t.string "slug", null: false
    t.integer "spent_cents", default: 0
    t.datetime "started_at"
    t.string "status", default: "draft"
    t.jsonb "tags", default: []
    t.jsonb "target_audience", default: {}
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_marketing_campaigns_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_marketing_campaigns_on_account_id"
    t.index ["campaign_type"], name: "index_marketing_campaigns_on_campaign_type"
    t.index ["created_by_id"], name: "index_marketing_campaigns_on_created_by_id"
    t.index ["scheduled_at"], name: "index_marketing_campaigns_on_scheduled_at", where: "(scheduled_at IS NOT NULL)"
    t.index ["slug"], name: "index_marketing_campaigns_on_slug", unique: true
    t.index ["status"], name: "index_marketing_campaigns_on_status"
    t.check_constraint "campaign_type::text = ANY (ARRAY['email'::character varying::text, 'social'::character varying::text, 'chat'::character varying::text, 'sms'::character varying::text, 'multi_channel'::character varying::text])", name: "marketing_campaigns_type_check"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'scheduled'::character varying::text, 'active'::character varying::text, 'paused'::character varying::text, 'completed'::character varying::text, 'archived'::character varying::text])", name: "marketing_campaigns_status_check"
  end

  create_table "marketing_content_calendars", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.boolean "all_day", default: false
    t.uuid "campaign_id"
    t.string "color"
    t.datetime "created_at", null: false
    t.string "entry_type", default: "post"
    t.jsonb "metadata", default: {}
    t.string "recurrence_rule"
    t.date "scheduled_date", null: false
    t.time "scheduled_time"
    t.string "status", default: "planned"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "scheduled_date"], name: "idx_on_account_id_scheduled_date_190cb0002e"
    t.index ["account_id"], name: "index_marketing_content_calendars_on_account_id"
    t.index ["campaign_id"], name: "index_marketing_content_calendars_on_campaign_id"
    t.index ["scheduled_date"], name: "index_marketing_content_calendars_on_scheduled_date"
    t.check_constraint "entry_type::text = ANY (ARRAY['post'::character varying::text, 'email'::character varying::text, 'social'::character varying::text, 'event'::character varying::text, 'reminder'::character varying::text])", name: "marketing_calendar_type_check"
    t.check_constraint "status::text = ANY (ARRAY['planned'::character varying::text, 'scheduled'::character varying::text, 'published'::character varying::text, 'cancelled'::character varying::text])", name: "marketing_calendar_status_check"
  end

  create_table "marketing_email_lists", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.boolean "double_opt_in", default: true
    t.jsonb "dynamic_filter", default: {}
    t.string "list_type", default: "standard"
    t.string "name", null: false
    t.string "slug", null: false
    t.integer "subscriber_count", default: 0
    t.datetime "updated_at", null: false
    t.text "welcome_email_body"
    t.string "welcome_email_subject"
    t.index ["account_id", "slug"], name: "index_marketing_email_lists_on_account_id_and_slug", unique: true
    t.index ["account_id"], name: "index_marketing_email_lists_on_account_id"
    t.index ["list_type"], name: "index_marketing_email_lists_on_list_type"
    t.check_constraint "list_type::text = ANY (ARRAY['standard'::character varying::text, 'dynamic'::character varying::text, 'segment'::character varying::text])", name: "marketing_email_lists_type_check"
  end

  create_table "marketing_email_subscribers", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.integer "bounce_count", default: 0
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.jsonb "custom_fields", default: {}
    t.string "email", null: false
    t.uuid "email_list_id", null: false
    t.string "first_name"
    t.string "last_name"
    t.jsonb "preferences", default: {}
    t.string "source"
    t.string "status", default: "pending"
    t.datetime "subscribed_at"
    t.jsonb "tags", default: []
    t.datetime "unsubscribed_at"
    t.datetime "updated_at", null: false
    t.index ["confirmation_token"], name: "index_marketing_email_subscribers_on_confirmation_token", unique: true, where: "(confirmation_token IS NOT NULL)"
    t.index ["email"], name: "index_marketing_email_subscribers_on_email"
    t.index ["email_list_id", "email"], name: "index_marketing_email_subscribers_on_email_list_id_and_email", unique: true
    t.index ["email_list_id"], name: "index_marketing_email_subscribers_on_email_list_id"
    t.index ["status"], name: "index_marketing_email_subscribers_on_status"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'subscribed'::character varying::text, 'unsubscribed'::character varying::text, 'bounced'::character varying::text, 'complained'::character varying::text])", name: "marketing_subscribers_status_check"
  end

  create_table "marketing_social_media_accounts", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "connected_by_id"
    t.datetime "created_at", null: false
    t.string "platform", null: false
    t.string "platform_account_id", null: false
    t.string "platform_username"
    t.integer "post_count", default: 0
    t.integer "rate_limit_remaining"
    t.datetime "rate_limit_reset_at"
    t.jsonb "scopes", default: []
    t.string "status", default: "connected"
    t.datetime "token_expires_at"
    t.datetime "updated_at", null: false
    t.string "vault_path"
    t.index ["account_id", "platform", "platform_account_id"], name: "idx_on_account_id_platform_platform_account_id_235d64ab05", unique: true
    t.index ["account_id"], name: "index_marketing_social_media_accounts_on_account_id"
    t.index ["connected_by_id"], name: "index_marketing_social_media_accounts_on_connected_by_id"
    t.index ["platform"], name: "index_marketing_social_media_accounts_on_platform"
    t.index ["status"], name: "index_marketing_social_media_accounts_on_status"
    t.check_constraint "platform::text = ANY (ARRAY['twitter'::character varying::text, 'linkedin'::character varying::text, 'facebook'::character varying::text, 'instagram'::character varying::text])", name: "marketing_social_platform_check"
    t.check_constraint "status::text = ANY (ARRAY['connected'::character varying::text, 'disconnected'::character varying::text, 'expired'::character varying::text, 'error'::character varying::text])", name: "marketing_social_status_check"
  end

  create_table "marketing_waitlist_signups", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.uuid "converted_account_id"
    t.datetime "converted_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.uuid "email_subscriber_id"
    t.string "ip_address"
    t.jsonb "metadata", default: {}
    t.string "referrer"
    t.string "source"
    t.string "status", default: "pending"
    t.datetime "unsubscribed_at"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["confirmation_token"], name: "index_marketing_waitlist_signups_on_confirmation_token", unique: true, where: "(confirmation_token IS NOT NULL)"
    t.index ["converted_account_id"], name: "index_marketing_waitlist_signups_on_converted_account_id"
    t.index ["email"], name: "index_marketing_waitlist_signups_on_email", unique: true
    t.index ["email_subscriber_id"], name: "index_marketing_waitlist_signups_on_email_subscriber_id"
    t.index ["source"], name: "index_marketing_waitlist_signups_on_source"
    t.index ["status"], name: "index_marketing_waitlist_signups_on_status"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'confirmed'::character varying::text, 'unsubscribed'::character varying::text])", name: "marketing_waitlist_signups_status_check"
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
    t.index ["account_id", "status"], name: "index_mcp_servers_on_account_id_and_status"
    t.index ["account_id"], name: "index_mcp_servers_on_account_id"
    t.index ["auth_type"], name: "index_mcp_servers_on_auth_type"
    t.index ["oauth_state"], name: "index_mcp_servers_on_oauth_state", unique: true, where: "(oauth_state IS NOT NULL)"
    t.index ["oauth_token_expires_at"], name: "index_mcp_servers_on_oauth_token_expires_at"
    t.index ["status"], name: "index_mcp_servers_on_status"
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
    t.string "principal_kind"
    t.uuid "principal_subject_id"
    t.string "protocol_version"
    t.datetime "revoked_at"
    t.string "session_token", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.uuid "user_id"
    t.index ["account_id", "status"], name: "index_mcp_sessions_on_account_id_and_status"
    t.index ["account_id"], name: "index_mcp_sessions_on_account_id"
    t.index ["ai_agent_id"], name: "index_mcp_sessions_on_ai_agent_id"
    t.index ["expires_at"], name: "index_mcp_sessions_on_expires_at"
    t.index ["oauth_application_id"], name: "index_mcp_sessions_on_oauth_application_id"
    t.index ["principal_kind", "principal_subject_id"], name: "index_mcp_sessions_on_principal"
    t.index ["session_token"], name: "index_mcp_sessions_on_session_token", unique: true
    t.index ["user_id", "status"], name: "index_mcp_sessions_on_user_id_and_status"
    t.index ["user_id"], name: "index_mcp_sessions_on_user_id"
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
    t.uuid "user_id"
    t.index ["mcp_tool_id", "created_at"], name: "index_mcp_tool_executions_on_mcp_tool_id_and_created_at"
    t.index ["mcp_tool_id"], name: "index_mcp_tool_executions_on_mcp_tool_id"
    t.index ["user_id", "created_at"], name: "index_mcp_tool_executions_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_mcp_tool_executions_on_user_id"
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
    t.index ["mcp_server_id", "name"], name: "index_mcp_tools_on_mcp_server_id_and_name"
    t.index ["mcp_server_id"], name: "index_mcp_tools_on_mcp_server_id"
    t.index ["permission_level"], name: "index_mcp_tools_on_permission_level"
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
    t.index ["account_id", "created_at"], name: "index_notifications_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_notifications_on_account_id"
    t.index ["category"], name: "index_notifications_on_category"
    t.index ["expires_at"], name: "index_notifications_on_expires_at"
    t.index ["notification_type"], name: "index_notifications_on_notification_type"
    t.index ["priority"], name: "index_notifications_on_priority"
    t.index ["user_id", "created_at"], name: "index_notifications_on_user_id_and_created_at"
    t.index ["user_id", "read_at"], name: "index_notifications_on_user_id_and_read_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
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
    t.index ["application_id"], name: "index_oauth_access_grants_on_application_id"
    t.index ["resource_owner_id"], name: "index_oauth_access_grants_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_grants_on_token", unique: true
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
    t.index ["application_id", "created_at"], name: "index_oauth_access_tokens_on_application_id_and_created_at"
    t.index ["application_id"], name: "index_oauth_access_tokens_on_application_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true
    t.index ["resource_owner_id"], name: "index_oauth_access_tokens_on_resource_owner_id"
    t.index ["revoked_at"], name: "index_oauth_access_tokens_on_revoked_at"
    t.index ["token"], name: "index_oauth_access_tokens_on_token", unique: true
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
    t.index ["owner_id"], name: "index_oauth_applications_on_owner_id"
    t.index ["owner_type", "owner_id"], name: "index_oauth_applications_on_owner_type_and_owner_id"
    t.index ["status"], name: "index_oauth_applications_on_status"
    t.index ["trusted"], name: "index_oauth_applications_on_trusted"
    t.index ["uid"], name: "index_oauth_applications_on_uid", unique: true
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
    t.index ["account_id"], name: "index_pages_on_account_id"
    t.index ["author_id"], name: "index_pages_on_author_id"
    t.index ["is_public"], name: "index_pages_on_is_public"
    t.index ["published_at"], name: "index_pages_on_published_at"
    t.index ["slug"], name: "index_pages_on_slug", unique: true
    t.index ["status"], name: "index_pages_on_status"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'published'::character varying::text, 'archived'::character varying::text])", name: "valid_page_status"
  end

  create_table "password_histories", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "password_digest", null: false
    t.uuid "user_id", null: false
    t.index ["created_at"], name: "index_password_histories_on_created_at"
    t.index ["user_id"], name: "index_password_histories_on_user_id"
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
    t.index ["account_id", "report_type"], name: "index_report_requests_on_account_id_and_report_type"
    t.index ["account_id"], name: "index_report_requests_on_account_id"
    t.index ["expires_at"], name: "index_report_requests_on_expires_at"
    t.index ["requested_at"], name: "index_report_requests_on_requested_at"
    t.index ["requested_by_id"], name: "index_report_requests_on_requested_by_id"
    t.index ["status"], name: "index_report_requests_on_status"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'generating'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'expired'::character varying::text, 'cancelled'::character varying::text])", name: "valid_report_request_status"
  end

  create_table "role_permissions", id: false, force: :cascade do |t|
    t.datetime "granted_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "permission_name", limit: 100, null: false
    t.uuid "role_id", null: false
    t.index ["permission_name"], name: "index_role_permissions_on_permission_name"
    t.index ["role_id", "permission_name"], name: "index_role_permissions_on_role_id_and_permission_name", unique: true
    t.index ["role_id"], name: "index_role_permissions_on_role_id"
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
    t.index ["account_id", "name"], name: "index_roles_on_account_id_and_name", unique: true, where: "(account_id IS NOT NULL)"
    t.index ["account_id"], name: "index_roles_on_account_id"
    t.index ["name"], name: "index_roles_on_name_global", unique: true, where: "(account_id IS NULL)"
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
    t.index ["account_id", "report_type"], name: "index_scheduled_reports_on_account_id_and_report_type"
    t.index ["account_id"], name: "index_scheduled_reports_on_account_id"
    t.index ["created_by_id"], name: "index_scheduled_reports_on_created_by_id"
    t.index ["frequency"], name: "index_scheduled_reports_on_frequency"
    t.index ["is_active"], name: "index_scheduled_reports_on_is_active"
    t.index ["next_run_at"], name: "index_scheduled_reports_on_next_run_at"
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
    t.index ["is_active"], name: "index_scheduled_tasks_on_is_active"
    t.index ["last_run_at"], name: "index_scheduled_tasks_on_last_run_at"
    t.index ["name"], name: "index_scheduled_tasks_on_name", unique: true
    t.index ["next_run_at"], name: "index_scheduled_tasks_on_next_run_at"
    t.index ["task_type"], name: "index_scheduled_tasks_on_task_type"
  end

  create_table "security_secrets", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "scope", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["account_id", "scope", "key"], name: "index_security_secrets_on_account_id_and_scope_and_key", unique: true
    t.index ["account_id"], name: "index_security_secrets_on_account_id"
    t.index ["scope", "key"], name: "index_security_secrets_platform_global_on_scope_and_key", unique: true, where: "(account_id IS NULL)"
  end

  create_table "shared_prompt_templates", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.string "category", null: false
    t.uuid "cloned_from_id"
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.text "description"
    t.string "domain", default: "general", null: false
    t.boolean "is_active", default: true, null: false
    t.boolean "is_system", default: false, null: false
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "model_requirements", default: {}, null: false
    t.string "name", null: false
    t.uuid "parent_template_id"
    t.decimal "rating", precision: 3, scale: 2, default: "0.0"
    t.integer "rating_count", default: 0
    t.string "slug", null: false
    t.string "source_key", limit: 255
    t.jsonb "source_snapshot", default: {}, null: false
    t.string "source_version"
    t.datetime "updated_at", null: false
    t.jsonb "variables", default: [], null: false
    t.integer "version", default: 1, null: false
    t.index ["account_id", "category"], name: "index_shared_prompt_templates_on_account_id_and_category"
    t.index ["account_id", "domain"], name: "index_shared_prompt_templates_on_account_id_and_domain"
    t.index ["account_id", "slug"], name: "index_shared_prompt_templates_on_account_id_and_slug", unique: true, where: "(account_id IS NOT NULL)"
    t.index ["cloned_from_id"], name: "index_shared_prompt_templates_on_cloned_from_id"
    t.index ["created_by_id"], name: "index_shared_prompt_templates_on_created_by_id"
    t.index ["is_active"], name: "index_shared_prompt_templates_on_is_active"
    t.index ["is_system"], name: "index_shared_prompt_templates_on_is_system"
    t.index ["parent_template_id"], name: "index_shared_prompt_templates_on_parent_template_id"
    t.index ["slug"], name: "index_shared_prompt_templates_on_slug_global", unique: true, where: "(account_id IS NULL)"
    t.index ["source_key"], name: "index_shared_prompt_templates_on_source_key"
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
    t.index ["category"], name: "index_site_settings_on_category"
    t.index ["is_public"], name: "index_site_settings_on_is_public"
    t.index ["key"], name: "index_site_settings_on_key", unique: true
    t.index ["setting_type"], name: "index_site_settings_on_setting_type"
    t.check_constraint "setting_type::text = ANY (ARRAY['string'::character varying::text, 'text'::character varying::text, 'integer'::character varying::text, 'boolean'::character varying::text, 'json'::character varying::text, 'array'::character varying::text])", name: "valid_site_setting_type"
  end

  create_table "supply_chain_attestations", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "attestation_id", null: false
    t.string "attestation_type", default: "slsa_provenance", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.jsonb "metadata", default: {}, null: false
    t.uuid "pipeline_run_id"
    t.jsonb "predicate", default: {}, null: false
    t.string "predicate_type", null: false
    t.string "rekor_log_id"
    t.string "rekor_log_url"
    t.datetime "rekor_logged_at"
    t.uuid "sbom_id"
    t.text "signature"
    t.string "signature_algorithm"
    t.string "signature_format", default: "dsse"
    t.uuid "signing_key_id"
    t.integer "slsa_level", default: 1
    t.string "subject_digest", null: false
    t.string "subject_digest_algorithm", default: "sha256", null: false
    t.string "subject_name", null: false
    t.datetime "updated_at", null: false
    t.jsonb "verification_results", default: {}, null: false
    t.string "verification_status", default: "unverified", null: false
    t.datetime "verified_at"
    t.index ["account_id", "attestation_id"], name: "idx_on_account_id_attestation_id_53e3a729e7", unique: true
    t.index ["account_id"], name: "index_supply_chain_attestations_on_account_id"
    t.index ["created_by_id"], name: "index_supply_chain_attestations_on_created_by_id"
    t.index ["pipeline_run_id"], name: "index_supply_chain_attestations_on_pipeline_run_id"
    t.index ["predicate"], name: "idx_attestations_predicate", using: :gin
    t.index ["sbom_id"], name: "index_supply_chain_attestations_on_sbom_id"
    t.index ["signing_key_id"], name: "index_supply_chain_attestations_on_signing_key_id"
    t.index ["subject_digest"], name: "index_supply_chain_attestations_on_subject_digest"
    t.index ["verification_status"], name: "index_supply_chain_attestations_on_verification_status"
    t.check_constraint "attestation_type::text = ANY (ARRAY['slsa_provenance'::character varying::text, 'sbom'::character varying::text, 'vuln_scan'::character varying::text, 'custom'::character varying::text])", name: "check_attestations_type"
    t.check_constraint "slsa_level = ANY (ARRAY[0, 1, 2, 3])", name: "check_attestations_slsa_level"
    t.check_constraint "verification_status::text = ANY (ARRAY['unverified'::character varying::text, 'verified'::character varying::text, 'failed'::character varying::text, 'expired'::character varying::text])", name: "check_attestations_verification_status"
  end

  create_table "supply_chain_attributions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "attribution_url"
    t.string "copyright_holder"
    t.integer "copyright_year"
    t.datetime "created_at", null: false
    t.uuid "license_id"
    t.text "license_text"
    t.jsonb "metadata", default: {}, null: false
    t.text "notice_text"
    t.string "package_name", null: false
    t.string "package_version"
    t.boolean "requires_attribution", default: true, null: false
    t.boolean "requires_license_copy", default: false, null: false
    t.boolean "requires_source_disclosure", default: false, null: false
    t.uuid "sbom_component_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_supply_chain_attributions_on_account_id"
    t.index ["license_id"], name: "index_supply_chain_attributions_on_license_id"
    t.index ["sbom_component_id"], name: "index_supply_chain_attributions_on_sbom_component_id", unique: true
  end

  create_table "supply_chain_build_provenances", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "attestation_id", null: false
    t.jsonb "build_config", default: {}, null: false
    t.integer "build_duration_ms"
    t.datetime "build_finished_at"
    t.datetime "build_started_at"
    t.string "builder_id", null: false
    t.string "builder_version"
    t.datetime "created_at", null: false
    t.jsonb "environment", default: {}, null: false
    t.jsonb "invocation", default: {}, null: false
    t.jsonb "materials", default: [], null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "reproducibility_hash"
    t.datetime "reproducibility_verified_at"
    t.boolean "reproducible", default: false, null: false
    t.string "source_branch"
    t.string "source_commit"
    t.string "source_repository"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_supply_chain_build_provenances_on_account_id"
    t.index ["attestation_id"], name: "index_supply_chain_build_provenances_on_attestation_id", unique: true
    t.index ["builder_id"], name: "index_supply_chain_build_provenances_on_builder_id"
    t.index ["materials"], name: "idx_build_provenance_materials", using: :gin
  end

  create_table "supply_chain_container_images", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "architecture"
    t.uuid "attestation_id"
    t.uuid "base_image_id"
    t.datetime "created_at", null: false
    t.integer "critical_vuln_count", default: 0, null: false
    t.jsonb "deployment_contexts", default: [], null: false
    t.string "digest", null: false
    t.integer "high_vuln_count", default: 0, null: false
    t.boolean "is_deployed", default: false, null: false
    t.boolean "is_signed", default: false, null: false
    t.jsonb "labels", default: {}, null: false
    t.datetime "last_scanned_at"
    t.jsonb "layers", default: [], null: false
    t.integer "low_vuln_count", default: 0, null: false
    t.integer "medium_vuln_count", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "os"
    t.datetime "pushed_at"
    t.string "registry", null: false
    t.string "repository", null: false
    t.uuid "sbom_id"
    t.bigint "size_bytes", default: 0
    t.string "status", default: "unverified", null: false
    t.string "tag"
    t.datetime "updated_at", null: false
    t.index ["account_id", "digest"], name: "index_supply_chain_container_images_on_account_id_and_digest", unique: true
    t.index ["account_id"], name: "index_supply_chain_container_images_on_account_id"
    t.index ["attestation_id"], name: "index_supply_chain_container_images_on_attestation_id"
    t.index ["base_image_id"], name: "index_supply_chain_container_images_on_base_image_id"
    t.index ["is_deployed"], name: "index_supply_chain_container_images_on_is_deployed"
    t.index ["labels"], name: "idx_container_images_labels", using: :gin
    t.index ["registry", "repository", "tag"], name: "idx_on_registry_repository_tag_4733543b97"
    t.index ["sbom_id"], name: "index_supply_chain_container_images_on_sbom_id"
    t.index ["status"], name: "index_supply_chain_container_images_on_status"
    t.check_constraint "status::text = ANY (ARRAY['unverified'::character varying::text, 'verified'::character varying::text, 'quarantined'::character varying::text, 'approved'::character varying::text, 'rejected'::character varying::text])", name: "check_container_images_status"
  end

  create_table "supply_chain_cve_monitors", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.text "description"
    t.jsonb "filters", default: {}, null: false
    t.boolean "is_active", default: true, null: false
    t.datetime "last_run_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "min_severity", default: "medium", null: false
    t.string "name", null: false
    t.datetime "next_run_at"
    t.jsonb "notification_channels", default: [], null: false
    t.string "schedule_cron"
    t.uuid "scope_id"
    t.string "scope_type", default: "account_wide", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_supply_chain_cve_monitors_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_supply_chain_cve_monitors_on_account_id"
    t.index ["created_by_id"], name: "index_supply_chain_cve_monitors_on_created_by_id"
    t.index ["is_active"], name: "index_supply_chain_cve_monitors_on_is_active"
    t.index ["next_run_at"], name: "index_supply_chain_cve_monitors_on_next_run_at"
    t.index ["scope_type", "scope_id"], name: "index_supply_chain_cve_monitors_on_scope_type_and_scope_id"
    t.check_constraint "min_severity::text = ANY (ARRAY['critical'::character varying::text, 'high'::character varying::text, 'medium'::character varying::text, 'low'::character varying::text])", name: "check_cve_monitors_severity"
    t.check_constraint "scope_type::text = ANY (ARRAY['image'::character varying::text, 'repository'::character varying::text, 'account_wide'::character varying::text])", name: "check_cve_monitors_scope"
  end

  create_table "supply_chain_image_policies", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.text "description"
    t.string "enforcement_level", default: "warn", null: false
    t.boolean "is_active", default: true, null: false
    t.jsonb "match_rules", default: {}, null: false
    t.integer "max_critical_vulns"
    t.integer "max_high_vulns"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.string "policy_type", default: "registry_allowlist", null: false
    t.integer "priority", default: 0, null: false
    t.boolean "require_sbom", default: false, null: false
    t.boolean "require_signature", default: false, null: false
    t.jsonb "rules", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_supply_chain_image_policies_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_supply_chain_image_policies_on_account_id"
    t.index ["created_by_id"], name: "index_supply_chain_image_policies_on_created_by_id"
    t.index ["is_active"], name: "index_supply_chain_image_policies_on_is_active"
    t.index ["policy_type"], name: "index_supply_chain_image_policies_on_policy_type"
    t.check_constraint "enforcement_level::text = ANY (ARRAY['log'::character varying::text, 'warn'::character varying::text, 'block'::character varying::text])", name: "check_image_policies_enforcement"
    t.check_constraint "policy_type::text = ANY (ARRAY['registry_allowlist'::character varying::text, 'signature_required'::character varying::text, 'vulnerability_threshold'::character varying::text, 'custom'::character varying::text])", name: "check_image_policies_type"
  end

  create_table "supply_chain_license_detections", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "ai_interpretation", default: {}, null: false
    t.decimal "confidence_score", precision: 5, scale: 4, default: "1.0"
    t.datetime "created_at", null: false
    t.string "detected_license_id"
    t.string "detected_license_name"
    t.string "detection_source", default: "manifest", null: false
    t.string "file_path"
    t.boolean "is_primary", default: true, null: false
    t.uuid "license_id"
    t.text "license_text_snippet"
    t.jsonb "metadata", default: {}, null: false
    t.boolean "requires_review", default: false, null: false
    t.uuid "sbom_component_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_supply_chain_license_detections_on_account_id"
    t.index ["detection_source"], name: "index_supply_chain_license_detections_on_detection_source"
    t.index ["license_id"], name: "index_supply_chain_license_detections_on_license_id"
    t.index ["sbom_component_id"], name: "index_supply_chain_license_detections_on_sbom_component_id"
  end

  create_table "supply_chain_license_policies", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "allowed_licenses", default: [], null: false
    t.boolean "block_copyleft", default: false, null: false
    t.boolean "block_strong_copyleft", default: true, null: false
    t.boolean "block_unknown", default: false, null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.jsonb "denied_licenses", default: [], null: false
    t.text "description"
    t.string "enforcement_level", default: "warn", null: false
    t.jsonb "exception_packages", default: [], null: false
    t.boolean "is_active", default: true, null: false
    t.boolean "is_default", default: false, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.string "policy_type", default: "allowlist", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_supply_chain_license_policies_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_supply_chain_license_policies_on_account_id"
    t.index ["created_by_id"], name: "index_supply_chain_license_policies_on_created_by_id"
    t.index ["is_active"], name: "index_supply_chain_license_policies_on_is_active"
    t.index ["is_default"], name: "idx_license_policies_default", where: "(is_default = true)"
    t.check_constraint "enforcement_level::text = ANY (ARRAY['log'::character varying::text, 'warn'::character varying::text, 'block'::character varying::text])", name: "check_license_policies_enforcement"
    t.check_constraint "policy_type::text = ANY (ARRAY['allowlist'::character varying::text, 'denylist'::character varying::text, 'hybrid'::character varying::text])", name: "check_license_policies_type"
  end

  create_table "supply_chain_license_violations", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "ai_remediation", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "exception_approved_at"
    t.uuid "exception_approved_by_id"
    t.datetime "exception_expires_at"
    t.text "exception_reason"
    t.boolean "exception_requested", default: false, null: false
    t.string "exception_status"
    t.uuid "license_id"
    t.uuid "license_policy_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.uuid "sbom_component_id", null: false
    t.uuid "sbom_id", null: false
    t.string "severity", default: "high", null: false
    t.string "status", default: "open", null: false
    t.datetime "updated_at", null: false
    t.string "violation_type", default: "denied", null: false
    t.index ["account_id", "status"], name: "index_supply_chain_license_violations_on_account_id_and_status"
    t.index ["account_id"], name: "index_supply_chain_license_violations_on_account_id"
    t.index ["exception_approved_by_id"], name: "idx_on_exception_approved_by_id_cfba11f498"
    t.index ["license_id"], name: "index_supply_chain_license_violations_on_license_id"
    t.index ["license_policy_id"], name: "index_supply_chain_license_violations_on_license_policy_id"
    t.index ["sbom_component_id"], name: "index_supply_chain_license_violations_on_sbom_component_id"
    t.index ["sbom_id"], name: "index_supply_chain_license_violations_on_sbom_id"
    t.index ["violation_type"], name: "index_supply_chain_license_violations_on_violation_type"
    t.check_constraint "severity::text = ANY (ARRAY['critical'::character varying::text, 'high'::character varying::text, 'medium'::character varying::text, 'low'::character varying::text])", name: "check_license_violations_severity"
    t.check_constraint "status::text = ANY (ARRAY['open'::character varying::text, 'reviewing'::character varying::text, 'resolved'::character varying::text, 'exception_granted'::character varying::text, 'wont_fix'::character varying::text])", name: "check_license_violations_status"
    t.check_constraint "violation_type::text = ANY (ARRAY['denied'::character varying::text, 'copyleft'::character varying::text, 'incompatible'::character varying::text, 'unknown'::character varying::text, 'expired'::character varying::text])", name: "check_license_violations_type"
  end

  create_table "supply_chain_licenses", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "category", default: "unknown", null: false
    t.jsonb "compatibility", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "detection_patterns", default: [], null: false
    t.boolean "is_copyleft", default: false, null: false
    t.boolean "is_deprecated", default: false, null: false
    t.boolean "is_network_copyleft", default: false, null: false
    t.boolean "is_osi_approved", default: false, null: false
    t.boolean "is_strong_copyleft", default: false, null: false
    t.text "license_text"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.string "spdx_id", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["category"], name: "index_supply_chain_licenses_on_category"
    t.index ["is_copyleft"], name: "index_supply_chain_licenses_on_is_copyleft"
    t.index ["spdx_id"], name: "index_supply_chain_licenses_on_spdx_id", unique: true
    t.check_constraint "category::text = ANY (ARRAY['permissive'::character varying::text, 'copyleft'::character varying::text, 'weak_copyleft'::character varying::text, 'public_domain'::character varying::text, 'proprietary'::character varying::text, 'unknown'::character varying::text])", name: "check_licenses_category"
  end

  create_table "supply_chain_questionnaire_responses", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "access_token", null: false
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.jsonb "metadata", default: {}, null: false
    t.decimal "overall_score", precision: 5, scale: 2
    t.uuid "requested_by_id"
    t.jsonb "responses", default: {}, null: false
    t.text "review_notes"
    t.datetime "reviewed_at"
    t.uuid "reviewed_by_id"
    t.uuid "risk_assessment_id"
    t.jsonb "section_scores", default: {}, null: false
    t.datetime "sent_at"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "submitted_at"
    t.uuid "template_id", null: false
    t.datetime "updated_at", null: false
    t.uuid "vendor_id", null: false
    t.index ["access_token"], name: "index_supply_chain_questionnaire_responses_on_access_token", unique: true
    t.index ["account_id"], name: "index_supply_chain_questionnaire_responses_on_account_id"
    t.index ["requested_by_id"], name: "index_supply_chain_questionnaire_responses_on_requested_by_id"
    t.index ["reviewed_by_id"], name: "index_supply_chain_questionnaire_responses_on_reviewed_by_id"
    t.index ["risk_assessment_id"], name: "idx_on_risk_assessment_id_2f7cfcf19d"
    t.index ["status"], name: "index_supply_chain_questionnaire_responses_on_status"
    t.index ["template_id"], name: "index_supply_chain_questionnaire_responses_on_template_id"
    t.index ["vendor_id", "template_id"], name: "idx_on_vendor_id_template_id_6af666fbfe"
    t.index ["vendor_id"], name: "index_supply_chain_questionnaire_responses_on_vendor_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'in_progress'::character varying::text, 'submitted'::character varying::text, 'reviewed'::character varying::text, 'expired'::character varying::text])", name: "check_questionnaire_responses_status"
  end

  create_table "supply_chain_questionnaire_templates", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.text "description"
    t.boolean "is_active", default: true, null: false
    t.boolean "is_system", default: false, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.jsonb "questions", default: [], null: false
    t.jsonb "sections", default: [], null: false
    t.string "template_type", default: "custom", null: false
    t.datetime "updated_at", null: false
    t.string "version", default: "1.0", null: false
    t.index ["account_id", "name"], name: "idx_questionnaire_templates_account_name", unique: true, where: "(account_id IS NOT NULL)"
    t.index ["account_id"], name: "index_supply_chain_questionnaire_templates_on_account_id"
    t.index ["created_by_id"], name: "index_supply_chain_questionnaire_templates_on_created_by_id"
    t.index ["is_system"], name: "index_supply_chain_questionnaire_templates_on_is_system"
    t.index ["template_type"], name: "index_supply_chain_questionnaire_templates_on_template_type"
    t.check_constraint "template_type::text = ANY (ARRAY['soc2'::character varying::text, 'iso27001'::character varying::text, 'gdpr'::character varying::text, 'hipaa'::character varying::text, 'pci_dss'::character varying::text, 'custom'::character varying::text])", name: "check_questionnaire_templates_type"
  end

  create_table "supply_chain_remediation_plans", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "approval_status", default: "pending"
    t.datetime "approved_at"
    t.uuid "approved_by_id"
    t.boolean "auto_executable", default: false, null: false
    t.jsonb "breaking_changes", default: [], null: false
    t.decimal "confidence_score", precision: 5, scale: 4, default: "0.0"
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.string "generated_pr_url"
    t.jsonb "metadata", default: {}, null: false
    t.string "plan_type", default: "manual", null: false
    t.uuid "sbom_id", null: false
    t.string "status", default: "draft", null: false
    t.text "summary"
    t.jsonb "target_vulnerabilities", default: [], null: false
    t.datetime "updated_at", null: false
    t.jsonb "upgrade_recommendations", default: [], null: false
    t.index ["account_id", "status"], name: "index_supply_chain_remediation_plans_on_account_id_and_status"
    t.index ["account_id"], name: "index_supply_chain_remediation_plans_on_account_id"
    t.index ["approved_by_id"], name: "index_supply_chain_remediation_plans_on_approved_by_id"
    t.index ["created_by_id"], name: "index_supply_chain_remediation_plans_on_created_by_id"
    t.index ["sbom_id"], name: "index_supply_chain_remediation_plans_on_sbom_id"
    t.check_constraint "plan_type::text = ANY (ARRAY['manual'::character varying::text, 'ai_generated'::character varying::text, 'auto_fix'::character varying::text])", name: "check_remediation_plans_type"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'pending_review'::character varying::text, 'approved'::character varying::text, 'rejected'::character varying::text, 'executing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "check_remediation_plans_status"
  end

  create_table "supply_chain_reports", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.text "description"
    t.datetime "expires_at"
    t.string "file_path"
    t.bigint "file_size_bytes"
    t.string "file_url"
    t.string "format", default: "pdf", null: false
    t.datetime "generated_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.jsonb "parameters", default: {}, null: false
    t.string "report_type", null: false
    t.uuid "sbom_id"
    t.string "status", default: "pending", null: false
    t.jsonb "summary", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "report_type"], name: "index_supply_chain_reports_on_account_id_and_report_type"
    t.index ["account_id"], name: "index_supply_chain_reports_on_account_id"
    t.index ["created_at"], name: "index_supply_chain_reports_on_created_at"
    t.index ["created_by_id"], name: "index_supply_chain_reports_on_created_by_id"
    t.index ["sbom_id"], name: "index_supply_chain_reports_on_sbom_id"
    t.index ["status"], name: "index_supply_chain_reports_on_status"
    t.check_constraint "format::text = ANY (ARRAY['pdf'::character varying::text, 'json'::character varying::text, 'csv'::character varying::text, 'html'::character varying::text, 'xml'::character varying::text, 'spdx'::character varying::text, 'cyclonedx'::character varying::text])", name: "check_reports_format"
    t.check_constraint "report_type::text = ANY (ARRAY['sbom_export'::character varying::text, 'vulnerability'::character varying::text, 'vulnerability_report'::character varying::text, 'license_report'::character varying::text, 'attribution'::character varying::text, 'compliance'::character varying::text, 'compliance_summary'::character varying::text, 'vendor_risk'::character varying::text, 'vendor_assessment'::character varying::text, 'custom'::character varying::text])", name: "check_reports_type"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'generating'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'expired'::character varying::text])", name: "check_reports_status"
  end

  create_table "supply_chain_risk_assessments", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "assessment_date"
    t.string "assessment_type", default: "initial", null: false
    t.uuid "assessor_id"
    t.datetime "completed_at"
    t.decimal "compliance_score", precision: 5, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.jsonb "evidence", default: [], null: false
    t.jsonb "findings", default: [], null: false
    t.jsonb "metadata", default: {}, null: false
    t.decimal "operational_score", precision: 5, scale: 2, default: "0.0"
    t.decimal "overall_score", precision: 5, scale: 2, default: "0.0"
    t.jsonb "recommendations", default: [], null: false
    t.decimal "security_score", precision: 5, scale: 2, default: "0.0"
    t.string "status", default: "in_progress", null: false
    t.text "summary"
    t.datetime "updated_at", null: false
    t.datetime "valid_until"
    t.uuid "vendor_id", null: false
    t.index ["account_id", "status"], name: "index_supply_chain_risk_assessments_on_account_id_and_status"
    t.index ["account_id"], name: "index_supply_chain_risk_assessments_on_account_id"
    t.index ["assessment_type"], name: "index_supply_chain_risk_assessments_on_assessment_type"
    t.index ["assessor_id"], name: "index_supply_chain_risk_assessments_on_assessor_id"
    t.index ["vendor_id", "created_at"], name: "idx_on_vendor_id_created_at_91807976d2"
    t.index ["vendor_id"], name: "index_supply_chain_risk_assessments_on_vendor_id"
    t.check_constraint "assessment_type::text = ANY (ARRAY['initial'::character varying::text, 'periodic'::character varying::text, 'incident'::character varying::text, 'renewal'::character varying::text])", name: "check_risk_assessments_type"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'in_progress'::character varying::text, 'pending_review'::character varying::text, 'completed'::character varying::text, 'expired'::character varying::text])", name: "check_risk_assessments_status"
  end

  create_table "supply_chain_sbom_components", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.string "dependency_type", default: "direct", null: false
    t.integer "depth", default: 0, null: false
    t.string "ecosystem", null: false
    t.boolean "has_known_vulnerabilities", default: false, null: false
    t.boolean "is_outdated", default: false, null: false
    t.string "latest_version"
    t.string "license_compliance_status", default: "unknown"
    t.string "license_name"
    t.string "license_spdx_id"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.string "namespace"
    t.jsonb "properties", default: {}, null: false
    t.string "purl", null: false
    t.decimal "risk_score", precision: 5, scale: 2, default: "0.0"
    t.uuid "sbom_id", null: false
    t.string "scope"
    t.datetime "updated_at", null: false
    t.string "version"
    t.index ["account_id", "ecosystem"], name: "index_supply_chain_sbom_components_on_account_id_and_ecosystem"
    t.index ["account_id"], name: "index_supply_chain_sbom_components_on_account_id"
    t.index ["has_known_vulnerabilities"], name: "idx_on_has_known_vulnerabilities_0c9d4ddb8d"
    t.index ["metadata"], name: "idx_sbom_components_metadata", using: :gin
    t.index ["purl"], name: "index_supply_chain_sbom_components_on_purl"
    t.index ["sbom_id", "purl"], name: "index_supply_chain_sbom_components_on_sbom_id_and_purl", unique: true
    t.index ["sbom_id"], name: "index_supply_chain_sbom_components_on_sbom_id"
    t.check_constraint "dependency_type::text = ANY (ARRAY['direct'::character varying::text, 'transitive'::character varying::text, 'dev'::character varying::text, 'optional'::character varying::text, 'peer'::character varying::text])", name: "check_sbom_components_dependency_type"
    t.check_constraint "ecosystem::text = ANY (ARRAY['npm'::character varying::text, 'gem'::character varying::text, 'pip'::character varying::text, 'maven'::character varying::text, 'gradle'::character varying::text, 'go'::character varying::text, 'cargo'::character varying::text, 'nuget'::character varying::text, 'composer'::character varying::text, 'hex'::character varying::text, 'pub'::character varying::text, 'cocoapods'::character varying::text, 'swift'::character varying::text, 'other'::character varying::text])", name: "check_sbom_components_ecosystem"
  end

  create_table "supply_chain_sbom_diffs", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "added_components", default: [], null: false
    t.integer "added_count", default: 0, null: false
    t.uuid "base_sbom_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "new_vulnerabilities", default: [], null: false
    t.jsonb "removed_components", default: [], null: false
    t.integer "removed_count", default: 0, null: false
    t.jsonb "resolved_vulnerabilities", default: [], null: false
    t.decimal "risk_delta", precision: 5, scale: 2, default: "0.0"
    t.uuid "target_sbom_id", null: false
    t.datetime "updated_at", null: false
    t.jsonb "updated_components", default: [], null: false
    t.integer "updated_count", default: 0, null: false
    t.index ["account_id", "created_at"], name: "index_supply_chain_sbom_diffs_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_supply_chain_sbom_diffs_on_account_id"
    t.index ["base_sbom_id", "target_sbom_id"], name: "idx_on_base_sbom_id_target_sbom_id_89b684c8d6", unique: true
    t.index ["base_sbom_id"], name: "index_supply_chain_sbom_diffs_on_base_sbom_id"
    t.index ["target_sbom_id"], name: "index_supply_chain_sbom_diffs_on_target_sbom_id"
  end

  create_table "supply_chain_sbom_vulnerabilities", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "component_id", null: false
    t.jsonb "context_factors", default: {}, null: false
    t.decimal "contextual_score", precision: 4, scale: 2
    t.datetime "created_at", null: false
    t.decimal "cvss_score", precision: 4, scale: 2
    t.string "cvss_vector"
    t.integer "cvss_version"
    t.text "description"
    t.text "dismissal_reason"
    t.datetime "dismissed_at"
    t.uuid "dismissed_by_id"
    t.string "fixed_version"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "modified_at"
    t.datetime "published_at"
    t.jsonb "references", default: [], null: false
    t.string "remediation_status", default: "open", null: false
    t.uuid "sbom_id", null: false
    t.string "severity", default: "unknown", null: false
    t.string "source", default: "nvd", null: false
    t.datetime "updated_at", null: false
    t.string "vulnerability_id", null: false
    t.index ["account_id", "severity"], name: "idx_on_account_id_severity_464ccca1a4"
    t.index ["account_id"], name: "index_supply_chain_sbom_vulnerabilities_on_account_id"
    t.index ["component_id"], name: "index_supply_chain_sbom_vulnerabilities_on_component_id"
    t.index ["context_factors"], name: "idx_sbom_vulns_context", using: :gin
    t.index ["dismissed_by_id"], name: "index_supply_chain_sbom_vulnerabilities_on_dismissed_by_id"
    t.index ["remediation_status"], name: "index_supply_chain_sbom_vulnerabilities_on_remediation_status"
    t.index ["sbom_id", "vulnerability_id", "component_id"], name: "idx_on_sbom_id_vulnerability_id_component_id_44bc83fa68", unique: true
    t.index ["sbom_id"], name: "index_supply_chain_sbom_vulnerabilities_on_sbom_id"
    t.index ["vulnerability_id"], name: "index_supply_chain_sbom_vulnerabilities_on_vulnerability_id"
    t.check_constraint "remediation_status::text = ANY (ARRAY['open'::character varying::text, 'in_progress'::character varying::text, 'fixed'::character varying::text, 'dismissed'::character varying::text, 'wont_fix'::character varying::text])", name: "check_sbom_vulns_remediation_status"
    t.check_constraint "severity::text = ANY (ARRAY['critical'::character varying::text, 'high'::character varying::text, 'medium'::character varying::text, 'low'::character varying::text, 'none'::character varying::text, 'unknown'::character varying::text])", name: "check_sbom_vulns_severity"
  end

  create_table "supply_chain_sboms", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "branch"
    t.string "commit_sha"
    t.integer "component_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.jsonb "document", default: {}, null: false
    t.string "document_hash"
    t.string "format", default: "cyclonedx_1_5", null: false
    t.uuid "git_repository_id"
    t.jsonb "metadata", default: {}, null: false
    t.string "name"
    t.boolean "ntia_minimum_compliant", default: false, null: false
    t.uuid "pipeline_run_id"
    t.decimal "risk_score", precision: 5, scale: 2, default: "0.0"
    t.string "sbom_id", null: false
    t.text "signature"
    t.string "signature_algorithm"
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.string "version"
    t.integer "vulnerability_count", default: 0, null: false
    t.index ["account_id", "sbom_id"], name: "index_supply_chain_sboms_on_account_id_and_sbom_id", unique: true
    t.index ["account_id", "status"], name: "index_supply_chain_sboms_on_account_id_and_status"
    t.index ["account_id"], name: "index_supply_chain_sboms_on_account_id"
    t.index ["created_at"], name: "index_supply_chain_sboms_on_created_at"
    t.index ["created_by_id"], name: "index_supply_chain_sboms_on_created_by_id"
    t.index ["git_repository_id", "commit_sha"], name: "index_supply_chain_sboms_on_git_repository_id_and_commit_sha"
    t.index ["git_repository_id"], name: "index_supply_chain_sboms_on_git_repository_id"
    t.index ["metadata"], name: "idx_sboms_metadata", using: :gin
    t.index ["pipeline_run_id"], name: "index_supply_chain_sboms_on_pipeline_run_id"
    t.check_constraint "format::text = ANY (ARRAY['spdx_2_3'::character varying::text, 'cyclonedx_1_4'::character varying::text, 'cyclonedx_1_5'::character varying::text, 'cyclonedx_1_6'::character varying::text])", name: "check_sboms_format"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'generating'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'archived'::character varying::text])", name: "check_sboms_status"
  end

  create_table "supply_chain_scan_executions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.text "error_message"
    t.string "execution_id", null: false
    t.jsonb "input_data", default: {}, null: false
    t.text "logs"
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "output_data", default: {}, null: false
    t.uuid "scan_instance_id", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.string "trigger_type", default: "manual", null: false
    t.uuid "triggered_by_id"
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_supply_chain_scan_executions_on_account_id_and_status"
    t.index ["account_id"], name: "index_supply_chain_scan_executions_on_account_id"
    t.index ["execution_id"], name: "index_supply_chain_scan_executions_on_execution_id", unique: true
    t.index ["scan_instance_id", "created_at"], name: "idx_on_scan_instance_id_created_at_17f6f16184"
    t.index ["scan_instance_id"], name: "index_supply_chain_scan_executions_on_scan_instance_id"
    t.index ["triggered_by_id"], name: "index_supply_chain_scan_executions_on_triggered_by_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text])", name: "check_scan_executions_status"
    t.check_constraint "trigger_type::text = ANY (ARRAY['manual'::character varying::text, 'scheduled'::character varying::text, 'webhook'::character varying::text, 'pipeline'::character varying::text, 'api'::character varying::text])", name: "check_scan_executions_trigger"
  end

  create_table "supply_chain_scan_instances", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "execution_count", default: 0, null: false
    t.integer "failure_count", default: 0, null: false
    t.uuid "installed_by_id"
    t.datetime "last_execution_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.datetime "next_execution_at"
    t.uuid "scan_template_id", null: false
    t.string "schedule_cron"
    t.string "status", default: "active", null: false
    t.integer "success_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "scan_template_id"], name: "idx_on_account_id_scan_template_id_52974de163", unique: true
    t.index ["account_id"], name: "index_supply_chain_scan_instances_on_account_id"
    t.index ["installed_by_id"], name: "index_supply_chain_scan_instances_on_installed_by_id"
    t.index ["next_execution_at"], name: "index_supply_chain_scan_instances_on_next_execution_at"
    t.index ["scan_template_id"], name: "index_supply_chain_scan_instances_on_scan_template_id"
    t.index ["status"], name: "index_supply_chain_scan_instances_on_status"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'paused'::character varying::text, 'disabled'::character varying::text])", name: "check_scan_instances_status"
  end

  create_table "supply_chain_scan_templates", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.decimal "average_rating", precision: 3, scale: 2, default: "0.0"
    t.string "category", default: "security", null: false
    t.jsonb "configuration_schema", default: {}, null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.jsonb "default_configuration", default: {}, null: false
    t.text "description"
    t.integer "install_count", default: 0, null: false
    t.boolean "is_public", default: false, null: false
    t.boolean "is_system", default: false, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.string "status", default: "draft", null: false
    t.jsonb "supported_ecosystems", default: [], null: false
    t.datetime "updated_at", null: false
    t.string "version", default: "1.0.0", null: false
    t.index ["account_id"], name: "index_supply_chain_scan_templates_on_account_id"
    t.index ["category"], name: "index_supply_chain_scan_templates_on_category"
    t.index ["created_by_id"], name: "index_supply_chain_scan_templates_on_created_by_id"
    t.index ["is_public"], name: "index_supply_chain_scan_templates_on_is_public"
    t.index ["slug"], name: "index_supply_chain_scan_templates_on_slug", unique: true
    t.index ["status"], name: "index_supply_chain_scan_templates_on_status"
    t.check_constraint "category::text = ANY (ARRAY['security'::character varying::text, 'compliance'::character varying::text, 'license'::character varying::text, 'quality'::character varying::text, 'custom'::character varying::text])", name: "check_scan_templates_category"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'published'::character varying::text, 'archived'::character varying::text, 'deprecated'::character varying::text])", name: "check_scan_templates_status"
  end

  create_table "supply_chain_signing_keys", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.text "description"
    t.text "encrypted_private_key"
    t.datetime "expires_at"
    t.string "fingerprint", null: false
    t.string "key_id", null: false
    t.string "key_type", default: "cosign", null: false
    t.string "kms_key_uri"
    t.string "kms_provider"
    t.string "kms_region"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.text "public_key", null: false
    t.datetime "rotated_at"
    t.uuid "rotated_from_id"
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "key_id"], name: "index_supply_chain_signing_keys_on_account_id_and_key_id", unique: true
    t.index ["account_id"], name: "index_supply_chain_signing_keys_on_account_id"
    t.index ["created_by_id"], name: "index_supply_chain_signing_keys_on_created_by_id"
    t.index ["fingerprint"], name: "index_supply_chain_signing_keys_on_fingerprint", unique: true
    t.index ["rotated_from_id"], name: "index_supply_chain_signing_keys_on_rotated_from_id"
    t.index ["status"], name: "index_supply_chain_signing_keys_on_status"
    t.check_constraint "key_type::text = ANY (ARRAY['cosign'::character varying::text, 'oidc_identity'::character varying::text, 'kms_reference'::character varying::text, 'gpg'::character varying::text])", name: "check_signing_keys_type"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'rotating'::character varying::text, 'rotated'::character varying::text, 'revoked'::character varying::text, 'expired'::character varying::text])", name: "check_signing_keys_status"
  end

  create_table "supply_chain_vendor_monitoring_events", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "acknowledged_at"
    t.uuid "acknowledged_by_id"
    t.jsonb "affected_services", default: [], null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "detected_at", null: false
    t.string "event_type", null: false
    t.string "external_url"
    t.boolean "is_acknowledged", default: false, null: false
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "recommended_actions", default: [], null: false
    t.datetime "resolved_at"
    t.string "severity", default: "info", null: false
    t.string "source", default: "internal", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.uuid "vendor_id", null: false
    t.index ["account_id", "severity"], name: "idx_on_account_id_severity_a442767bfe"
    t.index ["account_id"], name: "index_supply_chain_vendor_monitoring_events_on_account_id"
    t.index ["acknowledged_by_id"], name: "idx_on_acknowledged_by_id_6c4702b009"
    t.index ["event_type"], name: "index_supply_chain_vendor_monitoring_events_on_event_type"
    t.index ["is_acknowledged"], name: "index_supply_chain_vendor_monitoring_events_on_is_acknowledged"
    t.index ["vendor_id", "created_at"], name: "idx_on_vendor_id_created_at_457df8366a"
    t.index ["vendor_id"], name: "index_supply_chain_vendor_monitoring_events_on_vendor_id"
    t.check_constraint "event_type::text = ANY (ARRAY['security_incident'::character varying::text, 'breach'::character varying::text, 'certification_expiry'::character varying::text, 'contract_renewal'::character varying::text, 'service_degradation'::character varying::text, 'compliance_update'::character varying::text, 'news_alert'::character varying::text])", name: "check_vendor_events_type"
    t.check_constraint "severity::text = ANY (ARRAY['critical'::character varying::text, 'high'::character varying::text, 'medium'::character varying::text, 'low'::character varying::text, 'info'::character varying::text])", name: "check_vendor_events_severity"
  end

  create_table "supply_chain_vendors", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "certifications", default: [], null: false
    t.string "contact_email"
    t.datetime "contract_end_date"
    t.datetime "contract_start_date"
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.text "description"
    t.boolean "handles_pci", default: false, null: false
    t.boolean "handles_phi", default: false, null: false
    t.boolean "handles_pii", default: false, null: false
    t.boolean "has_baa", default: false, null: false
    t.boolean "has_dpa", default: false, null: false
    t.datetime "last_assessment_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.datetime "next_assessment_due"
    t.decimal "risk_score", precision: 5, scale: 2, default: "0.0"
    t.string "risk_tier", default: "medium", null: false
    t.jsonb "security_contacts", default: [], null: false
    t.string "slug", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.string "vendor_type", default: "saas", null: false
    t.string "website"
    t.index ["account_id", "slug"], name: "index_supply_chain_vendors_on_account_id_and_slug", unique: true
    t.index ["account_id"], name: "index_supply_chain_vendors_on_account_id"
    t.index ["certifications"], name: "idx_vendors_certifications", using: :gin
    t.index ["created_by_id"], name: "index_supply_chain_vendors_on_created_by_id"
    t.index ["risk_tier"], name: "index_supply_chain_vendors_on_risk_tier"
    t.index ["status"], name: "index_supply_chain_vendors_on_status"
    t.check_constraint "risk_tier::text = ANY (ARRAY['critical'::character varying::text, 'high'::character varying::text, 'medium'::character varying::text, 'low'::character varying::text])", name: "check_vendors_risk_tier"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'under_review'::character varying::text, 'terminated'::character varying::text])", name: "check_vendors_status"
    t.check_constraint "vendor_type::text = ANY (ARRAY['saas'::character varying::text, 'api'::character varying::text, 'library'::character varying::text, 'infrastructure'::character varying::text, 'hardware'::character varying::text, 'consulting'::character varying::text, 'other'::character varying::text])", name: "check_vendors_type"
  end

  create_table "supply_chain_verification_logs", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "attestation_id", null: false
    t.datetime "created_at", null: false
    t.string "log_hash", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "previous_log_hash"
    t.string "result", null: false
    t.text "result_message"
    t.datetime "updated_at", null: false
    t.jsonb "verification_details", default: {}, null: false
    t.string "verification_type", null: false
    t.uuid "verified_by_id"
    t.index ["account_id"], name: "index_supply_chain_verification_logs_on_account_id"
    t.index ["attestation_id", "created_at"], name: "idx_on_attestation_id_created_at_181e09a329"
    t.index ["attestation_id"], name: "index_supply_chain_verification_logs_on_attestation_id"
    t.index ["log_hash"], name: "index_supply_chain_verification_logs_on_log_hash", unique: true
    t.index ["previous_log_hash"], name: "index_supply_chain_verification_logs_on_previous_log_hash"
    t.index ["verified_by_id"], name: "index_supply_chain_verification_logs_on_verified_by_id"
  end

  create_table "supply_chain_vulnerability_feeds", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "api_key_encrypted"
    t.jsonb "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.integer "entry_count", default: 0, null: false
    t.boolean "is_active", default: true, null: false
    t.datetime "last_sync_at"
    t.text "last_sync_error"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.string "source", null: false
    t.string "sync_status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["account_id", "source"], name: "idx_on_account_id_source_ca62ab5a94", unique: true
    t.index ["account_id"], name: "index_supply_chain_vulnerability_feeds_on_account_id"
    t.index ["sync_status"], name: "index_supply_chain_vulnerability_feeds_on_sync_status"
    t.check_constraint "source::text = ANY (ARRAY['nvd'::character varying::text, 'osv'::character varying::text, 'github_advisory'::character varying::text, 'snyk'::character varying::text, 'sonatype'::character varying::text, 'custom'::character varying::text])", name: "check_vuln_feeds_source"
    t.check_constraint "sync_status::text = ANY (ARRAY['pending'::character varying::text, 'syncing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "check_vuln_feeds_sync_status"
  end

  create_table "supply_chain_vulnerability_scans", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "completed_at"
    t.uuid "container_image_id", null: false
    t.datetime "created_at", null: false
    t.integer "critical_count", default: 0, null: false
    t.integer "duration_ms"
    t.text "error_message"
    t.integer "high_count", default: 0, null: false
    t.jsonb "layer_vulnerabilities", default: {}, null: false
    t.integer "low_count", default: 0, null: false
    t.integer "medium_count", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "sbom", default: {}, null: false
    t.string "scanner_name", default: "trivy", null: false
    t.string "scanner_version"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.uuid "triggered_by_id"
    t.integer "unknown_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.jsonb "vulnerabilities", default: [], null: false
    t.index ["account_id", "status"], name: "idx_on_account_id_status_94f62095d3"
    t.index ["account_id"], name: "index_supply_chain_vulnerability_scans_on_account_id"
    t.index ["container_image_id", "created_at"], name: "idx_on_container_image_id_created_at_a0cbb8e663"
    t.index ["container_image_id"], name: "index_supply_chain_vulnerability_scans_on_container_image_id"
    t.index ["triggered_by_id"], name: "index_supply_chain_vulnerability_scans_on_triggered_by_id"
    t.index ["vulnerabilities"], name: "idx_vuln_scans_vulns", using: :gin
    t.check_constraint "scanner_name::text = ANY (ARRAY['trivy'::character varying::text, 'grype'::character varying::text, 'clair'::character varying::text, 'snyk'::character varying::text, 'custom'::character varying::text])", name: "check_vuln_scans_scanner"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text])", name: "check_vuln_scans_status"
  end

  create_table "system_acme_certificates", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "challenge_type", limit: 16, default: "dns-01", null: false
    t.string "common_name", limit: 255, null: false
    t.datetime "created_at", null: false
    t.uuid "dns_credential_id"
    t.datetime "expires_at"
    t.datetime "issued_at"
    t.string "issuer", limit: 64, default: "letsencrypt-prod", null: false
    t.datetime "last_renewal_attempt_at"
    t.text "last_renewal_error"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "migrated_to_vault_at"
    t.datetime "revoked_at"
    t.jsonb "sans", default: [], null: false
    t.string "status", limit: 32, default: "pending", null: false
    t.string "traefik_resolver_name"
    t.datetime "updated_at", null: false
    t.string "vault_path_account_key"
    t.string "vault_path_certificate"
    t.string "vault_path_chain"
    t.string "vault_path_private_key"
    t.index ["account_id", "common_name"], name: "idx_acme_certs_acct_cn_unique_active", unique: true, where: "((status)::text <> 'revoked'::text)"
    t.index ["account_id"], name: "index_system_acme_certificates_on_account_id"
    t.index ["dns_credential_id"], name: "index_system_acme_certificates_on_dns_credential_id"
    t.index ["expires_at"], name: "index_system_acme_certificates_on_expires_at"
    t.index ["issuer"], name: "index_system_acme_certificates_on_issuer"
    t.index ["migrated_to_vault_at"], name: "index_acme_certificates_on_migrated_to_vault_at", where: "(migrated_to_vault_at IS NOT NULL)"
    t.index ["revoked_at"], name: "index_system_acme_certificates_on_revoked_at"
    t.index ["status"], name: "index_system_acme_certificates_on_status"
  end

  create_table "system_acme_dns_credentials", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.text "encrypted_credentials"
    t.string "encryption_key_id"
    t.datetime "last_validated_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "migrated_to_vault_at"
    t.string "name", limit: 255, null: false
    t.string "provider", limit: 64, null: false
    t.string "status", limit: 32, default: "untested", null: false
    t.datetime "updated_at", null: false
    t.string "vault_path_credentials"
    t.index ["account_id", "name"], name: "index_system_acme_dns_credentials_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_system_acme_dns_credentials_on_account_id"
    t.index ["migrated_to_vault_at"], name: "index_acme_dns_credentials_on_migrated_to_vault_at", where: "(migrated_to_vault_at IS NOT NULL)"
    t.index ["provider"], name: "index_system_acme_dns_credentials_on_provider"
    t.index ["status"], name: "index_system_acme_dns_credentials_on_status"
  end

  create_table "system_bootstrap_tokens", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "consumed_at"
    t.string "consumed_from_ip"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "intended_subject", null: false
    t.uuid "node_id", null: false
    t.uuid "node_instance_id"
    t.text "purpose"
    t.boolean "single_use", default: true, null: false
    t.string "token_hash", null: false
    t.datetime "updated_at", null: false
    t.index ["consumed_at"], name: "index_system_bootstrap_tokens_on_consumed_at"
    t.index ["expires_at"], name: "index_system_bootstrap_tokens_on_expires_at"
    t.index ["node_id"], name: "index_system_bootstrap_tokens_on_node_id"
    t.index ["node_instance_id"], name: "index_system_bootstrap_tokens_on_node_instance_id"
    t.index ["token_hash"], name: "index_system_bootstrap_tokens_on_token_hash", unique: true
  end

  create_table "system_ci_runner_leases", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "build_task_id"
    t.datetime "busy_at"
    t.datetime "created_at", null: false
    t.boolean "ephemeral", default: false, null: false
    t.text "error_message"
    t.datetime "errored_at"
    t.datetime "expires_at"
    t.string "git_owner"
    t.string "git_repo"
    t.uuid "git_runner_id"
    t.uuid "instance_pool_id"
    t.datetime "leased_at"
    t.jsonb "metadata", default: {}, null: false
    t.uuid "node_instance_id", null: false
    t.string "purpose", default: "generic", null: false
    t.datetime "registered_at"
    t.datetime "released_at"
    t.datetime "releasing_at"
    t.string "runner_external_id"
    t.jsonb "runner_labels", default: [], null: false
    t.string "runner_name"
    t.string "runner_scope", default: "org", null: false
    t.string "status", default: "leased", null: false
    t.datetime "updated_at", null: false
    t.bigint "workflow_run_id"
    t.string "workflow_run_repo"
    t.index ["account_id"], name: "index_system_ci_runner_leases_on_account_id"
    t.index ["build_task_id"], name: "index_system_ci_runner_leases_on_build_task_id"
    t.index ["node_instance_id"], name: "index_system_ci_runner_leases_on_node_instance_id"
    t.index ["runner_name"], name: "index_system_ci_runner_leases_on_runner_name"
    t.index ["status"], name: "index_system_ci_runner_leases_on_status"
    t.index ["workflow_run_id"], name: "index_system_ci_runner_leases_on_workflow_run_id"
  end

  create_table "system_claude_code_credentials", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_credentials"
    t.string "encryption_key_id"
    t.datetime "migrated_to_vault_at"
    t.uuid "node_instance_id", null: false
    t.datetime "updated_at", null: false
    t.string "vault_path_credentials"
    t.index ["node_instance_id"], name: "index_system_claude_code_credentials_on_node_instance_id", unique: true
  end

  create_table "system_cve_exposures", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "cve_id", null: false
    t.datetime "detected_at", default: -> { "now()" }, null: false
    t.jsonb "metadata", default: {}, null: false
    t.uuid "node_module_version_id", null: false
    t.string "package_name", null: false
    t.string "package_version"
    t.string "resolution_note"
    t.datetime "resolved_at"
    t.string "state", default: "open", null: false
    t.datetime "updated_at", null: false
    t.index ["cve_id", "node_module_version_id", "package_name"], name: "idx_on_cve_id_node_module_version_id_package_name_a350319e5f", unique: true
    t.index ["cve_id"], name: "index_system_cve_exposures_on_cve_id"
    t.index ["detected_at"], name: "index_system_cve_exposures_on_detected_at"
    t.index ["node_module_version_id"], name: "index_system_cve_exposures_on_node_module_version_id"
    t.index ["state"], name: "index_system_cve_exposures_on_state"
    t.check_constraint "state::text = ANY (ARRAY['open'::character varying::text, 'remediating'::character varying::text, 'resolved'::character varying::text, 'wont_fix'::character varying::text])", name: "ck_cve_exposures_state"
  end

  create_table "system_cves", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "affected_packages", default: [], null: false
    t.datetime "created_at", null: false
    t.string "cve_id", null: false
    t.string "feed_source"
    t.datetime "ingested_at", default: -> { "now()" }
    t.jsonb "metadata", default: {}, null: false
    t.datetime "published_at"
    t.string "reference_url"
    t.string "severity", null: false
    t.text "summary"
    t.datetime "updated_at", null: false
    t.index ["affected_packages"], name: "index_system_cves_on_affected_packages", using: :gin
    t.index ["cve_id"], name: "index_system_cves_on_cve_id", unique: true
    t.index ["ingested_at"], name: "index_system_cves_on_ingested_at"
    t.index ["published_at"], name: "index_system_cves_on_published_at"
    t.index ["severity"], name: "index_system_cves_on_severity"
    t.check_constraint "severity::text = ANY (ARRAY['critical'::character varying::text, 'high'::character varying::text, 'medium'::character varying::text, 'low'::character varying::text, 'unknown'::character varying::text])", name: "ck_cves_severity"
  end

  create_table "system_dev_cell_deploy_keys", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "algorithm"
    t.datetime "created_at", null: false
    t.bigint "deploy_key_id"
    t.text "encrypted_credentials"
    t.string "encryption_key_id"
    t.string "fingerprint"
    t.datetime "migrated_to_vault_at"
    t.uuid "node_instance_id", null: false
    t.text "public_key_openssh"
    t.string "source_repo"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "vault_path_credentials"
    t.index ["node_instance_id"], name: "index_system_dev_cell_deploy_keys_on_node_instance_id", unique: true
  end

  create_table "system_disk_image_publications", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "arch", null: false
    t.integer "attempt_count", default: 1, null: false
    t.text "attestation_bundle", comment: "cosign attest-blob bundle over the publication payload predicate"
    t.text "cosign_bundle", comment: "cosign sign-blob bundle over the .img bytes"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.uuid "file_object_id"
    t.string "firmware_ref", comment: "rpi4-firmware module ref pinned at build time"
    t.string "git_sha", null: false
    t.uuid "node_platform_id", null: false
    t.string "oci_ref", comment: "Source OCI artifact ref (null for direct-upload mode)"
    t.jsonb "payload", default: {}, null: false
    t.uuid "prior_file_object_id"
    t.datetime "published_at"
    t.datetime "purged_at"
    t.datetime "retired_at"
    t.string "sha256", null: false
    t.bigint "size_bytes", null: false
    t.string "status", default: "queued", null: false, comment: "queued|awaiting_upload|verifying|published|failed|retired|purged"
    t.uuid "triggered_by_worker_id"
    t.text "uki_cosign_bundle"
    t.string "uki_oci_ref"
    t.string "uki_sha256"
    t.datetime "updated_at", null: false
    t.datetime "verified_at"
    t.uuid "webhook_id"
    t.index ["account_id"], name: "index_system_disk_image_publications_on_account_id"
    t.index ["file_object_id"], name: "index_system_disk_image_publications_on_file_object_id"
    t.index ["node_platform_id", "created_at"], name: "idx_on_node_platform_id_created_at_a541381409", order: { created_at: :desc }
    t.index ["node_platform_id", "git_sha"], name: "idx_on_node_platform_id_git_sha_ae0ad8696b", unique: true
    t.index ["node_platform_id", "status"], name: "idx_on_node_platform_id_status_8840e26bb2"
    t.index ["node_platform_id"], name: "index_system_disk_image_publications_on_node_platform_id"
    t.index ["prior_file_object_id"], name: "index_system_disk_image_publications_on_prior_file_object_id"
    t.index ["status"], name: "index_system_disk_image_publications_on_status"
    t.index ["triggered_by_worker_id"], name: "index_system_disk_image_publications_on_triggered_by_worker_id"
    t.index ["webhook_id"], name: "index_system_disk_image_publications_on_webhook_id"
  end

  create_table "system_disk_image_webhooks", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.string "label", null: false, comment: "Operator-chosen identifier (e.g. 'main-ci', 'release-pipeline')"
    t.datetime "last_received_at"
    t.datetime "last_rotated_at"
    t.integer "received_count", default: 0, null: false
    t.text "secret", null: false, comment: "HMAC secret for X-Powernode-Signature verification. Encrypted at rest via `encrypts :secret`. Plaintext shown to operator exactly once at create/rotate."
    t.string "secret_preview", null: false, comment: "First 8 chars of the secret for operator UI disambiguation (so they can identify which secret is which without seeing the full value)."
    t.string "status", default: "active", null: false, comment: "active|disabled|revoked"
    t.datetime "updated_at", null: false
    t.index ["account_id", "label"], name: "index_system_disk_image_webhooks_on_account_id_and_label", unique: true
    t.index ["account_id"], name: "index_system_disk_image_webhooks_on_account_id"
    t.index ["created_by_id"], name: "index_system_disk_image_webhooks_on_created_by_id"
    t.index ["status"], name: "index_system_disk_image_webhooks_on_status"
  end

  create_table "system_federation_audit_shipments", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.string "error_message"
    t.integer "event_count", default: 0, null: false
    t.uuid "federation_peer_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "period_end", null: false
    t.datetime "period_start", null: false
    t.string "sealed_path", limit: 512
    t.string "sha256", limit: 64
    t.datetime "shipped_at"
    t.string "status", limit: 32, default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_system_federation_audit_shipments_on_account_id"
    t.index ["federation_peer_id", "period_start"], name: "idx_on_federation_peer_id_period_start_0b3bd2ca8e"
    t.index ["federation_peer_id"], name: "index_system_federation_audit_shipments_on_federation_peer_id"
    t.check_constraint "period_end > period_start", name: "audit_shipment_period_valid"
  end

  create_table "system_federation_capabilities", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "conflict_resolution", limit: 48, default: "newer_wins_logical_clock", null: false
    t.datetime "created_at", null: false
    t.string "direction", limit: 32, null: false
    t.uuid "federation_peer_id", null: false
    t.jsonb "filter", default: {}, null: false
    t.datetime "last_synced_at"
    t.string "policy", limit: 32, default: "manual", null: false
    t.string "resource_kind", limit: 64, null: false
    t.jsonb "sync_cursor", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "resource_kind"], name: "idx_on_account_id_resource_kind_985a7ea6be"
    t.index ["federation_peer_id", "resource_kind", "direction"], name: "idx_on_federation_peer_id_resource_kind_direction_557f9ddf0d", unique: true
    t.index ["policy"], name: "index_system_federation_capabilities_on_policy"
    t.check_constraint "conflict_resolution::text = ANY (ARRAY['newer_wins_logical_clock'::character varying::text, 'local_wins'::character varying::text, 'remote_wins'::character varying::text, 'prompt'::character varying::text])", name: "federation_capabilities_conflict_resolution_enum"
    t.check_constraint "direction::text = ANY (ARRAY['push_local_to_remote'::character varying::text, 'pull_remote_to_local'::character varying::text, 'bidirectional'::character varying::text, 'migration_only'::character varying::text])", name: "federation_capabilities_direction_enum"
    t.check_constraint "policy::text = ANY (ARRAY['manual'::character varying::text, 'auto_on_change'::character varying::text, 'auto_periodic'::character varying::text, 'on_match_filter'::character varying::text])", name: "federation_capabilities_policy_enum"
  end

  create_table "system_federation_contract_versions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "contract_digest", limit: 64, null: false
    t.text "contract_text", null: false
    t.datetime "created_at", null: false
    t.date "deprecated_at"
    t.date "effective_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "updated_at", null: false
    t.integer "version", null: false
    t.index ["contract_digest"], name: "index_system_federation_contract_versions_on_contract_digest", unique: true
    t.index ["deprecated_at"], name: "index_system_federation_contract_versions_on_deprecated_at", where: "(deprecated_at IS NOT NULL)"
    t.index ["version"], name: "index_system_federation_contract_versions_on_version", unique: true
  end

  create_table "system_federation_grants", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.uuid "federation_peer_id", null: false
    t.uuid "grantor_user_id"
    t.datetime "issued_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "node_instance_ids", default: [], null: false
    t.jsonb "permission_scopes", default: [], null: false
    t.string "remote_subject", limit: 256, null: false
    t.uuid "resource_id"
    t.string "resource_kind", limit: 64, null: false
    t.string "revocation_reason", limit: 256
    t.datetime "revoked_at"
    t.jsonb "sdwan_network_ids", default: [], null: false
    t.jsonb "source_cidrs", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "expires_at"], name: "idx_fed_grants_account_expiring", where: "((revoked_at IS NULL) AND (archived_at IS NULL))"
    t.index ["account_id", "revoked_at"], name: "idx_fed_grants_account_revoked", where: "(archived_at IS NULL)"
    t.index ["account_id"], name: "index_system_federation_grants_on_account_id"
    t.index ["federation_peer_id", "remote_subject", "resource_kind", "resource_id"], name: "idx_fed_grants_specific_resource_unique", unique: true, where: "(resource_id IS NOT NULL)"
    t.index ["federation_peer_id", "remote_subject", "resource_kind"], name: "idx_fed_grants_kind_wide_unique", unique: true, where: "(resource_id IS NULL)"
    t.index ["federation_peer_id"], name: "index_system_federation_grants_on_federation_peer_id"
    t.index ["grantor_user_id"], name: "index_system_federation_grants_on_grantor_user_id"
    t.index ["node_instance_ids"], name: "index_system_federation_grants_on_node_instance_ids", using: :gin
    t.index ["sdwan_network_ids"], name: "index_system_federation_grants_on_sdwan_network_ids", using: :gin
  end

  create_table "system_federation_network_bridges", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "activated_at"
    t.datetime "created_at", null: false
    t.uuid "federation_peer_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "proposed_at"
    t.string "revocation_reason", limit: 256
    t.datetime "revoked_at"
    t.uuid "sdwan_network_id", null: false
    t.string "state", limit: 16, default: "proposed", null: false
    t.datetime "suspended_at"
    t.datetime "updated_at", null: false
    t.index ["account_id", "state"], name: "idx_on_account_id_state_4a17bb3bba"
    t.index ["federation_peer_id", "sdwan_network_id"], name: "idx_on_federation_peer_id_sdwan_network_id_caca247653", unique: true
    t.index ["sdwan_network_id"], name: "index_system_federation_network_bridges_on_sdwan_network_id"
    t.index ["state"], name: "index_system_federation_network_bridges_on_state"
    t.check_constraint "state::text = ANY (ARRAY['proposed'::character varying::text, 'active'::character varying::text, 'suspended'::character varying::text, 'revoked'::character varying::text])", name: "federation_network_bridges_state_enum"
  end

  create_table "system_federation_peers", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "acceptance_token_digest", comment: "SHA-256 hex digest of the plaintext acceptance token. Plaintext returned exactly once on propose; stored only as digest."
    t.datetime "acceptance_token_expires_at", comment: "When the acceptance token expires. accept! refuses tokens past this time."
    t.uuid "account_id", null: false
    t.jsonb "capabilities", default: {}, null: false
    t.integer "contract_version_agreed"
    t.datetime "created_at", null: false
    t.string "data_residency", limit: 64
    t.text "encrypted_credentials"
    t.jsonb "endpoints", default: [], null: false
    t.datetime "expires_at"
    t.jsonb "extension_slugs", default: [], null: false
    t.string "inbound_subject", limit: 255
    t.datetime "last_capability_sync_at"
    t.datetime "last_handshake_at"
    t.datetime "last_heartbeat_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "migrated_to_vault_at"
    t.uuid "outbound_certificate_id"
    t.uuid "parent_peer_id"
    t.string "peer_kind", limit: 32, default: "sdwan_only", null: false
    t.string "platform_version", limit: 64
    t.uuid "remote_account_id"
    t.uuid "remote_instance_id"
    t.string "remote_instance_url", null: false
    t.string "remote_prefix_advertisement"
    t.datetime "signed_at"
    t.string "spawn_mode", limit: 32
    t.string "spawn_role", limit: 16
    t.string "status", default: "proposed", null: false
    t.jsonb "sync_cursor", default: {}, null: false
    t.text "trusted_ca_pem"
    t.datetime "updated_at", null: false
    t.string "vault_path"
    t.index ["acceptance_token_digest"], name: "index_federation_peers_on_token_digest", where: "(acceptance_token_digest IS NOT NULL)"
    t.index ["account_id", "remote_instance_id"], name: "idx_on_account_id_remote_instance_id_98e822b5a5", unique: true
    t.index ["account_id"], name: "index_system_federation_peers_on_account_id"
    t.index ["data_residency"], name: "index_system_federation_peers_on_data_residency"
    t.index ["inbound_subject"], name: "index_federation_peers_on_inbound_subject", unique: true, where: "(inbound_subject IS NOT NULL)"
    t.index ["last_heartbeat_at"], name: "idx_federation_peers_platform_heartbeat", where: "((peer_kind)::text = 'platform'::text)"
    t.index ["outbound_certificate_id"], name: "index_system_federation_peers_on_outbound_certificate_id"
    t.index ["parent_peer_id"], name: "index_system_federation_peers_on_parent_peer_id"
    t.index ["peer_kind", "status"], name: "index_system_federation_peers_on_peer_kind_and_status"
    t.index ["peer_kind"], name: "index_system_federation_peers_on_peer_kind"
    t.index ["platform_version"], name: "index_system_federation_peers_on_platform_version"
    t.index ["remote_prefix_advertisement"], name: "index_system_federation_peers_on_remote_prefix_advertisement"
    t.index ["status"], name: "index_system_federation_peers_on_status"
    t.check_constraint "peer_kind::text = ANY (ARRAY['platform'::character varying::text, 'sdwan_only'::character varying::text])", name: "federation_peers_peer_kind_enum"
  end

  create_table "system_federation_schema_compatibility", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.datetime "created_at", null: false
    t.string "local_version", limit: 64, null: false
    t.string "notes", limit: 1024
    t.string "remote_version", limit: 64, null: false
    t.string "source", limit: 32, default: "default", null: false
    t.string "status", limit: 32, default: "compatible", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_system_federation_schema_compatibility_on_account_id"
    t.index ["local_version", "remote_version"], name: "idx_on_local_version_remote_version_24f89208e8", unique: true
    t.index ["status"], name: "index_system_federation_schema_compatibility_on_status"
  end

  create_table "system_federation_service_offerings", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "capacity_metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.jsonb "default_grant_scopes", default: ["read"], null: false
    t.integer "default_grant_ttl_days", default: 30, null: false
    t.datetime "deprecated_at"
    t.text "description_markdown"
    t.jsonb "latency_metadata", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "name", limit: 255, null: false
    t.datetime "retired_at"
    t.uuid "service_id", null: false
    t.string "slug", limit: 64, null: false
    t.string "status", limit: 16, default: "draft", null: false
    t.text "subscription_terms_markdown"
    t.datetime "updated_at", null: false
    t.index ["account_id", "slug"], name: "idx_on_account_id_slug_346731f4c9", unique: true
    t.index ["account_id"], name: "index_system_federation_service_offerings_on_account_id"
    t.index ["service_id"], name: "index_system_federation_service_offerings_on_service_id"
    t.index ["status"], name: "index_system_federation_service_offerings_on_status"
  end

  create_table "system_federation_service_subscriptions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "acme_certificate_id"
    t.datetime "activated_at"
    t.integer "backend_port", null: false
    t.string "backend_vip", limit: 255
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.uuid "federation_grant_id", null: false
    t.uuid "federation_peer_id", null: false
    t.string "local_hostname", limit: 255, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "protocol", limit: 16, null: false
    t.uuid "service_offering_id"
    t.string "service_offering_slug", limit: 64, null: false
    t.string "status", limit: 16, default: "pending", null: false
    t.datetime "subscribed_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "suspended_at"
    t.datetime "updated_at", null: false
    t.index ["account_id", "local_hostname"], name: "idx_on_account_id_local_hostname_51d1fcce3d", unique: true
    t.index ["account_id"], name: "index_system_federation_service_subscriptions_on_account_id"
    t.index ["acme_certificate_id"], name: "idx_on_acme_certificate_id_067efd537c"
    t.index ["federation_grant_id"], name: "idx_on_federation_grant_id_1cc186eb1f"
    t.index ["federation_peer_id", "service_offering_slug"], name: "idx_on_federation_peer_id_service_offering_slug_6f0a7bb80d"
    t.index ["federation_peer_id"], name: "idx_on_federation_peer_id_920bf6bbf4"
    t.index ["status"], name: "index_system_federation_service_subscriptions_on_status"
  end

  create_table "system_fleet_events", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "certificate_id"
    t.string "correlation_id"
    t.datetime "created_at", null: false
    t.uuid "cve_id"
    t.datetime "emitted_at", default: -> { "now()" }, null: false
    t.string "kind", null: false
    t.uuid "node_id"
    t.uuid "node_instance_id"
    t.uuid "node_module_id"
    t.uuid "node_module_version_id"
    t.jsonb "payload", default: {}, null: false
    t.string "severity", default: "low", null: false
    t.string "source"
    t.datetime "updated_at", null: false
    t.index ["account_id", "emitted_at"], name: "index_system_fleet_events_on_account_id_and_emitted_at"
    t.index ["account_id"], name: "index_system_fleet_events_on_account_id"
    t.index ["correlation_id"], name: "index_system_fleet_events_on_correlation_id"
    t.index ["emitted_at"], name: "index_system_fleet_events_on_emitted_at"
    t.index ["kind"], name: "index_system_fleet_events_on_kind"
    t.index ["node_instance_id"], name: "index_system_fleet_events_on_node_instance_id"
    t.index ["node_module_id"], name: "index_system_fleet_events_on_node_module_id"
    t.index ["payload"], name: "index_system_fleet_events_on_payload", using: :gin
    t.index ["severity"], name: "index_system_fleet_events_on_severity"
    t.check_constraint "severity::text = ANY (ARRAY['low'::character varying::text, 'medium'::character varying::text, 'high'::character varying::text, 'critical'::character varying::text])", name: "ck_fleet_events_severity"
  end

  create_table "system_fleet_remediation_outcomes", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "acted_at", null: false
    t.string "action_category"
    t.uuid "agent_id"
    t.string "correlation_id"
    t.datetime "created_at", null: false
    t.string "fingerprint", null: false
    t.jsonb "metadata", default: {}
    t.string "resource_ref"
    t.datetime "settle_until", null: false
    t.string "signal_kind", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.datetime "validated_at"
    t.index ["account_id", "status", "settle_until"], name: "idx_on_account_id_status_settle_until_f7bbeeaab4"
    t.index ["account_id"], name: "index_system_fleet_remediation_outcomes_on_account_id"
    t.index ["fingerprint"], name: "index_system_fleet_remediation_outcomes_on_fingerprint"
  end

  create_table "system_fulfillment_requests", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "approved_at"
    t.uuid "approved_by_user_id"
    t.uuid "build_batch_id"
    t.datetime "building_at"
    t.jsonb "cost_estimate", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "error"
    t.datetime "expired_at"
    t.datetime "expires_at"
    t.datetime "failed_at"
    t.integer "instance_count", default: 0, null: false
    t.integer "lease_ttl_seconds"
    t.integer "materialized_count", default: 0, null: false
    t.jsonb "materialized_module_ids", default: [], null: false
    t.jsonb "materialized_modules", default: [], null: false
    t.datetime "materializing_at"
    t.jsonb "node_instance_ids", default: [], null: false
    t.jsonb "parked", default: [], null: false
    t.jsonb "plan", default: {}, null: false
    t.datetime "provisioning_at"
    t.datetime "ready_at"
    t.text "request", null: false
    t.uuid "requested_by_user_id"
    t.integer "reused_count", default: 0, null: false
    t.jsonb "reused_modules", default: [], null: false
    t.jsonb "smoke"
    t.datetime "smoking_at"
    t.string "state", default: "composed", null: false
    t.uuid "template_id"
    t.datetime "templated_at"
    t.datetime "updated_at", null: false
    t.index ["account_id", "materializing_at"], name: "idx_fulfillment_requests_account_rate"
    t.index ["account_id"], name: "index_system_fulfillment_requests_on_account_id"
    t.index ["approved_by_user_id"], name: "index_system_fulfillment_requests_on_approved_by_user_id"
    t.index ["build_batch_id"], name: "index_system_fulfillment_requests_on_build_batch_id"
    t.index ["expires_at"], name: "index_system_fulfillment_requests_on_expires_at"
    t.index ["state"], name: "index_system_fulfillment_requests_on_state"
    t.index ["template_id"], name: "index_system_fulfillment_requests_on_template_id"
  end

  create_table "system_gitops_repositories", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.boolean "auto_apply", default: false, null: false
    t.string "branch", default: "main", null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.integer "last_diff_count", default: 0, null: false
    t.text "last_error"
    t.string "last_status", default: "pending"
    t.datetime "last_synced_at"
    t.string "last_synced_revision"
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.string "path_prefix", default: ""
    t.string "repo_url", null: false
    t.datetime "updated_at", null: false
    t.string "vault_credential_path"
    t.index ["account_id", "name"], name: "index_system_gitops_repositories_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_system_gitops_repositories_on_account_id"
    t.index ["enabled"], name: "index_system_gitops_repositories_on_enabled"
    t.index ["last_synced_at"], name: "index_system_gitops_repositories_on_last_synced_at"
  end

  create_table "system_gitops_sync_runs", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "diff_count", default: 0, null: false
    t.jsonb "diff_summary", default: {}
    t.text "error_message"
    t.uuid "gitops_repository_id", null: false
    t.uuid "proposal_ids", default: [], array: true
    t.datetime "started_at", null: false
    t.string "status", default: "running", null: false
    t.string "synced_revision"
    t.datetime "updated_at", null: false
    t.index ["gitops_repository_id"], name: "index_system_gitops_sync_runs_on_gitops_repository_id"
    t.index ["started_at"], name: "index_system_gitops_sync_runs_on_started_at"
    t.index ["status"], name: "index_system_gitops_sync_runs_on_status"
  end

  create_table "system_instance_pools", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "last_replenished_at"
    t.string "lifecycle_class", default: "ephemeral", null: false
    t.integer "max_size", default: 10, null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "min_size", default: 0, null: false
    t.string "name", null: false
    t.uuid "node_template_id", null: false
    t.text "preferred_regions", default: [], array: true
    t.uuid "provider_instance_type_id"
    t.uuid "provider_region_id"
    t.string "status", default: "active", null: false
    t.integer "target_size", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_system_instance_pools_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_system_instance_pools_on_account_id"
    t.index ["node_template_id"], name: "index_system_instance_pools_on_node_template_id"
    t.index ["provider_instance_type_id"], name: "index_system_instance_pools_on_provider_instance_type_id"
    t.index ["provider_region_id"], name: "index_system_instance_pools_on_provider_region_id"
    t.index ["status", "last_replenished_at"], name: "idx_instance_pools_reaper_targets", where: "((status)::text = ANY (ARRAY[('active'::character varying)::text, ('draining'::character varying)::text]))"
    t.check_constraint "lifecycle_class::text = ANY (ARRAY['ephemeral'::character varying::text, 'spot'::character varying::text])", name: "chk_instance_pools_lifecycle_class"
    t.check_constraint "max_size >= target_size", name: "chk_instance_pools_max_gte_target"
    t.check_constraint "min_size >= 0", name: "chk_instance_pools_min_size_nonneg"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'paused'::character varying::text, 'draining'::character varying::text, 'archived'::character varying::text])", name: "chk_instance_pools_status"
    t.check_constraint "target_size >= 0", name: "chk_instance_pools_target_size_nonneg"
    t.check_constraint "target_size >= min_size", name: "chk_instance_pools_target_gte_min"
  end

  create_table "system_migration_chains", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "audit_log", default: [], null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "current_hop_index", default: 0, null: false
    t.string "error_message"
    t.datetime "failed_at"
    t.jsonb "hop_peer_ids", default: [], null: false
    t.uuid "initiated_by_user_id"
    t.jsonb "metadata", default: {}, null: false
    t.string "operation", limit: 16, null: false
    t.string "root_resource_id", limit: 64, null: false
    t.string "root_resource_kind", limit: 64, null: false
    t.datetime "started_at"
    t.string "status", limit: 32, default: "planned", null: false
    t.integer "total_hops", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_system_migration_chains_on_account_id_and_status"
    t.index ["account_id"], name: "index_system_migration_chains_on_account_id"
    t.index ["initiated_by_user_id"], name: "index_system_migration_chains_on_initiated_by_user_id"
    t.index ["status"], name: "index_system_migration_chains_on_status"
    t.check_constraint "current_hop_index >= 0 AND current_hop_index <= total_hops", name: "migration_chain_hop_index_in_range"
    t.check_constraint "total_hops >= 1", name: "migration_chain_total_hops_positive"
  end

  create_table "system_migration_plan_steps", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "action", limit: 24, null: false
    t.datetime "applied_at"
    t.string "conflict_policy", limit: 32, default: "fail", null: false
    t.datetime "created_at", null: false
    t.string "error_message", limit: 2048
    t.jsonb "metadata", default: {}, null: false
    t.uuid "migration_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.uuid "resource_id", null: false
    t.string "resource_kind", limit: 64, null: false
    t.integer "step_order", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_system_migration_plan_steps_on_action"
    t.index ["migration_id", "step_order"], name: "idx_on_migration_id_step_order_a613cde875", unique: true
    t.index ["migration_id"], name: "index_system_migration_plan_steps_on_migration_id"
    t.index ["resource_kind", "resource_id"], name: "idx_on_resource_kind_resource_id_d9906d8436"
    t.check_constraint "action::text = ANY (ARRAY['create'::character varying::text, 'link_local'::character varying::text, 'skip'::character varying::text, 'conflict'::character varying::text])", name: "migration_plan_steps_action_enum"
    t.check_constraint "conflict_policy::text = ANY (ARRAY['skip_if_exists'::character varying::text, 'rename_with_suffix'::character varying::text, 'overwrite'::character varying::text, 'fail'::character varying::text])", name: "migration_plan_steps_conflict_policy_enum"
  end

  create_table "system_migrations", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "audit_log", default: [], null: false
    t.datetime "cancelled_at"
    t.integer "chain_position"
    t.datetime "completed_at"
    t.jsonb "conflict_log", default: [], null: false
    t.datetime "created_at", null: false
    t.uuid "destination_peer_id"
    t.boolean "dry_run", default: false, null: false
    t.string "error_message", limit: 2048
    t.datetime "failed_at"
    t.uuid "initiated_by_user_id"
    t.jsonb "metadata", default: {}, null: false
    t.uuid "migration_chain_id"
    t.string "operation", limit: 16, null: false
    t.jsonb "plan_summary", default: {}, null: false
    t.uuid "root_resource_id", null: false
    t.string "root_resource_kind", limit: 64, null: false
    t.uuid "source_account_id"
    t.datetime "started_at"
    t.string "status", limit: 16, default: "planned", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_system_migrations_on_account_id_and_status"
    t.index ["account_id"], name: "index_system_migrations_on_account_id"
    t.index ["destination_peer_id"], name: "index_system_migrations_on_destination_peer_id"
    t.index ["initiated_by_user_id"], name: "index_system_migrations_on_initiated_by_user_id"
    t.index ["migration_chain_id"], name: "index_system_migrations_on_migration_chain_id"
    t.index ["operation"], name: "index_system_migrations_on_operation"
    t.index ["root_resource_kind", "root_resource_id"], name: "idx_on_root_resource_kind_root_resource_id_87428e8e2e"
    t.check_constraint "operation::text = ANY (ARRAY['duplicate'::character varying::text, 'migrate'::character varying::text])", name: "migrations_operation_enum"
    t.check_constraint "status::text = ANY (ARRAY['planned'::character varying::text, 'validating'::character varying::text, 'transferring'::character varying::text, 'conflict'::character varying::text, 'applying'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text])", name: "migrations_status_enum"
  end

  create_table "system_module_artifacts", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "architecture", null: false
    t.datetime "built_at", null: false
    t.text "cosign_bundle"
    t.datetime "created_at", null: false
    t.string "fsverity_root_hash"
    t.string "media_type", null: false
    t.uuid "node_module_version_id", null: false
    t.string "oci_digest", null: false
    t.string "oci_ref", null: false
    t.string "provenance_uri"
    t.integer "sbom_packages_count", default: 0, null: false
    t.jsonb "sbom_packages_data", default: []
    t.datetime "sbom_packages_synced_at"
    t.string "sbom_uri"
    t.bigint "size_bytes", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "vex_uri"
    t.index ["architecture"], name: "index_system_module_artifacts_on_architecture"
    t.index ["node_module_version_id", "architecture"], name: "idx_on_node_module_version_id_architecture_dd136a07bc", unique: true
    t.index ["node_module_version_id"], name: "index_system_module_artifacts_on_node_module_version_id"
    t.index ["oci_digest"], name: "index_system_module_artifacts_on_oci_digest"
    t.index ["sbom_packages_count"], name: "index_system_module_artifacts_on_sbom_packages_count"
    t.index ["sbom_packages_synced_at"], name: "index_system_module_artifacts_on_sbom_packages_synced_at"
  end

  create_table "system_module_build_batches", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "awaiting_signature_at"
    t.string "base_sha", null: false
    t.datetime "cancelled_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "dispatched_at"
    t.text "error_message"
    t.datetime "failed_at"
    t.integer "failed_count", default: 0, null: false
    t.string "head_sha", null: false
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "module_slugs", default: [], null: false
    t.integer "planned_count", default: 0, null: false
    t.datetime "publishing_at"
    t.boolean "shadow", default: false, null: false
    t.string "status", default: "planning", null: false
    t.integer "succeeded_count", default: 0, null: false
    t.string "trigger", default: "push", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_system_module_build_batches_on_account_id"
    t.index ["module_slugs"], name: "index_system_module_build_batches_on_module_slugs", using: :gin
    t.index ["shadow"], name: "index_system_module_build_batches_on_shadow"
    t.index ["status"], name: "index_system_module_build_batches_on_status"
    t.index ["trigger"], name: "index_system_module_build_batches_on_trigger"
  end

  create_table "system_module_dependencies", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "dependency_id", null: false
    t.string "dependency_type", default: "requires", null: false
    t.uuid "node_module_id", null: false
    t.boolean "required", default: true, null: false
    t.datetime "updated_at", null: false
    t.string "version_constraint"
    t.index ["dependency_id"], name: "index_system_module_dependencies_on_dependency_id"
    t.index ["dependency_type"], name: "index_system_module_dependencies_on_dependency_type"
    t.index ["node_module_id", "dependency_id"], name: "idx_on_node_module_id_dependency_id_a970a995f6", unique: true
    t.index ["node_module_id"], name: "index_system_module_dependencies_on_node_module_id"
    t.check_constraint "dependency_type::text = ANY (ARRAY['requires'::character varying::text, 'recommends'::character varying::text, 'conflicts'::character varying::text, 'provides'::character varying::text])", name: "system_module_dependencies_type_check"
  end

  create_table "system_module_puppet_assignments", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.uuid "node_module_id", null: false
    t.jsonb "parameters", default: {}, null: false
    t.integer "priority", default: 0, null: false
    t.uuid "puppet_module_id", null: false
    t.datetime "updated_at", null: false
    t.index ["config"], name: "index_system_module_puppet_assignments_on_config", using: :gin
    t.index ["enabled"], name: "index_system_module_puppet_assignments_on_enabled"
    t.index ["node_module_id", "puppet_module_id"], name: "idx_on_node_module_id_puppet_module_id_3371df9005", unique: true
    t.index ["node_module_id"], name: "index_system_module_puppet_assignments_on_node_module_id"
    t.index ["parameters"], name: "index_system_module_puppet_assignments_on_parameters", using: :gin
    t.index ["priority"], name: "index_system_module_puppet_assignments_on_priority"
    t.index ["puppet_module_id"], name: "index_system_module_puppet_assignments_on_puppet_module_id"
  end

  create_table "system_module_service_dependencies", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "depends_on_module_service_id", null: false
    t.string "kind", limit: 32, default: "requires_health", null: false
    t.uuid "module_service_id", null: false
    t.datetime "updated_at", null: false
    t.index ["depends_on_module_service_id"], name: "idx_on_depends_on_module_service_id_b120776bd4"
    t.index ["module_service_id", "depends_on_module_service_id"], name: "idx_on_module_service_id_depends_on_module_service__4253d06e17", unique: true
  end

  create_table "system_module_services", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "capabilities", default: [], null: false
    t.datetime "created_at", null: false
    t.jsonb "env", default: {}, null: false
    t.jsonb "exposed_ports", default: [], null: false
    t.string "health_endpoint", limit: 256
    t.integer "health_initial_delay_seconds", default: 10, null: false
    t.integer "health_interval_seconds", default: 30, null: false
    t.string "health_method", limit: 8, default: "GET", null: false
    t.integer "health_timeout_seconds", default: 5, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "name", limit: 100, null: false
    t.uuid "node_module_id", null: false
    t.string "restart_policy", limit: 32, default: "always", null: false
    t.uuid "service_user_id"
    t.text "start_command"
    t.text "stop_command"
    t.string "system_user", limit: 32
    t.text "unit_body"
    t.datetime "updated_at", null: false
    t.string "working_directory", limit: 512
    t.index ["account_id"], name: "index_system_module_services_on_account_id"
    t.index ["node_module_id", "name"], name: "index_system_module_services_on_node_module_id_and_name", unique: true
    t.index ["restart_policy"], name: "index_system_module_services_on_restart_policy"
    t.index ["service_user_id"], name: "index_system_module_services_on_service_user_id"
    t.index ["system_user"], name: "index_system_module_services_on_system_user"
  end

  create_table "system_module_user_declarations", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "node_module_id", null: false
    t.uuid "service_group_id"
    t.uuid "service_user_id"
    t.datetime "updated_at", null: false
    t.index ["node_module_id", "service_group_id"], name: "index_module_user_declarations_unique_group", unique: true, where: "(service_group_id IS NOT NULL)"
    t.index ["node_module_id", "service_user_id"], name: "index_module_user_declarations_unique_user", unique: true, where: "(service_user_id IS NOT NULL)"
    t.index ["node_module_id"], name: "index_system_module_user_declarations_on_node_module_id"
    t.index ["service_group_id"], name: "index_system_module_user_declarations_on_service_group_id"
    t.index ["service_user_id"], name: "index_system_module_user_declarations_on_service_user_id"
    t.check_constraint "service_user_id IS NOT NULL AND service_group_id IS NULL OR service_user_id IS NULL AND service_group_id IS NOT NULL", name: "system_module_user_declarations_exactly_one_target"
  end

  create_table "system_mount_encryption_keys", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "algorithm", null: false
    t.datetime "created_at", null: false
    t.text "encrypted_credentials"
    t.string "encryption_key_id"
    t.boolean "escrowed", default: true, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "migrated_to_vault_at"
    t.uuid "node_instance_id"
    t.datetime "revoked_at"
    t.uuid "storage_assignment_id", null: false
    t.datetime "updated_at", null: false
    t.string "vault_path"
    t.index ["node_instance_id"], name: "index_system_mount_encryption_keys_on_node_instance_id"
    t.index ["storage_assignment_id"], name: "index_system_mount_encryption_keys_on_storage_assignment_id"
    t.check_constraint "algorithm::text = ANY (ARRAY['aes-xts-plain64'::character varying::text, 'aes-256-gcm'::character varying::text, 'fscrypt-v2'::character varying::text])", name: "system_mount_encryption_keys_algorithm_check"
  end

  create_table "system_node_architectures", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "aliases", default: [], null: false
    t.string "apt_name"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "display_name"
    t.boolean "enabled", default: true, null: false
    t.string "family", default: "other", null: false
    t.string "image_checksum", comment: "SHA256 checksum of boot image file"
    t.uuid "image_file_object_id"
    t.string "image_format", comment: "Image format (raw, qcow2, vmdk, etc.)"
    t.boolean "is_canonical", default: false, null: false
    t.string "kernel_checksum", comment: "SHA256 checksum of kernel file"
    t.uuid "kernel_file_object_id"
    t.text "kernel_options"
    t.string "kernel_version", comment: "Kernel version string"
    t.string "name", null: false
    t.integer "node_platform_count", default: 0, null: false
    t.integer "package_count", default: 0, null: false
    t.integer "package_repository_count", default: 0, null: false
    t.boolean "public", default: false, null: false
    t.string "ramdisk_checksum", comment: "SHA256 checksum of ramdisk file"
    t.uuid "ramdisk_file_object_id"
    t.string "rpm_name"
    t.datetime "updated_at", null: false
    t.index ["aliases"], name: "idx_node_architectures_aliases_gin", using: :gin
    t.index ["apt_name"], name: "index_system_node_architectures_on_apt_name", where: "(apt_name IS NOT NULL)"
    t.index ["enabled"], name: "index_system_node_architectures_on_enabled"
    t.index ["family"], name: "index_system_node_architectures_on_family"
    t.index ["image_file_object_id"], name: "index_system_node_architectures_on_image_file_object_id"
    t.index ["is_canonical"], name: "index_system_node_architectures_on_is_canonical"
    t.index ["kernel_file_object_id"], name: "index_system_node_architectures_on_kernel_file_object_id"
    t.index ["name"], name: "index_system_node_architectures_on_name", unique: true
    t.index ["public"], name: "index_system_node_architectures_on_public"
    t.index ["ramdisk_file_object_id"], name: "index_system_node_architectures_on_ramdisk_file_object_id"
    t.index ["rpm_name"], name: "index_system_node_architectures_on_rpm_name", where: "(rpm_name IS NOT NULL)"
  end

  create_table "system_node_certificates", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.datetime "created_at", null: false
    t.text "encrypted_credentials"
    t.uuid "encryption_key_id"
    t.string "issuer_subject"
    t.datetime "migrated_to_vault_at"
    t.uuid "node_instance_id"
    t.datetime "not_after", null: false
    t.datetime "not_before", null: false
    t.text "pem_chain"
    t.string "revocation_reason"
    t.datetime "revoked_at"
    t.string "serial", null: false
    t.string "subject", null: false
    t.string "subject_kind", limit: 32, default: "instance", null: false
    t.datetime "updated_at", null: false
    t.string "vault_path"
    t.index ["account_id"], name: "index_system_node_certificates_on_account_id"
    t.index ["node_instance_id"], name: "index_system_node_certificates_on_node_instance_id"
    t.index ["not_after"], name: "index_system_node_certificates_on_not_after"
    t.index ["revoked_at"], name: "index_system_node_certificates_on_revoked_at"
    t.index ["serial"], name: "index_system_node_certificates_on_serial", unique: true
    t.index ["subject"], name: "index_system_node_certificates_on_subject"
    t.index ["subject_kind"], name: "index_system_node_certificates_on_subject_kind"
    t.check_constraint "node_instance_id IS NOT NULL OR account_id IS NOT NULL", name: "node_certificates_owner_present"
    t.check_constraint "subject_kind::text = ANY (ARRAY['instance'::character varying::text, 'federation_peer'::character varying::text])", name: "node_certificates_subject_kind_enum"
  end

  create_table "system_node_instance_peers", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "addresses", default: [], array: true
    t.jsonb "capabilities", default: {}
    t.datetime "created_at", null: false
    t.integer "daily_decision_budget", default: 10, null: false
    t.integer "daily_decision_used", default: 0, null: false
    t.datetime "daily_decision_window_start"
    t.jsonb "declared_skills", default: []
    t.boolean "enabled", default: false, null: false
    t.bigint "execution_count", default: 0, null: false
    t.bigint "execution_failure_count", default: 0, null: false
    t.datetime "first_announced_at"
    t.jsonb "granted_mcp_tools", default: [], null: false
    t.jsonb "granted_peer_skills", default: [], null: false
    t.string "handle", null: false
    t.datetime "last_announced_at"
    t.datetime "last_executed_at"
    t.jsonb "metadata", default: {}
    t.uuid "node_instance_id", null: false
    t.string "status", default: "registered", null: false
    t.decimal "trust_score", precision: 5, scale: 4, default: "0.5"
    t.datetime "updated_at", null: false
    t.index ["account_id", "handle"], name: "index_system_node_instance_peers_on_account_id_and_handle", unique: true
    t.index ["account_id"], name: "index_system_node_instance_peers_on_account_id"
    t.index ["enabled"], name: "index_system_node_instance_peers_on_enabled"
    t.index ["node_instance_id"], name: "index_system_node_instance_peers_on_node_instance_id", unique: true
    t.index ["status"], name: "index_system_node_instance_peers_on_status"
  end

  create_table "system_node_instances", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "agent_version"
    t.string "architecture", default: "amd64", null: false
    t.string "boot_id"
    t.string "booted_image_git_sha"
    t.jsonb "capabilities", default: {}, null: false
    t.string "claim_code"
    t.datetime "claimed_at"
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "discovered_at"
    t.string "discovered_dmi_uuid"
    t.string "discovered_hostname"
    t.string "discovered_mac"
    t.uuid "enrollment_token_id"
    t.uuid "instance_pool_id"
    t.text "key"
    t.datetime "last_heartbeat_at"
    t.datetime "last_sync_attempted_at"
    t.datetime "last_synced_at"
    t.decimal "latitude", precision: 10, scale: 7, comment: "Latitude coordinate"
    t.datetime "lease_expires_at"
    t.string "lifecycle_class"
    t.decimal "longitude", precision: 10, scale: 7, comment: "Longitude coordinate"
    t.string "mac_address", comment: "Primary MAC address"
    t.string "mtls_subject"
    t.string "name", null: false
    t.string "network_profile", default: "lightweight", null: false, comment: "OVS+OVN dual-profile selector — see System::NodeInstance::NETWORK_PROFILES"
    t.uuid "node_id", null: false
    t.datetime "ops_hold_at"
    t.uuid "ops_hold_by_id"
    t.datetime "ops_hold_expires_at"
    t.string "ops_hold_provider_state"
    t.string "ops_hold_reason"
    t.datetime "pool_acquired_at"
    t.string "pool_state"
    t.datetime "pool_warming_started_at"
    t.string "private_ip_address"
    t.boolean "private_netboot", default: false, comment: "Enable private netboot"
    t.uuid "provider_instance_type_id"
    t.uuid "provider_region_id"
    t.string "public_ip_address"
    t.jsonb "running_module_digests", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "variety", default: "cloud", null: false
    t.string "vpn_ip_address"
    t.index ["account_id"], name: "index_system_node_instances_on_account_id"
    t.index ["architecture"], name: "index_system_node_instances_on_architecture"
    t.index ["capabilities"], name: "index_system_node_instances_on_capabilities", using: :gin
    t.index ["claim_code"], name: "idx_node_instances_claim_code_unique", unique: true, where: "(claim_code IS NOT NULL)"
    t.index ["config"], name: "index_system_node_instances_on_config", using: :gin
    t.index ["discovered_mac"], name: "index_system_node_instances_on_discovered_mac"
    t.index ["enrollment_token_id"], name: "index_system_node_instances_on_enrollment_token_id"
    t.index ["instance_pool_id", "pool_state", "pool_warming_started_at"], name: "idx_node_instances_pool_acquire", where: "(instance_pool_id IS NOT NULL)"
    t.index ["instance_pool_id"], name: "index_system_node_instances_on_instance_pool_id"
    t.index ["last_heartbeat_at"], name: "index_system_node_instances_on_last_heartbeat_at"
    t.index ["last_sync_attempted_at"], name: "index_system_node_instances_on_last_sync_attempted_at"
    t.index ["last_synced_at"], name: "index_system_node_instances_on_last_synced_at"
    t.index ["lifecycle_class", "lease_expires_at"], name: "idx_node_instances_task_scoped_lease", where: "(lifecycle_class IS NOT NULL)"
    t.index ["mac_address"], name: "index_system_node_instances_on_mac_address", unique: true, where: "(mac_address IS NOT NULL)"
    t.index ["mtls_subject"], name: "index_system_node_instances_on_mtls_subject"
    t.index ["network_profile"], name: "index_system_node_instances_on_network_profile"
    t.index ["node_id", "name"], name: "index_system_node_instances_on_node_id_and_name", unique: true
    t.index ["node_id", "status"], name: "index_system_node_instances_on_node_id_and_status"
    t.index ["node_id", "variety"], name: "index_system_node_instances_on_node_id_and_variety"
    t.index ["node_id"], name: "index_system_node_instances_on_node_id"
    t.index ["ops_hold_at"], name: "idx_system_node_instances_on_ops_hold", where: "(ops_hold_at IS NOT NULL)"
    t.index ["provider_instance_type_id"], name: "index_system_node_instances_on_provider_instance_type_id"
    t.index ["provider_region_id", "status"], name: "index_system_node_instances_on_provider_region_id_and_status"
    t.index ["provider_region_id"], name: "index_system_node_instances_on_provider_region_id"
    t.index ["running_module_digests"], name: "index_system_node_instances_on_running_module_digests", using: :gin
    t.check_constraint "architecture::text = ANY (ARRAY['amd64'::character varying::text, 'arm64'::character varying::text])", name: "system_node_instances_architecture_check"
    t.check_constraint "instance_pool_id IS NULL AND pool_state IS NULL OR instance_pool_id IS NOT NULL AND pool_state IS NOT NULL", name: "chk_node_instances_pool_consistency"
    t.check_constraint "network_profile::text = ANY (ARRAY['lightweight'::character varying::text, 'heavyweight'::character varying::text])", name: "system_node_instances_network_profile_check"
    t.check_constraint "pool_state IS NULL OR (pool_state::text = ANY (ARRAY['warming'::character varying::text, 'ready'::character varying::text, 'claimed'::character varying::text, 'draining'::character varying::text, 'errored'::character varying::text]))", name: "chk_node_instances_pool_state"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'provisioning'::character varying::text, 'starting'::character varying::text, 'running'::character varying::text, 'stopping'::character varying::text, 'stopped'::character varying::text, 'rebooting'::character varying::text, 'terminated'::character varying::text, 'error'::character varying::text])", name: "system_node_instances_status_check"
    t.check_constraint "variety::text = ANY (ARRAY['cloud'::character varying::text, 'physical'::character varying::text, 'dynamic'::character varying::text])", name: "system_node_instances_variety_check"
  end

  create_table "system_node_module_assignments", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.boolean "auto_resolved", default: false, null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.uuid "node_id", null: false
    t.uuid "node_module_id", null: false
    t.integer "priority", default: 0, null: false
    t.uuid "source_template_module_id"
    t.datetime "updated_at", null: false
    t.index ["auto_resolved"], name: "index_system_node_module_assignments_on_auto_resolved"
    t.index ["config"], name: "index_system_node_module_assignments_on_config", using: :gin
    t.index ["enabled"], name: "index_system_node_module_assignments_on_enabled"
    t.index ["node_id", "node_module_id"], name: "idx_on_node_id_node_module_id_83be72ef4f", unique: true
    t.index ["node_id"], name: "index_system_node_module_assignments_on_node_id"
    t.index ["node_module_id"], name: "index_system_node_module_assignments_on_node_module_id"
    t.index ["priority"], name: "index_system_node_module_assignments_on_priority"
    t.index ["source_template_module_id"], name: "idx_on_source_template_module_id_ca62ce738b"
  end

  create_table "system_node_module_categories", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "color"
    t.uuid "config_category_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.string "icon"
    t.uuid "instance_category_id"
    t.string "name", null: false
    t.uuid "parent_id"
    t.integer "position", default: 0, null: false
    t.boolean "public", default: false, null: false
    t.datetime "updated_at", null: false
    t.string "variety", default: "subscription", null: false
    t.index ["account_id", "name"], name: "index_system_node_module_categories_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_system_node_module_categories_on_account_id"
    t.index ["config_category_id"], name: "index_system_node_module_categories_on_config_category_id"
    t.index ["enabled"], name: "index_system_node_module_categories_on_enabled"
    t.index ["instance_category_id"], name: "index_system_node_module_categories_on_instance_category_id"
    t.index ["parent_id"], name: "index_system_node_module_categories_on_parent_id"
    t.index ["position"], name: "index_system_node_module_categories_on_position"
    t.index ["public"], name: "index_system_node_module_categories_on_public"
    t.index ["variety"], name: "index_system_node_module_categories_on_variety"
    t.check_constraint "variety::text = ANY (ARRAY['subscription'::character varying::text, 'config'::character varying::text, 'instance'::character varying::text])", name: "system_node_module_categories_variety_check"
  end

  create_table "system_node_module_copy_paths", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "destination_path", null: false
    t.boolean "enabled", default: true, null: false
    t.string "name", null: false
    t.boolean "preserve_permissions", default: true, null: false
    t.boolean "recursive", default: false, null: false
    t.string "source_path", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_system_node_module_copy_paths_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_system_node_module_copy_paths_on_account_id"
    t.index ["enabled"], name: "index_system_node_module_copy_paths_on_enabled"
  end

  create_table "system_node_module_versions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "artifacts", default: {}, null: false
    t.datetime "blessed_at"
    t.text "changelog"
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.string "data_checksum"
    t.string "data_file_name"
    t.integer "data_file_size"
    t.jsonb "file_spec", default: {}, null: false
    t.string "fsverity_root_hash"
    t.datetime "live_at"
    t.jsonb "mask", default: {}, null: false
    t.uuid "node_module_id", null: false
    t.string "oci_digest"
    t.jsonb "package_spec", default: {}, null: false
    t.string "promotion_state", default: "built", null: false
    t.jsonb "protected_spec", default: [], null: false
    t.string "provenance_uri"
    t.datetime "retired_at"
    t.string "sbom_uri"
    t.datetime "staging_baked_at"
    t.datetime "updated_at", null: false
    t.integer "version_number", null: false
    t.string "vex_uri"
    t.index ["artifacts"], name: "index_system_node_module_versions_on_artifacts", using: :gin
    t.index ["created_by_id"], name: "index_system_node_module_versions_on_created_by_id"
    t.index ["data_checksum"], name: "index_system_node_module_versions_on_data_checksum"
    t.index ["node_module_id", "version_number"], name: "idx_on_node_module_id_version_number_56c400291d", unique: true
    t.index ["node_module_id"], name: "index_system_node_module_versions_on_node_module_id"
    t.index ["oci_digest"], name: "index_system_node_module_versions_on_oci_digest"
    t.index ["promotion_state"], name: "index_system_node_module_versions_on_promotion_state"
    t.index ["protected_spec"], name: "index_system_node_module_versions_on_protected_spec", using: :gin
    t.index ["version_number"], name: "index_system_node_module_versions_on_version_number"
    t.check_constraint "promotion_state::text = ANY (ARRAY['built'::character varying::text, 'staging'::character varying::text, 'blessed'::character varying::text, 'live'::character varying::text, 'retired'::character varying::text])", name: "system_node_module_versions_promotion_state_check"
  end

  create_table "system_node_modules", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.boolean "auto_generated", default: false, null: false
    t.boolean "auto_promote", default: true, null: false
    t.jsonb "capabilities", default: [], null: false, comment: "Capability tags this module provides (denormalized from manifest.dependencies.provides) — queried by ManifestImportService for capability:foo dependency resolution."
    t.uuid "category_id"
    t.jsonb "config", default: {}, null: false
    t.integer "consent_budget_per_day"
    t.integer "consent_budget_used_count", default: 0, null: false
    t.datetime "consent_budget_window_start_at"
    t.uuid "copy_path_id"
    t.string "cosign_identity_regexp", comment: "Sigstore Fulcio identity regexp the agent will accept (e.g. 'https://gitea.example.com/.+')"
    t.string "cosign_issuer_regexp", comment: "Sigstore Fulcio OIDC issuer regexp (e.g. 'https://gitea.example.com')"
    t.datetime "created_at", null: false
    t.uuid "current_version_id"
    t.integer "current_version_number", default: 0, null: false
    t.string "data_checksum"
    t.string "data_file_name"
    t.integer "data_file_size"
    t.jsonb "dependency_spec", default: [], null: false
    t.text "description"
    t.vector "embedding", limit: 1536
    t.datetime "embedding_generated_at"
    t.boolean "enabled", default: true, null: false
    t.jsonb "file_spec", default: [], null: false
    t.string "gitea_repo_full_name"
    t.text "init_restart"
    t.text "init_start"
    t.text "init_stop"
    t.boolean "lock_spec", default: false, null: false
    t.text "manifest_yaml"
    t.jsonb "mask", default: [], null: false
    t.string "name", null: false
    t.uuid "node_id"
    t.uuid "node_instance_id"
    t.uuid "node_platform_id"
    t.jsonb "package_spec", default: [], null: false
    t.uuid "parent_module_id"
    t.integer "priority", default: 0, null: false
    t.jsonb "protected_spec", default: [], null: false
    t.boolean "public", default: false, null: false
    t.boolean "reboot_required", default: false, null: false
    t.datetime "updated_at", null: false
    t.string "variety", default: "config", null: false
    t.string "webhook_secret"
    t.index ["account_id", "name"], name: "index_system_node_modules_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_system_node_modules_on_account_id"
    t.index ["auto_generated"], name: "index_system_node_modules_on_auto_generated"
    t.index ["capabilities"], name: "idx_system_node_modules_on_capabilities_gin", using: :gin
    t.index ["category_id"], name: "index_system_node_modules_on_category_id"
    t.index ["config"], name: "index_system_node_modules_on_config", using: :gin
    t.index ["copy_path_id"], name: "index_system_node_modules_on_copy_path_id"
    t.index ["current_version_id"], name: "index_system_node_modules_on_current_version_id"
    t.index ["current_version_number"], name: "index_system_node_modules_on_current_version_number"
    t.index ["data_checksum"], name: "index_system_node_modules_on_data_checksum"
    t.index ["embedding"], name: "idx_system_node_modules_embedding_hnsw", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["enabled"], name: "index_system_node_modules_on_enabled"
    t.index ["file_spec"], name: "index_system_node_modules_on_file_spec", using: :gin
    t.index ["gitea_repo_full_name"], name: "idx_uniq_system_node_modules_gitea_repo", unique: true, where: "(gitea_repo_full_name IS NOT NULL)"
    t.index ["lock_spec"], name: "index_system_node_modules_on_lock_spec"
    t.index ["mask"], name: "index_system_node_modules_on_mask", using: :gin
    t.index ["node_id"], name: "index_system_node_modules_on_node_id"
    t.index ["node_instance_id"], name: "index_system_node_modules_on_node_instance_id"
    t.index ["node_platform_id"], name: "index_system_node_modules_on_node_platform_id"
    t.index ["package_spec"], name: "index_system_node_modules_on_package_spec", using: :gin
    t.index ["parent_module_id", "node_id", "node_instance_id"], name: "idx_on_parent_module_id_node_id_node_instance_id_525ef5dee4"
    t.index ["parent_module_id"], name: "index_system_node_modules_on_parent_module_id"
    t.index ["priority"], name: "index_system_node_modules_on_priority"
    t.index ["protected_spec"], name: "index_system_node_modules_on_protected_spec", using: :gin
    t.index ["public"], name: "index_system_node_modules_on_public"
    t.index ["reboot_required"], name: "index_system_node_modules_on_reboot_required"
    t.index ["variety"], name: "index_system_node_modules_on_variety"
    t.check_constraint "variety::text = ANY (ARRAY['config'::character varying::text, 'instance'::character varying::text, 'subscription'::character varying::text])", name: "system_node_modules_variety_check"
  end

  create_table "system_node_platforms", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.text "build_script"
    t.string "cosign_identity_regexp", comment: "Sigstore Fulcio identity regexp the publication processor will accept (e.g. 'https://registry.example.com/powernode/.+')"
    t.string "cosign_issuer_regexp", comment: "Sigstore Fulcio OIDC issuer regexp (e.g. 'https://registry.example.com')"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "disk_image_built_at"
    t.uuid "disk_image_file_object_id"
    t.string "disk_image_git_sha", comment: "Git SHA of the source build that produced the active disk image"
    t.string "disk_image_oci_ref", comment: "Last-published OCI reference (e.g. registry.example.com/powernode/disk-images/ubuntu-24.04-rpi4:abc123)"
    t.text "disk_image_publication_error", comment: "Last error message if disk_image_publication_status='failed'"
    t.string "disk_image_publication_status", default: "none", null: false, comment: "none|verifying|published|failed — operator-facing status"
    t.integer "disk_image_retention_count", default: 3, null: false, comment: "Number of historical publications to retain before reaper purges (per platform)"
    t.string "disk_image_sha256"
    t.bigint "disk_image_size_bytes"
    t.boolean "enabled", default: true, null: false
    t.text "init_script"
    t.string "name", null: false
    t.uuid "node_architecture_id", null: false
    t.boolean "public", default: false, null: false
    t.text "sync_script"
    t.datetime "updated_at", null: false
    t.index ["account_id", "enabled"], name: "index_system_node_platforms_on_account_id_and_enabled"
    t.index ["account_id", "name"], name: "index_system_node_platforms_on_account_id_and_name", unique: true
    t.index ["account_id", "public"], name: "index_system_node_platforms_on_account_id_and_public"
    t.index ["account_id"], name: "index_system_node_platforms_on_account_id"
    t.index ["disk_image_file_object_id"], name: "index_system_node_platforms_on_disk_image_file_object_id"
    t.index ["node_architecture_id"], name: "index_system_node_platforms_on_node_architecture_id"
  end

  create_table "system_node_scripts", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.text "data"
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.string "name", null: false
    t.boolean "public", default: false, null: false
    t.datetime "updated_at", null: false
    t.string "variety", default: "custom", null: false
    t.index ["account_id", "enabled"], name: "index_system_node_scripts_on_account_id_and_enabled"
    t.index ["account_id", "name"], name: "index_system_node_scripts_on_account_id_and_name", unique: true
    t.index ["account_id", "public"], name: "index_system_node_scripts_on_account_id_and_public"
    t.index ["account_id", "variety"], name: "index_system_node_scripts_on_account_id_and_variety"
    t.index ["account_id"], name: "index_system_node_scripts_on_account_id"
    t.check_constraint "variety::text = ANY (ARRAY['build'::character varying::text, 'init'::character varying::text, 'sync'::character varying::text, 'custom'::character varying::text])", name: "system_node_scripts_variety_check"
  end

  create_table "system_node_templates", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "admin_user"
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.vector "embedding", limit: 1536
    t.datetime "embedding_generated_at"
    t.boolean "enabled", default: true, null: false
    t.string "name", null: false
    t.uuid "node_platform_id", null: false
    t.boolean "public", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "enabled"], name: "index_system_node_templates_on_account_id_and_enabled"
    t.index ["account_id", "name"], name: "index_system_node_templates_on_account_id_and_name", unique: true
    t.index ["account_id", "public"], name: "index_system_node_templates_on_account_id_and_public"
    t.index ["account_id"], name: "index_system_node_templates_on_account_id"
    t.index ["config"], name: "index_system_node_templates_on_config", using: :gin
    t.index ["embedding"], name: "idx_system_node_templates_embedding_hnsw", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["node_platform_id"], name: "index_system_node_templates_on_node_platform_id"
  end

  create_table "system_nodes", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.boolean "allocate_public_ip", default: false, null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.uuid "internal_ca_id"
    t.string "lifecycle_class", default: "persistent", null: false
    t.string "name", null: false
    t.uuid "node_template_id", null: false
    t.string "public_address"
    t.integer "runtime_amount", default: 0, comment: "Runtime tracking in minutes"
    t.text "ssh_host_key"
    t.string "ssh_host_key_fingerprint"
    t.text "ssh_key"
    t.string "ssh_key_fingerprint"
    t.string "ssh_key_type", default: "ed25519", null: false
    t.boolean "tmpfs_store", default: false, comment: "Use tmpfs for storage"
    t.datetime "updated_at", null: false
    t.uuid "worker_id"
    t.index ["account_id", "enabled"], name: "index_system_nodes_on_account_id_and_enabled"
    t.index ["account_id", "name"], name: "index_system_nodes_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_system_nodes_on_account_id"
    t.index ["config"], name: "index_system_nodes_on_config", using: :gin
    t.index ["internal_ca_id"], name: "index_system_nodes_on_internal_ca_id"
    t.index ["lifecycle_class"], name: "index_system_nodes_on_lifecycle_class"
    t.index ["node_template_id"], name: "index_system_nodes_on_node_template_id"
    t.index ["ssh_host_key_fingerprint"], name: "index_system_nodes_on_ssh_host_key_fingerprint"
    t.index ["ssh_key_fingerprint"], name: "index_system_nodes_on_ssh_key_fingerprint"
    t.index ["worker_id"], name: "index_system_nodes_on_worker_id"
    t.check_constraint "lifecycle_class::text = ANY (ARRAY['persistent'::character varying::text, 'ephemeral'::character varying::text, 'spot'::character varying::text])", name: "chk_system_nodes_lifecycle_class"
  end

  create_table "system_package_module_links", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "alternatives_chosen", default: {}, null: false
    t.string "architecture", null: false
    t.boolean "auto_generated", default: true, null: false
    t.datetime "created_at", null: false
    t.string "file_spec_source", default: "package_query", null: false
    t.datetime "last_synced_at"
    t.uuid "node_module_id", null: false
    t.string "package_name", null: false
    t.uuid "package_repository_id", null: false
    t.string "package_version", null: false
    t.jsonb "recommends_chosen", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["node_module_id"], name: "index_system_package_module_links_on_node_module_id", unique: true
    t.index ["package_repository_id", "package_name", "architecture"], name: "idx_on_package_repository_id_package_name_architect_7e7d951352"
    t.index ["package_repository_id"], name: "index_system_package_module_links_on_package_repository_id"
    t.check_constraint "file_spec_source::text = ANY (ARRAY['manual'::character varying::text, 'package_query'::character varying::text])", name: "chk_pkgmodlink_file_spec_source"
  end

  create_table "system_package_repositories", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.jsonb "apt_config", default: {}, null: false
    t.jsonb "architectures", default: ["amd64"], null: false
    t.string "base_url", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.string "kind", null: false
    t.text "last_sync_error"
    t.datetime "last_synced_at"
    t.string "name", null: false
    t.integer "package_count", default: 0, null: false
    t.integer "parser_version", default: 0, null: false
    t.integer "priority", default: 100, null: false
    t.jsonb "rpm_config", default: {}, null: false
    t.text "signing_key_armor"
    t.text "sync_fingerprint"
    t.string "sync_status", default: "idle", null: false
    t.datetime "updated_at", null: false
    t.string "vault_credential_path"
    t.string "visibility", default: "account", null: false
    t.index ["account_id", "name"], name: "idx_pkgrepo_account_name_unique", unique: true, where: "(account_id IS NOT NULL)"
    t.index ["account_id"], name: "index_system_package_repositories_on_account_id"
    t.index ["created_by_id"], name: "index_system_package_repositories_on_created_by_id"
    t.index ["enabled"], name: "index_system_package_repositories_on_enabled"
    t.index ["name"], name: "idx_pkgrepo_shared_name_unique", unique: true, where: "(account_id IS NULL)"
    t.index ["sync_status"], name: "index_system_package_repositories_on_sync_status"
    t.index ["visibility"], name: "index_system_package_repositories_on_visibility"
    t.check_constraint "kind::text = ANY (ARRAY['apt'::character varying::text, 'rpm'::character varying::text, 'dnf'::character varying::text])", name: "chk_pkgrepo_kind"
    t.check_constraint "sync_status::text = ANY (ARRAY['idle'::character varying::text, 'syncing'::character varying::text, 'failed'::character varying::text])", name: "chk_pkgrepo_sync_status"
    t.check_constraint "visibility::text = 'shared'::text AND account_id IS NULL OR visibility::text = 'account'::text AND account_id IS NOT NULL", name: "chk_pkgrepo_visibility_account_consistency"
    t.check_constraint "visibility::text = ANY (ARRAY['account'::character varying::text, 'shared'::character varying::text])", name: "chk_pkgrepo_visibility"
  end

  create_table "system_package_repository_platforms", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "node_platform_id", null: false
    t.uuid "package_repository_id", null: false
    t.datetime "updated_at", null: false
    t.index ["node_platform_id"], name: "index_system_package_repository_platforms_on_node_platform_id"
    t.index ["package_repository_id", "node_platform_id"], name: "idx_on_package_repository_id_node_platform_id_97de2a5713", unique: true
    t.index ["package_repository_id"], name: "idx_on_package_repository_id_b0312aad60"
  end

  create_table "system_packages", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "architecture", null: false
    t.jsonb "breaks", default: [], null: false
    t.jsonb "conflicts", default: [], null: false
    t.datetime "created_at", null: false
    t.jsonb "depends", default: [], null: false
    t.text "description"
    t.bigint "download_size_bytes"
    t.vector "embedding", limit: 1536
    t.datetime "embedding_generated_at"
    t.datetime "embedding_started_at"
    t.string "filename"
    t.string "homepage"
    t.bigint "installed_size_bytes"
    t.string "license"
    t.string "maintainer"
    t.string "name", null: false
    t.datetime "obsoleted_at"
    t.uuid "package_repository_id", null: false
    t.jsonb "pre_depends", default: [], null: false
    t.jsonb "provides", default: [], null: false
    t.jsonb "raw_metadata", default: {}, null: false
    t.jsonb "recommends", default: [], null: false
    t.string "release_version"
    t.jsonb "replaces", default: [], null: false
    t.string "section_or_group"
    t.string "sha256"
    t.string "sha512"
    t.jsonb "suggests", default: [], null: false
    t.text "summary"
    t.datetime "updated_at", null: false
    t.string "version", null: false
    t.index ["depends"], name: "idx_packages_depends_gin", using: :gin
    t.index ["description"], name: "idx_packages_description_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["embedding"], name: "idx_packages_embedding_hnsw", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["license"], name: "index_system_packages_on_license"
    t.index ["name", "architecture"], name: "index_system_packages_on_name_and_architecture"
    t.index ["name"], name: "idx_packages_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["obsoleted_at"], name: "index_system_packages_on_obsoleted_at", where: "(obsoleted_at IS NOT NULL)"
    t.index ["package_repository_id", "name", "architecture", "version"], name: "idx_on_package_repository_id_name_architecture_vers_070df3cd30", unique: true
    t.index ["package_repository_id"], name: "index_system_packages_on_package_repository_id"
    t.index ["provides"], name: "idx_packages_provides_gin", using: :gin
    t.index ["section_or_group"], name: "index_system_packages_on_section_or_group"
  end

  create_table "system_peer_capability_revocations", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "jti"
    t.string "reason"
    t.string "sub"
    t.datetime "updated_at", null: false
    t.index ["account_id", "expires_at"], name: "idx_on_account_id_expires_at_0caf747af0"
    t.index ["account_id"], name: "index_system_peer_capability_revocations_on_account_id"
  end

  create_table "system_peer_capability_signing_keys", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.text "encrypted_credentials"
    t.string "handle", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "migrated_to_vault_at"
    t.string "public_key_b64", null: false
    t.string "revocation_reason"
    t.datetime "revoked_at"
    t.uuid "rotated_from_id"
    t.datetime "updated_at", null: false
    t.string "vault_path"
    t.index ["account_id", "handle"], name: "idx_on_account_id_handle_f2428572a0", unique: true
    t.index ["account_id"], name: "index_system_peer_capability_signing_keys_on_account_id"
    t.index ["rotated_from_id"], name: "index_system_peer_capability_signing_keys_on_rotated_from_id"
  end

  create_table "system_platform_deployments", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "name", limit: 100, null: false
    t.uuid "node_template_id", null: false
    t.string "public_dns_hostname", limit: 256
    t.string "satellite_extension_slug", limit: 64
    t.string "service_role", limit: 32, null: false
    t.integer "target_replicas", default: 1, null: false
    t.datetime "updated_at", null: false
    t.uuid "virtual_ip_id"
    t.index ["account_id", "name"], name: "index_system_platform_deployments_on_account_id_and_name", unique: true
    t.index ["account_id", "service_role"], name: "idx_on_account_id_service_role_5e382f42b3"
    t.index ["node_template_id"], name: "index_system_platform_deployments_on_node_template_id"
    t.index ["satellite_extension_slug"], name: "index_system_platform_deployments_on_satellite_extension_slug", where: "(satellite_extension_slug IS NOT NULL)"
    t.index ["virtual_ip_id"], name: "index_system_platform_deployments_on_virtual_ip_id"
    t.check_constraint "target_replicas >= 0", name: "platform_deployments_target_replicas_non_negative"
  end

  create_table "system_project_metrics", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "correlation_id"
    t.datetime "created_at", null: false
    t.string "metric_name", null: false
    t.string "metric_type", null: false
    t.uuid "mission_id", null: false
    t.datetime "sampled_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "value", default: {}, null: false
    t.index ["metric_type"], name: "index_system_project_metrics_on_metric_type"
    t.index ["mission_id", "metric_name", "sampled_at"], name: "idx_on_mission_id_metric_name_sampled_at_708816fc6f", order: { sampled_at: :desc }
    t.index ["mission_id"], name: "index_system_project_metrics_on_mission_id"
    t.index ["sampled_at"], name: "index_system_project_metrics_on_sampled_at"
  end

  create_table "system_provider_availability_zones", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "capabilities", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.string "name", null: false
    t.uuid "provider_region_id", null: false
    t.string "status", default: "available", null: false
    t.datetime "updated_at", null: false
    t.string "zone_code", null: false
    t.index "provider_region_id, lower((name)::text)", name: "idx_on_provider_region_id_lower_name_text_22d90a3a20", unique: true
    t.index ["capabilities"], name: "index_system_provider_availability_zones_on_capabilities", using: :gin
    t.index ["provider_region_id", "enabled"], name: "idx_on_provider_region_id_enabled_5fd74dd1c4"
    t.index ["provider_region_id", "zone_code"], name: "idx_on_provider_region_id_zone_code_83ae317fad", unique: true
    t.index ["provider_region_id"], name: "index_system_provider_availability_zones_on_provider_region_id"
    t.index ["status"], name: "index_system_provider_availability_zones_on_status"
    t.check_constraint "status::text = ANY (ARRAY['available'::character varying::text, 'impaired'::character varying::text, 'unavailable'::character varying::text])", name: "system_provider_availability_zones_status_check"
  end

  create_table "system_provider_connections", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.text "access_key"
    t.uuid "account_id", null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.string "endpoint_url"
    t.text "last_test_message"
    t.string "last_test_status"
    t.datetime "last_tested_at"
    t.string "name", null: false
    t.uuid "provider_id", null: false
    t.text "secret_key"
    t.string "status", default: "pending", null: false
    t.string "tenant"
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_system_provider_connections_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_system_provider_connections_on_account_id"
    t.index ["config"], name: "index_system_provider_connections_on_config", using: :gin
    t.index ["provider_id", "enabled"], name: "index_system_provider_connections_on_provider_id_and_enabled"
    t.index ["provider_id"], name: "index_system_provider_connections_on_provider_id"
    t.index ["status"], name: "index_system_provider_connections_on_status"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'connected'::character varying::text, 'error'::character varying::text])", name: "system_provider_connections_status_check"
  end

  create_table "system_provider_credentials", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.integer "consecutive_failures", default: 0, null: false
    t.datetime "created_at", null: false
    t.text "credentials"
    t.boolean "is_active", default: true, null: false
    t.text "last_error"
    t.datetime "last_test_at"
    t.string "last_test_status"
    t.string "name", null: false
    t.uuid "provider_id", null: false
    t.integer "scope", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "provider_id"], name: "idx_system_provider_creds_account_owned", where: "(scope = 0)"
    t.index ["account_id"], name: "index_system_provider_credentials_on_account_id"
    t.index ["provider_id"], name: "index_system_provider_credentials_on_provider_id"
    t.index ["scope"], name: "index_system_provider_credentials_on_scope"
  end

  create_table "system_provider_instance_types", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "USD"
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.integer "gpu_count", default: 0, null: false
    t.integer "gpu_memory_mb"
    t.string "gpu_type"
    t.decimal "hourly_price", precision: 10, scale: 4
    t.string "instance_type_code", null: false
    t.integer "memory_mb"
    t.string "name", null: false
    t.string "network_performance"
    t.string "processor_type"
    t.uuid "provider_id", null: false
    t.boolean "public", default: false, null: false
    t.jsonb "specs", default: {}, null: false
    t.integer "storage_gb"
    t.datetime "updated_at", null: false
    t.integer "vcpus"
    t.index "account_id, provider_id, lower((name)::text)", name: "idx_on_account_id_provider_id_lower_name_text_e444bb7539", unique: true
    t.index ["account_id", "enabled"], name: "index_system_provider_instance_types_on_account_id_and_enabled"
    t.index ["account_id"], name: "index_system_provider_instance_types_on_account_id"
    t.index ["gpu_type", "gpu_count"], name: "idx_system_provider_instance_types_gpu", where: "(gpu_count > 0)"
    t.index ["provider_id", "instance_type_code"], name: "idx_on_provider_id_instance_type_code_ced29cad6e", unique: true
    t.index ["provider_id"], name: "index_system_provider_instance_types_on_provider_id"
    t.index ["specs"], name: "index_system_provider_instance_types_on_specs", using: :gin
  end

  create_table "system_provider_network_subnets", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "availability_zone_id"
    t.integer "available_ip_count"
    t.string "cidr_block", null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "external_id"
    t.boolean "is_public", default: false, null: false
    t.boolean "map_public_ip_on_launch", default: false, null: false
    t.string "name", null: false
    t.uuid "network_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["availability_zone_id"], name: "index_system_provider_network_subnets_on_availability_zone_id"
    t.index ["cidr_block"], name: "index_system_provider_network_subnets_on_cidr_block"
    t.index ["config"], name: "index_system_provider_network_subnets_on_config", using: :gin
    t.index ["external_id"], name: "index_system_provider_network_subnets_on_external_id"
    t.index ["is_public"], name: "index_system_provider_network_subnets_on_is_public"
    t.index ["network_id", "name"], name: "index_system_provider_network_subnets_on_network_id_and_name", unique: true
    t.index ["network_id"], name: "index_system_provider_network_subnets_on_network_id"
    t.index ["status"], name: "index_system_provider_network_subnets_on_status"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'available'::character varying::text, 'deleting'::character varying::text, 'deleted'::character varying::text, 'error'::character varying::text])", name: "system_provider_network_subnets_status_check"
  end

  create_table "system_provider_networks", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "cidr_block", null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enable_dns_hostnames", default: false, null: false
    t.boolean "enable_dns_support", default: true, null: false
    t.string "external_id"
    t.boolean "is_default", default: false, null: false
    t.string "name", null: false
    t.uuid "provider_id", null: false
    t.uuid "provider_region_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_system_provider_networks_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_system_provider_networks_on_account_id"
    t.index ["cidr_block"], name: "index_system_provider_networks_on_cidr_block"
    t.index ["config"], name: "index_system_provider_networks_on_config", using: :gin
    t.index ["external_id"], name: "index_system_provider_networks_on_external_id"
    t.index ["is_default"], name: "index_system_provider_networks_on_is_default"
    t.index ["provider_id"], name: "index_system_provider_networks_on_provider_id"
    t.index ["provider_region_id"], name: "index_system_provider_networks_on_provider_region_id"
    t.index ["status"], name: "index_system_provider_networks_on_status"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'available'::character varying::text, 'deleting'::character varying::text, 'deleted'::character varying::text, 'error'::character varying::text])", name: "system_provider_networks_status_check"
  end

  create_table "system_provider_regions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "capabilities", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.string "endpoint_url"
    t.string "kernel_image"
    t.string "machine_image"
    t.string "name", null: false
    t.uuid "provider_id", null: false
    t.string "ramdisk_image"
    t.string "region_code", null: false
    t.datetime "updated_at", null: false
    t.index "account_id, provider_id, lower((name)::text)", name: "idx_on_account_id_provider_id_lower_name_text_256dd28654", unique: true
    t.index ["account_id", "enabled"], name: "index_system_provider_regions_on_account_id_and_enabled"
    t.index ["account_id"], name: "index_system_provider_regions_on_account_id"
    t.index ["capabilities"], name: "index_system_provider_regions_on_capabilities", using: :gin
    t.index ["provider_id", "region_code"], name: "index_system_provider_regions_on_provider_id_and_region_code", unique: true
    t.index ["provider_id"], name: "index_system_provider_regions_on_provider_id"
  end

  create_table "system_provider_volume_members", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "cloud_volume_id", comment: "Cloud provider volume ID for this member"
    t.jsonb "config", default: {}
    t.datetime "created_at", null: false
    t.string "device_name", comment: "Device name (e.g., /dev/sdb)"
    t.integer "member_index", default: 0, comment: "Order in RAID array"
    t.uuid "provider_volume_id", null: false
    t.integer "size_gb", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["cloud_volume_id"], name: "index_system_provider_volume_members_on_cloud_volume_id"
    t.index ["provider_volume_id", "member_index"], name: "idx_on_provider_volume_id_member_index_d195aa25b1", unique: true
    t.index ["provider_volume_id"], name: "index_system_provider_volume_members_on_provider_volume_id"
  end

  create_table "system_provider_volume_snapshots", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "encrypted", default: false, null: false
    t.string "external_id"
    t.string "name", null: false
    t.integer "progress", default: 0, null: false
    t.integer "size_gb", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.uuid "volume_id"
    t.index ["account_id", "name"], name: "index_system_provider_volume_snapshots_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_system_provider_volume_snapshots_on_account_id"
    t.index ["config"], name: "index_system_provider_volume_snapshots_on_config", using: :gin
    t.index ["encrypted"], name: "index_system_provider_volume_snapshots_on_encrypted"
    t.index ["external_id"], name: "index_system_provider_volume_snapshots_on_external_id"
    t.index ["status"], name: "index_system_provider_volume_snapshots_on_status"
    t.index ["volume_id"], name: "index_system_provider_volume_snapshots_on_volume_id"
    t.check_constraint "progress >= 0 AND progress <= 100", name: "system_provider_volume_snapshots_progress_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'creating'::character varying::text, 'completed'::character varying::text, 'error'::character varying::text, 'deleting'::character varying::text, 'deleted'::character varying::text])", name: "system_provider_volume_snapshots_status_check"
  end

  create_table "system_provider_volume_types", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.integer "max_iops"
    t.integer "max_size_gb", default: 16384, null: false
    t.integer "max_throughput"
    t.integer "min_iops"
    t.integer "min_size_gb", default: 1, null: false
    t.integer "min_throughput"
    t.string "name", null: false
    t.uuid "provider_id", null: false
    t.jsonb "specs", default: {}, null: false
    t.datetime "updated_at", null: false
    t.string "volume_type", null: false
    t.index ["account_id", "name"], name: "index_system_provider_volume_types_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_system_provider_volume_types_on_account_id"
    t.index ["enabled"], name: "index_system_provider_volume_types_on_enabled"
    t.index ["provider_id"], name: "index_system_provider_volume_types_on_provider_id"
    t.index ["specs"], name: "index_system_provider_volume_types_on_specs", using: :gin
    t.index ["volume_type"], name: "index_system_provider_volume_types_on_volume_type"
    t.check_constraint "volume_type::text = ANY (ARRAY['gp2'::character varying::text, 'gp3'::character varying::text, 'io1'::character varying::text, 'io2'::character varying::text, 'st1'::character varying::text, 'sc1'::character varying::text, 'standard'::character varying::text, 'ssd'::character varying::text, 'hdd'::character varying::text, 'nfs'::character varying::text, 'iscsi'::character varying::text, 'smb'::character varying::text, 'custom'::character varying::text])", name: "system_provider_volume_types_type_check"
  end

  create_table "system_provider_volumes", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "availability_zone_id"
    t.bigint "capacity_bytes", comment: "Total capacity in bytes"
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.boolean "delete_on_termination", default: false, null: false
    t.text "description"
    t.string "device_name"
    t.boolean "encrypted", default: false, null: false
    t.string "external_id"
    t.integer "iops"
    t.string "name", null: false
    t.uuid "node_instance_id"
    t.uuid "provider_region_id"
    t.integer "raid_level", comment: "RAID level (0 for striping, 1 for mirroring)"
    t.integer "size_gb", null: false
    t.string "status", default: "creating", null: false
    t.integer "throughput"
    t.datetime "updated_at", null: false
    t.bigint "used_bytes", default: 0, comment: "Used space in bytes"
    t.uuid "volume_type_id"
    t.index ["account_id", "name"], name: "index_system_provider_volumes_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_system_provider_volumes_on_account_id"
    t.index ["availability_zone_id"], name: "index_system_provider_volumes_on_availability_zone_id"
    t.index ["config"], name: "index_system_provider_volumes_on_config", using: :gin
    t.index ["encrypted"], name: "index_system_provider_volumes_on_encrypted"
    t.index ["external_id"], name: "index_system_provider_volumes_on_external_id"
    t.index ["node_instance_id"], name: "index_system_provider_volumes_on_node_instance_id"
    t.index ["provider_region_id"], name: "index_system_provider_volumes_on_provider_region_id"
    t.index ["status"], name: "index_system_provider_volumes_on_status"
    t.index ["volume_type_id"], name: "index_system_provider_volumes_on_volume_type_id"
    t.check_constraint "status::text = ANY (ARRAY['creating'::character varying::text, 'available'::character varying::text, 'in-use'::character varying::text, 'deleting'::character varying::text, 'deleted'::character varying::text, 'error'::character varying::text])", name: "system_provider_volumes_status_check"
  end

  create_table "system_providers", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "capabilities", default: {}, null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.string "name", null: false
    t.string "provider_type", null: false
    t.boolean "public", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "enabled"], name: "index_system_providers_on_account_id_and_enabled"
    t.index ["account_id", "name"], name: "index_system_providers_on_account_id_and_name", unique: true
    t.index ["account_id", "provider_type"], name: "index_system_providers_on_account_id_and_provider_type"
    t.index ["account_id"], name: "index_system_providers_on_account_id"
    t.index ["capabilities"], name: "index_system_providers_on_capabilities", using: :gin
    t.index ["config"], name: "index_system_providers_on_config", using: :gin
  end

  create_table "system_puppet_modules", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "author"
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.jsonb "dependencies", default: [], null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.string "forge_name"
    t.string "license"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.string "project_url"
    t.boolean "public", default: false, null: false
    t.string "source_url"
    t.datetime "updated_at", null: false
    t.string "version"
    t.index ["account_id", "name"], name: "index_system_puppet_modules_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_system_puppet_modules_on_account_id"
    t.index ["config"], name: "index_system_puppet_modules_on_config", using: :gin
    t.index ["dependencies"], name: "index_system_puppet_modules_on_dependencies", using: :gin
    t.index ["enabled"], name: "index_system_puppet_modules_on_enabled"
    t.index ["forge_name"], name: "index_system_puppet_modules_on_forge_name"
    t.index ["metadata"], name: "index_system_puppet_modules_on_metadata", using: :gin
    t.index ["public"], name: "index_system_puppet_modules_on_public"
  end

  create_table "system_puppet_resources", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "data"
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.boolean "exported", default: false, null: false
    t.string "name", null: false
    t.jsonb "parameters", default: {}, null: false
    t.string "path"
    t.uuid "puppet_module_id", null: false
    t.string "resource_type", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["config"], name: "index_system_puppet_resources_on_config", using: :gin
    t.index ["enabled"], name: "index_system_puppet_resources_on_enabled"
    t.index ["exported"], name: "index_system_puppet_resources_on_exported"
    t.index ["parameters"], name: "index_system_puppet_resources_on_parameters", using: :gin
    t.index ["puppet_module_id", "name"], name: "index_system_puppet_resources_on_puppet_module_id_and_name", unique: true
    t.index ["puppet_module_id"], name: "index_system_puppet_resources_on_puppet_module_id"
    t.index ["resource_type"], name: "index_system_puppet_resources_on_resource_type"
    t.check_constraint "resource_type::text = ANY (ARRAY['file'::character varying::text, 'package'::character varying::text, 'service'::character varying::text, 'exec'::character varying::text, 'user'::character varying::text, 'group'::character varying::text, 'cron'::character varying::text, 'mount'::character varying::text, 'host'::character varying::text, 'notify'::character varying::text, 'class'::character varying::text, 'define'::character varying::text, 'custom'::character varying::text])", name: "system_puppet_resources_type_check"
  end

  create_table "system_region_instance_types", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.boolean "available", default: true, null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "USD"
    t.decimal "hourly_price", precision: 10, scale: 4
    t.uuid "provider_instance_type_id", null: false
    t.uuid "provider_region_id", null: false
    t.datetime "updated_at", null: false
    t.index ["provider_instance_type_id"], name: "idx_on_provider_instance_type_id_72b7029b53"
    t.index ["provider_region_id", "available"], name: "idx_on_provider_region_id_available_bf1e064fb9"
    t.index ["provider_region_id", "provider_instance_type_id"], name: "idx_on_provider_region_id_provider_instance_type_id_619ba1cec5", unique: true
    t.index ["provider_region_id"], name: "index_system_region_instance_types_on_provider_region_id"
  end

  create_table "system_region_volume_types", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.uuid "provider_region_id", null: false
    t.datetime "updated_at", null: false
    t.uuid "volume_type_id", null: false
    t.index ["enabled"], name: "index_system_region_volume_types_on_enabled"
    t.index ["provider_region_id", "volume_type_id"], name: "idx_on_provider_region_id_volume_type_id_3f2d0afc1c", unique: true
    t.index ["provider_region_id"], name: "index_system_region_volume_types_on_provider_region_id"
    t.index ["volume_type_id"], name: "index_system_region_volume_types_on_volume_type_id"
  end

  create_table "system_sdwan_access_grants", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "granted_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.uuid "granted_by_id"
    t.jsonb "metadata", default: {}, null: false
    t.string "revocation_reason"
    t.datetime "revoked_at"
    t.uuid "sdwan_network_id", null: false
    t.string "status", default: "active", null: false
    t.string "tags", default: [], array: true
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["account_id"], name: "index_system_sdwan_access_grants_on_account_id"
    t.index ["granted_by_id"], name: "index_system_sdwan_access_grants_on_granted_by_id"
    t.index ["sdwan_network_id", "user_id"], name: "idx_on_sdwan_network_id_user_id_cb7dc7c04d", unique: true
    t.index ["sdwan_network_id"], name: "index_system_sdwan_access_grants_on_sdwan_network_id"
    t.index ["status"], name: "index_system_sdwan_access_grants_on_status"
    t.index ["user_id"], name: "index_system_sdwan_access_grants_on_user_id"
  end

  create_table "system_sdwan_account_bgps", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.bigint "as_number", null: false
    t.datetime "created_at", null: false
    t.integer "default_local_pref", default: 100, null: false
    t.uuid "default_route_policy_id"
    t.boolean "enabled", default: true, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "router_id_strategy", default: "peer_overlay_ipv6_hash", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_system_sdwan_account_bgps_on_account_id", unique: true
    t.index ["as_number"], name: "index_system_sdwan_account_bgps_on_as_number", unique: true
    t.index ["default_route_policy_id"], name: "index_system_sdwan_account_bgps_on_default_route_policy_id"
    t.check_constraint "as_number >= '4200000000'::bigint AND as_number <= '4294967294'::bigint", name: "sdwan_account_bgps_rfc6996_private"
  end

  create_table "system_sdwan_bgp_sessions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "last_error"
    t.datetime "last_observed_at", null: false
    t.datetime "last_state_change_at"
    t.string "neighbor_address", null: false
    t.uuid "neighbor_peer_id"
    t.integer "prefixes_received", default: 0
    t.integer "prefixes_sent", default: 0
    t.uuid "sdwan_network_id", null: false
    t.uuid "sdwan_peer_id", null: false
    t.string "state", default: "idle", null: false
    t.datetime "updated_at", null: false
    t.integer "uptime_seconds", default: 0
    t.index ["neighbor_peer_id"], name: "index_system_sdwan_bgp_sessions_on_neighbor_peer_id"
    t.index ["sdwan_network_id"], name: "index_system_sdwan_bgp_sessions_on_sdwan_network_id"
    t.index ["sdwan_peer_id", "neighbor_address"], name: "idx_on_sdwan_peer_id_neighbor_address_eee6501f89", unique: true
    t.index ["sdwan_peer_id"], name: "index_system_sdwan_bgp_sessions_on_sdwan_peer_id"
    t.index ["state"], name: "index_system_sdwan_bgp_sessions_on_state"
  end

  create_table "system_sdwan_configurations", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "account_prefix_48", null: false
    t.datetime "created_at", null: false
    t.string "instance_prefix_40", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_system_sdwan_configurations_on_account_id", unique: true
    t.index ["account_prefix_48"], name: "index_system_sdwan_configurations_on_account_prefix_48", unique: true
    t.index ["instance_prefix_40"], name: "index_system_sdwan_configurations_on_instance_prefix_40"
  end

  create_table "system_sdwan_constellation_signing_keys", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.text "encrypted_credentials"
    t.string "handle", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "migrated_to_vault_at"
    t.string "public_key_b64", null: false
    t.string "revocation_reason"
    t.datetime "revoked_at"
    t.uuid "rotated_from_id"
    t.datetime "updated_at", null: false
    t.string "vault_path"
    t.index ["account_id", "handle"], name: "idx_on_account_id_handle_f07d158a95", unique: true
    t.index ["account_id"], name: "index_system_sdwan_constellation_signing_keys_on_account_id"
    t.index ["rotated_from_id"], name: "idx_on_rotated_from_id_1cb79b41a3"
  end

  create_table "system_sdwan_firewall_rules", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "action", default: "accept", null: false
    t.datetime "created_at", null: false
    t.string "direction", default: "both", null: false
    t.int4range "dst_port_range"
    t.jsonb "dst_selector", default: {}, null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "last_compiled_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.integer "priority", default: 1000, null: false
    t.string "protocol", default: "any", null: false
    t.uuid "sdwan_network_id", null: false
    t.jsonb "src_selector", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_system_sdwan_firewall_rules_on_account_id"
    t.index ["enabled"], name: "index_system_sdwan_firewall_rules_on_enabled"
    t.index ["sdwan_network_id", "name"], name: "index_system_sdwan_firewall_rules_on_sdwan_network_id_and_name", unique: true
    t.index ["sdwan_network_id", "priority"], name: "idx_on_sdwan_network_id_priority_4bfb18f99c"
    t.index ["sdwan_network_id"], name: "index_system_sdwan_firewall_rules_on_sdwan_network_id"
  end

  create_table "system_sdwan_flow_samples", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.inet "dst_ip", null: false
    t.integer "dst_port"
    t.datetime "flow_end_at", null: false
    t.datetime "flow_start_at", null: false
    t.uuid "ipfix_collector_id", null: false
    t.datetime "observed_at", null: false
    t.bigint "octet_count", default: 0, null: false
    t.bigint "packet_count", default: 0, null: false
    t.integer "protocol", null: false
    t.inet "src_ip", null: false
    t.integer "src_port"
    t.datetime "updated_at", null: false
    t.index ["account_id", "observed_at"], name: "index_system_sdwan_flow_samples_on_account_id_and_observed_at", order: { observed_at: :desc }
    t.index ["ipfix_collector_id", "observed_at"], name: "idx_on_ipfix_collector_id_observed_at_37c3f078dd", order: { observed_at: :desc }
  end

  create_table "system_sdwan_host_bridges", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "applied_at"
    t.string "bridge_name", limit: 15, null: false
    t.datetime "created_at", null: false
    t.datetime "draining_at"
    t.string "ipv4_cidr", limit: 64
    t.string "ipv6_cidr", limit: 64
    t.string "kind", default: "linux", null: false
    t.jsonb "metadata", default: {}, null: false
    t.uuid "node_instance_id", null: false
    t.datetime "removed_at"
    t.integer "short_id", null: false
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_system_sdwan_host_bridges_on_account_id"
    t.index ["node_instance_id", "bridge_name"], name: "idx_on_node_instance_id_bridge_name_44ef700eac", unique: true
    t.index ["node_instance_id", "short_id"], name: "idx_on_node_instance_id_short_id_9b4413c61e", unique: true
    t.index ["node_instance_id"], name: "index_system_sdwan_host_bridges_on_node_instance_id"
    t.index ["state"], name: "index_system_sdwan_host_bridges_on_state"
    t.check_constraint "kind::text = ANY (ARRAY['linux'::character varying::text, 'ovs'::character varying::text])", name: "sdwan_host_bridges_kind_check"
    t.check_constraint "short_id >= 1 AND short_id <= 9999", name: "sdwan_host_bridges_short_id_range"
    t.check_constraint "state::text = ANY (ARRAY['pending'::character varying::text, 'active'::character varying::text, 'draining'::character varying::text, 'removed'::character varying::text])", name: "sdwan_host_bridges_state_check"
  end

  create_table "system_sdwan_host_vrf_assignments", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "applied_at"
    t.datetime "created_at", null: false
    t.datetime "draining_at"
    t.jsonb "metadata", default: {}, null: false
    t.uuid "node_instance_id", null: false
    t.datetime "removed_at"
    t.uuid "sdwan_network_id", null: false
    t.integer "short_id", null: false
    t.string "state", default: "pending", null: false
    t.integer "table_id", null: false
    t.datetime "updated_at", null: false
    t.string "vrf_name", limit: 15, null: false
    t.index ["account_id"], name: "index_system_sdwan_host_vrf_assignments_on_account_id"
    t.index ["node_instance_id", "sdwan_network_id"], name: "idx_on_node_instance_id_sdwan_network_id_830c83748d", unique: true
    t.index ["node_instance_id", "short_id"], name: "idx_on_node_instance_id_short_id_72f8eaf4b1", unique: true
    t.index ["node_instance_id", "table_id"], name: "idx_on_node_instance_id_table_id_bb4aa0d718", unique: true
    t.index ["node_instance_id", "vrf_name"], name: "idx_on_node_instance_id_vrf_name_3021d83c63", unique: true
    t.index ["node_instance_id"], name: "index_system_sdwan_host_vrf_assignments_on_node_instance_id"
    t.index ["sdwan_network_id"], name: "index_system_sdwan_host_vrf_assignments_on_sdwan_network_id"
    t.index ["state"], name: "index_system_sdwan_host_vrf_assignments_on_state"
    t.check_constraint "short_id >= 1 AND short_id <= 9999", name: "sdwan_hva_short_id_range"
    t.check_constraint "state::text = ANY (ARRAY['pending'::character varying::text, 'active'::character varying::text, 'draining'::character varying::text, 'removed'::character varying::text])", name: "sdwan_hva_state_check"
    t.check_constraint "table_id >= 100 AND table_id <= 65535 AND (table_id <> ALL (ARRAY[253, 254, 255]))", name: "sdwan_hva_table_id_range"
  end

  create_table "system_sdwan_ipfix_collectors", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.string "host", null: false
    t.string "name", null: false
    t.integer "port", default: 4739, null: false
    t.integer "sampling_rate", default: 1, null: false
    t.jsonb "settings", default: {}, null: false
    t.string "state", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_system_sdwan_ipfix_collectors_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_system_sdwan_ipfix_collectors_on_account_id"
    t.index ["state"], name: "index_system_sdwan_ipfix_collectors_on_state"
    t.check_constraint "port >= 1 AND port <= 65535", name: "chk_sdwan_ipfix_port_range"
    t.check_constraint "sampling_rate >= 1", name: "chk_sdwan_ipfix_sampling_min"
    t.check_constraint "state::text = ANY (ARRAY['active'::character varying::text, 'disabled'::character varying::text])", name: "chk_sdwan_ipfix_state"
  end

  create_table "system_sdwan_membership_credentials", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "constellation_handle", null: false
    t.datetime "created_at", null: false
    t.text "envelope_json", null: false
    t.datetime "issued_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "not_after", null: false
    t.datetime "not_before", null: false
    t.datetime "refresh_after", null: false
    t.bigint "revision", default: 0, null: false
    t.string "revocation_reason"
    t.datetime "revoked_at"
    t.uuid "sdwan_network_id", null: false
    t.uuid "sdwan_peer_id", null: false
    t.text "signature_b64", null: false
    t.string "signed_with_vault_path"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_system_sdwan_membership_credentials_on_account_id"
    t.index ["not_after"], name: "index_system_sdwan_membership_credentials_on_not_after"
    t.index ["sdwan_network_id"], name: "index_system_sdwan_membership_credentials_on_sdwan_network_id"
    t.index ["sdwan_peer_id", "sdwan_network_id", "revision"], name: "idx_on_sdwan_peer_id_sdwan_network_id_revision_3ee573444c"
    t.index ["sdwan_peer_id", "sdwan_network_id"], name: "idx_sdwan_mc_one_active_per_peer_network", unique: true, where: "((status)::text = 'active'::text)"
    t.index ["sdwan_peer_id"], name: "index_system_sdwan_membership_credentials_on_sdwan_peer_id"
    t.index ["status"], name: "index_system_sdwan_membership_credentials_on_status"
    t.check_constraint "not_after > not_before", name: "sdwan_mc_window_ordered"
    t.check_constraint "revision >= 0", name: "sdwan_mc_revision_nonneg"
  end

  create_table "system_sdwan_networks", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.boolean "advertise_overlay_subnet", default: true, null: false
    t.string "cidr_64", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "last_compiled_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.string "pod_subnet_prefix"
    t.integer "route_reflector_redundancy", default: 1, null: false
    t.string "routing_protocol", default: "static", null: false
    t.jsonb "settings", default: {}, null: false
    t.string "slug", null: false
    t.string "status", default: "registered", null: false
    t.string "tags", default: [], array: true
    t.datetime "updated_at", null: false
    t.string "vrf_name_template", default: "sdwan-{handle}", null: false
    t.index ["account_id", "name"], name: "index_system_sdwan_networks_on_account_id_and_name", unique: true
    t.index ["account_id", "slug"], name: "index_system_sdwan_networks_on_account_id_and_slug", unique: true
    t.index ["account_id"], name: "index_system_sdwan_networks_on_account_id"
    t.index ["cidr_64"], name: "index_system_sdwan_networks_on_cidr_64", unique: true
    t.index ["routing_protocol"], name: "index_system_sdwan_networks_on_routing_protocol"
    t.index ["status"], name: "index_system_sdwan_networks_on_status"
  end

  create_table "system_sdwan_ovn_acls", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "action", limit: 16, null: false
    t.datetime "activated_at"
    t.datetime "created_at", null: false
    t.string "direction", limit: 16, null: false
    t.text "match", null: false
    t.string "name", limit: 63, null: false
    t.integer "priority", default: 1000, null: false
    t.datetime "removed_at"
    t.uuid "sdwan_ovn_logical_switch_id", null: false
    t.string "state", limit: 16, default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_system_sdwan_ovn_acls_on_account_id"
    t.index ["sdwan_ovn_logical_switch_id", "name"], name: "idx_on_sdwan_ovn_logical_switch_id_name_735393d448", unique: true
    t.index ["sdwan_ovn_logical_switch_id", "state", "priority", "name"], name: "idx_on_sdwan_ovn_logical_switch_id_state_priority_n_97ebf80650"
    t.index ["sdwan_ovn_logical_switch_id"], name: "index_system_sdwan_ovn_acls_on_sdwan_ovn_logical_switch_id"
  end

  create_table "system_sdwan_ovn_deployments", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "activated_at"
    t.datetime "bootstrapped_at"
    t.datetime "created_at", null: false
    t.datetime "degraded_at"
    t.string "nb_db_endpoint"
    t.string "northd_host"
    t.string "sb_db_endpoint"
    t.jsonb "settings", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_system_sdwan_ovn_deployments_on_account_id", unique: true
    t.index ["status"], name: "index_system_sdwan_ovn_deployments_on_status"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'bootstrapping'::character varying::text, 'active'::character varying::text, 'degraded'::character varying::text])", name: "sdwan_ovn_deployments_status_check"
  end

  create_table "system_sdwan_ovn_logical_switch_ports", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "activated_at"
    t.jsonb "addresses", default: [], null: false
    t.datetime "created_at", null: false
    t.uuid "host_node_instance_id"
    t.string "kind", default: "vm", null: false
    t.string "mac", limit: 17, null: false
    t.string "name", limit: 63, null: false
    t.datetime "removed_at"
    t.uuid "sdwan_ovn_logical_switch_id", null: false
    t.jsonb "settings", default: {}, null: false
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_system_sdwan_ovn_logical_switch_ports_on_account_id"
    t.index ["host_node_instance_id"], name: "idx_on_host_node_instance_id_0c77da48ba"
    t.index ["kind"], name: "index_system_sdwan_ovn_logical_switch_ports_on_kind"
    t.index ["sdwan_ovn_logical_switch_id", "name"], name: "idx_on_sdwan_ovn_logical_switch_id_name_afcd7bf4ac", unique: true
    t.index ["sdwan_ovn_logical_switch_id"], name: "idx_on_sdwan_ovn_logical_switch_id_592e86c6e0"
    t.index ["state"], name: "index_system_sdwan_ovn_logical_switch_ports_on_state"
    t.check_constraint "kind::text = ANY (ARRAY['vm'::character varying::text, 'container'::character varying::text, 'external'::character varying::text])", name: "sdwan_ovn_lsps_kind_check"
    t.check_constraint "state::text = ANY (ARRAY['pending'::character varying::text, 'active'::character varying::text, 'removed'::character varying::text])", name: "sdwan_ovn_lsps_state_check"
  end

  create_table "system_sdwan_ovn_logical_switches", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "activated_at"
    t.string "cidr", limit: 64
    t.datetime "created_at", null: false
    t.string "description"
    t.string "name", limit: 63, null: false
    t.datetime "removed_at"
    t.uuid "sdwan_ovn_deployment_id", null: false
    t.jsonb "settings", default: {}, null: false
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_system_sdwan_ovn_logical_switches_on_account_id"
    t.index ["sdwan_ovn_deployment_id", "name"], name: "idx_on_sdwan_ovn_deployment_id_name_bf953e02b6", unique: true
    t.index ["sdwan_ovn_deployment_id"], name: "idx_on_sdwan_ovn_deployment_id_ece610cc47"
    t.index ["state"], name: "index_system_sdwan_ovn_logical_switches_on_state"
    t.check_constraint "state::text = ANY (ARRAY['pending'::character varying::text, 'active'::character varying::text, 'removed'::character varying::text])", name: "sdwan_ovn_lswitches_state_check"
  end

  create_table "system_sdwan_peer_keys", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_credentials"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "migrated_to_vault_at"
    t.string "public_key", null: false
    t.string "revocation_reason"
    t.datetime "revoked_at"
    t.uuid "rotated_from_id"
    t.uuid "sdwan_peer_id", null: false
    t.datetime "updated_at", null: false
    t.string "vault_path"
    t.index ["public_key"], name: "index_system_sdwan_peer_keys_on_public_key", unique: true
    t.index ["rotated_from_id"], name: "index_system_sdwan_peer_keys_on_rotated_from_id"
    t.index ["sdwan_peer_id"], name: "idx_sdwan_peer_keys_one_active_per_peer", unique: true, where: "(revoked_at IS NULL)"
  end

  create_table "system_sdwan_peers", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "assigned_address", null: false
    t.integer "bgp_local_pref_override"
    t.string "bgp_peer_group"
    t.boolean "bgp_route_reflector_client", default: false, null: false
    t.string "bgp_router_id_override"
    t.jsonb "bgp_session_state", default: {}, null: false
    t.jsonb "capabilities", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "endpoint_host"
    t.string "endpoint_host_v4"
    t.string "endpoint_host_v6"
    t.integer "endpoint_port"
    t.string "lan_subnets", default: [], array: true
    t.datetime "last_compiled_at"
    t.datetime "last_handshake_at"
    t.integer "listen_port", default: 51820, null: false
    t.jsonb "metadata", default: {}, null: false
    t.uuid "node_instance_id", null: false
    t.boolean "publicly_reachable", default: false, null: false
    t.uuid "sdwan_network_id", null: false
    t.string "status", default: "pending", null: false
    t.string "tags", default: [], null: false, array: true
    t.datetime "updated_at", null: false
    t.index ["account_id", "assigned_address"], name: "index_system_sdwan_peers_on_account_id_and_assigned_address", unique: true
    t.index ["account_id"], name: "index_system_sdwan_peers_on_account_id"
    t.index ["bgp_peer_group"], name: "index_system_sdwan_peers_on_bgp_peer_group"
    t.index ["bgp_route_reflector_client"], name: "index_system_sdwan_peers_on_bgp_route_reflector_client"
    t.index ["endpoint_host_v4"], name: "index_system_sdwan_peers_on_endpoint_host_v4"
    t.index ["endpoint_host_v6"], name: "index_system_sdwan_peers_on_endpoint_host_v6"
    t.index ["lan_subnets"], name: "index_sdwan_peers_on_lan_subnets", using: :gin
    t.index ["node_instance_id"], name: "index_system_sdwan_peers_on_node_instance_id"
    t.index ["publicly_reachable"], name: "index_system_sdwan_peers_on_publicly_reachable"
    t.index ["sdwan_network_id", "node_instance_id"], name: "idx_on_sdwan_network_id_node_instance_id_81e55720ce", unique: true
    t.index ["sdwan_network_id"], name: "index_system_sdwan_peers_on_sdwan_network_id"
    t.index ["status"], name: "index_system_sdwan_peers_on_status"
    t.index ["tags"], name: "index_system_sdwan_peers_on_tags", using: :gin
  end

  create_table "system_sdwan_port_mappings", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.string "description", limit: 255
    t.boolean "enabled", default: true, null: false
    t.datetime "last_compiled_at"
    t.integer "listen_port", null: false
    t.integer "max_connections"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", limit: 64, null: false
    t.string "protocol", default: "tcp", null: false
    t.integer "rate_limit"
    t.uuid "sdwan_network_id", null: false
    t.uuid "sdwan_peer_id", null: false
    t.jsonb "source_cidrs", default: [], null: false
    t.uuid "target_peer_id"
    t.integer "target_port"
    t.uuid "target_virtual_ip_id"
    t.datetime "updated_at", null: false
    t.index ["account_id", "sdwan_network_id"], name: "idx_on_account_id_sdwan_network_id_23c6d274d0"
    t.index ["account_id"], name: "index_system_sdwan_port_mappings_on_account_id"
    t.index ["sdwan_network_id"], name: "index_system_sdwan_port_mappings_on_sdwan_network_id"
    t.index ["sdwan_peer_id", "listen_port", "protocol"], name: "idx_on_sdwan_peer_id_listen_port_protocol_2acc7d7331", unique: true
    t.index ["sdwan_peer_id"], name: "index_system_sdwan_port_mappings_on_sdwan_peer_id"
    t.index ["target_peer_id"], name: "index_system_sdwan_port_mappings_on_target_peer_id"
    t.index ["target_virtual_ip_id"], name: "index_system_sdwan_port_mappings_on_target_virtual_ip_id"
    t.check_constraint "((target_peer_id IS NOT NULL)::integer + (target_virtual_ip_id IS NOT NULL)::integer) = 1", name: "sdwan_port_mappings_exactly_one_target"
    t.check_constraint "listen_port >= 1 AND listen_port <= 65535", name: "sdwan_port_mappings_listen_port_range"
    t.check_constraint "protocol::text = ANY (ARRAY['tcp'::character varying::text, 'udp'::character varying::text])", name: "sdwan_port_mappings_protocol_enum"
  end

  create_table "system_sdwan_route_leaks", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "activated_at"
    t.uuid "approved_by_id"
    t.datetime "created_at", null: false
    t.uuid "dest_network_id", null: false
    t.string "direction", default: "one_way", null: false
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "prefix_filter", default: [], null: false
    t.string "reason"
    t.datetime "revoked_at"
    t.uuid "source_network_id", null: false
    t.string "state", default: "proposed", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_system_sdwan_route_leaks_on_account_id"
    t.index ["approved_by_id"], name: "index_system_sdwan_route_leaks_on_approved_by_id"
    t.index ["dest_network_id"], name: "index_system_sdwan_route_leaks_on_dest_network_id"
    t.index ["source_network_id", "dest_network_id", "direction"], name: "idx_on_source_network_id_dest_network_id_direction_2c12449eae", unique: true
    t.index ["source_network_id"], name: "index_system_sdwan_route_leaks_on_source_network_id"
    t.index ["state"], name: "index_system_sdwan_route_leaks_on_state"
    t.check_constraint "direction::text = ANY (ARRAY['one_way'::character varying::text, 'bidirectional'::character varying::text])", name: "sdwan_route_leaks_direction_check"
    t.check_constraint "source_network_id <> dest_network_id", name: "sdwan_route_leaks_distinct_networks"
    t.check_constraint "state::text = ANY (ARRAY['proposed'::character varying::text, 'active'::character varying::text, 'revoked'::character varying::text])", name: "sdwan_route_leaks_state_check"
  end

  create_table "system_sdwan_route_policies", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.string "description", limit: 255
    t.string "direction", null: false
    t.boolean "enabled", default: true, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "name", limit: 64, null: false
    t.string "scope", default: "account", null: false
    t.uuid "scope_resource_id"
    t.jsonb "statements", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_system_sdwan_route_policies_on_account_id_and_name", unique: true
    t.index ["account_id", "scope"], name: "index_system_sdwan_route_policies_on_account_id_and_scope"
    t.index ["account_id"], name: "index_system_sdwan_route_policies_on_account_id"
    t.index ["scope", "scope_resource_id"], name: "idx_on_scope_scope_resource_id_cfab977127"
    t.check_constraint "direction::text = ANY (ARRAY['import'::character varying::text, 'export'::character varying::text])", name: "sdwan_route_policies_direction_enum"
    t.check_constraint "scope::text = ANY (ARRAY['account'::character varying::text, 'network'::character varying::text, 'peer'::character varying::text])", name: "sdwan_route_policies_scope_enum"
  end

  create_table "system_sdwan_services", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "backend_host"
    t.integer "backend_port", null: false
    t.uuid "backend_vip_id"
    t.string "client_auth", default: "none", null: false
    t.datetime "created_at", null: false
    t.string "edge_mode", default: "passthrough", null: false
    t.string "local_auth_mode", default: "authenticated", null: false
    t.uuid "local_certificate_id"
    t.boolean "local_enabled", default: false, null: false
    t.string "local_required_group"
    t.string "local_required_permission"
    t.boolean "local_strip_prefix", default: true, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "name", limit: 255, null: false
    t.string "protocol", default: "https", null: false
    t.boolean "public_enabled", default: false, null: false
    t.string "slug", limit: 64, null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "slug"], name: "index_system_sdwan_services_on_account_id_and_slug", unique: true
    t.index ["account_id"], name: "index_system_sdwan_services_on_account_id"
    t.index ["backend_vip_id"], name: "index_system_sdwan_services_on_backend_vip_id"
    t.index ["local_certificate_id"], name: "index_system_sdwan_services_on_local_certificate_id"
    t.index ["public_enabled"], name: "index_system_sdwan_services_on_public_enabled"
    t.check_constraint "backend_port >= 1 AND backend_port <= 65535", name: "sdwan_services_backend_port_range"
    t.check_constraint "backend_vip_id IS NOT NULL OR backend_host IS NOT NULL", name: "sdwan_services_backend_present"
    t.check_constraint "local_auth_mode::text = ANY (ARRAY['public'::character varying::text, 'authenticated'::character varying::text, 'scoped'::character varying::text])", name: "sdwan_services_local_auth_mode_enum"
    t.check_constraint "protocol::text = ANY (ARRAY['https'::character varying::text, 'http'::character varying::text, 'tcp'::character varying::text, 'tls'::character varying::text])", name: "sdwan_services_protocol_enum"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'disabled'::character varying::text])", name: "sdwan_services_status_enum"
  end

  create_table "system_sdwan_subnet_advertisements", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.text "as_path"
    t.datetime "created_at", null: false
    t.datetime "first_seen_at"
    t.datetime "last_seen_at"
    t.integer "local_pref"
    t.integer "med"
    t.jsonb "metadata", default: {}, null: false
    t.uuid "origin_peer_id"
    t.string "prefix", null: false
    t.uuid "sdwan_network_id", null: false
    t.uuid "sdwan_peer_id", null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.uuid "via_peer_id"
    t.datetime "withdrawn_at"
    t.index ["account_id"], name: "index_system_sdwan_subnet_advertisements_on_account_id"
    t.index ["sdwan_network_id", "prefix"], name: "idx_on_sdwan_network_id_prefix_d40b5207bd"
    t.index ["sdwan_network_id"], name: "index_system_sdwan_subnet_advertisements_on_sdwan_network_id"
    t.index ["sdwan_peer_id", "source"], name: "idx_on_sdwan_peer_id_source_8ee4d8e81d"
    t.index ["sdwan_peer_id"], name: "index_system_sdwan_subnet_advertisements_on_sdwan_peer_id"
    t.index ["source"], name: "index_system_sdwan_subnet_advertisements_on_source"
    t.index ["withdrawn_at"], name: "index_system_sdwan_subnet_advertisements_on_withdrawn_at"
  end

  create_table "system_sdwan_user_devices", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "assigned_address", null: false
    t.datetime "created_at", null: false
    t.text "encrypted_credentials"
    t.string "label", null: false
    t.datetime "last_downloaded_at"
    t.datetime "last_seen_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "migrated_to_vault_at"
    t.string "public_key", null: false
    t.string "revocation_reason"
    t.datetime "revoked_at"
    t.uuid "sdwan_access_grant_id", null: false
    t.datetime "updated_at", null: false
    t.string "vault_path"
    t.index ["assigned_address"], name: "index_system_sdwan_user_devices_on_assigned_address", unique: true
    t.index ["public_key"], name: "index_system_sdwan_user_devices_on_public_key", unique: true
    t.index ["revoked_at"], name: "index_system_sdwan_user_devices_on_revoked_at"
    t.index ["sdwan_access_grant_id", "label"], name: "idx_on_sdwan_access_grant_id_label_d9a1450048", unique: true
    t.index ["sdwan_access_grant_id"], name: "index_system_sdwan_user_devices_on_sdwan_access_grant_id"
  end

  create_table "system_sdwan_virtual_ip_assignments", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "assumed_at", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "reason", null: false
    t.datetime "released_at"
    t.uuid "sdwan_peer_id", null: false
    t.uuid "sdwan_virtual_ip_id", null: false
    t.string "triggered_by_signal_correlation_id"
    t.uuid "triggered_by_user_id"
    t.datetime "updated_at", null: false
    t.index ["released_at"], name: "index_system_sdwan_virtual_ip_assignments_on_released_at"
    t.index ["sdwan_peer_id"], name: "index_system_sdwan_virtual_ip_assignments_on_sdwan_peer_id"
    t.index ["sdwan_virtual_ip_id", "sdwan_peer_id"], name: "idx_sdwan_vip_assignments_one_active_holder_per_vip_peer", unique: true, where: "(released_at IS NULL)"
    t.index ["sdwan_virtual_ip_id"], name: "idx_on_sdwan_virtual_ip_id_ce637ca0e6"
  end

  create_table "system_sdwan_virtual_ips", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.integer "advertised_local_pref", default: 100
    t.integer "advertised_med", default: 0
    t.boolean "anycast", default: false, null: false
    t.string "cidr", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.uuid "failover_holder_peer_ids", default: [], array: true
    t.uuid "holder_peer_ids", default: [], array: true
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.uuid "sdwan_network_id", null: false
    t.string "state", default: "pending", null: false
    t.string "tags", default: [], array: true
    t.datetime "updated_at", null: false
    t.index ["account_id", "cidr"], name: "index_system_sdwan_virtual_ips_on_account_id_and_cidr", unique: true
    t.index ["account_id"], name: "index_system_sdwan_virtual_ips_on_account_id"
    t.index ["anycast"], name: "index_system_sdwan_virtual_ips_on_anycast"
    t.index ["sdwan_network_id", "name"], name: "index_system_sdwan_virtual_ips_on_sdwan_network_id_and_name", unique: true
    t.index ["sdwan_network_id"], name: "index_system_sdwan_virtual_ips_on_sdwan_network_id"
    t.index ["state"], name: "index_system_sdwan_virtual_ips_on_state"
  end

  create_table "system_service_groups", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "applied_at"
    t.datetime "created_at", null: false
    t.datetime "draining_at"
    t.integer "gid", null: false
    t.string "groupname", limit: 32, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "removed_at"
    t.string "state", limit: 32, default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["gid"], name: "index_system_service_groups_on_gid", unique: true
    t.index ["groupname"], name: "index_system_service_groups_on_groupname_live", unique: true, where: "((state)::text = ANY (ARRAY[('pending'::character varying)::text, ('active'::character varying)::text, ('draining'::character varying)::text]))"
    t.check_constraint "gid >= 70000 AND gid <= 99999", name: "system_service_groups_gid_in_range"
    t.check_constraint "state::text = ANY (ARRAY['pending'::character varying::text, 'active'::character varying::text, 'draining'::character varying::text, 'removed'::character varying::text])", name: "system_service_groups_state_enum"
  end

  create_table "system_service_user_group_memberships", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "service_group_id", null: false
    t.uuid "service_user_id", null: false
    t.datetime "updated_at", null: false
    t.index ["service_group_id"], name: "idx_on_service_group_id_0b6d6fa86a"
    t.index ["service_user_id", "service_group_id"], name: "idx_on_service_user_id_service_group_id_1b66fbb283", unique: true
  end

  create_table "system_service_users", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "applied_at"
    t.datetime "created_at", null: false
    t.datetime "draining_at"
    t.string "gecos", limit: 256, default: "", null: false
    t.string "home", limit: 256, default: "/var/empty", null: false
    t.jsonb "metadata", default: {}, null: false
    t.uuid "primary_group_id", null: false
    t.datetime "removed_at"
    t.string "shell", limit: 128, default: "/usr/sbin/nologin", null: false
    t.string "state", limit: 32, default: "active", null: false
    t.integer "uid", null: false
    t.datetime "updated_at", null: false
    t.string "username", limit: 32, null: false
    t.index ["primary_group_id"], name: "index_system_service_users_on_primary_group_id"
    t.index ["uid"], name: "index_system_service_users_on_uid", unique: true
    t.index ["username"], name: "index_system_service_users_on_username_live", unique: true, where: "((state)::text = ANY (ARRAY[('pending'::character varying)::text, ('active'::character varying)::text, ('draining'::character varying)::text]))"
    t.check_constraint "state::text = ANY (ARRAY['pending'::character varying::text, 'active'::character varying::text, 'draining'::character varying::text, 'removed'::character varying::text])", name: "system_service_users_state_enum"
    t.check_constraint "uid >= 70000 AND uid <= 99999", name: "system_service_users_uid_in_range"
  end

  create_table "system_slo_definitions", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enforces_autonomy", default: false, null: false
    t.decimal "error_rate_max_pct", precision: 5, scale: 2
    t.integer "latency_p99_max_ms"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.uuid "node_module_id", null: false
    t.datetime "updated_at", null: false
    t.decimal "uptime_target_pct", precision: 5, scale: 2
    t.string "window", default: "1d", null: false
    t.index ["node_module_id", "name"], name: "index_system_slo_definitions_on_node_module_id_and_name", unique: true
    t.index ["node_module_id"], name: "index_system_slo_definitions_on_node_module_id"
  end

  create_table "system_storage_assignments", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.boolean "auto_mount", default: true, null: false
    t.datetime "chown_completed_at"
    t.text "chown_last_error"
    t.integer "chown_previous_gid"
    t.integer "chown_previous_uid"
    t.datetime "chown_started_at"
    t.string "chown_state", limit: 32, default: "complete", null: false
    t.uuid "chown_task_id"
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.string "encryption_mode", default: "inherit", null: false
    t.text "error_message"
    t.uuid "file_storage_id", null: false
    t.datetime "last_mounted_at"
    t.datetime "last_status_at"
    t.jsonb "mount_options", default: {}, null: false
    t.string "mount_path", null: false
    t.uuid "node_instance_id", null: false
    t.string "owner_kind", limit: 32, default: "service_user", null: false
    t.boolean "read_only", default: false, null: false
    t.uuid "sdwan_network_id"
    t.uuid "sdwan_virtual_ip_id"
    t.uuid "service_user_id"
    t.uuid "shared_group_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_system_storage_assignments_on_account_id"
    t.index ["chown_state"], name: "index_system_storage_assignments_chown_in_flight", where: "((chown_state)::text <> 'complete'::text)"
    t.index ["file_storage_id", "node_instance_id"], name: "idx_on_file_storage_id_node_instance_id_e39b886367", unique: true
    t.index ["file_storage_id"], name: "index_system_storage_assignments_on_file_storage_id"
    t.index ["node_instance_id", "mount_path"], name: "idx_on_node_instance_id_mount_path_fd6fa07e10", unique: true
    t.index ["node_instance_id"], name: "index_system_storage_assignments_on_node_instance_id"
    t.index ["sdwan_network_id"], name: "index_system_storage_assignments_on_sdwan_network_id"
    t.index ["sdwan_virtual_ip_id"], name: "index_system_storage_assignments_on_sdwan_virtual_ip_id"
    t.index ["service_user_id"], name: "index_system_storage_assignments_on_service_user_id"
    t.index ["shared_group_id"], name: "index_system_storage_assignments_on_shared_group_id"
    t.check_constraint "chown_state::text = ANY (ARRAY['complete'::character varying::text, 'pending'::character varying::text, 'running'::character varying::text, 'failed'::character varying::text, 'manual_required'::character varying::text])", name: "system_storage_assignments_chown_state_enum"
    t.check_constraint "encryption_mode::text = ANY (ARRAY['inherit'::character varying::text, 'none'::character varying::text, 'fscrypt'::character varying::text, 'luks'::character varying::text, 'client_side_aes'::character varying::text])", name: "system_storage_assignments_encryption_mode_check"
    t.check_constraint "owner_kind::text = 'service_user'::text AND service_user_id IS NOT NULL OR owner_kind::text <> 'service_user'::text AND service_user_id IS NULL", name: "system_storage_assignments_owner_kind_consistency"
    t.check_constraint "owner_kind::text = ANY (ARRAY['service_user'::character varying::text, 'operator'::character varying::text, 'nobody'::character varying::text, 'root'::character varying::text])", name: "system_storage_assignments_owner_kind_enum"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'provisioning'::character varying::text, 'mounted'::character varying::text, 'degraded'::character varying::text, 'unmounting'::character varying::text, 'failed'::character varying::text, 'disabled'::character varying::text])", name: "system_storage_assignments_status_check"
  end

  create_table "system_storage_credentials", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_credentials"
    t.string "encryption_key_id"
    t.datetime "expires_at"
    t.string "kind", null: false
    t.datetime "last_rotated_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "migrated_to_vault_at"
    t.uuid "node_instance_id", null: false
    t.string "status", default: "issued", null: false
    t.uuid "storage_assignment_id", null: false
    t.datetime "updated_at", null: false
    t.string "vault_path"
    t.index ["node_instance_id"], name: "index_system_storage_credentials_on_node_instance_id"
    t.index ["storage_assignment_id", "status"], name: "idx_on_storage_assignment_id_status_5aa5747ca0"
    t.index ["storage_assignment_id"], name: "index_system_storage_credentials_on_storage_assignment_id"
    t.check_constraint "kind::text = ANY (ARRAY['peer_ip_acl'::character varying::text, 'cifs_user_pass'::character varying::text, 'sts_token'::character varying::text, 'tls_cert'::character varying::text, 'webdav_basic'::character varying::text])", name: "system_storage_credentials_kind_check"
    t.check_constraint "status::text = ANY (ARRAY['issued'::character varying::text, 'active'::character varying::text, 'rotating'::character varying::text, 'revoked'::character varying::text, 'expired'::character varying::text, 'failed'::character varying::text])", name: "system_storage_credentials_status_check"
  end

  create_table "system_storage_migrations", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "approved_at"
    t.jsonb "audit_log", default: [], null: false
    t.bigint "bytes_copied"
    t.bigint "bytes_total"
    t.bigint "bytes_verified"
    t.datetime "cancelled_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "error_message"
    t.datetime "failed_at"
    t.uuid "initiated_by_user_id"
    t.jsonb "metadata", default: {}, null: false
    t.uuid "node_instance_id", null: false
    t.jsonb "plan", default: {}, null: false
    t.string "role", limit: 64, null: false
    t.string "snapshot_subpath", limit: 512
    t.string "source_subpath", limit: 512
    t.uuid "source_volume_id", null: false
    t.datetime "started_at"
    t.string "status", limit: 32, default: "planned", null: false
    t.string "target_subpath", limit: 512
    t.uuid "target_volume_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_system_storage_migrations_on_account_id_and_status"
    t.index ["account_id"], name: "index_system_storage_migrations_on_account_id"
    t.index ["initiated_by_user_id"], name: "index_system_storage_migrations_on_initiated_by_user_id"
    t.index ["node_instance_id"], name: "index_system_storage_migrations_on_node_instance_id"
    t.index ["source_volume_id"], name: "index_system_storage_migrations_on_source_volume_id"
    t.index ["status"], name: "index_system_storage_migrations_on_status"
    t.index ["target_volume_id"], name: "index_system_storage_migrations_on_target_volume_id"
    t.check_constraint "source_volume_id <> target_volume_id", name: "storage_migration_source_ne_target"
  end

  create_table "system_sudoers_grants", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "commands", default: [], null: false
    t.datetime "created_at", null: false
    t.jsonb "flags", default: [], null: false
    t.string "grant_id", limit: 64, null: false
    t.uuid "node_module_id", null: false
    t.string "runas_group", limit: 32
    t.string "runas_user", limit: 32, default: "root", null: false
    t.uuid "service_user_id", null: false
    t.string "state", limit: 32, default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["node_module_id", "grant_id"], name: "index_system_sudoers_grants_on_node_module_id_and_grant_id", unique: true
    t.index ["service_user_id"], name: "index_system_sudoers_grants_on_service_user_id"
    t.check_constraint "state::text = ANY (ARRAY['active'::character varying::text, 'removed'::character varying::text])", name: "system_sudoers_grants_state_enum"
  end

  create_table "system_tasks", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "claimed_by_worker_id"
    t.string "command", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "description"
    t.text "error_message"
    t.jsonb "events", default: [], null: false
    t.boolean "exclusive", default: false, null: false
    t.string "idempotency_key"
    t.uuid "initiated_by_id"
    t.uuid "operable_id"
    t.string "operable_type"
    t.jsonb "options", default: {}, null: false
    t.integer "progress", default: 0, null: false
    t.datetime "scheduled_at"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "idempotency_key"], name: "idx_system_tasks_idempotency", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["account_id"], name: "index_system_tasks_on_account_id"
    t.index ["claimed_by_worker_id"], name: "index_system_tasks_on_claimed_by_worker_id"
    t.index ["command"], name: "index_system_tasks_on_command"
    t.index ["completed_at"], name: "index_system_tasks_on_completed_at"
    t.index ["events"], name: "index_system_tasks_on_events", using: :gin
    t.index ["exclusive"], name: "index_system_tasks_on_exclusive"
    t.index ["initiated_by_id"], name: "index_system_tasks_on_initiated_by_id"
    t.index ["operable_type", "operable_id"], name: "index_system_tasks_on_operable_type_and_operable_id"
    t.index ["options"], name: "index_system_tasks_on_options", using: :gin
    t.index ["scheduled_at"], name: "index_system_tasks_on_scheduled_at"
    t.index ["started_at"], name: "index_system_tasks_on_started_at"
    t.index ["status"], name: "index_system_tasks_on_status"
    t.check_constraint "progress >= 0 AND progress <= 100", name: "system_operations_progress_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'scheduled'::character varying::text, 'running'::character varying::text, 'complete'::character varying::text, 'failed'::character varying::text, 'aborted'::character varying::text, 'cancelled'::character varying::text])", name: "system_operations_status_check"
  end

  create_table "system_template_modules", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.uuid "node_module_id", null: false
    t.uuid "node_template_id", null: false
    t.integer "priority", default: 0, null: false
    t.jsonb "recommends_override", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["config"], name: "index_system_template_modules_on_config", using: :gin
    t.index ["enabled"], name: "index_system_template_modules_on_enabled"
    t.index ["node_module_id"], name: "index_system_template_modules_on_node_module_id"
    t.index ["node_template_id", "node_module_id"], name: "idx_on_node_template_id_node_module_id_b38ed1928a", unique: true
    t.index ["node_template_id"], name: "index_system_template_modules_on_node_template_id"
    t.index ["priority"], name: "index_system_template_modules_on_priority"
  end

  create_table "system_unclaimed_devices", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "agent_version"
    t.string "architecture"
    t.string "claim_code", null: false
    t.datetime "claimed_at"
    t.uuid "claimed_node_instance_id"
    t.datetime "created_at", null: false
    t.string "discovered_dmi_uuid"
    t.string "discovered_hostname"
    t.string "discovered_mac"
    t.datetime "expires_at", null: false
    t.datetime "first_seen_at", null: false
    t.datetime "last_seen_at", null: false
    t.string "platform_hint"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_system_unclaimed_devices_on_account_id"
    t.index ["claim_code"], name: "index_system_unclaimed_devices_on_claim_code", unique: true
    t.index ["claimed_node_instance_id"], name: "index_system_unclaimed_devices_on_claimed_node_instance_id"
    t.index ["discovered_mac"], name: "index_system_unclaimed_devices_on_discovered_mac"
    t.index ["expires_at"], name: "index_system_unclaimed_devices_on_expires_at"
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
    t.index ["scheduled_task_id", "started_at"], name: "index_task_executions_on_scheduled_task_id_and_started_at"
    t.index ["scheduled_task_id"], name: "index_task_executions_on_scheduled_task_id"
    t.index ["started_at"], name: "index_task_executions_on_started_at"
    t.index ["status"], name: "index_task_executions_on_status"
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
    t.index ["account_id"], name: "index_terms_acceptances_on_account_id"
    t.index ["document_type"], name: "index_terms_acceptances_on_document_type"
    t.index ["document_version"], name: "index_terms_acceptances_on_document_version"
    t.index ["user_id", "document_type", "document_version"], name: "idx_on_user_id_document_type_document_version_8eb2bf3f3a", unique: true
    t.index ["user_id", "document_type"], name: "index_terms_acceptances_on_user_id_and_document_type"
    t.index ["user_id"], name: "index_terms_acceptances_on_user_id"
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
    t.index ["account_id", "consent_type"], name: "index_user_consents_on_account_id_and_consent_type"
    t.index ["account_id"], name: "index_user_consents_on_account_id"
    t.index ["consent_type"], name: "index_user_consents_on_consent_type"
    t.index ["expires_at"], name: "index_user_consents_on_expires_at"
    t.index ["granted"], name: "index_user_consents_on_granted"
    t.index ["user_id", "consent_type"], name: "index_user_consents_on_user_id_and_consent_type"
    t.index ["user_id"], name: "index_user_consents_on_user_id"
  end

  create_table "user_roles", id: false, force: :cascade do |t|
    t.datetime "granted_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.uuid "granted_by_id"
    t.uuid "role_id", null: false
    t.uuid "user_id", null: false
    t.index ["granted_by_id"], name: "index_user_roles_on_granted_by_id"
    t.index ["role_id"], name: "index_user_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_user_roles_on_user_id_and_role_id", unique: true
    t.index ["user_id"], name: "index_user_roles_on_user_id"
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
    t.index ["created_at"], name: "index_user_tokens_on_created_at"
    t.index ["expires_at"], name: "index_user_tokens_on_expires_at"
    t.index ["last_used_at"], name: "index_user_tokens_on_last_used_at"
    t.index ["revoked"], name: "index_user_tokens_on_revoked"
    t.index ["token_digest"], name: "index_user_tokens_on_token_digest", unique: true
    t.index ["token_type"], name: "index_user_tokens_on_token_type"
    t.index ["user_id", "token_type"], name: "index_user_tokens_on_user_id_and_token_type"
    t.index ["user_id"], name: "index_user_tokens_on_user_id"
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
    t.index ["account_id"], name: "index_users_on_account_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["email_verification_token"], name: "index_users_on_email_verification_token", unique: true, where: "(email_verification_token IS NOT NULL)"
    t.index ["reset_token_digest"], name: "index_users_on_reset_token_digest", unique: true, where: "(reset_token_digest IS NOT NULL)"
    t.index ["status"], name: "index_users_on_status"
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
    t.index ["category", "enabled"], name: "index_validation_rules_on_category_and_enabled"
    t.index ["name"], name: "index_validation_rules_on_name", unique: true
    t.index ["severity"], name: "index_validation_rules_on_severity"
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
    t.index ["attempted_at"], name: "index_webhook_deliveries_on_attempted_at"
    t.index ["next_retry_at"], name: "index_webhook_deliveries_on_next_retry_at"
    t.index ["status"], name: "index_webhook_deliveries_on_status"
    t.index ["webhook_endpoint_id"], name: "index_webhook_deliveries_on_webhook_endpoint_id"
    t.index ["webhook_event_id"], name: "index_webhook_deliveries_on_webhook_event_id"
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
    t.index ["stat_date"], name: "index_webhook_delivery_stats_on_stat_date"
    t.index ["webhook_endpoint_id", "stat_date"], name: "idx_on_webhook_endpoint_id_stat_date_74f2f5be75", unique: true
    t.index ["webhook_endpoint_id"], name: "index_webhook_delivery_stats_on_webhook_endpoint_id"
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
    t.index ["account_id"], name: "index_webhook_endpoints_on_account_id"
    t.index ["circuit_broken_at"], name: "index_webhook_endpoints_on_circuit_broken", where: "(circuit_broken_at IS NOT NULL)"
    t.index ["content_type"], name: "index_webhook_endpoints_on_content_type"
    t.index ["created_by_id"], name: "index_webhook_endpoints_on_created_by_id"
    t.index ["failure_count"], name: "index_webhook_endpoints_on_failure_count"
    t.index ["is_active"], name: "index_webhook_endpoints_on_is_active"
    t.index ["last_delivery_at"], name: "index_webhook_endpoints_on_last_delivery_at"
    t.index ["status", "is_active"], name: "index_webhook_endpoints_on_status_and_is_active"
    t.index ["success_count"], name: "index_webhook_endpoints_on_success_count"
    t.index ["tier"], name: "index_webhook_endpoints_on_tier"
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
    t.index ["account_id", "event_type"], name: "index_webhook_events_on_account_id_and_event_type"
    t.index ["account_id"], name: "index_webhook_events_on_account_id"
    t.index ["event_id"], name: "index_webhook_events_on_event_id", unique: true
    t.index ["external_id"], name: "index_webhook_events_on_external_id", unique: true
    t.index ["occurred_at"], name: "index_webhook_events_on_occurred_at"
    t.index ["payment_id"], name: "index_webhook_events_on_payment_id"
    t.index ["provider"], name: "index_webhook_events_on_provider"
    t.index ["retry_count"], name: "index_webhook_events_on_retry_count"
    t.index ["status"], name: "index_webhook_events_on_status"
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
    t.index ["activity_type"], name: "index_worker_activities_on_activity_type"
    t.index ["occurred_at"], name: "index_worker_activities_on_occurred_at"
    t.index ["worker_id", "occurred_at"], name: "index_worker_activities_on_worker_id_and_occurred_at"
    t.index ["worker_id"], name: "index_worker_activities_on_worker_id"
  end

  create_table "worker_roles", id: false, force: :cascade do |t|
    t.datetime "granted_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.uuid "role_id", null: false
    t.uuid "worker_id", null: false
    t.index ["role_id"], name: "index_worker_roles_on_role_id"
    t.index ["worker_id", "role_id"], name: "index_worker_roles_on_worker_id_and_role_id", unique: true
    t.index ["worker_id"], name: "index_worker_roles_on_worker_id"
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
    t.index ["account_id"], name: "index_workers_on_account_id"
    t.index ["capabilities"], name: "index_workers_on_capabilities", using: :gin
    t.index ["is_system"], name: "index_workers_on_is_system_unique", unique: true, where: "(is_system = true)"
    t.index ["name"], name: "index_workers_on_name", unique: true
    t.index ["node_instance_id"], name: "index_workers_on_node_instance_id", unique: true, where: "(node_instance_id IS NOT NULL)"
    t.index ["permissions"], name: "index_workers_on_permissions", using: :gin
    t.index ["status"], name: "index_workers_on_status"
    t.index ["worker_type"], name: "index_workers_on_worker_type"
    t.check_constraint "worker_type::text = ANY (ARRAY['background'::character varying::text, 'infrastructure'::character varying::text])", name: "workers_worker_type_check"
  end

  add_foreign_key "account_delegations", "accounts"
  add_foreign_key "account_delegations", "roles"
  add_foreign_key "account_delegations", "users", column: "delegated_by_id"
  add_foreign_key "account_delegations", "users", column: "delegated_user_id"
  add_foreign_key "account_delegations", "users", column: "revoked_by_id"
  add_foreign_key "account_git_webhook_configs", "accounts"
  add_foreign_key "account_git_webhook_configs", "users", column: "created_by_id"
  add_foreign_key "account_terminations", "accounts"
  add_foreign_key "account_terminations", "data_export_requests"
  add_foreign_key "account_terminations", "users", column: "cancelled_by_id"
  add_foreign_key "account_terminations", "users", column: "processed_by_id"
  add_foreign_key "account_terminations", "users", column: "requested_by_id"
  add_foreign_key "ai_a2a_task_events", "ai_a2a_tasks"
  add_foreign_key "ai_a2a_tasks", "accounts"
  add_foreign_key "ai_a2a_tasks", "ai_a2a_tasks", column: "parent_task_id"
  add_foreign_key "ai_a2a_tasks", "ai_agent_cards", column: "from_agent_card_id"
  add_foreign_key "ai_a2a_tasks", "ai_agent_cards", column: "to_agent_card_id"
  add_foreign_key "ai_a2a_tasks", "ai_agents", column: "from_agent_id"
  add_foreign_key "ai_a2a_tasks", "ai_agents", column: "to_agent_id"
  add_foreign_key "ai_a2a_tasks", "chat_messages", on_delete: :nullify
  add_foreign_key "ai_a2a_tasks", "chat_sessions", on_delete: :nullify
  add_foreign_key "ai_a2a_tasks", "community_agents", on_delete: :nullify
  add_foreign_key "ai_a2a_tasks", "devops_container_instances", column: "container_instance_id"
  add_foreign_key "ai_a2a_tasks", "federation_partners", on_delete: :nullify
  add_foreign_key "ai_ab_tests", "accounts"
  add_foreign_key "ai_ab_tests", "users", column: "created_by_id"
  add_foreign_key "ai_agent_budgets", "accounts"
  add_foreign_key "ai_agent_budgets", "ai_agent_budgets", column: "parent_budget_id", on_delete: :nullify
  add_foreign_key "ai_agent_budgets", "ai_agents", column: "agent_id"
  add_foreign_key "ai_agent_cards", "accounts"
  add_foreign_key "ai_agent_cards", "ai_agents"
  add_foreign_key "ai_agent_connections", "accounts"
  add_foreign_key "ai_agent_escalations", "accounts"
  add_foreign_key "ai_agent_escalations", "ai_agents"
  add_foreign_key "ai_agent_escalations", "users", column: "escalated_to_user_id"
  add_foreign_key "ai_agent_executions", "accounts", on_delete: :cascade
  add_foreign_key "ai_agent_executions", "ai_agent_executions", column: "parent_execution_id", on_delete: :nullify
  add_foreign_key "ai_agent_executions", "ai_agents", on_delete: :cascade
  add_foreign_key "ai_agent_executions", "ai_providers", on_delete: :restrict
  add_foreign_key "ai_agent_executions", "users", on_delete: :restrict
  add_foreign_key "ai_agent_feedbacks", "accounts"
  add_foreign_key "ai_agent_feedbacks", "ai_agents"
  add_foreign_key "ai_agent_feedbacks", "users"
  add_foreign_key "ai_agent_goals", "accounts"
  add_foreign_key "ai_agent_goals", "ai_agent_goals", column: "parent_goal_id"
  add_foreign_key "ai_agent_goals", "ai_agents"
  add_foreign_key "ai_agent_identities", "accounts"
  add_foreign_key "ai_agent_installations", "accounts"
  add_foreign_key "ai_agent_installations", "ai_agent_templates", column: "agent_template_id"
  add_foreign_key "ai_agent_installations", "ai_agents", column: "installed_agent_id"
  add_foreign_key "ai_agent_installations", "users", column: "installed_by_id"
  add_foreign_key "ai_agent_lineages", "accounts"
  add_foreign_key "ai_agent_lineages", "ai_agents", column: "child_agent_id"
  add_foreign_key "ai_agent_lineages", "ai_agents", column: "parent_agent_id"
  add_foreign_key "ai_agent_model_performances", "accounts"
  add_foreign_key "ai_agent_model_performances", "ai_providers"
  add_foreign_key "ai_agent_observations", "accounts"
  add_foreign_key "ai_agent_observations", "ai_agent_goals", column: "goal_id"
  add_foreign_key "ai_agent_observations", "ai_agents"
  add_foreign_key "ai_agent_privilege_policies", "accounts"
  add_foreign_key "ai_agent_proposals", "accounts"
  add_foreign_key "ai_agent_proposals", "ai_agents"
  add_foreign_key "ai_agent_proposals", "ai_conversations", column: "conversation_id"
  add_foreign_key "ai_agent_proposals", "users", column: "reviewed_by_id"
  add_foreign_key "ai_agent_proposals", "users", column: "target_user_id"
  add_foreign_key "ai_agent_reviews", "accounts"
  add_foreign_key "ai_agent_reviews", "ai_agent_installations", column: "installation_id"
  add_foreign_key "ai_agent_reviews", "ai_agent_templates", column: "agent_template_id"
  add_foreign_key "ai_agent_reviews", "users"
  add_foreign_key "ai_agent_short_term_memories", "accounts"
  add_foreign_key "ai_agent_short_term_memories", "ai_agents", column: "agent_id"
  add_foreign_key "ai_agent_skills", "ai_agents"
  add_foreign_key "ai_agent_skills", "ai_skills"
  add_foreign_key "ai_agent_team_members", "ai_agent_teams"
  add_foreign_key "ai_agent_team_members", "ai_agents"
  add_foreign_key "ai_agent_teams", "accounts"
  add_foreign_key "ai_agent_templates", "accounts"
  add_foreign_key "ai_agent_templates", "ai_agents", column: "source_agent_id"
  add_foreign_key "ai_agent_trust_scores", "accounts"
  add_foreign_key "ai_agent_trust_scores", "ai_agents", column: "agent_id"
  add_foreign_key "ai_agents", "accounts", on_delete: :cascade
  add_foreign_key "ai_agents", "ai_providers"
  add_foreign_key "ai_agents", "users", column: "creator_id", on_delete: :restrict
  add_foreign_key "ai_agui_events", "accounts"
  add_foreign_key "ai_agui_events", "ai_agui_sessions", column: "session_id"
  add_foreign_key "ai_agui_sessions", "accounts"
  add_foreign_key "ai_agui_sessions", "users"
  add_foreign_key "ai_approval_chains", "accounts"
  add_foreign_key "ai_approval_chains", "users", column: "created_by_id"
  add_foreign_key "ai_approval_decisions", "ai_approval_requests", column: "approval_request_id"
  add_foreign_key "ai_approval_decisions", "users", column: "approver_id"
  add_foreign_key "ai_approval_requests", "accounts"
  add_foreign_key "ai_approval_requests", "ai_approval_chains", column: "approval_chain_id"
  add_foreign_key "ai_approval_requests", "users", column: "requested_by_id"
  add_foreign_key "ai_behavioral_fingerprints", "accounts"
  add_foreign_key "ai_behavioral_fingerprints", "ai_agents", column: "agent_id"
  add_foreign_key "ai_budget_transactions", "accounts"
  add_foreign_key "ai_budget_transactions", "ai_agent_budgets"
  add_foreign_key "ai_budget_transactions", "ai_agent_executions"
  add_foreign_key "ai_circuit_breakers", "accounts"
  add_foreign_key "ai_circuit_breakers", "ai_agents", column: "agent_id"
  add_foreign_key "ai_code_factory_evidence_manifests", "accounts"
  add_foreign_key "ai_code_factory_evidence_manifests", "ai_code_factory_review_states", column: "review_state_id"
  add_foreign_key "ai_code_factory_harness_gaps", "accounts"
  add_foreign_key "ai_code_factory_harness_gaps", "ai_code_factory_risk_contracts", column: "risk_contract_id"
  add_foreign_key "ai_code_factory_review_states", "accounts"
  add_foreign_key "ai_code_factory_review_states", "ai_code_factory_risk_contracts", column: "risk_contract_id"
  add_foreign_key "ai_code_factory_review_states", "ai_missions", column: "mission_id"
  add_foreign_key "ai_code_factory_review_states", "git_repositories", column: "repository_id"
  add_foreign_key "ai_code_factory_risk_contracts", "accounts"
  add_foreign_key "ai_code_factory_risk_contracts", "git_repositories", column: "repository_id"
  add_foreign_key "ai_code_factory_risk_contracts", "users", column: "created_by_id"
  add_foreign_key "ai_code_review_comments", "accounts"
  add_foreign_key "ai_code_review_comments", "ai_agents", column: "agent_id"
  add_foreign_key "ai_code_review_comments", "ai_task_reviews", column: "task_review_id"
  add_foreign_key "ai_code_reviews", "accounts"
  add_foreign_key "ai_code_reviews", "ai_pipeline_executions", column: "pipeline_execution_id"
  add_foreign_key "ai_collusion_indicators", "accounts"
  add_foreign_key "ai_compliance_audit_entries", "accounts"
  add_foreign_key "ai_compliance_audit_entries", "users"
  add_foreign_key "ai_compliance_policies", "accounts"
  add_foreign_key "ai_compliance_policies", "users", column: "created_by_id"
  add_foreign_key "ai_compliance_reports", "accounts"
  add_foreign_key "ai_compliance_reports", "users", column: "generated_by_id"
  add_foreign_key "ai_compound_learnings", "accounts"
  add_foreign_key "ai_compound_learnings", "ai_agent_teams"
  add_foreign_key "ai_compound_learnings", "ai_agents", column: "source_agent_id"
  add_foreign_key "ai_compound_learnings", "ai_compound_learnings", column: "superseded_by_id"
  add_foreign_key "ai_compound_learnings", "ai_team_executions", column: "source_execution_id"
  add_foreign_key "ai_compound_learnings", "git_repositories", on_delete: :nullify
  add_foreign_key "ai_context_access_logs", "accounts"
  add_foreign_key "ai_context_access_logs", "ai_agents"
  add_foreign_key "ai_context_access_logs", "ai_context_entries"
  add_foreign_key "ai_context_access_logs", "ai_persistent_contexts"
  add_foreign_key "ai_context_access_logs", "users"
  add_foreign_key "ai_context_entries", "ai_agents"
  add_foreign_key "ai_context_entries", "ai_persistent_contexts"
  add_foreign_key "ai_context_entries", "users", column: "created_by_user_id"
  add_foreign_key "ai_conversations", "accounts", on_delete: :cascade
  add_foreign_key "ai_conversations", "ai_agent_teams", column: "agent_team_id"
  add_foreign_key "ai_conversations", "ai_agents", on_delete: :nullify
  add_foreign_key "ai_conversations", "ai_providers", on_delete: :restrict
  add_foreign_key "ai_conversations", "users", on_delete: :restrict
  add_foreign_key "ai_cost_attributions", "accounts"
  add_foreign_key "ai_cost_attributions", "ai_providers", column: "provider_id"
  add_foreign_key "ai_cost_attributions", "ai_roi_metrics", column: "roi_metric_id"
  add_foreign_key "ai_cost_optimization_logs", "accounts"
  add_foreign_key "ai_dag_executions", "accounts"
  add_foreign_key "ai_dag_executions", "users", column: "triggered_by_id"
  add_foreign_key "ai_data_classifications", "accounts"
  add_foreign_key "ai_data_classifications", "users", column: "classified_by_id"
  add_foreign_key "ai_data_connectors", "accounts"
  add_foreign_key "ai_data_connectors", "ai_knowledge_bases", column: "knowledge_base_id"
  add_foreign_key "ai_data_connectors", "users", column: "created_by_id"
  add_foreign_key "ai_data_detections", "accounts"
  add_foreign_key "ai_data_detections", "ai_data_classifications", column: "classification_id"
  add_foreign_key "ai_data_source_config_versions", "accounts"
  add_foreign_key "ai_data_source_config_versions", "ai_data_sources"
  add_foreign_key "ai_data_source_credentials", "accounts", on_delete: :cascade
  add_foreign_key "ai_data_source_credentials", "ai_data_sources", on_delete: :cascade
  add_foreign_key "ai_data_source_endpoints", "ai_data_sources"
  add_foreign_key "ai_data_source_expectations", "ai_data_source_endpoints"
  add_foreign_key "ai_data_source_queries", "ai_data_source_endpoints"
  add_foreign_key "ai_data_source_queries", "ai_data_sources"
  add_foreign_key "ai_data_source_schema_versions", "ai_data_source_endpoints"
  add_foreign_key "ai_data_source_subscriptions", "ai_data_source_endpoints"
  add_foreign_key "ai_data_source_subscriptions", "ai_data_sources"
  add_foreign_key "ai_data_sources", "accounts", on_delete: :cascade
  add_foreign_key "ai_deferred_operations", "accounts"
  add_foreign_key "ai_deferred_operations", "ai_agents"
  add_foreign_key "ai_deferred_operations", "ai_approval_requests", column: "approval_request_id"
  add_foreign_key "ai_deferred_operations", "users", column: "requested_by_id"
  add_foreign_key "ai_delegation_policies", "accounts"
  add_foreign_key "ai_delegation_policies", "ai_agents", column: "agent_id"
  add_foreign_key "ai_deployment_risks", "accounts"
  add_foreign_key "ai_deployment_risks", "ai_pipeline_executions", column: "pipeline_execution_id"
  add_foreign_key "ai_deployment_risks", "users", column: "assessed_by_id"
  add_foreign_key "ai_devops_template_installations", "accounts"
  add_foreign_key "ai_devops_template_installations", "ai_devops_templates", column: "devops_template_id"
  add_foreign_key "ai_devops_template_installations", "users", column: "installed_by_id"
  add_foreign_key "ai_devops_templates", "accounts"
  add_foreign_key "ai_devops_templates", "users", column: "created_by_id"
  add_foreign_key "ai_discovery_results", "accounts"
  add_foreign_key "ai_document_chunks", "ai_documents", column: "document_id"
  add_foreign_key "ai_document_chunks", "ai_knowledge_bases", column: "knowledge_base_id"
  add_foreign_key "ai_documents", "ai_knowledge_bases", column: "knowledge_base_id"
  add_foreign_key "ai_documents", "users", column: "uploaded_by_id"
  add_foreign_key "ai_encrypted_messages", "accounts"
  add_foreign_key "ai_evaluation_results", "accounts"
  add_foreign_key "ai_evaluation_results", "ai_agents", column: "agent_id"
  add_foreign_key "ai_execution_events", "accounts"
  add_foreign_key "ai_execution_trace_spans", "ai_execution_traces", column: "execution_trace_id"
  add_foreign_key "ai_execution_traces", "accounts"
  add_foreign_key "ai_experience_replays", "accounts"
  add_foreign_key "ai_experience_replays", "ai_agent_executions", column: "source_execution_id"
  add_foreign_key "ai_experience_replays", "ai_agents"
  add_foreign_key "ai_experience_replays", "ai_trajectories", column: "source_trajectory_id"
  add_foreign_key "ai_file_locks", "accounts"
  add_foreign_key "ai_file_locks", "ai_worktree_sessions", column: "worktree_session_id"
  add_foreign_key "ai_file_locks", "ai_worktrees", column: "worktree_id"
  add_foreign_key "ai_goal_plan_steps", "ai_agent_goals", column: "sub_goal_id"
  add_foreign_key "ai_goal_plan_steps", "ai_goal_plans", column: "plan_id"
  add_foreign_key "ai_goal_plan_steps", "ai_ralph_tasks", column: "ralph_task_id"
  add_foreign_key "ai_goal_plans", "accounts"
  add_foreign_key "ai_goal_plans", "ai_agent_goals", column: "goal_id"
  add_foreign_key "ai_goal_plans", "ai_agents"
  add_foreign_key "ai_goal_plans", "users", column: "approved_by_id"
  add_foreign_key "ai_governance_reports", "accounts"
  add_foreign_key "ai_governance_reports", "ai_agent_teams", column: "subject_team_id"
  add_foreign_key "ai_governance_reports", "ai_agents", column: "monitor_agent_id"
  add_foreign_key "ai_governance_reports", "ai_agents", column: "subject_agent_id"
  add_foreign_key "ai_guardrail_configs", "accounts"
  add_foreign_key "ai_guardrail_configs", "ai_agents"
  add_foreign_key "ai_hybrid_search_results", "accounts"
  add_foreign_key "ai_improvement_recommendations", "accounts"
  add_foreign_key "ai_improvement_recommendations", "users", column: "approved_by_id"
  add_foreign_key "ai_intervention_policies", "accounts"
  add_foreign_key "ai_intervention_policies", "ai_agents"
  add_foreign_key "ai_intervention_policies", "ai_approval_chains", column: "approval_chain_id"
  add_foreign_key "ai_intervention_policies", "users"
  add_foreign_key "ai_kill_switch_events", "accounts"
  add_foreign_key "ai_kill_switch_events", "users", column: "triggered_by_id"
  add_foreign_key "ai_knowledge_bases", "accounts"
  add_foreign_key "ai_knowledge_bases", "git_repositories"
  add_foreign_key "ai_knowledge_bases", "users", column: "created_by_id"
  add_foreign_key "ai_knowledge_graph_edges", "accounts"
  add_foreign_key "ai_knowledge_graph_edges", "ai_documents", column: "source_document_id"
  add_foreign_key "ai_knowledge_graph_edges", "ai_knowledge_graph_nodes", column: "source_node_id"
  add_foreign_key "ai_knowledge_graph_edges", "ai_knowledge_graph_nodes", column: "target_node_id"
  add_foreign_key "ai_knowledge_graph_nodes", "accounts"
  add_foreign_key "ai_knowledge_graph_nodes", "ai_documents", column: "source_document_id"
  add_foreign_key "ai_knowledge_graph_nodes", "ai_knowledge_bases", column: "knowledge_base_id"
  add_foreign_key "ai_knowledge_graph_nodes", "ai_knowledge_graph_nodes", column: "merged_into_id"
  add_foreign_key "ai_knowledge_graph_nodes", "ai_skills"
  add_foreign_key "ai_mcp_app_instances", "accounts"
  add_foreign_key "ai_mcp_app_instances", "ai_agui_sessions", column: "session_id"
  add_foreign_key "ai_mcp_app_instances", "ai_mcp_apps", column: "mcp_app_id"
  add_foreign_key "ai_mcp_apps", "accounts"
  add_foreign_key "ai_memory_pools", "accounts"
  add_foreign_key "ai_merge_operations", "accounts"
  add_foreign_key "ai_merge_operations", "ai_worktree_sessions", column: "worktree_session_id"
  add_foreign_key "ai_merge_operations", "ai_worktrees", column: "worktree_id"
  add_foreign_key "ai_messages", "ai_agents"
  add_foreign_key "ai_messages", "ai_conversations", on_delete: :cascade
  add_foreign_key "ai_messages", "ai_messages", column: "parent_message_id", on_delete: :nullify
  add_foreign_key "ai_messages", "users", on_delete: :nullify
  add_foreign_key "ai_mission_approvals", "ai_missions", column: "mission_id"
  add_foreign_key "ai_missions", "ai_agent_teams", column: "team_id"
  add_foreign_key "ai_missions", "ai_code_factory_review_states", column: "review_state_id"
  add_foreign_key "ai_missions", "ai_code_factory_risk_contracts", column: "risk_contract_id"
  add_foreign_key "ai_missions", "ai_conversations", column: "conversation_id"
  add_foreign_key "ai_missions", "ai_mission_templates", column: "mission_template_id"
  add_foreign_key "ai_missions", "ai_ralph_loops", column: "ralph_loop_id", on_delete: :nullify
  add_foreign_key "ai_missions", "git_repositories", column: "repository_id"
  add_foreign_key "ai_missions", "users", column: "created_by_id"
  add_foreign_key "ai_mock_responses", "accounts"
  add_foreign_key "ai_mock_responses", "ai_sandboxes", column: "sandbox_id"
  add_foreign_key "ai_mock_responses", "users", column: "created_by_id"
  add_foreign_key "ai_model_routing_rules", "accounts"
  add_foreign_key "ai_performance_benchmarks", "accounts"
  add_foreign_key "ai_performance_benchmarks", "ai_agents", column: "target_agent_id"
  add_foreign_key "ai_performance_benchmarks", "ai_sandboxes", column: "sandbox_id"
  add_foreign_key "ai_performance_benchmarks", "users", column: "created_by_id"
  add_foreign_key "ai_persistent_contexts", "accounts"
  add_foreign_key "ai_persistent_contexts", "ai_agents"
  add_foreign_key "ai_persistent_contexts", "users", column: "created_by_user_id"
  add_foreign_key "ai_pipeline_executions", "accounts"
  add_foreign_key "ai_pipeline_executions", "ai_devops_template_installations", column: "devops_installation_id"
  add_foreign_key "ai_pipeline_executions", "users", column: "triggered_by_id"
  add_foreign_key "ai_policy_violations", "accounts"
  add_foreign_key "ai_policy_violations", "ai_compliance_policies", column: "policy_id"
  add_foreign_key "ai_policy_violations", "users", column: "detected_by_id"
  add_foreign_key "ai_policy_violations", "users", column: "resolved_by_id"
  add_foreign_key "ai_pressure_fields", "accounts"
  add_foreign_key "ai_provider_credentials", "accounts", on_delete: :cascade
  add_foreign_key "ai_provider_credentials", "ai_providers", on_delete: :cascade
  add_foreign_key "ai_provider_metrics", "accounts"
  add_foreign_key "ai_provider_metrics", "ai_providers", column: "provider_id"
  add_foreign_key "ai_providers", "accounts"
  add_foreign_key "ai_provisioning_code_deployments", "ai_missions", column: "mission_id"
  add_foreign_key "ai_provisioning_code_deployments", "system_node_instances", column: "node_instance_id"
  add_foreign_key "ai_quarantine_records", "accounts"
  add_foreign_key "ai_rag_queries", "accounts"
  add_foreign_key "ai_rag_queries", "ai_knowledge_bases", column: "knowledge_base_id"
  add_foreign_key "ai_rag_queries", "ai_missions", column: "mission_id"
  add_foreign_key "ai_rag_queries", "users"
  add_foreign_key "ai_ralph_iterations", "ai_ralph_loops", column: "ralph_loop_id"
  add_foreign_key "ai_ralph_iterations", "ai_ralph_tasks", column: "ralph_task_id"
  add_foreign_key "ai_ralph_loops", "accounts"
  add_foreign_key "ai_ralph_loops", "ai_agents", column: "default_agent_id", on_delete: :nullify
  add_foreign_key "ai_ralph_loops", "ai_code_factory_risk_contracts", column: "risk_contract_id"
  add_foreign_key "ai_ralph_loops", "ai_missions", column: "mission_id", on_delete: :nullify
  add_foreign_key "ai_ralph_loops", "devops_container_instances", column: "container_instance_id"
  add_foreign_key "ai_ralph_tasks", "ai_ralph_loops", column: "ralph_loop_id"
  add_foreign_key "ai_recorded_interactions", "accounts"
  add_foreign_key "ai_recorded_interactions", "ai_sandboxes", column: "sandbox_id"
  add_foreign_key "ai_remediation_logs", "accounts"
  add_foreign_key "ai_roi_metrics", "accounts"
  add_foreign_key "ai_role_profiles", "accounts"
  add_foreign_key "ai_routing_decisions", "accounts"
  add_foreign_key "ai_routing_decisions", "ai_agent_executions", column: "agent_execution_id"
  add_foreign_key "ai_routing_decisions", "ai_model_routing_rules", column: "routing_rule_id"
  add_foreign_key "ai_routing_decisions", "ai_providers", column: "selected_provider_id"
  add_foreign_key "ai_routing_decisions", "ai_task_complexity_assessments", column: "complexity_assessment_id"
  add_foreign_key "ai_runner_dispatches", "ai_missions", column: "mission_id"
  add_foreign_key "ai_runner_dispatches", "ai_worktree_sessions", column: "worktree_session_id"
  add_foreign_key "ai_runner_dispatches", "ai_worktrees", column: "worktree_id"
  add_foreign_key "ai_runner_dispatches", "git_repositories"
  add_foreign_key "ai_runner_dispatches", "git_runners"
  add_foreign_key "ai_sandboxes", "accounts"
  add_foreign_key "ai_sandboxes", "users", column: "created_by_id"
  add_foreign_key "ai_scheduled_messages", "accounts"
  add_foreign_key "ai_scheduled_messages", "ai_conversations", column: "conversation_id"
  add_foreign_key "ai_scheduled_messages", "users"
  add_foreign_key "ai_security_audit_trails", "accounts"
  add_foreign_key "ai_self_challenges", "accounts"
  add_foreign_key "ai_self_challenges", "ai_agents", column: "challenger_agent_id"
  add_foreign_key "ai_self_challenges", "ai_agents", column: "executor_agent_id"
  add_foreign_key "ai_self_challenges", "ai_agents", column: "validator_agent_id"
  add_foreign_key "ai_self_challenges", "ai_skills"
  add_foreign_key "ai_shadow_executions", "accounts"
  add_foreign_key "ai_shadow_executions", "ai_agents", column: "agent_id"
  add_foreign_key "ai_shared_knowledges", "accounts"
  add_foreign_key "ai_shared_knowledges", "git_repositories", on_delete: :nullify
  add_foreign_key "ai_shared_knowledges", "users", column: "created_by_id"
  add_foreign_key "ai_skill_compositions", "ai_skills", column: "component_skill_id"
  add_foreign_key "ai_skill_compositions", "ai_skills", column: "composite_skill_id"
  add_foreign_key "ai_skill_conflicts", "accounts"
  add_foreign_key "ai_skill_conflicts", "ai_skills", column: "skill_a_id"
  add_foreign_key "ai_skill_conflicts", "ai_skills", column: "skill_b_id"
  add_foreign_key "ai_skill_conflicts", "users", column: "resolved_by_id"
  add_foreign_key "ai_skill_proposals", "accounts"
  add_foreign_key "ai_skill_proposals", "ai_agents", column: "proposed_by_agent_id"
  add_foreign_key "ai_skill_proposals", "ai_skill_proposals", column: "parent_proposal_id"
  add_foreign_key "ai_skill_proposals", "ai_skills", column: "created_skill_id"
  add_foreign_key "ai_skill_proposals", "users", column: "proposed_by_user_id"
  add_foreign_key "ai_skill_proposals", "users", column: "reviewed_by_id"
  add_foreign_key "ai_skill_recipe_runs", "accounts"
  add_foreign_key "ai_skill_recipe_runs", "ai_agents"
  add_foreign_key "ai_skill_recipe_runs", "ai_skills"
  add_foreign_key "ai_skill_recipe_runs", "users"
  add_foreign_key "ai_skill_usage_records", "accounts"
  add_foreign_key "ai_skill_usage_records", "ai_agents"
  add_foreign_key "ai_skill_usage_records", "ai_skills"
  add_foreign_key "ai_skill_versions", "accounts"
  add_foreign_key "ai_skill_versions", "ai_agents", column: "created_by_agent_id"
  add_foreign_key "ai_skill_versions", "ai_skills"
  add_foreign_key "ai_skill_versions", "users", column: "created_by_user_id"
  add_foreign_key "ai_skills", "accounts"
  add_foreign_key "ai_skills", "ai_knowledge_bases", column: "ai_knowledge_base_id"
  add_foreign_key "ai_skills", "ai_skills", column: "parent_skill_id"
  add_foreign_key "ai_skills_mcp_servers", "ai_skills"
  add_foreign_key "ai_skills_mcp_servers", "mcp_servers"
  add_foreign_key "ai_stigmergic_signals", "accounts"
  add_foreign_key "ai_stigmergic_signals", "ai_agents", column: "emitter_agent_id"
  add_foreign_key "ai_stigmergic_signals", "ai_memory_pools", column: "memory_pool_id"
  add_foreign_key "ai_task_complexity_assessments", "accounts"
  add_foreign_key "ai_task_complexity_assessments", "ai_routing_decisions", column: "routing_decision_id"
  add_foreign_key "ai_task_reviews", "accounts"
  add_foreign_key "ai_task_reviews", "ai_agents", column: "reviewer_agent_id"
  add_foreign_key "ai_task_reviews", "ai_team_roles", column: "reviewer_role_id"
  add_foreign_key "ai_task_reviews", "ai_team_tasks", column: "team_task_id"
  add_foreign_key "ai_team_channels", "ai_agent_teams", column: "agent_team_id"
  add_foreign_key "ai_team_executions", "accounts"
  add_foreign_key "ai_team_executions", "ai_agent_teams", column: "agent_team_id"
  add_foreign_key "ai_team_executions", "ai_conversations"
  add_foreign_key "ai_team_executions", "ai_missions", column: "mission_id"
  add_foreign_key "ai_team_executions", "users", column: "approval_decided_by_id"
  add_foreign_key "ai_team_executions", "users", column: "triggered_by_id"
  add_foreign_key "ai_team_messages", "ai_team_channels", column: "channel_id"
  add_foreign_key "ai_team_messages", "ai_team_executions", column: "team_execution_id"
  add_foreign_key "ai_team_messages", "ai_team_roles", column: "from_role_id"
  add_foreign_key "ai_team_messages", "ai_team_roles", column: "to_role_id"
  add_foreign_key "ai_team_messages", "users"
  add_foreign_key "ai_team_restructure_events", "accounts"
  add_foreign_key "ai_team_restructure_events", "ai_agent_teams"
  add_foreign_key "ai_team_restructure_events", "ai_agents"
  add_foreign_key "ai_team_roles", "accounts"
  add_foreign_key "ai_team_roles", "ai_agent_teams", column: "agent_team_id"
  add_foreign_key "ai_team_roles", "ai_agents"
  add_foreign_key "ai_team_tasks", "ai_agents", column: "assigned_agent_id"
  add_foreign_key "ai_team_tasks", "ai_team_executions", column: "team_execution_id"
  add_foreign_key "ai_team_tasks", "ai_team_roles", column: "assigned_role_id"
  add_foreign_key "ai_team_templates", "accounts"
  add_foreign_key "ai_team_templates", "users", column: "created_by_id"
  add_foreign_key "ai_telemetry_events", "accounts"
  add_foreign_key "ai_telemetry_events", "ai_agents", column: "agent_id"
  add_foreign_key "ai_template_usage_metrics", "ai_agent_templates", column: "agent_template_id"
  add_foreign_key "ai_test_results", "ai_test_runs", column: "test_run_id"
  add_foreign_key "ai_test_results", "ai_test_scenarios", column: "scenario_id"
  add_foreign_key "ai_test_runs", "accounts"
  add_foreign_key "ai_test_runs", "ai_sandboxes", column: "sandbox_id"
  add_foreign_key "ai_test_runs", "users", column: "triggered_by_id"
  add_foreign_key "ai_test_scenarios", "accounts"
  add_foreign_key "ai_test_scenarios", "ai_agents", column: "target_agent_id"
  add_foreign_key "ai_test_scenarios", "ai_sandboxes", column: "sandbox_id"
  add_foreign_key "ai_test_scenarios", "users", column: "created_by_id"
  add_foreign_key "ai_trajectories", "accounts"
  add_foreign_key "ai_trajectories", "ai_agents"
  add_foreign_key "ai_trajectory_chapters", "ai_trajectories", column: "trajectory_id"
  add_foreign_key "ai_worktree_sessions", "accounts"
  add_foreign_key "ai_worktree_sessions", "users", column: "initiated_by_id"
  add_foreign_key "ai_worktrees", "accounts"
  add_foreign_key "ai_worktrees", "ai_agents"
  add_foreign_key "ai_worktrees", "ai_worktree_sessions", column: "worktree_session_id"
  add_foreign_key "api_key_usages", "api_keys"
  add_foreign_key "api_keys", "accounts"
  add_foreign_key "api_keys", "users", column: "created_by_id"
  add_foreign_key "audit_logs", "accounts"
  add_foreign_key "audit_logs", "users", on_delete: :nullify
  add_foreign_key "blacklisted_tokens", "users"
  add_foreign_key "chat_blacklists", "accounts"
  add_foreign_key "chat_blacklists", "chat_channels", column: "channel_id"
  add_foreign_key "chat_blacklists", "users", column: "blocked_by_id"
  add_foreign_key "chat_channels", "accounts"
  add_foreign_key "chat_channels", "ai_agents", column: "default_agent_id"
  add_foreign_key "chat_channels", "ai_team_channels"
  add_foreign_key "chat_message_attachments", "chat_messages", column: "message_id"
  add_foreign_key "chat_message_attachments", "file_objects"
  add_foreign_key "chat_messages", "ai_messages"
  add_foreign_key "chat_messages", "chat_sessions", column: "session_id"
  add_foreign_key "chat_sessions", "ai_agents", column: "assigned_agent_id"
  add_foreign_key "chat_sessions", "ai_conversations"
  add_foreign_key "chat_sessions", "chat_channels", column: "channel_id"
  add_foreign_key "circuit_breaker_events", "circuit_breakers"
  add_foreign_key "community_agent_ratings", "accounts"
  add_foreign_key "community_agent_ratings", "ai_a2a_tasks", column: "a2a_task_id"
  add_foreign_key "community_agent_ratings", "community_agents"
  add_foreign_key "community_agent_ratings", "users"
  add_foreign_key "community_agent_reports", "accounts", column: "reported_by_account_id"
  add_foreign_key "community_agent_reports", "community_agents"
  add_foreign_key "community_agent_reports", "users", column: "reported_by_user_id"
  add_foreign_key "community_agent_reports", "users", column: "resolved_by_id"
  add_foreign_key "community_agents", "accounts", column: "owner_account_id"
  add_foreign_key "community_agents", "ai_agent_cards", column: "agent_card_id"
  add_foreign_key "community_agents", "ai_agents", column: "agent_id"
  add_foreign_key "community_agents", "users", column: "published_by_id"
  add_foreign_key "community_agents", "users", column: "verified_by_id"
  add_foreign_key "data_deletion_requests", "accounts"
  add_foreign_key "data_deletion_requests", "users"
  add_foreign_key "data_deletion_requests", "users", column: "processed_by_id"
  add_foreign_key "data_deletion_requests", "users", column: "requested_by_id"
  add_foreign_key "data_export_requests", "accounts"
  add_foreign_key "data_export_requests", "users"
  add_foreign_key "data_export_requests", "users", column: "requested_by_id"
  add_foreign_key "data_retention_policies", "accounts"
  add_foreign_key "database_backups", "users", column: "created_by_id"
  add_foreign_key "database_restores", "database_backups"
  add_foreign_key "database_restores", "users", column: "initiated_by_id"
  add_foreign_key "delegation_permissions", "account_delegations"
  add_foreign_key "devops_ai_configs", "accounts", on_delete: :cascade
  add_foreign_key "devops_ai_configs", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "devops_container_image_builds", "accounts"
  add_foreign_key "devops_container_image_builds", "devops_container_image_builds", column: "triggered_by_build_id"
  add_foreign_key "devops_container_image_builds", "devops_container_templates", column: "container_template_id"
  add_foreign_key "devops_container_instances", "accounts"
  add_foreign_key "devops_container_instances", "ai_a2a_tasks", column: "a2a_task_id"
  add_foreign_key "devops_container_instances", "devops_container_templates", column: "template_id"
  add_foreign_key "devops_container_instances", "oauth_applications"
  add_foreign_key "devops_container_instances", "users", column: "triggered_by_id"
  add_foreign_key "devops_container_templates", "accounts"
  add_foreign_key "devops_container_templates", "devops_container_templates", column: "parent_template_id"
  add_foreign_key "devops_container_templates", "users", column: "created_by_id"
  add_foreign_key "devops_docker_activities", "devops_docker_containers", column: "container_id"
  add_foreign_key "devops_docker_activities", "devops_docker_hosts", column: "docker_host_id"
  add_foreign_key "devops_docker_activities", "devops_docker_images", column: "image_id"
  add_foreign_key "devops_docker_activities", "users", column: "triggered_by_id"
  add_foreign_key "devops_docker_containers", "devops_docker_hosts", column: "docker_host_id"
  add_foreign_key "devops_docker_events", "devops_docker_hosts", column: "docker_host_id"
  add_foreign_key "devops_docker_events", "users", column: "acknowledged_by_id"
  add_foreign_key "devops_docker_hosts", "accounts"
  add_foreign_key "devops_docker_hosts", "system_node_instances", column: "node_instance_id", on_delete: :cascade
  add_foreign_key "devops_docker_images", "devops_docker_hosts", column: "docker_host_id"
  add_foreign_key "devops_integration_credentials", "accounts"
  add_foreign_key "devops_integration_credentials", "users", column: "created_by_user_id"
  add_foreign_key "devops_integration_executions", "accounts"
  add_foreign_key "devops_integration_executions", "devops_integration_instances", column: "integration_instance_id"
  add_foreign_key "devops_integration_executions", "users", column: "triggered_by_user_id"
  add_foreign_key "devops_integration_instances", "accounts"
  add_foreign_key "devops_integration_instances", "devops_integration_credentials", column: "integration_credential_id"
  add_foreign_key "devops_integration_instances", "devops_integration_templates", column: "integration_template_id"
  add_foreign_key "devops_integration_instances", "users", column: "created_by_user_id"
  add_foreign_key "devops_kubernetes_clusters", "accounts"
  add_foreign_key "devops_kubernetes_nodes", "devops_kubernetes_clusters", column: "kubernetes_cluster_id", on_delete: :cascade
  add_foreign_key "devops_kubernetes_nodes", "system_node_instances", column: "node_instance_id", on_delete: :cascade
  add_foreign_key "devops_pipeline_repositories", "devops_pipelines", on_delete: :cascade
  add_foreign_key "devops_pipeline_repositories", "git_repositories", on_delete: :cascade
  add_foreign_key "devops_pipeline_runs", "devops_pipelines", on_delete: :cascade
  add_foreign_key "devops_pipeline_runs", "users", column: "triggered_by_id", on_delete: :nullify
  add_foreign_key "devops_pipeline_steps", "devops_pipelines", on_delete: :cascade
  add_foreign_key "devops_pipeline_steps", "shared_prompt_templates", on_delete: :nullify
  add_foreign_key "devops_pipelines", "accounts", on_delete: :cascade
  add_foreign_key "devops_pipelines", "ai_providers", on_delete: :nullify
  add_foreign_key "devops_pipelines", "devops_providers", on_delete: :restrict
  add_foreign_key "devops_pipelines", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "devops_port_allocations", "accounts"
  add_foreign_key "devops_providers", "accounts", on_delete: :cascade
  add_foreign_key "devops_providers", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "devops_resource_quotas", "accounts"
  add_foreign_key "devops_schedules", "devops_pipelines", on_delete: :cascade
  add_foreign_key "devops_schedules", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "devops_secret_references", "accounts"
  add_foreign_key "devops_secret_references", "users", column: "created_by_id"
  add_foreign_key "devops_step_approval_tokens", "devops_step_executions", column: "step_execution_id"
  add_foreign_key "devops_step_approval_tokens", "users", column: "recipient_user_id"
  add_foreign_key "devops_step_approval_tokens", "users", column: "responded_by_id"
  add_foreign_key "devops_step_executions", "devops_pipeline_runs", on_delete: :cascade
  add_foreign_key "devops_step_executions", "devops_pipeline_steps", on_delete: :cascade
  add_foreign_key "devops_swarm_clusters", "accounts"
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
  add_foreign_key "email_deliveries", "users"
  add_foreign_key "external_agents", "accounts", on_delete: :cascade
  add_foreign_key "external_agents", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "federation_partners", "accounts"
  add_foreign_key "federation_partners", "users", column: "approved_by_id"
  add_foreign_key "federation_partners", "users", column: "created_by_id"
  add_foreign_key "file_object_tags", "accounts"
  add_foreign_key "file_object_tags", "file_objects"
  add_foreign_key "file_object_tags", "file_tags"
  add_foreign_key "file_objects", "accounts"
  add_foreign_key "file_objects", "file_storages"
  add_foreign_key "file_objects", "users", column: "deleted_by_id"
  add_foreign_key "file_objects", "users", column: "uploaded_by_id"
  add_foreign_key "file_processing_jobs", "accounts"
  add_foreign_key "file_processing_jobs", "file_objects"
  add_foreign_key "file_shares", "accounts"
  add_foreign_key "file_shares", "file_objects"
  add_foreign_key "file_shares", "users", column: "created_by_id"
  add_foreign_key "file_storages", "accounts"
  add_foreign_key "file_tags", "accounts"
  add_foreign_key "file_versions", "accounts"
  add_foreign_key "file_versions", "file_objects"
  add_foreign_key "file_versions", "users", column: "created_by_id"
  add_foreign_key "git_pipeline_approvals", "accounts", on_delete: :cascade
  add_foreign_key "git_pipeline_approvals", "git_pipelines", on_delete: :cascade
  add_foreign_key "git_pipeline_approvals", "users", column: "requested_by_id", on_delete: :nullify
  add_foreign_key "git_pipeline_approvals", "users", column: "responded_by_id", on_delete: :nullify
  add_foreign_key "git_pipeline_jobs", "accounts", on_delete: :cascade
  add_foreign_key "git_pipeline_jobs", "git_pipelines", on_delete: :cascade
  add_foreign_key "git_pipeline_schedules", "accounts", on_delete: :cascade
  add_foreign_key "git_pipeline_schedules", "git_pipelines", column: "last_pipeline_id", on_delete: :nullify
  add_foreign_key "git_pipeline_schedules", "git_repositories", on_delete: :cascade
  add_foreign_key "git_pipeline_schedules", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "git_pipelines", "accounts", on_delete: :cascade
  add_foreign_key "git_pipelines", "git_repositories", on_delete: :cascade
  add_foreign_key "git_provider_credentials", "accounts", on_delete: :cascade
  add_foreign_key "git_provider_credentials", "git_providers", on_delete: :cascade
  add_foreign_key "git_provider_credentials", "users", on_delete: :nullify
  add_foreign_key "git_providers", "accounts"
  add_foreign_key "git_repositories", "accounts", on_delete: :cascade
  add_foreign_key "git_repositories", "devops_providers", on_delete: :nullify
  add_foreign_key "git_repositories", "git_provider_credentials", on_delete: :cascade
  add_foreign_key "git_runners", "accounts", on_delete: :cascade
  add_foreign_key "git_runners", "git_provider_credentials", on_delete: :cascade
  add_foreign_key "git_runners", "git_repositories", on_delete: :cascade
  add_foreign_key "git_webhook_events", "accounts", on_delete: :cascade
  add_foreign_key "git_webhook_events", "git_providers", on_delete: :cascade
  add_foreign_key "git_webhook_events", "git_repositories", on_delete: :cascade
  add_foreign_key "impersonation_sessions", "users", column: "impersonated_user_id"
  add_foreign_key "impersonation_sessions", "users", column: "impersonator_id"
  add_foreign_key "invitations", "accounts"
  add_foreign_key "invitations", "users", column: "inviter_id"
  add_foreign_key "jwt_blacklists", "users", on_delete: :nullify
  add_foreign_key "knowledge_base_article_views", "users"
  add_foreign_key "knowledge_base_articles", "accounts"
  add_foreign_key "knowledge_base_articles", "knowledge_base_categories", column: "category_id", on_delete: :cascade
  add_foreign_key "knowledge_base_articles", "users", column: "author_id"
  add_foreign_key "knowledge_base_articles", "users", column: "last_edited_by_id"
  add_foreign_key "knowledge_base_attachments", "users", column: "uploaded_by_id"
  add_foreign_key "knowledge_base_categories", "knowledge_base_categories", column: "parent_id"
  add_foreign_key "knowledge_base_comments", "knowledge_base_comments", column: "parent_id"
  add_foreign_key "knowledge_base_comments", "users", column: "author_id"
  add_foreign_key "knowledge_base_workflows", "users"
  add_foreign_key "marketing_campaign_contents", "marketing_campaigns", column: "campaign_id"
  add_foreign_key "marketing_campaign_contents", "users", column: "approved_by_id"
  add_foreign_key "marketing_campaign_email_lists", "marketing_campaigns", column: "campaign_id"
  add_foreign_key "marketing_campaign_email_lists", "marketing_email_lists", column: "email_list_id"
  add_foreign_key "marketing_campaign_metrics", "marketing_campaigns", column: "campaign_id"
  add_foreign_key "marketing_campaigns", "accounts"
  add_foreign_key "marketing_campaigns", "users", column: "created_by_id"
  add_foreign_key "marketing_content_calendars", "accounts"
  add_foreign_key "marketing_content_calendars", "marketing_campaigns", column: "campaign_id"
  add_foreign_key "marketing_email_lists", "accounts"
  add_foreign_key "marketing_email_subscribers", "marketing_email_lists", column: "email_list_id"
  add_foreign_key "marketing_social_media_accounts", "accounts"
  add_foreign_key "marketing_social_media_accounts", "users", column: "connected_by_id"
  add_foreign_key "marketing_waitlist_signups", "accounts", column: "converted_account_id", on_delete: :nullify
  add_foreign_key "marketing_waitlist_signups", "marketing_email_subscribers", column: "email_subscriber_id", on_delete: :nullify
  add_foreign_key "mcp_servers", "accounts"
  add_foreign_key "mcp_sessions", "accounts"
  add_foreign_key "mcp_sessions", "ai_agents"
  add_foreign_key "mcp_sessions", "oauth_applications"
  add_foreign_key "mcp_sessions", "users"
  add_foreign_key "mcp_tool_executions", "mcp_tools"
  add_foreign_key "mcp_tool_executions", "users"
  add_foreign_key "mcp_tools", "mcp_servers"
  add_foreign_key "notifications", "accounts"
  add_foreign_key "notifications", "users"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_grants", "users", column: "resource_owner_id", on_delete: :cascade
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "users", column: "resource_owner_id", on_delete: :cascade
  add_foreign_key "pages", "accounts"
  add_foreign_key "pages", "users", column: "author_id"
  add_foreign_key "password_histories", "users"
  add_foreign_key "report_requests", "accounts"
  add_foreign_key "report_requests", "users", column: "requested_by_id"
  add_foreign_key "role_permissions", "roles"
  add_foreign_key "roles", "accounts", on_delete: :cascade
  add_foreign_key "scheduled_reports", "accounts"
  add_foreign_key "scheduled_reports", "users", column: "created_by_id"
  add_foreign_key "security_secrets", "accounts"
  add_foreign_key "shared_prompt_templates", "accounts", on_delete: :cascade
  add_foreign_key "shared_prompt_templates", "shared_prompt_templates", column: "parent_template_id", on_delete: :nullify
  add_foreign_key "shared_prompt_templates", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "supply_chain_attestations", "accounts"
  add_foreign_key "supply_chain_attestations", "devops_pipeline_runs", column: "pipeline_run_id"
  add_foreign_key "supply_chain_attestations", "supply_chain_sboms", column: "sbom_id"
  add_foreign_key "supply_chain_attestations", "supply_chain_signing_keys", column: "signing_key_id"
  add_foreign_key "supply_chain_attestations", "users", column: "created_by_id"
  add_foreign_key "supply_chain_attributions", "accounts"
  add_foreign_key "supply_chain_attributions", "supply_chain_licenses", column: "license_id"
  add_foreign_key "supply_chain_attributions", "supply_chain_sbom_components", column: "sbom_component_id", on_delete: :cascade
  add_foreign_key "supply_chain_build_provenances", "accounts"
  add_foreign_key "supply_chain_build_provenances", "supply_chain_attestations", column: "attestation_id", on_delete: :cascade
  add_foreign_key "supply_chain_container_images", "accounts"
  add_foreign_key "supply_chain_container_images", "supply_chain_attestations", column: "attestation_id"
  add_foreign_key "supply_chain_container_images", "supply_chain_container_images", column: "base_image_id"
  add_foreign_key "supply_chain_container_images", "supply_chain_sboms", column: "sbom_id"
  add_foreign_key "supply_chain_cve_monitors", "accounts"
  add_foreign_key "supply_chain_cve_monitors", "users", column: "created_by_id"
  add_foreign_key "supply_chain_image_policies", "accounts"
  add_foreign_key "supply_chain_image_policies", "users", column: "created_by_id"
  add_foreign_key "supply_chain_license_detections", "accounts"
  add_foreign_key "supply_chain_license_detections", "supply_chain_licenses", column: "license_id"
  add_foreign_key "supply_chain_license_detections", "supply_chain_sbom_components", column: "sbom_component_id", on_delete: :cascade
  add_foreign_key "supply_chain_license_policies", "accounts"
  add_foreign_key "supply_chain_license_policies", "users", column: "created_by_id"
  add_foreign_key "supply_chain_license_violations", "accounts"
  add_foreign_key "supply_chain_license_violations", "supply_chain_license_policies", column: "license_policy_id"
  add_foreign_key "supply_chain_license_violations", "supply_chain_licenses", column: "license_id"
  add_foreign_key "supply_chain_license_violations", "supply_chain_sbom_components", column: "sbom_component_id"
  add_foreign_key "supply_chain_license_violations", "supply_chain_sboms", column: "sbom_id"
  add_foreign_key "supply_chain_license_violations", "users", column: "exception_approved_by_id"
  add_foreign_key "supply_chain_questionnaire_responses", "accounts"
  add_foreign_key "supply_chain_questionnaire_responses", "supply_chain_questionnaire_templates", column: "template_id"
  add_foreign_key "supply_chain_questionnaire_responses", "supply_chain_risk_assessments", column: "risk_assessment_id"
  add_foreign_key "supply_chain_questionnaire_responses", "supply_chain_vendors", column: "vendor_id"
  add_foreign_key "supply_chain_questionnaire_responses", "users", column: "requested_by_id"
  add_foreign_key "supply_chain_questionnaire_responses", "users", column: "reviewed_by_id"
  add_foreign_key "supply_chain_questionnaire_templates", "accounts"
  add_foreign_key "supply_chain_questionnaire_templates", "users", column: "created_by_id"
  add_foreign_key "supply_chain_remediation_plans", "accounts"
  add_foreign_key "supply_chain_remediation_plans", "supply_chain_sboms", column: "sbom_id"
  add_foreign_key "supply_chain_remediation_plans", "users", column: "approved_by_id"
  add_foreign_key "supply_chain_remediation_plans", "users", column: "created_by_id"
  add_foreign_key "supply_chain_reports", "accounts"
  add_foreign_key "supply_chain_reports", "supply_chain_sboms", column: "sbom_id"
  add_foreign_key "supply_chain_reports", "users", column: "created_by_id"
  add_foreign_key "supply_chain_risk_assessments", "accounts"
  add_foreign_key "supply_chain_risk_assessments", "supply_chain_vendors", column: "vendor_id", on_delete: :cascade
  add_foreign_key "supply_chain_risk_assessments", "users", column: "assessor_id"
  add_foreign_key "supply_chain_sbom_components", "accounts"
  add_foreign_key "supply_chain_sbom_components", "supply_chain_sboms", column: "sbom_id", on_delete: :cascade
  add_foreign_key "supply_chain_sbom_diffs", "accounts"
  add_foreign_key "supply_chain_sbom_diffs", "supply_chain_sboms", column: "base_sbom_id"
  add_foreign_key "supply_chain_sbom_diffs", "supply_chain_sboms", column: "target_sbom_id"
  add_foreign_key "supply_chain_sbom_vulnerabilities", "accounts"
  add_foreign_key "supply_chain_sbom_vulnerabilities", "supply_chain_sbom_components", column: "component_id", on_delete: :cascade
  add_foreign_key "supply_chain_sbom_vulnerabilities", "supply_chain_sboms", column: "sbom_id", on_delete: :cascade
  add_foreign_key "supply_chain_sbom_vulnerabilities", "users", column: "dismissed_by_id"
  add_foreign_key "supply_chain_sboms", "accounts"
  add_foreign_key "supply_chain_sboms", "devops_pipeline_runs", column: "pipeline_run_id"
  add_foreign_key "supply_chain_sboms", "git_repositories", on_delete: :nullify
  add_foreign_key "supply_chain_sboms", "users", column: "created_by_id"
  add_foreign_key "supply_chain_scan_executions", "accounts"
  add_foreign_key "supply_chain_scan_executions", "supply_chain_scan_instances", column: "scan_instance_id", on_delete: :cascade
  add_foreign_key "supply_chain_scan_executions", "users", column: "triggered_by_id"
  add_foreign_key "supply_chain_scan_instances", "accounts"
  add_foreign_key "supply_chain_scan_instances", "supply_chain_scan_templates", column: "scan_template_id"
  add_foreign_key "supply_chain_scan_instances", "users", column: "installed_by_id"
  add_foreign_key "supply_chain_scan_templates", "accounts"
  add_foreign_key "supply_chain_scan_templates", "users", column: "created_by_id"
  add_foreign_key "supply_chain_signing_keys", "accounts"
  add_foreign_key "supply_chain_signing_keys", "supply_chain_signing_keys", column: "rotated_from_id"
  add_foreign_key "supply_chain_signing_keys", "users", column: "created_by_id"
  add_foreign_key "supply_chain_vendor_monitoring_events", "accounts"
  add_foreign_key "supply_chain_vendor_monitoring_events", "supply_chain_vendors", column: "vendor_id", on_delete: :cascade
  add_foreign_key "supply_chain_vendor_monitoring_events", "users", column: "acknowledged_by_id"
  add_foreign_key "supply_chain_vendors", "accounts"
  add_foreign_key "supply_chain_vendors", "users", column: "created_by_id"
  add_foreign_key "supply_chain_verification_logs", "accounts"
  add_foreign_key "supply_chain_verification_logs", "supply_chain_attestations", column: "attestation_id"
  add_foreign_key "supply_chain_verification_logs", "users", column: "verified_by_id"
  add_foreign_key "supply_chain_vulnerability_feeds", "accounts"
  add_foreign_key "supply_chain_vulnerability_scans", "accounts"
  add_foreign_key "supply_chain_vulnerability_scans", "supply_chain_container_images", column: "container_image_id", on_delete: :cascade
  add_foreign_key "supply_chain_vulnerability_scans", "users", column: "triggered_by_id"
  add_foreign_key "system_acme_certificates", "accounts", on_delete: :cascade
  add_foreign_key "system_acme_certificates", "system_acme_dns_credentials", column: "dns_credential_id", on_delete: :nullify
  add_foreign_key "system_acme_dns_credentials", "accounts", on_delete: :cascade
  add_foreign_key "system_bootstrap_tokens", "system_node_instances", column: "node_instance_id", on_delete: :nullify
  add_foreign_key "system_bootstrap_tokens", "system_nodes", column: "node_id", on_delete: :cascade
  add_foreign_key "system_cve_exposures", "system_cves", column: "cve_id"
  add_foreign_key "system_cve_exposures", "system_node_module_versions", column: "node_module_version_id"
  add_foreign_key "system_disk_image_publications", "accounts"
  add_foreign_key "system_disk_image_publications", "file_objects"
  add_foreign_key "system_disk_image_publications", "file_objects", column: "prior_file_object_id"
  add_foreign_key "system_disk_image_publications", "system_disk_image_webhooks", column: "webhook_id"
  add_foreign_key "system_disk_image_publications", "system_node_platforms", column: "node_platform_id"
  add_foreign_key "system_disk_image_publications", "workers", column: "triggered_by_worker_id"
  add_foreign_key "system_disk_image_webhooks", "accounts"
  add_foreign_key "system_disk_image_webhooks", "users", column: "created_by_id"
  add_foreign_key "system_federation_audit_shipments", "accounts"
  add_foreign_key "system_federation_audit_shipments", "system_federation_peers", column: "federation_peer_id"
  add_foreign_key "system_federation_capabilities", "accounts", on_delete: :cascade
  add_foreign_key "system_federation_capabilities", "system_federation_peers", column: "federation_peer_id", on_delete: :cascade
  add_foreign_key "system_federation_grants", "accounts", on_delete: :cascade
  add_foreign_key "system_federation_grants", "system_federation_peers", column: "federation_peer_id", on_delete: :cascade
  add_foreign_key "system_federation_grants", "users", column: "grantor_user_id", on_delete: :restrict
  add_foreign_key "system_federation_network_bridges", "accounts", on_delete: :cascade
  add_foreign_key "system_federation_network_bridges", "system_federation_peers", column: "federation_peer_id", on_delete: :cascade
  add_foreign_key "system_federation_network_bridges", "system_sdwan_networks", column: "sdwan_network_id", on_delete: :restrict
  add_foreign_key "system_federation_peers", "accounts"
  add_foreign_key "system_federation_peers", "system_federation_peers", column: "parent_peer_id", on_delete: :nullify
  add_foreign_key "system_federation_peers", "system_node_certificates", column: "outbound_certificate_id"
  add_foreign_key "system_federation_schema_compatibility", "accounts"
  add_foreign_key "system_federation_service_offerings", "accounts", on_delete: :cascade
  add_foreign_key "system_federation_service_offerings", "system_sdwan_services", column: "service_id"
  add_foreign_key "system_federation_service_subscriptions", "accounts", on_delete: :cascade
  add_foreign_key "system_federation_service_subscriptions", "system_acme_certificates", column: "acme_certificate_id", on_delete: :nullify
  add_foreign_key "system_federation_service_subscriptions", "system_federation_grants", column: "federation_grant_id", on_delete: :restrict
  add_foreign_key "system_federation_service_subscriptions", "system_federation_peers", column: "federation_peer_id", on_delete: :cascade
  add_foreign_key "system_fleet_events", "accounts"
  add_foreign_key "system_fleet_remediation_outcomes", "accounts"
  add_foreign_key "system_gitops_repositories", "accounts"
  add_foreign_key "system_gitops_sync_runs", "system_gitops_repositories", column: "gitops_repository_id"
  add_foreign_key "system_instance_pools", "accounts", on_delete: :cascade
  add_foreign_key "system_instance_pools", "system_node_templates", column: "node_template_id", on_delete: :restrict
  add_foreign_key "system_instance_pools", "system_provider_instance_types", column: "provider_instance_type_id", on_delete: :nullify
  add_foreign_key "system_instance_pools", "system_provider_regions", column: "provider_region_id", on_delete: :nullify
  add_foreign_key "system_migration_chains", "accounts"
  add_foreign_key "system_migration_chains", "users", column: "initiated_by_user_id"
  add_foreign_key "system_migration_plan_steps", "system_migrations", column: "migration_id", on_delete: :cascade
  add_foreign_key "system_migrations", "accounts", on_delete: :cascade
  add_foreign_key "system_migrations", "system_federation_peers", column: "destination_peer_id", on_delete: :restrict
  add_foreign_key "system_migrations", "system_migration_chains", column: "migration_chain_id"
  add_foreign_key "system_migrations", "users", column: "initiated_by_user_id", on_delete: :nullify
  add_foreign_key "system_module_artifacts", "system_node_module_versions", column: "node_module_version_id"
  add_foreign_key "system_module_dependencies", "system_node_modules", column: "dependency_id"
  add_foreign_key "system_module_dependencies", "system_node_modules", column: "node_module_id"
  add_foreign_key "system_module_puppet_assignments", "system_node_modules", column: "node_module_id"
  add_foreign_key "system_module_puppet_assignments", "system_puppet_modules", column: "puppet_module_id"
  add_foreign_key "system_module_service_dependencies", "system_module_services", column: "depends_on_module_service_id", on_delete: :cascade
  add_foreign_key "system_module_service_dependencies", "system_module_services", column: "module_service_id", on_delete: :cascade
  add_foreign_key "system_module_services", "accounts", on_delete: :cascade
  add_foreign_key "system_module_services", "system_node_modules", column: "node_module_id", on_delete: :cascade
  add_foreign_key "system_module_services", "system_service_users", column: "service_user_id"
  add_foreign_key "system_module_user_declarations", "system_node_modules", column: "node_module_id", on_delete: :cascade
  add_foreign_key "system_module_user_declarations", "system_service_groups", column: "service_group_id", on_delete: :cascade
  add_foreign_key "system_module_user_declarations", "system_service_users", column: "service_user_id", on_delete: :cascade
  add_foreign_key "system_mount_encryption_keys", "system_node_instances", column: "node_instance_id", on_delete: :nullify
  add_foreign_key "system_mount_encryption_keys", "system_storage_assignments", column: "storage_assignment_id", on_delete: :cascade
  add_foreign_key "system_node_architectures", "file_objects", column: "image_file_object_id"
  add_foreign_key "system_node_architectures", "file_objects", column: "kernel_file_object_id"
  add_foreign_key "system_node_architectures", "file_objects", column: "ramdisk_file_object_id"
  add_foreign_key "system_node_certificates", "accounts", on_delete: :cascade
  add_foreign_key "system_node_certificates", "system_node_instances", column: "node_instance_id"
  add_foreign_key "system_node_instance_peers", "accounts"
  add_foreign_key "system_node_instance_peers", "system_node_instances", column: "node_instance_id"
  add_foreign_key "system_node_instances", "accounts"
  add_foreign_key "system_node_instances", "system_bootstrap_tokens", column: "enrollment_token_id"
  add_foreign_key "system_node_instances", "system_instance_pools", column: "instance_pool_id", on_delete: :nullify
  add_foreign_key "system_node_instances", "system_nodes", column: "node_id"
  add_foreign_key "system_node_instances", "system_provider_instance_types", column: "provider_instance_type_id"
  add_foreign_key "system_node_instances", "system_provider_regions", column: "provider_region_id"
  add_foreign_key "system_node_instances", "users", column: "ops_hold_by_id"
  add_foreign_key "system_node_module_assignments", "system_node_modules", column: "node_module_id"
  add_foreign_key "system_node_module_assignments", "system_nodes", column: "node_id"
  add_foreign_key "system_node_module_assignments", "system_template_modules", column: "source_template_module_id", on_delete: :nullify
  add_foreign_key "system_node_module_categories", "accounts"
  add_foreign_key "system_node_module_categories", "system_node_module_categories", column: "config_category_id"
  add_foreign_key "system_node_module_categories", "system_node_module_categories", column: "instance_category_id"
  add_foreign_key "system_node_module_categories", "system_node_module_categories", column: "parent_id"
  add_foreign_key "system_node_module_copy_paths", "accounts"
  add_foreign_key "system_node_module_versions", "system_node_modules", column: "node_module_id"
  add_foreign_key "system_node_module_versions", "users", column: "created_by_id"
  add_foreign_key "system_node_modules", "accounts"
  add_foreign_key "system_node_modules", "system_node_instances", column: "node_instance_id"
  add_foreign_key "system_node_modules", "system_node_module_categories", column: "category_id"
  add_foreign_key "system_node_modules", "system_node_module_copy_paths", column: "copy_path_id"
  add_foreign_key "system_node_modules", "system_node_module_versions", column: "current_version_id"
  add_foreign_key "system_node_modules", "system_node_modules", column: "parent_module_id"
  add_foreign_key "system_node_modules", "system_node_platforms", column: "node_platform_id"
  add_foreign_key "system_node_modules", "system_nodes", column: "node_id"
  add_foreign_key "system_node_platforms", "accounts"
  add_foreign_key "system_node_platforms", "system_node_architectures", column: "node_architecture_id"
  add_foreign_key "system_node_scripts", "accounts"
  add_foreign_key "system_node_templates", "accounts"
  add_foreign_key "system_node_templates", "system_node_platforms", column: "node_platform_id"
  add_foreign_key "system_nodes", "accounts"
  add_foreign_key "system_nodes", "system_node_templates", column: "node_template_id"
  add_foreign_key "system_nodes", "workers"
  add_foreign_key "system_package_module_links", "system_node_modules", column: "node_module_id", on_delete: :cascade
  add_foreign_key "system_package_module_links", "system_package_repositories", column: "package_repository_id", on_delete: :restrict
  add_foreign_key "system_package_repositories", "accounts"
  add_foreign_key "system_package_repositories", "users", column: "created_by_id", on_delete: :restrict
  add_foreign_key "system_package_repository_platforms", "system_node_platforms", column: "node_platform_id", on_delete: :cascade
  add_foreign_key "system_package_repository_platforms", "system_package_repositories", column: "package_repository_id", on_delete: :cascade
  add_foreign_key "system_packages", "system_package_repositories", column: "package_repository_id", on_delete: :cascade
  add_foreign_key "system_peer_capability_revocations", "accounts"
  add_foreign_key "system_peer_capability_signing_keys", "accounts"
  add_foreign_key "system_peer_capability_signing_keys", "system_peer_capability_signing_keys", column: "rotated_from_id"
  add_foreign_key "system_platform_deployments", "accounts", on_delete: :cascade
  add_foreign_key "system_platform_deployments", "system_node_templates", column: "node_template_id", on_delete: :restrict
  add_foreign_key "system_platform_deployments", "system_sdwan_virtual_ips", column: "virtual_ip_id", on_delete: :nullify
  add_foreign_key "system_project_metrics", "ai_missions", column: "mission_id"
  add_foreign_key "system_provider_availability_zones", "system_provider_regions", column: "provider_region_id"
  add_foreign_key "system_provider_connections", "accounts"
  add_foreign_key "system_provider_connections", "system_providers", column: "provider_id"
  add_foreign_key "system_provider_credentials", "accounts"
  add_foreign_key "system_provider_credentials", "system_providers", column: "provider_id"
  add_foreign_key "system_provider_instance_types", "accounts"
  add_foreign_key "system_provider_instance_types", "system_providers", column: "provider_id"
  add_foreign_key "system_provider_network_subnets", "system_provider_availability_zones", column: "availability_zone_id"
  add_foreign_key "system_provider_network_subnets", "system_provider_networks", column: "network_id"
  add_foreign_key "system_provider_networks", "accounts"
  add_foreign_key "system_provider_networks", "system_provider_regions", column: "provider_region_id"
  add_foreign_key "system_provider_networks", "system_providers", column: "provider_id"
  add_foreign_key "system_provider_regions", "accounts"
  add_foreign_key "system_provider_regions", "system_providers", column: "provider_id"
  add_foreign_key "system_provider_volume_members", "system_provider_volumes", column: "provider_volume_id"
  add_foreign_key "system_provider_volume_snapshots", "accounts"
  add_foreign_key "system_provider_volume_snapshots", "system_provider_volumes", column: "volume_id"
  add_foreign_key "system_provider_volume_types", "accounts"
  add_foreign_key "system_provider_volume_types", "system_providers", column: "provider_id"
  add_foreign_key "system_provider_volumes", "accounts"
  add_foreign_key "system_provider_volumes", "system_node_instances", column: "node_instance_id"
  add_foreign_key "system_provider_volumes", "system_provider_availability_zones", column: "availability_zone_id"
  add_foreign_key "system_provider_volumes", "system_provider_regions", column: "provider_region_id"
  add_foreign_key "system_provider_volumes", "system_provider_volume_types", column: "volume_type_id"
  add_foreign_key "system_providers", "accounts"
  add_foreign_key "system_puppet_modules", "accounts"
  add_foreign_key "system_puppet_resources", "system_puppet_modules", column: "puppet_module_id"
  add_foreign_key "system_region_instance_types", "system_provider_instance_types", column: "provider_instance_type_id"
  add_foreign_key "system_region_instance_types", "system_provider_regions", column: "provider_region_id"
  add_foreign_key "system_region_volume_types", "system_provider_regions", column: "provider_region_id"
  add_foreign_key "system_region_volume_types", "system_provider_volume_types", column: "volume_type_id"
  add_foreign_key "system_sdwan_access_grants", "accounts"
  add_foreign_key "system_sdwan_access_grants", "system_sdwan_networks", column: "sdwan_network_id"
  add_foreign_key "system_sdwan_access_grants", "users"
  add_foreign_key "system_sdwan_access_grants", "users", column: "granted_by_id"
  add_foreign_key "system_sdwan_account_bgps", "accounts"
  add_foreign_key "system_sdwan_bgp_sessions", "system_sdwan_networks", column: "sdwan_network_id"
  add_foreign_key "system_sdwan_bgp_sessions", "system_sdwan_peers", column: "neighbor_peer_id"
  add_foreign_key "system_sdwan_bgp_sessions", "system_sdwan_peers", column: "sdwan_peer_id"
  add_foreign_key "system_sdwan_configurations", "accounts"
  add_foreign_key "system_sdwan_constellation_signing_keys", "accounts"
  add_foreign_key "system_sdwan_constellation_signing_keys", "system_sdwan_constellation_signing_keys", column: "rotated_from_id"
  add_foreign_key "system_sdwan_firewall_rules", "accounts"
  add_foreign_key "system_sdwan_firewall_rules", "system_sdwan_networks", column: "sdwan_network_id"
  add_foreign_key "system_sdwan_flow_samples", "accounts"
  add_foreign_key "system_sdwan_flow_samples", "system_sdwan_ipfix_collectors", column: "ipfix_collector_id", on_delete: :cascade
  add_foreign_key "system_sdwan_host_bridges", "accounts"
  add_foreign_key "system_sdwan_host_bridges", "system_node_instances", column: "node_instance_id"
  add_foreign_key "system_sdwan_host_vrf_assignments", "accounts"
  add_foreign_key "system_sdwan_host_vrf_assignments", "system_node_instances", column: "node_instance_id"
  add_foreign_key "system_sdwan_host_vrf_assignments", "system_sdwan_networks", column: "sdwan_network_id"
  add_foreign_key "system_sdwan_ipfix_collectors", "accounts"
  add_foreign_key "system_sdwan_membership_credentials", "accounts"
  add_foreign_key "system_sdwan_membership_credentials", "system_sdwan_networks", column: "sdwan_network_id"
  add_foreign_key "system_sdwan_membership_credentials", "system_sdwan_peers", column: "sdwan_peer_id"
  add_foreign_key "system_sdwan_networks", "accounts"
  add_foreign_key "system_sdwan_ovn_acls", "accounts"
  add_foreign_key "system_sdwan_ovn_acls", "system_sdwan_ovn_logical_switches", column: "sdwan_ovn_logical_switch_id", on_delete: :cascade
  add_foreign_key "system_sdwan_ovn_deployments", "accounts"
  add_foreign_key "system_sdwan_ovn_logical_switch_ports", "accounts"
  add_foreign_key "system_sdwan_ovn_logical_switch_ports", "system_node_instances", column: "host_node_instance_id"
  add_foreign_key "system_sdwan_ovn_logical_switch_ports", "system_sdwan_ovn_logical_switches", column: "sdwan_ovn_logical_switch_id"
  add_foreign_key "system_sdwan_ovn_logical_switches", "accounts"
  add_foreign_key "system_sdwan_ovn_logical_switches", "system_sdwan_ovn_deployments", column: "sdwan_ovn_deployment_id"
  add_foreign_key "system_sdwan_peer_keys", "system_sdwan_peer_keys", column: "rotated_from_id"
  add_foreign_key "system_sdwan_peer_keys", "system_sdwan_peers", column: "sdwan_peer_id"
  add_foreign_key "system_sdwan_peers", "accounts"
  add_foreign_key "system_sdwan_peers", "system_node_instances", column: "node_instance_id", on_delete: :cascade
  add_foreign_key "system_sdwan_peers", "system_sdwan_networks", column: "sdwan_network_id"
  add_foreign_key "system_sdwan_port_mappings", "accounts"
  add_foreign_key "system_sdwan_port_mappings", "system_sdwan_networks", column: "sdwan_network_id"
  add_foreign_key "system_sdwan_port_mappings", "system_sdwan_peers", column: "sdwan_peer_id"
  add_foreign_key "system_sdwan_port_mappings", "system_sdwan_peers", column: "target_peer_id"
  add_foreign_key "system_sdwan_port_mappings", "system_sdwan_virtual_ips", column: "target_virtual_ip_id"
  add_foreign_key "system_sdwan_route_leaks", "accounts"
  add_foreign_key "system_sdwan_route_leaks", "system_sdwan_networks", column: "dest_network_id"
  add_foreign_key "system_sdwan_route_leaks", "system_sdwan_networks", column: "source_network_id"
  add_foreign_key "system_sdwan_route_leaks", "users", column: "approved_by_id"
  add_foreign_key "system_sdwan_route_policies", "accounts"
  add_foreign_key "system_sdwan_services", "accounts"
  add_foreign_key "system_sdwan_services", "system_acme_certificates", column: "local_certificate_id"
  add_foreign_key "system_sdwan_services", "system_sdwan_virtual_ips", column: "backend_vip_id"
  add_foreign_key "system_sdwan_subnet_advertisements", "accounts"
  add_foreign_key "system_sdwan_subnet_advertisements", "system_sdwan_networks", column: "sdwan_network_id"
  add_foreign_key "system_sdwan_subnet_advertisements", "system_sdwan_peers", column: "sdwan_peer_id"
  add_foreign_key "system_sdwan_user_devices", "system_sdwan_access_grants", column: "sdwan_access_grant_id"
  add_foreign_key "system_sdwan_virtual_ip_assignments", "system_sdwan_peers", column: "sdwan_peer_id"
  add_foreign_key "system_sdwan_virtual_ip_assignments", "system_sdwan_virtual_ips", column: "sdwan_virtual_ip_id"
  add_foreign_key "system_sdwan_virtual_ips", "accounts"
  add_foreign_key "system_sdwan_virtual_ips", "system_sdwan_networks", column: "sdwan_network_id"
  add_foreign_key "system_service_user_group_memberships", "system_service_groups", column: "service_group_id", on_delete: :cascade
  add_foreign_key "system_service_user_group_memberships", "system_service_users", column: "service_user_id", on_delete: :cascade
  add_foreign_key "system_service_users", "system_service_groups", column: "primary_group_id"
  add_foreign_key "system_slo_definitions", "system_node_modules", column: "node_module_id"
  add_foreign_key "system_storage_assignments", "accounts"
  add_foreign_key "system_storage_assignments", "system_node_instances", column: "node_instance_id", on_delete: :cascade
  add_foreign_key "system_storage_assignments", "system_sdwan_networks", column: "sdwan_network_id", on_delete: :nullify
  add_foreign_key "system_storage_assignments", "system_sdwan_virtual_ips", column: "sdwan_virtual_ip_id", on_delete: :nullify
  add_foreign_key "system_storage_assignments", "system_service_groups", column: "shared_group_id"
  add_foreign_key "system_storage_assignments", "system_service_users", column: "service_user_id"
  add_foreign_key "system_storage_credentials", "system_node_instances", column: "node_instance_id", on_delete: :cascade
  add_foreign_key "system_storage_credentials", "system_storage_assignments", column: "storage_assignment_id", on_delete: :cascade
  add_foreign_key "system_storage_migrations", "accounts"
  add_foreign_key "system_storage_migrations", "system_node_instances", column: "node_instance_id"
  add_foreign_key "system_storage_migrations", "system_provider_volumes", column: "source_volume_id"
  add_foreign_key "system_storage_migrations", "system_provider_volumes", column: "target_volume_id"
  add_foreign_key "system_storage_migrations", "users", column: "initiated_by_user_id"
  add_foreign_key "system_sudoers_grants", "system_node_modules", column: "node_module_id", on_delete: :cascade
  add_foreign_key "system_sudoers_grants", "system_service_users", column: "service_user_id", on_delete: :cascade
  add_foreign_key "system_tasks", "accounts"
  add_foreign_key "system_tasks", "users", column: "initiated_by_id"
  add_foreign_key "system_tasks", "workers", column: "claimed_by_worker_id", on_delete: :nullify
  add_foreign_key "system_template_modules", "system_node_modules", column: "node_module_id"
  add_foreign_key "system_template_modules", "system_node_templates", column: "node_template_id"
  add_foreign_key "system_unclaimed_devices", "accounts"
  add_foreign_key "system_unclaimed_devices", "system_node_instances", column: "claimed_node_instance_id"
  add_foreign_key "task_executions", "scheduled_tasks"
  add_foreign_key "terms_acceptances", "accounts"
  add_foreign_key "terms_acceptances", "users"
  add_foreign_key "user_consents", "accounts"
  add_foreign_key "user_consents", "users"
  add_foreign_key "user_roles", "roles"
  add_foreign_key "user_roles", "users"
  add_foreign_key "user_roles", "users", column: "granted_by_id"
  add_foreign_key "user_tokens", "users"
  add_foreign_key "users", "accounts"
  add_foreign_key "webhook_deliveries", "webhook_endpoints"
  add_foreign_key "webhook_deliveries", "webhook_events"
  add_foreign_key "webhook_delivery_stats", "webhook_endpoints"
  add_foreign_key "webhook_endpoints", "accounts"
  add_foreign_key "webhook_endpoints", "users", column: "created_by_id"
  add_foreign_key "webhook_events", "accounts"
  add_foreign_key "worker_activities", "workers"
  add_foreign_key "worker_roles", "roles"
  add_foreign_key "worker_roles", "workers"
  add_foreign_key "workers", "accounts"
end
