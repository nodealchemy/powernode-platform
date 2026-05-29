# frozen_string_literal: true

# Re-key RAG-query execution tracking onto Ai::Mission.
#
# The legacy `workflow_run_id` was a FK to the removed Ai::WorkflowRun model.
# A RAG query issued during a mission now keys off Ai::Mission — the platform's
# live execution-tracking spine — alongside the existing `agent_execution_id`.
class RekeyRagQueriesToMission < ActiveRecord::Migration[8.0]
  def change
    remove_column :ai_rag_queries, :workflow_run_id, :uuid
    add_reference :ai_rag_queries, :mission, type: :uuid, index: true,
                  foreign_key: { to_table: :ai_missions }
  end
end
