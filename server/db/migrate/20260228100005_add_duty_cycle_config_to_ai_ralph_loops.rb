# frozen_string_literal: true

class AddDutyCycleConfigToAiRalphLoops < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_ralph_loops, :duty_cycle_config, :jsonb, default: {}
  end
end
