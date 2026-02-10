# frozen_string_literal: true

class AddFinopsColumnsToAiRoutingDecisions < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_routing_decisions, :model_tier, :string
    add_reference :ai_routing_decisions, :complexity_assessment,
                  type: :uuid,
                  null: true,
                  foreign_key: { to_table: :ai_task_complexity_assessments },
                  index: true
    add_column :ai_routing_decisions, :was_cached, :boolean, default: false
    add_column :ai_routing_decisions, :was_compressed, :boolean, default: false
    add_column :ai_routing_decisions, :cached_tokens, :integer, default: 0
  end
end
