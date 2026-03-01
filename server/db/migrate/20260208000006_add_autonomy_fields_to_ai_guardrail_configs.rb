# frozen_string_literal: true

class AddAutonomyFieldsToAiGuardrailConfigs < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_guardrail_configs, :max_agents_per_team, :integer, default: 20
    add_column :ai_guardrail_configs, :allow_agent_creation, :boolean, default: false
    add_column :ai_guardrail_configs, :allow_cross_team_ops, :boolean, default: false
    add_column :ai_guardrail_configs, :require_human_approval, :boolean, default: true
    add_column :ai_guardrail_configs, :autonomy_level, :string, default: 'supervised'
    add_column :ai_guardrail_configs, :resource_limits, :jsonb, default: {}
  end
end
