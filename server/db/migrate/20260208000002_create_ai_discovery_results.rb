# frozen_string_literal: true

class CreateAiDiscoveryResults < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_discovery_results, id: :uuid do |t|
      t.references :account, foreign_key: true, type: :uuid, index: true
      t.string :scan_id
      t.string :scan_type
      t.string :status, default: 'pending'
      t.jsonb :discovered_agents, default: []
      t.jsonb :discovered_connections, default: []
      t.jsonb :discovered_tools, default: []
      t.jsonb :recommendations, default: []
      t.integer :agents_found, default: 0
      t.integer :connections_found, default: 0
      t.integer :tools_found, default: 0
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message
      t.timestamps
    end
    add_index :ai_discovery_results, :scan_id, unique: true
    add_index :ai_discovery_results, [:account_id, :scan_type]
  end
end
