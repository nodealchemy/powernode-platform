# frozen_string_literal: true

class CreateAiEncryptedMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_encrypted_messages, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.uuid :from_agent_id, null: false
      t.uuid :to_agent_id, null: false
      t.uuid :task_id
      t.binary :nonce, null: false
      t.binary :ciphertext, null: false
      t.binary :auth_tag, null: false
      t.text :aad
      t.text :signature
      t.text :ephemeral_public_key
      t.integer :sequence_number, null: false
      t.string :session_id
      t.string :status, default: "delivered"
      t.timestamps
    end

    add_index :ai_encrypted_messages, :from_agent_id
    add_index :ai_encrypted_messages, :to_agent_id
    add_index :ai_encrypted_messages, :session_id
    add_index :ai_encrypted_messages, [:session_id, :sequence_number], unique: true
  end
end
