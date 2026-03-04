# frozen_string_literal: true

class AddGovernanceFieldsToAiAgents < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_agents, :is_governance, :boolean, default: false, null: false
    add_column :ai_agents, :governance_scope, :jsonb, default: {}

    add_index :ai_agents, :is_governance, where: "is_governance = true", name: "idx_ai_agents_governance"
  end
end
