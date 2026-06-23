# frozen_string_literal: true

class AiPlatformCoreBaseline < ActiveRecord::Migration[8.1]
  def change
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
    t.index ["account_id"]
    t.index ["average_rating", "installation_count"]
    t.index ["category"]
    t.index ["cloned_from_id"]
    t.index ["is_featured"]
    t.index ["pricing_type"]
    t.index ["publisher_id"]
    t.index ["slug"], unique: true
    t.index ["source_agent_id"]
    t.index ["source_key"]
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
    t.index ["account_id", "name"], unique: true, where: "(account_id IS NOT NULL)"
    t.index ["account_id"]
    t.index ["cloned_from_id"]
    t.index ["created_by_id"]
    t.index ["git_repository_id"]
    t.index ["is_public"]
    t.index ["name"], unique: true, where: "(account_id IS NULL)", name: "index_ai_knowledge_bases_on_name_global"
    t.index ["source_key"]
    t.index ["status"]
    t.check_constraint "chunking_strategy::text = ANY (ARRAY['recursive'::character varying::text, 'semantic'::character varying::text, 'fixed'::character varying::text, 'sentence'::character varying::text, 'paragraph'::character varying::text, 'custom'::character varying::text])", name: "check_kb_chunking_strategy"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'indexing'::character varying::text, 'paused'::character varying::text, 'archived'::character varying::text, 'error'::character varying::text])", name: "check_kb_status"
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

    add_foreign_key "ai_agent_budgets", "accounts", column: "account_id"
    add_foreign_key "ai_agent_budgets", "ai_agent_budgets", column: "parent_budget_id", on_delete: :nullify
    add_foreign_key "ai_agent_budgets", "ai_agents", column: "agent_id"
    add_foreign_key "ai_agent_cards", "accounts", column: "account_id"
    add_foreign_key "ai_agent_cards", "ai_agents", column: "ai_agent_id"
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
    add_foreign_key "ai_agent_installations", "accounts", column: "account_id"
    add_foreign_key "ai_agent_installations", "ai_agent_templates", column: "agent_template_id"
    add_foreign_key "ai_agent_installations", "ai_agents", column: "installed_agent_id"
    add_foreign_key "ai_agent_installations", "users", column: "installed_by_id"
    add_foreign_key "ai_agent_lineages", "accounts", column: "account_id"
    add_foreign_key "ai_agent_lineages", "ai_agents", column: "child_agent_id"
    add_foreign_key "ai_agent_lineages", "ai_agents", column: "parent_agent_id"
    add_foreign_key "ai_agent_observations", "accounts", column: "account_id"
    add_foreign_key "ai_agent_observations", "ai_agent_goals", column: "goal_id"
    add_foreign_key "ai_agent_observations", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_agent_proposals", "accounts", column: "account_id"
    add_foreign_key "ai_agent_proposals", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_agent_proposals", "ai_conversations", column: "conversation_id"
    add_foreign_key "ai_agent_proposals", "users", column: "reviewed_by_id"
    add_foreign_key "ai_agent_proposals", "users", column: "target_user_id"
    add_foreign_key "ai_agent_short_term_memories", "accounts", column: "account_id"
    add_foreign_key "ai_agent_short_term_memories", "ai_agents", column: "agent_id"
    add_foreign_key "ai_agent_team_members", "ai_agent_teams", column: "ai_agent_team_id"
    add_foreign_key "ai_agent_team_members", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_agent_templates", "accounts", column: "account_id"
    add_foreign_key "ai_agent_templates", "ai_agents", column: "source_agent_id"
    add_foreign_key "ai_agent_trust_scores", "accounts", column: "account_id"
    add_foreign_key "ai_agent_trust_scores", "ai_agents", column: "agent_id"
    add_foreign_key "ai_agui_events", "accounts", column: "account_id"
    add_foreign_key "ai_agui_events", "ai_agui_sessions", column: "session_id"
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
    add_foreign_key "ai_code_factory_risk_contracts", "accounts", column: "account_id"
    add_foreign_key "ai_code_factory_risk_contracts", "git_repositories", column: "repository_id"
    add_foreign_key "ai_code_factory_risk_contracts", "users", column: "created_by_id"
    add_foreign_key "ai_context_entries", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_context_entries", "ai_persistent_contexts", column: "ai_persistent_context_id"
    add_foreign_key "ai_context_entries", "users", column: "created_by_user_id"
    add_foreign_key "ai_conversations", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "ai_conversations", "ai_agent_teams", column: "agent_team_id"
    add_foreign_key "ai_conversations", "ai_agents", column: "ai_agent_id", on_delete: :nullify
    add_foreign_key "ai_conversations", "ai_providers", column: "ai_provider_id", on_delete: :restrict
    add_foreign_key "ai_conversations", "users", column: "user_id", on_delete: :restrict
    add_foreign_key "ai_data_detections", "accounts", column: "account_id"
    add_foreign_key "ai_data_detections", "ai_data_classifications", column: "classification_id"
    add_foreign_key "ai_data_source_expectations", "ai_data_source_endpoints", column: "ai_data_source_endpoint_id"
    add_foreign_key "ai_data_source_queries", "ai_data_source_endpoints", column: "ai_data_source_endpoint_id"
    add_foreign_key "ai_data_source_queries", "ai_data_sources", column: "ai_data_source_id"
    add_foreign_key "ai_data_source_schema_versions", "ai_data_source_endpoints", column: "ai_data_source_endpoint_id"
    add_foreign_key "ai_data_source_subscriptions", "ai_data_source_endpoints", column: "ai_data_source_endpoint_id"
    add_foreign_key "ai_data_source_subscriptions", "ai_data_sources", column: "ai_data_source_id"
    add_foreign_key "ai_deferred_operations", "accounts", column: "account_id"
    add_foreign_key "ai_deferred_operations", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_deferred_operations", "ai_approval_requests", column: "approval_request_id"
    add_foreign_key "ai_deferred_operations", "users", column: "requested_by_id"
    add_foreign_key "ai_delegation_policies", "accounts", column: "account_id"
    add_foreign_key "ai_delegation_policies", "ai_agents", column: "agent_id"
    add_foreign_key "ai_devops_template_installations", "accounts", column: "account_id"
    add_foreign_key "ai_devops_template_installations", "ai_devops_templates", column: "devops_template_id"
    add_foreign_key "ai_devops_template_installations", "users", column: "installed_by_id"
    add_foreign_key "ai_evaluation_results", "accounts", column: "account_id"
    add_foreign_key "ai_evaluation_results", "ai_agents", column: "agent_id"
    add_foreign_key "ai_experience_replays", "accounts", column: "account_id"
    add_foreign_key "ai_experience_replays", "ai_agent_executions", column: "source_execution_id"
    add_foreign_key "ai_experience_replays", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_experience_replays", "ai_trajectories", column: "source_trajectory_id"
    add_foreign_key "ai_file_locks", "accounts", column: "account_id"
    add_foreign_key "ai_file_locks", "ai_worktree_sessions", column: "worktree_session_id"
    add_foreign_key "ai_file_locks", "ai_worktrees", column: "worktree_id"
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
    add_foreign_key "ai_intervention_policies", "accounts", column: "account_id"
    add_foreign_key "ai_intervention_policies", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_intervention_policies", "ai_approval_chains", column: "approval_chain_id"
    add_foreign_key "ai_intervention_policies", "users", column: "user_id"
    add_foreign_key "ai_knowledge_bases", "accounts", column: "account_id"
    add_foreign_key "ai_knowledge_bases", "git_repositories", column: "git_repository_id"
    add_foreign_key "ai_knowledge_bases", "users", column: "created_by_id"
    add_foreign_key "ai_mcp_app_instances", "accounts", column: "account_id"
    add_foreign_key "ai_mcp_app_instances", "ai_agui_sessions", column: "session_id"
    add_foreign_key "ai_mcp_app_instances", "ai_mcp_apps", column: "mcp_app_id"
    add_foreign_key "ai_merge_operations", "accounts", column: "account_id"
    add_foreign_key "ai_merge_operations", "ai_worktree_sessions", column: "worktree_session_id"
    add_foreign_key "ai_merge_operations", "ai_worktrees", column: "worktree_id"
    add_foreign_key "ai_messages", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_messages", "ai_conversations", column: "ai_conversation_id", on_delete: :cascade
    add_foreign_key "ai_messages", "ai_messages", column: "parent_message_id", on_delete: :nullify
    add_foreign_key "ai_messages", "users", column: "user_id", on_delete: :nullify
    add_foreign_key "ai_mock_responses", "accounts", column: "account_id"
    add_foreign_key "ai_mock_responses", "ai_sandboxes", column: "sandbox_id"
    add_foreign_key "ai_mock_responses", "users", column: "created_by_id"
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
    add_foreign_key "ai_recorded_interactions", "accounts", column: "account_id"
    add_foreign_key "ai_recorded_interactions", "ai_sandboxes", column: "sandbox_id"
    add_foreign_key "ai_routing_decisions", "accounts", column: "account_id"
    add_foreign_key "ai_routing_decisions", "ai_agent_executions", column: "agent_execution_id"
    add_foreign_key "ai_routing_decisions", "ai_model_routing_rules", column: "routing_rule_id"
    add_foreign_key "ai_routing_decisions", "ai_providers", column: "selected_provider_id"
    add_foreign_key "ai_routing_decisions", "ai_task_complexity_assessments", column: "complexity_assessment_id"
    add_foreign_key "ai_scheduled_messages", "accounts", column: "account_id"
    add_foreign_key "ai_scheduled_messages", "ai_conversations", column: "conversation_id"
    add_foreign_key "ai_scheduled_messages", "users", column: "user_id"
    add_foreign_key "ai_shadow_executions", "accounts", column: "account_id"
    add_foreign_key "ai_shadow_executions", "ai_agents", column: "agent_id"
    add_foreign_key "ai_shared_knowledges", "accounts", column: "account_id"
    add_foreign_key "ai_shared_knowledges", "git_repositories", column: "git_repository_id", on_delete: :nullify
    add_foreign_key "ai_shared_knowledges", "users", column: "created_by_id"
    add_foreign_key "ai_stigmergic_signals", "accounts", column: "account_id"
    add_foreign_key "ai_stigmergic_signals", "ai_agents", column: "emitter_agent_id"
    add_foreign_key "ai_stigmergic_signals", "ai_memory_pools", column: "memory_pool_id"
    add_foreign_key "ai_task_complexity_assessments", "accounts", column: "account_id"
    add_foreign_key "ai_task_complexity_assessments", "ai_routing_decisions", column: "routing_decision_id"
    add_foreign_key "ai_team_restructure_events", "accounts", column: "account_id"
    add_foreign_key "ai_team_restructure_events", "ai_agent_teams", column: "ai_agent_team_id"
    add_foreign_key "ai_team_restructure_events", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_team_roles", "accounts", column: "account_id"
    add_foreign_key "ai_team_roles", "ai_agent_teams", column: "agent_team_id"
    add_foreign_key "ai_team_roles", "ai_agents", column: "ai_agent_id"
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
    add_foreign_key "ai_worktrees", "accounts", column: "account_id"
    add_foreign_key "ai_worktrees", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_worktrees", "ai_worktree_sessions", column: "worktree_session_id"
    add_foreign_key "chat_blacklists", "accounts", column: "account_id"
    add_foreign_key "chat_blacklists", "chat_channels", column: "channel_id"
    add_foreign_key "chat_blacklists", "users", column: "blocked_by_id"
    add_foreign_key "chat_channels", "accounts", column: "account_id"
    add_foreign_key "chat_channels", "ai_agents", column: "default_agent_id"
    add_foreign_key "chat_channels", "ai_team_channels", column: "ai_team_channel_id"
    add_foreign_key "chat_sessions", "ai_agents", column: "assigned_agent_id"
    add_foreign_key "chat_sessions", "ai_conversations", column: "ai_conversation_id"
    add_foreign_key "chat_sessions", "chat_channels", column: "channel_id"
    add_foreign_key "community_agents", "accounts", column: "owner_account_id"
    add_foreign_key "community_agents", "ai_agent_cards", column: "agent_card_id"
    add_foreign_key "community_agents", "ai_agents", column: "agent_id"
    add_foreign_key "community_agents", "users", column: "published_by_id"
    add_foreign_key "community_agents", "users", column: "verified_by_id"
    add_foreign_key "devops_container_image_builds", "accounts", column: "account_id"
    add_foreign_key "devops_container_image_builds", "devops_container_image_builds", column: "triggered_by_build_id"
    add_foreign_key "devops_container_image_builds", "devops_container_templates", column: "container_template_id"
    add_foreign_key "devops_docker_activities", "devops_docker_containers", column: "container_id"
    add_foreign_key "devops_docker_activities", "devops_docker_hosts", column: "docker_host_id"
    add_foreign_key "devops_docker_activities", "devops_docker_images", column: "image_id"
    add_foreign_key "devops_docker_activities", "users", column: "triggered_by_id"
    add_foreign_key "devops_integration_executions", "accounts", column: "account_id"
    add_foreign_key "devops_integration_executions", "devops_integration_instances", column: "integration_instance_id"
    add_foreign_key "devops_integration_executions", "users", column: "triggered_by_user_id"
    add_foreign_key "devops_integration_instances", "accounts", column: "account_id"
    add_foreign_key "devops_integration_instances", "devops_integration_credentials", column: "integration_credential_id"
    add_foreign_key "devops_integration_instances", "devops_integration_templates", column: "integration_template_id"
    add_foreign_key "devops_integration_instances", "users", column: "created_by_user_id"
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
    add_foreign_key "devops_schedules", "devops_pipelines", column: "devops_pipeline_id", on_delete: :cascade
    add_foreign_key "devops_schedules", "users", column: "created_by_id", on_delete: :nullify
    add_foreign_key "devops_swarm_deployments", "devops_swarm_clusters", column: "cluster_id"
    add_foreign_key "devops_swarm_deployments", "devops_swarm_services", column: "service_id"
    add_foreign_key "devops_swarm_deployments", "devops_swarm_stacks", column: "stack_id"
    add_foreign_key "devops_swarm_deployments", "users", column: "triggered_by_id"
    add_foreign_key "devops_swarm_services", "devops_swarm_clusters", column: "cluster_id"
    add_foreign_key "devops_swarm_services", "devops_swarm_stacks", column: "stack_id"
    add_foreign_key "git_pipelines", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "git_pipelines", "git_repositories", column: "git_repository_id", on_delete: :cascade
    add_foreign_key "git_repositories", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "git_repositories", "devops_providers", column: "devops_provider_id", on_delete: :nullify
    add_foreign_key "git_repositories", "git_provider_credentials", column: "git_provider_credential_id", on_delete: :cascade
    add_foreign_key "git_runners", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "git_runners", "git_provider_credentials", column: "git_provider_credential_id", on_delete: :cascade
    add_foreign_key "git_runners", "git_repositories", column: "git_repository_id", on_delete: :cascade
    add_foreign_key "git_webhook_events", "accounts", column: "account_id", on_delete: :cascade
    add_foreign_key "git_webhook_events", "git_providers", column: "git_provider_id", on_delete: :cascade
    add_foreign_key "git_webhook_events", "git_repositories", column: "git_repository_id", on_delete: :cascade
    add_foreign_key "mcp_sessions", "accounts", column: "account_id"
    add_foreign_key "mcp_sessions", "ai_agents", column: "ai_agent_id"
    add_foreign_key "mcp_sessions", "oauth_applications", column: "oauth_application_id"
    add_foreign_key "mcp_sessions", "users", column: "user_id"
    add_foreign_key "mcp_tool_executions", "mcp_tools", column: "mcp_tool_id"
    add_foreign_key "mcp_tool_executions", "users", column: "user_id"
  end
end
