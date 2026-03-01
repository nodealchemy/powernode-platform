# frozen_string_literal: true

class AddConversationProfileToAiAgents < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_agents, :conversation_profile, :jsonb, default: {}, null: false
  end
end
