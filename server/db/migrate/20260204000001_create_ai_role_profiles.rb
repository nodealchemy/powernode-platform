# frozen_string_literal: true

class CreateAiRoleProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_role_profiles, id: :uuid do |t|
      t.references :account, foreign_key: true, type: :uuid, index: true
      t.string :name, null: false
      t.string :slug, null: false
      t.string :role_type, null: false
      t.text :description
      t.text :system_prompt_template
      t.jsonb :communication_style, default: {}
      t.jsonb :expected_output_schema, default: {}
      t.jsonb :review_criteria, default: []
      t.jsonb :quality_checks, default: []
      t.jsonb :delegation_rules, default: {}
      t.jsonb :escalation_rules, default: {}
      t.boolean :is_system, null: false, default: false
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :ai_role_profiles, :slug, unique: true
    add_index :ai_role_profiles, :is_system
  end
end
