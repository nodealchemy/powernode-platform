# frozen_string_literal: true

class CreateAiTemplateInstallations < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_template_installations, id: :uuid do |t|
      t.uuid :ai_agent_template_id, null: false
      t.uuid :account_id, null: false
      t.uuid :user_id, null: false
      t.uuid :ai_agent_id
      t.string :installation_status, null: false, default: 'pending'
      t.jsonb :custom_config, default: {}
      t.jsonb :installation_metadata, default: {}
      t.text :installation_notes
      t.timestamp :installed_at
      t.timestamp :last_used_at
      t.integer :usage_count, default: 0
      t.timestamps

      t.index :ai_agent_template_id
      t.index :account_id
      t.index :user_id
      t.index :ai_agent_id
      t.index :installation_status
      t.index [ :account_id, :ai_agent_template_id ], unique: true
      t.index :installed_at
      t.index :last_used_at

      t.foreign_key :ai_agent_templates, on_delete: :cascade
      t.foreign_key :accounts, on_delete: :cascade
      t.foreign_key :users, on_delete: :restrict
      t.foreign_key :ai_agents, on_delete: :cascade
    end
  end
end
