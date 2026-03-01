# frozen_string_literal: true

class CreateAiAgentSkills < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_agent_skills, id: :uuid do |t|
      t.references :ai_agent, type: :uuid, foreign_key: true, null: false, index: true
      t.references :ai_skill, type: :uuid, foreign_key: true, null: false, index: true
      t.integer :priority, default: 0
      t.boolean :is_active, default: true, null: false
      t.timestamps
    end

    add_index :ai_agent_skills, [:ai_agent_id, :ai_skill_id], unique: true
  end
end
