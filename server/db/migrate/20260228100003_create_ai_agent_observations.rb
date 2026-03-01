# frozen_string_literal: true

class CreateAiAgentObservations < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_agent_observations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :ai_agent, type: :uuid, null: false, foreign_key: true, index: true
      t.references :goal, type: :uuid, foreign_key: { to_table: :ai_agent_goals }
      t.string :sensor_type, null: false
      t.string :observation_type, null: false
      t.string :severity, null: false, default: "info"
      t.string :title, null: false
      t.jsonb :data, default: {}
      t.boolean :requires_action, default: false, null: false
      t.boolean :processed, default: false, null: false
      t.datetime :expires_at

      t.timestamps
    end

    add_index :ai_agent_observations, [:ai_agent_id, :processed]
    add_index :ai_agent_observations, [:ai_agent_id, :sensor_type]
    add_index :ai_agent_observations, [:account_id, :severity]
    add_index :ai_agent_observations, :expires_at, where: "expires_at IS NOT NULL"
  end
end
