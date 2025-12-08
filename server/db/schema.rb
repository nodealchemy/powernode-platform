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

ActiveRecord::Schema[8.0].define(version: 2025_12_08_000001) do
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
    t.index ["delegated_by_id"], name: "index_account_delegations_on_delegated_by_id"
    t.index ["delegated_user_id"], name: "index_account_delegations_on_delegated_user_id"
    t.index ["expires_at"], name: "index_account_delegations_on_expires_at"
    t.index ["revoked_by_id"], name: "index_account_delegations_on_revoked_by_id"
    t.index ["role_id"], name: "index_account_delegations_on_role_id"
    t.index ["status"], name: "index_account_delegations_on_status"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'revoked'::character varying::text])", name: "valid_delegation_status"
  end

  create_table "account_terminations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "requested_by_id"
    t.uuid "cancelled_by_id"
    t.uuid "processed_by_id"
    t.string "status", default: "pending", null: false
    t.text "reason"
    t.text "cancellation_reason"
    t.datetime "requested_at", null: false
    t.datetime "grace_period_ends_at", null: false
    t.datetime "cancelled_at"
    t.datetime "processing_started_at"
    t.datetime "completed_at"
    t.boolean "data_export_requested", default: false
    t.uuid "data_export_request_id"
    t.boolean "feedback_submitted", default: false
    t.text "feedback"
    t.jsonb "termination_log", default: []
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
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

  create_table "ai_agent_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_agent_id", null: false
    t.uuid "account_id", null: false
    t.uuid "user_id", null: false
    t.uuid "ai_provider_id", null: false
    t.string "execution_id", limit: 100, null: false
    t.string "status", default: "pending", null: false
    t.jsonb "input_parameters", default: {}, null: false
    t.jsonb "output_data", default: {}
    t.jsonb "execution_context", default: {}
    t.text "error_message"
    t.jsonb "error_details", default: {}
    t.datetime "started_at", precision: nil
    t.datetime "completed_at", precision: nil
    t.integer "duration_ms"
    t.integer "tokens_used", default: 0
    t.decimal "cost_usd", precision: 10, scale: 4, default: "0.0"
    t.jsonb "performance_metrics", default: {}
    t.uuid "parent_execution_id"
    t.string "webhook_url"
    t.jsonb "webhook_data", default: {}
    t.integer "webhook_attempts", default: 0
    t.datetime "webhook_last_attempt_at", precision: nil
    t.string "webhook_status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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

  create_table "ai_agent_messages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_workflow_run_id", null: false
    t.string "message_id", null: false
    t.string "from_agent_id", null: false
    t.string "to_agent_id"
    t.string "message_type", default: "direct", null: false
    t.string "communication_pattern", default: "request_response", null: false
    t.jsonb "message_content", default: {}, null: false
    t.jsonb "metadata", default: {}
    t.string "status", default: "sent", null: false
    t.string "in_reply_to_message_id"
    t.integer "sequence_number", null: false
    t.datetime "delivered_at", precision: nil
    t.datetime "acknowledged_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_workflow_run_id", "sequence_number"], name: "index_agent_messages_on_run_and_sequence"
    t.index ["ai_workflow_run_id"], name: "index_ai_agent_messages_on_ai_workflow_run_id"
    t.index ["from_agent_id", "to_agent_id"], name: "index_agent_messages_on_sender_receiver"
    t.index ["from_agent_id"], name: "index_ai_agent_messages_on_from_agent_id"
    t.index ["in_reply_to_message_id"], name: "index_ai_agent_messages_on_in_reply_to_message_id"
    t.index ["message_id"], name: "index_ai_agent_messages_on_message_id", unique: true
    t.index ["message_type"], name: "index_ai_agent_messages_on_message_type"
    t.index ["status"], name: "index_ai_agent_messages_on_status"
    t.index ["to_agent_id"], name: "index_ai_agent_messages_on_to_agent_id"
  end

  create_table "ai_agent_team_members", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_agent_team_id", null: false, comment: "Team this member belongs to"
    t.uuid "ai_agent_id", null: false, comment: "Agent assigned to this team role"
    t.string "role", null: false, comment: "Role in team: manager, researcher, writer, reviewer, executor"
    t.jsonb "capabilities", default: [], null: false, comment: "Specific capabilities this member provides to the team"
    t.integer "priority_order", default: 0, null: false, comment: "Execution priority (0 = highest, for sequential teams)"
    t.boolean "is_lead", default: false, null: false, comment: "Whether this member leads/coordinates the team"
    t.jsonb "member_config", default: {}, null: false, comment: "Member-specific configuration (retry_count, timeout, etc.)"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_agent_id"], name: "index_ai_agent_team_members_on_ai_agent_id"
    t.index ["ai_agent_team_id", "ai_agent_id"], name: "index_team_members_on_team_and_agent", unique: true
    t.index ["ai_agent_team_id", "is_lead"], name: "index_team_members_on_team_and_lead"
    t.index ["ai_agent_team_id", "priority_order"], name: "index_team_members_on_team_and_priority"
    t.index ["ai_agent_team_id"], name: "index_ai_agent_team_members_on_ai_agent_team_id"
  end

  create_table "ai_agent_teams", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false, comment: "Account that owns this team"
    t.string "name", null: false, comment: "Team name (e.g., \"Content Generation Crew\", \"Research Team\")"
    t.text "description", comment: "Team purpose and capabilities description"
    t.string "team_type", default: "hierarchical", null: false, comment: "Team coordination type: hierarchical, mesh, sequential, parallel"
    t.text "goal_description", comment: "High-level goal the team works toward"
    t.string "coordination_strategy", default: "manager_worker", null: false, comment: "Coordination pattern: manager_worker, peer_to_peer, hybrid"
    t.jsonb "team_config", default: {}, null: false, comment: "Team-specific configuration (max_iterations, timeout, etc.)"
    t.string "status", default: "active", null: false, comment: "Team status: active, inactive, archived"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_ai_agent_teams_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_agent_teams_on_account_id"
    t.index ["team_type"], name: "index_ai_agent_teams_on_team_type"
    t.check_constraint "coordination_strategy::text = ANY (ARRAY['manager_worker'::character varying::text, 'peer_to_peer'::character varying::text, 'hybrid'::character varying::text])", name: "ai_agent_teams_coordination_strategy_check"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'archived'::character varying::text])", name: "ai_agent_teams_status_check"
    t.check_constraint "team_type::text = ANY (ARRAY['hierarchical'::character varying::text, 'mesh'::character varying::text, 'sequential'::character varying::text, 'parallel'::character varying::text])", name: "ai_agent_teams_team_type_check"
  end

  create_table "ai_agents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "creator_id", null: false
    t.string "name", limit: 255, null: false
    t.string "slug", limit: 150, null: false
    t.text "description"
    t.string "agent_type", limit: 50, null: false
    t.string "status", default: "active", null: false
    t.jsonb "metadata", default: {}, null: false
    t.boolean "is_public", default: false
    t.string "version", limit: 20, default: "1.0.0", null: false
    t.datetime "last_executed_at", precision: nil
    t.jsonb "execution_stats", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "ai_provider_id", null: false
    t.jsonb "mcp_tool_manifest", default: {}, null: false, comment: "Complete MCP tool manifest for agent registration"
    t.jsonb "mcp_input_schema", default: {}, null: false, comment: "JSON Schema for validating agent input parameters"
    t.jsonb "mcp_output_schema", default: {}, null: false, comment: "JSON Schema for validating agent output"
    t.jsonb "mcp_capabilities", default: [], null: false, comment: "Array of MCP capabilities supported by this agent"
    t.jsonb "mcp_metadata", default: {}, null: false, comment: "Additional MCP-specific metadata"
    t.datetime "mcp_registered_at", precision: nil
    t.index ["account_id", "name"], name: "index_ai_agents_on_account_id_and_name"
    t.index ["account_id", "status"], name: "index_ai_agents_on_account_and_status"
    t.index ["account_id"], name: "index_ai_agents_on_account_id"
    t.index ["agent_type"], name: "index_ai_agents_on_agent_type"
    t.index ["ai_provider_id"], name: "index_ai_agents_on_ai_provider_id"
    t.index ["creator_id"], name: "index_ai_agents_on_creator_id"
    t.index ["is_public"], name: "index_ai_agents_on_is_public"
    t.index ["last_executed_at"], name: "index_ai_agents_on_last_executed_at"
    t.index ["mcp_capabilities"], name: "index_ai_agents_on_mcp_capabilities", using: :gin
    t.index ["mcp_registered_at"], name: "index_ai_agents_on_mcp_registered_at"
    t.index ["mcp_tool_manifest"], name: "index_ai_agents_on_mcp_tool_manifest", using: :gin
    t.index ["slug"], name: "index_ai_agents_on_slug", unique: true
    t.index ["status"], name: "index_ai_agents_on_status"
  end

  create_table "ai_conversations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "user_id", null: false
    t.uuid "ai_agent_id"
    t.uuid "ai_provider_id", null: false
    t.string "conversation_id", limit: 100, null: false
    t.string "title", limit: 255
    t.text "summary"
    t.string "status", default: "active", null: false
    t.jsonb "conversation_context", default: {}
    t.jsonb "metadata", default: {}
    t.integer "message_count", default: 0
    t.integer "total_tokens", default: 0
    t.decimal "total_cost", precision: 10, scale: 4, default: "0.0"
    t.datetime "last_activity_at", precision: nil
    t.uuid "websocket_session_id"
    t.string "websocket_channel"
    t.boolean "is_collaborative", default: false
    t.jsonb "participants", default: []
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_ai_conversations_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_conversations_on_account_id"
    t.index ["ai_agent_id"], name: "index_ai_conversations_on_ai_agent_id"
    t.index ["ai_provider_id"], name: "index_ai_conversations_on_ai_provider_id"
    t.index ["conversation_id"], name: "index_ai_conversations_on_conversation_id", unique: true
    t.index ["last_activity_at"], name: "index_ai_conversations_on_last_activity_at"
    t.index ["participants"], name: "index_ai_conversations_on_participants", using: :gin
    t.index ["status"], name: "index_ai_conversations_on_status"
    t.index ["user_id", "status"], name: "index_ai_conversations_on_user_id_and_status"
    t.index ["user_id"], name: "index_ai_conversations_on_user_id"
    t.index ["websocket_channel"], name: "index_ai_conversations_on_websocket_channel"
    t.index ["websocket_session_id"], name: "index_ai_conversations_on_websocket_session_id"
  end

  create_table "ai_messages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_conversation_id", null: false
    t.uuid "user_id"
    t.string "message_id", limit: 100, null: false
    t.string "role", limit: 20, null: false
    t.text "content", null: false
    t.jsonb "content_metadata", default: {}
    t.string "message_type", limit: 50, default: "text"
    t.jsonb "attachments", default: []
    t.integer "token_count", default: 0
    t.decimal "cost_usd", precision: 8, scale: 4, default: "0.0"
    t.jsonb "processing_metadata", default: {}
    t.string "status", limit: 20, default: "sent"
    t.text "error_message"
    t.datetime "processed_at", precision: nil
    t.integer "sequence_number"
    t.uuid "parent_message_id"
    t.boolean "is_edited", default: false
    t.datetime "edited_at", precision: nil
    t.jsonb "edit_history", default: []
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "ai_agent_id", null: false
    t.index ["ai_agent_id"], name: "index_ai_messages_on_ai_agent_id"
    t.index ["ai_conversation_id", "role"], name: "index_ai_messages_on_ai_conversation_id_and_role"
    t.index ["ai_conversation_id", "sequence_number"], name: "index_ai_messages_on_ai_conversation_id_and_sequence_number"
    t.index ["ai_conversation_id"], name: "index_ai_messages_on_ai_conversation_id"
    t.index ["attachments"], name: "index_ai_messages_on_attachments", using: :gin
    t.index ["edit_history"], name: "index_ai_messages_on_edit_history", using: :gin
    t.index ["message_id"], name: "index_ai_messages_on_message_id", unique: true
    t.index ["message_type"], name: "index_ai_messages_on_message_type"
    t.index ["parent_message_id"], name: "index_ai_messages_on_parent_message_id"
    t.index ["processed_at"], name: "index_ai_messages_on_processed_at"
    t.index ["role"], name: "index_ai_messages_on_role"
    t.index ["sequence_number"], name: "index_ai_messages_on_sequence_number"
    t.index ["status"], name: "index_ai_messages_on_status"
    t.index ["user_id"], name: "index_ai_messages_on_user_id"
  end

  create_table "ai_provider_credentials", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_provider_id", null: false
    t.uuid "account_id", null: false
    t.string "name", limit: 255, null: false
    t.text "encrypted_credentials", null: false
    t.string "encryption_key_id", limit: 50
    t.boolean "is_active", default: true
    t.boolean "is_default", default: false
    t.datetime "expires_at", precision: nil
    t.jsonb "access_scopes", default: []
    t.jsonb "rate_limits", default: {}
    t.jsonb "usage_stats", default: {}
    t.datetime "last_used_at", precision: nil
    t.string "last_error"
    t.integer "consecutive_failures", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_test_at"
    t.string "last_test_status"
    t.integer "success_count", default: 0, null: false
    t.integer "failure_count", default: 0, null: false
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
  end

  create_table "ai_provider_plugins", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "plugin_id", null: false
    t.string "provider_type", null: false
    t.jsonb "supported_capabilities", default: [], null: false
    t.jsonb "models", default: [], null: false
    t.jsonb "authentication_schema", default: {}, null: false
    t.jsonb "default_configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["plugin_id"], name: "index_ai_provider_plugins_on_plugin_id"
    t.index ["provider_type"], name: "index_ai_provider_plugins_on_provider_type"
    t.index ["supported_capabilities"], name: "index_ai_provider_plugins_on_supported_capabilities", using: :gin
  end

  create_table "ai_providers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.string "slug", limit: 50, null: false
    t.string "provider_type", limit: 50
    t.text "description"
    t.string "api_base_url", limit: 500
    t.jsonb "capabilities", default: [], null: false
    t.jsonb "supported_models", default: [], null: false
    t.jsonb "configuration_schema", default: {}, null: false
    t.jsonb "default_parameters", default: {}
    t.jsonb "rate_limits", default: {}
    t.jsonb "pricing_info", default: {}
    t.boolean "is_active", default: true
    t.boolean "requires_auth", default: true
    t.boolean "supports_streaming", default: false
    t.boolean "supports_functions", default: false
    t.boolean "supports_vision", default: false
    t.boolean "supports_code_execution", default: false
    t.string "documentation_url", limit: 500
    t.string "status_url", limit: 500
    t.integer "priority_order", default: 1000
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "account_id"
    t.string "api_endpoint", limit: 500
    t.string "provider_identifier", limit: 255
    t.index ["account_id", "provider_identifier"], name: "index_ai_providers_on_account_id_and_provider_identifier", unique: true
    t.index ["account_id"], name: "index_ai_providers_on_account_id"
    t.index ["capabilities"], name: "index_ai_providers_on_capabilities", using: :gin
    t.index ["is_active"], name: "index_ai_providers_on_is_active"
    t.index ["name"], name: "index_ai_providers_on_name"
    t.index ["priority_order"], name: "index_ai_providers_on_priority_order"
    t.index ["provider_type", "is_active"], name: "index_ai_providers_on_provider_type_and_is_active"
    t.index ["provider_type"], name: "index_ai_providers_on_provider_type"
    t.index ["slug"], name: "index_ai_providers_on_slug", unique: true
    t.index ["supported_models"], name: "index_ai_providers_on_supported_models", using: :gin
  end

  create_table "ai_shared_context_pools", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_workflow_run_id", null: false
    t.string "pool_id", null: false
    t.string "pool_type", default: "shared_memory", null: false
    t.string "scope", default: "workflow", null: false
    t.jsonb "context_data", default: {}, null: false
    t.jsonb "access_control", default: {}
    t.jsonb "metadata", default: {}
    t.string "created_by_agent_id"
    t.string "owner_agent_id"
    t.integer "version", default: 1, null: false
    t.datetime "last_accessed_at", precision: nil
    t.datetime "expires_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_workflow_run_id", "pool_type"], name: "index_context_pools_on_run_and_type"
    t.index ["ai_workflow_run_id", "scope"], name: "index_context_pools_on_run_and_scope"
    t.index ["ai_workflow_run_id"], name: "index_ai_shared_context_pools_on_ai_workflow_run_id"
    t.index ["owner_agent_id"], name: "index_ai_shared_context_pools_on_owner_agent_id"
    t.index ["pool_id"], name: "index_ai_shared_context_pools_on_pool_id", unique: true
    t.index ["pool_type"], name: "index_ai_shared_context_pools_on_pool_type"
    t.index ["scope"], name: "index_ai_shared_context_pools_on_scope"
  end

  create_table "ai_workflow_checkpoints", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_workflow_run_id", null: false
    t.string "checkpoint_id", null: false
    t.string "node_id", null: false
    t.string "checkpoint_type", default: "node_completion", null: false
    t.integer "sequence_number", null: false
    t.jsonb "workflow_state", default: {}, null: false
    t.jsonb "execution_context", default: {}, null: false
    t.jsonb "variable_snapshot", default: {}
    t.jsonb "metadata", default: {}
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_workflow_run_id", "checkpoint_id"], name: "index_checkpoints_on_run_and_id", unique: true
    t.index ["ai_workflow_run_id", "sequence_number"], name: "index_checkpoints_on_run_and_sequence"
    t.index ["ai_workflow_run_id"], name: "index_ai_workflow_checkpoints_on_ai_workflow_run_id"
    t.index ["checkpoint_id"], name: "index_ai_workflow_checkpoints_on_checkpoint_id"
    t.index ["sequence_number"], name: "index_ai_workflow_checkpoints_on_sequence_number"
  end

  create_table "ai_workflow_compensations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_workflow_run_id", null: false
    t.string "compensation_id", null: false
    t.uuid "ai_workflow_node_execution_id", null: false
    t.string "compensation_type", default: "rollback", null: false
    t.string "trigger_reason", null: false
    t.string "status", default: "pending", null: false
    t.jsonb "original_action", default: {}, null: false
    t.jsonb "compensation_action", default: {}, null: false
    t.jsonb "compensation_result", default: {}
    t.jsonb "metadata", default: {}
    t.integer "retry_count", default: 0
    t.integer "max_retries", default: 3
    t.datetime "executed_at", precision: nil
    t.datetime "completed_at", precision: nil
    t.datetime "failed_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_workflow_run_id", "status"], name: "index_compensations_on_run_and_status"
    t.index ["compensation_id"], name: "index_ai_workflow_compensations_on_compensation_id", unique: true
  end

  create_table "ai_workflow_edges", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_workflow_id", null: false
    t.string "edge_id", limit: 100, null: false
    t.string "source_node_id", limit: 100, null: false
    t.string "target_node_id", limit: 100, null: false
    t.string "source_handle", limit: 50
    t.string "target_handle", limit: 50
    t.string "edge_type", default: "default", null: false
    t.jsonb "condition", default: {}, null: false
    t.jsonb "configuration", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.boolean "is_conditional", default: false, null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
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
    t.uuid "user_id", null: false
    t.string "name", limit: 255, null: false
    t.string "execution_id", limit: 255, null: false
    t.string "status", limit: 50, default: "initializing", null: false
    t.json "configuration", default: "{}", null: false
    t.json "results", default: "[]"
    t.json "metadata", default: "{}"
    t.datetime "started_at", precision: nil
    t.datetime "completed_at", precision: nil
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"], name: "index_ai_workflow_executions_on_account_id_and_created_at"
    t.index ["account_id", "status"], name: "index_ai_workflow_executions_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_workflow_executions_on_account_id"
    t.index ["created_at"], name: "index_ai_workflow_executions_on_created_at"
    t.index ["execution_id"], name: "index_ai_workflow_executions_on_execution_id", unique: true
    t.index ["status"], name: "index_ai_workflow_executions_on_status"
    t.index ["user_id"], name: "index_ai_workflow_executions_on_user_id"
  end

  create_table "ai_workflow_node_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_workflow_run_id", null: false
    t.uuid "ai_workflow_node_id", null: false
    t.uuid "ai_agent_execution_id"
    t.string "execution_id", limit: 100, null: false
    t.string "status", default: "pending", null: false
    t.string "node_id", limit: 100, null: false
    t.string "node_type", limit: 50, null: false
    t.jsonb "input_data", default: {}, null: false
    t.jsonb "output_data", default: {}, null: false
    t.jsonb "configuration_snapshot", default: {}, null: false
    t.jsonb "error_details", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "cancelled_at"
    t.integer "duration_ms"
    t.decimal "cost", precision: 10, scale: 6, default: "0.0"
    t.integer "retry_count", default: 0, null: false
    t.integer "max_retries", default: 0, null: false
    t.datetime "created_at", null: false
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
    t.string "node_id", limit: 100, null: false
    t.string "node_type", limit: 50, null: false
    t.string "name", limit: 255, null: false
    t.text "description"
    t.jsonb "position", default: {}, null: false
    t.jsonb "configuration", default: {}, null: false
    t.jsonb "validation_rules", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.boolean "is_start_node", default: false, null: false
    t.boolean "is_end_node", default: false, null: false
    t.boolean "is_error_handler", default: false, null: false
    t.string "error_node_id", limit: 100
    t.integer "timeout_seconds", default: 300
    t.integer "retry_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "mcp_tool_config", default: {}, null: false, comment: "MCP tool configuration for this node"
    t.string "mcp_tool_id", comment: "ID of the MCP tool used by this node"
    t.string "mcp_tool_version"
    t.uuid "plugin_id"
    t.index ["ai_workflow_id", "is_end_node"], name: "index_ai_workflow_nodes_on_ai_workflow_id_and_is_end_node"
    t.index ["ai_workflow_id", "is_start_node"], name: "index_ai_workflow_nodes_on_ai_workflow_id_and_is_start_node"
    t.index ["ai_workflow_id", "node_id"], name: "index_workflow_nodes_on_workflow_node_id", unique: true
    t.index ["ai_workflow_id", "node_type"], name: "index_ai_workflow_nodes_on_ai_workflow_id_and_node_type"
    t.index ["ai_workflow_id"], name: "index_ai_workflow_nodes_on_ai_workflow_id"
    t.index ["mcp_tool_id", "mcp_tool_version"], name: "index_workflow_nodes_on_mcp_tool_and_version"
    t.index ["mcp_tool_id"], name: "index_ai_workflow_nodes_on_mcp_tool_id"
    t.index ["plugin_id"], name: "index_ai_workflow_nodes_on_plugin_id"
    t.check_constraint "node_type::text = ANY (ARRAY['start'::character varying::text, 'end'::character varying::text, 'trigger'::character varying::text, 'ai_agent'::character varying::text, 'prompt_template'::character varying::text, 'data_processor'::character varying::text, 'transform'::character varying::text, 'condition'::character varying::text, 'loop'::character varying::text, 'delay'::character varying::text, 'merge'::character varying::text, 'split'::character varying::text, 'database'::character varying::text, 'file'::character varying::text, 'validator'::character varying::text, 'email'::character varying::text, 'notification'::character varying::text, 'api_call'::character varying::text, 'webhook'::character varying::text, 'scheduler'::character varying::text, 'human_approval'::character varying::text, 'sub_workflow'::character varying::text, 'kb_article_create'::character varying::text, 'kb_article_read'::character varying::text, 'kb_article_update'::character varying::text, 'kb_article_search'::character varying::text, 'kb_article_publish'::character varying::text, 'page_create'::character varying::text, 'page_read'::character varying::text, 'page_update'::character varying::text, 'page_publish'::character varying::text])", name: "ai_workflow_nodes_type_check"
    t.check_constraint "retry_count >= 0", name: "ai_workflow_nodes_retry_check"
    t.check_constraint "timeout_seconds > 0", name: "ai_workflow_nodes_timeout_check"
  end

  create_table "ai_workflow_run_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_workflow_run_id", null: false
    t.uuid "ai_workflow_node_execution_id"
    t.string "log_level", default: "info", null: false
    t.string "event_type", null: false
    t.text "message", null: false
    t.jsonb "context_data", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "node_id", limit: 100
    t.string "source", limit: 100
    t.datetime "logged_at", null: false
    t.datetime "created_at", null: false
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
    t.uuid "ai_workflow_id", null: false
    t.uuid "account_id", null: false
    t.uuid "triggered_by_user_id"
    t.uuid "ai_workflow_trigger_id"
    t.string "run_id", limit: 100, null: false
    t.string "status", default: "initializing", null: false
    t.string "trigger_type", null: false
    t.jsonb "input_variables", default: {}, null: false
    t.jsonb "output_variables", default: {}, null: false
    t.jsonb "runtime_context", default: {}, null: false
    t.jsonb "error_details", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "cancelled_at"
    t.integer "total_nodes", default: 0, null: false
    t.integer "completed_nodes", default: 0, null: false
    t.integer "failed_nodes", default: 0, null: false
    t.integer "duration_ms"
    t.decimal "total_cost", precision: 10, scale: 6, default: "0.0"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "mcp_execution_context", default: {}, null: false, comment: "MCP execution context and state"
    t.string "current_node_id"
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
    t.uuid "created_by_id", null: false
    t.string "name", limit: 255, null: false
    t.text "description"
    t.string "cron_expression", null: false
    t.string "timezone", default: "UTC", null: false
    t.string "status", default: "active", null: false
    t.jsonb "input_variables", default: {}, null: false
    t.jsonb "configuration", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "starts_at"
    t.datetime "ends_at"
    t.datetime "next_execution_at"
    t.datetime "last_execution_at"
    t.integer "execution_count", default: 0, null: false
    t.integer "max_executions"
    t.boolean "is_active", default: true, null: false
    t.datetime "created_at", null: false
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

  create_table "ai_workflow_template_installations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_workflow_template_id", null: false
    t.uuid "ai_workflow_id", null: false
    t.uuid "account_id", null: false
    t.uuid "installed_by_user_id", null: false
    t.string "installation_id", limit: 100, null: false
    t.string "template_version", limit: 50, null: false
    t.jsonb "customizations", default: {}, null: false
    t.jsonb "variable_mappings", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.boolean "auto_update", default: false, null: false
    t.datetime "last_updated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "installed_by_user_id"], name: "idx_on_account_id_installed_by_user_id_9c10406073"
    t.index ["account_id"], name: "index_ai_workflow_template_installations_on_account_id"
    t.index ["ai_workflow_id"], name: "index_ai_workflow_template_installations_on_ai_workflow_id"
    t.index ["ai_workflow_template_id", "account_id"], name: "idx_on_ai_workflow_template_id_account_id_43e6c33988"
    t.index ["ai_workflow_template_id"], name: "idx_on_ai_workflow_template_id_95f5a8c354"
    t.index ["installation_id"], name: "index_ai_workflow_template_installations_on_installation_id", unique: true
    t.index ["installed_by_user_id"], name: "idx_on_installed_by_user_id_3082e94475"
    t.index ["last_updated_at"], name: "index_ai_workflow_template_installations_on_last_updated_at"
    t.index ["template_version"], name: "index_ai_workflow_template_installations_on_template_version"
  end

  create_table "ai_workflow_templates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", limit: 255, null: false
    t.string "slug", limit: 150, null: false
    t.text "description", null: false
    t.text "long_description"
    t.string "category", limit: 100, null: false
    t.string "difficulty_level", default: "beginner", null: false
    t.jsonb "workflow_definition", null: false
    t.jsonb "default_variables", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "tags", default: [], null: false
    t.string "author_name", limit: 255
    t.string "author_email", limit: 255
    t.string "author_url", limit: 500
    t.string "license", limit: 100, default: "MIT"
    t.string "version", default: "1.0.0", null: false
    t.integer "usage_count", default: 0, null: false
    t.decimal "rating", precision: 3, scale: 2, default: "0.0"
    t.integer "rating_count", default: 0, null: false
    t.boolean "is_featured", default: false, null: false
    t.boolean "is_public", default: false, null: false
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "account_id"
    t.uuid "created_by_user_id"
    t.index ["account_id", "is_public"], name: "index_ai_workflow_templates_on_account_id_and_is_public"
    t.index ["account_id"], name: "index_ai_workflow_templates_on_account_id"
    t.index ["category", "is_public"], name: "index_ai_workflow_templates_on_category_and_is_public"
    t.index ["created_by_user_id"], name: "index_ai_workflow_templates_on_created_by_user_id"
    t.index ["difficulty_level"], name: "index_ai_workflow_templates_on_difficulty_level"
    t.index ["is_featured", "is_public"], name: "index_ai_workflow_templates_on_is_featured_and_is_public"
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
    t.string "name", limit: 255, null: false
    t.string "trigger_type", null: false
    t.string "status", default: "active", null: false
    t.jsonb "configuration", default: {}, null: false
    t.jsonb "conditions", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "webhook_url", limit: 2048
    t.string "webhook_secret"
    t.string "schedule_cron"
    t.datetime "next_execution_at"
    t.datetime "last_triggered_at"
    t.integer "trigger_count", default: 0, null: false
    t.boolean "is_active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.string "name", limit: 100, null: false
    t.string "variable_type", default: "string", null: false
    t.text "description"
    t.jsonb "default_value"
    t.jsonb "validation_rules", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.boolean "is_required", default: false, null: false
    t.boolean "is_input", default: false, null: false
    t.boolean "is_output", default: false, null: false
    t.boolean "is_secret", default: false, null: false
    t.string "scope", default: "workflow", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.uuid "creator_id", null: false
    t.string "name", limit: 255, null: false
    t.string "slug", limit: 150, null: false
    t.text "description"
    t.string "status", default: "draft", null: false
    t.string "visibility", default: "private", null: false
    t.jsonb "configuration", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.boolean "is_template", default: false, null: false
    t.string "template_category", limit: 100
    t.string "version", default: "1.0.0", null: false
    t.datetime "published_at"
    t.datetime "last_executed_at"
    t.integer "execution_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "mcp_orchestration_config", default: {}, null: false, comment: "MCP-specific orchestration configuration"
    t.jsonb "mcp_tool_requirements", default: [], null: false, comment: "Array of required MCP tools for workflow execution"
    t.jsonb "mcp_input_schema", default: {}, null: false
    t.jsonb "mcp_output_schema", default: {}, null: false
    t.uuid "parent_version_id"
    t.boolean "is_active", default: true, null: false
    t.text "change_summary"
    t.jsonb "version_metadata", default: {}
    t.index ["account_id", "name", "version"], name: "index_workflows_on_account_name_version", unique: true
    t.index ["account_id", "slug"], name: "index_ai_workflows_on_account_slug", unique: true
    t.index ["account_id", "status"], name: "index_ai_workflows_on_account_id_and_status"
    t.index ["account_id"], name: "index_ai_workflows_on_account_id"
    t.index ["creator_id"], name: "index_ai_workflows_on_creator_id"
    t.index ["is_active"], name: "index_ai_workflows_on_is_active"
    t.index ["is_template", "template_category"], name: "index_ai_workflows_on_is_template_and_template_category"
    t.index ["last_executed_at"], name: "index_ai_workflows_on_last_executed_at"
    t.index ["mcp_tool_requirements"], name: "index_ai_workflows_on_mcp_tool_requirements", using: :gin
    t.index ["parent_version_id"], name: "index_ai_workflows_on_parent_version_id"
    t.index ["published_at"], name: "index_ai_workflows_on_published_at"
    t.index ["version"], name: "index_ai_workflows_on_version"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'active'::character varying::text, 'paused'::character varying::text, 'inactive'::character varying::text, 'archived'::character varying::text])", name: "ai_workflows_status_check"
    t.check_constraint "template_category IS NULL OR template_category::text <> ''::text", name: "ai_workflows_template_category_check"
    t.check_constraint "visibility::text = ANY (ARRAY['private'::character varying::text, 'account'::character varying::text, 'public'::character varying::text])", name: "ai_workflows_visibility_check"
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
    t.integer "request_count", default: 1, null: false
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
    t.string "key_prefix", limit: 20
    t.string "key_suffix", limit: 20
    t.jsonb "permissions", default: []
    t.jsonb "scopes", default: []
    t.jsonb "allowed_ips", default: []
    t.jsonb "rate_limits", default: {}
    t.integer "usage_count", default: 0
    t.integer "rate_limit_per_hour"
    t.integer "rate_limit_per_day"
    t.jsonb "metadata", default: {}
    t.boolean "is_active", default: true
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.string "last_used_ip", limit: 45
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.string "severity", default: "medium", null: false
    t.string "risk_level", default: "low", null: false
    t.string "request_id", limit: 50
    t.string "integrity_hash"
    t.string "previous_hash"
    t.bigint "sequence_number"
    t.datetime "chain_verified_at"
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

  create_table "batch_workflow_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "batch_id", null: false
    t.uuid "account_id", null: false
    t.uuid "user_id"
    t.integer "total_workflows", default: 0, null: false
    t.integer "completed_workflows", default: 0
    t.integer "successful_workflows", default: 0
    t.integer "failed_workflows", default: 0
    t.string "status", default: "pending", null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.integer "duration_ms"
    t.jsonb "configuration", default: {}
    t.jsonb "results", default: []
    t.jsonb "statistics", default: {}
    t.jsonb "error_details", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.uuid "user_id", null: false
    t.string "token", null: false
    t.string "reason", default: "logout"
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["expires_at"], name: "index_blacklisted_tokens_on_expires_at"
    t.index ["token"], name: "index_blacklisted_tokens_on_token", unique: true
    t.index ["user_id"], name: "index_blacklisted_tokens_on_user_id"
  end

  create_table "circuit_breaker_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "circuit_breaker_id", null: false
    t.string "event_type", null: false
    t.string "old_state"
    t.string "new_state"
    t.integer "failure_count"
    t.text "error_message"
    t.integer "duration_ms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["circuit_breaker_id", "created_at"], name: "idx_on_circuit_breaker_id_created_at_017ec04aab"
    t.index ["circuit_breaker_id"], name: "index_circuit_breaker_events_on_circuit_breaker_id"
    t.index ["event_type"], name: "index_circuit_breaker_events_on_event_type"
  end

  create_table "circuit_breakers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "service", null: false
    t.string "provider"
    t.string "state", default: "closed", null: false
    t.integer "failure_count", default: 0
    t.integer "failure_threshold", default: 5, null: false
    t.integer "success_count", default: 0
    t.integer "success_threshold", default: 2, null: false
    t.integer "timeout_seconds", default: 30
    t.integer "reset_timeout_seconds", default: 60
    t.jsonb "configuration", default: {}
    t.jsonb "metrics", default: {}
    t.datetime "last_failure_at"
    t.datetime "last_success_at"
    t.datetime "opened_at"
    t.datetime "half_opened_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name", "service"], name: "index_circuit_breakers_on_name_and_service", unique: true
    t.index ["service", "state"], name: "index_circuit_breakers_on_service_and_state"
    t.index ["state"], name: "index_circuit_breakers_on_state"
  end

  create_table "cookie_consents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id"
    t.string "visitor_id"
    t.boolean "necessary", default: true, null: false
    t.boolean "functional", default: false
    t.boolean "analytics", default: false
    t.boolean "marketing", default: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "consented_at", null: false
    t.datetime "updated_at_user"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_cookie_consents_on_user_id", unique: true, where: "(user_id IS NOT NULL)"
    t.index ["visitor_id"], name: "index_cookie_consents_on_visitor_id", unique: true, where: "(visitor_id IS NOT NULL)"
  end

  create_table "data_deletion_requests", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.uuid "account_id", null: false
    t.uuid "requested_by_id"
    t.uuid "processed_by_id"
    t.string "status", default: "pending", null: false
    t.string "deletion_type", default: "full", null: false
    t.jsonb "data_types_to_delete", default: []
    t.jsonb "data_types_to_retain", default: []
    t.text "reason"
    t.text "rejection_reason"
    t.datetime "approved_at"
    t.datetime "processing_started_at"
    t.datetime "completed_at"
    t.datetime "grace_period_ends_at"
    t.boolean "grace_period_extended", default: false
    t.jsonb "deletion_log", default: []
    t.jsonb "retention_log", default: []
    t.text "error_message"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_data_deletion_requests_on_account_id"
    t.index ["deletion_type"], name: "index_data_deletion_requests_on_deletion_type"
    t.index ["grace_period_ends_at"], name: "index_data_deletion_requests_on_grace_period_ends_at"
    t.index ["processed_by_id"], name: "index_data_deletion_requests_on_processed_by_id"
    t.index ["requested_by_id"], name: "index_data_deletion_requests_on_requested_by_id"
    t.index ["status"], name: "index_data_deletion_requests_on_status"
    t.index ["user_id"], name: "index_data_deletion_requests_on_user_id"
  end

  create_table "data_export_requests", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.uuid "account_id", null: false
    t.uuid "requested_by_id"
    t.string "status", default: "pending", null: false
    t.string "format", default: "json", null: false
    t.string "export_type", default: "full"
    t.jsonb "include_data_types", default: []
    t.jsonb "exclude_data_types", default: []
    t.string "file_path"
    t.integer "file_size_bytes"
    t.string "download_token"
    t.datetime "download_token_expires_at"
    t.datetime "processing_started_at"
    t.datetime "completed_at"
    t.datetime "downloaded_at"
    t.datetime "expires_at"
    t.text "error_message"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_data_export_requests_on_account_id"
    t.index ["download_token"], name: "index_data_export_requests_on_download_token", unique: true, where: "(download_token IS NOT NULL)"
    t.index ["expires_at"], name: "index_data_export_requests_on_expires_at"
    t.index ["requested_by_id"], name: "index_data_export_requests_on_requested_by_id"
    t.index ["status"], name: "index_data_export_requests_on_status"
    t.index ["user_id"], name: "index_data_export_requests_on_user_id"
  end

  create_table "data_retention_policies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.string "data_type", null: false
    t.integer "retention_days", null: false
    t.string "action", default: "delete", null: false
    t.boolean "active", default: true
    t.string "legal_basis"
    t.text "description"
    t.datetime "last_enforced_at"
    t.integer "records_processed_count", default: 0
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "data_type"], name: "index_data_retention_policies_on_account_id_and_data_type", unique: true
    t.index ["account_id"], name: "index_data_retention_policies_on_account_id"
    t.index ["active"], name: "index_data_retention_policies_on_active"
    t.index ["data_type"], name: "index_data_retention_policies_on_data_type"
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

  create_table "file_object_tags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "file_object_id", null: false
    t.uuid "file_tag_id", null: false
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_file_object_tags_on_account_id"
    t.index ["file_object_id", "file_tag_id"], name: "index_file_object_tags_on_file_object_id_and_file_tag_id", unique: true
    t.index ["file_object_id"], name: "index_file_object_tags_on_file_object_id"
    t.index ["file_tag_id"], name: "index_file_object_tags_on_file_tag_id"
  end

  create_table "file_objects", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "file_storage_id", null: false
    t.uuid "uploaded_by_id", null: false
    t.string "filename", null: false
    t.string "storage_key", null: false
    t.string "content_type", null: false
    t.bigint "file_size", null: false
    t.string "checksum_md5"
    t.string "checksum_sha256"
    t.string "file_type"
    t.string "category"
    t.string "visibility", default: "private", null: false
    t.string "attachable_type"
    t.uuid "attachable_id"
    t.integer "version", default: 1, null: false
    t.boolean "is_latest_version", default: true, null: false
    t.uuid "parent_file_id"
    t.jsonb "access_permissions", default: {}
    t.datetime "expires_at"
    t.integer "download_count", default: 0, null: false
    t.datetime "last_accessed_at"
    t.string "processing_status", default: "pending"
    t.jsonb "processing_metadata", default: {}
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "exif_data", default: {}
    t.jsonb "dimensions", default: {}
    t.datetime "deleted_at"
    t.uuid "deleted_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.check_constraint "category::text = ANY (ARRAY['user_upload'::character varying::text, 'workflow_output'::character varying::text, 'ai_generated'::character varying::text, 'temp'::character varying::text, 'system'::character varying::text, 'import'::character varying::text])", name: "file_objects_category_check"
    t.check_constraint "file_type::text = ANY (ARRAY['image'::character varying::text, 'document'::character varying::text, 'video'::character varying::text, 'audio'::character varying::text, 'archive'::character varying::text, 'code'::character varying::text, 'data'::character varying::text, 'other'::character varying::text])", name: "file_objects_file_type_check"
    t.check_constraint "processing_status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "file_objects_processing_status_check"
    t.check_constraint "visibility::text = ANY (ARRAY['private'::character varying::text, 'public'::character varying::text, 'shared'::character varying::text, 'internal'::character varying::text])", name: "file_objects_visibility_check"
  end

  create_table "file_processing_jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "file_object_id", null: false
    t.uuid "account_id", null: false
    t.string "job_type", null: false
    t.string "status", default: "pending", null: false
    t.integer "priority", default: 50, null: false
    t.jsonb "job_parameters", default: {}
    t.jsonb "result_data", default: {}
    t.string "output_storage_key"
    t.jsonb "error_details", default: {}
    t.integer "retry_count", default: 0, null: false
    t.integer "max_retries", default: 3, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.integer "duration_ms"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
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
    t.uuid "file_object_id", null: false
    t.uuid "account_id", null: false
    t.uuid "created_by_id", null: false
    t.string "share_token", null: false
    t.string "share_type", null: false
    t.string "access_level", default: "view", null: false
    t.jsonb "recipients", default: []
    t.string "password_digest"
    t.integer "max_downloads"
    t.integer "download_count", default: 0, null: false
    t.datetime "expires_at"
    t.datetime "last_accessed_at"
    t.jsonb "access_log", default: []
    t.string "status", default: "active", null: false
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
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
    t.string "name", null: false
    t.string "provider_type", null: false
    t.string "status", default: "active", null: false
    t.integer "priority", default: 100, null: false
    t.jsonb "configuration", default: {}, null: false
    t.jsonb "capabilities", default: {}, null: false
    t.bigint "files_count", default: 0, null: false
    t.bigint "total_size_bytes", default: 0, null: false
    t.bigint "quota_bytes"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "last_health_check_at"
    t.string "health_status"
    t.jsonb "health_details", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "is_default"
    t.index ["account_id", "name"], name: "index_file_storages_on_account_id_and_name", unique: true
    t.index ["account_id", "provider_type"], name: "index_file_storages_on_account_id_and_provider_type"
    t.index ["account_id", "status"], name: "index_file_storages_on_account_id_and_status"
    t.index ["account_id"], name: "index_file_storages_on_account_id"
    t.index ["configuration"], name: "index_file_storages_on_configuration", using: :gin
    t.index ["health_status"], name: "index_file_storages_on_health_status"
    t.index ["priority"], name: "index_file_storages_on_priority"
    t.check_constraint "provider_type::text = ANY (ARRAY['local'::character varying::text, 's3'::character varying::text, 'gcs'::character varying::text, 'azure'::character varying::text, 'ftp'::character varying::text, 'webdav'::character varying::text, 'custom'::character varying::text])", name: "file_storages_provider_type_check"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'maintenance'::character varying::text, 'failed'::character varying::text])", name: "file_storages_status_check"
  end

  create_table "file_tags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "name", null: false
    t.string "color"
    t.text "description"
    t.integer "files_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_file_tags_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_file_tags_on_account_id"
  end

  create_table "file_versions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "file_object_id", null: false
    t.uuid "account_id", null: false
    t.uuid "created_by_id", null: false
    t.integer "version_number", null: false
    t.string "storage_key", null: false
    t.bigint "file_size", null: false
    t.string "checksum_sha256"
    t.string "change_description"
    t.jsonb "change_metadata", default: {}
    t.jsonb "metadata", default: {}
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"], name: "index_file_versions_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_file_versions_on_account_id"
    t.index ["created_by_id"], name: "index_file_versions_on_created_by_id"
    t.index ["deleted_at"], name: "index_file_versions_on_deleted_at"
    t.index ["file_object_id", "version_number"], name: "index_file_versions_on_file_object_id_and_version_number", unique: true
    t.index ["file_object_id"], name: "index_file_versions_on_file_object_id"
    t.index ["storage_key"], name: "index_file_versions_on_storage_key"
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

  create_table "jwt_blacklists", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "jti", limit: 100, null: false
    t.datetime "expires_at", null: false
    t.uuid "user_id"
    t.string "reason", limit: 100
    t.boolean "user_blacklist", default: false, null: false
    t.text "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_jwt_blacklists_on_expires_at"
    t.index ["jti", "expires_at"], name: "index_jwt_blacklists_on_jti_and_expires_at"
    t.index ["jti"], name: "index_jwt_blacklists_on_jti", unique: true
    t.index ["user_id", "user_blacklist"], name: "index_jwt_blacklists_on_user_id_and_user_blacklist"
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

  create_table "mcp_servers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "name", null: false
    t.text "description"
    t.string "status", default: "disconnected", null: false
    t.string "connection_type", null: false
    t.string "command"
    t.jsonb "args", default: []
    t.jsonb "env", default: {}
    t.jsonb "capabilities", default: {}
    t.datetime "last_health_check"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "auth_type", default: "none", null: false
    t.string "oauth_provider"
    t.string "oauth_client_id"
    t.text "oauth_client_secret_encrypted"
    t.string "oauth_authorization_url"
    t.string "oauth_token_url"
    t.string "oauth_scopes"
    t.text "oauth_access_token_encrypted"
    t.text "oauth_refresh_token_encrypted"
    t.datetime "oauth_token_expires_at"
    t.string "oauth_token_type", default: "Bearer"
    t.string "oauth_pkce_code_verifier"
    t.string "oauth_state"
    t.datetime "oauth_last_refreshed_at"
    t.text "oauth_error"
    t.index ["account_id", "status"], name: "index_mcp_servers_on_account_id_and_status"
    t.index ["account_id"], name: "index_mcp_servers_on_account_id"
    t.index ["auth_type"], name: "index_mcp_servers_on_auth_type"
    t.index ["oauth_state"], name: "index_mcp_servers_on_oauth_state", unique: true, where: "(oauth_state IS NOT NULL)"
    t.index ["oauth_token_expires_at"], name: "index_mcp_servers_on_oauth_token_expires_at"
    t.index ["status"], name: "index_mcp_servers_on_status"
  end

  create_table "mcp_tool_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "mcp_tool_id", null: false
    t.uuid "user_id", null: false
    t.string "status", null: false
    t.jsonb "parameters", default: {}
    t.jsonb "result", default: {}
    t.text "error_message"
    t.integer "execution_time_ms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.integer "duration_ms"
    t.index ["mcp_tool_id", "created_at"], name: "index_mcp_tool_executions_on_mcp_tool_id_and_created_at"
    t.index ["mcp_tool_id"], name: "index_mcp_tool_executions_on_mcp_tool_id"
    t.index ["user_id", "created_at"], name: "index_mcp_tool_executions_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_mcp_tool_executions_on_user_id"
  end

  create_table "mcp_tools", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "mcp_server_id", null: false
    t.string "name", null: false
    t.text "description"
    t.jsonb "input_schema", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "enabled", default: true, null: false
    t.jsonb "required_permissions", default: [], null: false, comment: "Array of permission strings required to execute this tool"
    t.string "permission_level", default: "public", null: false, comment: "Permission level: public, account, admin"
    t.jsonb "allowed_scopes", default: {}, null: false, comment: "Allowed operation scopes (file_access, network, data, system, ai)"
    t.index ["mcp_server_id", "name"], name: "index_mcp_tools_on_mcp_server_id_and_name"
    t.index ["mcp_server_id"], name: "index_mcp_tools_on_mcp_server_id"
    t.index ["permission_level"], name: "index_mcp_tools_on_permission_level"
    t.check_constraint "permission_level::text = ANY (ARRAY['public'::character varying::text, 'account'::character varying::text, 'admin'::character varying::text])", name: "mcp_tools_permission_level_check"
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

  create_table "notifications", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "user_id", null: false
    t.string "notification_type", null: false
    t.string "title", null: false
    t.text "message", null: false
    t.string "severity", default: "info", null: false
    t.string "action_url"
    t.string "action_label"
    t.string "icon"
    t.string "category", default: "general"
    t.json "metadata", default: {}
    t.datetime "read_at"
    t.datetime "dismissed_at"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.uuid "resource_owner_id", null: false
    t.uuid "application_id", null: false
    t.string "token", null: false
    t.integer "expires_in", null: false
    t.text "redirect_uri", null: false
    t.string "scopes", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "revoked_at"
    t.string "code_challenge"
    t.string "code_challenge_method"
    t.index ["application_id"], name: "index_oauth_access_grants_on_application_id"
    t.index ["resource_owner_id"], name: "index_oauth_access_grants_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_grants_on_token", unique: true
  end

  create_table "oauth_access_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "resource_owner_id"
    t.uuid "application_id"
    t.string "token", null: false
    t.string "refresh_token"
    t.integer "expires_in"
    t.string "scopes"
    t.datetime "created_at", null: false
    t.datetime "revoked_at"
    t.string "previous_refresh_token", default: "", null: false
    t.inet "created_from_ip"
    t.string "user_agent"
    t.index ["application_id", "created_at"], name: "index_oauth_access_tokens_on_application_id_and_created_at"
    t.index ["application_id"], name: "index_oauth_access_tokens_on_application_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true
    t.index ["resource_owner_id"], name: "index_oauth_access_tokens_on_resource_owner_id"
    t.index ["revoked_at"], name: "index_oauth_access_tokens_on_revoked_at"
    t.index ["token"], name: "index_oauth_access_tokens_on_token", unique: true
  end

  create_table "oauth_applications", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "uid", null: false
    t.string "secret", null: false
    t.text "redirect_uri"
    t.string "scopes", default: "", null: false
    t.boolean "confidential", default: true, null: false
    t.string "owner_type"
    t.uuid "owner_id"
    t.string "description"
    t.boolean "trusted", default: false, null: false
    t.boolean "machine_client", default: false, null: false
    t.string "status", default: "active", null: false
    t.string "rate_limit_tier", default: "standard"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_oauth_applications_on_owner_id"
    t.index ["owner_type", "owner_id"], name: "index_oauth_applications_on_owner"
    t.index ["status"], name: "index_oauth_applications_on_status"
    t.index ["trusted"], name: "index_oauth_applications_on_trusted"
    t.index ["uid"], name: "index_oauth_applications_on_uid", unique: true
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
    t.datetime "failed_at"
    t.jsonb "gateway_response", default: {}
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "invoice_id"
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
    t.jsonb "features", default: {}
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

  create_table "plugin_dependencies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "plugin_id", null: false
    t.string "dependency_plugin_id", null: false
    t.string "version_constraint"
    t.boolean "is_required", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["plugin_id", "dependency_plugin_id"], name: "idx_on_plugin_id_dependency_plugin_id_f11554f3cb", unique: true
    t.index ["plugin_id"], name: "index_plugin_dependencies_on_plugin_id"
  end

  create_table "plugin_installations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "plugin_id", null: false
    t.uuid "installed_by_id", null: false
    t.string "status", default: "active", null: false
    t.datetime "installed_at", null: false
    t.datetime "last_activated_at"
    t.datetime "last_used_at"
    t.jsonb "configuration", default: {}, null: false
    t.jsonb "credentials", default: {}, null: false
    t.jsonb "installation_metadata", default: {}, null: false
    t.integer "execution_count", default: 0
    t.decimal "total_cost", precision: 10, scale: 4, default: "0.0"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "plugin_id"], name: "index_plugin_installations_on_account_id_and_plugin_id", unique: true
    t.index ["account_id"], name: "index_plugin_installations_on_account_id"
    t.index ["installed_at"], name: "index_plugin_installations_on_installed_at"
    t.index ["installed_by_id"], name: "index_plugin_installations_on_installed_by_id"
    t.index ["plugin_id"], name: "index_plugin_installations_on_plugin_id"
    t.index ["status"], name: "index_plugin_installations_on_status"
  end

  create_table "plugin_marketplaces", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "creator_id", null: false
    t.string "name", limit: 255, null: false
    t.string "slug", limit: 255, null: false
    t.string "owner", limit: 255, null: false
    t.text "description"
    t.string "marketplace_type", default: "private", null: false
    t.string "source_type", null: false
    t.string "source_url", limit: 500
    t.string "visibility", default: "private", null: false
    t.integer "plugin_count", default: 0
    t.decimal "average_rating", precision: 3, scale: 2
    t.jsonb "configuration", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "slug"], name: "index_plugin_marketplaces_on_account_id_and_slug", unique: true
    t.index ["account_id"], name: "index_plugin_marketplaces_on_account_id"
    t.index ["creator_id"], name: "index_plugin_marketplaces_on_creator_id"
    t.index ["marketplace_type"], name: "index_plugin_marketplaces_on_marketplace_type"
    t.index ["visibility"], name: "index_plugin_marketplaces_on_visibility"
  end

  create_table "plugin_reviews", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "plugin_id", null: false
    t.uuid "account_id", null: false
    t.uuid "user_id", null: false
    t.integer "rating", null: false
    t.text "review_text"
    t.boolean "is_verified_purchase", default: false
    t.string "plugin_version", limit: 20
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_plugin_reviews_on_account_id"
    t.index ["plugin_id", "account_id"], name: "index_plugin_reviews_on_plugin_id_and_account_id", unique: true
    t.index ["plugin_id"], name: "index_plugin_reviews_on_plugin_id"
    t.index ["rating"], name: "index_plugin_reviews_on_rating"
    t.index ["user_id"], name: "index_plugin_reviews_on_user_id"
  end

  create_table "plugins", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "creator_id", null: false
    t.uuid "source_marketplace_id"
    t.string "plugin_id", limit: 255, null: false
    t.string "name", limit: 255, null: false
    t.string "slug", limit: 255, null: false
    t.text "description"
    t.string "version", limit: 20, null: false
    t.string "author", limit: 255
    t.string "homepage", limit: 500
    t.string "license", limit: 50
    t.string "plugin_types", default: [], null: false, array: true
    t.string "source_type", null: false
    t.string "source_url", limit: 500
    t.string "source_ref", limit: 255
    t.string "status", default: "available", null: false
    t.boolean "is_verified", default: false
    t.boolean "is_official", default: false
    t.jsonb "manifest", default: {}, null: false
    t.jsonb "capabilities", default: [], null: false
    t.jsonb "configuration", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "install_count", default: 0
    t.integer "download_count", default: 0
    t.decimal "average_rating", precision: 3, scale: 2
    t.integer "rating_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "plugin_id"], name: "index_plugins_on_account_id_and_plugin_id", unique: true
    t.index ["account_id", "slug"], name: "index_plugins_on_account_id_and_slug", unique: true
    t.index ["account_id"], name: "index_plugins_on_account_id"
    t.index ["capabilities"], name: "index_plugins_on_capabilities", using: :gin
    t.index ["creator_id"], name: "index_plugins_on_creator_id"
    t.index ["is_official"], name: "index_plugins_on_is_official"
    t.index ["is_verified"], name: "index_plugins_on_is_verified"
    t.index ["plugin_types"], name: "index_plugins_on_plugin_types", using: :gin
    t.index ["source_marketplace_id"], name: "index_plugins_on_source_marketplace_id"
    t.index ["source_type"], name: "index_plugins_on_source_type"
    t.index ["status"], name: "index_plugins_on_status"
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

  create_table "terms_acceptances", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.uuid "account_id", null: false
    t.string "document_type", null: false
    t.string "document_version", null: false
    t.string "document_hash"
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "accepted_at", null: false
    t.datetime "superseded_at"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_terms_acceptances_on_account_id"
    t.index ["document_type"], name: "index_terms_acceptances_on_document_type"
    t.index ["document_version"], name: "index_terms_acceptances_on_document_version"
    t.index ["user_id", "document_type", "document_version"], name: "idx_on_user_id_document_type_document_version_8eb2bf3f3a", unique: true
    t.index ["user_id", "document_type"], name: "index_terms_acceptances_on_user_id_and_document_type"
    t.index ["user_id"], name: "index_terms_acceptances_on_user_id"
  end

  create_table "user_consents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.uuid "account_id", null: false
    t.string "consent_type", null: false
    t.boolean "granted", default: false, null: false
    t.string "version"
    t.text "consent_text"
    t.string "collection_method", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "granted_at"
    t.datetime "withdrawn_at"
    t.datetime "expires_at"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "consent_type"], name: "index_user_consents_on_account_id_and_consent_type"
    t.index ["account_id"], name: "index_user_consents_on_account_id"
    t.index ["consent_type"], name: "index_user_consents_on_consent_type"
    t.index ["expires_at"], name: "index_user_consents_on_expires_at"
    t.index ["granted"], name: "index_user_consents_on_granted"
    t.index ["user_id", "consent_type"], name: "index_user_consents_on_user_id_and_consent_type"
    t.index ["user_id"], name: "index_user_consents_on_user_id"
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
    t.string "name", default: "", null: false
    t.index ["account_id"], name: "index_users_on_account_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["email_verification_token"], name: "index_users_on_email_verification_token", unique: true, where: "(email_verification_token IS NOT NULL)"
    t.index ["reset_token_digest"], name: "index_users_on_reset_token_digest", unique: true, where: "(reset_token_digest IS NOT NULL)"
    t.index ["status"], name: "index_users_on_status"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'suspended'::character varying::text, 'pending_verification'::character varying::text])", name: "valid_user_status"
  end

  create_table "validation_rules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.string "category", null: false
    t.string "severity", default: "warning", null: false
    t.boolean "enabled", default: true
    t.boolean "auto_fixable", default: false
    t.jsonb "configuration", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category", "enabled"], name: "index_validation_rules_on_category_and_enabled"
    t.index ["severity"], name: "index_validation_rules_on_severity"
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
    t.uuid "created_by_id"
    t.string "url", limit: 1000, null: false
    t.string "description", limit: 500
    t.string "status", limit: 20, default: "active", null: false
    t.boolean "is_active", default: true
    t.string "secret_key"
    t.string "content_type", limit: 100, default: "application/json", null: false
    t.integer "timeout_seconds", default: 30, null: false
    t.integer "retry_limit", default: 3, null: false
    t.string "retry_backoff", limit: 20, default: "exponential", null: false
    t.integer "max_retries", default: 3
    t.jsonb "event_types", default: []
    t.jsonb "headers", default: {}
    t.integer "success_count", default: 0, null: false
    t.integer "failure_count", default: 0, null: false
    t.datetime "last_delivery_at", precision: nil
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "idx_webhook_endpoints_on_account_id"
    t.index ["account_id"], name: "index_webhook_endpoints_on_account_id"
    t.index ["content_type"], name: "idx_webhook_endpoints_on_content_type"
    t.index ["created_by_id"], name: "idx_webhook_endpoints_on_created_by"
    t.index ["created_by_id"], name: "index_webhook_endpoints_on_created_by_id"
    t.index ["failure_count"], name: "idx_webhook_endpoints_on_failure_count"
    t.index ["is_active"], name: "idx_webhook_endpoints_on_is_active"
    t.index ["last_delivery_at"], name: "idx_webhook_endpoints_on_last_delivery_at"
    t.index ["status", "is_active"], name: "idx_webhook_endpoints_on_status_active"
    t.index ["success_count"], name: "idx_webhook_endpoints_on_success_count"
    t.check_constraint "content_type::text = ANY (ARRAY['application/json'::character varying::text, 'application/x-www-form-urlencoded'::character varying::text])", name: "valid_webhook_content_type"
    t.check_constraint "failure_count >= 0", name: "valid_webhook_failure_count"
    t.check_constraint "retry_backoff::text = ANY (ARRAY['linear'::character varying::text, 'exponential'::character varying::text])", name: "valid_webhook_retry_backoff"
    t.check_constraint "retry_limit >= 0 AND retry_limit <= 10", name: "valid_webhook_retry_limit"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text, 'suspended'::character varying::text])", name: "valid_webhook_status"
    t.check_constraint "success_count >= 0", name: "valid_webhook_success_count"
    t.check_constraint "timeout_seconds > 0 AND timeout_seconds <= 300", name: "valid_webhook_timeout"
  end

  create_table "webhook_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.uuid "payment_id"
    t.string "provider", null: false
    t.string "event_type", null: false
    t.string "event_id", null: false
    t.string "external_id", null: false
    t.jsonb "payload", default: {}
    t.datetime "occurred_at", null: false
    t.string "status", default: "pending"
    t.integer "retry_count", default: 0, null: false
    t.text "error_message"
    t.text "metadata"
    t.datetime "processed_at"
    t.datetime "created_at", null: false
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
    t.uuid "account_id"
    t.string "name", null: false
    t.text "description"
    t.string "status", default: "active"
    t.string "token_digest"
    t.jsonb "permissions", default: []
    t.datetime "last_seen_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "config", default: {}, null: false
    t.index ["account_id"], name: "index_workers_on_account_id"
    t.index ["name"], name: "index_workers_on_name", unique: true
    t.index ["permissions"], name: "index_workers_on_permissions", using: :gin
    t.index ["status"], name: "index_workers_on_status"
  end

  create_table "workflow_node_plugins", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "plugin_id", null: false
    t.string "node_type", null: false
    t.string "node_category", null: false
    t.jsonb "input_schema", default: {}, null: false
    t.jsonb "output_schema", default: {}, null: false
    t.jsonb "configuration_schema", default: {}, null: false
    t.jsonb "ui_configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["node_category"], name: "index_workflow_node_plugins_on_node_category"
    t.index ["node_type"], name: "index_workflow_node_plugins_on_node_type"
    t.index ["plugin_id"], name: "index_workflow_node_plugins_on_plugin_id"
  end

  create_table "workflow_validations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "workflow_id", null: false
    t.string "overall_status", null: false
    t.integer "health_score", null: false
    t.integer "total_nodes", null: false
    t.integer "validated_nodes", null: false
    t.jsonb "issues", default: [], null: false
    t.integer "validation_duration_ms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workflow_id", "created_at"], name: "index_workflow_validations_on_workflow_id_and_created_at"
    t.index ["workflow_id"], name: "index_workflow_validations_on_workflow_id"
  end

  add_foreign_key "account_delegations", "accounts"
  add_foreign_key "account_delegations", "roles"
  add_foreign_key "account_delegations", "users", column: "delegated_by_id"
  add_foreign_key "account_delegations", "users", column: "delegated_user_id"
  add_foreign_key "account_delegations", "users", column: "revoked_by_id"
  add_foreign_key "account_terminations", "accounts"
  add_foreign_key "account_terminations", "data_export_requests"
  add_foreign_key "account_terminations", "users", column: "cancelled_by_id"
  add_foreign_key "account_terminations", "users", column: "processed_by_id"
  add_foreign_key "account_terminations", "users", column: "requested_by_id"
  add_foreign_key "ai_agent_executions", "accounts", on_delete: :cascade
  add_foreign_key "ai_agent_executions", "ai_agent_executions", column: "parent_execution_id", on_delete: :nullify
  add_foreign_key "ai_agent_executions", "ai_agents", on_delete: :cascade
  add_foreign_key "ai_agent_executions", "ai_providers", on_delete: :restrict
  add_foreign_key "ai_agent_executions", "users", on_delete: :restrict
  add_foreign_key "ai_agent_messages", "ai_workflow_runs", on_delete: :cascade
  add_foreign_key "ai_agent_team_members", "ai_agent_teams"
  add_foreign_key "ai_agent_team_members", "ai_agents"
  add_foreign_key "ai_agent_teams", "accounts"
  add_foreign_key "ai_agents", "accounts", on_delete: :cascade
  add_foreign_key "ai_agents", "ai_providers"
  add_foreign_key "ai_agents", "users", column: "creator_id", on_delete: :restrict
  add_foreign_key "ai_conversations", "accounts", on_delete: :cascade
  add_foreign_key "ai_conversations", "ai_agents", on_delete: :nullify
  add_foreign_key "ai_conversations", "ai_providers", on_delete: :restrict
  add_foreign_key "ai_conversations", "users", on_delete: :restrict
  add_foreign_key "ai_messages", "ai_agents"
  add_foreign_key "ai_messages", "ai_conversations", on_delete: :cascade
  add_foreign_key "ai_messages", "ai_messages", column: "parent_message_id", on_delete: :nullify
  add_foreign_key "ai_messages", "users", on_delete: :nullify
  add_foreign_key "ai_provider_credentials", "accounts", on_delete: :cascade
  add_foreign_key "ai_provider_credentials", "ai_providers", on_delete: :cascade
  add_foreign_key "ai_provider_plugins", "plugins"
  add_foreign_key "ai_providers", "accounts"
  add_foreign_key "ai_shared_context_pools", "ai_workflow_runs", on_delete: :cascade
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
  add_foreign_key "ai_workflow_nodes", "plugins"
  add_foreign_key "ai_workflow_run_logs", "ai_workflow_node_executions"
  add_foreign_key "ai_workflow_run_logs", "ai_workflow_runs"
  add_foreign_key "ai_workflow_runs", "accounts"
  add_foreign_key "ai_workflow_runs", "ai_workflow_triggers"
  add_foreign_key "ai_workflow_runs", "ai_workflows"
  add_foreign_key "ai_workflow_runs", "users", column: "triggered_by_user_id"
  add_foreign_key "ai_workflow_schedules", "ai_workflows"
  add_foreign_key "ai_workflow_schedules", "users", column: "created_by_id"
  add_foreign_key "ai_workflow_template_installations", "accounts"
  add_foreign_key "ai_workflow_template_installations", "ai_workflow_templates"
  add_foreign_key "ai_workflow_template_installations", "ai_workflows"
  add_foreign_key "ai_workflow_template_installations", "users", column: "installed_by_user_id"
  add_foreign_key "ai_workflow_templates", "accounts"
  add_foreign_key "ai_workflow_templates", "users", column: "created_by_user_id"
  add_foreign_key "ai_workflow_triggers", "ai_workflows"
  add_foreign_key "ai_workflow_variables", "ai_workflows"
  add_foreign_key "ai_workflows", "accounts"
  add_foreign_key "ai_workflows", "ai_workflows", column: "parent_version_id", on_delete: :nullify
  add_foreign_key "ai_workflows", "users", column: "creator_id"
  add_foreign_key "api_key_usages", "api_keys"
  add_foreign_key "api_keys", "accounts"
  add_foreign_key "api_keys", "users", column: "created_by_id"
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
  add_foreign_key "batch_workflow_runs", "accounts"
  add_foreign_key "batch_workflow_runs", "users"
  add_foreign_key "blacklisted_tokens", "users"
  add_foreign_key "circuit_breaker_events", "circuit_breakers"
  add_foreign_key "cookie_consents", "users"
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
  add_foreign_key "email_deliveries", "users"
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
  add_foreign_key "marketplace_listings", "apps", on_delete: :cascade
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
  add_foreign_key "plugin_dependencies", "plugins"
  add_foreign_key "plugin_installations", "accounts"
  add_foreign_key "plugin_installations", "plugins"
  add_foreign_key "plugin_installations", "users", column: "installed_by_id"
  add_foreign_key "plugin_marketplaces", "accounts"
  add_foreign_key "plugin_marketplaces", "users", column: "creator_id"
  add_foreign_key "plugin_reviews", "accounts"
  add_foreign_key "plugin_reviews", "plugins"
  add_foreign_key "plugin_reviews", "users"
  add_foreign_key "plugins", "accounts"
  add_foreign_key "plugins", "plugin_marketplaces", column: "source_marketplace_id"
  add_foreign_key "plugins", "users", column: "creator_id"
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
  add_foreign_key "webhook_endpoints", "accounts"
  add_foreign_key "webhook_endpoints", "users", column: "created_by_id"
  add_foreign_key "webhook_events", "accounts"
  add_foreign_key "webhook_events", "payments"
  add_foreign_key "worker_activities", "workers"
  add_foreign_key "worker_roles", "roles"
  add_foreign_key "worker_roles", "workers"
  add_foreign_key "workers", "accounts"
  add_foreign_key "workflow_node_plugins", "plugins"
  add_foreign_key "workflow_validations", "ai_workflows", column: "workflow_id"
end
