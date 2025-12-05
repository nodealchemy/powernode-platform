# frozen_string_literal: true

class CreateAiMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_messages, id: :uuid do |t|
      t.uuid :ai_conversation_id, null: false
      t.uuid :user_id
      t.string :message_id, null: false, limit: 100
      t.string :role, null: false, limit: 20
      t.text :content, null: false
      t.jsonb :content_metadata, default: {}
      t.string :message_type, default: 'text', limit: 50
      t.jsonb :attachments, default: []
      t.integer :token_count, default: 0
      t.decimal :cost_usd, precision: 8, scale: 4, default: 0
      t.jsonb :processing_metadata, default: {}
      t.string :status, default: 'sent', limit: 20
      t.text :error_message
      t.timestamp :processed_at
      t.integer :sequence_number
      t.uuid :parent_message_id
      t.boolean :is_edited, default: false
      t.timestamp :edited_at
      t.jsonb :edit_history, default: []
      t.timestamps

      t.index :ai_conversation_id
      t.index :user_id
      t.index :message_id, unique: true
      t.index :role
      t.index :message_type
      t.index :status
      t.index :sequence_number
      t.index :parent_message_id
      t.index [:ai_conversation_id, :sequence_number]
      t.index [:ai_conversation_id, :role]
      t.index :processed_at

      t.foreign_key :ai_conversations, on_delete: :cascade
      t.foreign_key :users, on_delete: :nullify
      t.foreign_key :ai_messages, column: :parent_message_id, on_delete: :nullify
    end

    add_index :ai_messages, :attachments, using: 'gin'
    add_index :ai_messages, :edit_history, using: 'gin'
  end
end