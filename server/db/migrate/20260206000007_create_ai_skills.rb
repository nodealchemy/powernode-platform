# frozen_string_literal: true

class CreateAiSkills < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_skills, id: :uuid do |t|
      t.references :account, type: :uuid, foreign_key: true, index: true, null: true
      t.references :ai_knowledge_base, type: :uuid, foreign_key: true, index: true, null: true
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :category, null: false
      t.string :status, default: "active"
      t.text :system_prompt
      t.jsonb :commands, default: []
      t.jsonb :activation_rules, default: {}
      t.jsonb :metadata, default: {}
      t.jsonb :tags, default: []
      t.boolean :is_system, default: false, null: false
      t.boolean :is_enabled, default: true, null: false
      t.string :version, default: "1.0.0"
      t.integer :usage_count, default: 0, null: false
      t.timestamps
    end

    add_index :ai_skills, :slug, unique: true
    add_index :ai_skills, :category
    add_index :ai_skills, :status
    add_index :ai_skills, :is_system
    add_index :ai_skills, :tags, using: :gin

    create_table :ai_skill_connectors, id: :uuid do |t|
      t.references :ai_skill, type: :uuid, foreign_key: true, null: false
      t.references :mcp_server, type: :uuid, foreign_key: true, null: false
      t.string :role, default: "primary"
      t.timestamps
    end

    add_index :ai_skill_connectors, [:ai_skill_id, :mcp_server_id], unique: true
  end
end
