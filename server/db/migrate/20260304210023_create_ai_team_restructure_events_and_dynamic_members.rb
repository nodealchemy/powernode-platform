# frozen_string_literal: true

class CreateAiTeamRestructureEventsAndDynamicMembers < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_team_restructure_events, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :ai_agent_team, type: :uuid, null: false, foreign_key: { to_table: :ai_agent_teams }
      t.references :ai_agent, type: :uuid, foreign_key: { to_table: :ai_agents }

      t.string :event_type, null: false
      t.jsonb :previous_state, default: {}
      t.jsonb :new_state, default: {}
      t.jsonb :rationale, default: {}
      t.jsonb :metrics_snapshot, default: {}

      t.timestamps
    end

    add_index :ai_team_restructure_events, [:ai_agent_team_id, :event_type], name: "idx_restructure_events_team_type"

    # Add dynamic member fields to existing agent_team_members
    add_column :ai_agent_team_members, :recruited_at, :datetime
    add_column :ai_agent_team_members, :released_at, :datetime
    add_column :ai_agent_team_members, :is_dynamic, :boolean, default: false, null: false
  end
end
