# frozen_string_literal: true

class CreateAiWorkflowTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_workflow_templates, id: :uuid do |t|
      t.string :name, null: false, limit: 255
      t.string :slug, null: false, limit: 150
      t.text :description, null: false
      t.text :long_description
      t.string :category, null: false, limit: 100
      t.string :difficulty_level, null: false, default: 'beginner'
      t.jsonb :workflow_definition, null: false
      t.jsonb :default_variables, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.jsonb :tags, null: false, default: []
      t.string :author_name, limit: 255
      t.string :author_email, limit: 255
      t.string :author_url, limit: 500
      t.string :license, limit: 100, default: 'MIT'
      t.string :version, null: false, default: '1.0.0'
      t.integer :usage_count, null: false, default: 0
      t.decimal :rating, precision: 3, scale: 2, default: 0.0
      t.integer :rating_count, null: false, default: 0
      t.boolean :is_featured, null: false, default: false
      t.boolean :is_public, null: false, default: false
      t.datetime :published_at
      t.timestamps

      t.index :slug, unique: true
      t.index [:category, :is_public]
      t.index [:is_featured, :is_public]
      t.index :difficulty_level
      t.index :usage_count
      t.index :rating
      t.index :published_at
    end

    add_check_constraint :ai_workflow_templates,
      "difficulty_level IN ('beginner', 'intermediate', 'advanced', 'expert')",
      name: 'ai_workflow_templates_difficulty_check'

    add_check_constraint :ai_workflow_templates,
      "usage_count >= 0",
      name: 'ai_workflow_templates_usage_count_check'

    add_check_constraint :ai_workflow_templates,
      "rating >= 0 AND rating <= 5",
      name: 'ai_workflow_templates_rating_check'

    add_check_constraint :ai_workflow_templates,
      "rating_count >= 0",
      name: 'ai_workflow_templates_rating_count_check'
  end
end