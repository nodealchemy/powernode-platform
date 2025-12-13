# frozen_string_literal: true

class CreateAiAgentMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_agent_messages, id: :uuid do |t|
      t.uuid :ai_workflow_run_id, null: false
      t.string :message_id, null: false
      t.string :from_agent_id, null: false
      t.string :to_agent_id
      t.string :message_type, null: false, default: 'direct'
      t.string :communication_pattern, null: false, default: 'request_response'
      t.jsonb :message_content, null: false, default: {}
      t.jsonb :metadata, default: {}
      t.string :status, null: false, default: 'sent'
      t.string :in_reply_to_message_id
      t.integer :sequence_number, null: false
      t.timestamp :delivered_at
      t.timestamp :acknowledged_at

      t.timestamps
    end

    add_index :ai_agent_messages, :ai_workflow_run_id
    add_index :ai_agent_messages, :message_id, unique: true
    add_index :ai_agent_messages, :from_agent_id
    add_index :ai_agent_messages, :to_agent_id
    add_index :ai_agent_messages, :message_type
    add_index :ai_agent_messages, :status
    add_index :ai_agent_messages, :in_reply_to_message_id
    add_index :ai_agent_messages, [ :ai_workflow_run_id, :sequence_number ], name: 'index_agent_messages_on_run_and_sequence'
    add_index :ai_agent_messages, [ :from_agent_id, :to_agent_id ], name: 'index_agent_messages_on_sender_receiver'

    add_foreign_key :ai_agent_messages, :ai_workflow_runs, on_delete: :cascade
  end
end
