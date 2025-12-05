# frozen_string_literal: true

class CreateAiAgentTeams < ActiveRecord::Migration[8.0]
  def change
    # ==========================================
    # AI Agent Teams - CrewAI-style orchestration
    # ==========================================
    create_table :ai_agent_teams, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true,
                   comment: 'Account that owns this team'

      t.string :name, null: false,
               comment: 'Team name (e.g., "Content Generation Crew", "Research Team")'

      t.text :description,
             comment: 'Team purpose and capabilities description'

      t.string :team_type, default: 'hierarchical', null: false,
               comment: 'Team coordination type: hierarchical, mesh, sequential, parallel'

      t.text :goal_description,
             comment: 'High-level goal the team works toward'

      t.string :coordination_strategy, default: 'manager_worker', null: false,
               comment: 'Coordination pattern: manager_worker, peer_to_peer, hybrid'

      t.jsonb :team_config, default: {}, null: false,
              comment: 'Team-specific configuration (max_iterations, timeout, etc.)'

      t.string :status, default: 'active', null: false,
              comment: 'Team status: active, inactive, archived'

      t.timestamps
    end

    # Add check constraint for team_type values
    add_check_constraint :ai_agent_teams,
                        "team_type IN ('hierarchical', 'mesh', 'sequential', 'parallel')",
                        name: 'ai_agent_teams_team_type_check'

    # Add check constraint for coordination_strategy values
    add_check_constraint :ai_agent_teams,
                        "coordination_strategy IN ('manager_worker', 'peer_to_peer', 'hybrid')",
                        name: 'ai_agent_teams_coordination_strategy_check'

    # Add check constraint for status values
    add_check_constraint :ai_agent_teams,
                        "status IN ('active', 'inactive', 'archived')",
                        name: 'ai_agent_teams_status_check'

    # Add indexes for common queries
    add_index :ai_agent_teams, [:account_id, :status]
    add_index :ai_agent_teams, :team_type

    # ==========================================
    # AI Agent Team Members - Agent roles in teams
    # ==========================================
    create_table :ai_agent_team_members, id: :uuid do |t|
      t.references :ai_agent_team, type: :uuid, null: false, foreign_key: true,
                   comment: 'Team this member belongs to'

      t.references :ai_agent, type: :uuid, null: false, foreign_key: true,
                   comment: 'Agent assigned to this team role'

      t.string :role, null: false,
               comment: 'Role in team: manager, researcher, writer, reviewer, executor'

      t.jsonb :capabilities, default: [], null: false,
              comment: 'Specific capabilities this member provides to the team'

      t.integer :priority_order, default: 0, null: false,
                comment: 'Execution priority (0 = highest, for sequential teams)'

      t.boolean :is_lead, default: false, null: false,
                comment: 'Whether this member leads/coordinates the team'

      t.jsonb :member_config, default: {}, null: false,
              comment: 'Member-specific configuration (retry_count, timeout, etc.)'

      t.timestamps
    end

    # Ensure each agent can only have one role per team
    add_index :ai_agent_team_members, [:ai_agent_team_id, :ai_agent_id],
              unique: true,
              name: 'index_team_members_on_team_and_agent'

    # Index for priority-based queries (sequential execution)
    add_index :ai_agent_team_members, [:ai_agent_team_id, :priority_order],
              name: 'index_team_members_on_team_and_priority'

    # Index for finding team leads
    add_index :ai_agent_team_members, [:ai_agent_team_id, :is_lead],
              name: 'index_team_members_on_team_and_lead'
  end
end
