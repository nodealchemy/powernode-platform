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

ActiveRecord::Schema[8.1].define(version: 2026_02_17_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "ltree"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"
  enable_extension "vector"

  create_table "account_delegations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "delegated_user_id"], name: "index_account_delegations_unique", unique: true
    t.index ["account_id"], name: "index_account_delegations_on_account_id"
    t.index ["delegated_by_id"], name: "index_account_delegations_on_delegated_by_id"
    t.index ["delegated_user_id"], name: "index_account_delegations_on_delegated_user_id"
    t.index ["expires_at"], name: "index_account_delegations_on_expires_at"
    t.index ["revoked_by_id"], name: "index_account_delegations_on_revoked_by_id"
    t.index ["role_id"], name: "index_account_delegations_on_role_id"
    t.index ["status"], name: "index_account_delegations_on_status"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'revoked'::character varying::text])", name: "valid_delegation_status"
  end

  create_table "account_git_webhook_configs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "status"], name: "index_account_git_webhooks_on_account_status"
    t.index ["account_id"], name: "index_account_git_webhook_configs_on_account_id"
    t.index ["created_by_id"], name: "index_account_git_webhook_configs_on_created_by_id"
    t.check_constraint "branch_filter_type::text = ANY (ARRAY['none'::character varying, 'exact'::character varying, 'wildcard'::character varying, 'regex'::character varying]::text[])", name: "account_git_webhook_configs_branch_filter_type_check"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'inactive'::character varying]::text[])", name: "account_git_webhook_configs_status_check"
  end

  create_table "account_terminations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "accounts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "analytics_tier", default: "free", null: false
    t.string "billing_email"
    t.datetime "created_at", null: false
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
    t.datetime "updated_at", null: false
    t.index ["analytics_tier"], name: "index_accounts_on_analytics_tier"
    t.index ["paypal_customer_id"], name: "index_accounts_on_paypal_customer_id", unique: true, where: "(paypal_customer_id IS NOT NULL)"
    t.index ["status"], name: "index_accounts_on_status"
    t.index ["stripe_customer_id"], name: "index_accounts_on_stripe_customer_id", unique: true, where: "(stripe_customer_id IS NOT NULL)"
    t.index ["subdomain"], name: "index_accounts_on_subdomain", unique: true, where: "((subdomain IS NOT NULL) AND ((subdomain)::text <> ''::text))"
    t.check_constraint "analytics_tier::text = ANY (ARRAY['free'::character varying::text, 'starter'::character varying::text, 'pro'::character varying::text, 'enterprise'::character varying::text])", name: "check_analytics_tier"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'cancelled'::character varying::text, 'suspended'::character varying::text])", name: "valid_account_status"
  end

  create_table "admin_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["category"], name: "idx_admin_settings_on_category"
    t.index ["is_public"], name: "idx_admin_settings_on_is_public"
    t.index ["key"], name: "idx_admin_settings_on_key_unique", unique: true
    t.index ["setting_type"], name: "idx_admin_settings_on_setting_type"
    t.index ["sort_order"], name: "idx_admin_settings_on_sort_order"
    t.check_constraint "setting_type::text = ANY (ARRAY['string'::character varying::text, 'text'::character varying::text, 'integer'::character varying::text, 'boolean'::character varying::text, 'json'::character varying::text, 'array'::character varying::text])", name: "valid_admin_setting_type"
  end

  create_table "ai_a2a_task_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["ai_a2a_task_id", "created_at"], name: "idx_a2a_events_task_time"
    t.index ["ai_a2a_task_id"], name: "index_ai_a2a_task_events_on_ai_a2a_task_id"
    t.index ["event_id"], name: "index_ai_a2a_task_events_on_event_id"
    t.index ["event_type"], name: "index_ai_a2a_task_events_on_event_type"
    t.check_constraint "event_type::text = ANY (ARRAY['status_change'::character varying, 'artifact_added'::character varying, 'message'::character varying, 'progress'::character varying, 'error'::character varying, 'cancelled'::character varying]::text[])", name: "ai_a2a_task_events_type_check"
  end

  create_table "ai_a2a_tasks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_workflow_run_id"
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
    t.index ["ai_workflow_run_id", "sequence_number"], name: "index_ai_a2a_tasks_on_ai_workflow_run_id_and_sequence_number"
    t.index ["ai_workflow_run_id"], name: "index_ai_a2a_tasks_on_ai_workflow_run_id"
    t.index ["created_at"], name: "index_ai_a2a_tasks_on_created_at"
    t.index ["dag_execution_id", "execution_order"], name: "index_ai_a2a_tasks_on_dag_execution_id_and_execution_order", where: "(dag_execution_id IS NOT NULL)"
    t.index ["dag_execution_id"], name: "index_ai_a2a_tasks_on_dag_execution_id", where: "(dag_execution_id IS NOT NULL)"
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
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'active'::character varying, 'completed'::character varying, 'failed'::character varying, 'cancelled'::character varying, 'input_required'::character varying]::text[])", name: "ai_a2a_tasks_status_check"
  end

  create_table "ai_ab_tests", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_account_credits", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.boolean "allow_negative_balance", default: false, null: false
    t.decimal "balance", precision: 15, scale: 4, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.decimal "credit_limit", precision: 15, scale: 4
    t.boolean "is_reseller", default: false, null: false
    t.datetime "last_purchase_at"
    t.datetime "last_usage_at"
    t.decimal "lifetime_credits_expired", precision: 15, scale: 4, default: "0.0"
    t.decimal "lifetime_credits_purchased", precision: 15, scale: 4, default: "0.0"
    t.decimal "lifetime_credits_transferred_in", precision: 15, scale: 4, default: "0.0"
    t.decimal "lifetime_credits_transferred_out", precision: 15, scale: 4, default: "0.0"
    t.decimal "lifetime_credits_used", precision: 15, scale: 4, default: "0.0"
    t.decimal "reseller_discount_percentage", precision: 5, scale: 2, default: "0.0"
    t.decimal "reserved_balance", precision: 15, scale: 4, default: "0.0", null: false
    t.jsonb "settings", default: {}
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_ai_account_credits_on_account_id", unique: true
    t.index ["balance"], name: "index_ai_account_credits_on_balance"
    t.index ["is_reseller"], name: "index_ai_account_credits_on_is_reseller"
  end

  create_table "ai_agent_budgets", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
  end

  create_table "ai_agent_cards", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "name"], name: "idx_agent_cards_account_name", unique: true
    t.index ["account_id"], name: "index_ai_agent_cards_on_account_id"
    t.index ["ai_agent_id"], name: "index_ai_agent_cards_on_ai_agent_id"
    t.index ["capabilities"], name: "index_ai_agent_cards_on_capabilities", using: :gin
    t.index ["protocol_version"], name: "index_ai_agent_cards_on_protocol_version"
    t.index ["status"], name: "index_ai_agent_cards_on_status"
    t.index ["tags"], name: "index_ai_agent_cards_on_tags", using: :gin
    t.index ["visibility"], name: "index_ai_agent_cards_on_visibility"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'inactive'::character varying, 'deprecated'::character varying]::text[])", name: "ai_agent_cards_status_check"
    t.check_constraint "visibility::text = ANY (ARRAY['private'::character varying, 'internal'::character varying, 'public'::character varying]::text[])", name: "ai_agent_cards_visibility_check"
  end

  create_table "ai_agent_connections", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_agent_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_agent_identities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_agent_installations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "agent_template_id"], name: "idx_agent_installations_account_template", unique: true
    t.index ["account_id"], name: "index_ai_agent_installations_on_account_id"
    t.index ["agent_template_id"], name: "index_ai_agent_installations_on_agent_template_id"
    t.index ["installed_agent_id"], name: "index_ai_agent_installations_on_installed_agent_id"
    t.index ["installed_by_id"], name: "index_ai_agent_installations_on_installed_by_id"
    t.index ["license_expires_at"], name: "index_ai_agent_installations_on_license_expires_at"
    t.index ["status"], name: "index_ai_agent_installations_on_status"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'paused'::character varying::text, 'expired'::character varying::text, 'cancelled'::character varying::text, 'pending_update'::character varying::text])", name: "check_installation_status"
  end

  create_table "ai_agent_lineages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["parent_agent_id"], name: "index_ai_agent_lineages_on_parent_agent_id"
  end

  create_table "ai_agent_privilege_policies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_agent_reviews", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_agent_short_term_memories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "access_count", default: 0
    t.uuid "account_id", null: false
    t.uuid "agent_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "last_accessed_at"
    t.string "memory_key", null: false
    t.string "memory_type", default: "general"
    t.jsonb "memory_value", null: false
    t.string "session_id", null: false
    t.integer "ttl_seconds", default: 3600
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_ai_agent_short_term_memories_on_account_id"
    t.index ["agent_id", "session_id", "memory_key"], name: "idx_short_term_memories_agent_session_key", unique: true
    t.index ["agent_id"], name: "index_ai_agent_short_term_memories_on_agent_id"
    t.index ["expires_at"], name: "index_ai_agent_short_term_memories_on_expires_at"
  end

  create_table "ai_agent_skills", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_agent_team_members", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_agent_id", null: false, comment: "Agent assigned to this team role"
    t.uuid "ai_agent_team_id", null: false, comment: "Team this member belongs to"
    t.jsonb "capabilities", default: [], null: false, comment: "Specific capabilities this member provides to the team"
    t.datetime "created_at", null: false
    t.boolean "is_lead", default: false, null: false, comment: "Whether this member leads/coordinates the team"
    t.jsonb "member_config", default: {}, null: false, comment: "Member-specific configuration (retry_count, timeout, etc.)"
    t.integer "priority_order", default: 0, null: false, comment: "Execution priority (0 = highest, for sequential teams)"
    t.string "role", null: false, comment: "Role in team: manager, researcher, writer, reviewer, executor"
    t.datetime "updated_at", null: false
    t.index ["ai_agent_id"], name: "index_ai_agent_team_members_on_ai_agent_id"
    t.index ["ai_agent_team_id", "ai_agent_id"], name: "index_team_members_on_team_and_agent", unique: true
    t.index ["ai_agent_team_id", "is_lead"], name: "index_team_members_on_team_and_lead"
    t.index ["ai_agent_team_id", "priority_order"], name: "index_team_members_on_team_and_priority"
    t.index ["ai_agent_team_id"], name: "index_ai_agent_team_members_on_ai_agent_team_id"
  end

  create_table "ai_agent_teams", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.string "status", default: "active", null: false, comment: "Team status: active, inactive, archived"
    t.integer "task_timeout_seconds", default: 300
    t.jsonb "team_config", default: {}, null: false, comment: "Team-specific configuration (max_iterations, timeout, etc.)"
    t.string "team_topology", default: "hierarchical"
    t.string "team_type", default: "hierarchical", null: false, comment: "Team coordination type: hierarchical, mesh, sequential, parallel"
    t.uuid "template_id"
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_ai_agent_teams_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_agent_teams_on_account_id"
    t.index ["team_topology"], name: "index_ai_agent_teams_on_team_topology"
    t.index ["team_type"], name: "index_ai_agent_teams_on_team_type"
    t.index ["template_id"], name: "index_ai_agent_teams_on_template_id"
    t.check_constraint "communication_pattern::text = ANY (ARRAY['hub_spoke'::character varying::text, 'peer_to_peer'::character varying::text, 'broadcast'::character varying::text, 'sequential'::character varying::text, 'event_driven'::character varying::text])", name: "check_communication_pattern"
    t.check_constraint "coordination_strategy::text = ANY (ARRAY['manager_led'::character varying::text, 'consensus'::character varying::text, 'auction'::character varying::text, 'round_robin'::character varying::text, 'priority_based'::character varying::text])", name: "check_coordination_strategy"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'archived'::character varying::text])", name: "ai_agent_teams_status_check"
    t.check_constraint "team_topology::text = ANY (ARRAY['hierarchical'::character varying::text, 'flat'::character varying::text, 'mesh'::character varying::text, 'pipeline'::character varying::text, 'hybrid'::character varying::text])", name: "check_team_topology_enum"
    t.check_constraint "team_type::text = ANY (ARRAY['hierarchical'::character varying::text, 'mesh'::character varying::text, 'sequential'::character varying::text, 'parallel'::character varying::text])", name: "ai_agent_teams_team_type_check"
  end

  create_table "ai_agent_templates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["average_rating", "installation_count"], name: "idx_on_average_rating_installation_count_b612451228"
    t.index ["category"], name: "index_ai_agent_templates_on_category"
    t.index ["is_featured"], name: "index_ai_agent_templates_on_is_featured"
    t.index ["pricing_type"], name: "index_ai_agent_templates_on_pricing_type"
    t.index ["publisher_id"], name: "index_ai_agent_templates_on_publisher_id"
    t.index ["slug"], name: "index_ai_agent_templates_on_slug", unique: true
    t.index ["source_agent_id"], name: "index_ai_agent_templates_on_source_agent_id"
    t.index ["status", "visibility"], name: "index_ai_agent_templates_on_status_and_visibility"
    t.index ["vertical"], name: "index_ai_agent_templates_on_vertical"
    t.check_constraint "pricing_type::text = ANY (ARRAY['free'::character varying::text, 'one_time'::character varying::text, 'subscription'::character varying::text, 'usage_based'::character varying::text, 'freemium'::character varying::text])", name: "check_pricing_type"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'pending_review'::character varying::text, 'published'::character varying::text, 'rejected'::character varying::text, 'archived'::character varying::text, 'suspended'::character varying::text])", name: "check_template_status"
    t.check_constraint "visibility::text = ANY (ARRAY['private'::character varying::text, 'unlisted'::character varying::text, 'public'::character varying::text, 'enterprise'::character varying::text])", name: "check_template_visibility"
  end

  create_table "ai_agent_trust_scores", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_agents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "agent_type", limit: 50, null: false
    t.uuid "ai_provider_id", null: false
    t.jsonb "autonomy_config", default: {}
    t.jsonb "conversation_profile", default: {}, null: false
    t.datetime "created_at", null: false
    t.uuid "creator_id", null: false
    t.text "description"
    t.jsonb "execution_stats", default: {}
    t.boolean "is_concierge", default: false, null: false
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
    t.index ["account_id", "name"], name: "index_ai_agents_on_account_id_and_name"
    t.index ["account_id", "status"], name: "index_ai_agents_on_account_and_status"
    t.index ["account_id"], name: "index_ai_agents_on_account_id"
    t.index ["agent_type"], name: "index_ai_agents_on_agent_type"
    t.index ["ai_provider_id"], name: "index_ai_agents_on_ai_provider_id"
    t.index ["creator_id"], name: "index_ai_agents_on_creator_id"
    t.index ["is_public"], name: "index_ai_agents_on_is_public"
    t.index ["last_executed_at"], name: "index_ai_agents_on_last_executed_at"
    t.index ["mcp_registered_at"], name: "index_ai_agents_on_mcp_registered_at"
    t.index ["mcp_tool_manifest"], name: "index_ai_agents_on_mcp_tool_manifest", using: :gin
    t.index ["parent_agent_id"], name: "index_ai_agents_on_parent_agent_id"
    t.index ["slug"], name: "index_ai_agents_on_slug", unique: true
    t.index ["status"], name: "index_ai_agents_on_status"
  end

  create_table "ai_agui_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_agui_sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_approval_chains", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.check_constraint "trigger_type::text = ANY (ARRAY['workflow_deploy'::character varying::text, 'agent_deploy'::character varying::text, 'high_cost'::character varying::text, 'sensitive_data'::character varying::text, 'model_change'::character varying::text, 'policy_override'::character varying::text, 'manual'::character varying::text])", name: "check_chain_trigger_type"
  end

  create_table "ai_approval_decisions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_approval_requests", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_code_factory_evidence_manifests", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_code_factory_harness_gaps", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "status"], name: "idx_cf_harness_gaps_account_status"
    t.index ["account_id"], name: "index_ai_code_factory_harness_gaps_on_account_id"
    t.index ["incident_id"], name: "idx_cf_harness_gaps_incident"
    t.index ["risk_contract_id"], name: "index_ai_code_factory_harness_gaps_on_risk_contract_id"
  end

  create_table "ai_code_factory_review_states", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "status"], name: "idx_cf_review_states_account_status"
    t.index ["account_id"], name: "index_ai_code_factory_review_states_on_account_id"
    t.index ["mission_id"], name: "index_ai_code_factory_review_states_on_mission_id"
    t.index ["repository_id", "pr_number", "head_sha"], name: "idx_cf_review_states_repo_pr_sha", unique: true
    t.index ["repository_id"], name: "index_ai_code_factory_review_states_on_repository_id"
    t.index ["risk_contract_id"], name: "index_ai_code_factory_review_states_on_risk_contract_id"
  end

  create_table "ai_code_factory_risk_contracts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "repository_id", "status"], name: "idx_cf_contracts_account_repo_status"
    t.index ["account_id"], name: "index_ai_code_factory_risk_contracts_on_account_id"
    t.index ["created_by_id"], name: "index_ai_code_factory_risk_contracts_on_created_by_id"
    t.index ["repository_id"], name: "index_ai_code_factory_risk_contracts_on_repository_id"
  end

  create_table "ai_code_review_comments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_code_reviews", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_compliance_audit_entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_compliance_policies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_compliance_reports", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_compound_learnings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "access_count", default: 0, null: false
    t.uuid "account_id", null: false
    t.uuid "ai_agent_team_id"
    t.jsonb "applicable_domains", default: []
    t.string "category", null: false
    t.decimal "confidence_score", precision: 5, scale: 4, default: "0.5", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.decimal "decay_rate", precision: 5, scale: 4, default: "0.003"
    t.decimal "effectiveness_score", precision: 5, scale: 4
    t.vector "embedding", limit: 1536
    t.datetime "expires_at"
    t.string "extraction_method"
    t.decimal "importance_score", precision: 5, scale: 4, default: "0.5", null: false
    t.integer "injection_count", default: 0, null: false
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
    t.index ["account_id", "category"], name: "index_ai_compound_learnings_on_account_id_and_category"
    t.index ["account_id", "scope"], name: "index_ai_compound_learnings_on_account_id_and_scope"
    t.index ["account_id", "status"], name: "index_ai_compound_learnings_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_compound_learnings_on_account_id"
    t.index ["ai_agent_team_id", "category"], name: "index_ai_compound_learnings_on_ai_agent_team_id_and_category"
    t.index ["ai_agent_team_id"], name: "index_ai_compound_learnings_on_ai_agent_team_id"
    t.index ["applicable_domains"], name: "index_ai_compound_learnings_on_applicable_domains", using: :gin
    t.index ["effectiveness_score"], name: "index_ai_compound_learnings_on_effectiveness_score"
    t.index ["embedding"], name: "idx_compound_learnings_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["importance_score"], name: "index_ai_compound_learnings_on_importance_score"
    t.index ["source_agent_id"], name: "index_ai_compound_learnings_on_source_agent_id"
    t.index ["source_execution_id"], name: "index_ai_compound_learnings_on_source_execution_id"
    t.index ["superseded_by_id"], name: "index_ai_compound_learnings_on_superseded_by_id"
    t.index ["tags"], name: "index_ai_compound_learnings_on_tags", using: :gin
  end

  create_table "ai_context_access_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "created_at"], name: "idx_access_logs_account_created"
    t.index ["account_id"], name: "index_ai_context_access_logs_on_account_id"
    t.index ["action"], name: "index_ai_context_access_logs_on_action"
    t.index ["ai_agent_id"], name: "index_ai_context_access_logs_on_ai_agent_id"
    t.index ["ai_context_entry_id"], name: "index_ai_context_access_logs_on_ai_context_entry_id"
    t.index ["ai_persistent_context_id", "action"], name: "idx_access_logs_context_action"
    t.index ["ai_persistent_context_id"], name: "index_ai_context_access_logs_on_ai_persistent_context_id"
    t.index ["success"], name: "index_ai_context_access_logs_on_success"
    t.index ["user_id"], name: "index_ai_context_access_logs_on_user_id"
  end

  create_table "ai_context_entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.check_constraint "memory_type::text = ANY (ARRAY['factual'::character varying, 'experiential'::character varying, 'working'::character varying]::text[])", name: "ai_context_entries_memory_type_check"
  end

  create_table "ai_conversations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_cost_attributions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "attribution_date"], name: "idx_cost_attributions_account_date"
    t.index ["account_id"], name: "index_ai_cost_attributions_on_account_id"
    t.index ["attribution_date"], name: "index_ai_cost_attributions_on_attribution_date"
    t.index ["cost_category", "attribution_date"], name: "idx_on_cost_category_attribution_date_66ad966491"
    t.index ["provider_id"], name: "index_ai_cost_attributions_on_provider_id"
    t.index ["roi_metric_id"], name: "index_ai_cost_attributions_on_roi_metric_id"
    t.index ["source_type", "source_id"], name: "idx_cost_attributions_source"
    t.check_constraint "cost_category::text = ANY (ARRAY['ai_inference'::character varying::text, 'ai_training'::character varying::text, 'embedding'::character varying::text, 'storage'::character varying::text, 'compute'::character varying::text, 'api_calls'::character varying::text, 'bandwidth'::character varying::text, 'other'::character varying::text])", name: "check_cost_category"
  end

  create_table "ai_cost_optimization_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_credit_packs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "bonus_credits", precision: 10, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.integer "credits", null: false
    t.string "description"
    t.decimal "effective_price_per_credit", precision: 10, scale: 6
    t.boolean "is_active", default: true, null: false
    t.boolean "is_featured", default: false, null: false
    t.integer "max_purchase_quantity"
    t.jsonb "metadata", default: {}
    t.integer "min_purchase_quantity", default: 1
    t.string "name", null: false
    t.string "pack_type", default: "standard", null: false
    t.decimal "price_usd", precision: 10, scale: 2, null: false
    t.integer "sort_order", default: 0
    t.datetime "updated_at", null: false
    t.datetime "valid_from"
    t.datetime "valid_until"
    t.index ["is_active", "sort_order"], name: "index_ai_credit_packs_on_is_active_and_sort_order"
    t.index ["is_active"], name: "index_ai_credit_packs_on_is_active"
    t.index ["pack_type"], name: "index_ai_credit_packs_on_pack_type"
    t.check_constraint "pack_type::text = ANY (ARRAY['standard'::character varying::text, 'bulk'::character varying::text, 'enterprise'::character varying::text, 'promotional'::character varying::text, 'reseller'::character varying::text])", name: "check_credit_pack_type"
  end

  create_table "ai_credit_purchases", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.decimal "bonus_credits", precision: 15, scale: 4, default: "0.0"
    t.datetime "created_at", null: false
    t.uuid "credit_pack_id", null: false
    t.datetime "credits_applied_at"
    t.decimal "credits_purchased", precision: 15, scale: 4, null: false
    t.decimal "discount_amount_usd", precision: 10, scale: 2, default: "0.0"
    t.decimal "discount_percentage", precision: 5, scale: 2, default: "0.0"
    t.datetime "expires_at"
    t.decimal "final_price_usd", precision: 10, scale: 2, null: false
    t.jsonb "metadata", default: {}
    t.datetime "paid_at"
    t.string "payment_method"
    t.string "payment_reference"
    t.integer "quantity", default: 1, null: false
    t.string "status", default: "pending", null: false
    t.decimal "total_credits", precision: 15, scale: 4, null: false
    t.decimal "total_price_usd", precision: 10, scale: 2, null: false
    t.decimal "unit_price_usd", precision: 10, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["account_id", "created_at"], name: "index_ai_credit_purchases_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_ai_credit_purchases_on_account_id"
    t.index ["credit_pack_id"], name: "index_ai_credit_purchases_on_credit_pack_id"
    t.index ["payment_reference"], name: "index_ai_credit_purchases_on_payment_reference"
    t.index ["status"], name: "index_ai_credit_purchases_on_status"
    t.index ["user_id"], name: "index_ai_credit_purchases_on_user_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'refunded'::character varying::text, 'partially_refunded'::character varying::text])", name: "check_credit_purchase_status"
  end

  create_table "ai_credit_transactions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_credit_id", null: false
    t.uuid "account_id", null: false
    t.decimal "amount", precision: 15, scale: 4, null: false
    t.decimal "balance_after", precision: 15, scale: 4, null: false
    t.decimal "balance_before", precision: 15, scale: 4, null: false
    t.datetime "created_at", null: false
    t.uuid "credit_pack_id"
    t.string "description"
    t.datetime "expires_at"
    t.string "external_reference"
    t.uuid "initiated_by_id"
    t.jsonb "metadata", default: {}
    t.datetime "processed_at"
    t.uuid "reference_id"
    t.string "reference_type"
    t.uuid "related_transaction_id"
    t.string "status", default: "completed", null: false
    t.string "transaction_type", null: false
    t.datetime "updated_at", null: false
    t.index ["account_credit_id"], name: "index_ai_credit_transactions_on_account_credit_id"
    t.index ["account_id", "created_at"], name: "index_ai_credit_transactions_on_account_id_and_created_at"
    t.index ["account_id", "transaction_type"], name: "idx_on_account_id_transaction_type_95c2c5d3e7"
    t.index ["account_id"], name: "index_ai_credit_transactions_on_account_id"
    t.index ["created_at"], name: "index_ai_credit_transactions_on_created_at"
    t.index ["credit_pack_id"], name: "index_ai_credit_transactions_on_credit_pack_id"
    t.index ["expires_at"], name: "index_ai_credit_transactions_on_expires_at"
    t.index ["initiated_by_id"], name: "index_ai_credit_transactions_on_initiated_by_id"
    t.index ["reference_type", "reference_id"], name: "idx_on_reference_type_reference_id_860e01290c"
    t.index ["related_transaction_id"], name: "index_ai_credit_transactions_on_related_transaction_id"
    t.index ["status"], name: "index_ai_credit_transactions_on_status"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'reversed'::character varying::text, 'expired'::character varying::text])", name: "check_credit_transaction_status"
    t.check_constraint "transaction_type::text = ANY (ARRAY['purchase'::character varying::text, 'usage'::character varying::text, 'refund'::character varying::text, 'transfer_in'::character varying::text, 'transfer_out'::character varying::text, 'bonus'::character varying::text, 'adjustment'::character varying::text, 'expiration'::character varying::text, 'reservation'::character varying::text, 'release'::character varying::text])", name: "check_credit_transaction_type"
  end

  create_table "ai_credit_transfers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "amount", precision: 15, scale: 4, null: false
    t.datetime "approved_at"
    t.uuid "approved_by_id"
    t.string "cancellation_reason"
    t.datetime "cancelled_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "description"
    t.decimal "fee_amount", precision: 15, scale: 4, default: "0.0"
    t.decimal "fee_percentage", precision: 5, scale: 2, default: "0.0"
    t.uuid "from_account_id", null: false
    t.uuid "from_transaction_id"
    t.uuid "initiated_by_id", null: false
    t.jsonb "metadata", default: {}
    t.decimal "net_amount", precision: 15, scale: 4, null: false
    t.string "reference_code", null: false
    t.string "status", default: "pending", null: false
    t.uuid "to_account_id", null: false
    t.uuid "to_transaction_id"
    t.datetime "updated_at", null: false
    t.index ["approved_by_id"], name: "index_ai_credit_transfers_on_approved_by_id"
    t.index ["from_account_id", "created_at"], name: "index_ai_credit_transfers_on_from_account_id_and_created_at"
    t.index ["from_account_id"], name: "index_ai_credit_transfers_on_from_account_id"
    t.index ["initiated_by_id"], name: "index_ai_credit_transfers_on_initiated_by_id"
    t.index ["reference_code"], name: "index_ai_credit_transfers_on_reference_code", unique: true
    t.index ["status"], name: "index_ai_credit_transfers_on_status"
    t.index ["to_account_id", "created_at"], name: "index_ai_credit_transfers_on_to_account_id_and_created_at"
    t.index ["to_account_id"], name: "index_ai_credit_transfers_on_to_account_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'approved'::character varying::text, 'completed'::character varying::text, 'rejected'::character varying::text, 'cancelled'::character varying::text, 'failed'::character varying::text])", name: "check_credit_transfer_status"
  end

  create_table "ai_credit_usage_rates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "base_credits", precision: 10, scale: 6, default: "0.0"
    t.datetime "created_at", null: false
    t.decimal "credits_per_1k_input_tokens", precision: 10, scale: 6
    t.decimal "credits_per_1k_output_tokens", precision: 10, scale: 6
    t.decimal "credits_per_gb_storage", precision: 10, scale: 6
    t.decimal "credits_per_minute", precision: 10, scale: 6
    t.decimal "credits_per_request", precision: 10, scale: 6
    t.datetime "effective_from", null: false
    t.datetime "effective_until"
    t.boolean "is_active", default: true, null: false
    t.jsonb "metadata", default: {}
    t.string "model_name"
    t.string "operation_type", null: false
    t.string "provider_type"
    t.datetime "updated_at", null: false
    t.index ["is_active", "effective_from"], name: "index_ai_credit_usage_rates_on_is_active_and_effective_from"
    t.index ["operation_type", "provider_type", "model_name"], name: "idx_credit_rates_operation_provider_model"
  end

  create_table "ai_dag_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.uuid "workflow_id"
    t.index ["account_id", "status"], name: "index_ai_dag_executions_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_dag_executions_on_account_id"
    t.index ["status"], name: "index_ai_dag_executions_on_status"
    t.index ["triggered_by_id"], name: "index_ai_dag_executions_on_triggered_by_id"
    t.index ["workflow_id"], name: "index_ai_dag_executions_on_workflow_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'running'::character varying, 'completed'::character varying, 'failed'::character varying, 'cancelled'::character varying]::text[])", name: "ai_dag_executions_status_check"
  end

  create_table "ai_data_classifications", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_data_connectors", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_data_detections", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_deployment_risks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_devops_template_installations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.uuid "created_workflow_id"
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
    t.index ["account_id", "devops_template_id"], name: "idx_devops_installations_account_template", unique: true
    t.index ["account_id"], name: "index_ai_devops_template_installations_on_account_id"
    t.index ["created_workflow_id"], name: "index_ai_devops_template_installations_on_created_workflow_id"
    t.index ["devops_template_id"], name: "index_ai_devops_template_installations_on_devops_template_id"
    t.index ["installed_by_id"], name: "index_ai_devops_template_installations_on_installed_by_id"
    t.index ["status"], name: "index_ai_devops_template_installations_on_status"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'paused'::character varying::text, 'disabled'::character varying::text, 'pending_update'::character varying::text])", name: "check_devops_installation_status"
  end

  create_table "ai_devops_templates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id"], name: "index_ai_devops_templates_on_account_id"
    t.index ["category"], name: "index_ai_devops_templates_on_category"
    t.index ["created_by_id"], name: "index_ai_devops_templates_on_created_by_id"
    t.index ["is_featured"], name: "index_ai_devops_templates_on_is_featured"
    t.index ["is_system"], name: "index_ai_devops_templates_on_is_system"
    t.index ["slug"], name: "index_ai_devops_templates_on_slug", unique: true
    t.index ["status", "visibility"], name: "index_ai_devops_templates_on_status_and_visibility"
    t.index ["template_type"], name: "index_ai_devops_templates_on_template_type"
    t.check_constraint "category::text = ANY (ARRAY['code_quality'::character varying::text, 'deployment'::character varying::text, 'documentation'::character varying::text, 'testing'::character varying::text, 'security'::character varying::text, 'monitoring'::character varying::text, 'release'::character varying::text, 'custom'::character varying::text])", name: "check_devops_category"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'pending_review'::character varying::text, 'published'::character varying::text, 'archived'::character varying::text, 'deprecated'::character varying::text])", name: "check_devops_status"
    t.check_constraint "template_type::text = ANY (ARRAY['code_review'::character varying::text, 'security_scan'::character varying::text, 'test_generation'::character varying::text, 'deployment_validation'::character varying::text, 'release_notes'::character varying::text, 'changelog'::character varying::text, 'api_docs'::character varying::text, 'coverage_analysis'::character varying::text, 'performance_check'::character varying::text, 'custom'::character varying::text])", name: "check_devops_template_type"
    t.check_constraint "visibility::text = ANY (ARRAY['private'::character varying::text, 'team'::character varying::text, 'public'::character varying::text, 'marketplace'::character varying::text])", name: "check_devops_visibility"
  end

  create_table "ai_discovery_results", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_document_chunks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_documents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_encrypted_messages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_evaluation_results", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_execution_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_execution_trace_spans", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_execution_traces", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_file_locks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["worktree_session_id", "file_path"], name: "idx_ai_file_locks_session_file", unique: true
    t.index ["worktree_session_id"], name: "index_ai_file_locks_on_worktree_session_id"
  end

  create_table "ai_guardrail_configs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_hybrid_search_results", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.check_constraint "search_mode::text = ANY (ARRAY['vector'::character varying, 'keyword'::character varying, 'hybrid'::character varying, 'graph'::character varying]::text[])", name: "check_ai_hybrid_search_mode"
  end

  create_table "ai_improvement_recommendations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_knowledge_bases", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "name"], name: "index_ai_knowledge_bases_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_ai_knowledge_bases_on_account_id"
    t.index ["created_by_id"], name: "index_ai_knowledge_bases_on_created_by_id"
    t.index ["is_public"], name: "index_ai_knowledge_bases_on_is_public"
    t.index ["status"], name: "index_ai_knowledge_bases_on_status"
    t.check_constraint "chunking_strategy::text = ANY (ARRAY['recursive'::character varying::text, 'semantic'::character varying::text, 'fixed'::character varying::text, 'sentence'::character varying::text, 'paragraph'::character varying::text, 'custom'::character varying::text])", name: "check_kb_chunking_strategy"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'indexing'::character varying::text, 'paused'::character varying::text, 'archived'::character varying::text, 'error'::character varying::text])", name: "check_kb_status"
  end

  create_table "ai_knowledge_graph_edges", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["source_node_id", "target_node_id", "relation_type"], name: "index_ai_kg_edges_unique_active", unique: true, where: "((status)::text = 'active'::text)"
    t.index ["source_node_id"], name: "index_ai_knowledge_graph_edges_on_source_node_id"
    t.index ["target_node_id"], name: "index_ai_knowledge_graph_edges_on_target_node_id"
  end

  create_table "ai_knowledge_graph_nodes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.decimal "confidence", precision: 5, scale: 4, default: "1.0"
    t.datetime "created_at", null: false
    t.text "description"
    t.vector "embedding", limit: 1536
    t.string "entity_type"
    t.uuid "knowledge_base_id"
    t.datetime "last_seen_at"
    t.integer "mention_count", default: 1
    t.uuid "merged_into_id"
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.string "node_type", null: false
    t.ltree "path"
    t.jsonb "properties", default: {}
    t.uuid "source_document_id"
    t.string "status", default: "active"
    t.datetime "updated_at", null: false
    t.index ["account_id", "name", "node_type"], name: "index_ai_kg_nodes_unique_active", unique: true, where: "((status)::text = 'active'::text)"
    t.index ["account_id"], name: "index_ai_knowledge_graph_nodes_on_account_id"
    t.index ["embedding"], name: "index_ai_knowledge_graph_nodes_on_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["entity_type"], name: "index_ai_knowledge_graph_nodes_on_entity_type"
    t.index ["knowledge_base_id"], name: "index_ai_knowledge_graph_nodes_on_knowledge_base_id"
    t.index ["name"], name: "index_ai_kg_nodes_on_name"
    t.index ["node_type"], name: "index_ai_knowledge_graph_nodes_on_node_type"
    t.index ["path"], name: "index_ai_knowledge_graph_nodes_on_path", using: :gist
    t.index ["status"], name: "index_ai_knowledge_graph_nodes_on_status"
    t.check_constraint "node_type::text = ANY (ARRAY['entity'::character varying, 'concept'::character varying, 'relation'::character varying, 'attribute'::character varying]::text[])", name: "check_ai_kg_node_type"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'merged'::character varying, 'archived'::character varying]::text[])", name: "check_ai_kg_node_status"
  end

  create_table "ai_marketplace_categories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "display_order", default: 0
    t.string "icon"
    t.boolean "is_active", default: true, null: false
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.uuid "parent_id"
    t.string "slug", null: false
    t.integer "template_count", default: 0
    t.datetime "updated_at", null: false
    t.index ["is_active"], name: "index_ai_marketplace_categories_on_is_active"
    t.index ["parent_id", "display_order"], name: "index_ai_marketplace_categories_on_parent_id_and_display_order"
    t.index ["parent_id"], name: "index_ai_marketplace_categories_on_parent_id"
    t.index ["slug"], name: "index_ai_marketplace_categories_on_slug", unique: true
  end

  create_table "ai_marketplace_moderations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "agent_template_id", null: false
    t.jsonb "automated_check_results", default: {}
    t.datetime "automated_checks_at"
    t.jsonb "changes_summary", default: {}
    t.datetime "created_at", null: false
    t.boolean "passed_automated_checks", default: false, null: false
    t.string "rejection_reason"
    t.text "review_notes"
    t.string "review_type", default: "initial", null: false
    t.datetime "reviewed_at"
    t.uuid "reviewed_by_id"
    t.integer "revision_number", default: 1, null: false
    t.string "status", default: "pending", null: false
    t.text "submission_notes"
    t.datetime "submitted_at", null: false
    t.uuid "submitted_by_id", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_template_id", "status"], name: "idx_on_agent_template_id_status_5550f53f8c"
    t.index ["agent_template_id"], name: "index_ai_marketplace_moderations_on_agent_template_id"
    t.index ["reviewed_by_id"], name: "index_ai_marketplace_moderations_on_reviewed_by_id"
    t.index ["status"], name: "index_ai_marketplace_moderations_on_status"
    t.index ["submitted_at"], name: "index_ai_marketplace_moderations_on_submitted_at"
    t.index ["submitted_by_id"], name: "index_ai_marketplace_moderations_on_submitted_by_id"
    t.check_constraint "review_type::text = ANY (ARRAY['initial'::character varying::text, 'update'::character varying::text, 'reinstatement'::character varying::text, 'appeal'::character varying::text])", name: "check_review_type"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'in_review'::character varying::text, 'approved'::character varying::text, 'rejected'::character varying::text, 'revision_requested'::character varying::text])", name: "check_moderation_status"
  end

  create_table "ai_marketplace_purchases", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "agent_template_id", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.decimal "discount_amount", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "final_price", precision: 15, scale: 2, null: false
    t.uuid "installation_id"
    t.boolean "is_refunded", default: false, null: false
    t.jsonb "metadata", default: {}
    t.datetime "paid_at"
    t.string "payment_method"
    t.string "payment_reference"
    t.decimal "price", precision: 15, scale: 2, null: false
    t.string "purchase_type", default: "one_time", null: false
    t.decimal "refund_amount", precision: 15, scale: 2
    t.text "refund_reason"
    t.datetime "refunded_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["account_id", "agent_template_id"], name: "idx_on_account_id_agent_template_id_a3a7719c31"
    t.index ["account_id"], name: "index_ai_marketplace_purchases_on_account_id"
    t.index ["agent_template_id"], name: "index_ai_marketplace_purchases_on_agent_template_id"
    t.index ["created_at"], name: "index_ai_marketplace_purchases_on_created_at"
    t.index ["installation_id"], name: "index_ai_marketplace_purchases_on_installation_id"
    t.index ["status"], name: "index_ai_marketplace_purchases_on_status"
    t.index ["user_id"], name: "index_ai_marketplace_purchases_on_user_id"
    t.check_constraint "purchase_type::text = ANY (ARRAY['one_time'::character varying::text, 'subscription'::character varying::text, 'credit'::character varying::text, 'upgrade'::character varying::text])", name: "check_purchase_type"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'refunded'::character varying::text, 'cancelled'::character varying::text])", name: "check_purchase_status"
  end

  create_table "ai_marketplace_transactions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "agent_template_id", null: false
    t.decimal "commission_amount_usd", precision: 10, scale: 2, null: false
    t.integer "commission_percentage", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.decimal "gross_amount_usd", precision: 10, scale: 2, null: false
    t.uuid "installation_id"
    t.jsonb "metadata", default: {}
    t.string "payment_reference"
    t.decimal "publisher_amount_usd", precision: 10, scale: 2, null: false
    t.uuid "publisher_id", null: false
    t.string "status", default: "pending", null: false
    t.string "transaction_type", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"], name: "index_ai_marketplace_transactions_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_ai_marketplace_transactions_on_account_id"
    t.index ["agent_template_id"], name: "index_ai_marketplace_transactions_on_agent_template_id"
    t.index ["installation_id"], name: "index_ai_marketplace_transactions_on_installation_id"
    t.index ["publisher_id", "status"], name: "index_ai_marketplace_transactions_on_publisher_id_and_status"
    t.index ["publisher_id"], name: "index_ai_marketplace_transactions_on_publisher_id"
    t.index ["status"], name: "index_ai_marketplace_transactions_on_status"
    t.index ["transaction_type"], name: "index_ai_marketplace_transactions_on_transaction_type"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'refunded'::character varying::text, 'disputed'::character varying::text])", name: "check_transaction_status"
    t.check_constraint "transaction_type::text = ANY (ARRAY['purchase'::character varying::text, 'subscription'::character varying::text, 'renewal'::character varying::text, 'refund'::character varying::text, 'payout'::character varying::text])", name: "check_transaction_type"
  end

  create_table "ai_mcp_app_instances", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_mcp_apps", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_memory_pools", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_merge_operations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_messages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_agent_id", null: false
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

  create_table "ai_mission_approvals", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_missions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.string "deployed_container_id"
    t.integer "deployed_port"
    t.string "deployed_url"
    t.text "description"
    t.integer "duration_ms"
    t.jsonb "error_details", default: {}
    t.text "error_message"
    t.jsonb "feature_suggestions", default: []
    t.jsonb "metadata", default: {}
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
    t.index ["deployed_port"], name: "index_ai_missions_on_deployed_port", unique: true, where: "(((status)::text = 'active'::text) AND (deployed_port IS NOT NULL))"
    t.index ["ralph_loop_id"], name: "index_ai_missions_on_ralph_loop_id"
    t.index ["repository_id"], name: "index_ai_missions_on_repository_id"
    t.index ["review_state_id"], name: "index_ai_missions_on_review_state_id"
    t.index ["risk_contract_id"], name: "index_ai_missions_on_risk_contract_id"
    t.index ["team_id"], name: "index_ai_missions_on_team_id"
  end

  create_table "ai_mock_responses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_model_routing_rules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "is_active", "priority"], name: "idx_routing_rules_account_active_priority"
    t.index ["account_id", "rule_type"], name: "index_ai_model_routing_rules_on_account_id_and_rule_type"
    t.index ["account_id"], name: "index_ai_model_routing_rules_on_account_id"
    t.index ["conditions"], name: "index_ai_model_routing_rules_on_conditions", using: :gin
    t.check_constraint "rule_type::text = ANY (ARRAY['capability_based'::character varying::text, 'cost_based'::character varying::text, 'latency_based'::character varying::text, 'quality_based'::character varying::text, 'custom'::character varying::text, 'ml_optimized'::character varying::text])", name: "check_routing_rule_type"
  end

  create_table "ai_outcome_billing_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.decimal "base_charge_usd", precision: 10, scale: 4
    t.datetime "billed_at"
    t.datetime "completed_at"
    t.boolean "counted_for_sla", default: true, null: false
    t.datetime "created_at", null: false
    t.decimal "discount_usd", precision: 10, scale: 4, default: "0.0"
    t.integer "duration_ms"
    t.text "failure_reason"
    t.decimal "final_charge_usd", precision: 10, scale: 4
    t.uuid "invoice_line_item_id"
    t.boolean "is_billable", default: true, null: false
    t.boolean "is_billed", default: false, null: false
    t.boolean "is_successful"
    t.boolean "met_sla_criteria"
    t.jsonb "metadata", default: {}
    t.uuid "outcome_definition_id", null: false
    t.decimal "quality_score", precision: 5, scale: 4
    t.integer "retry_count", default: 0
    t.uuid "sla_contract_id"
    t.uuid "source_id", null: false
    t.string "source_name"
    t.string "source_type", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.decimal "time_charge_usd", precision: 10, scale: 4
    t.decimal "token_charge_usd", precision: 10, scale: 4
    t.integer "tokens_used"
    t.datetime "updated_at", null: false
    t.datetime "validated_at"
    t.uuid "validated_by_id"
    t.index ["account_id", "created_at"], name: "index_ai_outcome_billing_records_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_ai_outcome_billing_records_on_account_id"
    t.index ["created_at"], name: "index_ai_outcome_billing_records_on_created_at"
    t.index ["is_billable", "is_billed"], name: "index_ai_outcome_billing_records_on_is_billable_and_is_billed"
    t.index ["outcome_definition_id", "created_at"], name: "idx_on_outcome_definition_id_created_at_7e6df8dcb9"
    t.index ["outcome_definition_id"], name: "index_ai_outcome_billing_records_on_outcome_definition_id"
    t.index ["sla_contract_id"], name: "index_ai_outcome_billing_records_on_sla_contract_id"
    t.index ["source_type", "source_id"], name: "index_ai_outcome_billing_records_on_source_type_and_source_id"
    t.index ["status"], name: "index_ai_outcome_billing_records_on_status"
    t.index ["validated_by_id"], name: "index_ai_outcome_billing_records_on_validated_by_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'successful'::character varying::text, 'failed'::character varying::text, 'timeout'::character varying::text, 'cancelled'::character varying::text, 'refunded'::character varying::text])", name: "check_outcome_billing_status"
  end

  create_table "ai_outcome_definitions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.decimal "base_price_usd", precision: 10, scale: 4, null: false
    t.string "category"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "effective_from"
    t.datetime "effective_until"
    t.integer "free_tier_count", default: 0
    t.boolean "is_active", default: true, null: false
    t.boolean "is_system", default: false, null: false
    t.decimal "max_charge_usd", precision: 10, scale: 4
    t.jsonb "metadata", default: {}
    t.decimal "min_charge_usd", precision: 10, scale: 4
    t.string "name", null: false
    t.string "outcome_type", null: false
    t.decimal "price_per_minute", precision: 10, scale: 4
    t.decimal "price_per_token", precision: 15, scale: 10
    t.decimal "quality_threshold", precision: 5, scale: 4
    t.decimal "sla_credit_percentage", precision: 5, scale: 2
    t.boolean "sla_enabled", default: false, null: false
    t.integer "sla_measurement_window_hours", default: 720
    t.decimal "sla_target_percentage", precision: 6, scale: 4
    t.jsonb "success_criteria", default: {}, null: false
    t.integer "timeout_seconds", default: 300
    t.datetime "updated_at", null: false
    t.string "validation_method", default: "automatic", null: false
    t.jsonb "volume_tiers", default: []
    t.index ["account_id", "is_active"], name: "index_ai_outcome_definitions_on_account_id_and_is_active"
    t.index ["account_id", "outcome_type"], name: "index_ai_outcome_definitions_on_account_id_and_outcome_type"
    t.index ["account_id"], name: "index_ai_outcome_definitions_on_account_id"
    t.index ["is_system"], name: "index_ai_outcome_definitions_on_is_system"
    t.index ["outcome_type"], name: "index_ai_outcome_definitions_on_outcome_type"
    t.check_constraint "outcome_type::text = ANY (ARRAY['task_completion'::character varying::text, 'quality_threshold'::character varying::text, 'classification'::character varying::text, 'extraction'::character varying::text, 'generation'::character varying::text, 'conversation'::character varying::text, 'workflow'::character varying::text, 'custom'::character varying::text])", name: "check_outcome_type"
    t.check_constraint "validation_method::text = ANY (ARRAY['automatic'::character varying::text, 'human_review'::character varying::text, 'hybrid'::character varying::text, 'api_callback'::character varying::text])", name: "check_validation_method"
  end

  create_table "ai_performance_benchmarks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.uuid "target_workflow_id"
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
    t.index ["target_workflow_id"], name: "index_ai_performance_benchmarks_on_target_workflow_id"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'paused'::character varying::text, 'archived'::character varying::text])", name: "check_benchmark_status"
  end

  create_table "ai_persistent_contexts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "ai_agent_id"], name: "idx_contexts_account_agent"
    t.index ["account_id", "context_type"], name: "idx_contexts_account_type"
    t.index ["account_id"], name: "index_ai_persistent_contexts_on_account_id"
    t.index ["ai_agent_id"], name: "index_ai_persistent_contexts_on_ai_agent_id"
    t.index ["archived_at"], name: "index_ai_persistent_contexts_on_archived_at"
    t.index ["context_id"], name: "index_ai_persistent_contexts_on_context_id", unique: true
    t.index ["context_type"], name: "index_ai_persistent_contexts_on_context_type"
    t.index ["created_by_user_id"], name: "index_ai_persistent_contexts_on_created_by_user_id"
    t.index ["expires_at"], name: "index_ai_persistent_contexts_on_expires_at"
    t.index ["scope"], name: "index_ai_persistent_contexts_on_scope"
  end

  create_table "ai_pipeline_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.uuid "workflow_run_id"
    t.index ["account_id", "status"], name: "index_ai_pipeline_executions_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_pipeline_executions_on_account_id"
    t.index ["devops_installation_id"], name: "index_ai_pipeline_executions_on_devops_installation_id"
    t.index ["execution_id"], name: "index_ai_pipeline_executions_on_execution_id", unique: true
    t.index ["pipeline_type"], name: "index_ai_pipeline_executions_on_pipeline_type"
    t.index ["repository_id", "created_at"], name: "index_ai_pipeline_executions_on_repository_id_and_created_at"
    t.index ["trigger_source"], name: "index_ai_pipeline_executions_on_trigger_source"
    t.index ["triggered_by_id"], name: "index_ai_pipeline_executions_on_triggered_by_id"
    t.index ["workflow_run_id"], name: "index_ai_pipeline_executions_on_workflow_run_id"
    t.check_constraint "pipeline_type::text = ANY (ARRAY['pr_review'::character varying::text, 'commit_analysis'::character varying::text, 'deployment'::character varying::text, 'release'::character varying::text, 'scheduled'::character varying::text, 'manual'::character varying::text])", name: "check_pipeline_type"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text, 'timeout'::character varying::text])", name: "check_pipeline_status"
  end

  create_table "ai_policy_violations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_provider_credentials", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_provider_metrics", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "recorded_at"], name: "idx_provider_metrics_account_time"
    t.index ["account_id"], name: "index_ai_provider_metrics_on_account_id"
    t.index ["granularity", "recorded_at"], name: "index_ai_provider_metrics_on_granularity_and_recorded_at"
    t.index ["provider_id", "recorded_at"], name: "idx_provider_metrics_provider_time"
    t.index ["provider_id"], name: "index_ai_provider_metrics_on_provider_id"
    t.index ["recorded_at"], name: "index_ai_provider_metrics_on_recorded_at"
    t.check_constraint "granularity::text = ANY (ARRAY['minute'::character varying::text, 'hour'::character varying::text, 'day'::character varying::text, 'week'::character varying::text, 'month'::character varying::text])", name: "check_metric_granularity"
  end

  create_table "ai_providers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_publisher_accounts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.float "average_rating"
    t.jsonb "branding", default: {}
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "last_payout_at"
    t.decimal "lifetime_earnings_usd", precision: 12, scale: 2, default: "0.0"
    t.jsonb "payout_settings", default: {}
    t.decimal "pending_payout_usd", precision: 12, scale: 2, default: "0.0"
    t.uuid "primary_user_id"
    t.string "publisher_name", null: false
    t.string "publisher_slug", null: false
    t.integer "revenue_share_percentage", default: 70
    t.string "status", default: "pending", null: false
    t.string "stripe_account_id"
    t.string "stripe_account_status", default: "pending"
    t.boolean "stripe_onboarding_completed", default: false
    t.boolean "stripe_payout_enabled", default: false
    t.string "support_email"
    t.integer "total_installations", default: 0
    t.integer "total_templates", default: 0
    t.datetime "updated_at", null: false
    t.string "verification_status", default: "unverified", null: false
    t.datetime "verified_at"
    t.string "website_url"
    t.index ["account_id"], name: "index_ai_publisher_accounts_on_account_id", unique: true
    t.index ["primary_user_id"], name: "index_ai_publisher_accounts_on_primary_user_id"
    t.index ["publisher_slug"], name: "index_ai_publisher_accounts_on_publisher_slug", unique: true
    t.index ["status"], name: "index_ai_publisher_accounts_on_status"
    t.index ["stripe_account_id"], name: "index_ai_publisher_accounts_on_stripe_account_id", unique: true
    t.index ["verification_status"], name: "index_ai_publisher_accounts_on_verification_status"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'active'::character varying::text, 'suspended'::character varying::text, 'terminated'::character varying::text])", name: "check_publisher_status"
    t.check_constraint "verification_status::text = ANY (ARRAY['unverified'::character varying::text, 'pending'::character varying::text, 'verified'::character varying::text, 'rejected'::character varying::text])", name: "check_verification_status"
  end

  create_table "ai_publisher_earnings_snapshots", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "active_templates", default: 0, null: false
    t.decimal "average_rating", precision: 3, scale: 2
    t.datetime "created_at", null: false
    t.decimal "gross_earnings", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "net_earnings", precision: 15, scale: 2, default: "0.0", null: false
    t.integer "new_customers", default: 0, null: false
    t.decimal "paid_out", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "pending_payout", precision: 15, scale: 2, default: "0.0", null: false
    t.uuid "publisher_id", null: false
    t.integer "returning_customers", default: 0, null: false
    t.date "snapshot_date", null: false
    t.integer "total_sales", default: 0, null: false
    t.integer "total_templates", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["publisher_id", "snapshot_date"], name: "idx_publisher_earnings_date", unique: true
    t.index ["publisher_id"], name: "index_ai_publisher_earnings_snapshots_on_publisher_id"
    t.index ["snapshot_date"], name: "index_ai_publisher_earnings_snapshots_on_snapshot_date"
  end

  create_table "ai_quarantine_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_rag_queries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.uuid "workflow_run_id"
    t.index ["account_id", "created_at"], name: "index_ai_rag_queries_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_ai_rag_queries_on_account_id"
    t.index ["knowledge_base_id", "created_at"], name: "index_ai_rag_queries_on_knowledge_base_id_and_created_at"
    t.index ["knowledge_base_id"], name: "index_ai_rag_queries_on_knowledge_base_id"
    t.index ["query_embedding"], name: "idx_rag_queries_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["status"], name: "index_ai_rag_queries_on_status"
    t.index ["user_id"], name: "index_ai_rag_queries_on_user_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "check_rag_query_status"
  end

  create_table "ai_ralph_iterations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'running'::character varying, 'completed'::character varying, 'failed'::character varying, 'skipped'::character varying]::text[])", name: "ai_ralph_iterations_status_check"
  end

  create_table "ai_ralph_loops", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["created_at"], name: "index_ai_ralph_loops_on_created_at"
    t.index ["default_agent_id"], name: "index_ai_ralph_loops_on_default_agent_id"
    t.index ["mission_id"], name: "index_ai_ralph_loops_on_mission_id"
    t.index ["next_scheduled_at"], name: "index_ai_ralph_loops_on_next_scheduled_at"
    t.index ["risk_contract_id"], name: "index_ai_ralph_loops_on_risk_contract_id"
    t.index ["schedule_paused", "next_scheduled_at"], name: "index_ralph_loops_on_schedule_state"
    t.index ["scheduling_mode"], name: "index_ai_ralph_loops_on_scheduling_mode"
    t.index ["status"], name: "index_ai_ralph_loops_on_status"
    t.index ["webhook_token"], name: "index_ai_ralph_loops_on_webhook_token", unique: true, where: "(webhook_token IS NOT NULL)"
    t.check_constraint "ai_tool::text = ANY (ARRAY['amp'::character varying, 'claude_code'::character varying, 'ollama'::character varying]::text[])", name: "ai_ralph_loops_ai_tool_check"
    t.check_constraint "scheduling_mode::text = ANY (ARRAY['manual'::character varying, 'scheduled'::character varying, 'continuous'::character varying, 'event_triggered'::character varying]::text[])", name: "ai_ralph_loops_scheduling_mode_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'running'::character varying, 'paused'::character varying, 'completed'::character varying, 'failed'::character varying, 'cancelled'::character varying]::text[])", name: "ai_ralph_loops_status_check"
  end

  create_table "ai_ralph_tasks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.jsonb "required_capabilities", default: []
    t.string "status", default: "pending", null: false
    t.string "task_key", null: false
    t.datetime "updated_at", null: false
    t.index ["capability_match_strategy"], name: "index_ai_ralph_tasks_on_capability_match_strategy"
    t.index ["execution_type"], name: "index_ai_ralph_tasks_on_execution_type"
    t.index ["executor_type", "executor_id"], name: "index_ai_ralph_tasks_on_executor"
    t.index ["executor_type", "executor_id"], name: "index_ai_ralph_tasks_on_executor_type_and_executor_id"
    t.index ["last_executor_type", "last_executor_id"], name: "index_ai_ralph_tasks_on_last_executor"
    t.index ["priority"], name: "index_ai_ralph_tasks_on_priority"
    t.index ["ralph_loop_id", "task_key"], name: "index_ai_ralph_tasks_on_ralph_loop_id_and_task_key", unique: true
    t.index ["ralph_loop_id"], name: "index_ai_ralph_tasks_on_ralph_loop_id"
    t.index ["required_capabilities"], name: "index_ai_ralph_tasks_on_required_capabilities", using: :gin
    t.index ["status"], name: "index_ai_ralph_tasks_on_status"
    t.check_constraint "capability_match_strategy::text = ANY (ARRAY['all'::character varying, 'any'::character varying, 'weighted'::character varying]::text[])", name: "ai_ralph_tasks_capability_match_strategy_check"
    t.check_constraint "execution_type::text = ANY (ARRAY['agent'::character varying, 'workflow'::character varying, 'pipeline'::character varying, 'a2a_task'::character varying, 'container'::character varying, 'human'::character varying, 'community'::character varying]::text[])", name: "ai_ralph_tasks_execution_type_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'in_progress'::character varying, 'passed'::character varying, 'failed'::character varying, 'blocked'::character varying, 'skipped'::character varying]::text[])", name: "ai_ralph_tasks_status_check"
  end

  create_table "ai_recorded_interactions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.uuid "source_workflow_run_id"
    t.integer "tokens_input", default: 0
    t.integer "tokens_output", default: 0
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_ai_recorded_interactions_on_account_id"
    t.index ["interaction_type"], name: "index_ai_recorded_interactions_on_interaction_type"
    t.index ["recording_id"], name: "index_ai_recorded_interactions_on_recording_id", unique: true
    t.index ["sandbox_id", "recorded_at"], name: "index_ai_recorded_interactions_on_sandbox_id_and_recorded_at"
    t.index ["sandbox_id"], name: "index_ai_recorded_interactions_on_sandbox_id"
    t.index ["source_workflow_run_id"], name: "index_ai_recorded_interactions_on_source_workflow_run_id"
    t.check_constraint "interaction_type::text = ANY (ARRAY['llm_request'::character varying::text, 'tool_call'::character varying::text, 'api_call'::character varying::text, 'workflow_step'::character varying::text, 'agent_action'::character varying::text])", name: "check_interaction_type"
  end

  create_table "ai_remediation_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_roi_metrics", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "metric_type", "period_date"], name: "idx_roi_metrics_account_type_date"
    t.index ["account_id", "period_type", "period_date"], name: "idx_roi_metrics_account_period"
    t.index ["account_id"], name: "index_ai_roi_metrics_on_account_id"
    t.index ["attributable_type", "attributable_id"], name: "idx_roi_metrics_attributable"
    t.index ["period_date"], name: "index_ai_roi_metrics_on_period_date"
    t.check_constraint "metric_type::text = ANY (ARRAY['workflow'::character varying::text, 'agent'::character varying::text, 'provider'::character varying::text, 'team'::character varying::text, 'account_total'::character varying::text, 'department'::character varying::text])", name: "check_roi_metric_type"
    t.check_constraint "period_type::text = ANY (ARRAY['daily'::character varying::text, 'weekly'::character varying::text, 'monthly'::character varying::text, 'quarterly'::character varying::text, 'yearly'::character varying::text])", name: "check_roi_period_type"
  end

  create_table "ai_role_profiles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_routing_decisions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.uuid "workflow_run_id"
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
    t.index ["workflow_run_id"], name: "index_ai_routing_decisions_on_workflow_run_id"
  end

  create_table "ai_runner_dispatches", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_sandboxes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_scheduled_messages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "status"], name: "index_ai_scheduled_messages_on_account_and_status"
    t.index ["account_id"], name: "index_ai_scheduled_messages_on_account_id"
    t.index ["conversation_id"], name: "index_ai_scheduled_messages_on_conversation_id"
    t.index ["status", "next_scheduled_at"], name: "index_ai_scheduled_messages_on_status_and_next_at"
    t.index ["user_id"], name: "index_ai_scheduled_messages_on_user_id"
  end

  create_table "ai_security_audit_trails", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_shared_context_pools", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "access_control", default: {}
    t.uuid "ai_workflow_run_id", null: false
    t.jsonb "context_data", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "created_by_agent_id"
    t.datetime "expires_at", precision: nil
    t.datetime "last_accessed_at", precision: nil
    t.jsonb "metadata", default: {}
    t.string "owner_agent_id"
    t.string "pool_id", null: false
    t.string "pool_type", default: "shared_memory", null: false
    t.string "scope", default: "workflow", null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.index ["ai_workflow_run_id", "pool_type"], name: "index_context_pools_on_run_and_type"
    t.index ["ai_workflow_run_id", "scope"], name: "index_context_pools_on_run_and_scope"
    t.index ["ai_workflow_run_id"], name: "index_ai_shared_context_pools_on_ai_workflow_run_id"
    t.index ["owner_agent_id"], name: "index_ai_shared_context_pools_on_owner_agent_id"
    t.index ["pool_id"], name: "index_ai_shared_context_pools_on_pool_id", unique: true
    t.index ["pool_type"], name: "index_ai_shared_context_pools_on_pool_type"
    t.index ["scope"], name: "index_ai_shared_context_pools_on_scope"
  end

  create_table "ai_shared_knowledges", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "access_level", default: "team"
    t.uuid "account_id", null: false
    t.text "content", null: false
    t.string "content_type", default: "text"
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.vector "embedding", limit: 1536
    t.string "integrity_hash"
    t.datetime "last_used_at"
    t.jsonb "provenance", default: {}
    t.decimal "quality_score", precision: 5, scale: 4
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
    t.index ["source_type", "source_id"], name: "index_ai_shared_knowledges_on_source_type_and_source_id"
    t.index ["tags"], name: "index_ai_shared_knowledges_on_tags", using: :gin
  end

  create_table "ai_skills", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.jsonb "activation_rules", default: {}
    t.uuid "ai_knowledge_base_id"
    t.string "category", null: false
    t.jsonb "commands", default: []
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "is_enabled", default: true, null: false
    t.boolean "is_system", default: false, null: false
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.string "slug", null: false
    t.string "status", default: "active"
    t.text "system_prompt"
    t.jsonb "tags", default: []
    t.datetime "updated_at", null: false
    t.integer "usage_count", default: 0, null: false
    t.string "version", default: "1.0.0"
    t.index ["account_id"], name: "index_ai_skills_on_account_id"
    t.index ["ai_knowledge_base_id"], name: "index_ai_skills_on_ai_knowledge_base_id"
    t.index ["category"], name: "index_ai_skills_on_category"
    t.index ["is_system"], name: "index_ai_skills_on_is_system"
    t.index ["slug"], name: "index_ai_skills_on_slug", unique: true
    t.index ["status"], name: "index_ai_skills_on_status"
    t.index ["tags"], name: "index_ai_skills_on_tags", using: :gin
  end

  create_table "ai_skills_mcp_servers", id: false, force: :cascade do |t|
    t.uuid "ai_skill_id", null: false
    t.uuid "mcp_server_id", null: false
    t.index ["ai_skill_id", "mcp_server_id"], name: "idx_skills_mcp_servers_unique", unique: true
    t.index ["mcp_server_id"], name: "idx_skills_mcp_servers_on_mcp_server"
  end

  create_table "ai_sla_contracts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "activated_at"
    t.decimal "availability_target", precision: 6, scale: 4
    t.decimal "breach_credit_percentage", precision: 5, scale: 2, null: false
    t.datetime "cancelled_at"
    t.string "contract_type", default: "standard", null: false
    t.datetime "created_at", null: false
    t.boolean "current_period_breached", default: false
    t.datetime "current_period_end"
    t.datetime "current_period_start"
    t.integer "current_period_successful", default: 0
    t.integer "current_period_total", default: 0
    t.decimal "current_success_rate", precision: 6, scale: 4
    t.datetime "expires_at"
    t.decimal "latency_p95_target_ms", precision: 10, scale: 2
    t.decimal "max_monthly_credit_percentage", precision: 5, scale: 2, default: "100.0"
    t.integer "measurement_window_hours", default: 720, null: false
    t.jsonb "metadata", default: {}
    t.decimal "monthly_commitment_usd", precision: 10, scale: 2
    t.string "name", null: false
    t.uuid "outcome_definition_id"
    t.decimal "price_multiplier", precision: 5, scale: 2, default: "1.0"
    t.string "status", default: "active", null: false
    t.decimal "success_rate_target", precision: 6, scale: 4, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_ai_sla_contracts_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_sla_contracts_on_account_id"
    t.index ["current_period_end"], name: "index_ai_sla_contracts_on_current_period_end"
    t.index ["outcome_definition_id"], name: "index_ai_sla_contracts_on_outcome_definition_id"
    t.index ["status"], name: "index_ai_sla_contracts_on_status"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'pending_approval'::character varying::text, 'active'::character varying::text, 'suspended'::character varying::text, 'expired'::character varying::text, 'cancelled'::character varying::text])", name: "check_sla_contract_status"
  end

  create_table "ai_sla_violations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.decimal "actual_value", precision: 10, scale: 4, null: false
    t.integer "affected_outcomes_count"
    t.datetime "created_at", null: false
    t.decimal "credit_amount_usd", precision: 10, scale: 2, null: false
    t.datetime "credit_applied_at"
    t.decimal "credit_percentage", precision: 5, scale: 2, null: false
    t.string "credit_status", default: "pending", null: false
    t.uuid "credit_transaction_id"
    t.text "description"
    t.decimal "deviation_percentage", precision: 10, scale: 4
    t.jsonb "metadata", default: {}
    t.datetime "period_end", null: false
    t.datetime "period_start", null: false
    t.string "severity", default: "minor", null: false
    t.uuid "sla_contract_id", null: false
    t.decimal "target_value", precision: 10, scale: 4, null: false
    t.datetime "updated_at", null: false
    t.string "violation_type", null: false
    t.index ["account_id", "created_at"], name: "index_ai_sla_violations_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_ai_sla_violations_on_account_id"
    t.index ["credit_status"], name: "index_ai_sla_violations_on_credit_status"
    t.index ["sla_contract_id", "period_start"], name: "index_ai_sla_violations_on_sla_contract_id_and_period_start"
    t.index ["sla_contract_id"], name: "index_ai_sla_violations_on_sla_contract_id"
    t.index ["violation_type"], name: "index_ai_sla_violations_on_violation_type"
    t.check_constraint "credit_status::text = ANY (ARRAY['pending'::character varying::text, 'approved'::character varying::text, 'applied'::character varying::text, 'rejected'::character varying::text, 'waived'::character varying::text])", name: "check_sla_credit_status"
    t.check_constraint "violation_type::text = ANY (ARRAY['success_rate'::character varying::text, 'latency'::character varying::text, 'availability'::character varying::text, 'quality'::character varying::text])", name: "check_sla_violation_type"
  end

  create_table "ai_task_complexity_assessments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.check_constraint "complexity_level::text = ANY (ARRAY['trivial'::character varying, 'simple'::character varying, 'moderate'::character varying, 'complex'::character varying, 'expert'::character varying]::text[])", name: "chk_ai_task_complexity_level"
    t.check_constraint "recommended_tier::text = ANY (ARRAY['economy'::character varying, 'standard'::character varying, 'premium'::character varying]::text[])", name: "chk_ai_task_recommended_tier"
  end

  create_table "ai_task_reviews", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["team_task_id", "status"], name: "idx_task_reviews_on_task_and_status"
    t.index ["team_task_id"], name: "index_ai_task_reviews_on_team_task_id"
  end

  create_table "ai_team_channels", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_team_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.uuid "workflow_run_id"
    t.index ["account_id", "status"], name: "index_ai_team_executions_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_team_executions_on_account_id"
    t.index ["agent_team_id", "created_at"], name: "index_ai_team_executions_on_agent_team_id_and_created_at"
    t.index ["agent_team_id"], name: "index_ai_team_executions_on_agent_team_id"
    t.index ["ai_conversation_id"], name: "index_ai_team_executions_on_ai_conversation_id"
    t.index ["control_signal"], name: "index_ai_team_executions_on_control_signal"
    t.index ["execution_id"], name: "index_ai_team_executions_on_execution_id", unique: true
    t.index ["started_at"], name: "index_ai_team_executions_on_started_at"
    t.index ["triggered_by_id"], name: "index_ai_team_executions_on_triggered_by_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'running'::character varying, 'paused'::character varying, 'completed'::character varying, 'failed'::character varying, 'cancelled'::character varying, 'timeout'::character varying, 'awaiting_approval'::character varying]::text[])", name: "check_team_execution_status"
  end

  create_table "ai_team_messages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.uuid "team_execution_id", null: false
    t.uuid "to_role_id"
    t.datetime "updated_at", null: false
    t.index ["channel_id", "created_at"], name: "index_ai_team_messages_on_channel_id_and_created_at"
    t.index ["channel_id"], name: "index_ai_team_messages_on_channel_id"
    t.index ["from_role_id", "created_at"], name: "index_ai_team_messages_on_from_role_id_and_created_at"
    t.index ["from_role_id"], name: "index_ai_team_messages_on_from_role_id"
    t.index ["in_reply_to_id"], name: "index_ai_team_messages_on_in_reply_to_id"
    t.index ["message_type"], name: "index_ai_team_messages_on_message_type"
    t.index ["team_execution_id", "sequence_number"], name: "idx_on_team_execution_id_sequence_number_beb97b4ae3"
    t.index ["team_execution_id"], name: "index_ai_team_messages_on_team_execution_id"
    t.index ["to_role_id"], name: "index_ai_team_messages_on_to_role_id"
    t.check_constraint "message_type::text = ANY (ARRAY['task_assignment'::character varying, 'task_update'::character varying, 'task_result'::character varying, 'work_plan'::character varying, 'synthesis'::character varying, 'question'::character varying, 'answer'::character varying, 'escalation'::character varying, 'coordination'::character varying, 'broadcast'::character varying, 'human_input'::character varying]::text[])", name: "check_team_message_type"
  end

  create_table "ai_team_roles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_team_tasks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["parent_task_id"], name: "index_ai_team_tasks_on_parent_task_id"
    t.index ["priority"], name: "index_ai_team_tasks_on_priority"
    t.index ["task_id"], name: "index_ai_team_tasks_on_task_id", unique: true
    t.index ["team_execution_id", "status"], name: "index_ai_team_tasks_on_team_execution_id_and_status"
    t.index ["team_execution_id"], name: "index_ai_team_tasks_on_team_execution_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'assigned'::character varying::text, 'in_progress'::character varying::text, 'waiting'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text, 'delegated'::character varying::text])", name: "check_team_task_status"
    t.check_constraint "task_type::text = ANY (ARRAY['execution'::character varying::text, 'review'::character varying::text, 'validation'::character varying::text, 'coordination'::character varying::text, 'escalation'::character varying::text, 'human_input'::character varying::text])", name: "check_team_task_type"
  end

  create_table "ai_team_templates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id"], name: "index_ai_team_templates_on_account_id"
    t.index ["created_by_id"], name: "index_ai_team_templates_on_created_by_id"
    t.index ["is_public", "category"], name: "index_ai_team_templates_on_is_public_and_category"
    t.index ["is_system"], name: "index_ai_team_templates_on_is_system"
    t.index ["slug"], name: "index_ai_team_templates_on_slug", unique: true
    t.index ["team_topology"], name: "index_ai_team_templates_on_team_topology"
    t.check_constraint "team_topology::text = ANY (ARRAY['hierarchical'::character varying::text, 'flat'::character varying::text, 'mesh'::character varying::text, 'pipeline'::character varying::text, 'hybrid'::character varying::text])", name: "check_team_topology"
  end

  create_table "ai_template_usage_metrics", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["agent_template_id", "metric_date"], name: "idx_template_metrics_date", unique: true
    t.index ["agent_template_id"], name: "index_ai_template_usage_metrics_on_agent_template_id"
    t.index ["metric_date"], name: "index_ai_template_usage_metrics_on_metric_date"
  end

  create_table "ai_test_results", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_test_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "ai_test_scenarios", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.uuid "target_workflow_id"
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
    t.index ["target_workflow_id"], name: "index_ai_test_scenarios_on_target_workflow_id"
    t.check_constraint "scenario_type::text = ANY (ARRAY['unit'::character varying::text, 'integration'::character varying::text, 'regression'::character varying::text, 'performance'::character varying::text, 'security'::character varying::text, 'chaos'::character varying::text, 'custom'::character varying::text])", name: "check_scenario_type"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'active'::character varying::text, 'disabled'::character varying::text, 'archived'::character varying::text])", name: "check_scenario_status"
  end

  create_table "ai_trajectories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.uuid "workflow_run_id"
    t.index ["account_id"], name: "index_ai_trajectories_on_account_id"
    t.index ["ai_agent_id"], name: "index_ai_trajectories_on_ai_agent_id"
    t.index ["status"], name: "index_ai_trajectories_on_status"
    t.index ["tags"], name: "index_ai_trajectories_on_tags", using: :gin
    t.index ["team_execution_id"], name: "index_ai_trajectories_on_team_execution_id"
    t.index ["trajectory_id"], name: "index_ai_trajectories_on_trajectory_id", unique: true
    t.index ["workflow_run_id"], name: "index_ai_trajectories_on_workflow_run_id"
  end

  create_table "ai_trajectory_chapters", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["trajectory_id", "chapter_number"], name: "idx_trajectory_chapters_on_trajectory_and_number", unique: true
    t.index ["trajectory_id"], name: "index_ai_trajectory_chapters_on_trajectory_id"
  end

  create_table "ai_workflow_approval_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_workflow_node_execution_id", null: false
    t.datetime "created_at", null: false
    t.datetime "email_sent_at"
    t.datetime "expires_at", null: false
    t.string "recipient_email", null: false
    t.uuid "recipient_user_id"
    t.datetime "responded_at"
    t.uuid "responded_by_id"
    t.text "response_comment"
    t.string "status", default: "pending", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_workflow_node_execution_id", "status"], name: "idx_ai_workflow_approval_tokens_execution_status"
    t.index ["ai_workflow_node_execution_id"], name: "idx_on_ai_workflow_node_execution_id_0389e52806"
    t.index ["recipient_user_id"], name: "index_ai_workflow_approval_tokens_on_recipient_user_id"
    t.index ["responded_by_id"], name: "index_ai_workflow_approval_tokens_on_responded_by_id"
    t.index ["status", "expires_at"], name: "idx_ai_workflow_approval_tokens_pending_expiry", where: "((status)::text = 'pending'::text)"
    t.index ["token_digest"], name: "index_ai_workflow_approval_tokens_on_token_digest", unique: true
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'approved'::character varying::text, 'rejected'::character varying::text, 'expired'::character varying::text])", name: "ai_workflow_approval_tokens_status_check"
  end

  create_table "ai_workflow_checkpoints", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_workflow_run_id", null: false
    t.string "checkpoint_id", null: false
    t.string "checkpoint_type", default: "node_completion", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "execution_context", default: {}, null: false
    t.jsonb "metadata", default: {}
    t.string "node_id", null: false
    t.integer "sequence_number", null: false
    t.datetime "updated_at", null: false
    t.jsonb "variable_snapshot", default: {}
    t.jsonb "workflow_state", default: {}, null: false
    t.index ["ai_workflow_run_id", "checkpoint_id"], name: "index_checkpoints_on_run_and_id", unique: true
    t.index ["ai_workflow_run_id", "sequence_number"], name: "index_checkpoints_on_run_and_sequence"
    t.index ["ai_workflow_run_id"], name: "index_ai_workflow_checkpoints_on_ai_workflow_run_id"
    t.index ["checkpoint_id"], name: "index_ai_workflow_checkpoints_on_checkpoint_id"
    t.index ["sequence_number"], name: "index_ai_workflow_checkpoints_on_sequence_number"
  end

  create_table "ai_workflow_compensations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_workflow_node_execution_id", null: false
    t.uuid "ai_workflow_run_id", null: false
    t.jsonb "compensation_action", default: {}, null: false
    t.string "compensation_id", null: false
    t.jsonb "compensation_result", default: {}
    t.string "compensation_type", default: "rollback", null: false
    t.datetime "completed_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "executed_at", precision: nil
    t.datetime "failed_at", precision: nil
    t.integer "max_retries", default: 3
    t.jsonb "metadata", default: {}
    t.jsonb "original_action", default: {}, null: false
    t.integer "retry_count", default: 0
    t.string "status", default: "pending", null: false
    t.string "trigger_reason", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_workflow_run_id", "status"], name: "index_compensations_on_run_and_status"
    t.index ["compensation_id"], name: "index_ai_workflow_compensations_on_compensation_id", unique: true
  end

  create_table "ai_workflow_edges", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_workflow_id", null: false
    t.jsonb "condition", default: {}, null: false
    t.jsonb "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "edge_id", limit: 255, null: false
    t.string "edge_type", default: "default", null: false
    t.boolean "is_conditional", default: false, null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "priority", default: 0, null: false
    t.string "source_handle", limit: 50
    t.string "source_node_id", limit: 255, null: false
    t.string "target_handle", limit: 50
    t.string "target_node_id", limit: 255, null: false
    t.datetime "updated_at", null: false
    t.index ["ai_workflow_id", "edge_id"], name: "index_workflow_edges_on_workflow_edge_id", unique: true
    t.index ["ai_workflow_id", "is_conditional"], name: "index_ai_workflow_edges_on_ai_workflow_id_and_is_conditional"
    t.index ["ai_workflow_id", "source_node_id"], name: "index_ai_workflow_edges_on_ai_workflow_id_and_source_node_id"
    t.index ["ai_workflow_id", "target_node_id"], name: "index_ai_workflow_edges_on_ai_workflow_id_and_target_node_id"
    t.index ["ai_workflow_id"], name: "index_ai_workflow_edges_on_ai_workflow_id"
    t.index ["priority"], name: "index_ai_workflow_edges_on_priority"
    t.check_constraint "edge_type::text = ANY (ARRAY['default'::character varying::text, 'success'::character varying::text, 'error'::character varying::text, 'conditional'::character varying::text, 'retry'::character varying::text, 'timeout'::character varying::text, 'skip'::character varying::text, 'fallback'::character varying::text, 'compensation'::character varying::text, 'loop'::character varying::text])", name: "ai_workflow_edges_type_check"
  end

  create_table "ai_workflow_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "completed_at", precision: nil
    t.json "configuration", default: "{}", null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "execution_id", limit: 255, null: false
    t.json "metadata", default: "{}"
    t.string "name", limit: 255, null: false
    t.json "results", default: "[]"
    t.datetime "started_at", precision: nil
    t.string "status", limit: 50, default: "initializing", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["account_id", "created_at"], name: "index_ai_workflow_executions_on_account_id_and_created_at"
    t.index ["account_id", "status"], name: "index_ai_workflow_executions_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_workflow_executions_on_account_id"
    t.index ["created_at"], name: "index_ai_workflow_executions_on_created_at"
    t.index ["execution_id"], name: "index_ai_workflow_executions_on_execution_id", unique: true
    t.index ["status"], name: "index_ai_workflow_executions_on_status"
    t.index ["user_id"], name: "index_ai_workflow_executions_on_user_id"
  end

  create_table "ai_workflow_node_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_agent_execution_id"
    t.uuid "ai_workflow_node_id", null: false
    t.uuid "ai_workflow_run_id", null: false
    t.datetime "cancelled_at"
    t.datetime "completed_at"
    t.jsonb "configuration_snapshot", default: {}, null: false
    t.decimal "cost", precision: 10, scale: 6, default: "0.0"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.jsonb "error_details", default: {}, null: false
    t.string "execution_id", limit: 100, null: false
    t.jsonb "input_data", default: {}, null: false
    t.integer "max_retries", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "node_id", limit: 100, null: false
    t.string "node_type", limit: 50, null: false
    t.jsonb "output_data", default: {}, null: false
    t.integer "retry_count", default: 0, null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_agent_execution_id"], name: "index_ai_workflow_node_executions_on_ai_agent_execution_id"
    t.index ["ai_workflow_node_id"], name: "index_ai_workflow_node_executions_on_ai_workflow_node_id"
    t.index ["ai_workflow_run_id", "node_id"], name: "index_node_executions_on_run_node", unique: true
    t.index ["ai_workflow_run_id", "status"], name: "idx_on_ai_workflow_run_id_status_0ccb23af98"
    t.index ["ai_workflow_run_id"], name: "index_ai_workflow_node_executions_on_ai_workflow_run_id"
    t.index ["completed_at"], name: "index_ai_workflow_node_executions_on_completed_at"
    t.index ["cost"], name: "index_ai_workflow_node_executions_on_cost"
    t.index ["execution_id"], name: "index_ai_workflow_node_executions_on_execution_id", unique: true
    t.index ["node_type"], name: "index_ai_workflow_node_executions_on_node_type"
    t.index ["started_at"], name: "index_ai_workflow_node_executions_on_started_at"
    t.check_constraint "cost >= 0::numeric", name: "ai_workflow_node_executions_cost_check"
    t.check_constraint "max_retries >= 0", name: "ai_workflow_node_executions_max_retries_check"
    t.check_constraint "retry_count <= max_retries", name: "ai_workflow_node_executions_retry_limit_check"
    t.check_constraint "retry_count >= 0", name: "ai_workflow_node_executions_retry_count_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text, 'skipped'::character varying::text, 'waiting_approval'::character varying::text])", name: "ai_workflow_node_executions_status_check"
  end

  create_table "ai_workflow_nodes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_workflow_id", null: false
    t.jsonb "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "error_node_id", limit: 255
    t.boolean "is_end_node", default: false, null: false
    t.boolean "is_error_handler", default: false, null: false
    t.boolean "is_start_node", default: false, null: false
    t.jsonb "mcp_tool_config", default: {}, null: false, comment: "MCP tool configuration for this node"
    t.string "mcp_tool_id", comment: "ID of the MCP tool used by this node"
    t.string "mcp_tool_version"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", limit: 255, null: false
    t.string "node_id", limit: 255, null: false
    t.string "node_type", limit: 50, null: false
    t.uuid "plugin_id"
    t.jsonb "position", default: {}, null: false
    t.integer "retry_count", default: 0
    t.uuid "shared_prompt_template_id"
    t.integer "timeout_seconds", default: 300
    t.datetime "updated_at", null: false
    t.jsonb "validation_rules", default: {}, null: false
    t.index ["ai_workflow_id", "is_end_node"], name: "index_ai_workflow_nodes_on_ai_workflow_id_and_is_end_node"
    t.index ["ai_workflow_id", "is_start_node"], name: "index_ai_workflow_nodes_on_ai_workflow_id_and_is_start_node"
    t.index ["ai_workflow_id", "node_id"], name: "index_workflow_nodes_on_workflow_node_id", unique: true
    t.index ["ai_workflow_id", "node_type"], name: "index_ai_workflow_nodes_on_ai_workflow_id_and_node_type"
    t.index ["ai_workflow_id"], name: "index_ai_workflow_nodes_on_ai_workflow_id"
    t.index ["mcp_tool_id", "mcp_tool_version"], name: "index_workflow_nodes_on_mcp_tool_and_version"
    t.index ["mcp_tool_id"], name: "index_ai_workflow_nodes_on_mcp_tool_id"
    t.index ["plugin_id"], name: "index_ai_workflow_nodes_on_plugin_id"
    t.index ["shared_prompt_template_id"], name: "index_ai_workflow_nodes_on_shared_prompt_template_id"
    t.check_constraint "node_type::text = ANY (ARRAY['start'::character varying, 'end'::character varying, 'trigger'::character varying, 'ai_agent'::character varying, 'prompt_template'::character varying, 'data_processor'::character varying, 'transform'::character varying, 'condition'::character varying, 'loop'::character varying, 'delay'::character varying, 'merge'::character varying, 'split'::character varying, 'database'::character varying, 'file'::character varying, 'validator'::character varying, 'email'::character varying, 'notification'::character varying, 'api_call'::character varying, 'webhook'::character varying, 'scheduler'::character varying, 'human_approval'::character varying, 'sub_workflow'::character varying, 'kb_article'::character varying, 'page'::character varying, 'mcp_operation'::character varying, 'ci_trigger'::character varying, 'ci_wait_status'::character varying, 'ci_get_logs'::character varying, 'ci_cancel'::character varying, 'git_commit_status'::character varying, 'git_create_check'::character varying, 'integration_execute'::character varying, 'git_checkout'::character varying, 'git_branch'::character varying, 'git_pull_request'::character varying, 'git_comment'::character varying, 'deploy'::character varying, 'run_tests'::character varying, 'shell_command'::character varying, 'ralph_loop'::character varying]::text[])", name: "ai_workflow_nodes_type_check"
    t.check_constraint "retry_count >= 0", name: "ai_workflow_nodes_retry_check"
    t.check_constraint "timeout_seconds > 0", name: "ai_workflow_nodes_timeout_check"
  end

  create_table "ai_workflow_run_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_workflow_node_execution_id"
    t.uuid "ai_workflow_run_id", null: false
    t.jsonb "context_data", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.string "log_level", default: "info", null: false
    t.datetime "logged_at", null: false
    t.text "message", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "node_id", limit: 100
    t.string "source", limit: 100
    t.datetime "updated_at", null: false
    t.index ["ai_workflow_node_execution_id"], name: "index_ai_workflow_run_logs_on_ai_workflow_node_execution_id"
    t.index ["ai_workflow_run_id", "event_type"], name: "idx_on_ai_workflow_run_id_event_type_e8cb27369f"
    t.index ["ai_workflow_run_id", "log_level"], name: "index_ai_workflow_run_logs_on_ai_workflow_run_id_and_log_level"
    t.index ["ai_workflow_run_id", "logged_at"], name: "index_ai_workflow_run_logs_on_ai_workflow_run_id_and_logged_at"
    t.index ["ai_workflow_run_id"], name: "index_ai_workflow_run_logs_on_ai_workflow_run_id"
    t.index ["event_type"], name: "index_ai_workflow_run_logs_on_event_type"
    t.index ["logged_at"], name: "index_ai_workflow_run_logs_on_logged_at"
    t.index ["node_id", "logged_at"], name: "index_ai_workflow_run_logs_on_node_id_and_logged_at"
    t.check_constraint "event_type::text = ANY (ARRAY['workflow_started'::character varying::text, 'workflow_completed'::character varying::text, 'workflow_failed'::character varying::text, 'workflow_cancelled'::character varying::text, 'node_started'::character varying::text, 'node_completed'::character varying::text, 'node_failed'::character varying::text, 'node_cancelled'::character varying::text, 'node_skipped'::character varying::text, 'variable_updated'::character varying::text, 'condition_evaluated'::character varying::text, 'error_handled'::character varying::text, 'retry_attempted'::character varying::text, 'approval_requested'::character varying::text, 'approval_granted'::character varying::text, 'approval_denied'::character varying::text, 'webhook_sent'::character varying::text, 'api_called'::character varying::text, 'data_transformed'::character varying::text, 'cost_added'::character varying::text, 'timeout_detected'::character varying::text, 'ai_agent_execution_queued'::character varying::text, 'api_call_queued'::character varying::text, 'webhook_queued'::character varying::text, 'condition_evaluation_queued'::character varying::text, 'loop_execution_queued'::character varying::text, 'transform_execution_queued'::character varying::text, 'sub_workflow_queued'::character varying::text, 'merge_execution_queued'::character varying::text, 'split_execution_queued'::character varying::text, 'delay_scheduled'::character varying::text, 'node_retry_scheduled'::character varying::text, 'webhook_started'::character varying::text, 'webhook_sending'::character varying::text, 'webhook_response_received'::character varying::text, 'webhook_completed'::character varying::text, 'webhook_failed'::character varying::text, 'condition_evaluation_started'::character varying::text, 'condition_evaluation_completed'::character varying::text, 'condition_evaluation_error'::character varying::text, 'node_execution_error'::character varying::text, 'delay_execution_started'::character varying::text, 'delay_execution_completed'::character varying::text, 'approval_notification_sent'::character varying::text, 'merge_execution_started'::character varying::text, 'merge_execution_completed'::character varying::text, 'split_execution_started'::character varying::text, 'split_execution_completed'::character varying::text, 'api_call_started'::character varying::text, 'api_request_sent'::character varying::text, 'api_response_received'::character varying::text, 'api_call_completed'::character varying::text, 'api_call_failed'::character varying::text, 'human_approval_started'::character varying::text, 'human_approval_initiated'::character varying::text, 'approval_request_created'::character varying::text, 'approval_email_sent'::character varying::text, 'approval_in_app_sent'::character varying::text])", name: "ai_workflow_run_logs_event_type_check"
    t.check_constraint "log_level::text = ANY (ARRAY['debug'::character varying::text, 'info'::character varying::text, 'warn'::character varying::text, 'error'::character varying::text, 'fatal'::character varying::text])", name: "ai_workflow_run_logs_level_check"
  end

  create_table "ai_workflow_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "a2a_artifacts", default: []
    t.uuid "a2a_context_id"
    t.uuid "a2a_task_id"
    t.uuid "account_id", null: false
    t.uuid "ai_workflow_id", null: false
    t.uuid "ai_workflow_trigger_id"
    t.datetime "cancelled_at"
    t.datetime "completed_at"
    t.integer "completed_nodes", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "current_node_id"
    t.integer "duration_ms"
    t.jsonb "error_details", default: {}, null: false
    t.integer "failed_nodes", default: 0, null: false
    t.jsonb "input_variables", default: {}, null: false
    t.jsonb "mcp_execution_context", default: {}, null: false, comment: "MCP execution context and state"
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "output_variables", default: {}, null: false
    t.string "run_id", limit: 100, null: false
    t.jsonb "runtime_context", default: {}, null: false
    t.datetime "started_at"
    t.string "status", default: "initializing", null: false
    t.decimal "total_cost", precision: 10, scale: 6, default: "0.0"
    t.integer "total_nodes", default: 0, null: false
    t.string "trigger_type", null: false
    t.uuid "triggered_by_user_id"
    t.datetime "updated_at", null: false
    t.index ["a2a_context_id"], name: "index_ai_workflow_runs_on_a2a_context_id", where: "(a2a_context_id IS NOT NULL)"
    t.index ["a2a_task_id"], name: "index_ai_workflow_runs_on_a2a_task_id", where: "(a2a_task_id IS NOT NULL)"
    t.index ["account_id", "status"], name: "index_ai_workflow_runs_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_workflow_runs_on_account_id"
    t.index ["ai_workflow_id", "status"], name: "index_ai_workflow_runs_on_ai_workflow_id_and_status"
    t.index ["ai_workflow_id"], name: "index_ai_workflow_runs_on_ai_workflow_id"
    t.index ["ai_workflow_trigger_id"], name: "index_ai_workflow_runs_on_ai_workflow_trigger_id"
    t.index ["completed_at"], name: "index_ai_workflow_runs_on_completed_at"
    t.index ["run_id"], name: "index_ai_workflow_runs_on_run_id", unique: true
    t.index ["started_at"], name: "index_ai_workflow_runs_on_started_at"
    t.index ["total_cost"], name: "index_ai_workflow_runs_on_total_cost"
    t.index ["trigger_type"], name: "index_ai_workflow_runs_on_trigger_type"
    t.index ["triggered_by_user_id"], name: "index_ai_workflow_runs_on_triggered_by_user_id"
    t.check_constraint "completed_nodes <= total_nodes", name: "ai_workflow_runs_progress_check"
    t.check_constraint "status::text = ANY (ARRAY['initializing'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text, 'waiting_approval'::character varying::text])", name: "ai_workflow_runs_status_check"
    t.check_constraint "total_cost >= 0::numeric", name: "ai_workflow_runs_cost_check"
    t.check_constraint "trigger_type::text = ANY (ARRAY['manual'::character varying::text, 'webhook'::character varying::text, 'schedule'::character varying::text, 'event'::character varying::text, 'api_call'::character varying::text])", name: "ai_workflow_runs_trigger_type_check"
  end

  create_table "ai_workflow_schedules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_workflow_id", null: false
    t.jsonb "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.string "cron_expression", null: false
    t.text "description"
    t.datetime "ends_at"
    t.integer "execution_count", default: 0, null: false
    t.jsonb "input_variables", default: {}, null: false
    t.boolean "is_active", default: true, null: false
    t.datetime "last_execution_at"
    t.integer "max_executions"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", limit: 255, null: false
    t.datetime "next_execution_at"
    t.datetime "starts_at"
    t.string "status", default: "active", null: false
    t.string "timezone", default: "UTC", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_workflow_id", "status"], name: "index_ai_workflow_schedules_on_ai_workflow_id_and_status"
    t.index ["ai_workflow_id"], name: "index_ai_workflow_schedules_on_ai_workflow_id"
    t.index ["created_by_id"], name: "index_ai_workflow_schedules_on_created_by_id"
    t.index ["cron_expression"], name: "index_ai_workflow_schedules_on_cron_expression"
    t.index ["last_execution_at"], name: "index_ai_workflow_schedules_on_last_execution_at"
    t.index ["next_execution_at", "is_active"], name: "index_ai_workflow_schedules_on_next_execution_at_and_is_active"
    t.index ["timezone"], name: "index_ai_workflow_schedules_on_timezone"
    t.check_constraint "ends_at IS NULL OR starts_at IS NULL OR ends_at > starts_at", name: "ai_workflow_schedules_date_range_check"
    t.check_constraint "execution_count >= 0", name: "ai_workflow_schedules_execution_count_check"
    t.check_constraint "max_executions IS NULL OR max_executions > 0", name: "ai_workflow_schedules_max_executions_check"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'paused'::character varying::text, 'disabled'::character varying::text, 'expired'::character varying::text])", name: "ai_workflow_schedules_status_check"
  end

  create_table "ai_workflow_templates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.string "author_email", limit: 255
    t.string "author_name", limit: 255
    t.string "author_url", limit: 500
    t.string "category", limit: 100, null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_user_id"
    t.jsonb "default_variables", default: {}, null: false
    t.text "description", null: false
    t.string "difficulty_level", default: "beginner", null: false
    t.boolean "is_featured", default: false, null: false
    t.boolean "is_marketplace_published", default: false
    t.boolean "is_public", default: false, null: false
    t.string "license", limit: 100, default: "MIT"
    t.text "long_description"
    t.datetime "marketplace_approved_at"
    t.text "marketplace_rejection_reason"
    t.string "marketplace_status"
    t.datetime "marketplace_submitted_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", limit: 255, null: false
    t.datetime "published_at"
    t.decimal "rating", precision: 3, scale: 2, default: "0.0"
    t.integer "rating_count", default: 0, null: false
    t.string "slug", limit: 150, null: false
    t.jsonb "tags", default: [], null: false
    t.datetime "updated_at", null: false
    t.integer "usage_count", default: 0, null: false
    t.string "version", default: "1.0.0", null: false
    t.jsonb "workflow_definition", null: false
    t.index ["account_id", "is_public"], name: "index_ai_workflow_templates_on_account_id_and_is_public"
    t.index ["account_id"], name: "index_ai_workflow_templates_on_account_id"
    t.index ["category", "is_public"], name: "index_ai_workflow_templates_on_category_and_is_public"
    t.index ["created_by_user_id"], name: "index_ai_workflow_templates_on_created_by_user_id"
    t.index ["difficulty_level"], name: "index_ai_workflow_templates_on_difficulty_level"
    t.index ["is_featured", "is_public"], name: "index_ai_workflow_templates_on_is_featured_and_is_public"
    t.index ["is_marketplace_published", "marketplace_status"], name: "idx_ai_workflow_templates_marketplace"
    t.index ["published_at"], name: "index_ai_workflow_templates_on_published_at"
    t.index ["rating"], name: "index_ai_workflow_templates_on_rating"
    t.index ["slug"], name: "index_ai_workflow_templates_on_slug", unique: true
    t.index ["usage_count"], name: "index_ai_workflow_templates_on_usage_count"
    t.check_constraint "difficulty_level::text = ANY (ARRAY['beginner'::character varying::text, 'intermediate'::character varying::text, 'advanced'::character varying::text, 'expert'::character varying::text])", name: "ai_workflow_templates_difficulty_check"
    t.check_constraint "rating >= 0::numeric AND rating <= 5::numeric", name: "ai_workflow_templates_rating_check"
    t.check_constraint "rating_count >= 0", name: "ai_workflow_templates_rating_count_check"
    t.check_constraint "usage_count >= 0", name: "ai_workflow_templates_usage_count_check"
  end

  create_table "ai_workflow_triggers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_workflow_id", null: false
    t.jsonb "conditions", default: {}, null: false
    t.jsonb "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.boolean "is_active", default: true, null: false
    t.datetime "last_triggered_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", limit: 255, null: false
    t.datetime "next_execution_at"
    t.string "schedule_cron"
    t.string "status", default: "active", null: false
    t.integer "trigger_count", default: 0, null: false
    t.string "trigger_type", null: false
    t.datetime "updated_at", null: false
    t.string "webhook_secret"
    t.string "webhook_url", limit: 2048
    t.index ["ai_workflow_id", "status"], name: "index_ai_workflow_triggers_on_ai_workflow_id_and_status"
    t.index ["ai_workflow_id", "trigger_type"], name: "index_ai_workflow_triggers_on_ai_workflow_id_and_trigger_type"
    t.index ["ai_workflow_id"], name: "index_ai_workflow_triggers_on_ai_workflow_id"
    t.index ["next_execution_at"], name: "index_ai_workflow_triggers_on_next_execution_at"
    t.index ["schedule_cron"], name: "index_ai_workflow_triggers_on_schedule_cron"
    t.index ["trigger_type", "is_active"], name: "index_ai_workflow_triggers_on_trigger_type_and_is_active"
    t.index ["webhook_url"], name: "index_ai_workflow_triggers_on_webhook_url"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'paused'::character varying::text, 'disabled'::character varying::text, 'error'::character varying::text])", name: "ai_workflow_triggers_status_check"
    t.check_constraint "trigger_type::text <> 'schedule'::text OR schedule_cron IS NOT NULL", name: "ai_workflow_triggers_schedule_required_check"
    t.check_constraint "trigger_type::text <> 'webhook'::text OR webhook_url IS NOT NULL", name: "ai_workflow_triggers_webhook_required_check"
    t.check_constraint "trigger_type::text = ANY (ARRAY['manual'::character varying::text, 'webhook'::character varying::text, 'schedule'::character varying::text, 'event'::character varying::text, 'api_call'::character varying::text])", name: "ai_workflow_triggers_type_check"
  end

  create_table "ai_workflow_variables", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_workflow_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "default_value"
    t.text "description"
    t.boolean "is_input", default: false, null: false
    t.boolean "is_output", default: false, null: false
    t.boolean "is_required", default: false, null: false
    t.boolean "is_secret", default: false, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "name", limit: 100, null: false
    t.string "scope", default: "workflow", null: false
    t.datetime "updated_at", null: false
    t.jsonb "validation_rules", default: {}, null: false
    t.string "variable_type", default: "string", null: false
    t.index ["ai_workflow_id", "is_input"], name: "index_ai_workflow_variables_on_ai_workflow_id_and_is_input"
    t.index ["ai_workflow_id", "is_output"], name: "index_ai_workflow_variables_on_ai_workflow_id_and_is_output"
    t.index ["ai_workflow_id", "is_required"], name: "index_ai_workflow_variables_on_ai_workflow_id_and_is_required"
    t.index ["ai_workflow_id", "name"], name: "index_workflow_variables_on_workflow_name", unique: true
    t.index ["ai_workflow_id"], name: "index_ai_workflow_variables_on_ai_workflow_id"
    t.index ["scope"], name: "index_ai_workflow_variables_on_scope"
    t.check_constraint "name::text ~ '^[a-zA-Z][a-zA-Z0-9_]*$'::text", name: "ai_workflow_variables_name_format_check"
    t.check_constraint "scope::text = ANY (ARRAY['workflow'::character varying::text, 'node'::character varying::text, 'global'::character varying::text])", name: "ai_workflow_variables_scope_check"
    t.check_constraint "variable_type::text = ANY (ARRAY['string'::character varying::text, 'number'::character varying::text, 'boolean'::character varying::text, 'object'::character varying::text, 'array'::character varying::text, 'date'::character varying::text, 'datetime'::character varying::text, 'file'::character varying::text, 'json'::character varying::text])", name: "ai_workflow_variables_type_check"
  end

  create_table "ai_workflows", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.text "change_summary"
    t.jsonb "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.uuid "creator_id", null: false
    t.text "description"
    t.integer "execution_count", default: 0, null: false
    t.boolean "is_active", default: true, null: false
    t.boolean "is_template", default: false, null: false
    t.datetime "last_executed_at"
    t.jsonb "mcp_input_schema", default: {}, null: false
    t.jsonb "mcp_orchestration_config", default: {}, null: false, comment: "MCP-specific orchestration configuration"
    t.jsonb "mcp_output_schema", default: {}, null: false
    t.jsonb "mcp_tool_requirements", default: [], null: false, comment: "Array of required MCP tools for workflow execution"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", limit: 255, null: false
    t.uuid "parent_version_id"
    t.datetime "published_at"
    t.string "slug", limit: 150, null: false
    t.string "status", default: "draft", null: false
    t.string "template_category", limit: 100
    t.datetime "updated_at", null: false
    t.string "version", default: "1.0.0", null: false
    t.jsonb "version_metadata", default: {}
    t.string "visibility", default: "private", null: false
    t.string "workflow_type", limit: 20, default: "ai", null: false
    t.index ["account_id", "name", "version"], name: "index_workflows_on_account_name_version", unique: true
    t.index ["account_id", "slug"], name: "index_ai_workflows_on_account_slug", unique: true
    t.index ["account_id", "status"], name: "index_ai_workflows_on_account_id_and_status"
    t.index ["account_id", "workflow_type"], name: "index_ai_workflows_on_account_id_and_workflow_type"
    t.index ["account_id"], name: "index_ai_workflows_on_account_id"
    t.index ["creator_id"], name: "index_ai_workflows_on_creator_id"
    t.index ["is_active"], name: "index_ai_workflows_on_is_active"
    t.index ["is_template", "template_category"], name: "index_ai_workflows_on_is_template_and_template_category"
    t.index ["last_executed_at"], name: "index_ai_workflows_on_last_executed_at"
    t.index ["mcp_tool_requirements"], name: "index_ai_workflows_on_mcp_tool_requirements", using: :gin
    t.index ["parent_version_id"], name: "index_ai_workflows_on_parent_version_id"
    t.index ["published_at"], name: "index_ai_workflows_on_published_at"
    t.index ["version"], name: "index_ai_workflows_on_version"
    t.index ["workflow_type"], name: "index_ai_workflows_on_workflow_type"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'active'::character varying::text, 'paused'::character varying::text, 'inactive'::character varying::text, 'archived'::character varying::text])", name: "ai_workflows_status_check"
    t.check_constraint "template_category IS NULL OR template_category::text <> ''::text", name: "ai_workflows_template_category_check"
    t.check_constraint "visibility::text = ANY (ARRAY['private'::character varying::text, 'account'::character varying::text, 'public'::character varying::text])", name: "ai_workflows_visibility_check"
    t.check_constraint "workflow_type::text = ANY (ARRAY['ai'::character varying::text, 'cicd'::character varying::text])", name: "ai_workflows_workflow_type_check"
  end

  create_table "ai_worktree_sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["source_type", "source_id"], name: "index_ai_worktree_sessions_on_source"
    t.index ["status"], name: "index_ai_worktree_sessions_on_status"
  end

  create_table "ai_worktrees", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["assignee_type", "assignee_id"], name: "index_ai_worktrees_on_assignee"
    t.index ["branch_name"], name: "index_ai_worktrees_on_branch_name", unique: true
    t.index ["status"], name: "index_ai_worktrees_on_status"
    t.index ["worktree_path"], name: "index_ai_worktrees_on_worktree_path", unique: true
    t.index ["worktree_session_id"], name: "index_ai_worktrees_on_worktree_session_id"
  end

  create_table "analytics_alert_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.boolean "acknowledged", default: false
    t.datetime "acknowledged_at"
    t.string "acknowledged_by"
    t.uuid "analytics_alert_id", null: false
    t.jsonb "context", default: {}
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.text "message"
    t.string "resolution_notes"
    t.boolean "resolved", default: false
    t.datetime "resolved_at"
    t.string "severity", default: "medium"
    t.decimal "threshold_value", precision: 15, scale: 4
    t.decimal "triggered_value", precision: 15, scale: 4
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_analytics_alert_events_on_account_id"
    t.index ["analytics_alert_id", "created_at"], name: "idx_on_analytics_alert_id_created_at_fd77b4cb4b"
    t.index ["analytics_alert_id"], name: "index_analytics_alert_events_on_analytics_alert_id"
    t.index ["event_type"], name: "index_analytics_alert_events_on_event_type"
    t.index ["severity"], name: "index_analytics_alert_events_on_severity"
    t.check_constraint "event_type::text = ANY (ARRAY['triggered'::character varying::text, 'resolved'::character varying::text, 'acknowledged'::character varying::text, 'escalated'::character varying::text])", name: "alert_events_type_check"
    t.check_constraint "severity::text = ANY (ARRAY['critical'::character varying::text, 'high'::character varying::text, 'medium'::character varying::text, 'low'::character varying::text, 'info'::character varying::text])", name: "alert_events_severity_check"
  end

  create_table "analytics_alerts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.string "alert_type", null: false
    t.boolean "auto_resolve", default: true
    t.string "comparison_period", default: "previous_period"
    t.string "condition", null: false
    t.integer "cooldown_minutes", default: 60
    t.datetime "cooldown_until"
    t.datetime "created_at", null: false
    t.decimal "current_value", precision: 15, scale: 4
    t.datetime "last_checked_at"
    t.datetime "last_triggered_at"
    t.jsonb "metadata", default: {}
    t.string "metric_name", null: false
    t.string "name", null: false
    t.text "notification_channels", default: [], array: true
    t.jsonb "notification_settings", default: {}
    t.string "status", default: "enabled", null: false
    t.decimal "threshold_value", precision: 15, scale: 4, null: false
    t.integer "trigger_count", default: 0
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_analytics_alerts_on_account_id"
    t.index ["alert_type"], name: "index_analytics_alerts_on_alert_type"
    t.index ["metric_name"], name: "index_analytics_alerts_on_metric_name"
    t.index ["status"], name: "index_analytics_alerts_on_status"
    t.check_constraint "alert_type::text = ANY (ARRAY['threshold'::character varying::text, 'anomaly'::character varying::text, 'trend'::character varying::text, 'comparison'::character varying::text])", name: "analytics_alerts_type_check"
    t.check_constraint "condition::text = ANY (ARRAY['greater_than'::character varying::text, 'less_than'::character varying::text, 'equals'::character varying::text, 'change_percent'::character varying::text, 'anomaly_detected'::character varying::text])", name: "analytics_alerts_condition_check"
    t.check_constraint "status::text = ANY (ARRAY['enabled'::character varying::text, 'disabled'::character varying::text, 'triggered'::character varying::text, 'resolved'::character varying::text])", name: "analytics_alerts_status_check"
  end

  create_table "analytics_tiers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "api_access", default: false, null: false
    t.integer "api_calls_per_day", default: 0, null: false
    t.integer "cohort_months", default: 3, null: false
    t.datetime "created_at", null: false
    t.boolean "csv_export", default: false, null: false
    t.boolean "custom_reports", default: false, null: false
    t.text "description"
    t.jsonb "features", default: {}
    t.boolean "forecasting", default: false, null: false
    t.boolean "is_active", default: true, null: false
    t.decimal "monthly_price", precision: 10, scale: 2, default: "0.0", null: false
    t.string "name", null: false
    t.integer "retention_days", default: 30, null: false
    t.string "slug", null: false
    t.integer "sort_order", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["is_active"], name: "index_analytics_tiers_on_is_active"
    t.index ["slug"], name: "index_analytics_tiers_on_slug", unique: true
  end

  create_table "api_key_usages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["api_key_id", "used_at"], name: "idx_api_key_usages_on_api_key_used_at"
    t.index ["api_key_id"], name: "index_api_key_usages_on_api_key_id"
    t.index ["endpoint"], name: "idx_api_key_usages_on_endpoint"
    t.index ["response_status"], name: "idx_api_key_usages_on_response_status"
    t.index ["used_at"], name: "idx_api_key_usages_on_used_at"
  end

  create_table "api_keys", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id"], name: "idx_api_keys_on_account_id"
    t.index ["account_id"], name: "index_api_keys_on_account_id"
    t.index ["allowed_ips"], name: "idx_api_keys_on_allowed_ips", using: :gin
    t.index ["created_by_id"], name: "index_api_keys_on_created_by_id"
    t.index ["expires_at"], name: "idx_api_keys_on_expires_at"
    t.index ["is_active"], name: "idx_api_keys_on_is_active"
    t.index ["key_digest"], name: "idx_api_keys_on_key_digest_unique", unique: true
    t.index ["key_prefix"], name: "idx_api_keys_on_key_prefix"
    t.index ["key_suffix"], name: "idx_api_keys_on_key_suffix"
    t.index ["permissions"], name: "idx_api_keys_on_permissions", using: :gin
    t.index ["prefix"], name: "idx_api_keys_on_prefix_unique", unique: true
    t.index ["scopes"], name: "idx_api_keys_on_scopes", using: :gin
    t.index ["usage_count"], name: "idx_api_keys_on_usage_count"
    t.check_constraint "rate_limit_per_day IS NULL OR rate_limit_per_day > 0", name: "valid_api_key_daily_limit"
    t.check_constraint "rate_limit_per_hour IS NULL OR rate_limit_per_hour > 0", name: "valid_api_key_hourly_limit"
    t.check_constraint "usage_count >= 0", name: "valid_api_key_usage_count"
  end

  create_table "audit_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "created_at"], name: "idx_audit_logs_on_account_created_at"
    t.index ["account_id"], name: "index_audit_logs_on_account_id"
    t.index ["action"], name: "idx_audit_logs_on_action"
    t.index ["chain_verified_at"], name: "index_audit_logs_on_chain_verified_at"
    t.index ["created_at"], name: "idx_audit_logs_on_created_at"
    t.index ["integrity_hash"], name: "index_audit_logs_on_integrity_hash", unique: true, where: "(integrity_hash IS NOT NULL)"
    t.index ["request_id"], name: "index_audit_logs_on_request_id"
    t.index ["resource_type", "resource_id"], name: "idx_audit_logs_on_resource_type_id"
    t.index ["risk_level"], name: "index_audit_logs_on_risk_level"
    t.index ["sequence_number"], name: "index_audit_logs_on_sequence_number", unique: true, where: "(sequence_number IS NOT NULL)"
    t.index ["severity"], name: "index_audit_logs_on_severity"
    t.index ["user_id"], name: "idx_audit_logs_on_user_id"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "baas_api_keys", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "baas_tenant_id", null: false
    t.datetime "created_at", null: false
    t.string "environment", default: "production", null: false
    t.datetime "expires_at"
    t.string "key_hash", null: false
    t.string "key_prefix", null: false
    t.string "key_type", default: "secret", null: false
    t.datetime "last_used_at"
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.integer "rate_limit_per_day", default: 10000
    t.integer "rate_limit_per_minute", default: 100
    t.text "scopes", default: [], array: true
    t.string "status", default: "active", null: false
    t.bigint "total_requests", default: 0
    t.datetime "updated_at", null: false
    t.index ["baas_tenant_id", "environment"], name: "index_baas_api_keys_on_baas_tenant_id_and_environment"
    t.index ["baas_tenant_id"], name: "index_baas_api_keys_on_baas_tenant_id"
    t.index ["key_hash"], name: "index_baas_api_keys_on_key_hash", unique: true
    t.index ["key_prefix"], name: "index_baas_api_keys_on_key_prefix"
    t.index ["status"], name: "index_baas_api_keys_on_status"
    t.check_constraint "environment::text = ANY (ARRAY['development'::character varying::text, 'staging'::character varying::text, 'production'::character varying::text])", name: "baas_api_keys_environment_check"
    t.check_constraint "key_type::text = ANY (ARRAY['secret'::character varying::text, 'publishable'::character varying::text, 'restricted'::character varying::text])", name: "baas_api_keys_key_type_check"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'revoked'::character varying::text, 'expired'::character varying::text])", name: "baas_api_keys_status_check"
  end

  create_table "baas_billing_configurations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "auto_charge", default: true
    t.boolean "auto_invoice", default: true
    t.uuid "baas_tenant_id", null: false
    t.datetime "created_at", null: false
    t.string "default_tax_rate_id"
    t.integer "default_trial_days", default: 14
    t.integer "dunning_attempts", default: 3
    t.boolean "dunning_enabled", default: true
    t.integer "dunning_interval_days", default: 3
    t.integer "invoice_due_days", default: 30
    t.string "invoice_prefix", default: "INV"
    t.boolean "metered_billing_enabled", default: false
    t.boolean "paypal_connected", default: false
    t.string "paypal_merchant_id"
    t.decimal "platform_fee_percentage", precision: 5, scale: 2, default: "2.9"
    t.jsonb "settings", default: {}
    t.string "stripe_account_id"
    t.string "stripe_account_status", default: "not_connected"
    t.boolean "stripe_connected", default: false
    t.boolean "tax_enabled", default: false
    t.string "tax_provider"
    t.boolean "trial_enabled", default: true
    t.datetime "updated_at", null: false
    t.boolean "usage_billing_enabled", default: false
    t.index ["baas_tenant_id"], name: "index_baas_billing_configurations_on_baas_tenant_id"
    t.index ["stripe_account_id"], name: "index_baas_billing_configurations_on_stripe_account_id", unique: true, where: "(stripe_account_id IS NOT NULL)"
  end

  create_table "baas_customers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "address_line1"
    t.string "address_line2"
    t.uuid "baas_tenant_id", null: false
    t.integer "balance_cents", default: 0
    t.string "city"
    t.string "country"
    t.datetime "created_at", null: false
    t.string "currency", default: "usd"
    t.string "default_payment_method_id"
    t.string "email"
    t.string "external_id", null: false
    t.jsonb "metadata", default: {}
    t.string "name"
    t.string "postal_code"
    t.string "state"
    t.string "status", default: "active", null: false
    t.string "stripe_customer_id"
    t.boolean "tax_exempt", default: false
    t.string "tax_id"
    t.string "tax_id_type"
    t.datetime "updated_at", null: false
    t.index ["baas_tenant_id", "email"], name: "index_baas_customers_on_baas_tenant_id_and_email"
    t.index ["baas_tenant_id", "external_id"], name: "index_baas_customers_on_baas_tenant_id_and_external_id", unique: true
    t.index ["baas_tenant_id"], name: "index_baas_customers_on_baas_tenant_id"
    t.index ["stripe_customer_id"], name: "index_baas_customers_on_stripe_customer_id", unique: true, where: "(stripe_customer_id IS NOT NULL)"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'archived'::character varying::text, 'deleted'::character varying::text])", name: "baas_customers_status_check"
  end

  create_table "baas_invoices", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "amount_due_cents", default: 0
    t.integer "amount_paid_cents", default: 0
    t.uuid "baas_customer_id", null: false
    t.uuid "baas_subscription_id"
    t.uuid "baas_tenant_id", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "usd"
    t.integer "discount_cents", default: 0
    t.datetime "due_date"
    t.string "external_id", null: false
    t.string "hosted_invoice_url"
    t.string "invoice_pdf_url"
    t.jsonb "line_items", default: []
    t.jsonb "metadata", default: {}
    t.string "number"
    t.datetime "paid_at"
    t.date "period_end"
    t.date "period_start"
    t.string "status", default: "draft", null: false
    t.string "stripe_invoice_id"
    t.integer "subtotal_cents", default: 0
    t.integer "tax_cents", default: 0
    t.integer "total_cents", default: 0
    t.datetime "updated_at", null: false
    t.datetime "voided_at"
    t.index ["baas_customer_id"], name: "index_baas_invoices_on_baas_customer_id"
    t.index ["baas_subscription_id"], name: "index_baas_invoices_on_baas_subscription_id"
    t.index ["baas_tenant_id", "external_id"], name: "index_baas_invoices_on_baas_tenant_id_and_external_id", unique: true
    t.index ["baas_tenant_id"], name: "index_baas_invoices_on_baas_tenant_id"
    t.index ["number"], name: "index_baas_invoices_on_number"
    t.index ["status"], name: "index_baas_invoices_on_status"
    t.index ["stripe_invoice_id"], name: "index_baas_invoices_on_stripe_invoice_id", unique: true, where: "(stripe_invoice_id IS NOT NULL)"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'open'::character varying::text, 'paid'::character varying::text, 'void'::character varying::text, 'uncollectible'::character varying::text])", name: "baas_invoices_status_check"
  end

  create_table "baas_subscriptions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "baas_customer_id", null: false
    t.uuid "baas_tenant_id", null: false
    t.string "billing_interval", default: "month", null: false
    t.integer "billing_interval_count", default: 1
    t.boolean "cancel_at_period_end", default: false
    t.datetime "canceled_at"
    t.string "cancellation_reason"
    t.datetime "created_at", null: false
    t.string "currency", default: "usd"
    t.date "current_period_end"
    t.date "current_period_start"
    t.datetime "ended_at"
    t.string "external_id", null: false
    t.jsonb "metadata", default: {}
    t.string "plan_external_id", null: false
    t.integer "quantity", default: 1
    t.string "status", default: "active", null: false
    t.string "stripe_price_id"
    t.string "stripe_subscription_id"
    t.datetime "trial_end"
    t.decimal "unit_amount", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.index ["baas_customer_id"], name: "index_baas_subscriptions_on_baas_customer_id"
    t.index ["baas_tenant_id", "external_id"], name: "index_baas_subscriptions_on_baas_tenant_id_and_external_id", unique: true
    t.index ["baas_tenant_id"], name: "index_baas_subscriptions_on_baas_tenant_id"
    t.index ["status"], name: "index_baas_subscriptions_on_status"
    t.index ["stripe_subscription_id"], name: "index_baas_subscriptions_on_stripe_subscription_id", unique: true, where: "(stripe_subscription_id IS NOT NULL)"
    t.check_constraint "billing_interval::text = ANY (ARRAY['day'::character varying::text, 'week'::character varying::text, 'month'::character varying::text, 'year'::character varying::text])", name: "baas_subscriptions_billing_interval_check"
    t.check_constraint "status::text = ANY (ARRAY['incomplete'::character varying::text, 'incomplete_expired'::character varying::text, 'trialing'::character varying::text, 'active'::character varying::text, 'past_due'::character varying::text, 'canceled'::character varying::text, 'unpaid'::character varying::text, 'paused'::character varying::text])", name: "baas_subscriptions_status_check"
  end

  create_table "baas_tenants", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.date "api_requests_reset_date"
    t.integer "api_requests_today", default: 0
    t.jsonb "branding", default: {}
    t.datetime "created_at", null: false
    t.string "default_currency", default: "usd"
    t.string "environment", default: "production", null: false
    t.integer "max_api_requests_per_day", default: 10000
    t.integer "max_customers", default: 100
    t.integer "max_subscriptions", default: 500
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.string "slug", null: false
    t.string "status", default: "active", null: false
    t.string "tier", default: "starter", null: false
    t.string "timezone", default: "UTC"
    t.bigint "total_customers", default: 0
    t.bigint "total_invoices", default: 0
    t.decimal "total_revenue_processed", precision: 15, scale: 2, default: "0.0"
    t.bigint "total_subscriptions", default: 0
    t.datetime "updated_at", null: false
    t.string "webhook_secret"
    t.string "webhook_url"
    t.index ["account_id"], name: "index_baas_tenants_on_account_id"
    t.index ["slug"], name: "index_baas_tenants_on_slug", unique: true
    t.index ["status"], name: "index_baas_tenants_on_status"
    t.index ["tier"], name: "index_baas_tenants_on_tier"
    t.check_constraint "environment::text = ANY (ARRAY['development'::character varying::text, 'staging'::character varying::text, 'production'::character varying::text])", name: "baas_tenants_environment_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'active'::character varying::text, 'suspended'::character varying::text, 'terminated'::character varying::text])", name: "baas_tenants_status_check"
    t.check_constraint "tier::text = ANY (ARRAY['free'::character varying::text, 'starter'::character varying::text, 'pro'::character varying::text, 'enterprise'::character varying::text])", name: "baas_tenants_tier_check"
  end

  create_table "baas_usage_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action", default: "increment", null: false
    t.uuid "baas_tenant_id", null: false
    t.date "billing_period_end"
    t.date "billing_period_start"
    t.datetime "created_at", null: false
    t.string "customer_external_id", null: false
    t.datetime "event_timestamp", null: false
    t.string "idempotency_key"
    t.string "invoice_id"
    t.jsonb "metadata", default: {}
    t.string "meter_id", null: false
    t.datetime "processed_at"
    t.jsonb "properties", default: {}
    t.decimal "quantity", precision: 15, scale: 4, null: false
    t.string "status", default: "pending", null: false
    t.string "subscription_external_id"
    t.datetime "updated_at", null: false
    t.index ["baas_tenant_id", "customer_external_id"], name: "idx_on_baas_tenant_id_customer_external_id_bcac543050"
    t.index ["baas_tenant_id", "meter_id", "event_timestamp"], name: "idx_on_baas_tenant_id_meter_id_event_timestamp_e13ba829ad"
    t.index ["baas_tenant_id", "status"], name: "index_baas_usage_records_on_baas_tenant_id_and_status"
    t.index ["baas_tenant_id"], name: "index_baas_usage_records_on_baas_tenant_id"
    t.index ["event_timestamp"], name: "index_baas_usage_records_on_event_timestamp"
    t.index ["idempotency_key"], name: "index_baas_usage_records_on_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.check_constraint "action::text = ANY (ARRAY['set'::character varying::text, 'increment'::character varying::text])", name: "baas_usage_records_action_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processed'::character varying::text, 'invoiced'::character varying::text, 'failed'::character varying::text])", name: "baas_usage_records_status_check"
  end

  create_table "background_jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "batch_workflow_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "batch_id", null: false
    t.datetime "completed_at"
    t.integer "completed_workflows", default: 0
    t.jsonb "configuration", default: {}
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.jsonb "error_details", default: {}
    t.integer "failed_workflows", default: 0
    t.jsonb "results", default: []
    t.datetime "started_at"
    t.jsonb "statistics", default: {}
    t.string "status", default: "pending", null: false
    t.integer "successful_workflows", default: 0
    t.integer "total_workflows", default: 0, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["account_id", "created_at"], name: "index_batch_workflow_runs_on_account_id_and_created_at"
    t.index ["account_id", "status"], name: "index_batch_workflow_runs_on_account_id_and_status"
    t.index ["account_id"], name: "index_batch_workflow_runs_on_account_id"
    t.index ["batch_id"], name: "index_batch_workflow_runs_on_batch_id", unique: true
    t.index ["created_at"], name: "index_batch_workflow_runs_on_created_at"
    t.index ["status"], name: "index_batch_workflow_runs_on_status"
    t.index ["user_id"], name: "index_batch_workflow_runs_on_user_id"
    t.check_constraint "(successful_workflows + failed_workflows) <= completed_workflows", name: "batch_workflow_runs_success_failed_check"
    t.check_constraint "completed_workflows <= total_workflows", name: "batch_workflow_runs_completed_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text])", name: "batch_workflow_runs_status_check"
  end

  create_table "blacklisted_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "reason", default: "logout"
    t.string "token", null: false
    t.uuid "user_id", null: false
    t.index ["expires_at"], name: "index_blacklisted_tokens_on_expires_at"
    t.index ["token"], name: "index_blacklisted_tokens_on_token", unique: true
    t.index ["user_id"], name: "index_blacklisted_tokens_on_user_id"
  end

  create_table "chat_blacklists", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.check_constraint "block_type::text = ANY (ARRAY['temporary'::character varying, 'permanent'::character varying]::text[])", name: "chat_blacklists_type_check"
  end

  create_table "chat_channels", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
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
    t.index ["default_agent_id"], name: "index_chat_channels_on_default_agent_id"
    t.index ["platform"], name: "index_chat_channels_on_platform"
    t.index ["status"], name: "index_chat_channels_on_status"
    t.index ["webhook_token"], name: "index_chat_channels_on_webhook_token", unique: true
    t.check_constraint "platform::text = ANY (ARRAY['whatsapp'::character varying, 'telegram'::character varying, 'discord'::character varying, 'slack'::character varying, 'mattermost'::character varying]::text[])", name: "chat_channels_platform_check"
    t.check_constraint "status::text = ANY (ARRAY['connected'::character varying, 'disconnected'::character varying, 'connecting'::character varying, 'error'::character varying]::text[])", name: "chat_channels_status_check"
  end

  create_table "chat_message_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.check_constraint "attachment_type::text = ANY (ARRAY['image'::character varying, 'audio'::character varying, 'video'::character varying, 'document'::character varying]::text[])", name: "chat_attachments_type_check"
  end

  create_table "chat_messages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.check_constraint "delivery_status::text = ANY (ARRAY['pending'::character varying, 'sent'::character varying, 'delivered'::character varying, 'read'::character varying, 'failed'::character varying]::text[])", name: "chat_messages_delivery_status_check"
    t.check_constraint "direction::text = ANY (ARRAY['inbound'::character varying, 'outbound'::character varying]::text[])", name: "chat_messages_direction_check"
    t.check_constraint "message_type::text = ANY (ARRAY['text'::character varying, 'image'::character varying, 'audio'::character varying, 'video'::character varying, 'document'::character varying, 'location'::character varying, 'sticker'::character varying]::text[])", name: "chat_messages_type_check"
  end

  create_table "chat_sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'idle'::character varying, 'closed'::character varying, 'blocked'::character varying]::text[])", name: "chat_sessions_status_check"
  end

  create_table "churn_predictions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.decimal "churn_probability", precision: 5, scale: 4, null: false
    t.decimal "confidence_score", precision: 5, scale: 4
    t.jsonb "contributing_factors", default: []
    t.datetime "created_at", null: false
    t.integer "days_until_churn"
    t.datetime "intervention_at"
    t.boolean "intervention_triggered", default: false
    t.string "model_version", null: false
    t.datetime "predicted_at", null: false
    t.date "predicted_churn_date"
    t.string "prediction_type", default: "monthly"
    t.string "primary_risk_factor"
    t.jsonb "recommended_actions", default: []
    t.string "risk_tier", null: false
    t.uuid "subscription_id"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_churn_predictions_on_account_id"
    t.index ["churn_probability"], name: "index_churn_predictions_on_churn_probability"
    t.index ["predicted_at"], name: "index_churn_predictions_on_predicted_at"
    t.index ["risk_tier"], name: "index_churn_predictions_on_risk_tier"
    t.index ["subscription_id"], name: "index_churn_predictions_on_subscription_id"
    t.check_constraint "prediction_type::text = ANY (ARRAY['weekly'::character varying::text, 'monthly'::character varying::text, 'quarterly'::character varying::text])", name: "churn_predictions_type_check"
    t.check_constraint "risk_tier::text = ANY (ARRAY['critical'::character varying::text, 'high'::character varying::text, 'medium'::character varying::text, 'low'::character varying::text, 'minimal'::character varying::text])", name: "churn_predictions_risk_tier_check"
  end

  create_table "circuit_breaker_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "circuit_breakers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "community_agent_ratings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["community_agent_id", "account_id"], name: "idx_community_ratings_unique_per_account", unique: true
    t.index ["community_agent_id"], name: "index_community_agent_ratings_on_community_agent_id"
    t.index ["rating"], name: "index_community_agent_ratings_on_rating"
    t.index ["user_id"], name: "index_community_agent_ratings_on_user_id"
    t.index ["verified_usage"], name: "index_community_agent_ratings_on_verified_usage"
    t.check_constraint "rating >= 1 AND rating <= 5", name: "community_ratings_range_check"
  end

  create_table "community_agent_reports", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.check_constraint "report_type::text = ANY (ARRAY['malicious'::character varying, 'spam'::character varying, 'inappropriate'::character varying, 'copyright'::character varying, 'other'::character varying]::text[])", name: "community_reports_type_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'investigating'::character varying, 'resolved'::character varying, 'dismissed'::character varying]::text[])", name: "community_reports_status_check"
  end

  create_table "community_agents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["agent_card_id"], name: "index_community_agents_on_agent_card_id"
    t.index ["agent_id"], name: "index_community_agents_on_agent_id"
    t.index ["category"], name: "index_community_agents_on_category"
    t.index ["federation_key"], name: "index_community_agents_on_federation_key", unique: true, where: "(federation_key IS NOT NULL)"
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
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'active'::character varying, 'suspended'::character varying, 'deprecated'::character varying]::text[])", name: "community_agents_status_check"
    t.check_constraint "visibility::text = ANY (ARRAY['public'::character varying, 'unlisted'::character varying, 'private'::character varying]::text[])", name: "community_agents_visibility_check"
  end

  create_table "cookie_consents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "analytics", default: false
    t.datetime "consented_at", null: false
    t.datetime "created_at", null: false
    t.boolean "functional", default: false
    t.string "ip_address"
    t.boolean "marketing", default: false
    t.jsonb "metadata", default: {}
    t.boolean "necessary", default: true, null: false
    t.datetime "updated_at", null: false
    t.datetime "updated_at_user"
    t.string "user_agent"
    t.uuid "user_id"
    t.string "visitor_id"
    t.index ["user_id"], name: "index_cookie_consents_on_user_id", unique: true, where: "(user_id IS NOT NULL)"
    t.index ["visitor_id"], name: "index_cookie_consents_on_visitor_id", unique: true, where: "(visitor_id IS NOT NULL)"
  end

  create_table "customer_health_scores", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.boolean "at_risk", default: false
    t.datetime "calculated_at", null: false
    t.jsonb "component_details", default: {}
    t.datetime "created_at", null: false
    t.decimal "engagement_score", precision: 5, scale: 2
    t.string "health_status", default: "healthy", null: false
    t.jsonb "metrics_snapshot", default: {}
    t.decimal "overall_score", precision: 5, scale: 2, null: false
    t.decimal "payment_score", precision: 5, scale: 2
    t.text "risk_factors", default: [], array: true
    t.string "risk_level", default: "low"
    t.decimal "score_change_30d", precision: 5, scale: 2
    t.decimal "score_change_90d", precision: 5, scale: 2
    t.uuid "subscription_id"
    t.decimal "support_score", precision: 5, scale: 2
    t.decimal "tenure_score", precision: 5, scale: 2
    t.string "trend_direction", default: "stable"
    t.datetime "updated_at", null: false
    t.decimal "usage_score", precision: 5, scale: 2
    t.index ["account_id"], name: "index_customer_health_scores_on_account_id"
    t.index ["at_risk"], name: "index_customer_health_scores_on_at_risk"
    t.index ["calculated_at"], name: "index_customer_health_scores_on_calculated_at"
    t.index ["health_status"], name: "index_customer_health_scores_on_health_status"
    t.index ["overall_score"], name: "index_customer_health_scores_on_overall_score"
    t.index ["subscription_id"], name: "index_customer_health_scores_on_subscription_id"
    t.check_constraint "health_status::text = ANY (ARRAY['critical'::character varying::text, 'at_risk'::character varying::text, 'needs_attention'::character varying::text, 'healthy'::character varying::text, 'thriving'::character varying::text])", name: "customer_health_scores_status_check"
    t.check_constraint "risk_level::text = ANY (ARRAY['critical'::character varying::text, 'high'::character varying::text, 'medium'::character varying::text, 'low'::character varying::text, 'none'::character varying::text])", name: "customer_health_scores_risk_level_check"
    t.check_constraint "trend_direction::text = ANY (ARRAY['improving'::character varying::text, 'stable'::character varying::text, 'declining'::character varying::text, 'critical_decline'::character varying::text])", name: "customer_health_scores_trend_check"
  end

  create_table "data_deletion_requests", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "data_export_requests", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "data_retention_policies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "database_backups", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["backup_type"], name: "idx_database_backups_on_backup_type"
    t.index ["created_by_id"], name: "idx_database_backups_on_created_by_id"
    t.index ["created_by_id"], name: "index_database_backups_on_created_by_id"
    t.index ["started_at"], name: "idx_database_backups_on_started_at"
    t.index ["status"], name: "idx_database_backups_on_status"
    t.check_constraint "backup_type::text = ANY (ARRAY['full'::character varying::text, 'incremental'::character varying::text, 'manual'::character varying::text])", name: "valid_backup_type"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "valid_backup_status"
  end

  create_table "database_restores", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.datetime "created_at", null: false
    t.uuid "permission_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_delegation_id", "permission_id"], name: "index_delegation_permissions_unique", unique: true
    t.index ["account_delegation_id"], name: "index_delegation_permissions_on_account_delegation_id"
    t.index ["permission_id"], name: "index_delegation_permissions_on_permission"
    t.index ["permission_id"], name: "index_delegation_permissions_on_permission_id"
  end

  create_table "devops_ai_configs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "devops_container_instances", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["sandbox_mode"], name: "index_devops_container_instances_on_sandbox_mode"
    t.index ["status"], name: "index_devops_container_instances_on_status"
    t.index ["template_id"], name: "index_devops_container_instances_on_template_id"
    t.index ["triggered_by_id"], name: "index_devops_container_instances_on_triggered_by_id"
    t.index ["trust_level"], name: "index_devops_container_instances_on_trust_level"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'provisioning'::character varying, 'running'::character varying, 'completed'::character varying, 'failed'::character varying, 'cancelled'::character varying, 'timeout'::character varying]::text[])", name: "mcp_instances_status_check"
  end

  create_table "devops_container_templates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.jsonb "allowed_egress_domains", default: []
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
    t.string "image_name", null: false
    t.string "image_tag", default: "latest"
    t.jsonb "input_schema", default: {}
    t.jsonb "labels", default: {}
    t.datetime "last_used_at"
    t.integer "max_retries", default: 3
    t.jsonb "mcp_bridge_config", default: {}
    t.integer "memory_mb", default: 512
    t.string "name", null: false
    t.boolean "network_access", default: false
    t.jsonb "output_schema", default: {}
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
    t.index ["account_id", "name"], name: "index_devops_container_templates_on_account_id_and_name", unique: true, where: "(account_id IS NOT NULL)"
    t.index ["account_id"], name: "index_devops_container_templates_on_account_id"
    t.index ["category"], name: "index_devops_container_templates_on_category"
    t.index ["created_by_id"], name: "index_devops_container_templates_on_created_by_id"
    t.index ["slug"], name: "index_devops_container_templates_on_slug", unique: true
    t.index ["status"], name: "index_devops_container_templates_on_status"
    t.index ["visibility"], name: "index_devops_container_templates_on_visibility"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'deprecated'::character varying, 'archived'::character varying]::text[])", name: "mcp_templates_status_check"
    t.check_constraint "visibility::text = ANY (ARRAY['private'::character varying, 'account'::character varying, 'public'::character varying]::text[])", name: "mcp_templates_visibility_check"
  end

  create_table "devops_docker_activities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.check_constraint "activity_type::text = ANY (ARRAY['create'::character varying, 'start'::character varying, 'stop'::character varying, 'restart'::character varying, 'remove'::character varying, 'pull'::character varying, 'image_remove'::character varying, 'image_tag'::character varying]::text[])", name: "chk_docker_activities_type"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'running'::character varying, 'completed'::character varying, 'failed'::character varying]::text[])", name: "chk_docker_activities_status"
  end

  create_table "devops_docker_containers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["docker_host_id", "docker_container_id"], name: "idx_docker_containers_host_container", unique: true
    t.index ["docker_host_id"], name: "index_devops_docker_containers_on_docker_host_id"
    t.index ["state"], name: "index_devops_docker_containers_on_state"
    t.check_constraint "state::text = ANY (ARRAY['created'::character varying, 'running'::character varying, 'paused'::character varying, 'restarting'::character varying, 'exited'::character varying, 'removing'::character varying, 'dead'::character varying]::text[])", name: "chk_docker_containers_state"
  end

  create_table "devops_docker_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.check_constraint "severity::text = ANY (ARRAY['info'::character varying, 'warning'::character varying, 'error'::character varying, 'critical'::character varying]::text[])", name: "chk_docker_events_severity"
    t.check_constraint "source_type::text = ANY (ARRAY['host'::character varying, 'container'::character varying, 'image'::character varying, 'network'::character varying, 'volume'::character varying]::text[])", name: "chk_docker_events_source_type"
  end

  create_table "devops_docker_hosts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.string "os_type"
    t.string "slug", null: false
    t.string "status", default: "pending", null: false
    t.bigint "storage_bytes"
    t.integer "sync_interval_seconds", default: 60
    t.boolean "tls_verify", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_devops_docker_hosts_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_devops_docker_hosts_on_account_id"
    t.index ["environment"], name: "index_devops_docker_hosts_on_environment"
    t.index ["slug"], name: "index_devops_docker_hosts_on_slug", unique: true
    t.index ["status"], name: "index_devops_docker_hosts_on_status"
    t.check_constraint "environment::text = ANY (ARRAY['staging'::character varying, 'production'::character varying, 'development'::character varying, 'custom'::character varying]::text[])", name: "chk_docker_hosts_environment"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'connected'::character varying, 'disconnected'::character varying, 'error'::character varying, 'maintenance'::character varying]::text[])", name: "chk_docker_hosts_status"
  end

  create_table "devops_docker_images", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["docker_host_id", "docker_image_id"], name: "idx_docker_images_host_image", unique: true
    t.index ["docker_host_id"], name: "index_devops_docker_images_on_docker_host_id"
  end

  create_table "devops_integration_credentials", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "credential_type"], name: "idx_credentials_account_type"
    t.index ["account_id", "name"], name: "index_devops_integration_credentials_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_devops_integration_credentials_on_account_id"
    t.index ["created_by_user_id"], name: "index_devops_integration_credentials_on_created_by_user_id"
    t.index ["credential_type"], name: "index_devops_integration_credentials_on_credential_type"
    t.index ["expires_at"], name: "index_devops_integration_credentials_on_expires_at"
    t.index ["is_active"], name: "index_devops_integration_credentials_on_is_active"
    t.index ["vault_path"], name: "index_devops_integration_credentials_on_vault_path", unique: true, where: "(vault_path IS NOT NULL)"
  end

  create_table "devops_integration_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "created_at"], name: "idx_executions_account_created"
    t.index ["account_id"], name: "index_devops_integration_executions_on_account_id"
    t.index ["execution_id"], name: "index_devops_integration_executions_on_execution_id", unique: true
    t.index ["integration_instance_id", "status"], name: "idx_executions_instance_status"
    t.index ["integration_instance_id"], name: "index_devops_integration_executions_on_integration_instance_id"
    t.index ["parent_execution_id"], name: "index_devops_integration_executions_on_parent_execution_id"
    t.index ["status"], name: "index_devops_integration_executions_on_status"
    t.index ["trigger_type"], name: "index_devops_integration_executions_on_trigger_type"
    t.index ["triggered_by_user_id"], name: "index_devops_integration_executions_on_triggered_by_user_id"
  end

  create_table "devops_integration_instances", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "status"], name: "idx_instances_account_status"
    t.index ["account_id"], name: "index_devops_integration_instances_on_account_id"
    t.index ["created_by_user_id"], name: "index_devops_integration_instances_on_created_by_user_id"
    t.index ["health_status"], name: "index_devops_integration_instances_on_health_status"
    t.index ["integration_credential_id"], name: "idx_on_integration_credential_id_d627796068"
    t.index ["integration_template_id"], name: "index_devops_integration_instances_on_integration_template_id"
    t.index ["status"], name: "index_devops_integration_instances_on_status"
  end

  create_table "devops_integration_templates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.boolean "is_marketplace_published", default: false
    t.boolean "is_public", default: false
    t.datetime "marketplace_approved_at"
    t.text "marketplace_rejection_reason"
    t.string "marketplace_status"
    t.datetime "marketplace_submitted_at"
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
    t.index ["is_marketplace_published", "marketplace_status"], name: "idx_integration_templates_marketplace"
    t.index ["is_public", "is_active"], name: "idx_templates_public_active"
    t.index ["is_public"], name: "index_devops_integration_templates_on_is_public"
    t.index ["slug"], name: "index_devops_integration_templates_on_slug", unique: true
  end

  create_table "devops_pipeline_repositories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ci_cd_pipeline_id", null: false
    t.uuid "ci_cd_repository_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "overrides", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["ci_cd_pipeline_id", "ci_cd_repository_id"], name: "idx_pipeline_repos_on_pipeline_and_repo", unique: true
    t.index ["ci_cd_pipeline_id"], name: "index_devops_pipeline_repositories_on_ci_cd_pipeline_id"
    t.index ["ci_cd_repository_id"], name: "index_devops_pipeline_repositories_on_ci_cd_repository_id"
  end

  create_table "devops_pipeline_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "artifacts", default: [], null: false
    t.uuid "ci_cd_pipeline_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
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
    t.index ["ci_cd_pipeline_id", "run_number"], name: "index_devops_pipeline_runs_on_ci_cd_pipeline_id_and_run_number", unique: true
    t.index ["ci_cd_pipeline_id", "status"], name: "index_devops_pipeline_runs_on_ci_cd_pipeline_id_and_status"
    t.index ["ci_cd_pipeline_id"], name: "index_devops_pipeline_runs_on_ci_cd_pipeline_id"
    t.index ["external_run_id"], name: "index_devops_pipeline_runs_on_external_run_id"
    t.index ["triggered_by_id"], name: "index_devops_pipeline_runs_on_triggered_by_id"
  end

  create_table "devops_pipeline_steps", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "approval_settings", default: {}, null: false, comment: "Approval config: {\"timeout_hours\": 24, \"notification_recipients\": [], \"require_comment\": false}"
    t.uuid "ci_cd_pipeline_id", null: false
    t.text "condition"
    t.jsonb "configuration", default: {}, null: false
    t.boolean "continue_on_error", default: false, null: false
    t.datetime "created_at", null: false
    t.jsonb "inputs", default: {}, null: false
    t.boolean "is_active", default: true, null: false
    t.string "name", null: false
    t.jsonb "outputs", default: [], null: false
    t.integer "position", default: 0, null: false
    t.boolean "requires_approval", default: false, null: false, comment: "When true, step execution pauses and sends notifications for manual approval"
    t.uuid "shared_prompt_template_id"
    t.string "step_type", null: false
    t.datetime "updated_at", null: false
    t.index ["ci_cd_pipeline_id", "name"], name: "index_devops_pipeline_steps_on_ci_cd_pipeline_id_and_name", unique: true
    t.index ["ci_cd_pipeline_id", "position"], name: "index_devops_pipeline_steps_on_ci_cd_pipeline_id_and_position"
    t.index ["ci_cd_pipeline_id"], name: "index_devops_pipeline_steps_on_ci_cd_pipeline_id"
    t.index ["shared_prompt_template_id"], name: "index_devops_pipeline_steps_on_shared_prompt_template_id"
  end

  create_table "devops_pipeline_templates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.boolean "is_marketplace_published", default: false
    t.boolean "is_public", default: false
    t.boolean "is_system", default: false
    t.datetime "marketplace_approved_at"
    t.text "marketplace_rejection_reason"
    t.string "marketplace_status"
    t.datetime "marketplace_submitted_at"
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
    t.index ["is_marketplace_published", "marketplace_status"], name: "idx_cicd_pipeline_templates_marketplace"
    t.index ["is_public"], name: "index_devops_pipeline_templates_on_is_public"
    t.index ["slug"], name: "index_devops_pipeline_templates_on_slug", unique: true
    t.index ["source_pipeline_id"], name: "index_devops_pipeline_templates_on_source_pipeline_id"
    t.index ["status"], name: "index_devops_pipeline_templates_on_status"
  end

  create_table "devops_pipelines", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ai_provider_id"
    t.boolean "allow_concurrent", default: false, null: false
    t.uuid "ci_cd_provider_id"
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.text "description"
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
    t.index ["ci_cd_provider_id"], name: "index_devops_pipelines_on_ci_cd_provider_id"
    t.index ["created_by_id"], name: "index_devops_pipelines_on_created_by_id"
  end

  create_table "devops_providers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "devops_repositories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "ci_cd_provider_id", null: false
    t.datetime "created_at", null: false
    t.string "default_branch", default: "main"
    t.string "external_id"
    t.string "full_name", null: false
    t.boolean "is_active", default: true, null: false
    t.datetime "last_synced_at"
    t.string "name", null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "full_name"], name: "index_devops_repositories_on_account_id_and_full_name", unique: true
    t.index ["account_id"], name: "index_devops_repositories_on_account_id"
    t.index ["ci_cd_provider_id"], name: "index_devops_repositories_on_ci_cd_provider_id"
    t.index ["external_id"], name: "index_devops_repositories_on_external_id"
  end

  create_table "devops_resource_quotas", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "devops_schedules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ci_cd_pipeline_id", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.string "cron_expression", null: false
    t.jsonb "inputs", default: {}, null: false
    t.boolean "is_active", default: true, null: false
    t.datetime "last_run_at"
    t.string "name", null: false
    t.datetime "next_run_at"
    t.string "timezone", default: "UTC"
    t.datetime "updated_at", null: false
    t.index ["ci_cd_pipeline_id", "is_active"], name: "index_devops_schedules_on_ci_cd_pipeline_id_and_is_active"
    t.index ["ci_cd_pipeline_id"], name: "index_devops_schedules_on_ci_cd_pipeline_id"
    t.index ["created_by_id"], name: "index_devops_schedules_on_created_by_id"
    t.index ["next_run_at"], name: "index_devops_schedules_on_next_run_at", where: "(is_active = true)"
  end

  create_table "devops_secret_references", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.check_constraint "secret_type::text = ANY (ARRAY['ai_provider'::character varying, 'mcp_server'::character varying, 'chat_channel'::character varying, 'git_credential'::character varying, 'custom'::character varying]::text[])", name: "mcp_secrets_type_check"
  end

  create_table "devops_step_approval_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["step_execution_id", "status"], name: "idx_approval_tokens_on_step_execution_and_status"
    t.index ["step_execution_id"], name: "index_devops_step_approval_tokens_on_step_execution_id"
    t.index ["token_digest"], name: "index_devops_step_approval_tokens_on_token_digest", unique: true
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'approved'::character varying::text, 'rejected'::character varying::text, 'expired'::character varying::text])", name: "ci_cd_step_approval_tokens_status_check"
  end

  create_table "devops_step_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ci_cd_pipeline_run_id", null: false
    t.uuid "ci_cd_pipeline_step_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "duration_seconds"
    t.text "error_message"
    t.text "logs"
    t.jsonb "outputs", default: {}, null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["ci_cd_pipeline_run_id", "ci_cd_pipeline_step_id"], name: "idx_step_executions_on_run_and_step", unique: true
    t.index ["ci_cd_pipeline_run_id"], name: "index_devops_step_executions_on_ci_cd_pipeline_run_id"
    t.index ["ci_cd_pipeline_step_id"], name: "index_devops_step_executions_on_ci_cd_pipeline_step_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'waiting_approval'::character varying::text, 'success'::character varying::text, 'failure'::character varying::text, 'skipped'::character varying::text])", name: "ci_cd_step_executions_status_check"
  end

  create_table "devops_swarm_clusters", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.check_constraint "environment::text = ANY (ARRAY['staging'::character varying, 'production'::character varying, 'development'::character varying, 'custom'::character varying]::text[])", name: "swarm_clusters_environment_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'connected'::character varying, 'disconnected'::character varying, 'error'::character varying, 'maintenance'::character varying]::text[])", name: "swarm_clusters_status_check"
  end

  create_table "devops_swarm_deployments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.check_constraint "deployment_type::text = ANY (ARRAY['deploy'::character varying, 'update'::character varying, 'scale'::character varying, 'rollback'::character varying, 'remove'::character varying, 'stack_deploy'::character varying, 'stack_remove'::character varying]::text[])", name: "swarm_deployments_type_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'running'::character varying, 'completed'::character varying, 'failed'::character varying, 'cancelled'::character varying]::text[])", name: "swarm_deployments_status_check"
  end

  create_table "devops_swarm_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.check_constraint "severity::text = ANY (ARRAY['info'::character varying, 'warning'::character varying, 'error'::character varying, 'critical'::character varying]::text[])", name: "swarm_events_severity_check"
    t.check_constraint "source_type::text = ANY (ARRAY['node'::character varying, 'service'::character varying, 'task'::character varying, 'cluster'::character varying, 'stack'::character varying]::text[])", name: "swarm_events_source_type_check"
  end

  create_table "devops_swarm_nodes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.check_constraint "availability::text = ANY (ARRAY['active'::character varying, 'pause'::character varying, 'drain'::character varying]::text[])", name: "swarm_nodes_availability_check"
    t.check_constraint "role::text = ANY (ARRAY['manager'::character varying, 'worker'::character varying]::text[])", name: "swarm_nodes_role_check"
    t.check_constraint "status::text = ANY (ARRAY['ready'::character varying, 'down'::character varying, 'disconnected'::character varying, 'unknown'::character varying]::text[])", name: "swarm_nodes_status_check"
  end

  create_table "devops_swarm_services", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["cluster_id", "docker_service_id"], name: "idx_swarm_services_cluster_docker_id", unique: true
    t.index ["cluster_id"], name: "index_devops_swarm_services_on_cluster_id"
    t.index ["service_name"], name: "index_devops_swarm_services_on_service_name"
    t.index ["stack_id"], name: "index_devops_swarm_services_on_stack_id"
    t.check_constraint "mode::text = ANY (ARRAY['replicated'::character varying, 'global'::character varying]::text[])", name: "swarm_services_mode_check"
  end

  create_table "devops_swarm_stacks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "cluster_id", null: false
    t.text "compose_file"
    t.jsonb "compose_variables", default: {}
    t.datetime "created_at", null: false
    t.integer "deploy_count", default: 0
    t.datetime "last_deployed_at"
    t.string "name", null: false
    t.integer "service_count", default: 0
    t.string "slug", null: false
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.index ["cluster_id", "name"], name: "index_devops_swarm_stacks_on_cluster_id_and_name", unique: true
    t.index ["cluster_id"], name: "index_devops_swarm_stacks_on_cluster_id"
    t.index ["slug"], name: "index_devops_swarm_stacks_on_slug"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying, 'deploying'::character varying, 'deployed'::character varying, 'failed'::character varying, 'removing'::character varying, 'removed'::character varying]::text[])", name: "swarm_stacks_status_check"
  end

  create_table "email_deliveries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "external_agents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "name"], name: "idx_external_agents_account_name", unique: true
    t.index ["account_id"], name: "index_external_agents_on_account_id"
    t.index ["agent_card_url"], name: "index_external_agents_on_agent_card_url"
    t.index ["capabilities"], name: "index_external_agents_on_capabilities", using: :gin
    t.index ["created_by_id"], name: "index_external_agents_on_created_by_id"
    t.index ["skills"], name: "index_external_agents_on_skills", using: :gin
    t.index ["slug"], name: "index_external_agents_on_slug", unique: true, where: "(slug IS NOT NULL)"
    t.index ["status"], name: "index_external_agents_on_status"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'inactive'::character varying, 'error'::character varying, 'unreachable'::character varying]::text[])", name: "external_agents_status_check"
  end

  create_table "federation_partners", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "status"], name: "index_federation_partners_on_account_id_and_status"
    t.index ["account_id"], name: "index_federation_partners_on_account_id"
    t.index ["approved_by_id"], name: "index_federation_partners_on_approved_by_id"
    t.index ["created_by_id"], name: "index_federation_partners_on_created_by_id"
    t.index ["organization_id"], name: "index_federation_partners_on_organization_id", unique: true
    t.index ["status"], name: "index_federation_partners_on_status"
    t.index ["trust_level"], name: "index_federation_partners_on_trust_level"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'active'::character varying, 'suspended'::character varying, 'revoked'::character varying]::text[])", name: "federation_partners_status_check"
    t.check_constraint "trust_level >= 1 AND trust_level <= 5", name: "federation_partners_trust_check"
  end

  create_table "file_object_tags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "file_objects", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "category"], name: "index_file_objects_on_account_id_and_category"
    t.index ["account_id", "created_at"], name: "index_file_objects_on_account_id_and_created_at"
    t.index ["account_id", "file_type"], name: "index_file_objects_on_account_id_and_file_type"
    t.index ["account_id", "filename"], name: "index_file_objects_on_account_id_and_filename"
    t.index ["account_id", "is_latest_version"], name: "index_file_objects_on_account_id_and_is_latest_version"
    t.index ["account_id", "visibility"], name: "index_file_objects_on_account_id_and_visibility"
    t.index ["account_id"], name: "index_file_objects_on_account_id"
    t.index ["attachable_type", "attachable_id"], name: "index_file_objects_on_attachable_type_and_attachable_id"
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
    t.check_constraint "category IS NULL OR (category::text = ANY (ARRAY['user_upload'::character varying::text, 'workflow_output'::character varying::text, 'ai_generated'::character varying::text, 'temp'::character varying::text, 'system'::character varying::text, 'import'::character varying::text, 'page_content'::character varying::text, 'sbom_export'::character varying::text, 'attestation_proof'::character varying::text, 'supply_chain_scan_report'::character varying::text, 'vendor_compliance'::character varying::text, 'vendor_assessment'::character varying::text, 'vendor_certificate'::character varying::text]))", name: "file_objects_category_check"
    t.check_constraint "file_type::text = ANY (ARRAY['image'::character varying::text, 'document'::character varying::text, 'video'::character varying::text, 'audio'::character varying::text, 'archive'::character varying::text, 'code'::character varying::text, 'data'::character varying::text, 'other'::character varying::text])", name: "file_objects_file_type_check"
    t.check_constraint "processing_status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "file_objects_processing_status_check"
    t.check_constraint "visibility::text = ANY (ARRAY['private'::character varying::text, 'public'::character varying::text, 'shared'::character varying::text, 'internal'::character varying::text])", name: "file_objects_visibility_check"
  end

  create_table "file_processing_jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.check_constraint "job_type::text = ANY (ARRAY['thumbnail'::character varying::text, 'resize'::character varying::text, 'convert'::character varying::text, 'scan'::character varying::text, 'ocr'::character varying::text, 'metadata_extract'::character varying::text, 'compress'::character varying::text, 'watermark'::character varying::text, 'transform'::character varying::text])", name: "file_processing_jobs_job_type_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text])", name: "file_processing_jobs_status_check"
  end

  create_table "file_shares", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "file_storages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "capabilities", default: {}, null: false
    t.jsonb "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.bigint "files_count", default: 0, null: false
    t.jsonb "health_details", default: {}
    t.string "health_status"
    t.boolean "is_default"
    t.datetime "last_health_check_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.integer "priority", default: 100, null: false
    t.string "provider_type", null: false
    t.bigint "quota_bytes"
    t.string "status", default: "active", null: false
    t.bigint "total_size_bytes", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_file_storages_on_account_id_and_name", unique: true
    t.index ["account_id", "provider_type"], name: "index_file_storages_on_account_id_and_provider_type"
    t.index ["account_id", "status"], name: "index_file_storages_on_account_id_and_status"
    t.index ["account_id"], name: "index_file_storages_on_account_id"
    t.index ["configuration"], name: "index_file_storages_on_configuration", using: :gin
    t.index ["health_status"], name: "index_file_storages_on_health_status"
    t.index ["priority"], name: "index_file_storages_on_priority"
    t.check_constraint "provider_type::text = ANY (ARRAY['local'::character varying::text, 's3'::character varying::text, 'gcs'::character varying::text, 'azure'::character varying::text, 'nfs'::character varying::text, 'smb'::character varying::text, 'ftp'::character varying::text, 'webdav'::character varying::text, 'custom'::character varying::text])", name: "file_storages_provider_type_check"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'maintenance'::character varying::text, 'failed'::character varying::text])", name: "file_storages_status_check"
  end

  create_table "file_tags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "file_versions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "flipper_features", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_flipper_features_on_key", unique: true
  end

  create_table "flipper_gates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "feature_key", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["feature_key", "key", "value"], name: "index_flipper_gates_on_feature_key_and_key_and_value", unique: true
  end

  create_table "gateway_configurations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_value", null: false
    t.string "key_name", limit: 100, null: false
    t.string "provider", limit: 50, null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "key_name"], name: "idx_gateway_configurations_on_provider_key_unique", unique: true
    t.index ["provider"], name: "idx_gateway_configurations_on_provider"
  end

  create_table "gateway_connection_jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "gateway", null: false
    t.string "operation", null: false
    t.jsonb "payload", default: {}
    t.jsonb "response", default: {}
    t.integer "retry_count", default: 0
    t.datetime "scheduled_at"
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.index ["gateway", "operation"], name: "idx_gateway_connection_jobs_on_gateway_operation"
    t.index ["scheduled_at"], name: "idx_gateway_connection_jobs_on_scheduled_at"
    t.index ["status"], name: "idx_gateway_connection_jobs_on_status"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "valid_gateway_job_status"
  end

  create_table "git_pipeline_approvals", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "git_pipeline_jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "git_pipeline_schedules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "git_pipelines", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "git_provider_credentials", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "git_providers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["capabilities"], name: "index_git_providers_on_capabilities", using: :gin
    t.index ["is_active"], name: "index_git_providers_on_is_active"
    t.index ["priority_order"], name: "index_git_providers_on_priority_order"
    t.index ["provider_type"], name: "index_git_providers_on_provider_type"
    t.index ["slug"], name: "index_git_providers_on_slug", unique: true
  end

  create_table "git_repositories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "branch_filter", comment: "Branch filter pattern for webhooks"
    t.string "branch_filter_type", default: "none", comment: "Filter type: none, exact, wildcard, regex"
    t.string "clone_url", limit: 500
    t.datetime "created_at", null: false
    t.string "default_branch", limit: 255, default: "main"
    t.text "description"
    t.string "external_id", limit: 255, null: false
    t.integer "forks_count", default: 0
    t.string "full_name", limit: 500, null: false
    t.uuid "git_provider_credential_id", null: false
    t.boolean "has_issues", default: true
    t.boolean "has_pull_requests", default: true
    t.boolean "has_wiki", default: false
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
    t.index ["account_id", "full_name"], name: "index_git_repositories_on_account_id_and_full_name", unique: true
    t.index ["account_id"], name: "index_git_repositories_on_account_id"
    t.index ["external_id"], name: "index_git_repositories_on_external_id"
    t.index ["git_provider_credential_id"], name: "index_git_repositories_on_git_provider_credential_id"
    t.index ["is_private"], name: "index_git_repositories_on_is_private"
    t.index ["last_synced_at"], name: "index_git_repositories_on_last_synced_at"
    t.index ["owner"], name: "index_git_repositories_on_owner"
    t.index ["topics"], name: "index_git_repositories_on_topics", using: :gin
    t.index ["webhook_configured"], name: "index_git_repositories_on_webhook_configured"
    t.check_constraint "branch_filter_type::text = ANY (ARRAY['none'::character varying, 'exact'::character varying, 'wildcard'::character varying, 'regex'::character varying]::text[])", name: "git_repositories_branch_filter_type_check"
  end

  create_table "git_runners", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["git_provider_credential_id", "external_id"], name: "idx_git_runners_on_credential_and_external_id", unique: true
    t.index ["git_provider_credential_id"], name: "index_git_runners_on_git_provider_credential_id"
    t.index ["git_repository_id"], name: "index_git_runners_on_git_repository_id"
    t.index ["last_seen_at"], name: "index_git_runners_on_last_seen_at"
    t.index ["runner_scope"], name: "index_git_runners_on_runner_scope"
    t.index ["status"], name: "index_git_runners_on_status"
  end

  create_table "git_webhook_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "git_workflow_triggers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_workflow_trigger_id", null: false
    t.string "branch_pattern", default: "*"
    t.datetime "created_at", null: false
    t.jsonb "event_filters", default: {}, null: false
    t.string "event_type", null: false
    t.uuid "git_repository_id"
    t.boolean "is_active", default: true, null: false
    t.datetime "last_triggered_at", precision: nil
    t.jsonb "metadata", default: {}, null: false
    t.string "path_pattern"
    t.jsonb "payload_mapping", default: {}, null: false
    t.string "status", default: "active", null: false
    t.integer "trigger_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["ai_workflow_trigger_id"], name: "index_git_workflow_triggers_on_ai_workflow_trigger_id"
    t.index ["event_type", "is_active"], name: "index_git_workflow_triggers_on_event_type_active"
    t.index ["event_type"], name: "index_git_workflow_triggers_on_event_type"
    t.index ["git_repository_id", "event_type"], name: "index_git_workflow_triggers_on_repo_and_event"
    t.index ["git_repository_id"], name: "index_git_workflow_triggers_on_git_repository_id"
    t.index ["is_active"], name: "index_git_workflow_triggers_on_is_active"
    t.index ["status"], name: "index_git_workflow_triggers_on_status"
  end

  create_table "impersonation_sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["impersonated_user_id"], name: "index_impersonation_sessions_on_impersonated_user"
    t.index ["impersonated_user_id"], name: "index_impersonation_sessions_on_impersonated_user_id"
    t.index ["impersonator_id"], name: "index_impersonation_sessions_on_impersonator"
    t.index ["impersonator_id"], name: "index_impersonation_sessions_on_impersonator_id"
    t.index ["session_token"], name: "index_impersonation_sessions_on_session_token_unique", unique: true
    t.index ["started_at"], name: "index_impersonation_sessions_on_started_at"
  end

  create_table "invitations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["email", "account_id"], name: "index_invitations_on_email_account", unique: true
    t.index ["expires_at"], name: "index_invitations_on_expires_at"
    t.index ["inviter_id"], name: "index_invitations_on_inviter_id"
    t.index ["role_names"], name: "index_invitations_on_role_names", using: :gin
    t.index ["status"], name: "index_invitations_on_status"
    t.index ["token_digest"], name: "index_invitations_on_token_digest", unique: true
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'accepted'::character varying::text, 'expired'::character varying::text, 'cancelled'::character varying::text])", name: "valid_invitation_status"
  end

  create_table "invoice_line_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description", null: false
    t.uuid "invoice_id", null: false
    t.string "line_type", default: "subscription", null: false
    t.jsonb "metadata", default: {}
    t.datetime "period_end"
    t.datetime "period_start"
    t.uuid "plan_id"
    t.integer "quantity", default: 1, null: false
    t.integer "total_amount_cents", null: false
    t.integer "unit_amount_cents", null: false
    t.datetime "updated_at", null: false
    t.index ["invoice_id"], name: "idx_invoice_line_items_on_invoice_id"
    t.index ["invoice_id"], name: "index_invoice_line_items_on_invoice_id"
    t.index ["plan_id"], name: "idx_invoice_line_items_on_plan_id"
    t.index ["plan_id"], name: "index_invoice_line_items_on_plan_id"
  end

  create_table "invoices", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "usd", null: false
    t.datetime "due_at"
    t.string "invoice_number", null: false
    t.datetime "issued_at"
    t.jsonb "metadata", default: {}
    t.datetime "paid_at"
    t.string "paypal_invoice_id", limit: 100
    t.string "status", limit: 50, null: false
    t.string "stripe_invoice_id", limit: 100
    t.uuid "subscription_id"
    t.integer "subtotal_cents", default: 0, null: false
    t.integer "tax_cents", default: 0, null: false
    t.decimal "tax_rate", precision: 5, scale: 4, default: "0.0"
    t.integer "total_cents", default: 0, null: false
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

  create_table "jwt_blacklists", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "knowledge_base_article_tags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "article_id", null: false
    t.datetime "created_at", null: false
    t.uuid "tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["article_id", "tag_id"], name: "index_kb_article_tags_unique", unique: true
    t.index ["tag_id"], name: "idx_kb_article_tags_on_tag_id"
  end

  create_table "knowledge_base_article_views", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["article_id", "viewed_at"], name: "idx_kb_article_views_on_article_viewed_at"
    t.index ["read_to_end"], name: "idx_kb_article_views_on_read_to_end"
    t.index ["session_id"], name: "idx_kb_article_views_on_session_id"
    t.index ["user_id"], name: "idx_kb_article_views_on_user_id"
    t.index ["user_id"], name: "index_knowledge_base_article_views_on_user_id"
    t.index ["viewed_at"], name: "idx_kb_article_views_on_viewed_at"
    t.check_constraint "reading_time_seconds IS NULL OR reading_time_seconds >= 0", name: "valid_kb_reading_time_seconds"
  end

  create_table "knowledge_base_articles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.string "content_type", limit: 100
    t.datetime "created_at", null: false
    t.integer "download_count", default: 0
    t.string "file_path", limit: 1000
    t.bigint "file_size"
    t.string "filename", limit: 255, null: false
    t.jsonb "metadata", default: {}
    t.datetime "updated_at", null: false
    t.uuid "uploaded_by_id", null: false
    t.index ["article_id"], name: "idx_kb_attachments_on_article_id"
    t.index ["download_count"], name: "idx_kb_attachments_on_download_count"
    t.index ["filename"], name: "idx_kb_attachments_on_filename"
    t.index ["uploaded_by_id"], name: "idx_kb_attachments_on_uploaded_by_id"
    t.index ["uploaded_by_id"], name: "index_knowledge_base_attachments_on_uploaded_by_id"
    t.check_constraint "download_count >= 0", name: "valid_kb_download_count"
    t.check_constraint "file_size > 0", name: "valid_kb_attachment_size"
  end

  create_table "knowledge_base_categories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["is_active"], name: "idx_knowledge_base_categories_on_is_active"
    t.index ["is_public"], name: "idx_knowledge_base_categories_on_is_public"
    t.index ["parent_id"], name: "index_knowledge_base_categories_on_parent_id"
    t.index ["slug"], name: "idx_knowledge_base_categories_on_slug_unique", unique: true
    t.index ["sort_order"], name: "idx_knowledge_base_categories_on_sort_order"
  end

  create_table "knowledge_base_comments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["article_id", "status"], name: "idx_kb_comments_on_article_status"
    t.index ["author_id"], name: "idx_kb_comments_on_author_id"
    t.index ["author_id"], name: "index_knowledge_base_comments_on_author_id"
    t.index ["created_at"], name: "idx_kb_comments_on_created_at"
    t.index ["is_helpful_vote"], name: "idx_kb_comments_on_is_helpful_vote"
    t.index ["parent_id"], name: "idx_kb_comments_on_parent_id"
    t.index ["parent_id"], name: "index_knowledge_base_comments_on_parent_id"
    t.index ["status"], name: "idx_kb_comments_on_status"
    t.check_constraint "helpful_count >= 0", name: "valid_kb_comment_helpful_count"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'approved'::character varying::text, 'rejected'::character varying::text, 'spam'::character varying::text])", name: "valid_kb_comment_status"
  end

  create_table "knowledge_base_tags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "color", limit: 7, default: "#6B7280"
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "is_active", default: true
    t.string "name", limit: 100, null: false
    t.string "slug", limit: 100, null: false
    t.datetime "updated_at", null: false
    t.integer "usage_count", default: 0
    t.index ["is_active"], name: "idx_knowledge_base_tags_on_is_active"
    t.index ["name"], name: "idx_knowledge_base_tags_on_name_unique", unique: true
    t.index ["slug"], name: "idx_knowledge_base_tags_on_slug_unique", unique: true
    t.index ["usage_count"], name: "idx_knowledge_base_tags_on_usage_count"
    t.check_constraint "color::text ~ '^#[0-9A-Fa-f]{6}$'::text", name: "valid_kb_tag_color"
    t.check_constraint "usage_count >= 0", name: "valid_kb_tag_usage_count"
  end

  create_table "knowledge_base_workflows", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action", limit: 100, null: false
    t.uuid "article_id", null: false
    t.text "comment"
    t.datetime "created_at", null: false
    t.string "from_status", limit: 50
    t.jsonb "metadata", default: {}
    t.string "to_status", limit: 50
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["action"], name: "idx_kb_workflows_on_action"
    t.index ["article_id", "created_at"], name: "idx_kb_workflows_on_article_created_at"
    t.index ["created_at"], name: "idx_kb_workflows_on_created_at"
    t.index ["from_status"], name: "idx_kb_workflows_on_from_status"
    t.index ["to_status"], name: "idx_kb_workflows_on_to_status"
    t.index ["user_id"], name: "idx_kb_workflows_on_user_id"
    t.index ["user_id"], name: "index_knowledge_base_workflows_on_user_id"
    t.check_constraint "action::text = ANY (ARRAY['create'::character varying::text, 'edit'::character varying::text, 'publish'::character varying::text, 'unpublish'::character varying::text, 'archive'::character varying::text, 'delete'::character varying::text, 'review'::character varying::text])", name: "valid_kb_workflow_action"
  end

  create_table "marketing_campaign_contents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["campaign_id", "channel", "variant_name"], name: "idx_campaign_contents_unique", unique: true
    t.index ["campaign_id"], name: "index_marketing_campaign_contents_on_campaign_id"
    t.index ["channel"], name: "index_marketing_campaign_contents_on_channel"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying, 'approved'::character varying, 'rejected'::character varying]::text[])", name: "marketing_contents_status_check"
  end

  create_table "marketing_campaign_email_lists", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "campaign_id", null: false
    t.datetime "created_at", null: false
    t.uuid "email_list_id", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "email_list_id"], name: "idx_campaign_email_lists_unique", unique: true
    t.index ["campaign_id"], name: "index_marketing_campaign_email_lists_on_campaign_id"
    t.index ["email_list_id"], name: "index_marketing_campaign_email_lists_on_email_list_id"
  end

  create_table "marketing_campaign_metrics", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["campaign_id", "channel", "metric_date"], name: "idx_campaign_metrics_unique", unique: true
    t.index ["campaign_id"], name: "index_marketing_campaign_metrics_on_campaign_id"
    t.index ["metric_date"], name: "index_marketing_campaign_metrics_on_metric_date"
  end

  create_table "marketing_campaigns", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.check_constraint "campaign_type::text = ANY (ARRAY['email'::character varying, 'social'::character varying, 'chat'::character varying, 'sms'::character varying, 'multi_channel'::character varying]::text[])", name: "marketing_campaigns_type_check"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying, 'scheduled'::character varying, 'active'::character varying, 'paused'::character varying, 'completed'::character varying, 'archived'::character varying]::text[])", name: "marketing_campaigns_status_check"
  end

  create_table "marketing_content_calendars", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.check_constraint "entry_type::text = ANY (ARRAY['post'::character varying, 'email'::character varying, 'social'::character varying, 'event'::character varying, 'reminder'::character varying]::text[])", name: "marketing_calendar_type_check"
    t.check_constraint "status::text = ANY (ARRAY['planned'::character varying, 'scheduled'::character varying, 'published'::character varying, 'cancelled'::character varying]::text[])", name: "marketing_calendar_status_check"
  end

  create_table "marketing_email_lists", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.check_constraint "list_type::text = ANY (ARRAY['standard'::character varying, 'dynamic'::character varying, 'segment'::character varying]::text[])", name: "marketing_email_lists_type_check"
  end

  create_table "marketing_email_subscribers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'subscribed'::character varying, 'unsubscribed'::character varying, 'bounced'::character varying, 'complained'::character varying]::text[])", name: "marketing_subscribers_status_check"
  end

  create_table "marketing_social_media_accounts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "platform", "platform_account_id"], name: "idx_social_accounts_unique", unique: true
    t.index ["account_id"], name: "index_marketing_social_media_accounts_on_account_id"
    t.index ["connected_by_id"], name: "index_marketing_social_media_accounts_on_connected_by_id"
    t.index ["platform"], name: "index_marketing_social_media_accounts_on_platform"
    t.index ["status"], name: "index_marketing_social_media_accounts_on_status"
    t.check_constraint "platform::text = ANY (ARRAY['twitter'::character varying, 'linkedin'::character varying, 'facebook'::character varying, 'instagram'::character varying]::text[])", name: "marketing_social_platform_check"
    t.check_constraint "status::text = ANY (ARRAY['connected'::character varying, 'disconnected'::character varying, 'expired'::character varying, 'error'::character varying]::text[])", name: "marketing_social_status_check"
  end

  create_table "marketplace_reviews", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.integer "helpful_count", default: 0, null: false
    t.string "moderation_status", default: "approved", null: false
    t.integer "rating", null: false
    t.uuid "reviewable_id", null: false
    t.string "reviewable_type", null: false
    t.string "title", limit: 255
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.boolean "verified_purchase", default: false, null: false
    t.index ["account_id", "reviewable_type", "reviewable_id"], name: "idx_marketplace_reviews_unique_per_account", unique: true
    t.index ["account_id"], name: "index_marketplace_reviews_on_account_id"
    t.index ["moderation_status"], name: "index_marketplace_reviews_on_moderation_status"
    t.index ["rating"], name: "index_marketplace_reviews_on_rating"
    t.index ["reviewable_type", "reviewable_id"], name: "idx_marketplace_reviews_on_reviewable"
    t.index ["user_id"], name: "index_marketplace_reviews_on_user_id"
  end

  create_table "marketplace_subscriptions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "cancelled_at"
    t.jsonb "configuration", default: {}
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}
    t.datetime "next_billing_at"
    t.string "status", default: "active", null: false
    t.uuid "subscribable_id"
    t.string "subscribable_type"
    t.datetime "subscribed_at", null: false
    t.uuid "subscribed_by_user_id"
    t.string "tier"
    t.datetime "updated_at", null: false
    t.jsonb "usage_metrics", default: {}
    t.index ["account_id"], name: "index_marketplace_subscriptions_on_account_id"
    t.index ["status"], name: "index_marketplace_subscriptions_on_status"
    t.index ["subscribable_type", "subscribable_id"], name: "idx_app_subscriptions_on_subscribable"
    t.index ["subscribed_at"], name: "index_marketplace_subscriptions_on_subscribed_at"
  end

  create_table "mcp_hosted_servers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.decimal "avg_latency_ms", precision: 10, scale: 2
    t.jsonb "build_config", default: {}
    t.jsonb "capabilities", default: []
    t.uuid "container_instance_id"
    t.uuid "container_template_id"
    t.integer "cpu_millicores", default: 500
    t.datetime "created_at", null: false
    t.integer "current_instances", default: 0
    t.string "current_version"
    t.uuid "deployed_by_id"
    t.string "deployment_region", default: "us-east-1"
    t.text "description"
    t.string "entry_point"
    t.jsonb "environment_variables", default: {}
    t.string "health_status", default: "unknown"
    t.boolean "is_published", default: false, null: false
    t.datetime "last_deployed_at"
    t.datetime "last_health_check_at"
    t.integer "marketplace_installs", default: 0
    t.decimal "marketplace_rating", precision: 3, scale: 2
    t.integer "marketplace_reviews_count", default: 0
    t.integer "max_instances", default: 3
    t.uuid "mcp_server_id"
    t.integer "memory_mb", default: 512
    t.jsonb "metadata", default: {}
    t.integer "min_instances", default: 0
    t.decimal "monthly_subscription_price", precision: 10, scale: 2
    t.string "name", null: false
    t.decimal "price_per_request", precision: 10, scale: 6
    t.string "runtime", default: "node", null: false
    t.string "runtime_version"
    t.string "server_type", default: "custom", null: false
    t.string "source_branch"
    t.text "source_code"
    t.string "source_commit"
    t.string "source_type", null: false
    t.string "source_url"
    t.string "status", default: "pending", null: false
    t.integer "timeout_seconds", default: 30
    t.jsonb "tools_manifest", default: []
    t.decimal "total_cost_usd", precision: 10, scale: 4, default: "0.0"
    t.bigint "total_errors", default: 0
    t.bigint "total_requests", default: 0
    t.datetime "updated_at", null: false
    t.integer "version_count", default: 1
    t.string "visibility", default: "private", null: false
    t.index ["account_id", "name"], name: "index_mcp_hosted_servers_on_account_id_and_name", unique: true
    t.index ["account_id", "status"], name: "index_mcp_hosted_servers_on_account_id_and_status"
    t.index ["account_id"], name: "index_mcp_hosted_servers_on_account_id"
    t.index ["container_instance_id"], name: "index_mcp_hosted_servers_on_container_instance_id"
    t.index ["container_template_id"], name: "index_mcp_hosted_servers_on_container_template_id"
    t.index ["deployed_by_id"], name: "index_mcp_hosted_servers_on_deployed_by_id"
    t.index ["health_status"], name: "index_mcp_hosted_servers_on_health_status"
    t.index ["is_published"], name: "index_mcp_hosted_servers_on_is_published"
    t.index ["mcp_server_id"], name: "index_mcp_hosted_servers_on_mcp_server_id"
    t.index ["server_type"], name: "index_mcp_hosted_servers_on_server_type"
    t.index ["status"], name: "index_mcp_hosted_servers_on_status"
    t.index ["visibility"], name: "index_mcp_hosted_servers_on_visibility"
    t.check_constraint "source_type::text = ANY (ARRAY['git'::character varying::text, 'upload'::character varying::text, 'inline'::character varying::text, 'registry'::character varying::text])", name: "check_mcp_source_type"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'building'::character varying::text, 'deploying'::character varying::text, 'running'::character varying::text, 'stopped'::character varying::text, 'failed'::character varying::text, 'deleted'::character varying::text])", name: "check_mcp_server_status"
    t.check_constraint "visibility::text = ANY (ARRAY['private'::character varying::text, 'team'::character varying::text, 'public'::character varying::text, 'marketplace'::character varying::text])", name: "check_mcp_server_visibility"
  end

  create_table "mcp_server_deployments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "build_completed_at"
    t.integer "build_duration_seconds"
    t.text "build_logs"
    t.datetime "build_started_at"
    t.datetime "created_at", null: false
    t.uuid "deployed_by_id"
    t.datetime "deployment_completed_at"
    t.integer "deployment_duration_seconds"
    t.text "deployment_logs"
    t.datetime "deployment_started_at"
    t.string "deployment_type", default: "manual", null: false
    t.string "error_message"
    t.uuid "hosted_server_id", null: false
    t.boolean "is_rollback", default: false, null: false
    t.jsonb "metadata", default: {}
    t.uuid "rollback_from_deployment_id"
    t.string "source_commit"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "version", null: false
    t.index ["deployed_by_id"], name: "index_mcp_server_deployments_on_deployed_by_id"
    t.index ["hosted_server_id", "created_at"], name: "idx_on_hosted_server_id_created_at_139f51691d"
    t.index ["hosted_server_id"], name: "index_mcp_server_deployments_on_hosted_server_id"
    t.index ["status"], name: "index_mcp_server_deployments_on_status"
    t.index ["version"], name: "index_mcp_server_deployments_on_version"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'building'::character varying::text, 'deploying'::character varying::text, 'running'::character varying::text, 'failed'::character varying::text, 'rolled_back'::character varying::text, 'superseded'::character varying::text])", name: "check_deployment_status"
  end

  create_table "mcp_server_metrics", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "active_instances"
    t.decimal "avg_latency_ms", precision: 10, scale: 2
    t.decimal "bandwidth_cost_usd", precision: 10, scale: 6
    t.decimal "compute_cost_usd", precision: 10, scale: 6
    t.decimal "cpu_usage_percent", precision: 5, scale: 2
    t.datetime "created_at", null: false
    t.integer "failed_requests", default: 0
    t.string "granularity", default: "minute", null: false
    t.uuid "hosted_server_id", null: false
    t.decimal "memory_usage_percent", precision: 5, scale: 2
    t.bigint "memory_used_bytes"
    t.decimal "p50_latency_ms", precision: 10, scale: 2
    t.decimal "p95_latency_ms", precision: 10, scale: 2
    t.decimal "p99_latency_ms", precision: 10, scale: 2
    t.datetime "recorded_at", null: false
    t.integer "successful_requests", default: 0
    t.integer "timeout_requests", default: 0
    t.decimal "total_cost_usd", precision: 10, scale: 6
    t.integer "total_requests", default: 0
    t.datetime "updated_at", null: false
    t.index ["granularity", "recorded_at"], name: "index_mcp_server_metrics_on_granularity_and_recorded_at"
    t.index ["hosted_server_id", "recorded_at"], name: "index_mcp_server_metrics_on_hosted_server_id_and_recorded_at"
    t.index ["hosted_server_id"], name: "index_mcp_server_metrics_on_hosted_server_id"
    t.index ["recorded_at"], name: "index_mcp_server_metrics_on_recorded_at"
  end

  create_table "mcp_server_subscriptions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.datetime "current_period_end"
    t.datetime "current_period_start"
    t.datetime "expires_at"
    t.uuid "hosted_server_id", null: false
    t.jsonb "metadata", default: {}
    t.decimal "monthly_price_usd", precision: 10, scale: 2, default: "0.0"
    t.integer "monthly_request_limit"
    t.integer "requests_used_this_month", default: 0
    t.string "status", default: "active", null: false
    t.datetime "subscribed_at", null: false
    t.string "subscription_type", default: "free", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "hosted_server_id"], name: "idx_mcp_subscriptions_account_server", unique: true
    t.index ["account_id"], name: "index_mcp_server_subscriptions_on_account_id"
    t.index ["hosted_server_id"], name: "index_mcp_server_subscriptions_on_hosted_server_id"
    t.index ["status"], name: "index_mcp_server_subscriptions_on_status"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'paused'::character varying::text, 'cancelled'::character varying::text, 'expired'::character varying::text])", name: "check_mcp_subscription_status"
  end

  create_table "mcp_servers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "mcp_tool_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["mcp_tool_id", "created_at"], name: "index_mcp_tool_executions_on_mcp_tool_id_and_created_at"
    t.index ["mcp_tool_id"], name: "index_mcp_tool_executions_on_mcp_tool_id"
    t.index ["user_id", "created_at"], name: "index_mcp_tool_executions_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_mcp_tool_executions_on_user_id"
  end

  create_table "mcp_tools", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "missing_payment_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "usd", null: false
    t.datetime "detected_at", null: false
    t.string "external_payment_id", null: false
    t.string "gateway", null: false
    t.datetime "gateway_created_at"
    t.jsonb "gateway_data", default: {}
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_missing_payment_logs_on_account_id"
    t.index ["detected_at"], name: "idx_missing_payment_logs_on_detected_at"
    t.index ["gateway", "external_payment_id"], name: "idx_missing_payment_logs_on_gateway_external_id_unique", unique: true
    t.index ["status"], name: "idx_missing_payment_logs_on_status"
    t.check_constraint "amount_cents > 0", name: "valid_missing_payment_amount"
  end

  create_table "notifications", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["user_id", "created_at"], name: "index_notifications_on_user_id_and_created_at"
    t.index ["user_id", "read_at"], name: "index_notifications_on_user_id_and_read_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "oauth_access_grants", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "oauth_access_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "oauth_applications", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["owner_type", "owner_id"], name: "index_oauth_applications_on_owner"
    t.index ["status"], name: "index_oauth_applications_on_status"
    t.index ["trusted"], name: "index_oauth_applications_on_trusted"
    t.index ["uid"], name: "index_oauth_applications_on_uid", unique: true
  end

  create_table "pages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "author_id"
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
    t.index ["author_id"], name: "index_pages_on_author_id"
    t.index ["is_public"], name: "idx_pages_on_is_public"
    t.index ["published_at"], name: "idx_pages_on_published_at"
    t.index ["slug"], name: "idx_pages_on_slug_unique", unique: true
    t.index ["status"], name: "idx_pages_on_status"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'published'::character varying::text, 'archived'::character varying::text])", name: "valid_page_status"
  end

  create_table "password_histories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "password_digest", null: false
    t.uuid "user_id", null: false
    t.index ["created_at"], name: "index_password_histories_on_created_at"
    t.index ["user_id"], name: "index_password_histories_on_user_id"
  end

  create_table "payment_methods", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "brand", limit: 50
    t.string "cardholder_name"
    t.datetime "created_at", null: false
    t.integer "exp_month"
    t.integer "exp_year"
    t.string "external_id", null: false
    t.string "gateway", limit: 50, null: false
    t.boolean "is_active", default: true
    t.boolean "is_default", default: false
    t.string "last_four", limit: 4
    t.jsonb "metadata", default: {}
    t.string "payment_type", limit: 50, null: false
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
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "usd", null: false
    t.string "external_id"
    t.datetime "failed_at"
    t.text "failure_reason"
    t.string "gateway", limit: 50, null: false
    t.jsonb "gateway_response", default: {}
    t.uuid "invoice_id"
    t.jsonb "metadata", default: {}
    t.uuid "payment_method_id"
    t.datetime "processed_at"
    t.string "status", limit: 50, null: false
    t.uuid "subscription_id"
    t.string "transaction_type", limit: 50
    t.datetime "updated_at", null: false
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
    t.string "action", limit: 100
    t.string "category", limit: 50, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", limit: 100, null: false
    t.string "resource", limit: 100
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_permissions_on_category"
    t.index ["name"], name: "index_permissions_on_name", unique: true
    t.index ["resource", "action", "category"], name: "idx_permissions_on_resource_action_category_unique", unique: true
    t.check_constraint "category::text = ANY (ARRAY['resource'::character varying::text, 'admin'::character varying::text, 'system'::character varying::text])", name: "valid_permission_category"
  end

  create_table "plans", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "annual_discount_percent", precision: 5, scale: 2, default: "0.0"
    t.string "billing_cycle", limit: 20, default: "monthly", null: false
    t.string "billing_interval", limit: 20, default: "monthly", null: false
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "USD"
    t.jsonb "default_roles", default: []
    t.text "description"
    t.jsonb "features", default: {}
    t.boolean "has_annual_discount", default: false, null: false
    t.boolean "has_promotional_discount", default: false, null: false
    t.boolean "has_volume_discount", default: false, null: false
    t.boolean "is_active", default: true, null: false
    t.boolean "is_public", default: true, null: false
    t.jsonb "limits", default: {}
    t.jsonb "metadata", default: {}
    t.string "name", limit: 100, null: false
    t.string "paypal_plan_id"
    t.integer "price_cents", default: 0, null: false
    t.string "promotional_discount_code"
    t.datetime "promotional_discount_end"
    t.decimal "promotional_discount_percent", precision: 5, scale: 2, default: "0.0"
    t.datetime "promotional_discount_start"
    t.string "slug", limit: 100, null: false
    t.string "status", limit: 20, default: "active", null: false
    t.integer "trial_days", default: 0
    t.integer "trial_period_days", default: 0
    t.datetime "updated_at", null: false
    t.jsonb "volume_discount_tiers", default: []
    t.index ["billing_interval"], name: "idx_plans_on_billing_interval"
    t.index ["is_active"], name: "idx_plans_on_is_active"
    t.index ["is_public"], name: "idx_plans_on_is_public"
    t.index ["slug"], name: "idx_plans_on_slug_unique", unique: true
    t.check_constraint "billing_interval::text = ANY (ARRAY['monthly'::character varying::text, 'yearly'::character varying::text, 'one_time'::character varying::text])", name: "valid_billing_interval"
    t.check_constraint "price_cents >= 0", name: "valid_price"
  end

  create_table "reconciliation_flags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "amount_cents", precision: 15, scale: 2
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.string "flag_type", null: false
    t.jsonb "metadata", default: {}
    t.uuid "reconciliation_report_id", null: false
    t.text "resolution_notes"
    t.datetime "resolved_at"
    t.uuid "resolved_by_id"
    t.string "severity", default: "medium"
    t.string "status", default: "open"
    t.string "transaction_id"
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
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.jsonb "findings", default: {}
    t.uuid "investigator_id", null: false
    t.text "notes"
    t.uuid "reconciliation_flag_id", null: false
    t.datetime "started_at", null: false
    t.string "status", default: "open"
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
    t.datetime "created_at", null: false
    t.date "date_range_end", null: false
    t.date "date_range_start", null: false
    t.integer "discrepancies_count", default: 0
    t.integer "discrepancies_found", default: 0
    t.string "gateway", null: false
    t.integer "high_severity_count", default: 0
    t.integer "matched_transactions", default: 0
    t.integer "medium_severity_count", default: 0
    t.jsonb "metadata", default: {}
    t.date "reconciliation_date", null: false
    t.string "reconciliation_type", null: false
    t.date "report_date", null: false
    t.string "report_type", null: false
    t.string "status", default: "pending"
    t.text "summary"
    t.decimal "total_amount_cents", precision: 15, scale: 2, default: "0.0"
    t.integer "total_transactions", default: 0
    t.integer "unmatched_transactions", default: 0
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
    t.index ["account_id", "report_type"], name: "idx_report_requests_on_account_report_type"
    t.index ["account_id"], name: "index_report_requests_on_account_id"
    t.index ["expires_at"], name: "idx_report_requests_on_expires_at"
    t.index ["requested_at"], name: "idx_report_requests_on_requested_at"
    t.index ["requested_by_id"], name: "idx_report_requests_on_requested_by_id"
    t.index ["requested_by_id"], name: "index_report_requests_on_requested_by_id"
    t.index ["status"], name: "idx_report_requests_on_status"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'generating'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'expired'::character varying::text, 'cancelled'::character varying::text])", name: "valid_report_request_status"
  end

  create_table "reseller_commissions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "available_at"
    t.decimal "commission_amount", precision: 15, scale: 2, null: false
    t.decimal "commission_percentage", precision: 5, scale: 2, null: false
    t.string "commission_type", null: false
    t.datetime "created_at", null: false
    t.datetime "earned_at", null: false
    t.decimal "gross_amount", precision: 15, scale: 2, null: false
    t.jsonb "metadata", default: {}
    t.datetime "paid_at"
    t.uuid "payout_id"
    t.uuid "referred_account_id", null: false
    t.uuid "reseller_id", null: false
    t.uuid "source_id"
    t.string "source_type", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["commission_type"], name: "index_reseller_commissions_on_commission_type"
    t.index ["payout_id"], name: "index_reseller_commissions_on_payout_id"
    t.index ["referred_account_id"], name: "index_reseller_commissions_on_referred_account_id"
    t.index ["reseller_id", "earned_at"], name: "index_reseller_commissions_on_reseller_id_and_earned_at"
    t.index ["reseller_id", "status"], name: "index_reseller_commissions_on_reseller_id_and_status"
    t.index ["reseller_id"], name: "index_reseller_commissions_on_reseller_id"
    t.index ["source_type", "source_id"], name: "index_reseller_commissions_on_source_type_and_source_id"
    t.index ["status"], name: "index_reseller_commissions_on_status"
    t.check_constraint "commission_type::text = ANY (ARRAY['signup_bonus'::character varying::text, 'recurring'::character varying::text, 'one_time'::character varying::text, 'upgrade_bonus'::character varying::text])", name: "check_commission_type"
    t.check_constraint "source_type::text = ANY (ARRAY['subscription'::character varying::text, 'payment'::character varying::text, 'credit_purchase'::character varying::text, 'plan_upgrade'::character varying::text])", name: "check_commission_source_type"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'available'::character varying::text, 'paid'::character varying::text, 'cancelled'::character varying::text, 'clawed_back'::character varying::text])", name: "check_commission_status"
  end

  create_table "reseller_payouts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "amount", precision: 15, scale: 2, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.datetime "failed_at"
    t.text "failure_reason"
    t.decimal "fee", precision: 15, scale: 2, default: "0.0", null: false
    t.jsonb "metadata", default: {}
    t.decimal "net_amount", precision: 15, scale: 2, null: false
    t.jsonb "payout_details", default: {}
    t.string "payout_method", null: false
    t.string "payout_reference", null: false
    t.datetime "processed_at"
    t.uuid "processed_by_id"
    t.string "provider_reference"
    t.datetime "requested_at", null: false
    t.uuid "reseller_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["payout_reference"], name: "index_reseller_payouts_on_payout_reference", unique: true
    t.index ["processed_by_id"], name: "index_reseller_payouts_on_processed_by_id"
    t.index ["requested_at"], name: "index_reseller_payouts_on_requested_at"
    t.index ["reseller_id", "status"], name: "index_reseller_payouts_on_reseller_id_and_status"
    t.index ["reseller_id"], name: "index_reseller_payouts_on_reseller_id"
    t.index ["status"], name: "index_reseller_payouts_on_status"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text])", name: "check_payout_status"
  end

  create_table "reseller_referrals", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "churned_at"
    t.datetime "created_at", null: false
    t.datetime "first_payment_at"
    t.jsonb "metadata", default: {}
    t.string "referral_code_used", null: false
    t.uuid "referred_account_id", null: false
    t.datetime "referred_at", null: false
    t.uuid "reseller_id", null: false
    t.string "status", default: "active", null: false
    t.decimal "total_commission_earned", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "total_revenue", precision: 15, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.index ["referral_code_used"], name: "index_reseller_referrals_on_referral_code_used"
    t.index ["referred_account_id"], name: "index_reseller_referrals_on_referred_account_id", unique: true
    t.index ["reseller_id", "status"], name: "index_reseller_referrals_on_reseller_id_and_status"
    t.index ["reseller_id"], name: "index_reseller_referrals_on_reseller_id"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'churned'::character varying::text, 'cancelled'::character varying::text])", name: "check_referral_status"
  end

  create_table "resellers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "activated_at"
    t.integer "active_referrals", default: 0, null: false
    t.datetime "approved_at"
    t.uuid "approved_by_id"
    t.jsonb "branding", default: {}
    t.decimal "commission_percentage", precision: 5, scale: 2, default: "10.0", null: false
    t.string "company_name", null: false
    t.string "contact_email", null: false
    t.string "contact_phone"
    t.datetime "created_at", null: false
    t.decimal "lifetime_earnings", precision: 15, scale: 2, default: "0.0", null: false
    t.jsonb "payout_details", default: {}
    t.string "payout_method", default: "bank_transfer"
    t.decimal "pending_payout", precision: 15, scale: 2, default: "0.0", null: false
    t.uuid "primary_user_id", null: false
    t.string "referral_code", null: false
    t.string "status", default: "pending", null: false
    t.string "tax_id"
    t.string "tier", default: "bronze", null: false
    t.decimal "total_paid_out", precision: 15, scale: 2, default: "0.0", null: false
    t.integer "total_referrals", default: 0, null: false
    t.decimal "total_revenue_generated", precision: 15, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.string "website_url"
    t.index ["account_id"], name: "index_resellers_on_account_id", unique: true
    t.index ["approved_by_id"], name: "index_resellers_on_approved_by_id"
    t.index ["primary_user_id"], name: "index_resellers_on_primary_user_id"
    t.index ["referral_code"], name: "index_resellers_on_referral_code", unique: true
    t.index ["status", "tier"], name: "index_resellers_on_status_and_tier"
    t.index ["status"], name: "index_resellers_on_status"
    t.index ["tier"], name: "index_resellers_on_tier"
    t.check_constraint "payout_method::text = ANY (ARRAY['bank_transfer'::character varying::text, 'paypal'::character varying::text, 'stripe'::character varying::text, 'check'::character varying::text, 'wire'::character varying::text])", name: "check_reseller_payout_method"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'approved'::character varying::text, 'active'::character varying::text, 'suspended'::character varying::text, 'terminated'::character varying::text])", name: "check_reseller_status"
    t.check_constraint "tier::text = ANY (ARRAY['bronze'::character varying::text, 'silver'::character varying::text, 'gold'::character varying::text, 'platinum'::character varying::text])", name: "check_reseller_tier"
  end

  create_table "revenue_forecasts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.decimal "accuracy_percentage", precision: 5, scale: 2
    t.decimal "actual_mrr", precision: 15, scale: 2
    t.jsonb "assumptions", default: {}
    t.decimal "confidence_level", precision: 5, scale: 2, default: "95.0"
    t.jsonb "contributing_factors", default: []
    t.datetime "created_at", null: false
    t.date "forecast_date", null: false
    t.string "forecast_period", null: false
    t.string "forecast_type", null: false
    t.datetime "generated_at", null: false
    t.decimal "lower_bound", precision: 15, scale: 2
    t.string "model_version"
    t.decimal "projected_arr", precision: 15, scale: 2
    t.integer "projected_churned_customers"
    t.decimal "projected_churned_revenue", precision: 15, scale: 2
    t.decimal "projected_expansion_revenue", precision: 15, scale: 2
    t.decimal "projected_mrr", precision: 15, scale: 2
    t.decimal "projected_net_revenue", precision: 15, scale: 2
    t.integer "projected_new_customers"
    t.decimal "projected_new_revenue", precision: 15, scale: 2
    t.integer "projected_total_customers"
    t.datetime "updated_at", null: false
    t.decimal "upper_bound", precision: 15, scale: 2
    t.index ["account_id"], name: "index_revenue_forecasts_on_account_id"
    t.index ["forecast_date", "forecast_type"], name: "index_revenue_forecasts_on_forecast_date_and_forecast_type"
    t.index ["forecast_period"], name: "index_revenue_forecasts_on_forecast_period"
    t.check_constraint "forecast_period::text = ANY (ARRAY['weekly'::character varying::text, 'monthly'::character varying::text, 'quarterly'::character varying::text, 'yearly'::character varying::text])", name: "revenue_forecasts_period_check"
    t.check_constraint "forecast_type::text = ANY (ARRAY['mrr'::character varying::text, 'arr'::character varying::text, 'customers'::character varying::text, 'revenue'::character varying::text])", name: "revenue_forecasts_type_check"
  end

  create_table "revenue_snapshots", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.integer "active_subscriptions", default: 0
    t.integer "arpu_cents", default: 0
    t.integer "arr_cents", default: 0
    t.integer "churned_customers_count", default: 0
    t.integer "churned_revenue_cents", default: 0
    t.integer "churned_subscriptions", default: 0
    t.datetime "created_at", null: false
    t.decimal "customer_churn_rate_percentage", precision: 5, scale: 2, default: "0.0"
    t.decimal "growth_rate_percentage", precision: 5, scale: 2, default: "0.0"
    t.integer "ltv_cents", default: 0
    t.jsonb "metadata", default: {}
    t.integer "mrr_cents", default: 0
    t.integer "new_customers_count", default: 0
    t.integer "new_revenue_cents", default: 0
    t.integer "new_subscriptions", default: 0
    t.string "period_type", limit: 20, null: false
    t.decimal "revenue_churn_rate_percentage", precision: 5, scale: 2, default: "0.0"
    t.date "snapshot_date", null: false
    t.integer "total_customers_count", default: 0
    t.integer "total_revenue_cents", default: 0
    t.datetime "updated_at", null: false
    t.index ["account_id", "snapshot_date", "period_type"], name: "index_revenue_snapshots_unique", unique: true
    t.index ["account_id"], name: "index_revenue_snapshots_on_account_id"
    t.index ["period_type"], name: "idx_revenue_snapshots_on_period_type"
    t.index ["snapshot_date"], name: "idx_revenue_snapshots_on_snapshot_date"
    t.check_constraint "period_type::text = ANY (ARRAY['daily'::character varying::text, 'weekly'::character varying::text, 'monthly'::character varying::text, 'yearly'::character varying::text])", name: "valid_period_type"
  end

  create_table "role_permissions", id: false, force: :cascade do |t|
    t.datetime "granted_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.uuid "permission_id", null: false
    t.uuid "role_id", null: false
    t.index ["permission_id"], name: "index_role_permissions_on_permission_id"
    t.index ["permission_id"], name: "index_role_perms_on_permission"
    t.index ["role_id", "permission_id"], name: "index_role_perms_unique", unique: true
    t.index ["role_id"], name: "index_role_permissions_on_role_id"
  end

  create_table "roles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "display_name", limit: 100
    t.boolean "immutable", default: false, null: false
    t.boolean "is_system", default: false, null: false
    t.string "name", limit: 100, null: false
    t.string "role_type", limit: 20
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_roles_on_name", unique: true
  end

  create_table "scheduled_reports", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "report_type"], name: "idx_scheduled_reports_on_account_report_type"
    t.index ["account_id"], name: "index_scheduled_reports_on_account_id"
    t.index ["created_by_id"], name: "index_scheduled_reports_on_created_by_id"
    t.index ["frequency"], name: "idx_scheduled_reports_on_frequency"
    t.index ["is_active"], name: "idx_scheduled_reports_on_is_active"
    t.index ["next_run_at"], name: "idx_scheduled_reports_on_next_run_at"
    t.check_constraint "frequency::text = ANY (ARRAY['daily'::character varying::text, 'weekly'::character varying::text, 'monthly'::character varying::text, 'quarterly'::character varying::text, 'yearly'::character varying::text])", name: "valid_report_frequency"
  end

  create_table "scheduled_tasks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["is_active"], name: "idx_scheduled_tasks_on_is_active"
    t.index ["last_run_at"], name: "idx_scheduled_tasks_on_last_run_at"
    t.index ["name"], name: "idx_scheduled_tasks_on_name_unique", unique: true
    t.index ["next_run_at"], name: "idx_scheduled_tasks_on_next_run_at"
    t.index ["task_type"], name: "idx_scheduled_tasks_on_task_type"
  end

  create_table "shared_prompt_templates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "category", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.text "description"
    t.string "domain", default: "general", null: false
    t.boolean "is_active", default: true, null: false
    t.boolean "is_marketplace_published", default: false
    t.boolean "is_system", default: false, null: false
    t.datetime "marketplace_approved_at"
    t.text "marketplace_rejection_reason"
    t.string "marketplace_status"
    t.datetime "marketplace_submitted_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.uuid "parent_template_id"
    t.decimal "rating", precision: 3, scale: 2, default: "0.0"
    t.integer "rating_count", default: 0
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.jsonb "variables", default: [], null: false
    t.integer "version", default: 1, null: false
    t.index ["account_id", "category"], name: "index_shared_prompt_templates_on_account_id_and_category"
    t.index ["account_id", "domain"], name: "index_shared_prompt_templates_on_account_id_and_domain"
    t.index ["account_id", "slug"], name: "index_shared_prompt_templates_on_account_id_and_slug", unique: true
    t.index ["is_active"], name: "index_shared_prompt_templates_on_is_active"
    t.index ["is_marketplace_published", "marketplace_status"], name: "idx_shared_prompt_templates_marketplace"
    t.index ["is_system"], name: "index_shared_prompt_templates_on_is_system"
    t.index ["parent_template_id"], name: "index_shared_prompt_templates_on_parent_template_id"
  end

  create_table "site_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "category", limit: 100
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "is_public", default: true
    t.string "key", limit: 255, null: false
    t.string "setting_type", limit: 50, default: "string"
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["category"], name: "idx_site_settings_on_category"
    t.index ["is_public"], name: "idx_site_settings_on_is_public"
    t.index ["key"], name: "idx_site_settings_on_key_unique", unique: true
    t.index ["setting_type"], name: "idx_site_settings_on_setting_type"
    t.check_constraint "setting_type::text = ANY (ARRAY['string'::character varying::text, 'text'::character varying::text, 'integer'::character varying::text, 'boolean'::character varying::text, 'json'::character varying::text, 'array'::character varying::text])", name: "valid_site_setting_type"
  end

  create_table "subscriptions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "canceled_at"
    t.datetime "created_at", null: false
    t.datetime "current_period_end"
    t.datetime "current_period_start"
    t.datetime "ended_at"
    t.jsonb "metadata", default: {}
    t.string "paypal_agreement_id"
    t.string "paypal_plan_id"
    t.string "paypal_subscription_id", limit: 100
    t.uuid "plan_id", null: false
    t.integer "quantity", default: 1, null: false
    t.string "status", limit: 50, null: false
    t.string "stripe_subscription_id", limit: 100
    t.datetime "trial_end"
    t.datetime "trial_start"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_subscriptions_on_account_id"
    t.index ["current_period_end"], name: "idx_subscriptions_on_current_period_end"
    t.index ["paypal_subscription_id"], name: "idx_subscriptions_on_paypal_id_unique", unique: true, where: "(paypal_subscription_id IS NOT NULL)"
    t.index ["plan_id"], name: "index_subscriptions_on_plan_id"
    t.index ["status"], name: "idx_subscriptions_on_status"
    t.index ["stripe_subscription_id"], name: "idx_subscriptions_on_stripe_id_unique", unique: true, where: "(stripe_subscription_id IS NOT NULL)"
    t.index ["trial_end"], name: "idx_subscriptions_on_trial_end"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'trialing'::character varying::text, 'past_due'::character varying::text, 'canceled'::character varying::text, 'unpaid'::character varying::text, 'incomplete'::character varying::text, 'incomplete_expired'::character varying::text, 'paused'::character varying::text, 'suspended'::character varying::text])", name: "valid_subscription_status"
  end

  create_table "supply_chain_attestations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "attestation_id"], name: "idx_attestations_account_id", unique: true
    t.index ["account_id"], name: "index_supply_chain_attestations_on_account_id"
    t.index ["created_by_id"], name: "index_supply_chain_attestations_on_created_by_id"
    t.index ["pipeline_run_id"], name: "index_supply_chain_attestations_on_pipeline_run_id"
    t.index ["predicate"], name: "idx_attestations_predicate", using: :gin
    t.index ["sbom_id"], name: "index_supply_chain_attestations_on_sbom_id"
    t.index ["signing_key_id"], name: "index_supply_chain_attestations_on_signing_key_id"
    t.index ["subject_digest"], name: "idx_attestations_subject_digest"
    t.index ["verification_status"], name: "idx_attestations_verification"
    t.check_constraint "attestation_type::text = ANY (ARRAY['slsa_provenance'::character varying::text, 'sbom'::character varying::text, 'vuln_scan'::character varying::text, 'custom'::character varying::text])", name: "check_attestations_type"
    t.check_constraint "slsa_level = ANY (ARRAY[0, 1, 2, 3])", name: "check_attestations_slsa_level"
    t.check_constraint "verification_status::text = ANY (ARRAY['unverified'::character varying::text, 'verified'::character varying::text, 'failed'::character varying::text, 'expired'::character varying::text])", name: "check_attestations_verification_status"
  end

  create_table "supply_chain_attributions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id"], name: "idx_attributions_account"
    t.index ["account_id"], name: "index_supply_chain_attributions_on_account_id"
    t.index ["license_id"], name: "index_supply_chain_attributions_on_license_id"
    t.index ["sbom_component_id"], name: "idx_attributions_component", unique: true
    t.index ["sbom_component_id"], name: "index_supply_chain_attributions_on_sbom_component_id"
  end

  create_table "supply_chain_build_provenances", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["attestation_id"], name: "idx_build_provenance_attestation", unique: true
    t.index ["attestation_id"], name: "index_supply_chain_build_provenances_on_attestation_id"
    t.index ["builder_id"], name: "idx_build_provenance_builder"
    t.index ["materials"], name: "idx_build_provenance_materials", using: :gin
  end

  create_table "supply_chain_container_images", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "digest"], name: "idx_container_images_account_digest", unique: true
    t.index ["account_id"], name: "index_supply_chain_container_images_on_account_id"
    t.index ["attestation_id"], name: "index_supply_chain_container_images_on_attestation_id"
    t.index ["base_image_id"], name: "index_supply_chain_container_images_on_base_image_id"
    t.index ["is_deployed"], name: "idx_container_images_deployed"
    t.index ["labels"], name: "idx_container_images_labels", using: :gin
    t.index ["registry", "repository", "tag"], name: "idx_container_images_registry_repo_tag"
    t.index ["sbom_id"], name: "index_supply_chain_container_images_on_sbom_id"
    t.index ["status"], name: "idx_container_images_status"
    t.check_constraint "status::text = ANY (ARRAY['unverified'::character varying::text, 'verified'::character varying::text, 'quarantined'::character varying::text, 'approved'::character varying::text, 'rejected'::character varying::text])", name: "check_container_images_status"
  end

  create_table "supply_chain_cve_monitors", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "name"], name: "idx_cve_monitors_account_name", unique: true
    t.index ["account_id"], name: "index_supply_chain_cve_monitors_on_account_id"
    t.index ["created_by_id"], name: "index_supply_chain_cve_monitors_on_created_by_id"
    t.index ["is_active"], name: "idx_cve_monitors_active"
    t.index ["next_run_at"], name: "idx_cve_monitors_next_run"
    t.index ["scope_type", "scope_id"], name: "idx_cve_monitors_scope"
    t.check_constraint "min_severity::text = ANY (ARRAY['critical'::character varying::text, 'high'::character varying::text, 'medium'::character varying::text, 'low'::character varying::text])", name: "check_cve_monitors_severity"
    t.check_constraint "scope_type::text = ANY (ARRAY['image'::character varying::text, 'repository'::character varying::text, 'account_wide'::character varying::text])", name: "check_cve_monitors_scope"
  end

  create_table "supply_chain_image_policies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "name"], name: "idx_image_policies_account_name", unique: true
    t.index ["account_id"], name: "index_supply_chain_image_policies_on_account_id"
    t.index ["created_by_id"], name: "index_supply_chain_image_policies_on_created_by_id"
    t.index ["is_active"], name: "idx_image_policies_active"
    t.index ["policy_type"], name: "idx_image_policies_type"
    t.check_constraint "enforcement_level::text = ANY (ARRAY['log'::character varying::text, 'warn'::character varying::text, 'block'::character varying::text])", name: "check_image_policies_enforcement"
    t.check_constraint "policy_type::text = ANY (ARRAY['registry_allowlist'::character varying::text, 'signature_required'::character varying::text, 'vulnerability_threshold'::character varying::text, 'custom'::character varying::text])", name: "check_image_policies_type"
  end

  create_table "supply_chain_license_detections", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["detection_source"], name: "idx_license_detections_source"
    t.index ["license_id"], name: "idx_license_detections_license"
    t.index ["license_id"], name: "index_supply_chain_license_detections_on_license_id"
    t.index ["sbom_component_id"], name: "idx_license_detections_component"
    t.index ["sbom_component_id"], name: "index_supply_chain_license_detections_on_sbom_component_id"
  end

  create_table "supply_chain_license_policies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "name"], name: "idx_license_policies_account_name", unique: true
    t.index ["account_id"], name: "index_supply_chain_license_policies_on_account_id"
    t.index ["created_by_id"], name: "index_supply_chain_license_policies_on_created_by_id"
    t.index ["is_active"], name: "idx_license_policies_active"
    t.index ["is_default"], name: "idx_license_policies_default", where: "(is_default = true)"
    t.check_constraint "enforcement_level::text = ANY (ARRAY['log'::character varying::text, 'warn'::character varying::text, 'block'::character varying::text])", name: "check_license_policies_enforcement"
    t.check_constraint "policy_type::text = ANY (ARRAY['allowlist'::character varying::text, 'denylist'::character varying::text, 'hybrid'::character varying::text])", name: "check_license_policies_type"
  end

  create_table "supply_chain_license_violations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "status"], name: "idx_license_violations_account_status"
    t.index ["account_id"], name: "index_supply_chain_license_violations_on_account_id"
    t.index ["exception_approved_by_id"], name: "idx_on_exception_approved_by_id_cfba11f498"
    t.index ["license_id"], name: "index_supply_chain_license_violations_on_license_id"
    t.index ["license_policy_id"], name: "index_supply_chain_license_violations_on_license_policy_id"
    t.index ["sbom_component_id"], name: "index_supply_chain_license_violations_on_sbom_component_id"
    t.index ["sbom_id"], name: "idx_license_violations_sbom"
    t.index ["sbom_id"], name: "index_supply_chain_license_violations_on_sbom_id"
    t.index ["violation_type"], name: "idx_license_violations_type"
    t.check_constraint "severity::text = ANY (ARRAY['critical'::character varying::text, 'high'::character varying::text, 'medium'::character varying::text, 'low'::character varying::text])", name: "check_license_violations_severity"
    t.check_constraint "status::text = ANY (ARRAY['open'::character varying::text, 'reviewing'::character varying::text, 'resolved'::character varying::text, 'exception_granted'::character varying::text, 'wont_fix'::character varying::text])", name: "check_license_violations_status"
    t.check_constraint "violation_type::text = ANY (ARRAY['denied'::character varying::text, 'copyleft'::character varying::text, 'incompatible'::character varying::text, 'unknown'::character varying::text, 'expired'::character varying::text])", name: "check_license_violations_type"
  end

  create_table "supply_chain_licenses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["category"], name: "idx_licenses_category"
    t.index ["is_copyleft"], name: "idx_licenses_copyleft"
    t.index ["spdx_id"], name: "idx_licenses_spdx_id", unique: true
    t.check_constraint "category::text = ANY (ARRAY['permissive'::character varying::text, 'copyleft'::character varying::text, 'weak_copyleft'::character varying::text, 'public_domain'::character varying::text, 'proprietary'::character varying::text, 'unknown'::character varying::text])", name: "check_licenses_category"
  end

  create_table "supply_chain_questionnaire_responses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["access_token"], name: "idx_questionnaire_responses_token", unique: true
    t.index ["account_id"], name: "index_supply_chain_questionnaire_responses_on_account_id"
    t.index ["requested_by_id"], name: "index_supply_chain_questionnaire_responses_on_requested_by_id"
    t.index ["reviewed_by_id"], name: "index_supply_chain_questionnaire_responses_on_reviewed_by_id"
    t.index ["risk_assessment_id"], name: "idx_on_risk_assessment_id_2f7cfcf19d"
    t.index ["status"], name: "idx_questionnaire_responses_status"
    t.index ["template_id"], name: "index_supply_chain_questionnaire_responses_on_template_id"
    t.index ["vendor_id", "template_id"], name: "idx_questionnaire_responses_vendor_template"
    t.index ["vendor_id"], name: "index_supply_chain_questionnaire_responses_on_vendor_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'in_progress'::character varying::text, 'submitted'::character varying::text, 'reviewed'::character varying::text, 'expired'::character varying::text])", name: "check_questionnaire_responses_status"
  end

  create_table "supply_chain_questionnaire_templates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["is_system"], name: "idx_questionnaire_templates_system"
    t.index ["template_type"], name: "idx_questionnaire_templates_type"
    t.check_constraint "template_type::text = ANY (ARRAY['soc2'::character varying::text, 'iso27001'::character varying::text, 'gdpr'::character varying::text, 'hipaa'::character varying::text, 'pci_dss'::character varying::text, 'custom'::character varying::text])", name: "check_questionnaire_templates_type"
  end

  create_table "supply_chain_remediation_plans", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.uuid "workflow_run_id"
    t.index ["account_id", "status"], name: "idx_remediation_plans_account_status"
    t.index ["account_id"], name: "index_supply_chain_remediation_plans_on_account_id"
    t.index ["approved_by_id"], name: "index_supply_chain_remediation_plans_on_approved_by_id"
    t.index ["created_by_id"], name: "index_supply_chain_remediation_plans_on_created_by_id"
    t.index ["sbom_id"], name: "idx_remediation_plans_sbom"
    t.index ["sbom_id"], name: "index_supply_chain_remediation_plans_on_sbom_id"
    t.index ["workflow_run_id"], name: "index_supply_chain_remediation_plans_on_workflow_run_id"
    t.check_constraint "plan_type::text = ANY (ARRAY['manual'::character varying::text, 'ai_generated'::character varying::text, 'auto_fix'::character varying::text])", name: "check_remediation_plans_type"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'pending_review'::character varying::text, 'approved'::character varying::text, 'rejected'::character varying::text, 'executing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "check_remediation_plans_status"
  end

  create_table "supply_chain_reports", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "report_type"], name: "idx_reports_account_type"
    t.index ["account_id"], name: "index_supply_chain_reports_on_account_id"
    t.index ["created_at"], name: "idx_reports_created"
    t.index ["created_by_id"], name: "index_supply_chain_reports_on_created_by_id"
    t.index ["sbom_id"], name: "index_supply_chain_reports_on_sbom_id"
    t.index ["status"], name: "idx_reports_status"
    t.check_constraint "format::text = ANY (ARRAY['pdf'::character varying::text, 'json'::character varying::text, 'csv'::character varying::text, 'html'::character varying::text, 'xml'::character varying::text, 'spdx'::character varying::text, 'cyclonedx'::character varying::text])", name: "check_reports_format"
    t.check_constraint "report_type::text = ANY (ARRAY['sbom_export'::character varying::text, 'vulnerability'::character varying::text, 'vulnerability_report'::character varying::text, 'license_report'::character varying::text, 'attribution'::character varying::text, 'compliance'::character varying::text, 'compliance_summary'::character varying::text, 'vendor_risk'::character varying::text, 'vendor_assessment'::character varying::text, 'custom'::character varying::text])", name: "check_reports_type"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'generating'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'expired'::character varying::text])", name: "check_reports_status"
  end

  create_table "supply_chain_risk_assessments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "status"], name: "idx_risk_assessments_account_status"
    t.index ["account_id"], name: "index_supply_chain_risk_assessments_on_account_id"
    t.index ["assessment_type"], name: "idx_risk_assessments_type"
    t.index ["assessor_id"], name: "index_supply_chain_risk_assessments_on_assessor_id"
    t.index ["vendor_id", "created_at"], name: "idx_risk_assessments_vendor_created"
    t.index ["vendor_id"], name: "index_supply_chain_risk_assessments_on_vendor_id"
    t.check_constraint "assessment_type::text = ANY (ARRAY['initial'::character varying::text, 'periodic'::character varying::text, 'incident'::character varying::text, 'renewal'::character varying::text])", name: "check_risk_assessments_type"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'in_progress'::character varying::text, 'pending_review'::character varying::text, 'completed'::character varying::text, 'expired'::character varying::text])", name: "check_risk_assessments_status"
  end

  create_table "supply_chain_sbom_components", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "ecosystem"], name: "idx_sbom_components_account_ecosystem"
    t.index ["account_id"], name: "index_supply_chain_sbom_components_on_account_id"
    t.index ["has_known_vulnerabilities"], name: "idx_sbom_components_has_vulns"
    t.index ["metadata"], name: "idx_sbom_components_metadata", using: :gin
    t.index ["purl"], name: "idx_sbom_components_purl"
    t.index ["sbom_id", "purl"], name: "idx_sbom_components_sbom_purl", unique: true
    t.index ["sbom_id"], name: "index_supply_chain_sbom_components_on_sbom_id"
    t.check_constraint "dependency_type::text = ANY (ARRAY['direct'::character varying::text, 'transitive'::character varying::text, 'dev'::character varying::text, 'optional'::character varying::text, 'peer'::character varying::text])", name: "check_sbom_components_dependency_type"
    t.check_constraint "ecosystem::text = ANY (ARRAY['npm'::character varying::text, 'gem'::character varying::text, 'pip'::character varying::text, 'maven'::character varying::text, 'gradle'::character varying::text, 'go'::character varying::text, 'cargo'::character varying::text, 'nuget'::character varying::text, 'composer'::character varying::text, 'hex'::character varying::text, 'pub'::character varying::text, 'cocoapods'::character varying::text, 'swift'::character varying::text, 'other'::character varying::text])", name: "check_sbom_components_ecosystem"
  end

  create_table "supply_chain_sbom_diffs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "created_at"], name: "idx_sbom_diffs_account_created"
    t.index ["account_id"], name: "index_supply_chain_sbom_diffs_on_account_id"
    t.index ["base_sbom_id", "target_sbom_id"], name: "idx_sbom_diffs_base_target", unique: true
    t.index ["base_sbom_id"], name: "index_supply_chain_sbom_diffs_on_base_sbom_id"
    t.index ["target_sbom_id"], name: "index_supply_chain_sbom_diffs_on_target_sbom_id"
  end

  create_table "supply_chain_sbom_vulnerabilities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "severity"], name: "idx_sbom_vulns_account_severity"
    t.index ["account_id"], name: "index_supply_chain_sbom_vulnerabilities_on_account_id"
    t.index ["component_id"], name: "index_supply_chain_sbom_vulnerabilities_on_component_id"
    t.index ["context_factors"], name: "idx_sbom_vulns_context", using: :gin
    t.index ["dismissed_by_id"], name: "index_supply_chain_sbom_vulnerabilities_on_dismissed_by_id"
    t.index ["remediation_status"], name: "idx_sbom_vulns_status"
    t.index ["sbom_id", "vulnerability_id", "component_id"], name: "idx_sbom_vulns_unique", unique: true
    t.index ["sbom_id"], name: "index_supply_chain_sbom_vulnerabilities_on_sbom_id"
    t.index ["vulnerability_id"], name: "idx_sbom_vulns_vuln_id"
    t.check_constraint "remediation_status::text = ANY (ARRAY['open'::character varying::text, 'in_progress'::character varying::text, 'fixed'::character varying::text, 'dismissed'::character varying::text, 'wont_fix'::character varying::text])", name: "check_sbom_vulns_remediation_status"
    t.check_constraint "severity::text = ANY (ARRAY['critical'::character varying::text, 'high'::character varying::text, 'medium'::character varying::text, 'low'::character varying::text, 'none'::character varying::text, 'unknown'::character varying::text])", name: "check_sbom_vulns_severity"
  end

  create_table "supply_chain_sboms", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "branch"
    t.string "commit_sha"
    t.integer "component_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.jsonb "document", default: {}, null: false
    t.string "document_hash"
    t.string "format", default: "cyclonedx_1_5", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "name"
    t.boolean "ntia_minimum_compliant", default: false, null: false
    t.uuid "pipeline_run_id"
    t.uuid "repository_id"
    t.decimal "risk_score", precision: 5, scale: 2, default: "0.0"
    t.string "sbom_id", null: false
    t.text "signature"
    t.string "signature_algorithm"
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.string "version"
    t.integer "vulnerability_count", default: 0, null: false
    t.index ["account_id", "sbom_id"], name: "idx_sboms_account_sbom_id", unique: true
    t.index ["account_id", "status"], name: "idx_sboms_account_status"
    t.index ["account_id"], name: "index_supply_chain_sboms_on_account_id"
    t.index ["created_at"], name: "idx_sboms_created_at"
    t.index ["created_by_id"], name: "index_supply_chain_sboms_on_created_by_id"
    t.index ["metadata"], name: "idx_sboms_metadata", using: :gin
    t.index ["pipeline_run_id"], name: "index_supply_chain_sboms_on_pipeline_run_id"
    t.index ["repository_id", "commit_sha"], name: "idx_sboms_repo_commit"
    t.index ["repository_id"], name: "index_supply_chain_sboms_on_repository_id"
    t.check_constraint "format::text = ANY (ARRAY['spdx_2_3'::character varying::text, 'cyclonedx_1_4'::character varying::text, 'cyclonedx_1_5'::character varying::text, 'cyclonedx_1_6'::character varying::text])", name: "check_sboms_format"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'generating'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'archived'::character varying::text])", name: "check_sboms_status"
  end

  create_table "supply_chain_scan_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "status"], name: "idx_scan_executions_account_status"
    t.index ["account_id"], name: "index_supply_chain_scan_executions_on_account_id"
    t.index ["execution_id"], name: "idx_scan_executions_execution_id", unique: true
    t.index ["scan_instance_id", "created_at"], name: "idx_scan_executions_instance_created"
    t.index ["scan_instance_id"], name: "index_supply_chain_scan_executions_on_scan_instance_id"
    t.index ["triggered_by_id"], name: "index_supply_chain_scan_executions_on_triggered_by_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text])", name: "check_scan_executions_status"
    t.check_constraint "trigger_type::text = ANY (ARRAY['manual'::character varying::text, 'scheduled'::character varying::text, 'webhook'::character varying::text, 'pipeline'::character varying::text, 'api'::character varying::text])", name: "check_scan_executions_trigger"
  end

  create_table "supply_chain_scan_instances", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "scan_template_id"], name: "idx_scan_instances_account_template", unique: true
    t.index ["account_id"], name: "index_supply_chain_scan_instances_on_account_id"
    t.index ["installed_by_id"], name: "index_supply_chain_scan_instances_on_installed_by_id"
    t.index ["next_execution_at"], name: "idx_scan_instances_next_execution"
    t.index ["scan_template_id"], name: "index_supply_chain_scan_instances_on_scan_template_id"
    t.index ["status"], name: "idx_scan_instances_status"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'paused'::character varying::text, 'disabled'::character varying::text])", name: "check_scan_instances_status"
  end

  create_table "supply_chain_scan_templates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["category"], name: "idx_scan_templates_category"
    t.index ["created_by_id"], name: "index_supply_chain_scan_templates_on_created_by_id"
    t.index ["is_public"], name: "idx_scan_templates_public"
    t.index ["slug"], name: "idx_scan_templates_slug", unique: true
    t.index ["status"], name: "idx_scan_templates_status"
    t.check_constraint "category::text = ANY (ARRAY['security'::character varying::text, 'compliance'::character varying::text, 'license'::character varying::text, 'quality'::character varying::text, 'custom'::character varying::text])", name: "check_scan_templates_category"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'published'::character varying::text, 'archived'::character varying::text, 'deprecated'::character varying::text])", name: "check_scan_templates_status"
  end

  create_table "supply_chain_signing_keys", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "key_id"], name: "idx_signing_keys_account_key_id", unique: true
    t.index ["account_id"], name: "index_supply_chain_signing_keys_on_account_id"
    t.index ["created_by_id"], name: "index_supply_chain_signing_keys_on_created_by_id"
    t.index ["fingerprint"], name: "idx_signing_keys_fingerprint", unique: true
    t.index ["rotated_from_id"], name: "index_supply_chain_signing_keys_on_rotated_from_id"
    t.index ["status"], name: "idx_signing_keys_status"
    t.check_constraint "key_type::text = ANY (ARRAY['cosign'::character varying::text, 'oidc_identity'::character varying::text, 'kms_reference'::character varying::text, 'gpg'::character varying::text])", name: "check_signing_keys_type"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'rotating'::character varying::text, 'rotated'::character varying::text, 'revoked'::character varying::text, 'expired'::character varying::text])", name: "check_signing_keys_status"
  end

  create_table "supply_chain_vendor_monitoring_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "severity"], name: "idx_vendor_events_account_severity"
    t.index ["account_id"], name: "index_supply_chain_vendor_monitoring_events_on_account_id"
    t.index ["acknowledged_by_id"], name: "idx_on_acknowledged_by_id_6c4702b009"
    t.index ["event_type"], name: "idx_vendor_events_type"
    t.index ["is_acknowledged"], name: "idx_vendor_events_acknowledged"
    t.index ["vendor_id", "created_at"], name: "idx_vendor_events_vendor_created"
    t.index ["vendor_id"], name: "index_supply_chain_vendor_monitoring_events_on_vendor_id"
    t.check_constraint "event_type::text = ANY (ARRAY['security_incident'::character varying::text, 'breach'::character varying::text, 'certification_expiry'::character varying::text, 'contract_renewal'::character varying::text, 'service_degradation'::character varying::text, 'compliance_update'::character varying::text, 'news_alert'::character varying::text])", name: "check_vendor_events_type"
    t.check_constraint "severity::text = ANY (ARRAY['critical'::character varying::text, 'high'::character varying::text, 'medium'::character varying::text, 'low'::character varying::text, 'info'::character varying::text])", name: "check_vendor_events_severity"
  end

  create_table "supply_chain_vendors", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "slug"], name: "idx_vendors_account_slug", unique: true
    t.index ["account_id"], name: "index_supply_chain_vendors_on_account_id"
    t.index ["certifications"], name: "idx_vendors_certifications", using: :gin
    t.index ["created_by_id"], name: "index_supply_chain_vendors_on_created_by_id"
    t.index ["risk_tier"], name: "idx_vendors_risk_tier"
    t.index ["status"], name: "idx_vendors_status"
    t.check_constraint "risk_tier::text = ANY (ARRAY['critical'::character varying::text, 'high'::character varying::text, 'medium'::character varying::text, 'low'::character varying::text])", name: "check_vendors_risk_tier"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'under_review'::character varying::text, 'terminated'::character varying::text])", name: "check_vendors_status"
    t.check_constraint "vendor_type::text = ANY (ARRAY['saas'::character varying::text, 'api'::character varying::text, 'library'::character varying::text, 'infrastructure'::character varying::text, 'hardware'::character varying::text, 'consulting'::character varying::text, 'other'::character varying::text])", name: "check_vendors_type"
  end

  create_table "supply_chain_verification_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["attestation_id", "created_at"], name: "idx_verification_logs_attestation_time"
    t.index ["attestation_id"], name: "index_supply_chain_verification_logs_on_attestation_id"
    t.index ["log_hash"], name: "idx_verification_logs_hash", unique: true
    t.index ["previous_log_hash"], name: "idx_verification_logs_prev_hash"
    t.index ["verified_by_id"], name: "index_supply_chain_verification_logs_on_verified_by_id"
  end

  create_table "supply_chain_vulnerability_feeds", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "source"], name: "idx_vuln_feeds_account_source", unique: true
    t.index ["account_id"], name: "index_supply_chain_vulnerability_feeds_on_account_id"
    t.index ["sync_status"], name: "idx_vuln_feeds_sync_status"
    t.check_constraint "source::text = ANY (ARRAY['nvd'::character varying::text, 'osv'::character varying::text, 'github_advisory'::character varying::text, 'snyk'::character varying::text, 'sonatype'::character varying::text, 'custom'::character varying::text])", name: "check_vuln_feeds_source"
    t.check_constraint "sync_status::text = ANY (ARRAY['pending'::character varying::text, 'syncing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "check_vuln_feeds_sync_status"
  end

  create_table "supply_chain_vulnerability_scans", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "status"], name: "idx_vuln_scans_account_status"
    t.index ["account_id"], name: "index_supply_chain_vulnerability_scans_on_account_id"
    t.index ["container_image_id", "created_at"], name: "idx_vuln_scans_image_created"
    t.index ["container_image_id"], name: "index_supply_chain_vulnerability_scans_on_container_image_id"
    t.index ["triggered_by_id"], name: "index_supply_chain_vulnerability_scans_on_triggered_by_id"
    t.index ["vulnerabilities"], name: "idx_vuln_scans_vulns", using: :gin
    t.check_constraint "scanner_name::text = ANY (ARRAY['trivy'::character varying::text, 'grype'::character varying::text, 'clair'::character varying::text, 'snyk'::character varying::text, 'custom'::character varying::text])", name: "check_vuln_scans_scanner"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text])", name: "check_vuln_scans_status"
  end

  create_table "task_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["scheduled_task_id", "started_at"], name: "idx_task_executions_on_scheduled_task_started_at"
    t.index ["scheduled_task_id"], name: "index_task_executions_on_scheduled_task_id"
    t.index ["started_at"], name: "idx_task_executions_on_started_at"
    t.index ["status"], name: "idx_task_executions_on_status"
    t.check_constraint "status::text = ANY (ARRAY['running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'timeout'::character varying::text])", name: "valid_execution_status"
  end

  create_table "terms_acceptances", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "usage_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.string "event_id", null: false
    t.boolean "is_processed", default: false, null: false
    t.jsonb "metadata", default: {}
    t.datetime "processed_at"
    t.jsonb "properties", default: {}
    t.decimal "quantity", precision: 15, scale: 4, default: "1.0", null: false
    t.string "source"
    t.datetime "timestamp", null: false
    t.datetime "updated_at", null: false
    t.uuid "usage_meter_id", null: false
    t.uuid "user_id"
    t.index ["account_id", "event_id"], name: "index_usage_events_on_account_id_and_event_id", unique: true
    t.index ["account_id", "timestamp"], name: "index_usage_events_on_account_id_and_timestamp"
    t.index ["account_id", "usage_meter_id"], name: "index_usage_events_on_account_id_and_usage_meter_id"
    t.index ["account_id"], name: "index_usage_events_on_account_id"
    t.index ["is_processed"], name: "index_usage_events_on_is_processed"
    t.index ["timestamp"], name: "index_usage_events_on_timestamp"
    t.index ["usage_meter_id"], name: "index_usage_events_on_usage_meter_id"
    t.index ["user_id"], name: "index_usage_events_on_user_id"
    t.check_constraint "source IS NULL OR (source::text = ANY (ARRAY['api'::character varying::text, 'webhook'::character varying::text, 'system'::character varying::text, 'import'::character varying::text, 'internal'::character varying::text]))", name: "check_usage_event_source"
  end

  create_table "usage_meters", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "aggregation_type", default: "sum", null: false
    t.string "billing_model", default: "tiered", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "is_active", default: true, null: false
    t.boolean "is_billable", default: true, null: false
    t.string "name", null: false
    t.jsonb "pricing_tiers", default: []
    t.string "reset_period", default: "monthly", null: false
    t.string "slug", null: false
    t.string "unit_name", default: "units", null: false
    t.datetime "updated_at", null: false
    t.index ["is_active"], name: "index_usage_meters_on_is_active"
    t.index ["slug"], name: "index_usage_meters_on_slug", unique: true
    t.check_constraint "aggregation_type::text = ANY (ARRAY['sum'::character varying::text, 'max'::character varying::text, 'count'::character varying::text, 'last'::character varying::text, 'average'::character varying::text])", name: "check_aggregation_type"
    t.check_constraint "billing_model::text = ANY (ARRAY['tiered'::character varying::text, 'volume'::character varying::text, 'package'::character varying::text, 'flat'::character varying::text, 'per_unit'::character varying::text])", name: "check_billing_model"
    t.check_constraint "reset_period::text = ANY (ARRAY['never'::character varying::text, 'daily'::character varying::text, 'weekly'::character varying::text, 'monthly'::character varying::text, 'yearly'::character varying::text, 'billing_period'::character varying::text])", name: "check_reset_period"
  end

  create_table "usage_quotas", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.boolean "allow_overage", default: true, null: false
    t.datetime "created_at", null: false
    t.integer "critical_threshold_percent", default: 95
    t.datetime "current_period_end"
    t.datetime "current_period_start"
    t.decimal "current_usage", precision: 15, scale: 4, default: "0.0", null: false
    t.decimal "hard_limit", precision: 15, scale: 4
    t.boolean "notify_on_exceeded", default: true, null: false
    t.boolean "notify_on_warning", default: true, null: false
    t.decimal "overage_rate", precision: 15, scale: 4
    t.uuid "plan_id"
    t.decimal "soft_limit", precision: 15, scale: 4
    t.datetime "updated_at", null: false
    t.uuid "usage_meter_id", null: false
    t.integer "warning_threshold_percent", default: 80
    t.index ["account_id", "usage_meter_id"], name: "index_usage_quotas_on_account_id_and_usage_meter_id", unique: true
    t.index ["account_id"], name: "index_usage_quotas_on_account_id"
    t.index ["plan_id"], name: "index_usage_quotas_on_plan_id"
    t.index ["usage_meter_id"], name: "index_usage_quotas_on_usage_meter_id"
  end

  create_table "usage_summaries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.decimal "billable_quantity", precision: 15, scale: 4, default: "0.0", null: false
    t.decimal "calculated_amount", precision: 15, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.integer "event_count", default: 0, null: false
    t.uuid "invoice_id"
    t.boolean "is_billed", default: false, null: false
    t.date "period_end", null: false
    t.date "period_start", null: false
    t.boolean "quota_exceeded", default: false, null: false
    t.decimal "quota_limit", precision: 15, scale: 4
    t.decimal "quota_used", precision: 15, scale: 4, default: "0.0", null: false
    t.uuid "subscription_id"
    t.decimal "total_quantity", precision: 15, scale: 4, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.uuid "usage_meter_id", null: false
    t.index ["account_id", "period_start"], name: "index_usage_summaries_on_account_id_and_period_start"
    t.index ["account_id", "usage_meter_id", "period_start"], name: "idx_usage_summaries_unique_period", unique: true
    t.index ["account_id"], name: "index_usage_summaries_on_account_id"
    t.index ["invoice_id"], name: "index_usage_summaries_on_invoice_id"
    t.index ["is_billed"], name: "index_usage_summaries_on_is_billed"
    t.index ["subscription_id"], name: "index_usage_summaries_on_subscription_id"
    t.index ["usage_meter_id"], name: "index_usage_summaries_on_usage_meter_id"
  end

  create_table "user_consents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["granted_by_id"], name: "index_user_roles_on_granted_by"
    t.index ["granted_by_id"], name: "index_user_roles_on_granted_by_id"
    t.index ["role_id"], name: "index_user_roles_on_role"
    t.index ["role_id"], name: "index_user_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_user_roles_unique", unique: true
    t.index ["user_id"], name: "index_user_roles_on_user_id"
  end

  create_table "user_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "validation_rules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["severity"], name: "index_validation_rules_on_severity"
  end

  create_table "webhook_deliveries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "webhook_delivery_stats", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["webhook_endpoint_id", "stat_date"], name: "idx_webhook_stats_endpoint_date", unique: true
    t.index ["webhook_endpoint_id"], name: "index_webhook_delivery_stats_on_webhook_endpoint_id"
  end

  create_table "webhook_endpoints", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id"], name: "idx_webhook_endpoints_on_account_id"
    t.index ["account_id"], name: "index_webhook_endpoints_on_account_id"
    t.index ["circuit_broken_at"], name: "index_webhook_endpoints_on_circuit_broken", where: "(circuit_broken_at IS NOT NULL)"
    t.index ["content_type"], name: "idx_webhook_endpoints_on_content_type"
    t.index ["created_by_id"], name: "idx_webhook_endpoints_on_created_by"
    t.index ["created_by_id"], name: "index_webhook_endpoints_on_created_by_id"
    t.index ["failure_count"], name: "idx_webhook_endpoints_on_failure_count"
    t.index ["is_active"], name: "idx_webhook_endpoints_on_is_active"
    t.index ["last_delivery_at"], name: "idx_webhook_endpoints_on_last_delivery_at"
    t.index ["status", "is_active"], name: "idx_webhook_endpoints_on_status_active"
    t.index ["success_count"], name: "idx_webhook_endpoints_on_success_count"
    t.index ["tier"], name: "index_webhook_endpoints_on_tier"
    t.check_constraint "content_type::text = ANY (ARRAY['application/json'::character varying::text, 'application/x-www-form-urlencoded'::character varying::text])", name: "valid_webhook_content_type"
    t.check_constraint "failure_count >= 0", name: "valid_webhook_failure_count"
    t.check_constraint "payload_detail_level::text = ANY (ARRAY['full'::character varying, 'minimal'::character varying, 'ids_only'::character varying]::text[])", name: "webhook_endpoints_payload_detail_level_check"
    t.check_constraint "retry_backoff::text = ANY (ARRAY['linear'::character varying::text, 'exponential'::character varying::text])", name: "valid_webhook_retry_backoff"
    t.check_constraint "retry_limit >= 0 AND retry_limit <= 10", name: "valid_webhook_retry_limit"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'suspended'::character varying::text])", name: "valid_webhook_status"
    t.check_constraint "success_count >= 0", name: "valid_webhook_success_count"
    t.check_constraint "tier::text = ANY (ARRAY['free'::character varying::text, 'pro'::character varying::text, 'enterprise'::character varying::text])", name: "check_webhook_tier"
    t.check_constraint "timeout_seconds > 0 AND timeout_seconds <= 300", name: "valid_webhook_timeout"
  end

  create_table "webhook_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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
    t.index ["account_id", "event_type"], name: "idx_webhook_events_on_account_event_type"
    t.index ["account_id"], name: "index_webhook_events_on_account_id"
    t.index ["event_id"], name: "idx_webhook_events_on_event_id_unique", unique: true
    t.index ["external_id"], name: "idx_webhook_events_on_external_id_unique", unique: true
    t.index ["occurred_at"], name: "idx_webhook_events_on_occurred_at"
    t.index ["payment_id"], name: "index_webhook_events_on_payment_id"
    t.index ["provider"], name: "idx_webhook_events_on_provider"
    t.index ["retry_count"], name: "idx_webhook_events_on_retry_count"
    t.index ["status"], name: "idx_webhook_events_on_status"
    t.check_constraint "provider::text = ANY (ARRAY['stripe'::character varying::text, 'paypal'::character varying::text])", name: "valid_webhook_provider"
    t.check_constraint "retry_count >= 0 AND retry_count <= 10", name: "valid_webhook_retry_count"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'processed'::character varying::text, 'failed'::character varying::text, 'skipped'::character varying::text])", name: "valid_webhook_event_status"
  end

  create_table "worker_activities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "activity_type", limit: 100, null: false
    t.datetime "created_at", null: false
    t.jsonb "details", default: {}
    t.datetime "occurred_at", null: false
    t.string "status", limit: 50
    t.datetime "updated_at", null: false
    t.uuid "worker_id", null: false
    t.index ["activity_type"], name: "idx_worker_activities_on_activity_type"
    t.index ["occurred_at"], name: "idx_worker_activities_on_occurred_at"
    t.index ["worker_id", "occurred_at"], name: "idx_worker_activities_on_worker_occurred_at"
    t.index ["worker_id"], name: "index_worker_activities_on_worker_id"
  end

  create_table "worker_roles", id: false, force: :cascade do |t|
    t.datetime "granted_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.uuid "role_id", null: false
    t.uuid "worker_id", null: false
    t.index ["role_id"], name: "index_worker_roles_on_role"
    t.index ["role_id"], name: "index_worker_roles_on_role_id"
    t.index ["worker_id", "role_id"], name: "index_worker_roles_unique", unique: true
    t.index ["worker_id"], name: "index_worker_roles_on_worker_id"
  end

  create_table "workers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "last_seen_at"
    t.string "name", null: false
    t.jsonb "permissions", default: []
    t.string "status", default: "active"
    t.string "token_digest"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_workers_on_account_id"
    t.index ["name"], name: "index_workers_on_name", unique: true
    t.index ["permissions"], name: "index_workers_on_permissions", using: :gin
    t.index ["status"], name: "index_workers_on_status"
  end

  create_table "workflow_validations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "health_score", null: false
    t.jsonb "issues", default: [], null: false
    t.string "overall_status", null: false
    t.integer "total_nodes", null: false
    t.datetime "updated_at", null: false
    t.integer "validated_nodes", null: false
    t.integer "validation_duration_ms"
    t.uuid "workflow_id", null: false
    t.index ["workflow_id", "created_at"], name: "index_workflow_validations_on_workflow_id_and_created_at"
    t.index ["workflow_id"], name: "index_workflow_validations_on_workflow_id"
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
  add_foreign_key "ai_a2a_tasks", "ai_workflow_runs"
  add_foreign_key "ai_a2a_tasks", "chat_messages", on_delete: :nullify
  add_foreign_key "ai_a2a_tasks", "chat_sessions", on_delete: :nullify
  add_foreign_key "ai_a2a_tasks", "community_agents", on_delete: :nullify
  add_foreign_key "ai_a2a_tasks", "devops_container_instances", column: "container_instance_id"
  add_foreign_key "ai_a2a_tasks", "federation_partners", on_delete: :nullify
  add_foreign_key "ai_ab_tests", "accounts"
  add_foreign_key "ai_ab_tests", "users", column: "created_by_id"
  add_foreign_key "ai_account_credits", "accounts"
  add_foreign_key "ai_agent_budgets", "accounts"
  add_foreign_key "ai_agent_budgets", "ai_agent_budgets", column: "parent_budget_id"
  add_foreign_key "ai_agent_budgets", "ai_agents", column: "agent_id"
  add_foreign_key "ai_agent_cards", "accounts"
  add_foreign_key "ai_agent_cards", "ai_agents"
  add_foreign_key "ai_agent_connections", "accounts"
  add_foreign_key "ai_agent_executions", "accounts", on_delete: :cascade
  add_foreign_key "ai_agent_executions", "ai_agent_executions", column: "parent_execution_id", on_delete: :nullify
  add_foreign_key "ai_agent_executions", "ai_agents", on_delete: :cascade
  add_foreign_key "ai_agent_executions", "ai_providers", on_delete: :restrict
  add_foreign_key "ai_agent_executions", "users", on_delete: :restrict
  add_foreign_key "ai_agent_identities", "accounts"
  add_foreign_key "ai_agent_installations", "accounts"
  add_foreign_key "ai_agent_installations", "ai_agent_templates", column: "agent_template_id"
  add_foreign_key "ai_agent_installations", "ai_agents", column: "installed_agent_id"
  add_foreign_key "ai_agent_installations", "users", column: "installed_by_id"
  add_foreign_key "ai_agent_lineages", "accounts"
  add_foreign_key "ai_agent_lineages", "ai_agents", column: "child_agent_id"
  add_foreign_key "ai_agent_lineages", "ai_agents", column: "parent_agent_id"
  add_foreign_key "ai_agent_privilege_policies", "accounts"
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
  add_foreign_key "ai_agent_templates", "ai_agents", column: "source_agent_id"
  add_foreign_key "ai_agent_templates", "ai_publisher_accounts", column: "publisher_id"
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
  add_foreign_key "ai_credit_purchases", "accounts"
  add_foreign_key "ai_credit_purchases", "ai_credit_packs", column: "credit_pack_id"
  add_foreign_key "ai_credit_purchases", "users"
  add_foreign_key "ai_credit_transactions", "accounts"
  add_foreign_key "ai_credit_transactions", "ai_account_credits", column: "account_credit_id"
  add_foreign_key "ai_credit_transactions", "ai_credit_packs", column: "credit_pack_id"
  add_foreign_key "ai_credit_transactions", "users", column: "initiated_by_id"
  add_foreign_key "ai_credit_transfers", "accounts", column: "from_account_id"
  add_foreign_key "ai_credit_transfers", "accounts", column: "to_account_id"
  add_foreign_key "ai_credit_transfers", "users", column: "approved_by_id"
  add_foreign_key "ai_credit_transfers", "users", column: "initiated_by_id"
  add_foreign_key "ai_dag_executions", "accounts"
  add_foreign_key "ai_dag_executions", "ai_workflows", column: "workflow_id"
  add_foreign_key "ai_dag_executions", "users", column: "triggered_by_id"
  add_foreign_key "ai_data_classifications", "accounts"
  add_foreign_key "ai_data_classifications", "users", column: "classified_by_id"
  add_foreign_key "ai_data_connectors", "accounts"
  add_foreign_key "ai_data_connectors", "ai_knowledge_bases", column: "knowledge_base_id"
  add_foreign_key "ai_data_connectors", "users", column: "created_by_id"
  add_foreign_key "ai_data_detections", "accounts"
  add_foreign_key "ai_data_detections", "ai_data_classifications", column: "classification_id"
  add_foreign_key "ai_deployment_risks", "accounts"
  add_foreign_key "ai_deployment_risks", "ai_pipeline_executions", column: "pipeline_execution_id"
  add_foreign_key "ai_deployment_risks", "users", column: "assessed_by_id"
  add_foreign_key "ai_devops_template_installations", "accounts"
  add_foreign_key "ai_devops_template_installations", "ai_devops_templates", column: "devops_template_id"
  add_foreign_key "ai_devops_template_installations", "ai_workflows", column: "created_workflow_id"
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
  add_foreign_key "ai_file_locks", "accounts"
  add_foreign_key "ai_file_locks", "ai_worktree_sessions", column: "worktree_session_id"
  add_foreign_key "ai_file_locks", "ai_worktrees", column: "worktree_id"
  add_foreign_key "ai_guardrail_configs", "accounts"
  add_foreign_key "ai_guardrail_configs", "ai_agents"
  add_foreign_key "ai_hybrid_search_results", "accounts"
  add_foreign_key "ai_improvement_recommendations", "accounts"
  add_foreign_key "ai_improvement_recommendations", "users", column: "approved_by_id"
  add_foreign_key "ai_knowledge_bases", "accounts"
  add_foreign_key "ai_knowledge_bases", "users", column: "created_by_id"
  add_foreign_key "ai_knowledge_graph_edges", "accounts"
  add_foreign_key "ai_knowledge_graph_edges", "ai_documents", column: "source_document_id"
  add_foreign_key "ai_knowledge_graph_edges", "ai_knowledge_graph_nodes", column: "source_node_id"
  add_foreign_key "ai_knowledge_graph_edges", "ai_knowledge_graph_nodes", column: "target_node_id"
  add_foreign_key "ai_knowledge_graph_nodes", "accounts"
  add_foreign_key "ai_knowledge_graph_nodes", "ai_documents", column: "source_document_id"
  add_foreign_key "ai_knowledge_graph_nodes", "ai_knowledge_bases", column: "knowledge_base_id"
  add_foreign_key "ai_knowledge_graph_nodes", "ai_knowledge_graph_nodes", column: "merged_into_id"
  add_foreign_key "ai_marketplace_categories", "ai_marketplace_categories", column: "parent_id"
  add_foreign_key "ai_marketplace_moderations", "ai_agent_templates", column: "agent_template_id"
  add_foreign_key "ai_marketplace_moderations", "users", column: "reviewed_by_id"
  add_foreign_key "ai_marketplace_moderations", "users", column: "submitted_by_id"
  add_foreign_key "ai_marketplace_purchases", "accounts"
  add_foreign_key "ai_marketplace_purchases", "ai_agent_installations", column: "installation_id"
  add_foreign_key "ai_marketplace_purchases", "ai_agent_templates", column: "agent_template_id"
  add_foreign_key "ai_marketplace_purchases", "users"
  add_foreign_key "ai_marketplace_transactions", "accounts"
  add_foreign_key "ai_marketplace_transactions", "ai_agent_installations", column: "installation_id"
  add_foreign_key "ai_marketplace_transactions", "ai_agent_templates", column: "agent_template_id"
  add_foreign_key "ai_marketplace_transactions", "ai_publisher_accounts", column: "publisher_id"
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
  add_foreign_key "ai_missions", "ai_ralph_loops", column: "ralph_loop_id"
  add_foreign_key "ai_missions", "git_repositories", column: "repository_id"
  add_foreign_key "ai_missions", "users", column: "created_by_id"
  add_foreign_key "ai_mock_responses", "accounts"
  add_foreign_key "ai_mock_responses", "ai_sandboxes", column: "sandbox_id"
  add_foreign_key "ai_mock_responses", "users", column: "created_by_id"
  add_foreign_key "ai_model_routing_rules", "accounts"
  add_foreign_key "ai_outcome_billing_records", "accounts"
  add_foreign_key "ai_outcome_billing_records", "ai_outcome_definitions", column: "outcome_definition_id"
  add_foreign_key "ai_outcome_billing_records", "ai_sla_contracts", column: "sla_contract_id"
  add_foreign_key "ai_outcome_billing_records", "users", column: "validated_by_id"
  add_foreign_key "ai_outcome_definitions", "accounts"
  add_foreign_key "ai_performance_benchmarks", "accounts"
  add_foreign_key "ai_performance_benchmarks", "ai_agents", column: "target_agent_id"
  add_foreign_key "ai_performance_benchmarks", "ai_sandboxes", column: "sandbox_id"
  add_foreign_key "ai_performance_benchmarks", "ai_workflows", column: "target_workflow_id"
  add_foreign_key "ai_performance_benchmarks", "users", column: "created_by_id"
  add_foreign_key "ai_persistent_contexts", "accounts"
  add_foreign_key "ai_persistent_contexts", "ai_agents"
  add_foreign_key "ai_persistent_contexts", "users", column: "created_by_user_id"
  add_foreign_key "ai_pipeline_executions", "accounts"
  add_foreign_key "ai_pipeline_executions", "ai_devops_template_installations", column: "devops_installation_id"
  add_foreign_key "ai_pipeline_executions", "ai_workflow_runs", column: "workflow_run_id"
  add_foreign_key "ai_pipeline_executions", "users", column: "triggered_by_id"
  add_foreign_key "ai_policy_violations", "accounts"
  add_foreign_key "ai_policy_violations", "ai_compliance_policies", column: "policy_id"
  add_foreign_key "ai_policy_violations", "users", column: "detected_by_id"
  add_foreign_key "ai_policy_violations", "users", column: "resolved_by_id"
  add_foreign_key "ai_provider_credentials", "accounts", on_delete: :cascade
  add_foreign_key "ai_provider_credentials", "ai_providers", on_delete: :cascade
  add_foreign_key "ai_provider_metrics", "accounts"
  add_foreign_key "ai_provider_metrics", "ai_providers", column: "provider_id"
  add_foreign_key "ai_providers", "accounts"
  add_foreign_key "ai_publisher_accounts", "accounts"
  add_foreign_key "ai_publisher_accounts", "users", column: "primary_user_id"
  add_foreign_key "ai_publisher_earnings_snapshots", "ai_publisher_accounts", column: "publisher_id"
  add_foreign_key "ai_quarantine_records", "accounts"
  add_foreign_key "ai_rag_queries", "accounts"
  add_foreign_key "ai_rag_queries", "ai_knowledge_bases", column: "knowledge_base_id"
  add_foreign_key "ai_rag_queries", "users"
  add_foreign_key "ai_ralph_iterations", "ai_ralph_loops", column: "ralph_loop_id"
  add_foreign_key "ai_ralph_iterations", "ai_ralph_tasks", column: "ralph_task_id"
  add_foreign_key "ai_ralph_loops", "accounts"
  add_foreign_key "ai_ralph_loops", "ai_agents", column: "default_agent_id", on_delete: :nullify
  add_foreign_key "ai_ralph_loops", "ai_code_factory_risk_contracts", column: "risk_contract_id"
  add_foreign_key "ai_ralph_loops", "ai_missions", column: "mission_id"
  add_foreign_key "ai_ralph_loops", "devops_container_instances", column: "container_instance_id"
  add_foreign_key "ai_ralph_tasks", "ai_ralph_loops", column: "ralph_loop_id"
  add_foreign_key "ai_recorded_interactions", "accounts"
  add_foreign_key "ai_recorded_interactions", "ai_sandboxes", column: "sandbox_id"
  add_foreign_key "ai_recorded_interactions", "ai_workflow_runs", column: "source_workflow_run_id"
  add_foreign_key "ai_remediation_logs", "accounts"
  add_foreign_key "ai_roi_metrics", "accounts"
  add_foreign_key "ai_role_profiles", "accounts"
  add_foreign_key "ai_routing_decisions", "accounts"
  add_foreign_key "ai_routing_decisions", "ai_agent_executions", column: "agent_execution_id"
  add_foreign_key "ai_routing_decisions", "ai_model_routing_rules", column: "routing_rule_id"
  add_foreign_key "ai_routing_decisions", "ai_providers", column: "selected_provider_id"
  add_foreign_key "ai_routing_decisions", "ai_task_complexity_assessments", column: "complexity_assessment_id"
  add_foreign_key "ai_routing_decisions", "ai_workflow_runs", column: "workflow_run_id"
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
  add_foreign_key "ai_shared_context_pools", "ai_workflow_runs", on_delete: :cascade
  add_foreign_key "ai_shared_knowledges", "accounts"
  add_foreign_key "ai_shared_knowledges", "users", column: "created_by_id"
  add_foreign_key "ai_skills", "accounts"
  add_foreign_key "ai_skills", "ai_knowledge_bases", column: "ai_knowledge_base_id"
  add_foreign_key "ai_skills_mcp_servers", "ai_skills"
  add_foreign_key "ai_skills_mcp_servers", "mcp_servers"
  add_foreign_key "ai_sla_contracts", "accounts"
  add_foreign_key "ai_sla_contracts", "ai_outcome_definitions", column: "outcome_definition_id"
  add_foreign_key "ai_sla_violations", "accounts"
  add_foreign_key "ai_sla_violations", "ai_sla_contracts", column: "sla_contract_id"
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
  add_foreign_key "ai_team_executions", "users", column: "approval_decided_by_id"
  add_foreign_key "ai_team_executions", "users", column: "triggered_by_id"
  add_foreign_key "ai_team_messages", "ai_team_channels", column: "channel_id"
  add_foreign_key "ai_team_messages", "ai_team_executions", column: "team_execution_id"
  add_foreign_key "ai_team_messages", "ai_team_roles", column: "from_role_id"
  add_foreign_key "ai_team_messages", "ai_team_roles", column: "to_role_id"
  add_foreign_key "ai_team_roles", "accounts"
  add_foreign_key "ai_team_roles", "ai_agent_teams", column: "agent_team_id"
  add_foreign_key "ai_team_roles", "ai_agents"
  add_foreign_key "ai_team_tasks", "ai_agents", column: "assigned_agent_id"
  add_foreign_key "ai_team_tasks", "ai_team_executions", column: "team_execution_id"
  add_foreign_key "ai_team_tasks", "ai_team_roles", column: "assigned_role_id"
  add_foreign_key "ai_team_templates", "accounts"
  add_foreign_key "ai_team_templates", "users", column: "created_by_id"
  add_foreign_key "ai_template_usage_metrics", "ai_agent_templates", column: "agent_template_id"
  add_foreign_key "ai_test_results", "ai_test_runs", column: "test_run_id"
  add_foreign_key "ai_test_results", "ai_test_scenarios", column: "scenario_id"
  add_foreign_key "ai_test_runs", "accounts"
  add_foreign_key "ai_test_runs", "ai_sandboxes", column: "sandbox_id"
  add_foreign_key "ai_test_runs", "users", column: "triggered_by_id"
  add_foreign_key "ai_test_scenarios", "accounts"
  add_foreign_key "ai_test_scenarios", "ai_agents", column: "target_agent_id"
  add_foreign_key "ai_test_scenarios", "ai_sandboxes", column: "sandbox_id"
  add_foreign_key "ai_test_scenarios", "ai_workflows", column: "target_workflow_id"
  add_foreign_key "ai_test_scenarios", "users", column: "created_by_id"
  add_foreign_key "ai_trajectories", "accounts"
  add_foreign_key "ai_trajectories", "ai_agents"
  add_foreign_key "ai_trajectory_chapters", "ai_trajectories", column: "trajectory_id"
  add_foreign_key "ai_workflow_approval_tokens", "ai_workflow_node_executions"
  add_foreign_key "ai_workflow_approval_tokens", "users", column: "recipient_user_id"
  add_foreign_key "ai_workflow_approval_tokens", "users", column: "responded_by_id"
  add_foreign_key "ai_workflow_checkpoints", "ai_workflow_runs", on_delete: :cascade
  add_foreign_key "ai_workflow_compensations", "ai_workflow_node_executions", on_delete: :cascade
  add_foreign_key "ai_workflow_compensations", "ai_workflow_runs", on_delete: :cascade
  add_foreign_key "ai_workflow_edges", "ai_workflows"
  add_foreign_key "ai_workflow_executions", "accounts", on_delete: :cascade
  add_foreign_key "ai_workflow_executions", "users", on_delete: :cascade
  add_foreign_key "ai_workflow_node_executions", "ai_agent_executions"
  add_foreign_key "ai_workflow_node_executions", "ai_workflow_nodes"
  add_foreign_key "ai_workflow_node_executions", "ai_workflow_runs"
  add_foreign_key "ai_workflow_nodes", "ai_workflows"
  add_foreign_key "ai_workflow_nodes", "shared_prompt_templates", on_delete: :nullify
  add_foreign_key "ai_workflow_run_logs", "ai_workflow_node_executions"
  add_foreign_key "ai_workflow_run_logs", "ai_workflow_runs"
  add_foreign_key "ai_workflow_runs", "accounts"
  add_foreign_key "ai_workflow_runs", "ai_a2a_tasks", column: "a2a_task_id", on_delete: :nullify
  add_foreign_key "ai_workflow_runs", "ai_workflow_triggers"
  add_foreign_key "ai_workflow_runs", "ai_workflows"
  add_foreign_key "ai_workflow_runs", "users", column: "triggered_by_user_id"
  add_foreign_key "ai_workflow_schedules", "ai_workflows"
  add_foreign_key "ai_workflow_schedules", "users", column: "created_by_id"
  add_foreign_key "ai_workflow_templates", "accounts"
  add_foreign_key "ai_workflow_templates", "users", column: "created_by_user_id"
  add_foreign_key "ai_workflow_triggers", "ai_workflows"
  add_foreign_key "ai_workflow_variables", "ai_workflows"
  add_foreign_key "ai_workflows", "accounts"
  add_foreign_key "ai_workflows", "ai_workflows", column: "parent_version_id", on_delete: :nullify
  add_foreign_key "ai_workflows", "users", column: "creator_id"
  add_foreign_key "ai_worktree_sessions", "accounts"
  add_foreign_key "ai_worktree_sessions", "users", column: "initiated_by_id"
  add_foreign_key "ai_worktrees", "accounts"
  add_foreign_key "ai_worktrees", "ai_agents"
  add_foreign_key "ai_worktrees", "ai_worktree_sessions", column: "worktree_session_id"
  add_foreign_key "analytics_alert_events", "accounts"
  add_foreign_key "analytics_alert_events", "analytics_alerts"
  add_foreign_key "analytics_alerts", "accounts"
  add_foreign_key "api_key_usages", "api_keys"
  add_foreign_key "api_keys", "accounts"
  add_foreign_key "api_keys", "users", column: "created_by_id"
  add_foreign_key "audit_logs", "accounts"
  add_foreign_key "audit_logs", "users", on_delete: :nullify
  add_foreign_key "baas_api_keys", "baas_tenants"
  add_foreign_key "baas_billing_configurations", "baas_tenants"
  add_foreign_key "baas_customers", "baas_tenants"
  add_foreign_key "baas_invoices", "baas_customers"
  add_foreign_key "baas_invoices", "baas_subscriptions"
  add_foreign_key "baas_invoices", "baas_tenants"
  add_foreign_key "baas_subscriptions", "baas_customers"
  add_foreign_key "baas_subscriptions", "baas_tenants"
  add_foreign_key "baas_tenants", "accounts"
  add_foreign_key "baas_usage_records", "baas_tenants"
  add_foreign_key "batch_workflow_runs", "accounts"
  add_foreign_key "batch_workflow_runs", "users"
  add_foreign_key "blacklisted_tokens", "users"
  add_foreign_key "chat_blacklists", "accounts"
  add_foreign_key "chat_blacklists", "chat_channels", column: "channel_id"
  add_foreign_key "chat_blacklists", "users", column: "blocked_by_id"
  add_foreign_key "chat_channels", "accounts"
  add_foreign_key "chat_channels", "ai_agents", column: "default_agent_id"
  add_foreign_key "chat_message_attachments", "chat_messages", column: "message_id"
  add_foreign_key "chat_message_attachments", "file_objects"
  add_foreign_key "chat_messages", "ai_messages"
  add_foreign_key "chat_messages", "chat_sessions", column: "session_id"
  add_foreign_key "chat_sessions", "ai_agents", column: "assigned_agent_id"
  add_foreign_key "chat_sessions", "ai_conversations"
  add_foreign_key "chat_sessions", "chat_channels", column: "channel_id"
  add_foreign_key "churn_predictions", "accounts"
  add_foreign_key "churn_predictions", "subscriptions"
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
  add_foreign_key "cookie_consents", "users"
  add_foreign_key "customer_health_scores", "accounts"
  add_foreign_key "customer_health_scores", "subscriptions"
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
  add_foreign_key "delegation_permissions", "permissions"
  add_foreign_key "devops_ai_configs", "accounts", on_delete: :cascade
  add_foreign_key "devops_ai_configs", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "devops_container_instances", "accounts"
  add_foreign_key "devops_container_instances", "ai_a2a_tasks", column: "a2a_task_id"
  add_foreign_key "devops_container_instances", "devops_container_templates", column: "template_id"
  add_foreign_key "devops_container_instances", "users", column: "triggered_by_id"
  add_foreign_key "devops_container_templates", "accounts"
  add_foreign_key "devops_container_templates", "users", column: "created_by_id"
  add_foreign_key "devops_docker_activities", "devops_docker_containers", column: "container_id"
  add_foreign_key "devops_docker_activities", "devops_docker_hosts", column: "docker_host_id"
  add_foreign_key "devops_docker_activities", "devops_docker_images", column: "image_id"
  add_foreign_key "devops_docker_activities", "users", column: "triggered_by_id"
  add_foreign_key "devops_docker_containers", "devops_docker_hosts", column: "docker_host_id"
  add_foreign_key "devops_docker_events", "devops_docker_hosts", column: "docker_host_id"
  add_foreign_key "devops_docker_events", "users", column: "acknowledged_by_id"
  add_foreign_key "devops_docker_hosts", "accounts"
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
  add_foreign_key "devops_pipeline_repositories", "devops_pipelines", column: "ci_cd_pipeline_id", on_delete: :cascade
  add_foreign_key "devops_pipeline_repositories", "devops_repositories", column: "ci_cd_repository_id", on_delete: :cascade
  add_foreign_key "devops_pipeline_runs", "devops_pipelines", column: "ci_cd_pipeline_id", on_delete: :cascade
  add_foreign_key "devops_pipeline_runs", "users", column: "triggered_by_id", on_delete: :nullify
  add_foreign_key "devops_pipeline_steps", "devops_pipelines", column: "ci_cd_pipeline_id", on_delete: :cascade
  add_foreign_key "devops_pipeline_steps", "shared_prompt_templates", on_delete: :nullify
  add_foreign_key "devops_pipelines", "accounts", on_delete: :cascade
  add_foreign_key "devops_pipelines", "ai_providers", on_delete: :nullify
  add_foreign_key "devops_pipelines", "devops_providers", column: "ci_cd_provider_id", on_delete: :restrict
  add_foreign_key "devops_pipelines", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "devops_providers", "accounts", on_delete: :cascade
  add_foreign_key "devops_providers", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "devops_repositories", "accounts", on_delete: :cascade
  add_foreign_key "devops_repositories", "devops_providers", column: "ci_cd_provider_id", on_delete: :cascade
  add_foreign_key "devops_resource_quotas", "accounts"
  add_foreign_key "devops_schedules", "devops_pipelines", column: "ci_cd_pipeline_id", on_delete: :cascade
  add_foreign_key "devops_schedules", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "devops_secret_references", "accounts"
  add_foreign_key "devops_secret_references", "users", column: "created_by_id"
  add_foreign_key "devops_step_approval_tokens", "devops_step_executions", column: "step_execution_id"
  add_foreign_key "devops_step_approval_tokens", "users", column: "recipient_user_id"
  add_foreign_key "devops_step_approval_tokens", "users", column: "responded_by_id"
  add_foreign_key "devops_step_executions", "devops_pipeline_runs", column: "ci_cd_pipeline_run_id", on_delete: :cascade
  add_foreign_key "devops_step_executions", "devops_pipeline_steps", column: "ci_cd_pipeline_step_id", on_delete: :cascade
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
  add_foreign_key "git_repositories", "accounts", on_delete: :cascade
  add_foreign_key "git_repositories", "git_provider_credentials", on_delete: :cascade
  add_foreign_key "git_runners", "accounts", on_delete: :cascade
  add_foreign_key "git_runners", "git_provider_credentials", on_delete: :cascade
  add_foreign_key "git_runners", "git_repositories", on_delete: :cascade
  add_foreign_key "git_webhook_events", "accounts", on_delete: :cascade
  add_foreign_key "git_webhook_events", "git_providers", on_delete: :cascade
  add_foreign_key "git_webhook_events", "git_repositories", on_delete: :cascade
  add_foreign_key "git_workflow_triggers", "ai_workflow_triggers"
  add_foreign_key "git_workflow_triggers", "git_repositories"
  add_foreign_key "impersonation_sessions", "users", column: "impersonated_user_id"
  add_foreign_key "impersonation_sessions", "users", column: "impersonator_id"
  add_foreign_key "invitations", "accounts"
  add_foreign_key "invitations", "users", column: "inviter_id"
  add_foreign_key "invoice_line_items", "invoices"
  add_foreign_key "invoice_line_items", "plans"
  add_foreign_key "invoices", "accounts"
  add_foreign_key "invoices", "subscriptions"
  add_foreign_key "jwt_blacklists", "users", on_delete: :nullify
  add_foreign_key "knowledge_base_article_views", "users"
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
  add_foreign_key "marketplace_reviews", "accounts"
  add_foreign_key "marketplace_reviews", "users"
  add_foreign_key "marketplace_subscriptions", "accounts"
  add_foreign_key "mcp_hosted_servers", "accounts"
  add_foreign_key "mcp_hosted_servers", "devops_container_instances", column: "container_instance_id"
  add_foreign_key "mcp_hosted_servers", "devops_container_templates", column: "container_template_id"
  add_foreign_key "mcp_hosted_servers", "mcp_servers"
  add_foreign_key "mcp_hosted_servers", "users", column: "deployed_by_id"
  add_foreign_key "mcp_server_deployments", "mcp_hosted_servers", column: "hosted_server_id"
  add_foreign_key "mcp_server_deployments", "users", column: "deployed_by_id"
  add_foreign_key "mcp_server_metrics", "mcp_hosted_servers", column: "hosted_server_id"
  add_foreign_key "mcp_server_subscriptions", "accounts"
  add_foreign_key "mcp_server_subscriptions", "mcp_hosted_servers", column: "hosted_server_id"
  add_foreign_key "mcp_servers", "accounts"
  add_foreign_key "mcp_tool_executions", "mcp_tools"
  add_foreign_key "mcp_tool_executions", "users"
  add_foreign_key "mcp_tools", "mcp_servers"
  add_foreign_key "missing_payment_logs", "accounts"
  add_foreign_key "notifications", "accounts"
  add_foreign_key "notifications", "users"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_grants", "users", column: "resource_owner_id", on_delete: :cascade
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "users", column: "resource_owner_id", on_delete: :cascade
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
  add_foreign_key "reseller_commissions", "accounts", column: "referred_account_id"
  add_foreign_key "reseller_commissions", "reseller_payouts", column: "payout_id"
  add_foreign_key "reseller_commissions", "resellers"
  add_foreign_key "reseller_payouts", "resellers"
  add_foreign_key "reseller_payouts", "users", column: "processed_by_id"
  add_foreign_key "reseller_referrals", "accounts", column: "referred_account_id"
  add_foreign_key "reseller_referrals", "resellers"
  add_foreign_key "resellers", "accounts"
  add_foreign_key "resellers", "users", column: "approved_by_id"
  add_foreign_key "resellers", "users", column: "primary_user_id"
  add_foreign_key "revenue_forecasts", "accounts"
  add_foreign_key "revenue_snapshots", "accounts"
  add_foreign_key "role_permissions", "permissions"
  add_foreign_key "role_permissions", "roles"
  add_foreign_key "scheduled_reports", "accounts"
  add_foreign_key "scheduled_reports", "users", column: "created_by_id"
  add_foreign_key "shared_prompt_templates", "accounts", on_delete: :cascade
  add_foreign_key "shared_prompt_templates", "shared_prompt_templates", column: "parent_template_id", on_delete: :nullify
  add_foreign_key "shared_prompt_templates", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "subscriptions", "accounts"
  add_foreign_key "subscriptions", "plans"
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
  add_foreign_key "supply_chain_remediation_plans", "ai_workflow_runs", column: "workflow_run_id"
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
  add_foreign_key "supply_chain_sboms", "devops_repositories", column: "repository_id"
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
  add_foreign_key "task_executions", "scheduled_tasks"
  add_foreign_key "terms_acceptances", "accounts"
  add_foreign_key "terms_acceptances", "users"
  add_foreign_key "usage_events", "accounts"
  add_foreign_key "usage_events", "usage_meters"
  add_foreign_key "usage_events", "users"
  add_foreign_key "usage_quotas", "accounts"
  add_foreign_key "usage_quotas", "plans"
  add_foreign_key "usage_quotas", "usage_meters"
  add_foreign_key "usage_summaries", "accounts"
  add_foreign_key "usage_summaries", "invoices"
  add_foreign_key "usage_summaries", "subscriptions"
  add_foreign_key "usage_summaries", "usage_meters"
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
  add_foreign_key "webhook_events", "payments"
  add_foreign_key "worker_activities", "workers"
  add_foreign_key "worker_roles", "roles"
  add_foreign_key "worker_roles", "workers"
  add_foreign_key "workers", "accounts"
  add_foreign_key "workflow_validations", "ai_workflows", column: "workflow_id"
end
