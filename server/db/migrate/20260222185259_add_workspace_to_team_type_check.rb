# frozen_string_literal: true

class AddWorkspaceToTeamTypeCheck < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE ai_agent_teams
        DROP CONSTRAINT ai_agent_teams_team_type_check,
        ADD CONSTRAINT ai_agent_teams_team_type_check
          CHECK (team_type IN ('hierarchical', 'mesh', 'sequential', 'parallel', 'workspace'))
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE ai_agent_teams
        DROP CONSTRAINT ai_agent_teams_team_type_check,
        ADD CONSTRAINT ai_agent_teams_team_type_check
          CHECK (team_type IN ('hierarchical', 'mesh', 'sequential', 'parallel'))
    SQL
  end
end
