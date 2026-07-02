# frozen_string_literal: true

# Governed per-task tier routing (campaign 019f2163 inc2) records a STRUCTURED
# rationale on every routing decision: complexity level/score/top signals, gate
# states, capability/empirical evidence, and the effort-first decision. The
# existing string `decision_reason` holds a human one-liner; `rationale` holds the
# machine-auditable object the escalation-governance rule requires (any tier above
# standard / above baseline MUST carry a non-empty rationale). Core table, no new
# tables — mirrors the existing jsonb columns on this table (default {}).
class AddRationaleToAiRoutingDecisions < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_routing_decisions, :rationale, :jsonb, null: false, default: {}
  end
end
