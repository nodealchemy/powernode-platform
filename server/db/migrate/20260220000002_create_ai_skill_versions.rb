# frozen_string_literal: true

class CreateAiSkillVersions < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_skill_versions, id: :uuid do |t|
      t.references :account, type: :uuid, foreign_key: true, null: false
      t.references :ai_skill, type: :uuid, foreign_key: true, null: false
      t.references :created_by_agent, type: :uuid, foreign_key: { to_table: :ai_agents }, null: true
      t.references :created_by_user, type: :uuid, foreign_key: { to_table: :users }, null: true

      t.string :version, null: false
      t.text :system_prompt
      t.jsonb :commands, default: []
      t.jsonb :tags, default: []
      t.jsonb :metadata, default: {}

      t.float :effectiveness_score, default: 0.5
      t.integer :usage_count, default: 0
      t.integer :success_count, default: 0
      t.integer :failure_count, default: 0

      t.text :change_reason
      t.string :change_type, default: 'manual'

      t.boolean :is_active, default: false
      t.boolean :is_ab_variant, default: false
      t.float :ab_traffic_pct, default: 0.0

      t.timestamps
    end

    add_index :ai_skill_versions, [:ai_skill_id, :version], unique: true
  end
end
