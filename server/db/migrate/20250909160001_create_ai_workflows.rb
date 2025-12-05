# frozen_string_literal: true

class CreateAiWorkflows < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_workflows, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :creator, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.string :name, null: false, limit: 255
      t.string :slug, null: false, limit: 150
      t.text :description
      t.string :status, null: false, default: 'draft'
      t.string :visibility, null: false, default: 'private'
      t.jsonb :configuration, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.boolean :is_template, null: false, default: false
      t.string :template_category, limit: 100
      t.integer :version, null: false, default: 1
      t.datetime :published_at
      t.datetime :last_executed_at
      t.integer :execution_count, null: false, default: 0
      t.timestamps

      t.index [:account_id, :slug], unique: true, name: 'index_ai_workflows_on_account_slug'
      t.index [:account_id, :status]
      t.index [:is_template, :template_category]
      t.index :last_executed_at
      t.index :published_at
    end

    add_check_constraint :ai_workflows, 
      "status IN ('draft', 'published', 'archived', 'paused')",
      name: 'ai_workflows_status_check'

    add_check_constraint :ai_workflows,
      "visibility IN ('private', 'account', 'public')",
      name: 'ai_workflows_visibility_check'

    add_check_constraint :ai_workflows,
      "template_category IS NULL OR template_category != ''",
      name: 'ai_workflows_template_category_check'
  end
end