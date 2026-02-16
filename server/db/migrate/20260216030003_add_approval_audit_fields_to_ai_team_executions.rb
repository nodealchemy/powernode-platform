# frozen_string_literal: true

class AddApprovalAuditFieldsToAiTeamExecutions < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_team_executions, :approval_decision, :string
    add_column :ai_team_executions, :approval_decided_by_id, :uuid
    add_column :ai_team_executions, :approval_decided_at, :datetime
    add_column :ai_team_executions, :approval_feedback, :text

    add_foreign_key :ai_team_executions, :users, column: :approval_decided_by_id
  end
end
