# frozen_string_literal: true

class CreateAiSkillUsageRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_skill_usage_records, id: :uuid do |t|
      t.references :account, type: :uuid, foreign_key: true, null: false
      t.references :ai_skill, type: :uuid, foreign_key: true, null: false, index: false
      t.references :ai_agent, type: :uuid, foreign_key: true, null: true, index: false

      t.uuid :execution_id
      t.string :execution_type
      t.string :outcome, null: false
      t.integer :duration_ms
      t.float :confidence_delta
      t.text :context_summary
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :ai_skill_usage_records, [:ai_skill_id, :outcome]
    add_index :ai_skill_usage_records, [:ai_agent_id, :created_at]
    add_index :ai_skill_usage_records, :created_at
  end
end
