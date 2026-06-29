# frozen_string_literal: true

# Add covering single-column indexes for genuine internal foreign-key columns
# that lack one. Unindexed FKs slow association lookups and (more dangerously)
# turn `dependent: :destroy`/`nullify` cascades and join filters into sequential
# scans on the child table.
#
# Curation methodology (core-only, conservative):
#   * Scope: only tables created by CORE migrations (server/db/migrate) so the
#     migration is safe in true core mode (extension tables may be absent).
#   * Included a `*_id` column ONLY when it is a VERIFIED local FK — it has a
#     real `belongs_to` reflection on the owning model OR a DB foreign-key
#     constraint pointing at a local table — AND it is not already covered by a
#     single-column index or the first column of a composite index.
#   * Excluded: opaque/external identifiers (tax_id, gitea_*, docker_container_id,
#     vault_token_id, platform_user_id, correlation_id, external_id, stripe_*,
#     paypal_*, Docker daemon image_id, etc.), polymorphic `*_id` columns (which
#     want a composite `[*_type, *_id]` index, out of scope here), and columns
#     with no `belongs_to`/FK constraint (unmodeled — not a verified local FK).
#
# CONCURRENTLY (so it never takes an exclusive lock on a live table) requires
# running outside a transaction; `if_not_exists` keeps it idempotent/re-runnable.
class AddMissingFkIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # [table, fk_column] — each a verified internal belongs_to / DB FK.
  FK_INDEXES = [
    ["ai_a2a_tasks", "chat_message_id"],
    ["ai_a2a_tasks", "chat_session_id"],
    ["ai_a2a_tasks", "community_agent_id"],
    ["ai_a2a_tasks", "container_instance_id"],
    ["ai_a2a_tasks", "federation_partner_id"],
    ["ai_agent_budgets", "parent_budget_id"],
    ["ai_campaign_decisions", "user_id"],
    ["ai_campaign_proposals", "reviewed_by_id"],
    ["ai_campaigns", "created_by_id"],
    ["ai_compound_learnings", "disproven_by_id"],
    ["ai_compound_learnings", "verified_by_id"],
    ["ai_delivery_runs", "campaign_land_id"],
    ["ai_delivery_runs", "repository_id"],
    ["ai_delivery_runs", "triggered_by_id"],
    ["ai_deploy_runs", "campaign_id"],
    ["ai_deploy_runs", "triggered_by_id"],
    ["ai_knowledge_graph_edges", "source_document_id"],
    ["ai_knowledge_graph_nodes", "ai_skill_id"],
    ["ai_knowledge_graph_nodes", "merged_into_id"],
    ["ai_knowledge_graph_nodes", "source_document_id"],
    ["ai_parked_questions", "answered_by_id"],
    ["ai_ralph_loops", "container_instance_id"],
    ["ai_skill_conflicts", "resolved_by_id"],
    ["ai_skill_proposals", "created_skill_id"],
    ["ai_skill_proposals", "reviewed_by_id"],
    ["ai_skill_recipe_runs", "ai_agent_id"],
    ["ai_team_executions", "approval_decided_by_id"],
    ["ai_team_tasks", "delegated_from_task_id"],
    ["file_bundles", "created_by_id"],
    ["git_repositories", "devops_provider_id"],
    ["shared_prompt_templates", "created_by_id"],
  ].freeze

  def change
    FK_INDEXES.each do |table, column|
      next unless table_exists?(table)
      next unless column_exists?(table, column)

      add_index table, column, algorithm: :concurrently, if_not_exists: true
    end
  end
end
