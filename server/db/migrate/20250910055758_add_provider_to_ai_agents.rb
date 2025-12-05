# frozen_string_literal: true

class AddProviderToAiAgents < ActiveRecord::Migration[8.0]
  def change
    add_reference :ai_agents, :ai_provider, null: false, foreign_key: true, type: :uuid
  end
end
