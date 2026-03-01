# frozen_string_literal: true

class CreateSharedPromptTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :shared_prompt_templates, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :account_id, null: false
      t.uuid :created_by_id
      t.string :name, null: false
      t.string :slug, null: false
      t.string :category, null: false
      t.string :domain, null: false, default: "general"
      t.text :description
      t.text :content, null: false
      t.jsonb :variables, default: [], null: false
      t.jsonb :metadata, default: {}, null: false
      t.integer :version, default: 1, null: false
      t.uuid :parent_template_id
      t.boolean :is_active, default: true, null: false
      t.boolean :is_system, default: false, null: false
      t.timestamps

      t.index [ :account_id, :slug ], unique: true
      t.index [ :account_id, :category ]
      t.index [ :account_id, :domain ]
      t.index :is_system
      t.index :parent_template_id
      t.index :is_active
    end

    add_foreign_key :shared_prompt_templates, :accounts, on_delete: :cascade
    add_foreign_key :shared_prompt_templates, :users, column: :created_by_id, on_delete: :nullify
    add_foreign_key :shared_prompt_templates, :shared_prompt_templates, column: :parent_template_id, on_delete: :nullify
  end
end
