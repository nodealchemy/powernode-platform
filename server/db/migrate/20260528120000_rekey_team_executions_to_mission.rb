# frozen_string_literal: true

# Re-key team-execution tracking onto Ai::Mission.
#
# The legacy `workflow_run_id` was a FK to the removed Ai::WorkflowRun model
# (the AI workflow-orchestration subsystem was torn down). Execution tracking
# now keys off Ai::Mission — the platform's live execution-tracking spine —
# matching Ai::RunnerDispatch, Ai::RalphLoop, and the code-factory models which
# already reference missions via `mission_id`.
class RekeyTeamExecutionsToMission < ActiveRecord::Migration[8.0]
  def change
    remove_column :ai_team_executions, :workflow_run_id, :uuid
    add_reference :ai_team_executions, :mission, type: :uuid, index: true,
                  foreign_key: { to_table: :ai_missions }
  end
end
