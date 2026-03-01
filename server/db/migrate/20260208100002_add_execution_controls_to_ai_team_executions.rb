# frozen_string_literal: true

class AddExecutionControlsToAiTeamExecutions < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_team_executions, :control_signal, :string
    add_column :ai_team_executions, :redirect_instructions, :jsonb, default: {}
    add_column :ai_team_executions, :paused_at, :datetime
    add_column :ai_team_executions, :resume_count, :integer, default: 0

    add_index :ai_team_executions, :control_signal
  end
end
