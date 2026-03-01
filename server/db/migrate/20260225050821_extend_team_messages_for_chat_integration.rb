# frozen_string_literal: true

class ExtendTeamMessagesForChatIntegration < ActiveRecord::Migration[8.0]
  def change
    # Allow team messages without an execution context (e.g., user-sent from chat UI)
    change_column_null :ai_team_messages, :team_execution_id, true

    # Track which user sent a human_input message
    add_reference :ai_team_messages, :user, type: :uuid, foreign_key: true, null: true
  end
end
