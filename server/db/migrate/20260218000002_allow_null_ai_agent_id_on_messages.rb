# frozen_string_literal: true

class AllowNullAiAgentIdOnMessages < ActiveRecord::Migration[8.0]
  def change
    change_column_null :ai_messages, :ai_agent_id, true
  end
end
