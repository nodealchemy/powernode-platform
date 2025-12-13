# frozen_string_literal: true

class CreateAiAgents < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_agents, id: :uuid do |t|
      t.uuid :account_id, null: false
      t.uuid :creator_id, null: false
      t.string :name, null: false, limit: 255
      t.string :slug, null: false, limit: 150
      t.text :description
      t.string :agent_type, null: false, limit: 50
      t.string :status, null: false, default: 'active'
      t.jsonb :configuration, null: false, default: {}
      t.jsonb :capabilities, null: false, default: []
      t.jsonb :metadata, null: false, default: {}
      t.boolean :is_public, default: false
      t.integer :version, default: 1
      t.timestamp :last_executed_at
      t.jsonb :execution_stats, default: {}
      t.timestamps

      t.index :account_id
      t.index :creator_id
      t.index :slug, unique: true
      t.index [ :account_id, :name ]
      t.index :agent_type
      t.index :status
      t.index :is_public
      t.index :last_executed_at

      t.foreign_key :accounts, on_delete: :cascade
      t.foreign_key :users, column: :creator_id, on_delete: :restrict
    end
  end
end
