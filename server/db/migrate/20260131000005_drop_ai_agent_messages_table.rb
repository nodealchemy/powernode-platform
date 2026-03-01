# frozen_string_literal: true

# Drop legacy AgentMessage table - replaced by A2A tasks (Ai::A2aTask)
class DropAiAgentMessagesTable < ActiveRecord::Migration[7.2]
  def up
    drop_table :ai_agent_messages, if_exists: true
  end

  def down
    create_table :ai_agent_messages, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :ai_workflow_run, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :message_id, null: false
      t.uuid :from_agent_id, null: false
      t.uuid :to_agent_id
      t.string :message_type, null: false
      t.string :communication_pattern, null: false, default: "request_response"
      t.jsonb :message_content, null: false, default: {}
      t.string :status, null: false, default: "sent"
      t.jsonb :metadata, default: {}
      t.string :in_reply_to_message_id
      t.datetime :delivered_at
      t.datetime :acknowledged_at
      t.integer :sequence_number, null: false, default: 0
      t.timestamps
    end

    add_index :ai_agent_messages, :ai_workflow_run_id
    add_index :ai_agent_messages, :message_id, unique: true
    add_index :ai_agent_messages, %i[from_agent_id to_agent_id]
    add_index :ai_agent_messages, :message_type
    add_index :ai_agent_messages, :status
    add_index :ai_agent_messages, :in_reply_to_message_id
  end
end
