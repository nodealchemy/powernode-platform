# frozen_string_literal: true

class AiPlatformAdvancedBaseline < ActiveRecord::Migration[8.1]
  def change
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
    t.string "slug", null: false
    t.string "source_key", limit: 255
    t.jsonb "source_snapshot", default: {}, null: false
    t.string "source_version"
    t.string "status", default: "active"
    t.text "system_prompt"
    t.jsonb "tags", default: []
    t.datetime "updated_at", null: false
    t.integer "usage_count", default: 0, null: false
    t.string "version", default: "1.0.0"
    t.index ["account_id"]
    t.index ["ai_knowledge_base_id"]
    t.index ["category"]
    t.index ["cloned_from_id"]
    t.index ["is_system"]
    t.index ["parent_skill_id"]
    t.index ["slug"], unique: true
    t.index ["source_key"]
    t.index ["status"]
    t.index ["tags"], name: "index_ai_skills_on_tags", using: :gin
  end

  create_table "ai_skills_mcp_servers", id: false, force: :cascade do |t|
    t.uuid "ai_skill_id", null: false
    t.uuid "mcp_server_id", null: false
    t.index ["ai_skill_id", "mcp_server_id"], unique: true
    t.index ["mcp_server_id"]
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
    add_foreign_key "ai_agent_reviews", "accounts", column: "account_id"
    add_foreign_key "ai_agent_reviews", "ai_agent_installations", column: "installation_id"
    add_foreign_key "ai_agent_reviews", "ai_agent_templates", column: "agent_template_id"
    add_foreign_key "ai_agent_reviews", "users", column: "user_id"
    add_foreign_key "ai_agent_skills", "ai_agents", column: "ai_agent_id"
    add_foreign_key "ai_agent_skills", "ai_skills", column: "ai_skill_id"
    add_foreign_key "ai_code_factory_evidence_manifests", "accounts", column: "account_id"
    add_foreign_key "ai_code_factory_evidence_manifests", "ai_code_factory_review_states", column: "review_state_id"
    add_foreign_key "ai_code_factory_harness_gaps", "accounts", column: "account_id"
    add_foreign_key "ai_code_factory_harness_gaps", "ai_code_factory_risk_contracts", column: "risk_contract_id"
    add_foreign_key "ai_code_factory_review_states", "accounts", column: "account_id"
    add_foreign_key "ai_code_factory_review_states", "ai_code_factory_risk_contracts", column: "risk_contract_id"
    add_foreign_key "ai_code_factory_review_states", "ai_missions", column: "mission_id"
    add_foreign_key "ai_code_factory_review_states", "git_repositories", column: "repository_id"
    add_foreign_key "ai_code_review_comments", "accounts", column: "account_id"
    add_foreign_key "ai_code_review_comments", "ai_agents", column: "agent_id"
    add_foreign_key "ai_code_review_comments", "ai_task_reviews", column: "task_review_id"
    add_foreign_key "ai_code_reviews", "accounts", column: "account_id"
    add_foreign_key "ai_code_reviews", "ai_pipeline_executions", column: "pipeline_execution_id"
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
    add_foreign_key "ai_data_connectors", "accounts", column: "account_id"
    add_foreign_key "ai_data_connectors", "ai_knowledge_bases", column: "knowledge_base_id"
    add_foreign_key "ai_data_connectors", "users", column: "created_by_id"
    add_foreign_key "ai_deployment_risks", "accounts", column: "account_id"
    add_foreign_key "ai_deployment_risks", "ai_pipeline_executions", column: "pipeline_execution_id"
    add_foreign_key "ai_deployment_risks", "users", column: "assessed_by_id"
    add_foreign_key "ai_document_chunks", "ai_documents", column: "document_id"
    add_foreign_key "ai_document_chunks", "ai_knowledge_bases", column: "knowledge_base_id"
    add_foreign_key "ai_documents", "ai_knowledge_bases", column: "knowledge_base_id"
    add_foreign_key "ai_documents", "users", column: "uploaded_by_id"
    add_foreign_key "ai_goal_plan_steps", "ai_agent_goals", column: "sub_goal_id"
    add_foreign_key "ai_goal_plan_steps", "ai_goal_plans", column: "plan_id"
    add_foreign_key "ai_goal_plan_steps", "ai_ralph_tasks", column: "ralph_task_id"
    add_foreign_key "ai_knowledge_graph_edges", "accounts", column: "account_id"
    add_foreign_key "ai_knowledge_graph_edges", "ai_documents", column: "source_document_id"
    add_foreign_key "ai_knowledge_graph_edges", "ai_knowledge_graph_nodes", column: "source_node_id"
    add_foreign_key "ai_knowledge_graph_edges", "ai_knowledge_graph_nodes", column: "target_node_id"
    add_foreign_key "ai_knowledge_graph_nodes", "accounts", column: "account_id"
    add_foreign_key "ai_knowledge_graph_nodes", "ai_documents", column: "source_document_id"
    add_foreign_key "ai_knowledge_graph_nodes", "ai_knowledge_bases", column: "knowledge_base_id"
    add_foreign_key "ai_knowledge_graph_nodes", "ai_knowledge_graph_nodes", column: "merged_into_id"
    add_foreign_key "ai_knowledge_graph_nodes", "ai_skills", column: "ai_skill_id"
    add_foreign_key "ai_mission_approvals", "ai_missions", column: "mission_id"
    add_foreign_key "ai_missions", "ai_agent_teams", column: "team_id"
    add_foreign_key "ai_missions", "ai_code_factory_review_states", column: "review_state_id"
    add_foreign_key "ai_missions", "ai_code_factory_risk_contracts", column: "risk_contract_id"
    add_foreign_key "ai_missions", "ai_conversations", column: "conversation_id"
    add_foreign_key "ai_missions", "ai_mission_templates", column: "mission_template_id"
    add_foreign_key "ai_missions", "ai_ralph_loops", column: "ralph_loop_id", on_delete: :nullify
    add_foreign_key "ai_missions", "git_repositories", column: "repository_id"
    add_foreign_key "ai_missions", "users", column: "created_by_id"
    add_foreign_key "ai_provisioning_code_deployments", "ai_missions", column: "mission_id"
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
    add_foreign_key "ai_runner_dispatches", "ai_missions", column: "mission_id"
    add_foreign_key "ai_runner_dispatches", "ai_worktree_sessions", column: "worktree_session_id"
    add_foreign_key "ai_runner_dispatches", "ai_worktrees", column: "worktree_id"
    add_foreign_key "ai_runner_dispatches", "git_repositories", column: "git_repository_id"
    add_foreign_key "ai_runner_dispatches", "git_runners", column: "git_runner_id"
    add_foreign_key "ai_self_challenges", "accounts", column: "account_id"
    add_foreign_key "ai_self_challenges", "ai_agents", column: "challenger_agent_id"
    add_foreign_key "ai_self_challenges", "ai_agents", column: "executor_agent_id"
    add_foreign_key "ai_self_challenges", "ai_agents", column: "validator_agent_id"
    add_foreign_key "ai_self_challenges", "ai_skills", column: "ai_skill_id"
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
    add_foreign_key "ai_task_reviews", "accounts", column: "account_id"
    add_foreign_key "ai_task_reviews", "ai_agents", column: "reviewer_agent_id"
    add_foreign_key "ai_task_reviews", "ai_team_roles", column: "reviewer_role_id"
    add_foreign_key "ai_task_reviews", "ai_team_tasks", column: "team_task_id"
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
    add_foreign_key "ai_team_tasks", "ai_agents", column: "assigned_agent_id"
    add_foreign_key "ai_team_tasks", "ai_team_executions", column: "team_execution_id"
    add_foreign_key "ai_team_tasks", "ai_team_roles", column: "assigned_role_id"
    add_foreign_key "chat_message_attachments", "chat_messages", column: "message_id"
    add_foreign_key "chat_message_attachments", "file_objects", column: "file_object_id"
    add_foreign_key "chat_messages", "ai_messages", column: "ai_message_id"
    add_foreign_key "chat_messages", "chat_sessions", column: "session_id"
    add_foreign_key "community_agent_ratings", "accounts", column: "account_id"
    add_foreign_key "community_agent_ratings", "ai_a2a_tasks", column: "a2a_task_id"
    add_foreign_key "community_agent_ratings", "community_agents", column: "community_agent_id"
    add_foreign_key "community_agent_ratings", "users", column: "user_id"
    add_foreign_key "community_agent_reports", "accounts", column: "reported_by_account_id"
    add_foreign_key "community_agent_reports", "community_agents", column: "community_agent_id"
    add_foreign_key "community_agent_reports", "users", column: "reported_by_user_id"
    add_foreign_key "community_agent_reports", "users", column: "resolved_by_id"
    add_foreign_key "devops_container_instances", "accounts", column: "account_id"
    add_foreign_key "devops_container_instances", "ai_a2a_tasks", column: "a2a_task_id"
    add_foreign_key "devops_container_instances", "devops_container_templates", column: "template_id"
    add_foreign_key "devops_container_instances", "oauth_applications", column: "oauth_application_id"
    add_foreign_key "devops_container_instances", "users", column: "triggered_by_id"
    add_foreign_key "devops_step_approval_tokens", "devops_step_executions", column: "step_execution_id"
    add_foreign_key "devops_step_approval_tokens", "users", column: "recipient_user_id"
    add_foreign_key "devops_step_approval_tokens", "users", column: "responded_by_id"
    add_foreign_key "devops_step_executions", "devops_pipeline_runs", column: "devops_pipeline_run_id", on_delete: :cascade
    add_foreign_key "devops_step_executions", "devops_pipeline_steps", column: "devops_pipeline_step_id", on_delete: :cascade
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
  end
end
