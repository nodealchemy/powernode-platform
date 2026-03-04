# frozen_string_literal: true

class CreateAiSkillCompositions < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_skill_compositions, id: :uuid do |t|
      t.references :composite_skill, type: :uuid, null: false, foreign_key: { to_table: :ai_skills }
      t.references :component_skill, type: :uuid, null: false, foreign_key: { to_table: :ai_skills }

      t.integer :execution_order, null: false
      t.string :composition_type, null: false, default: "sequential"
      t.jsonb :condition, default: {}
      t.jsonb :input_mapping, default: {}
      t.jsonb :output_mapping, default: {}

      t.timestamps
    end

    add_index :ai_skill_compositions, [:composite_skill_id, :execution_order],
              unique: true, name: "idx_skill_compositions_order"
    # component_skill_id index already created by t.references above

    add_column :ai_skills, :is_composite, :boolean, default: false, null: false
  end
end
