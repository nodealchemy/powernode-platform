# frozen_string_literal: true

class AiPlatformFoundationBaseline < ActiveRecord::Migration[8.1]
  def change
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
    t.index ["account_id"]
    t.index ["category"]
    t.index ["cloned_from_id"]
    t.index ["created_by_id"]
    t.index ["is_featured"]
    t.index ["is_system"]
    t.index ["slug"], unique: true
    t.index ["source_key"]
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
    t.index ["account_id", "template_type"]
    t.index ["account_id"]
    t.index ["cloned_from_id"]
    t.index ["is_default"], name: "index_ai_mission_templates_on_is_default", where: "(is_default = true)"
    t.index ["mission_type", "status"]
    t.index ["source_key"]
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
    t.index ["account_id"]
    t.index ["cloned_from_id"]
    t.index ["created_by_id"]
    t.index ["is_public", "category"]
    t.index ["is_system"]
    t.index ["slug"], unique: true
    t.index ["source_key"]
    t.index ["team_topology"]
    t.check_constraint "team_topology::text = ANY (ARRAY['hierarchical'::character varying::text, 'flat'::character varying::text, 'mesh'::character varying::text, 'pipeline'::character varying::text, 'hybrid'::character varying::text])", name: "check_team_topology"
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

    add_foreign_key "ai_ab_tests", "accounts", column: "account_id"
    add_foreign_key "ai_ab_tests", "users", column: "created_by_id"
    add_foreign_key "ai_agent_connections", "accounts", column: "account_id"
    add_foreign_key "ai_agent_identities", "accounts", column: "account_id"
    add_foreign_key "ai_agent_model_performances", "accounts", column: "account_id"
    add_foreign_key "ai_agent_model_performances", "ai_providers", column: "ai_provider_id"
    add_foreign_key "ai_agent_privilege_policies", "accounts", column: "account_id"
    add_foreign_key "ai_agent_teams", "accounts", column: "account_id"
    add_foreign_key "ai_agents", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "ai_agents", "ai_providers", column: "ai_provider_id"
    add_foreign_key "ai_agents", "users", column: "creator_id", on_delete: :restrict
    add_foreign_key "ai_agui_sessions", "accounts", column: "account_id"
    add_foreign_key "ai_agui_sessions", "users", column: "user_id"
    add_foreign_key "ai_approval_chains", "accounts", column: "account_id"
    add_foreign_key "ai_approval_chains", "users", column: "created_by_id"
    add_foreign_key "ai_collusion_indicators", "accounts", column: "account_id"
    add_foreign_key "ai_compliance_audit_entries", "accounts", column: "account_id"
    add_foreign_key "ai_compliance_audit_entries", "users", column: "user_id"
    add_foreign_key "ai_compliance_policies", "accounts", column: "account_id"
    add_foreign_key "ai_compliance_policies", "users", column: "created_by_id"
    add_foreign_key "ai_compliance_reports", "accounts", column: "account_id"
    add_foreign_key "ai_compliance_reports", "users", column: "generated_by_id"
    add_foreign_key "ai_cost_attributions", "accounts", column: "account_id"
    add_foreign_key "ai_cost_attributions", "ai_providers", column: "provider_id"
    add_foreign_key "ai_cost_attributions", "ai_roi_metrics", column: "roi_metric_id"
    add_foreign_key "ai_cost_optimization_logs", "accounts", column: "account_id"
    add_foreign_key "ai_dag_executions", "accounts", column: "account_id"
    add_foreign_key "ai_dag_executions", "users", column: "triggered_by_id"
    add_foreign_key "ai_data_classifications", "accounts", column: "account_id"
    add_foreign_key "ai_data_classifications", "users", column: "classified_by_id"
    add_foreign_key "ai_data_source_config_versions", "accounts", column: "account_id"
    add_foreign_key "ai_data_source_config_versions", "ai_data_sources", column: "ai_data_source_id"
    add_foreign_key "ai_data_source_credentials", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "ai_data_source_credentials", "ai_data_sources", column: "ai_data_source_id", on_delete: :cascade
    add_foreign_key "ai_data_source_endpoints", "ai_data_sources", column: "ai_data_source_id"
    add_foreign_key "ai_data_sources", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "ai_devops_templates", "accounts", column: "account_id"
    add_foreign_key "ai_devops_templates", "users", column: "created_by_id"
    add_foreign_key "ai_discovery_results", "accounts", column: "account_id"
    add_foreign_key "ai_encrypted_messages", "accounts", column: "account_id"
    add_foreign_key "ai_execution_events", "accounts", column: "account_id"
    add_foreign_key "ai_execution_trace_spans", "ai_execution_traces", column: "execution_trace_id"
    add_foreign_key "ai_execution_traces", "accounts", column: "account_id"
    add_foreign_key "ai_hybrid_search_results", "accounts", column: "account_id"
    add_foreign_key "ai_improvement_recommendations", "accounts", column: "account_id"
    add_foreign_key "ai_improvement_recommendations", "users", column: "approved_by_id"
    add_foreign_key "ai_kill_switch_events", "accounts", column: "account_id"
    add_foreign_key "ai_kill_switch_events", "users", column: "triggered_by_id"
    add_foreign_key "ai_mcp_apps", "accounts", column: "account_id"
    add_foreign_key "ai_memory_pools", "accounts", column: "account_id"
    add_foreign_key "ai_model_routing_rules", "accounts", column: "account_id"
    add_foreign_key "ai_pressure_fields", "accounts", column: "account_id"
    add_foreign_key "ai_provider_credentials", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "ai_provider_credentials", "ai_providers", column: "ai_provider_id", on_delete: :cascade
    add_foreign_key "ai_provider_metrics", "accounts", column: "account_id"
    add_foreign_key "ai_provider_metrics", "ai_providers", column: "provider_id"
    add_foreign_key "ai_providers", "accounts", column: "account_id"
    add_foreign_key "ai_quarantine_records", "accounts", column: "account_id"
    add_foreign_key "ai_remediation_logs", "accounts", column: "account_id"
    add_foreign_key "ai_roi_metrics", "accounts", column: "account_id"
    add_foreign_key "ai_role_profiles", "accounts", column: "account_id"
    add_foreign_key "ai_sandboxes", "accounts", column: "account_id"
    add_foreign_key "ai_sandboxes", "users", column: "created_by_id"
    add_foreign_key "ai_security_audit_trails", "accounts", column: "account_id"
    add_foreign_key "ai_team_channels", "ai_agent_teams", column: "agent_team_id"
    add_foreign_key "ai_team_templates", "accounts", column: "account_id"
    add_foreign_key "ai_team_templates", "users", column: "created_by_id"
    add_foreign_key "ai_worktree_sessions", "accounts", column: "account_id"
    add_foreign_key "ai_worktree_sessions", "users", column: "initiated_by_id"
    add_foreign_key "devops_ai_configs", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "devops_ai_configs", "users", column: "created_by_id", on_delete: :nullify
    add_foreign_key "devops_container_templates", "accounts", column: "account_id"
    add_foreign_key "devops_container_templates", "devops_container_templates", column: "parent_template_id"
    add_foreign_key "devops_container_templates", "users", column: "created_by_id"
    add_foreign_key "devops_docker_containers", "devops_docker_hosts", column: "docker_host_id"
    add_foreign_key "devops_docker_events", "devops_docker_hosts", column: "docker_host_id"
    add_foreign_key "devops_docker_events", "users", column: "acknowledged_by_id"
    add_foreign_key "devops_docker_hosts", "accounts", column: "account_id"
    add_foreign_key "devops_docker_images", "devops_docker_hosts", column: "docker_host_id"
    add_foreign_key "devops_integration_credentials", "accounts", column: "account_id"
    add_foreign_key "devops_integration_credentials", "users", column: "created_by_user_id"
    add_foreign_key "devops_kubernetes_clusters", "accounts", column: "account_id"
    add_foreign_key "devops_kubernetes_nodes", "devops_kubernetes_clusters", column: "kubernetes_cluster_id", on_delete: :cascade
    add_foreign_key "devops_port_allocations", "accounts", column: "account_id"
    add_foreign_key "devops_providers", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "devops_providers", "users", column: "created_by_id", on_delete: :nullify
    add_foreign_key "devops_resource_quotas", "accounts", column: "account_id"
    add_foreign_key "devops_secret_references", "accounts", column: "account_id"
    add_foreign_key "devops_secret_references", "users", column: "created_by_id"
    add_foreign_key "devops_swarm_clusters", "accounts", column: "account_id"
    add_foreign_key "devops_swarm_events", "devops_swarm_clusters", column: "cluster_id"
    add_foreign_key "devops_swarm_events", "users", column: "acknowledged_by_id"
    add_foreign_key "devops_swarm_nodes", "devops_swarm_clusters", column: "cluster_id"
    add_foreign_key "devops_swarm_stacks", "devops_swarm_clusters", column: "cluster_id"
    add_foreign_key "git_provider_credentials", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "git_provider_credentials", "git_providers", column: "git_provider_id", on_delete: :cascade
    add_foreign_key "git_provider_credentials", "users", column: "user_id", on_delete: :nullify
    add_foreign_key "git_providers", "accounts", column: "account_id"
    add_foreign_key "mcp_servers", "accounts", column: "account_id"
    add_foreign_key "mcp_tools", "mcp_servers", column: "mcp_server_id"
  end
end
