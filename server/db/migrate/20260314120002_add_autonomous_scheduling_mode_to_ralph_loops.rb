# frozen_string_literal: true

class AddAutonomousSchedulingModeToRalphLoops < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      ALTER TABLE ai_ralph_loops DROP CONSTRAINT IF EXISTS ai_ralph_loops_scheduling_mode_check;
      ALTER TABLE ai_ralph_loops ADD CONSTRAINT ai_ralph_loops_scheduling_mode_check
        CHECK (scheduling_mode IN ('manual', 'scheduled', 'continuous', 'event_triggered', 'autonomous'));
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE ai_ralph_loops DROP CONSTRAINT IF EXISTS ai_ralph_loops_scheduling_mode_check;
      ALTER TABLE ai_ralph_loops ADD CONSTRAINT ai_ralph_loops_scheduling_mode_check
        CHECK (scheduling_mode IN ('manual', 'scheduled', 'continuous', 'event_triggered'));
    SQL
  end
end
