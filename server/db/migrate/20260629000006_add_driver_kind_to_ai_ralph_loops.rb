# frozen_string_literal: true

# Delegation routing (Campaign Discovery & Delegation Control Plane, increment 4):
# a campaign's dev-loop can be driven by a Claude Code session (the dev-loop pull queue)
# OR by the platform executor (a platform agent/group/mission), interchangeably. driver_kind
# records the current driver; driver_target holds the platform target ref. NULLABLE so legacy
# (non-campaign) loops are unaffected — their drain behavior stays scheduling_mode-driven.
class AddDriverKindToAiRalphLoops < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_ralph_loops, :driver_kind, :string # claude_code|platform_agent|platform_group|platform_mission (nil = legacy)
    add_column :ai_ralph_loops, :driver_target, :jsonb, null: false, default: {} # { agent_id | group_id | mission_id }
    add_index :ai_ralph_loops, :driver_kind
  end
end
