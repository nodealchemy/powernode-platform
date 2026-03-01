# frozen_string_literal: true

class AddTeamConversationSupport < ActiveRecord::Migration[8.0]
  def up
    # Add conversation_type and agent_team_id to ai_conversations
    add_column :ai_conversations, :conversation_type, :string, default: "agent", null: false
    add_reference :ai_conversations, :agent_team, type: :uuid,
                  foreign_key: { to_table: :ai_agent_teams }, index: true

    # Partial index for team conversations
    add_index :ai_conversations, [:agent_team_id, :conversation_type],
              name: "index_ai_conversations_on_team_type",
              where: "conversation_type = 'team'"

    # Add conversation reference to ai_team_executions
    add_reference :ai_team_executions, :ai_conversation, type: :uuid,
                  foreign_key: { to_table: :ai_conversations }, index: true

    # Drop existing CHECK constraint and recreate with awaiting_approval
    remove_check_constraint :ai_team_executions, name: "check_team_execution_status"
    add_check_constraint :ai_team_executions,
      "status IN ('pending', 'running', 'paused', 'completed', 'failed', 'cancelled', 'timeout', 'awaiting_approval')",
      name: "check_team_execution_status"
  end

  def down
    remove_check_constraint :ai_team_executions, name: "check_team_execution_status"
    add_check_constraint :ai_team_executions,
      "status IN ('pending', 'running', 'paused', 'completed', 'failed', 'cancelled', 'timeout')",
      name: "check_team_execution_status"

    remove_reference :ai_team_executions, :ai_conversation
    remove_index :ai_conversations, name: "index_ai_conversations_on_team_type"
    remove_reference :ai_conversations, :agent_team
    remove_column :ai_conversations, :conversation_type
  end
end
