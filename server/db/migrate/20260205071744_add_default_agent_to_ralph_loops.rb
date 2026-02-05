# frozen_string_literal: true

class AddDefaultAgentToRalphLoops < ActiveRecord::Migration[8.0]
  def change
    add_reference :ai_ralph_loops, :default_agent, type: :uuid,
                  foreign_key: { to_table: :ai_agents, on_delete: :nullify },
                  index: true

    # Make ai_tool nullable — execution now routes through agents
    change_column_null :ai_ralph_loops, :ai_tool, true
    change_column_default :ai_ralph_loops, :ai_tool, from: "claude_code", to: nil

    # Remove CHECK constraint that limits ai_tool values
    execute <<~SQL
      ALTER TABLE ai_ralph_loops DROP CONSTRAINT IF EXISTS chk_ralph_loop_ai_tool;
    SQL
  end
end
