# frozen_string_literal: true

class CreateAiWorkflowTemplateInstallations < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_workflow_template_installations, id: :uuid do |t|
      t.references :ai_workflow_template, null: false, foreign_key: true, type: :uuid
      t.references :ai_workflow, null: false, foreign_key: true, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :installed_by_user, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.string :installation_id, null: false, limit: 100
      t.string :template_version, null: false, limit: 50
      t.jsonb :customizations, null: false, default: {}
      t.jsonb :variable_mappings, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.boolean :auto_update, null: false, default: false
      t.datetime :last_updated_at
      t.timestamps

      t.index [ :ai_workflow_template_id, :account_id ]
      t.index [ :account_id, :installed_by_user_id ]
      t.index :installation_id, unique: true
      t.index :template_version
      t.index :last_updated_at
    end
  end
end
