# frozen_string_literal: true

class CreateAiAgentConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_agent_connections, id: :uuid do |t|
      t.references :account, foreign_key: true, type: :uuid, index: true
      t.string :connection_type
      t.string :source_type
      t.uuid :source_id
      t.string :target_type
      t.uuid :target_id
      t.string :status, default: 'active'
      t.float :strength, default: 1.0
      t.jsonb :metadata, default: {}
      t.string :discovered_by
      t.timestamps
    end
    add_index :ai_agent_connections, [:source_type, :source_id]
    add_index :ai_agent_connections, [:target_type, :target_id]
    add_index :ai_agent_connections, [:account_id, :connection_type]
  end
end
