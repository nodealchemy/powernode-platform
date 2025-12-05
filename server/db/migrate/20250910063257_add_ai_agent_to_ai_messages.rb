# frozen_string_literal: true

class AddAiAgentToAiMessages < ActiveRecord::Migration[8.0]
  def change
    add_reference :ai_messages, :ai_agent, null: false, foreign_key: true, type: :uuid
  end
end
