# frozen_string_literal: true

class AddConciergeFlagToAiAgents < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_agents, :is_concierge, :boolean, default: false, null: false
    add_index :ai_agents, [:account_id, :is_concierge], where: "is_concierge = true", name: "idx_ai_agents_concierge"
  end
end
