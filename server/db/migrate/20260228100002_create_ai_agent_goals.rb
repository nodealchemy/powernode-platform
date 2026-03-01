# frozen_string_literal: true

class CreateAiAgentGoals < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_agent_goals, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :ai_agent, type: :uuid, null: false, foreign_key: true, index: true
      t.references :parent_goal, type: :uuid, foreign_key: { to_table: :ai_agent_goals }
      t.string :created_by_type
      t.uuid :created_by_id
      t.string :title, null: false, limit: 255
      t.text :description
      t.string :goal_type, null: false
      t.integer :priority, null: false, default: 3
      t.string :status, null: false, default: "pending"
      t.jsonb :success_criteria, default: {}
      t.decimal :progress, precision: 3, scale: 2, default: 0.0
      t.datetime :deadline
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :ai_agent_goals, [:ai_agent_id, :status]
    add_index :ai_agent_goals, [:account_id, :goal_type]
    add_index :ai_agent_goals, [:created_by_type, :created_by_id]
    add_index :ai_agent_goals, [:ai_agent_id, :status, :priority],
              name: "idx_ai_agent_goals_active_priority"
  end
end
