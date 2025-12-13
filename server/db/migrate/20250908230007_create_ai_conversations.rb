# frozen_string_literal: true

class CreateAiConversations < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_conversations, id: :uuid do |t|
      t.uuid :account_id, null: false
      t.uuid :user_id, null: false
      t.uuid :ai_agent_id
      t.uuid :ai_provider_id, null: false
      t.string :conversation_id, null: false, limit: 100
      t.string :title, limit: 255
      t.text :summary
      t.string :status, null: false, default: 'active'
      t.jsonb :conversation_context, default: {}
      t.jsonb :metadata, default: {}
      t.integer :message_count, default: 0
      t.integer :total_tokens, default: 0
      t.decimal :total_cost, precision: 10, scale: 4, default: 0
      t.timestamp :last_activity_at
      t.uuid :websocket_session_id
      t.string :websocket_channel
      t.boolean :is_collaborative, default: false
      t.jsonb :participants, default: []
      t.timestamps

      t.index :account_id
      t.index :user_id
      t.index :ai_agent_id
      t.index :ai_provider_id
      t.index :conversation_id, unique: true
      t.index :status
      t.index :last_activity_at
      t.index :websocket_session_id
      t.index :websocket_channel
      t.index [ :account_id, :status ]
      t.index [ :user_id, :status ]

      t.foreign_key :accounts, on_delete: :cascade
      t.foreign_key :users, on_delete: :restrict
      t.foreign_key :ai_agents, on_delete: :nullify
      t.foreign_key :ai_providers, on_delete: :restrict
    end

    add_index :ai_conversations, :participants, using: 'gin'
  end
end
