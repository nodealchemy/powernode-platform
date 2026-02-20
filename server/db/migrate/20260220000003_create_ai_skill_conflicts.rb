# frozen_string_literal: true

class CreateAiSkillConflicts < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_skill_conflicts, id: :uuid do |t|
      t.references :account, type: :uuid, foreign_key: true, null: false
      t.string :conflict_type, null: false
      t.string :severity, null: false
      t.string :status, default: 'detected', null: false

      t.references :skill_a, type: :uuid, foreign_key: { to_table: :ai_skills }, null: false
      t.references :skill_b, type: :uuid, foreign_key: { to_table: :ai_skills }, null: true
      t.uuid :node_a_id
      t.uuid :node_b_id
      t.uuid :edge_id

      t.float :similarity_score
      t.float :priority_score
      t.string :resolution_strategy
      t.jsonb :resolution_details, default: {}

      t.boolean :auto_resolvable, default: false
      t.datetime :detected_at
      t.datetime :resolved_at
      t.references :resolved_by, type: :uuid, foreign_key: { to_table: :users }, null: true, index: false

      t.timestamps
    end

    add_index :ai_skill_conflicts, [:skill_a_id, :skill_b_id, :conflict_type],
              unique: true,
              where: "status NOT IN ('resolved', 'dismissed')",
              name: "idx_skill_conflicts_unique_active"
  end
end
